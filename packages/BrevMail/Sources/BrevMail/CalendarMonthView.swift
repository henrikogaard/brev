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

/// The month grid inside the Calendar surface (ADR-0072 #6).
///
/// Complete weeks covering the displayed month; cells borrowed from
/// adjacent months render dimmed. Each cell shows its day number plus up
/// to three event chips with a "+N more" overflow — tapping a cell
/// selects the day and the root view switches to the day layout.
public struct CalendarMonthView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.calendar) private var calendar

    /// Weeks of seven cells covering the displayed month.
    let weeks: [[CalendarGridLayout.MonthDay]]
    /// Events covering a day, resolved by the caller.
    let eventsFor: (Date) -> [PIMEvent]
    /// Resolves an event's collection for the chip color.
    let collectionFor: (PIMEvent) -> PIMCollection?
    /// Selection shared with the detail pane.
    @Binding var selectedEventID: PIMEvent.ID?
    /// Tapping a cell lands here — the root view switches to day layout.
    let onSelectDay: (Date) -> Void
    /// Clock for the today highlight.
    let now: Date

    /// The most chips a cell renders before collapsing into "+N more".
    private static let maxVisibleChips = 3

    public init(
        weeks: [[CalendarGridLayout.MonthDay]],
        eventsFor: @escaping (Date) -> [PIMEvent],
        collectionFor: @escaping (PIMEvent) -> PIMCollection? = { _ in nil },
        selectedEventID: Binding<PIMEvent.ID?>,
        onSelectDay: @escaping (Date) -> Void = { _ in },
        now: Date = Date()
    ) {
        self.weeks = weeks
        self.eventsFor = eventsFor
        self.collectionFor = collectionFor
        _selectedEventID = selectedEventID
        self.onSelectDay = onSelectDay
        self.now = now
    }

    public var body: some View {
        VStack(spacing: 0) {
            weekdayHeader
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(
                        Array(weeks.enumerated()),
                        id: \.offset
                    ) { _, week in
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(week) { cell in
                                dayCell(cell)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityLabel(
            String(localized: "Month view", bundle: .module)
        )
    }

    // MARK: - Weekday header

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, BrevSpacing.xs)
        .accessibilityHidden(true)
    }

    /// Abbreviated weekday symbols in the calendar's first-weekday order.
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    // MARK: - Day cells

    private func dayCell(_ cell: CalendarGridLayout.MonthDay) -> some View {
        let dayEvents = eventsFor(cell.day)
        let visible = dayEvents.prefix(Self.maxVisibleChips)
        let overflow = dayEvents.count - visible.count
        return VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            Text(cell.day.formatted(.dateTime.day()))
                .brevFont(.caption)
                .foregroundStyle(
                    isToday(cell.day)
                        ? theme.bgPrimary.color
                        : cell.inMonth
                        ? theme.textPrimary.color
                        : theme.textTertiary.color
                )
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(
                        isToday(cell.day)
                            ? theme.accent.color
                            : Color.clear
                    )
                )
            ForEach(visible) { event in
                CalendarEventChip(
                    event: event,
                    collection: collectionFor(event),
                    isSelected: selectedEventID == event.id
                ) {
                    selectedEventID = event.id
                }
            }
            if overflow > 0 {
                Text(String(
                    localized: "+\(overflow) more",
                    bundle: .module
                ))
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
                .padding(.leading, BrevSpacing.xs)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, BrevSpacing.xxs)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .top)
        .opacity(cell.inMonth ? 1 : 0.55)
        .background(
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
        )
        .onTapGesture {
            onSelectDay(cell.day)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.bgSecondary.color)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            cell.day.formatted(
                .dateTime.weekday(.wide).month(.wide).day()
            )
        )
        .accessibilityHint(
            String(localized: "Show this day", bundle: .module)
        )
    }

    private func isToday(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: now)
    }
}
