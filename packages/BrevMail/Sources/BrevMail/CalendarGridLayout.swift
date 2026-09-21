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

/// Grid math for the Calendar day/week/month layouts (ADR-0072 #6).
///
/// Pure functions over `PIMEvent` so the views stay thin and every rule
/// is testable without rendering. Two coverage rules matter:
///
/// - All-day events carry a floating `VALUE=DATE` pinned to midnight UTC
///   with an *exclusive* DTEND — a one-day event stores end = start + 1
///   day. Coverage is computed in UTC so a viewer west of UTC never sees
///   the event a day early.
/// - Timed events cover every local day their [start, end) interval
///   intersects, so a multi-day event appears on each day it touches and
///   an event ending exactly at midnight does not bleed into that day.
public enum CalendarGridLayout {
    /// One cell in the month grid — a real day plus its position
    /// relative to the displayed month.
    public struct MonthDay: Identifiable, Hashable, Sendable {
        public let id: String
        /// Start-of-day in the display zone.
        public let day: Date
        /// False for leading/trailing cells borrowed from adjacent
        /// months — the view dims them.
        public let inMonth: Bool

        public init(day: Date, inMonth: Bool) {
            id = String(day.timeIntervalSince1970)
            self.day = day
            self.inMonth = inMonth
        }
    }

    /// A timed event assigned to a horizontal lane inside a day column.
    /// `lane` / `laneCount` position the block when events overlap.
    public struct LanePlacement: Identifiable, Hashable, Sendable {
        public let event: PIMEvent
        /// Minutes from the day's midnight to the event's visible start
        /// (clamped to the day boundary for spanning events).
        public let startMinute: Double
        /// Visible length in minutes, clamped to the day boundary.
        public let durationMinutes: Double
        /// Zero-based lane index within the overlap group.
        public let lane: Int
        /// Total lanes in the event's overlap group (1 = no overlap).
        /// Assigned when the sweep closes the group.
        public var laneCount: Int

        public var id: PIMEvent.ID { event.id }

        public init(
            event: PIMEvent,
            startMinute: Double,
            durationMinutes: Double,
            lane: Int,
            laneCount: Int
        ) {
            self.event = event
            self.startMinute = startMinute
            self.durationMinutes = durationMinutes
            self.lane = lane
            self.laneCount = laneCount
        }
    }

    // MARK: - Day coverage

    /// Whether an event should render on the given day (start-of-day in
    /// the display zone). Undated events cover no day.
    public static func coversDay(
        _ event: PIMEvent,
        day: Date,
        calendar: Calendar
    ) -> Bool {
        guard let start = event.start else { return false }
        var zone = calendar
        if event.isAllDay {
            zone.timeZone = TimeZone(identifier: "UTC") ?? zone.timeZone
        }
        let dayStart = zone.startOfDay(for: day)
        guard let dayEnd = zone.date(
            byAdding: .day,
            value: 1,
            to: dayStart
        ) else { return false }
        let eventEnd = event.end ?? start
        // Half-open interval intersection: [start, end) ∩ [day, day+1).
        return start < dayEnd && eventEnd > dayStart
    }

