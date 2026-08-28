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

@Suite("MailBadgePresentation")
struct MailBadgePresentationTests {
    @Test("badge policy off suppresses every badge count")
    func badgePolicyOffSuppressesEveryBadgeCount() {
        let settings = NotificationSettings(
            notificationsEnabled: true,
            badgeEnabled: true,
            badgePolicy: .off,
            soundEnabled: true,
            showPreviews: true,
            accountOverrides: [:],
            quietHoursEnabled: false,
            quietHoursStart: 22,
            quietHoursEnd: 7
        )

        #expect(MailBadgePresentation.unreadCount(
            folders: [Self.inbox(unreadCount: 4)],
            sourceSections: [Self.section(unreadCount: 4)],
            settings: settings
        ) == 0)
    }

    @Test("inbox badge policy counts inbox unread mail across visible sections")
    func inboxBadgePolicyCountsInboxUnreadMailAcrossVisibleSections() {
        let settings = NotificationSettings(
            notificationsEnabled: true,
            badgeEnabled: true,
            badgePolicy: .inboxUnread,
            soundEnabled: true,
            showPreviews: true,
            accountOverrides: [:],
            quietHoursEnabled: false,
            quietHoursStart: 22,
            quietHoursEnd: 7
        )

        #expect(MailBadgePresentation.unreadCount(
            folders: [Self.inbox(unreadCount: 2), Self.archive(unreadCount: 9)],
            sourceSections: [
                Self.section(unreadCount: 2),
                Self.section(unreadCount: 5)
            ],
            settings: settings
        ) == 7)
    }

    @Test("selected source badges respect per-account overrides")
    func selectedSourceBadgesRespectPerAccountOverrides() {
        var settings = NotificationSettings(
            notificationsEnabled: true,
            badgeEnabled: true,
            badgePolicy: .selectedSources,
            soundEnabled: true,
            showPreviews: true,
            accountOverrides: [:],
            quietHoursEnabled: false,
            quietHoursStart: 22,
            quietHoursEnd: 7
        )
        settings.setAccountOverride(
            accountID: "acct-1",
            notificationsEnabled: true,
            badgeEnabled: true,
            soundEnabled: true
        )
        settings.setAccountOverride(
            accountID: "acct-2",
            notificationsEnabled: true,
            badgeEnabled: false,
            soundEnabled: true
        )

        #expect(MailBadgePresentation.unreadCount(
            folders: [],
            sourceSections: [
                Self.section(sourceID: MailSourceID(accountID: "acct-1", mailboxID: "box-1"), unreadCount: 4),
                Self.section(sourceID: MailSourceID(accountID: "acct-2", mailboxID: "box-2"), unreadCount: 8)
            ],
            settings: settings
        ) == 4)
    }

    @Test("badge-enabled off suppresses the count even when unread mail exists")
    func badgeEnabledOffSuppressesTheCountEvenWhenUnreadMailExists() {
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

        #expect(MailBadgePresentation.unreadCount(
            folders: [Self.inbox(unreadCount: 3)],
            sourceSections: [],
            settings: settings
        ) == 0)
    }

    private static func inbox(unreadCount: Int) -> Folder {
        Folder(id: "inbox", name: "Inbox", role: .inbox, unreadCount: unreadCount)
    }

    private static func archive(unreadCount: Int) -> Folder {
        Folder(id: "archive", name: "Archive", role: .archive, unreadCount: unreadCount)
    }

    private static func section(
        sourceID: MailSourceID = MailSourceID(accountID: "acct-1", mailboxID: "box-1"),
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
            folders: [Folder(id: "inbox-\(sourceID.mailboxID)", name: "Inbox", role: .inbox, unreadCount: unreadCount)]
        )
    }
}
