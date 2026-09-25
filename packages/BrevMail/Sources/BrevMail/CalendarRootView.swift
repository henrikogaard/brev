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
import BrevDesign
import BrevThemes
import SwiftUI

/// The Calendar browsing surface (ADR-0072, issue #6).
///
/// A two-column split: the leading column switches between the agenda
/// list and the day/week/month grids (all sharing selection and the
/// date anchor), and the read-only event detail sits on the trailing
/// side. On iOS the split collapses into a push navigation. All content
/// comes from the local sync cache — the view never issues provider
/// requests on its own; the only provider-adjacent actions are the
/// explicit Sync Now toolbar item and, when an editing model is wired
/// (issue #7), the New Event / Edit / Delete affordances that run
/// through CalendarEditingModel.
public struct CalendarRootView: View {
    @Environment(\.brevTheme) private var theme

    @State private var model: CalendarBrowsingModel
    /// Event authoring; nil keeps the surface read-only.
    private let editing: CalendarEditingModel?
    /// Dismisses the hosting surface (iOS presents the view in a full-screen
    /// cover); nil hides the Done affordance.
    private let onDismiss: (() -> Void)?
    @State private var columnVisibility = NavigationSplitViewVisibility
        .automatic
    /// Drives iOS push navigation onto the detail column on selection.
    @State private var preferredCompactColumn = NavigationSplitViewColumn
        .sidebar
    /// The sheet request: a new event anchored at a date, or an edit
    /// of the cached event.
    @State private var editorRequest: EditorRequest?

    /// Identifiable sheet payload for the event editor.
    private enum EditorRequest: Identifiable {
        case create(start: Date)
        case edit(PIMEvent)

        var id: String {
            switch self {
            case .create(let start):
                "create-\(start.timeIntervalSince1970)"
            case .edit(let event):
                "edit-\(event.id)"
            }
        }
    }

