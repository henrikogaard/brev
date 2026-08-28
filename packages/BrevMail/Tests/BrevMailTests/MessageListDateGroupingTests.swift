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

import BrevBackend
@testable import BrevMail
import Foundation
import Testing

@Suite("MessageListDateGrouping")
struct MessageListDateGroupingTests {
    @Test("groups received dates into Outlook-style sections")
    func groupsReceivedDatesIntoOutlookStyleSections() {
        let reference = Self.date(year: 2026, month: 5, day: 29, hour: 12)
        let calendar = Calendar(identifier: .gregorian)
        let headers = [
            Self.makeHeader(id: "today", daysBefore: 0, reference: reference, calendar: calendar),
            Self.makeHeader(id: "yesterday", daysBefore: 1, reference: reference, calendar: calendar),
            Self.makeHeader(id: "last-week", daysBefore: 8, reference: reference, calendar: calendar),
            Self.makeHeader(id: "two-weeks", daysBefore: 16, reference: reference, calendar: calendar),
            Self.makeHeader(id: "one-month", daysBefore: 35, reference: reference, calendar: calendar)
        ]

        let sections = MessageListDateGrouping.sections(
            for: headers,
            referenceDate: reference,
            calendar: calendar
        )

        #expect(sections.map(\.title) == [
            "Today",
            "Yesterday",
            "Last week",
            "Two weeks ago",
            "One month ago"
        ])
        #expect(sections.map { $0.headers.map(\.id) } == [
            ["today"],
            ["yesterday"],
            ["last-week"],
            ["two-weeks"],
            ["one-month"]
        ])
    }

    @Test("old dates group into years instead of large month counts")
    func oldDatesGroupIntoYearsInsteadOfLargeMonthCounts() {
        let reference = Self.date(year: 2026, month: 5, day: 29, hour: 12)
        let calendar = Calendar(identifier: .gregorian)
        let headers = [
            Self.makeHeader(id: "five-months", daysBefore: 150, reference: reference, calendar: calendar),
            Self.makeHeader(id: "one-year", daysBefore: 365, reference: reference, calendar: calendar),
            // ~164 months ago — previously rendered as "164 months ago".
            Self.makeHeader(id: "thirteen-years", daysBefore: 5000, reference: reference, calendar: calendar)
        ]

        let sections = MessageListDateGrouping.sections(
            for: headers,
            referenceDate: reference,
            calendar: calendar
        )

        #expect(sections.map(\.title) == ["5 months ago", "One year ago", "13 years ago"])
    }

    @Test("pinned messages are separated into a top section")
    func pinnedMessagesAreSeparatedIntoTopSection() {
        let reference = Self.date(year: 2026, month: 5, day: 29, hour: 12)
        let calendar = Calendar(identifier: .gregorian)
        let today = Self.makeHeader(id: "today", daysBefore: 0, reference: reference, calendar: calendar)
        let olderPinned = Self.makeHeader(id: "older", daysBefore: 16, reference: reference, calendar: calendar)

        let sections = MessageListDateGrouping.sections(
            for: [olderPinned, today],
            pinnedIDs: [olderPinned.id],
            referenceDate: reference,
            calendar: calendar
        )

        #expect(sections.map(\.title) == ["Pinned", "Today"])
        #expect(sections.map { $0.headers.map(\.id) } == [[olderPinned.id], [today.id]])
    }

    private static func makeHeader(
        id: String,
        daysBefore: Int,
        reference: Date,
        calendar: Calendar
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: id,
            folderID: "inbox",
            from: Correspondent(name: "Ada", email: "ada@example.org"),
            subject: id,
            snippet: "",
            date: calendar.date(byAdding: .day, value: -daysBefore, to: reference)!
        )
    }

    private static func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: year,
            month: month,
            day: day,
            hour: hour
        ).date!
    }
}
