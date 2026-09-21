/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the conditions in the LICENSE file.
 */

import BrevCalendar
import Foundation

/// Browsing model behind the Calendar surface (ADR-0072).
///
/// Reads the synced cache only — `load()` never issues provider requests,
/// so an offline launch renders the last complete snapshot. Provider
/// traffic happens solely inside `syncNow`, which the user triggers
/// explicitly. One unreadable source cache never blanks the others; the
/// failure surfaces inline while healthy sources keep rendering.
@Observable
@MainActor
public final class CalendarBrowsingModel {
    /// One day bucket in the agenda list.
    public struct DaySection: Identifiable, Hashable, Sendable {
        public let id: String
        /// Start-of-day in the display zone; nil buckets undated events.
        public let day: Date?
        public var events: [PIMEvent]

        public init(id: String, day: Date?, events: [PIMEvent]) {
            self.id = id
            self.day = day
            self.events = events
        }
    }

    /// The leading column's layout: the agenda list or one of the
    /// date-anchored grids (ADR-0072 #6).
    public enum ViewMode: String, CaseIterable, Sendable {
        case agenda
        case day
        case week
        case month

        /// The picker label for the mode.
        public var title: String {
            switch self {
            case .agenda:
                String(localized: "Agenda", bundle: .module)
            case .day:
                String(localized: "Day", bundle: .module)
            case .week:
                String(localized: "Week", bundle: .module)
            case .month:
                String(localized: "Month", bundle: .module)
            }
        }
    }

    // MARK: - State

    /// Calendar sources known to the coordinator, in coordinator order.
    public private(set) var sources: [PIMSource] = []
    /// Discovered collections per source; empty when discovery never ran.
    public private(set) var collectionsBySource:
        [PIMSource.ID: [PIMCollection]] = [:]
    /// All cached events across calendar sources, sorted by start.
    public private(set) var events: [PIMEvent] = []
    public private(set) var isLoading = false
    /// Inline error text for the last failed load or sync pass.
    public private(set) var lastError: String?
    /// Sources currently running a Sync Now pass.
    public private(set) var syncingSourceIDs: Set<PIMSource.ID> = []

    /// Local-only query over the cached event fields.
    public var searchText = ""
    /// Selection shared between the agenda and the detail pane.
    public var selectedEventID: PIMEvent.ID?
    /// The active layout for the leading column.
    public var viewMode: ViewMode = .agenda
    /// The anchor date the day/week/month grids navigate around.
    /// Always a start-of-day in the display zone.
    public private(set) var selectedDay: Date
    /// One-line notice when a brev://event deep link names a record
    /// that is no longer in the cache (#10).
    public private(set) var deepLinkNotice: String?

    private let coordinator: PIMSourceCoordinator?
    private let collectionService: PIMCollectionService?
    private let eventSyncService: PIMEventSyncService?
    private let now: () -> Date
    private let calendar: Calendar
    /// Whether load() finished at least once — deep links ensure the
    /// cache is loaded before they reveal so a cold window cannot
    /// report a miss on data it never read.
    private var didLoad = false

    /// - Parameters:
    ///   - coordinator: Source registry; nil in sessions without PIM.
    ///   - collectionService: Collection cache for visibility + colors.
    ///   - eventSyncService: Event cache and Sync Now owner.
    ///   - now: Clock, injected for tests.
    ///   - calendar: Day-boundary calendar, injected for tests.
    public init(
        coordinator: PIMSourceCoordinator? = nil,
        collectionService: PIMCollectionService? = nil,
        eventSyncService: PIMEventSyncService? = nil,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.coordinator = coordinator
        self.collectionService = collectionService
        self.eventSyncService = eventSyncService
        self.now = now
        self.calendar = calendar
        selectedDay = calendar.startOfDay(for: now())
    }

    // MARK: - Derived state

    /// Events the agenda shows: hidden collections excluded, search
    /// applied, sorted by start. An event whose collection has no
    /// discovery record still shows — it was synced while visible.
    public var visibleEvents: [PIMEvent] {
        let hiddenCollectionIDs = Set(
            collectionsBySource.values.flatMap { $0 }
                .filter { !$0.isVisible }
                .map(\.id)
        )
        return events.filter {
            !hiddenCollectionIDs.contains($0.collectionID)
                && CalendarEventPresentation.matches($0, query: searchText)
        }
    }

