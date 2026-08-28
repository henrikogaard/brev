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
@testable import BrevSettings
import Testing

@Suite("UnreadBadgeUpdater")
struct UnreadBadgeUpdaterTests {
    @Test("normalises negative input to zero before persisting the count")
    func normalisesNegativeInput() async {
        let updater = await UnreadBadgeUpdater()
        await MainActor.run { updater.updateBadge(totalUnread: -3) }
        let last = await MainActor.run { updater.lastAppliedCount }
        #expect(last == 0)
    }

    @Test("passes positive values through unchanged")
    func passesPositiveValuesThrough() async {
        let updater = await UnreadBadgeUpdater()
        await MainActor.run { updater.updateBadge(totalUnread: 12) }
        let last = await MainActor.run { updater.lastAppliedCount }
        #expect(last == 12)
    }

    @Test("zero count clears the persisted last-applied value")
    func zeroCountClearsThePersistedValue() async {
        let updater = await UnreadBadgeUpdater()
        await MainActor.run {
            updater.updateBadge(totalUnread: 4)
            updater.updateBadge(totalUnread: 0)
        }
        let last = await MainActor.run { updater.lastAppliedCount }
        #expect(last == 0)
    }

    @Test("policy-aware update honours NotificationSettings.badgeEnabled")
    func policyAwareUpdateRespectsBadgeEnabled() async {
        let updater = await UnreadBadgeUpdater()
        let settings = NotificationSettings(
            notificationsEnabled: true,
            badgeEnabled: false,
            badgePolicy: .allUnread,
            soundEnabled: true,
            showPreviews: true,
            accountOverrides: [:],
            quietHoursEnabled: false,
            quietHoursStart: 22,
            quietHoursEnd: 7
        )
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox, unreadCount: 9)
        let section = Self.section(sourceID: MailSourceID(accountID: "acct-1", mailboxID: "box-1"), unreadCount: 9)
        await MainActor.run {
            updater.updateBadge(
                folders: [folder],
                sourceSections: [section],
                settings: settings
            )
        }
        let last = await MainActor.run { updater.lastAppliedCount }
        #expect(last == 0)
    }

    private static func section(
        sourceID: MailSourceID,
        unreadCount: Int
    ) -> MailSourceSection {
        let account = BrevAccount(
            id: sourceID.accountID,
            displayName: "Account",
            emailAddress: "account@example.org"
        )
        let mailbox = Mailbox(
            id: sourceID.mailboxID,
            email: "account@example.org",
            displayName: "Mailbox"
        )
        return MailSourceSection(
            id: sourceID,
            account: account,
            mailbox: mailbox,
            folders: [Folder(id: "inbox", name: "Inbox", role: .inbox, unreadCount: unreadCount)]
        )
    }
}
