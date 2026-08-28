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

@Suite("FollowUpReminderPresentation")
struct FollowUpReminderPresentationTests {
    @Test("preset due dates advance by the expected interval")
    func presetDueDatesAdvanceByExpectedInterval() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000)

        #expect(FollowUpReminderPresentation
            .dueAt(for: .laterToday, now: now, calendar: calendar) == Date(timeIntervalSince1970: 1_814_400))
        #expect(FollowUpReminderPresentation
            .dueAt(for: .tomorrow, now: now, calendar: calendar) == Date(timeIntervalSince1970: 1_886_400))
        #expect(FollowUpReminderPresentation
            .dueAt(for: .nextWeek, now: now, calendar: calendar) == Date(timeIntervalSince1970: 2_404_800))
    }

    @Test("reminder factory keeps message and thread scope and clamps due date")
    func reminderFactoryKeepsMessageAndThreadScopeAndClampsDueDate() {
        let header = MessageHeader(
            id: "message-1",
            threadID: "thread-1",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            subject: "Hello",
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600),
            isRead: false,
            isFlagged: false
        )
        let sourceID = MailSourceID(accountID: "acct-1", mailboxID: "box-1")
        let now = Date(timeIntervalSince1970: 1_800_000)

        let reminder = FollowUpReminderPresentation.reminder(
            for: header,
            sourceID: sourceID,
            dueAt: Date(timeIntervalSince1970: 1_700_000),
            now: now
        )

        #expect(reminder.messageID == "message-1")
        #expect(reminder.threadID == "thread-1")
        #expect(reminder.accountID == "acct-1")
        #expect(reminder.mailboxID == "box-1")
        #expect(reminder.folderID == "inbox")
        #expect(reminder.dueAt == now)
    }
}