    /// Agenda sections in chronological order; undated events trail the
    /// dated sections rather than being dropped.
    public var days: [DaySection] {
        var order: [Date] = []
        var byDay: [Date: [PIMEvent]] = [:]
        var undated: [PIMEvent] = []
        for event in visibleEvents {
            if let day = CalendarEventPresentation.dayStart(
                for: event,
                calendar: calendar
            ) {
                if byDay[day] == nil { order.append(day) }
                byDay[day, default: []].append(event)
            } else {
                undated.append(event)
            }
        }
        var sections = order.sorted().map { day in
            DaySection(
                id: String(day.timeIntervalSince1970),
                day: day,
                events: byDay[day] ?? []
            )
        }
        if !undated.isEmpty {
            sections.append(
                DaySection(id: "undated", day: nil, events: undated)
            )
        }
        return sections
    }

    // MARK: - Grid navigation

    /// The events covering one day — hidden collections and the search
    /// query applied, all-day first then chronological.
    public func events(onDay day: Date) -> [PIMEvent] {
        CalendarGridLayout.events(
            visibleEvents,
            onDay: day,
            calendar: calendar
        )
    }

    /// The all-day events covering one day — the grid views pin these
    /// above the hour lanes.
    public func allDayEvents(onDay day: Date) -> [PIMEvent] {
        CalendarGridLayout.allDayEvents(
            visibleEvents,
            onDay: day,
            calendar: calendar
        )
    }

    /// Lane-placed timed events for one day — overlapping events split
    /// the column into lanes.
    public func timedLanes(
        onDay day: Date
    ) -> [CalendarGridLayout.LanePlacement] {
        CalendarGridLayout.timedLanes(
            visibleEvents,
            onDay: day,
            calendar: calendar
        )
    }

    /// The seven days of the selected day\u2019s week.
    public var selectedWeekDays: [Date] {
        CalendarGridLayout.weekDays(
            containing: selectedDay,
            calendar: calendar
        )
    }

    /// The selected day\u2019s month grid, shaped as weeks of seven.
    public var selectedMonthWeeks: [[CalendarGridLayout.MonthDay]] {
        CalendarGridLayout.monthWeeks(
            containing: selectedDay,
            calendar: calendar
        )
    }

    /// The toolbar title for the active grid mode.
    public var rangeTitle: String {
        switch viewMode {
        case .agenda:
            String(localized: "Agenda", bundle: .module)
        case .day:
            CalendarGridLayout.dayTitle(
                for: selectedDay,
                calendar: calendar
            )
        case .week:
            CalendarGridLayout.weekTitle(
                containing: selectedDay,
                calendar: calendar
            )
        case .month:
            CalendarGridLayout.monthTitle(
                containing: selectedDay,
                calendar: calendar
            )
        }
    }

    /// Whether the previous/next/today controls apply to the active
    /// mode — the agenda has no date anchor, so they hide there.
    public var showsDateNavigation: Bool {
        viewMode != .agenda
    }

    /// Steps the anchor one day, week, or month back per the active mode.
    public func goToPrevious() {
        move(by: -1)
    }

    /// Steps the anchor one day, week, or month forward per the mode.
    public func goToNext() {
        move(by: 1)
    }

    /// Returns the anchor to today in the display zone.
    public func goToToday() {
        selectedDay = calendar.startOfDay(for: now())
    }

    /// Moves the anchor to a specific day — a month-cell tap lands here
    /// before the view switches to the day layout.
    public func selectDay(_ day: Date) {
        selectedDay = calendar.startOfDay(for: day)
    }

    private func move(by direction: Int) {
        let component: Calendar.Component
        switch viewMode {
        case .agenda, .day:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        }
        if let next = calendar.date(
            byAdding: component,
            value: direction,
            to: selectedDay
        ) {
            selectedDay = calendar.startOfDay(for: next)
        }
    }

    /// The most recent cache write across loaded events — the "Updated"
    /// label's timestamp. Nil when the cache is empty.
    public var lastSyncAt: Date? {
        events.map(\.syncedAt).max()
    }

    /// Sources whose cached data may be stale — failed, needs
    /// reauthentication, or disconnected while the cache stays readable
    /// (ADR-0072 kept-cache contract).
    public var staleSources: [PIMSource] {
        sources.filter {
            switch $0.status {
            case .failed, .authenticationRequired, .disconnected:
                true
            case .connecting, .ready, .syncing, .permissionLimited:
                false
            }
        }
    }

    /// Whether any calendar source exists — drives the empty state that
    /// points at Settings rather than a bare "no events".
    public var hasSources: Bool {
        !sources.isEmpty
    }

    /// Whether Sync Now can run for a source in this session — the
    /// service exists and the source sits in a syncable status.
    public func canSyncNow(_ source: PIMSource) -> Bool {
        eventSyncService != nil
            && [
                PIMSourceStatus.ready, .syncing, .permissionLimited, .failed
            ].contains(source.status)
    }

