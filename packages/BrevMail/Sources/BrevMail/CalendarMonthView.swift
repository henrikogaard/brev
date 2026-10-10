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
/// selects the day and the root view switches to the day layout. On a
/// compact iPhone the chips become event dots and the whole cell is one
/// button whose label lists the day's events.
public struct CalendarMonthView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.calendar) private var calendar
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    /// The today circle and day-number box scale with Dynamic Type.
    @ScaledMetric(relativeTo: .caption) private var dayNumberSize: CGFloat = 22
    /// Compact cells keep a 44 pt-or-taller touch target at every text size.
    @ScaledMetric(relativeTo: .caption) private var compactCellHeight: CGFloat = 56

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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            String(localized: "Month view", bundle: .module)
        )
    }

    // MARK: - Weekday header

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .brevFont(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textSecondary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
            }
        }
        #if os(iOS)
        // A month grid has no room for accessibility-size weekday names.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        #endif
        .padding(.vertical, BrevSpacing.sm)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrevSeparator.color(for: theme))
                .frame(height: 0.5)
        }
        .accessibilityHidden(true)
    }

    /// Abbreviated weekday symbols in the calendar's first-weekday order.
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    // MARK: - Day cells

    /// Compact iPhone cells are about 56 pt wide: chips cannot show a title
    /// there, so each cell becomes one button with the day number and up to
    /// three event dots, and its label lists the events (audit P2, P3).
    private var usesCompactCells: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    @ViewBuilder
    private func dayCell(_ cell: CalendarGridLayout.MonthDay) -> some View {
        if usesCompactCells {
            compactDayCell(cell)
        } else {
            chipDayCell(cell)
        }
    }

    /// The spoken label: day, event count and the first titles.
    private func cellLabel(
        _ cell: CalendarGridLayout.MonthDay,
        events: [PIMEvent]
    ) -> String {
        CalendarMonthCellPresentation.accessibilityLabel(
            day: cell.day,
            events: events,
            isToday: isToday(cell.day),
            calendar: calendar
        )
    }

    @ViewBuilder
    private func dayNumber(_ cell: CalendarGridLayout.MonthDay) -> some View {
        #if os(macOS)
        // The macOS window keeps its original fixed box.
        Text(cell.day.formatted(.dateTime.day()))
            .brevFont(.caption)
            .padding(.leading, BrevSpacing.xs)
            .foregroundStyle(dayNumberColor(cell))
            .frame(width: 22, height: 22)
            .background(Circle().fill(isToday(cell.day) ? theme.accent.color : Color.clear))
        #else
        Text(cell.day.formatted(.dateTime.day()))
            .brevFont(.caption)
            .foregroundStyle(dayNumberColor(cell))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(minWidth: dayNumberSize, minHeight: dayNumberSize)
            .background(Circle().fill(isToday(cell.day) ? theme.accent.color : Color.clear))
        #endif
    }

    private func dayNumberColor(_ cell: CalendarGridLayout.MonthDay) -> Color {
        if isToday(cell.day) { return theme.bgPrimary.color }
        return cell.inMonth ? theme.textPrimary.color : theme.textTertiary.color
    }

    private func compactDayCell(_ cell: CalendarGridLayout.MonthDay) -> some View {
        let dayEvents = eventsFor(cell.day)
        return Button {
            onSelectDay(cell.day)
        } label: {
            VStack(spacing: BrevSpacing.xxs) {
                dayNumber(cell)
                HStack(spacing: 3) {
                    ForEach(
                        Array(dayEvents.prefix(
                            CalendarMonthCellPresentation.dotCount(forEventCount: dayEvents.count)
                        ).enumerated()),
                        id: \.offset
                    ) { _, event in
                        Circle()
                            .fill(dotColor(for: event))
                            .frame(width: 6, height: 6)
                    }
                    if CalendarMonthCellPresentation.hasOverflow(eventCount: dayEvents.count) {
                        Image(systemName: "plus")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(theme.textSecondary.color)
                    }
                }
                .frame(height: 8)
                .opacity(cell.inMonth ? 1 : 0.5)
                Spacer(minLength: 0)
            }
            .padding(.vertical, BrevSpacing.xs)
            .frame(maxWidth: .infinity, minHeight: compactCellHeight, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(BrevSeparator.color(for: theme))
                .frame(height: 1)
        }
        .accessibilityLabel(cellLabel(cell, events: dayEvents))
        .accessibilityHint(
            String(localized: "Show this day", bundle: .module)
        )
    }

    private func chipDayCell(_ cell: CalendarGridLayout.MonthDay) -> some View {
        let dayEvents = eventsFor(cell.day)
        let visible = dayEvents.prefix(Self.maxVisibleChips)
        let overflow = dayEvents.count - visible.count
        return VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            Button {
                onSelectDay(cell.day)
            } label: {
                dayNumber(cell)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(cellLabel(cell, events: dayEvents))
            .accessibilityHint(
                String(localized: "Show this day", bundle: .module)
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
                Button {
                    onSelectDay(cell.day)
                } label: {
                    Text(String(
                        localized: "+\(overflow) more",
                        bundle: .module
                    ))
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                    .padding(.leading, BrevSpacing.xs)
                }
                .buttonStyle(.plain)
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
                .fill(BrevSeparator.color(for: theme))
                .frame(height: 1)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(BrevSeparator.color(for: theme))
                .frame(width: 1)
        }
        .accessibilityElement(children: .contain)
    }

    /// The event's collection color, or the accent when the provider sent none.
    private func dotColor(for event: PIMEvent) -> Color {
        guard let hex = collectionFor(event)?.colorHex else {
            return theme.accent.color
        }
        return BrevColor(hex).color
    }

    private func isToday(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: now)
    }
}
