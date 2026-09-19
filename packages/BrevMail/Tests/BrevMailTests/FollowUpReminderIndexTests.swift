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
import BrevSettings
import Foundation
import Testing

@Suite("Follow-up reminder index")
struct FollowUpReminderIndexTests {
    private let sourceID = MailSourceID(accountID: "acct-1", mailboxID: "personal")

    @Test("exact mailbox match beats account and global records")
    func exactMatchWins() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let settings = FollowUpSettings(reminders: [
            reminder(id: "global", messageID: "m", dueAt: now, accountID: nil, mailboxID: nil),
            reminder(id: "account", messageID: "m", dueAt: now, accountID: "acct-1", mailboxID: nil),
            reminder(id: "exact", messageID: "m", dueAt: now.addingTimeInterval(60),
                     accountID: "acct-1", mailboxID: "personal")
        ])
        let index = FollowUpReminderIndex(settings: settings)

        #expect(index.reminder(for: "m", sourceID: sourceID)?.id == "exact")
        // Same resolution the settings query produces.
        #expect(index.reminder(for: "m", sourceID: sourceID)?.id
            == settings.reminder(for: "m", sourceID: sourceID)?.id)
    }

    @Test("account-scoped match beats global; earliest due wins within a scope")
    func accountMatchAndEarliestDue() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let settings = FollowUpSettings(reminders: [
            reminder(id: "global", messageID: "m", dueAt: now, accountID: nil, mailboxID: nil),
            reminder(id: "later", messageID: "m", dueAt: now.addingTimeInterval(120),
                     accountID: "acct-1", mailboxID: nil),
            reminder(id: "earlier", messageID: "m", dueAt: now.addingTimeInterval(60),
                     accountID: "acct-1", mailboxID: nil)
        ])
        let index = FollowUpReminderIndex(settings: settings)

        #expect(index.reminder(for: "m", sourceID: sourceID)?.id == "earlier")
        #expect(index.reminder(for: "m", sourceID: nil)?.id == "global")
    }

    @Test("dismissed and completed reminders are skipped")
    func inactiveRemindersAreSkipped() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var dismissed = reminder(id: "dismissed", messageID: "m", dueAt: now,
                                 accountID: "acct-1", mailboxID: "personal")
        dismissed.isDismissed = true
        var completed = reminder(id: "completed", messageID: "m", dueAt: now,
                                 accountID: "acct-1", mailboxID: "personal")
        completed.isCompleted = true
        let active = reminder(id: "active", messageID: "m", dueAt: now,
                              accountID: "acct-1", mailboxID: "personal")
        let index = FollowUpReminderIndex(
            settings: FollowUpSettings(reminders: [dismissed, completed, active])
        )

        #expect(index.reminder(for: "m", sourceID: sourceID)?.id == "active")
        #expect(index.reminder(for: "missing", sourceID: sourceID) == nil)
    }

    private func reminder(
        id: String,
        messageID: String,
        dueAt: Date,
        accountID: String?,
        mailboxID: String?
    ) -> FollowUpReminder {
        FollowUpReminder(
            id: id,
            messageID: messageID,
            threadID: messageID,
            accountID: accountID,
            mailboxID: mailboxID,
            dueAt: dueAt
        )
    }
}