    /// The cached record behind a selection, if it still exists.
    public func event(id: PIMEvent.ID?) -> PIMEvent? {
        guard let id else { return nil }
        return events.first { $0.id == id }
    }

    /// The collection a cached event belongs to, for color and
    /// provenance on rows and the detail pane.
    public func collection(for event: PIMEvent) -> PIMCollection? {
        collectionsBySource[event.sourceID]?.first {
            $0.id == event.collectionID
        }
    }

    /// The source a cached event belongs to, for provenance on detail.
    public func source(for event: PIMEvent) -> PIMSource? {
        sources.first { $0.id == event.sourceID }
    }

    // MARK: - Loading

    /// Loads sources, collections, and the cached events. Cache-only —
    /// never contacts a provider.
    public func load() async {
        isLoading = true
        defer {
            isLoading = false
            didLoad = true
        }
        do {
            sources = try await coordinator?.allSources()
                .filter { $0.kind == .calendar } ?? []
        } catch {
            lastError = error.localizedDescription
            return
        }
        await loadCollections()
        await loadEvents()
        reconcileSelection()
    }

    // MARK: - Deep links

    /// Reveals the event a brev://event link names (#10).
    ///
    /// Ensures the cache has loaded at least once, then selects the
    /// record and anchors the day grids on it. A record that left the
    /// cache — the source was disconnected with its cache cleared, or
    /// the link is stale — fails safe: the selection clears and an
    /// inline notice explains the miss instead of silently landing on
    /// an unrelated event.
    public func revealEvent(id: PIMEvent.ID) async {
        if !didLoad { await load() }
        guard let event = events.first(where: { $0.id == id }) else {
            selectedEventID = nil
            deepLinkNotice = String(
                localized:
                "That event is no longer synced. It may have been deleted or its calendar source removed.",
                bundle: .module
            )
            return
        }
        deepLinkNotice = nil
        searchText = ""
        selectedEventID = event.id
        if let day = CalendarEventPresentation.dayStart(
            for: event,
            calendar: calendar
        ) {
            selectedDay = day
        }
    }

    private func loadCollections() async {
        guard let collectionService else {
            collectionsBySource = [:]
            return
        }
        var map: [PIMSource.ID: [PIMCollection]] = [:]
        for source in sources {
            // A store read failure must not blank the source — its rows
            // render without color/visibility metadata instead.
            await map[source.id] =
                (try? collectionService.collections(for: source.id))
                    ?? []
        }
        collectionsBySource = map
    }

    private func loadEvents() async {
        guard let eventSyncService else {
            events = []
            return
        }
        var all: [PIMEvent] = []
        var failedSources: [String] = []
        for source in sources {
            do {
                try await all.append(
                    contentsOf: eventSyncService.events(
                        for: source.id
                    )
                )
            } catch {
                // One unreadable cache must not blank the others.
                failedSources.append(source.displayName)
            }
        }
        events = all.sorted {
            ($0.start ?? .distantPast) < ($1.start ?? .distantPast)
        }
        if failedSources.isEmpty {
            lastError = nil
        } else {
            lastError = String(
                localized:
                "Couldn't read the cache for \(failedSources.formatted(.list(type: .and))).",
                bundle: .module
            )
        }
    }

    // MARK: - Sync

    /// User-initiated sync for one calendar source; reloads the cache
    /// afterward so the agenda reflects the fresh snapshot.
    public func syncNow(sourceID: PIMSource.ID) async {
        guard let eventSyncService, !syncingSourceIDs.contains(sourceID)
        else { return }
        syncingSourceIDs.insert(sourceID)
        defer { syncingSourceIDs.remove(sourceID) }
        do {
            let summary = try await eventSyncService.syncNow(
                sourceID: sourceID
            )
            if let first = summary.failures.first {
                lastError = first.message
            } else {
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
        await load()
    }

    /// Whether any source can run a Sync Now pass right now.
    public var canSyncAny: Bool {
        sources.contains { canSyncNow($0) }
    }

    /// Syncs every syncable source — the toolbar's single Sync action.
    public func syncAll() async {
        for source in sources where canSyncNow(source) {
            await syncNow(sourceID: source.id)
        }
    }

    // MARK: - Selection

    /// Drops a stale selection after reloads; never auto-selects — the
    /// detail pane shows a placeholder until the user picks an event.
    private func reconcileSelection() {
        guard let selectedEventID else { return }
        if !events.contains(where: { $0.id == selectedEventID }) {
            self.selectedEventID = nil
        }
    }
}
