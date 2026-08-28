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

import Foundation

/// Formats an event's start–end range for display in the reader's calendar
/// invite card. Shared by the single-message and threaded readers so the two
/// surfaces can't drift apart.
enum CalendarEventRangeFormatter {
    /// A human-readable range string for a parsed calendar event.
    ///
    /// All-day events carry a floating `VALUE=DATE` that `ICSParser` pins to
    /// midnight UTC. They are therefore rendered in UTC, otherwise a viewer west
    /// of UTC would see the date a day early (an all-day "Jun 15" showing as
    /// "Jun 14"). Timed events render in the viewer's current zone as usual.
    ///
    /// - Parameters:
    ///   - start: Event start instant.
    ///   - end: Optional event end instant.
    ///   - isAllDay: Whether the event is an all-day (`VALUE=DATE`) event.
    ///   - separator: The glyph placed between start and end (e.g. an en dash).
    static func string(
        start: Date,
        end: Date?,
        isAllDay: Bool,
        separator: String
    ) -> String {
        var style: Date.FormatStyle = isAllDay
            ? .dateTime.weekday(.wide).month().day().year()
            : .dateTime.weekday(.wide).month().day().hour().minute()
        if isAllDay {
            style.timeZone = TimeZone(identifier: "UTC") ?? style.timeZone
        }
        let startText = start.formatted(style)
        guard let end else { return startText }
        let endText: String
        if Calendar.current.isDate(start, inSameDayAs: end), !isAllDay {
            endText = end.formatted(.dateTime.hour().minute())
        } else {
            endText = end.formatted(style)
        }
        return "\(startText) \(separator) \(endText)"
    }
}
