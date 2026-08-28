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

@Suite("Thread inline child row")
struct ThreadInlineChildRowTests {
    @Test("date label is derived from the injected reference date, not wall-clock now")
    func dateLabelUsesInjectedReferenceDate() {
        let header = Self.header
        let fifteenDaysLater = header.date.addingTimeInterval(15 * 86400)
        let thirtyDaysLater = header.date.addingTimeInterval(30 * 86400)

        let labelAtFifteen = ThreadInlineChildRow.dateLabel(
            for: header,
            referenceDate: fifteenDaysLater,
            calendar: Self.calendar,
            locale: Self.locale,
            timeZone: Self.timeZone
        )
        let labelAtThirty = ThreadInlineChildRow.dateLabel(
            for: header,
            referenceDate: thirtyDaysLater,
            calendar: Self.calendar,
            locale: Self.locale,
            timeZone: Self.timeZone
        )

        #expect(
            labelAtFifteen == MessageListDatePresentation.label(
                for: header.date,
                showsAbsoluteArrivalTime: false,
                referenceDate: fifteenDaysLater,
                calendar: Self.calendar,
                locale: Self.locale,
                timeZone: Self.timeZone
            )
        )
        // The same message must label differently when the injected "now"
        // differs — proof the label cannot drift with the wall clock.
        #expect(labelAtFifteen != labelAtThirty)
    }

    private static let locale = Locale(identifier: "en_US")
    private static let timeZone = TimeZone(identifier: "UTC")!
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        return calendar
    }

    private static let header = MessageHeader(
        id: "inbox:thread-child",
        threadID: "thread-1",
        folderID: "inbox",
        from: Correspondent(name: "Avery Kim", email: "avery@example.org"),
        subject: "Project update",
        snippet: "Deterministic dates keep snapshots stable.",
        date: Date(timeIntervalSince1970: 1_779_960_600),
        isRead: true
    )
}
