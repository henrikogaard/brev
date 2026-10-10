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

/// Text and counts for one month-grid cell (audit finding P3).
///
/// The grid shows a cell's events as chips or dots, which VoiceOver cannot
/// reach one by one inside a single tappable cell. The cell label therefore
/// carries the day, the event count and the first titles.
enum CalendarMonthCellPresentation {
    /// The most event titles a cell label spells out before "+N more".
    static let maxSpokenTitles = 3
    /// The most dots a compact cell draws.
    static let maxDots = 3

    /// "Wednesday, October 14, 3 events: Standup, Review, Lunch".
    ///
    /// - Parameters:
    ///   - day: The cell's day.
    ///   - events: Events covering the day, in display order.
    ///   - isToday: Prefixes "Today" so the highlight is not colour-only.
    ///   - calendar: Supplies the locale, time zone and calendar system.
    static func accessibilityLabel(
        day: Date,
        events: [PIMEvent],
        isToday: Bool,
        calendar: Calendar
    ) -> String {
        var parts: [String] = []
        if isToday {
            parts.append(String(localized: "Today", bundle: .module))
        }
        parts.append(dayText(day, calendar: calendar))
        guard !events.isEmpty else {
            parts.append(String(localized: "No events", bundle: .module))
            return parts.joined(separator: ", ")
        }

        var titles = events.prefix(maxSpokenTitles).map {
            $0.summary ?? CalendarEventPresentation.untitledTitle()
        }
        let overflow = events.count - maxSpokenTitles
        if overflow > 0 {
            titles.append(String(localized: "+\(overflow) more", bundle: .module))
        }
        let header = parts.joined(separator: ", ")
        return "\(header), \(eventCountText(events.count)): \(titles.joined(separator: ", "))"
    }

    /// "3 events" with a singular form.
    static func eventCountText(_ count: Int) -> String {
        String(localized: "\(count) events", bundle: .module)
    }

    /// How many dots a compact cell draws for `eventCount` events.
    static func dotCount(forEventCount eventCount: Int) -> Int {
        min(max(eventCount, 0), maxDots)
    }

    /// Whether a compact cell has events beyond its dots.
    static func hasOverflow(eventCount: Int) -> Bool {
        eventCount > maxDots
    }

    private static func dayText(_ day: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = calendar.locale ?? .current
        return day.formatted(style.weekday(.wide).month(.wide).day())
    }
}
