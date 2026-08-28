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

@testable import BrevMail
import Foundation
import Testing

@Suite("CalendarEventRangeFormatter")
struct CalendarEventRangeFormatterTests {
    /// The instant `ICSParser` produces for an all-day `VALUE=DATE:20260615`:
    /// midnight UTC on 15 June 2026.
    private static func allDayInstant() -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.date(from: DateComponents(year: 2026, month: 6, day: 15))!
    }

    @Test("all-day events render the literal VALUE=DATE in UTC, not a day early")
    func allDayRendersInUTC() {
        let start = Self.allDayInstant()

        let formatted = CalendarEventRangeFormatter.string(
            start: start, end: nil, isAllDay: true, separator: "–"
        )

        // The fix pins all-day formatting to UTC. Compare against an explicit
        // UTC-pinned reference so the assertion holds in any CI time zone — and
        // fails if the UTC pin is removed and a non-UTC machine renders Jun 14.
        var utcStyle = Date.FormatStyle.dateTime.weekday(.wide).month().day().year()
        utcStyle.timeZone = TimeZone(identifier: "UTC")!
        #expect(formatted == start.formatted(utcStyle))
    }

    @Test("timed events still render in the viewer's current time zone")
    func timedRendersInLocalZone() {
        let start = Date(timeIntervalSince1970: 1_750_000_000) // arbitrary timed instant

        let formatted = CalendarEventRangeFormatter.string(
            start: start, end: nil, isAllDay: false, separator: "–"
        )

        var localStyle = Date.FormatStyle.dateTime.weekday(.wide).month().day().hour().minute()
        localStyle.timeZone = TimeZone.current
        #expect(formatted == start.formatted(localStyle))
    }

    @Test("a range joins start and end with the supplied separator")
    func rangeUsesSeparator() {
        let start = Self.allDayInstant()
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let end = utc.date(from: DateComponents(year: 2026, month: 6, day: 16))!

        let formatted = CalendarEventRangeFormatter.string(
            start: start, end: end, isAllDay: true, separator: "–"
        )

        #expect(formatted.contains(" – "))
    }
}
