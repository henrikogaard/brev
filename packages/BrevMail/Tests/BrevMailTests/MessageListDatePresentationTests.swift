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

@Suite("MessageListDatePresentation")
struct MessageListDatePresentationTests {
    @Test("absolute arrival labels show time for messages received today")
    func absoluteArrivalLabelsShowTimeForMessagesReceivedToday() {
        let label = MessageListDatePresentation.label(
            for: Self.date(year: 2026, month: 6, day: 3, hour: 9, minute: 5),
            showsAbsoluteArrivalTime: true,
            referenceDate: Self.date(year: 2026, month: 6, day: 3, hour: 12, minute: 0),
            calendar: Self.calendar,
            locale: Self.locale,
            timeZone: Self.timeZone
        )

        #expect(label == "9:05 AM")
    }

    @Test("absolute arrival labels include date and time for messages not received today")
    func absoluteArrivalLabelsIncludeDateAndTimeForMessagesNotReceivedToday() {
        let label = MessageListDatePresentation.label(
            for: Self.date(year: 2026, month: 6, day: 2, hour: 20, minute: 30),
            showsAbsoluteArrivalTime: true,
            referenceDate: Self.date(year: 2026, month: 6, day: 3, hour: 12, minute: 0),
            calendar: Self.calendar,
            locale: Self.locale,
            timeZone: Self.timeZone
        )

        #expect(label == "Jun 2, 8:30 PM")
    }

    @Test("absolute arrival labels include year for messages from another year")
    func absoluteArrivalLabelsIncludeYearForMessagesFromAnotherYear() {
        let label = MessageListDatePresentation.label(
            for: Self.date(year: 2025, month: 12, day: 31, hour: 23, minute: 59),
            showsAbsoluteArrivalTime: true,
            referenceDate: Self.date(year: 2026, month: 6, day: 3, hour: 12, minute: 0),
            calendar: Self.calendar,
            locale: Self.locale,
            timeZone: Self.timeZone
        )

        #expect(label == "Dec 31, 2025, 11:59 PM")
    }

    @Test("sentinel dates show unknown date instead of relative age")
    func sentinelDatesShowUnknownDateInsteadOfRelativeAge() {
        let relativeLabel = MessageListDatePresentation.label(
            for: Date.distantPast,
            showsAbsoluteArrivalTime: false,
            referenceDate: Self.date(year: 2026, month: 6, day: 8, hour: 12, minute: 0),
            calendar: Self.calendar,
            locale: Self.locale,
            timeZone: Self.timeZone
        )
        let absoluteLabel = MessageListDatePresentation.label(
            for: Date.distantPast,
            showsAbsoluteArrivalTime: true,
            referenceDate: Self.date(year: 2026, month: 6, day: 8, hour: 12, minute: 0),
            calendar: Self.calendar,
            locale: Self.locale,
            timeZone: Self.timeZone
        )

        #expect(relativeLabel == "Unknown date")
        #expect(absoluteLabel == "Unknown date")
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static let locale = Locale(identifier: "en_US_POSIX")
    private static let timeZone = TimeZone(identifier: "UTC")!

    private static func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date!
    }
}
