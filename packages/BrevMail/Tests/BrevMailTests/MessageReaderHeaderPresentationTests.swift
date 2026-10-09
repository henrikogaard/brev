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

@Suite("MessageReaderHeaderPresentation")
struct MessageReaderHeaderPresentationTests {
    private static let utc = TimeZone(identifier: "UTC") ?? .gmt
    private static let oslo = TimeZone(identifier: "Europe/Oslo") ?? .gmt
    private static let en = Locale(identifier: "en_US")
    private static let nb = Locale(identifier: "nb_NO")

    /// Friday 2026-10-09 12:00 UTC.
    private static let now = date(2026, 10, 9, 12, 0)

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )) ?? .distantPast
    }

    private func label(
        _ date: Date,
        locale: Locale = en,
        timeZone: TimeZone = utc
    ) -> String {
        MessageReaderHeaderPresentation.shortDate(
            for: date,
            now: Self.now,
            calendar: Calendar(identifier: .gregorian),
            locale: locale,
            timeZone: timeZone
        )
    }

    @Test("today shows the time only")
    func todayShowsTime() {
        let value = Self.date(2026, 10, 9, 10, 17)
        #expect(label(value, locale: Self.nb) == "10:17")
        #expect(label(value, locale: Self.en).hasPrefix("10:17"))
    }

    @Test("the last six days show the weekday")
    func recentDaysShowWeekday() {
        #expect(label(Self.date(2026, 10, 8, 23, 0)) == "Thu")
        #expect(label(Self.date(2026, 10, 3, 9, 0)) == "Sat")
        #expect(label(Self.date(2026, 10, 8, 23, 0), locale: Self.nb).hasPrefix("tor"))
    }

    @Test("older dates this year show day and month")
    func thisYearShowsDayMonth() {
        #expect(label(Self.date(2026, 10, 2, 9, 0)) == "Oct 2")
        #expect(label(Self.date(2026, 1, 15, 9, 0)) == "Jan 15")
        #expect(label(Self.date(2026, 10, 2, 9, 0), locale: Self.nb) == "2. okt.")
    }

    @Test("previous years include the year")
    func olderShowsYear() {
        #expect(label(Self.date(2025, 12, 31, 9, 0)) == "Dec 31, 2025")
        #expect(label(Self.date(2025, 12, 31, 9, 0), locale: Self.nb) == "31. des. 2025")
    }

    @Test("future dates fall back to a date, never a weekday")
    func futureDatesShowDate() {
        #expect(label(Self.date(2026, 10, 20, 9, 0)) == "Oct 20")
    }

    @Test("day boundaries follow the supplied time zone")
    func timeZoneDecidesToday() {
        // 22:30 UTC on Oct 8 is 00:30 on Oct 9 in Oslo (UTC+2).
        let value = Self.date(2026, 10, 8, 22, 30)
        #expect(label(value, locale: Self.nb, timeZone: Self.oslo) == "00:30")
        #expect(label(value, timeZone: Self.utc) == "Thu")
    }

    @Test("an unknown date uses the shared unknown label")
    func unknownDate() {
        #expect(label(.distantPast) == MessageListDatePresentation.unknownDateLabel)
    }

    @Test("VoiceOver reads the sender with the full date")
    func accessibilitySummary() {
        let summary = MessageReaderHeaderPresentation.accessibilityLabel(
            senderName: "Henrik Ogard via TestFlight",
            fullDate: "9 Oct 2026 at 10:17"
        )
        #expect(summary.contains("Henrik Ogard via TestFlight"))
        #expect(summary.contains("9 Oct 2026 at 10:17"))
    }
}
