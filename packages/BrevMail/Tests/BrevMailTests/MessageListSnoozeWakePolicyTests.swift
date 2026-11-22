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

@Suite("Message list snooze wake policy")
struct MessageListSnoozeWakePolicyTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let source = MailSourceID(accountID: "account", mailboxID: "mailbox")

    @Test("an expired snooze promotes at the exact wake boundary")
    func expiresAtBoundary() {
        let messageID = SourceMessageID(sourceID: Self.source, messageID: "message")
        let wakeAt = Self.now
        let overrides = MessageListSnoozeWakePolicy.effectiveDateOverrides(
            for: [Self.entry(messageID, date: wakeAt.addingTimeInterval(-86400))],
            snoozes: [LocalMessageSnooze(messageID: messageID, wakeAt: wakeAt)],
            now: wakeAt
        )

        #expect(overrides[messageID] == wakeAt)
        #expect(MessageListSnoozeWakePolicy.nearestWakeDate(
            in: [LocalMessageSnooze(messageID: messageID, wakeAt: wakeAt)],
            sourceIDs: [Self.source],
            after: wakeAt
        ) == nil)
    }

    @Test("a canceled or future snooze does not promote a message")
    func canceledAndFutureSnoozesDoNotPromote() {
        let messageID = SourceMessageID(sourceID: Self.source, messageID: "message")
        let entry = Self.entry(messageID, date: Self.now.addingTimeInterval(-86400))

        #expect(MessageListSnoozeWakePolicy.effectiveDateOverrides(
            for: [entry],
            snoozes: [],
            now: Self.now
        ).isEmpty)

        let futureWake = Self.now.addingTimeInterval(3600)
        #expect(MessageListSnoozeWakePolicy.effectiveDateOverrides(
            for: [entry],
            snoozes: [LocalMessageSnooze(messageID: messageID, wakeAt: futureWake)],
            now: Self.now
        ).isEmpty)
    }

    @Test("a snooze on one source cannot promote a colliding message on another source")
    func sourceScopedPromotion() {
        let otherSource = MailSourceID(accountID: "other-account", mailboxID: "other-mailbox")
        let firstID = SourceMessageID(sourceID: Self.source, messageID: "shared")
        let otherID = SourceMessageID(sourceID: otherSource, messageID: "shared")
        let date = Self.now.addingTimeInterval(-86400)
        let overrides = MessageListSnoozeWakePolicy.effectiveDateOverrides(
            for: [Self.entry(firstID, date: date), Self.entry(otherID, date: date)],
            snoozes: [LocalMessageSnooze(messageID: firstID, wakeAt: Self.now)],
            now: Self.now
        )

        #expect(overrides[firstID] == Self.now)
        #expect(overrides[otherID] == nil)
    }

    @Test("a threaded representative inherits the latest effective date of loaded members")
    func threadRepresentativeUsesLatestMemberWake() {
        let representative = SourceMessageID(sourceID: Self.source, messageID: "representative")
        let member = SourceMessageID(sourceID: Self.source, messageID: "member")
        let wakeAt = Self.now
        let overrides = MessageListSnoozeWakePolicy.effectiveDateOverrides(
            for: [
                Self.entry(representative, date: wakeAt.addingTimeInterval(-172_800), threadID: "thread"),
                Self.entry(member, date: wakeAt.addingTimeInterval(-86400), threadID: "thread"),
            ],
            snoozes: [LocalMessageSnooze(messageID: member, wakeAt: wakeAt)],
            now: wakeAt
        )

        #expect(overrides[representative] == wakeAt)
        #expect(overrides[member] == wakeAt)
    }

    @Test("conversation-derived members share wake order without thread-ID matching")
    func conversationMembersShareWakeOrderWithoutThreadFallback() {
        let wakeAt = Self.now
        let anchor = Self.header(id: "anchor", rfcID: "root@example.org", date: wakeAt.addingTimeInterval(-86400))
        let parent = Self.header(
            id: "parent",
            rfcID: "parent@example.org",
            date: wakeAt.addingTimeInterval(-172_800),
            references: ["root@example.org"]
        )
        let arrival = Self.header(
            id: "arrival",
            rfcID: "arrival@example.org",
            date: wakeAt.addingTimeInterval(-3600),
            inReplyTo: "parent@example.org"
        )
        let unrelated = Self.header(
            id: "unrelated",
            rfcID: "unrelated@example.org",
            date: wakeAt.addingTimeInterval(-5000)
        )
        let anchorID = SourceMessageID(sourceID: Self.source, messageID: anchor.id)
        let metadata = LocalMessageSnoozeConversationMetadata(rfcIdentifiers: ["root@example.org"])
        let overrides = MessageListSnoozeWakePolicy.effectiveDateOverrides(
            for: [anchor, parent, arrival, unrelated].map {
                MessageListSnoozeWakeEntry(
                    sourceMessageID: SourceMessageID(sourceID: Self.source, messageID: $0.id),
                    headerDate: $0.date,
                    threadID: "same-thread",
                    header: $0
                )
            },
            snoozes: [LocalMessageSnooze(
                messageID: anchorID,
                wakeAt: wakeAt,
                createdAt: wakeAt.addingTimeInterval(-600),
                conversationMetadata: metadata
            )],
            now: wakeAt
        )

        #expect(overrides[SourceMessageID(sourceID: Self.source, messageID: parent.id)] == wakeAt)
        #expect(overrides[SourceMessageID(sourceID: Self.source, messageID: arrival.id)] == wakeAt)
        #expect(overrides[SourceMessageID(sourceID: Self.source, messageID: unrelated.id)] == nil)
    }

    @Test("promotion is limited to unsearched newest-first Inbox lists")
    func eligibilityIsNarrow() {
        #expect(MessageListSnoozeWakePolicy.shouldPromoteInboxWake(
            isInbox: true,
            isNewestFirst: true,
            hasActiveSearch: false,
            isSmartView: false,
            isSavedSearch: false
        ))
        #expect(!MessageListSnoozeWakePolicy.shouldPromoteInboxWake(
            isInbox: false,
            isNewestFirst: true,
            hasActiveSearch: false,
            isSmartView: false,
            isSavedSearch: false
        ))
        #expect(!MessageListSnoozeWakePolicy.shouldPromoteInboxWake(
            isInbox: true,
            isNewestFirst: false,
            hasActiveSearch: false,
            isSmartView: false,
            isSavedSearch: false
        ))
        #expect(!MessageListSnoozeWakePolicy.shouldPromoteInboxWake(
            isInbox: true,
            isNewestFirst: true,
            hasActiveSearch: true,
            isSmartView: false,
            isSavedSearch: false
        ))
        #expect(!MessageListSnoozeWakePolicy.shouldPromoteInboxWake(
            isInbox: true,
            isNewestFirst: true,
            hasActiveSearch: false,
            isSmartView: true,
            isSavedSearch: false
        ))
        #expect(!MessageListSnoozeWakePolicy.shouldPromoteInboxWake(
            isInbox: true,
            isNewestFirst: true,
            hasActiveSearch: false,
            isSmartView: false,
            isSavedSearch: true
        ))
    }

    @Test("nearest future wake advances after cancellation and expiry")
    func nearestWakeReschedules() {
        let first = SourceMessageID(sourceID: Self.source, messageID: "first")
        let second = SourceMessageID(sourceID: Self.source, messageID: "second")
        let firstWake = Self.now.addingTimeInterval(60)
        let secondWake = Self.now.addingTimeInterval(120)
        let snoozes = [
            LocalMessageSnooze(messageID: first, wakeAt: firstWake),
            LocalMessageSnooze(messageID: second, wakeAt: secondWake),
        ]

        #expect(MessageListSnoozeWakePolicy.nearestWakeDate(
            in: snoozes,
            sourceIDs: [Self.source],
            after: Self.now
        ) == firstWake)
        #expect(MessageListSnoozeWakePolicy.nearestWakeDate(
            in: [snoozes[1]],
            sourceIDs: [Self.source],
            after: Self.now
        ) == secondWake)
        #expect(MessageListSnoozeWakePolicy.nearestWakeDate(
            in: snoozes,
            sourceIDs: [Self.source],
            after: firstWake
        ) == secondWake)
        #expect(MessageListSnoozeWakePolicy.sleepNanoseconds(until: secondWake, now: Self.now)
            == 120_000_000_000)
    }

    @Test("nearest wake selection follows the active source set")
    func nearestWakeTracksSourceChanges() {
        let otherSource = MailSourceID(accountID: "other-account", mailboxID: "other-mailbox")
        let localID = SourceMessageID(sourceID: Self.source, messageID: "local")
        let otherID = SourceMessageID(sourceID: otherSource, messageID: "other")
        let localWake = Self.now.addingTimeInterval(120)
        let otherWake = Self.now.addingTimeInterval(60)
        let snoozes = [
            LocalMessageSnooze(messageID: localID, wakeAt: localWake),
            LocalMessageSnooze(messageID: otherID, wakeAt: otherWake),
        ]

        #expect(MessageListSnoozeWakePolicy.nearestWakeDate(
            in: snoozes,
            sourceIDs: [Self.source],
            after: Self.now
        ) == localWake)
        #expect(MessageListSnoozeWakePolicy.nearestWakeDate(
            in: snoozes,
            sourceIDs: [otherSource],
            after: Self.now
        ) == otherWake)
        #expect(MessageListSnoozeWakePolicy.nearestWakeDate(
            in: snoozes,
            sourceIDs: [],
            after: Self.now
        ) == nil)
    }

    private static func entry(
        _ messageID: SourceMessageID,
        date: Date,
        threadID: String? = nil
    ) -> MessageListSnoozeWakeEntry {
        MessageListSnoozeWakeEntry(sourceMessageID: messageID, headerDate: date, threadID: threadID)
    }

    private static func header(
        id: String,
        rfcID: String,
        date: Date,
        inReplyTo: String? = nil,
        references: [String]? = nil
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "same-thread",
            folderID: "Inbox",
            from: Correspondent(email: "ada@example.org"),
            to: [],
            subject: "Wake order",
            snippet: "",
            date: date,
            messageID: rfcID,
            inReplyTo: inReplyTo,
            references: references
        )
    }
}
