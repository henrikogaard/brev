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
import Foundation
import Testing

@Suite("NewMailNotificationPolicy")
struct NewMailNotificationPolicyTests {
    @Test("notifications disabled suppresses delivery")
    func notificationsDisabledSuppressesDelivery() {
        var settings = Self.settings(notificationsEnabled: false)

        let decision = NewMailNotificationPolicy.decision(
            settings: settings,
            accountID: "acct-1",
            now: Self.date(hour: 10),
            calendar: Self.calendar
        )

        #expect(decision.shouldDeliver == false)
        #expect(decision.showPreviews == settings.showPreviews)
        #expect(decision.playSound == false)

        settings.notificationsEnabled = true
        #expect(NewMailNotificationPolicy.decision(
            settings: settings,
            accountID: "acct-1",
            now: Self.date(hour: 10),
            calendar: Self.calendar
        ).shouldDeliver)
    }

    @Test("account override can suppress notifications and sound")
    func accountOverrideControlsNotificationsAndSound() {
        var settings = Self.settings()
        settings.setAccountOverride(
            accountID: "muted",
            notificationsEnabled: false,
            badgeEnabled: true,
            soundEnabled: true
        )
        settings.setAccountOverride(
            accountID: "quiet",
            notificationsEnabled: true,
            badgeEnabled: true,
            soundEnabled: false
        )

        #expect(NewMailNotificationPolicy.decision(
            settings: settings,
            accountID: "muted",
            now: Self.date(hour: 10),
            calendar: Self.calendar
        ).shouldDeliver == false)

        let quietDecision = NewMailNotificationPolicy.decision(
            settings: settings,
            accountID: "quiet",
            now: Self.date(hour: 10),
            calendar: Self.calendar
        )
        #expect(quietDecision.shouldDeliver)
        #expect(quietDecision.playSound == false)
    }

    @Test("quiet hours suppress same-day and overnight windows")
    func quietHoursSuppressConfiguredWindows() {
        var sameDay = Self.settings()
        sameDay.quietHoursEnabled = true
        sameDay.quietHoursStart = 9
        sameDay.quietHoursEnd = 17

        #expect(NewMailNotificationPolicy.decision(
            settings: sameDay,
            accountID: "acct-1",
            now: Self.date(hour: 12),
            calendar: Self.calendar
        ).shouldDeliver == false)
        #expect(NewMailNotificationPolicy.decision(
            settings: sameDay,
            accountID: "acct-1",
            now: Self.date(hour: 18),
            calendar: Self.calendar
        ).shouldDeliver)

        var overnight = Self.settings()
        overnight.quietHoursEnabled = true
        overnight.quietHoursStart = 22
        overnight.quietHoursEnd = 7

        #expect(NewMailNotificationPolicy.decision(
            settings: overnight,
            accountID: "acct-1",
            now: Self.date(hour: 23),
            calendar: Self.calendar
        ).shouldDeliver == false)
        #expect(NewMailNotificationPolicy.decision(
            settings: overnight,
            accountID: "acct-1",
            now: Self.date(hour: 6),
            calendar: Self.calendar
        ).shouldDeliver == false)
        #expect(NewMailNotificationPolicy.decision(
            settings: overnight,
            accountID: "acct-1",
            now: Self.date(hour: 12),
            calendar: Self.calendar
        ).shouldDeliver)
    }

    @Test("preview preference is preserved in delivery decision")
    func previewPreferenceIsPreserved() {
        var settings = Self.settings()
        settings.showPreviews = false

        let decision = NewMailNotificationPolicy.decision(
            settings: settings,
            accountID: "acct-1",
            now: Self.date(hour: 10),
            calendar: Self.calendar
        )

        #expect(decision.shouldDeliver)
        #expect(decision.showPreviews == false)
    }

    @Test("preview payload feeds the notification content extension")
    func previewPayloadFeedsNotificationContentExtension() {
        let payload = NewMailNotificationPolicy.contentPayload(
            correspondent: .init(name: "Maja Holm", email: "maja@example.org"),
            subject: "Standup notes",
            snippet: "Can we pull the UI polish task before lunch?",
            receivedAt: Self.date(hour: 10),
            messageID: "msg-1",
            accountID: "acct-1",
            folderName: "Inbox",
            showPreviews: true,
            playSound: true
        )

        #expect(payload.title == "Maja Holm")
        #expect(payload.body == "Standup notes")
        #expect(payload.categoryIdentifier == "brev.newMail")
        #expect(payload.threadIdentifier == "brev.newMail.acct-1")
        #expect(payload.userInfo["messageID"] == "msg-1")
        #expect(payload.userInfo["accountID"] == "acct-1")
        #expect(payload.userInfo["senderName"] == "Maja Holm")
        #expect(payload.userInfo["subject"] == "Standup notes")
        #expect(payload.userInfo["snippet"] == "Can we pull the UI polish task before lunch?")
        #expect(payload.userInfo["date"] == "2026-06-03T10:00:00Z")
        #expect(payload.playSound)
    }

    @Test("inline Reply uses a capability-gated notification category")
    func inlineReplyUsesCapabilityGatedCategory() {
        let withoutReply = NewMailNotificationPolicy.contentPayload(
            correspondent: .init(name: "Maja Holm", email: "maja@example.org"),
            subject: "Standup notes",
            snippet: "",
            receivedAt: Self.date(hour: 10),
            messageID: "msg-1",
            accountID: "acct-1",
            folderID: "inbox",
            folderName: "Inbox",
            showPreviews: true,
            playSound: true,
            allowsInlineReply: false
        )
        let withReply = NewMailNotificationPolicy.contentPayload(
            correspondent: .init(name: "Maja Holm", email: "maja@example.org"),
            subject: "Standup notes",
            snippet: "",
            receivedAt: Self.date(hour: 10),
            messageID: "msg-1",
            accountID: "acct-1",
            folderID: "inbox",
            folderName: "Inbox",
            showPreviews: true,
            playSound: true,
            allowsInlineReply: true
        )

        #expect(withoutReply.categoryIdentifier == "brev.newMail")
        #expect(withReply.categoryIdentifier == "brev.newMail.replyEnabled")
    }

    @Test("hidden previews omit private notification extension fields")
    func hiddenPreviewsOmitPrivateNotificationExtensionFields() {
        let payload = NewMailNotificationPolicy.contentPayload(
            correspondent: .init(name: "Maja Holm", email: "maja@example.org"),
            subject: "Standup notes",
            snippet: "Can we pull the UI polish task before lunch?",
            receivedAt: Self.date(hour: 10),
            messageID: "msg-1",
            accountID: "acct-1",
            folderName: "Inbox",
            showPreviews: false,
            playSound: false
        )

        #expect(payload.title == "New mail")
        #expect(payload.body == "In Inbox")
        #expect(payload.userInfo["messageID"] == "msg-1")
        #expect(payload.userInfo["accountID"] == "acct-1")
        #expect(payload.userInfo["senderName"] == nil)
        #expect(payload.userInfo["subject"] == nil)
        #expect(payload.userInfo["snippet"] == nil)
        #expect(payload.userInfo["date"] == nil)
        #expect(!payload.playSound)
    }

    @Test("message preview uses matching visible header")
    func messagePreviewUsesMatchingVisibleHeader() {
        let header = MessageHeader(
            id: "INBOX:44",
            threadID: "<44@example.org>",
            folderID: "INBOX",
            from: Correspondent(name: "Wolt", email: "info@wolt.com"),
            to: [Correspondent(email: "henrik@example.org")],
            subject: "Kjopskvittering",
            snippet: "Takk for at du bestilte.",
            date: Self.date(hour: 11),
            isRead: false,
            isFlagged: false
        )

        let preview = NewMailNotificationPolicy.messagePreview(
            messageID: "INBOX:44",
            visibleHeaders: [
                MessageHeader(
                    id: "INBOX:43",
                    threadID: "<43@example.org>",
                    folderID: "INBOX",
                    from: Correspondent(email: "other@example.org"),
                    to: [],
                    subject: "Other",
                    snippet: "",
                    date: Self.date(hour: 9),
                    isRead: false,
                    isFlagged: false
                ),
                header,
            ],
            fallbackDate: Self.date(hour: 10)
        )

        #expect(preview.correspondent == header.from)
        #expect(preview.subject == "Kjopskvittering")
        #expect(preview.snippet == "Takk for at du bestilte.")
        #expect(preview.receivedAt == Self.date(hour: 11))
    }

    @Test("message preview uses cached header when message is not visible")
    func messagePreviewUsesCachedHeaderWhenMessageIsNotVisible() {
        let cachedHeader = MessageHeader(
            id: "INBOX:44",
            threadID: "<44@example.org>",
            folderID: "INBOX",
            from: Correspondent(name: "Brev CI", email: "ci@example.org"),
            to: [Correspondent(email: "henrik@example.org")],
            subject: "Build finished",
            snippet: "The IMAP notification check passed.",
            date: Self.date(hour: 12),
            isRead: false,
            isFlagged: false
        )

        let preview = NewMailNotificationPolicy.messagePreview(
            messageID: "INBOX:44",
            visibleHeaders: [],
            cachedHeaders: [cachedHeader],
            fallbackDate: Self.date(hour: 10)
        )

        #expect(preview.correspondent == cachedHeader.from)
        #expect(preview.subject == "Build finished")
        #expect(preview.snippet == "The IMAP notification check passed.")
        #expect(preview.receivedAt == Self.date(hour: 12))
    }

    @Test("message preview prefers visible header over cached header")
    func messagePreviewPrefersVisibleHeaderOverCachedHeader() {
        let visibleHeader = MessageHeader(
            id: "INBOX:44",
            threadID: "<44@example.org>",
            folderID: "INBOX",
            from: Correspondent(name: "Visible", email: "visible@example.org"),
            to: [Correspondent(email: "henrik@example.org")],
            subject: "Visible subject",
            snippet: "Visible snippet",
            date: Self.date(hour: 13),
            isRead: false,
            isFlagged: false
        )
        let cachedHeader = MessageHeader(
            id: "INBOX:44",
            threadID: "<44@example.org>",
            folderID: "INBOX",
            from: Correspondent(name: "Cached", email: "cached@example.org"),
            to: [Correspondent(email: "henrik@example.org")],
            subject: "Cached subject",
            snippet: "Cached snippet",
            date: Self.date(hour: 12),
            isRead: false,
            isFlagged: false
        )

        let preview = NewMailNotificationPolicy.messagePreview(
            messageID: "INBOX:44",
            visibleHeaders: [visibleHeader],
            cachedHeaders: [cachedHeader],
            fallbackDate: Self.date(hour: 10)
        )

        #expect(preview.correspondent == visibleHeader.from)
        #expect(preview.subject == "Visible subject")
        #expect(preview.snippet == "Visible snippet")
        #expect(preview.receivedAt == Self.date(hour: 13))
    }

    @Test("message preview falls back when header is not visible")
    func messagePreviewFallsBackWhenHeaderIsNotVisible() {
        let fallbackDate = Self.date(hour: 10)

        let preview = NewMailNotificationPolicy.messagePreview(
            messageID: "INBOX:44",
            visibleHeaders: [],
            fallbackDate: fallbackDate
        )

        #expect(preview.correspondent == Correspondent(name: nil, email: ""))
        #expect(preview.subject == "")
        #expect(preview.snippet == "")
        #expect(preview.receivedAt == fallbackDate)
    }

    private static func settings(notificationsEnabled: Bool = true) -> NotificationSettings {
        NotificationSettings(
            notificationsEnabled: notificationsEnabled,
            badgeEnabled: true,
            badgePolicy: .inboxUnread,
            soundEnabled: true,
            showPreviews: true,
            accountOverrides: [:],
            quietHoursEnabled: false,
            quietHoursStart: 22,
            quietHoursEnd: 7
        )
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func date(hour: Int) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 6,
            day: 3,
            hour: hour
        ).date!
    }
}
