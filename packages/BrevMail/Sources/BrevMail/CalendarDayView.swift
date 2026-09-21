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

/// The single-day grid inside the Calendar surface (ADR-0072 #6).
///
/// All-day events pin to a strip above the hour lanes; timed events
/// render as blocks positioned by start minute and split into lanes when
/// they overlap. Tapping a block selects the event for the detail pane.
public struct CalendarDayView: View {
    /// The displayed day (start-of-day in the display zone).
    let day: Date
    /// All-day events covering the day, pinned above the hour grid.
    let allDayEvents: [PIMEvent]
    /// Lane-placed timed events covering the day.
    let placements: [CalendarGridLayout.LanePlacement]
    /// Resolves an event's collection for the block color.
    let collectionFor: (PIMEvent) -> PIMCollection?
    /// Selection shared with the detail pane.
    @Binding var selectedEventID: PIMEvent.ID?

    public init(
        day: Date,
        allDayEvents: [PIMEvent],
        placements: [CalendarGridLayout.LanePlacement],
        collectionFor: @escaping (PIMEvent) -> PIMCollection? = { _ in nil },
        selectedEventID: Binding<PIMEvent.ID?>
    ) {
        self.day = day
        self.allDayEvents = allDayEvents
        self.placements = placements
        self.collectionFor = collectionFor
        _selectedEventID = selectedEventID
    }

    public var body: some View {
        VStack(spacing: 0) {
            if !allDayEvents.isEmpty {
                AllDayStrip(
                    events: allDayEvents,
                    collectionFor: collectionFor,
                    selectedEventID: $selectedEventID
                )
            }
            ScrollView {
                CalendarDayColumn(
                    placements: placements,
                    collectionFor: collectionFor,
                    selectedEventID: $selectedEventID,
                    hourHeight: 48,
                    showsHourLabels: true
                )
            }
        }
        .accessibilityLabel(
            String(localized: "Day view", bundle: .module)
        )
    }
}

/// The horizontal all-day strip shared by the day and week grids —
/// one chip per all-day or spanning event covering the day.
struct AllDayStrip: View {
    @Environment(\.brevTheme) private var theme

    let events: [PIMEvent]
    let collectionFor: (PIMEvent) -> PIMCollection?
    @Binding var selectedEventID: PIMEvent.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            ForEach(events) { event in
                CalendarEventChip(
                    event: event,
                    collection: collectionFor(event),
                    isSelected: selectedEventID == event.id
                ) {
                    selectedEventID = event.id
                }
            }
        }
        .padding(.horizontal, BrevSpacing.sm)
        .padding(.vertical, BrevSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgSecondary.color)
        .accessibilityLabel(
            String(localized: "All-day events", bundle: .module)
        )
    }
}

/// One tappable event chip — a colored leading bar plus the title,
/// used by the all-day strip and the month cells.
struct CalendarEventChip: View {
    @Environment(\.brevTheme) private var theme

    let event: PIMEvent
    let collection: PIMCollection?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BrevSpacing.xs) {
                RoundedRectangle(cornerRadius: BrevRadius.sm)
                    .fill(chipColor)
                    .frame(width: 3)
                    .accessibilityHidden(true)
                Text(
                    event.summary
                        ?? CalendarEventPresentation.untitledTitle()
                )
                .brevFont(.caption)
                .foregroundStyle(theme.textPrimary.color)
                .strikethrough(event.status == .cancelled)
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, BrevSpacing.xs)
            .padding(.vertical, BrevSpacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BrevRadius.sm)
                    .fill(
                        isSelected
                            ? theme.accentMuted.color
                            : theme.bgSecondary.color
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            event.summary
                ?? CalendarEventPresentation.untitledTitle()
        )
        .accessibilityAddTraits(
            isSelected ? .isSelected : []
        )
    }

    /// The collection's provider color, or the theme accent when the
    /// provider sent none (Rule 1 exempts data-driven colors).
    private var chipColor: Color {
        guard let hex = collection?.colorHex else {
            return theme.accent.color
        }
        return BrevColor(hex).color
    }
}

/// The hour-lane grid for one day, shared by the day view (full height,
/// hour labels) and the week view (compact, labels only on the leading
/// column).
struct CalendarDayColumn: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.calendar) private var calendar

    let placements: [CalendarGridLayout.LanePlacement]
    let collectionFor: (PIMEvent) -> PIMCollection?
    @Binding var selectedEventID: PIMEvent.ID?
    /// Points per hour — 48 in the day view, tighter in week columns.
    var hourHeight: CGFloat = 48
    /// Whether a leading hour ruler renders inside this column.
    var showsHourLabels = true

    private let hours = 0 ..< 24

    var body: some View {
        HStack(spacing: 0) {
            if showsHourLabels {
                hourRuler
            }
            gridArea
        }
    }

    private var hourRuler: some View {
        VStack(spacing: 0) {
            ForEach(hours, id: \.self) { hour in
                Text(hourText(hour))
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                    .frame(height: hourHeight, alignment: .top)
            }
        }
        .frame(width: 48)
        .accessibilityHidden(true)
    }

    private var gridArea: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Hour gridlines.
                VStack(spacing: 0) {
                    ForEach(hours, id: \.self) { _ in
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(theme.bgSecondary.color)
                                .frame(height: 1)
                            Spacer(minLength: 0)
                        }
                        .frame(height: hourHeight, alignment: .top)
                    }
                }
                // Event blocks.
                ForEach(placements) { placement in
                    eventBlock(placement, width: geo.size.width)
                }
            }
        }
        .frame(height: hourHeight * 24)
    }

    private func eventBlock(
        _ placement: CalendarGridLayout.LanePlacement,
        width: CGFloat
    ) -> some View {
        let laneWidth = width / CGFloat(max(placement.laneCount, 1))
        let x = laneWidth * CGFloat(placement.lane)
        let y = CGFloat(placement.startMinute / 60) * hourHeight
        let height = max(
            CGFloat(placement.durationMinutes / 60) * hourHeight,
            18
        )
        let event = placement.event
        return Button {
            selectedEventID = event.id
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(
                    event.summary
                        ?? CalendarEventPresentation.untitledTitle()
                )
                .brevFont(.caption)
                .foregroundStyle(theme.bgPrimary.color)
                .strikethrough(event.status == .cancelled)
                .lineLimit(2)
                if height >= 36 {
                    Text(CalendarEventPresentation.agendaTimeText(
                        for: event,
                        calendar: calendar
                    ))
                    .brevFont(.caption)
                    .foregroundStyle(theme.bgPrimary.color.opacity(0.85))
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, BrevSpacing.xs)
            .padding(.vertical, BrevSpacing.xxs)
            .frame(
                width: laneWidth - 2,
                height: height,
                alignment: .topLeading
            )
            .background(
                RoundedRectangle(cornerRadius: BrevRadius.sm)
                    .fill(blockColor(for: event))
                    .opacity(
                        selectedEventID == event.id ? 1 : 0.85
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: BrevRadius.sm)
                    .stroke(
                        theme.accent.color,
                        lineWidth: selectedEventID == event.id ? 2 : 0
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: x, y: y)
        .accessibilityLabel(
            event.summary
                ?? CalendarEventPresentation.untitledTitle()
        )
        .accessibilityAddTraits(
            selectedEventID == event.id ? .isSelected : []
        )
    }

    private func blockColor(for event: PIMEvent) -> Color {
        guard let hex = collectionFor(event)?.colorHex else {
            return theme.accent.color
        }
        return BrevColor(hex).color
    }

    private func hourText(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = calendar.date(from: components) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}
