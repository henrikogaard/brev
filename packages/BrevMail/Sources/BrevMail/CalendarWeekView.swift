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

/// The seven-day grid inside the Calendar surface (ADR-0072 #6).
///
/// One column per weekday, honoring the calendar's first-weekday
/// setting. All-day events pin to a per-column strip; timed events share
/// the lane layout from the day view at a compact hour height. Column
/// headers carry the weekday and day number and highlight today.
public struct CalendarWeekView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.calendar) private var calendar

    /// The week's seven day-starts, first-weekday aware.
    let days: [Date]
    /// All-day events per day, resolved by the caller.
    let allDayFor: (Date) -> [PIMEvent]
    /// Lane-placed timed events per day, resolved by the caller.
    let lanesFor: (Date) -> [CalendarGridLayout.LanePlacement]
    /// Resolves an event's collection for the block color.
    let collectionFor: (PIMEvent) -> PIMCollection?
    /// Selection shared with the detail pane.
    @Binding var selectedEventID: PIMEvent.ID?
    /// Tapping a day header lands here — the root view switches to the
    /// day layout.
    let onSelectDay: (Date) -> Void
    /// Clock for the today highlight.
    let now: Date

    public init(
        days: [Date],
        allDayFor: @escaping (Date) -> [PIMEvent],
        lanesFor: @escaping (Date) -> [CalendarGridLayout.LanePlacement],
        collectionFor: @escaping (PIMEvent) -> PIMCollection? = { _ in nil },
        selectedEventID: Binding<PIMEvent.ID?>,
        onSelectDay: @escaping (Date) -> Void = { _ in },
        now: Date = Date()
    ) {
        self.days = days
        self.allDayFor = allDayFor
        self.lanesFor = lanesFor
        self.collectionFor = collectionFor
        _selectedEventID = selectedEventID
        self.onSelectDay = onSelectDay
        self.now = now
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerRow
            if days.contains(where: { !allDayFor($0).isEmpty }) {
                allDayRow
            }
            ScrollView {
                HStack(spacing: 0) {
                    hourRuler
                    ForEach(days, id: \.self) { day in
                        CalendarDayColumn(
                            placements: lanesFor(day),
                            collectionFor: collectionFor,
                            selectedEventID: $selectedEventID,
                            hourHeight: 28,
                            showsHourLabels: false
                        )
                    }
                }
            }
        }
        .accessibilityLabel(
            String(localized: "Week view", bundle: .module)
        )
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            // Matches the hour ruler's width so columns align.
            Color.clear
                .frame(width: 48, height: 1)
                .accessibilityHidden(true)
            ForEach(days, id: \.self) { day in
                Button {
                    onSelectDay(day)
                } label: {
                    VStack(spacing: BrevSpacing.xxs) {
                        Text(day.formatted(
                            .dateTime.weekday(.abbreviated)
                        ))
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        Text(day.formatted(.dateTime.day()))
                            .brevFont(.subheadline)
                            .foregroundStyle(
                                isToday(day)
                                    ? theme.bgPrimary.color
                                    : theme.textPrimary.color
                            )
                            .frame(width: 28, height: 28)
                            .background(
                                Circle().fill(
                                    isToday(day)
                                        ? theme.accent.color
                                        : Color.clear
                                )
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    day.formatted(
                        .dateTime.weekday(.wide).month().day()
                    )
                )
                .accessibilityHint(
                    String(
                        localized: "Show this day",
                        bundle: .module
                    )
                )
            }
        }
        .padding(.vertical, BrevSpacing.xs)
    }

    // MARK: - All-day row

    private var allDayRow: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear
                .frame(width: 48, height: 1)
                .accessibilityHidden(true)
            ForEach(days, id: \.self) { day in
                VStack(spacing: BrevSpacing.xxs) {
                    ForEach(allDayFor(day)) { event in
                        CalendarEventChip(
                            event: event,
                            collection: collectionFor(event),
                            isSelected: selectedEventID == event.id
                        ) {
                            selectedEventID = event.id
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 2)
            }
        }
        .padding(.vertical, BrevSpacing.xs)
        .background(theme.bgSecondary.color)
        .accessibilityLabel(
            String(localized: "All-day events", bundle: .module)
        )
    }

    // MARK: - Hour ruler

    private var hourRuler: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< 24, id: \.self) { hour in
                Text(hourText(hour))
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                    .frame(height: 28, alignment: .top)
            }
        }
        .frame(width: 48)
        .accessibilityHidden(true)
    }

    private func isToday(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: now)
    }

    private func hourText(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = calendar.date(from: components) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}