    /// - Parameter model: The browsing model; the app shell builds it
    ///   over the session's PIM services.
    /// - Parameter editing: The authoring model; pass nil (default) for
    ///   a read-only calendar.
    /// - Parameter onDismiss: Dismiss action for a host that presents the
    ///   view modally; nil (default) shows no Done button.
    public init(
        model: CalendarBrowsingModel,
        editing: CalendarEditingModel? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        _model = State(initialValue: model)
        self.editing = editing
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
            leadingColumn
                .navigationTitle(
                    String(localized: "Calendar", bundle: .module)
                )
        } detail: {
            detailColumn
        }
        .searchable(
            text: Bindable(model).searchText,
            prompt: String(
                localized: "Search events",
                bundle: .module
            )
        )
        .task { await model.load() }
        .task { await editing?.load() }
        .onChange(of: model.selectedEventID) { _, newValue in
            if newValue != nil {
                preferredCompactColumn = .detail
            }
        }
        .sheet(item: $editorRequest) { request in
            if let editing {
                editorSheet(for: request, editing: editing)
            }
        }
    }

    // MARK: - Leading column

    private var leadingColumn: some View {
        VStack(spacing: 0) {
            if !model.staleSources.isEmpty {
                staleBanner
            }
            if let lastError = model.lastError {
                errorBanner(lastError)
            }
            if let lastError = editing?.lastError {
                errorBanner(lastError)
            }
            if let deepLinkNotice = model.deepLinkNotice {
                errorBanner(deepLinkNotice)
            }
            if model.hasSources {
                navigationHeader
            }
            content
        }
        .toolbar { toolbarContent }
        // The calendar grid lives in this column — it needs real width on
        // macOS or day/week/month cells collapse to chips. iOS compact
        // ignores the width and stacks columns as before.
        .navigationSplitViewColumnWidth(min: 300, ideal: 460, max: 760)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading, model.events.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(
                    String(localized: "Loading events", bundle: .module)
                )
        } else if !model.hasSources {
            emptyState(
                symbol: "calendar.badge.plus",
                title: String(
                    localized: "No calendars connected",
                    bundle: .module
                ),
                message: String(
                    localized:
                    "Connect a calendar in Settings → Calendar & Contacts to see events here.",
                    bundle: .module
                )
            )
        } else if model.days.isEmpty, model.viewMode == .agenda {
            emptyState(
                symbol: "calendar",
                title: String(
                    localized: "No events",
                    bundle: .module
                ),
                message: model.searchText.isEmpty
                    ? String(
                        localized:
                        "Synced events will appear here. Use Sync Now to refresh the cache.",
                        bundle: .module
                    )
                    : String(
                        localized: "No events match your search.",
                        bundle: .module
                    )
            )
        } else {
            switch model.viewMode {
            case .agenda:
                CalendarAgendaView(
                    days: model.days,
                    collectionFor: { model.collection(for: $0) },
                    selectedEventID: Bindable(model).selectedEventID
                )
            case .day:
                CalendarDayView(
                    day: model.selectedDay,
                    allDayEvents: model.allDayEvents(
                        onDay: model.selectedDay
                    ),
                    placements: model.timedLanes(onDay: model.selectedDay),
                    collectionFor: { model.collection(for: $0) },
                    selectedEventID: Bindable(model).selectedEventID
                )
            case .week:
                CalendarWeekView(
                    days: model.selectedWeekDays,
                    allDayFor: { model.allDayEvents(onDay: $0) },
                    lanesFor: { model.timedLanes(onDay: $0) },
                    collectionFor: { model.collection(for: $0) },
                    selectedEventID: Bindable(model).selectedEventID,
                    onSelectDay: { day in
                        model.selectDay(day)
                        model.viewMode = .day
                    }
                )
            case .month:
                CalendarMonthView(
                    weeks: model.selectedMonthWeeks,
                    eventsFor: { model.events(onDay: $0) },
                    collectionFor: { model.collection(for: $0) },
                    selectedEventID: Bindable(model).selectedEventID,
                    onSelectDay: { day in
                        model.selectDay(day)
                        model.viewMode = .day
                    }
                )
            }
        }
    }

    // MARK: - Detail column

    @ViewBuilder
    private var detailColumn: some View {
        if let event = model.event(id: model.selectedEventID) {
            CalendarEventDetailView(
                event: event,
                collection: model.collection(for: event),
                source: model.source(for: event),
                onEdit: editAction(for: event),
                onDelete: deleteAction(for: event),
                isRecurring: editing?.needsScopeChoice(for: event)
                    ?? false
            )
        } else {
            ContentUnavailableView(
                String(localized: "No event selected", bundle: .module),
                systemImage: "calendar",
                description: Text(String(
                    localized: "Pick an event from the agenda.",
                    bundle: .module
                ))
            )
            .foregroundStyle(theme.textSecondary.color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bgPrimary.color)
        }
    }

    // MARK: - Banners

    /// Kept-cache warning: a failed/disconnected/auth-required source
    /// still renders its last snapshot, flagged so the data's age is
    /// never ambiguous (ADR-0072 staleness contract).
    private var staleBanner: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(String(
                    localized: "Showing cached data",
                    bundle: .module
                ))
                .brevFont(.subheadline)
                if let lastSyncAt = model.lastSyncAt {
                    Text(String(
                        localized:
                        "Last updated \(lastSyncAt.formatted(.relative(presentation: .named)))",
                        bundle: .module
                    ))
                    .brevFont(.caption)
                }
            }
            Spacer(minLength: BrevSpacing.sm)
        }
        .foregroundStyle(theme.warning.color)
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .background(theme.bgSecondary.color)
        .accessibilityElement(children: .combine)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "exclamationmark.circle")
                .accessibilityHidden(true)
            Text(message)
                .brevFont(.caption)
            Spacer(minLength: BrevSpacing.sm)
        }
        .foregroundStyle(theme.danger.color)
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .background(theme.bgSecondary.color)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Empty state + toolbar

    private func emptyState(
        symbol: String,
        title: String,
        message: String
    ) -> some View {
        ContentUnavailableView(
            title,
            systemImage: symbol,
            description: Text(message)
        )
        .foregroundStyle(theme.textSecondary.color)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgPrimary.color)
    }

    /// The Edit action for the detail pane — present only while the
    /// event's collection is writable.
    private func editAction(for event: PIMEvent) -> (() -> Void)? {
        guard let editing, editing.canEdit(event) else { return nil }
        return {
            Task { await presentEditor(for: event) }
        }
    }

    /// The Delete action for the detail pane — same writability gate.
    private func deleteAction(
        for event: PIMEvent
    ) -> ((CalendarRecurringEditScope?) -> Void)? {
        guard let editing, editing.canEdit(event) else { return nil }
        return { scope in
            Task { await delete(event, scope: scope) }
        }
    }

    /// Refreshes writable targets before presenting so the picker never
    /// offers a stale (or misses a newly enabled) calendar.
    private func presentEditor(for event: PIMEvent) async {
        await editing?.load()
        editorRequest = .edit(event)
    }

    private func presentNewEvent() async {
        await editing?.load()
        // New events anchor at 9:00 on the selected day — a sane
        // default the date pickers adjust from.
        let anchor = Calendar.current.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: model.selectedDay
        ) ?? model.selectedDay
        editorRequest = .create(start: anchor)
    }

    private func delete(
        _ event: PIMEvent,
        scope: CalendarRecurringEditScope?
    ) async {
        do {
            try await editing?.delete(event, scope: scope)
            model.selectedEventID = nil
            await model.load()
        } catch {
            // The editing model carries the displayable error.
        }
    }

    @ViewBuilder
    private func editorSheet(
        for request: EditorRequest,
        editing: CalendarEditingModel
    ) -> some View {
        let onSaved: () async -> Void = {
            await editing.load()
            await model.load()
        }
        switch request {
        case .create(let start):
            CalendarEventEditorView(
                editing: editing,
                start: start,
                onSaved: onSaved
            )
        case .edit(let event):
            CalendarEventEditorView(
                editing: editing,
                event: event,
                onSaved: onSaved
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let onDismiss {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Done", bundle: .module), action: onDismiss)
            }
        }
    }

    // MARK: - Navigation header

    /// In-view replacement for `.principal`/`.primaryAction` toolbar items:
    /// on macOS sidebar toolbars only propagate to the window titlebar when
    /// the column content is a `List`, so grid modes (ScrollView) dropped
    /// every toolbar item and the mode picker became unreachable. Rendering
    /// the controls inline keeps them visible in every mode and layout on
    /// both platforms.
    private var navigationHeader: some View {
        HStack(spacing: BrevSpacing.sm) {
            Picker(
                String(localized: "Layout", bundle: .module),
                selection: Bindable(model).viewMode
            ) {
                ForEach(
                    CalendarBrowsingModel.ViewMode.allCases,
                    id: \.self
                ) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            // Menu style stays compact at any column width — the segmented
            // variant needs ~320pt the sidebar cannot guarantee. fixedSize
            // keeps the selected-mode label ("Month") on one line where
            // narrow columns would otherwise wrap it mid-word.
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(
                String(localized: "Calendar layout", bundle: .module)
            )

            if model.showsDateNavigation {
                HStack(spacing: BrevSpacing.xxs) {
                    Button {
                        model.goToPrevious()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel(
                        String(localized: "Previous", bundle: .module)
                    )
                    Button {
                        model.goToToday()
                    } label: {
                        Text(String(localized: "Today", bundle: .module))
                    }
                    Button {
                        model.goToNext()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityLabel(
                        String(localized: "Next", bundle: .module)
                    )
                }
                Text(model.rangeTitle)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textSecondary.color)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let editing,
               editing.canAuthor, editing.defaultTarget != nil {
                Button {
                    Task { await presentNewEvent() }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(
                    String(localized: "New event", bundle: .module)
                )
            }
            Button {
                Task { await model.syncAll() }
            } label: {
                if model.syncingSourceIDs.isEmpty {
                    Image(systemName: "arrow.triangle.2.circlepath")
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .disabled(!model.canSyncAny)
            .accessibilityLabel(
                String(localized: "Sync calendars now", bundle: .module)
            )
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.xs)
    }
}