    /// The events covering one day, display-sorted: all-day events
    /// first, then timed events by start.
    public static func events(
        _ events: [PIMEvent],
        onDay day: Date,
        calendar: Calendar
    ) -> [PIMEvent] {
        events
            .filter { coversDay($0, day: day, calendar: calendar) }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay {
                    return lhs.isAllDay
                }
                return (lhs.start ?? .distantPast)
                    < (rhs.start ?? .distantPast)
            }
    }

    /// The all-day events covering one day — the day/week views pin
    /// these to a strip above the hour lanes.
    public static func allDayEvents(
        _ events: [PIMEvent],
        onDay day: Date,
        calendar: Calendar
    ) -> [PIMEvent] {
        self.events(events, onDay: day, calendar: calendar)
            .filter(\.isAllDay)
    }

    // MARK: - Week

    /// The seven day-starts of the week containing `day`, honoring the
    /// calendar's first-weekday setting.
    public static func weekDays(
        containing day: Date,
        calendar: Calendar
    ) -> [Date] {
        let start = calendar.startOfDay(for: day)
        // weekday is 1-based Sunday-first; shift so firstWeekday is 0.
        let weekday = calendar.component(.weekday, from: start)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let weekStart = calendar.date(
            byAdding: .day,
            value: -offset,
            to: start
        ) else { return [start] }
        return (0 ..< 7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: weekStart)
        }
    }

    // MARK: - Month

    /// The month grid's cells: complete weeks covering the month
    /// containing `day`, padded with adjacent-month days so every row
    /// has seven cells.
    public static func monthDays(
        containing day: Date,
        calendar: Calendar
    ) -> [MonthDay] {
        guard let monthInterval = calendar.dateInterval(
            of: .month,
            for: day
        ) else { return [] }
        let firstWeek = weekDays(
            containing: monthInterval.start,
            calendar: calendar
        )
        guard let gridStart = firstWeek.first else { return [] }
        var cells: [MonthDay] = []
        var cursor = gridStart
        // Walk complete weeks until the grid covers the month's end.
        while cursor < monthInterval.end || cells.count % 7 != 0 {
            cells.append(
                MonthDay(
                    day: cursor,
                    inMonth: monthInterval.contains(cursor)
                )
            )
            guard let next = calendar.date(
                byAdding: .day,
                value: 1,
                to: cursor
            ) else { break }
            cursor = next
        }
        return cells
    }

    /// The month grid shaped as weeks of seven cells.
    public static func monthWeeks(
        containing day: Date,
        calendar: Calendar
    ) -> [[MonthDay]] {
        let days = monthDays(containing: day, calendar: calendar)
        return stride(from: 0, to: days.count, by: 7).map {
            Array(days[$0 ..< min($0 + 7, days.count)])
        }
    }

    // MARK: - Timed lanes

    /// Lane assignments for one day's timed events, clipped to the day
    /// boundary so spanning events render as continuing blocks.
    ///
    /// Overlapping events share a group; each takes its own lane and the
    /// group's lane count so the view can split the column width.
    public static func timedLanes(
        _ events: [PIMEvent],
        onDay day: Date,
        calendar: Calendar
    ) -> [LanePlacement] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(
            byAdding: .day,
            value: 1,
            to: dayStart
        ) else { return [] }
        let timed = events.filter {
            !$0.isAllDay && coversDay($0, day: day, calendar: calendar)
        }
        // Clip each event to the visible day.
        struct Clip {
            let event: PIMEvent
            let start: Date
            let end: Date
        }
        var clips: [Clip] = timed.compactMap { event in
            guard let start = event.start else { return nil }
            let clipStart = max(start, dayStart)
            let clipEnd = min(event.end ?? start, dayEnd)
            // Zero-length and inverted events still get a minimum
            // visible block rather than vanishing.
            let visibleEnd = max(clipEnd, clipStart)
            return Clip(event: event, start: clipStart, end: visibleEnd)
        }
        clips.sort { $0.start < $1.start }

        // Sweep-line: events overlapping the open lanes' latest end join
        // the group; a gap closes the group and assigns lane counts.
        var placements: [LanePlacement] = []
        var laneEnds: [Date] = []
        var group: [Int] = [] // indices into placements

        func closeGroup() {
            let count = laneEnds.count
            for index in group {
                placements[index].laneCount = count
            }
            laneEnds = []
            group = []
        }

        for clip in clips {
            // A start at or after every lane's end opens a fresh group.
            if let latestEnd = laneEnds.max(), clip.start >= latestEnd {
                closeGroup()
            }
            let lane: Int
            if let free = laneEnds.firstIndex(where: { clip.start >= $0 }) {
                lane = free
                laneEnds[free] = clip.end
            } else {
                lane = laneEnds.count
                laneEnds.append(clip.end)
            }
            placements.append(
                LanePlacement(
                    event: clip.event,
                    startMinute: clip.start.timeIntervalSince(dayStart) / 60,
                    durationMinutes: max(
                        clip.end.timeIntervalSince(clip.start) / 60,
                        1
                    ),
                    lane: lane,
                    laneCount: 0 // assigned when the group closes
                )
            )
            group.append(placements.count - 1)
        }
        closeGroup()
        return placements
    }

    // MARK: - Range titles

    /// Toolbar title for the day view: "Tuesday, September 22".
    public static func dayTitle(
        for day: Date,
        calendar: Calendar
    ) -> String {
        day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// Toolbar title for the week view: "Sep 21 – 27, 2026".
    public static func weekTitle(
        containing day: Date,
        calendar: Calendar
    ) -> String {
        let days = weekDays(containing: day, calendar: calendar)
        guard let first = days.first, let last = days.last else {
            return dayTitle(for: day, calendar: calendar)
        }
        let startText = first.formatted(.dateTime.month(.abbreviated).day())
        let endText = last.formatted(
            .dateTime.month(.abbreviated).day().year()
        )
        return "\(startText) – \(endText)"
    }

    /// Toolbar title for the month view: "September 2026".
    public static func monthTitle(
        containing day: Date,
        calendar: Calendar
    ) -> String {
        day.formatted(.dateTime.month(.wide).year())
    }
}
