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
/// requests; the only network-adjacent action is the explicit Sync Now
/// toolbar item.
public struct CalendarRootView: View {
    @Environment(\.brevTheme) private var theme

    @State private var model: CalendarBrowsingModel
    @State private var columnVisibility = NavigationSplitViewVisibility
        .automatic
    /// Drives iOS push navigation onto the detail column on selection.
    @State private var preferredCompactColumn = NavigationSplitViewColumn
        .sidebar

    /// - Parameter model: The browsing model; the app shell builds it
    ///   over the session's PIM services.
    public init(model: CalendarBrowsingModel) {
        _model = State(initialValue: model)
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
        .onChange(of: model.selectedEventID) { _, newValue in
            if newValue != nil {
                preferredCompactColumn = .detail
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
            content
        }
        .toolbar { toolbarContent }
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
                source: model.source(for: event)
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
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
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
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
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
                            String(
                                localized: "Previous",
                                bundle: .module
                            )
                        )
                        Button {
                            model.goToToday()
                        } label: {
                            Text(
                                String(
                                    localized: "Today",
                                    bundle: .module
                                )
                            )
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
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await model.syncAll() }
            } label: {
                if model.syncingSourceIDs.isEmpty {
                    Label(
                        String(localized: "Sync Now", bundle: .module),
                        systemImage: "arrow.triangle.2.circlepath"
                    )
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
    }
}
