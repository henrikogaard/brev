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
import Testing
import UserNotifications

@Suite("BrevLocalNotificationCenter")
struct BrevLocalNotificationCenterTests {
    @Test("category identifier is exposed for testability")
    @MainActor
    func categoryIdentifierIsStable() {
        #expect(BrevLocalNotificationCenter.newMailCategoryIdentifier == "brev.newMail")
        #expect(BrevLocalNotificationCenter.newMailReplyCategoryIdentifier == "brev.newMail.replyEnabled")
        #expect(BrevLocalNotificationCenter.markReadActionIdentifier == "brev.newMail.markRead")
        #expect(BrevLocalNotificationCenter.archiveActionIdentifier == "brev.newMail.archive")
        #expect(BrevLocalNotificationCenter.replyActionIdentifier == "brev.newMail.reply")
    }

    @Test("reply action accepts text without foregrounding the app")
    @MainActor
    func replyActionAcceptsInlineText() throws {
        let action = BrevLocalNotificationCenter.makeReplyAction()
        let textAction = try #require(action as? UNTextInputNotificationAction)

        #expect(textAction.textInputButtonTitle == "Send")
        #expect(textAction.textInputPlaceholder == "Reply")
        #expect(textAction.options.contains(.authenticationRequired))
        #expect(!textAction.options.contains(.foreground))
    }

    // Regression: the inbox-refresh reminder must use a FIXED identifier so each
    // schedule replaces the prior pending request. A per-call UUID identifier
    // made reminders stack on every focus loss and fire as foreground banners.
    @Test("inbox-refresh reminder identifier is fixed, not per-call")
    @MainActor
    func inboxRefreshReminderIdentifierIsFixed() {
        #expect(BrevLocalNotificationCenter.inboxRefreshReminderID == "brev.inboxRefresh")
        // A UUID would make it unique each call; the fixed id must not contain one.
        #expect(!BrevLocalNotificationCenter.inboxRefreshReminderID.contains("-"))
    }

    @Test("follow-up reminder identifiers are stable per message")
    func followUpReminderIdentifierIsStablePerMessage() {
        #expect(BrevLocalNotificationCenter.followUpReminderIdentifier(for: "message-1") == "brev.followUp.message-1")
        #expect(BrevLocalNotificationCenter.followUpReminderIdentifier(for: "message-1") ==
            BrevLocalNotificationCenter.followUpReminderIdentifier(for: "message-1"))
    }

    @Test("source-aware follow-up identifiers do not collide across mailboxes")
    func sourceAwareFollowUpIdentifiersDoNotCollideAcrossMailboxes() {
        let sourceA = MailSourceID(accountID: "acct-1", mailboxID: "inbox")
        let sourceB = MailSourceID(accountID: "acct-1", mailboxID: "archive")

        let first = BrevLocalNotificationCenter.followUpReminderIdentifier(
            for: "same-message",
            sourceID: sourceA
        )
        let second = BrevLocalNotificationCenter.followUpReminderIdentifier(
            for: "same-message",
            sourceID: sourceB
        )

        #expect(first != second)
        #expect(first.hasPrefix("brev.followUp.v2."))
        #expect(BrevLocalNotificationCenter.followUpReminderIdentifier(
            for: "same-message",
            sourceID: nil
        ) == "brev.followUp.same-message")
    }

    @Test("follow-up payload carries route data when source and folder are known")
    func followUpPayloadCarriesRouteData() {
        let sourceID = MailSourceID(accountID: "acct-1", mailboxID: "inbox-mailbox")
        let reminder = FollowUpReminder(
            messageID: "message-1",
            threadID: "thread-1",
            accountID: sourceID.accountID,
            mailboxID: sourceID.mailboxID,
            folderID: "INBOX",
            dueAt: Date().addingTimeInterval(3600)
        )

        let route = NotificationRoutingPolicy.route(
            from: BrevLocalNotificationCenter.followUpNotificationUserInfo(for: reminder)
        )

        #expect(route == NotificationMailRoute(
            accountID: "acct-1",
            folderID: "INBOX",
            messageID: "message-1",
            sourceID: sourceID
        ))
    }

    @Test("migration keeps v2 requests but drops duplicate legacy IDs")
    func migrationKeepsV2RequestsAndDropsDuplicateLegacyIDs() {
        let sourceID = MailSourceID(accountID: "acct-1", mailboxID: "inbox-mailbox")
        let reminder = FollowUpReminder(
            messageID: "message-1",
            threadID: "thread-1",
            accountID: sourceID.accountID,
            mailboxID: sourceID.mailboxID,
            folderID: "INBOX",
            dueAt: Date().addingTimeInterval(3600)
        )
        let legacy = FollowUpReminder(
            messageID: "legacy-message",
            threadID: "legacy-thread",
            dueAt: Date().addingTimeInterval(3600)
        )
        let settings = FollowUpSettings(reminders: [reminder, legacy])
        let activeIDs = BrevLocalNotificationCenter.activeFollowUpReminderIdentifiers(for: settings)

        #expect(activeIDs.contains(BrevLocalNotificationCenter.followUpReminderIdentifier(for: reminder)))
        #expect(!activeIDs.contains(BrevLocalNotificationCenter.legacyFollowUpReminderIdentifier(for: reminder.messageID)))
        #expect(activeIDs.contains(BrevLocalNotificationCenter.legacyFollowUpReminderIdentifier(for: legacy.messageID)))
    }

    @Test("auth status enum covers the four user-facing cases")
    func authStatusEnumCoverage() {
        let all = BrevNotificationAuthStatus.allCases
        #expect(all.contains(.notDetermined))
        #expect(all.contains(.denied))
        #expect(all.contains(.authorized))
        #expect(all.contains(.provisional))
    }

    @Test("every auth status has a non-empty display title and subtitle")
    func authStatusDisplayStrings() {
        for status in BrevNotificationAuthStatus.allCases {
            #expect(!status.displayTitle.isEmpty)
            #expect(!status.displaySubtitle.isEmpty)
        }
    }
}
