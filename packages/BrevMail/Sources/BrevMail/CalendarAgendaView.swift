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

/// The day-grouped agenda list inside the Calendar surface (ADR-0072).
///
/// Renders pre-grouped `DaySection`s — already filtered for hidden
/// collections and the local search query — with per-row collection color,
/// time range, title, and location. Cancelled events stay visible with a
/// strikethrough so a provider cancellation never looks like a deletion.
public struct CalendarAgendaView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.calendar) private var calendar

    /// Day buckets in chronological order.
    let days: [CalendarBrowsingModel.DaySection]
    /// Resolves an event's collection for color and provenance.
    let collectionFor: (PIMEvent) -> PIMCollection?
    /// Selection shared with the detail pane.
    @Binding var selectedEventID: PIMEvent.ID?
    /// Clock for the "Today"/"Tomorrow" section titles.
    let now: Date

    public init(
        days: [CalendarBrowsingModel.DaySection],
        collectionFor: @escaping (PIMEvent) -> PIMCollection? = { _ in nil },
        selectedEventID: Binding<PIMEvent.ID?>,
        now: Date = Date()
    ) {
        self.days = days
        self.collectionFor = collectionFor
        _selectedEventID = selectedEventID
        self.now = now
    }

    public var body: some View {
        List(selection: $selectedEventID) {
            ForEach(days) { section in
                Section {
                    ForEach(section.events) { event in
                        eventRow(event)
                            .tag(event.id)
                    }
                } header: {
                    Text(sectionTitle(for: section))
                        .brevFont(.subheadline)
                        .foregroundStyle(theme.textSecondary.color)
                }
            }
        }
        .listStyle(.plain)
        .accessibilityLabel(
            String(localized: "Calendar events", bundle: .module)
        )
    }

    private func sectionTitle(
        for section: CalendarBrowsingModel.DaySection
    ) -> String {
        guard let day = section.day else {
            return String(localized: "Undated", bundle: .module)
        }
        return CalendarEventPresentation.daySectionTitle(
            for: day,
            calendar: calendar,
            now: now
        )
    }

    private func eventRow(_ event: PIMEvent) -> some View {
        CalendarEventRowView(
            event: event,
            collection: collectionFor(event)
        )
    }
}

/// One event row in the agenda list — time range, title, location,
/// join-link and collection provenance. Extracted so the row renders
/// identically in the List and in snapshot fixtures (List rows do not
/// materialize inside a bare hosting controller).
public struct CalendarEventRowView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.calendar) private var calendar

    let event: PIMEvent
    let collection: PIMCollection?

    public init(event: PIMEvent, collection: PIMCollection? = nil) {
        self.event = event
        self.collection = collection
    }

    public var body: some View {
        HStack(alignment: .top, spacing: BrevSpacing.sm) {
            RoundedRectangle(cornerRadius: BrevRadius.sm)
                .fill(collectionColor)
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                HStack(spacing: BrevSpacing.xs) {
                    Text(CalendarEventPresentation.agendaTimeText(
                        for: event,
                        calendar: calendar
                    ))
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .frame(minWidth: 96, alignment: .leading)

                    Text(event.summary
                        ?? CalendarEventPresentation.untitledTitle())
                        .brevFont(.subheadline)
                        .foregroundStyle(theme.textPrimary.color)
                        .strikethrough(event.status == .cancelled)
                        .lineLimit(2)
                }

                HStack(spacing: BrevSpacing.xs) {
                    if let location = event.location, !location.isEmpty {
                        Label {
                            Text(location)
                        } icon: {
                            Image(systemName: "mappin")
                        }
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .lineLimit(1)
                    }
                    if event.conferenceURL != nil {
                        Image(systemName: "video")
                            .brevFont(.caption)
                            .foregroundStyle(theme.accent.color)
                            .accessibilityLabel(
                                String(
                                    localized: "Has a join link",
                                    bundle: .module
                                )
                            )
                    }
                    if let collection {
                        Text(collection.displayName)
                            .brevFont(.caption)
                            .foregroundStyle(theme.textTertiary.color)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, BrevSpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    /// The collection's provider color, or the theme accent when the
    /// provider sent none — never a literal (Rule 1 exempts data-driven
    /// colors; the hex comes from the collection record).
    private var collectionColor: Color {
        guard let hex = collection?.colorHex else {
            return theme.accent.color
        }
        return BrevColor(hex).color
    }
}
