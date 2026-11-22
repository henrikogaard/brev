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

    @Test("an expired cached Inbox conversation member resurfaces at the exact wake time")
    func expiredCachedInboxConversationMemberResurfaces() {
        let wakeAt = Self.now
        let anchor = Self.header(
            id: "snoozed-anchor",
            rfcID: "anchor@example.org",
            date: wakeAt.addingTimeInterval(-172_800),
            folderID: "Sent"
        )
        let oldInboxHeader = Self.header(
            id: "old-inbox-message",
            rfcID: "reply@example.org",
            date: wakeAt.addingTimeInterval(-86400),
            inReplyTo: "anchor@example.org"
        )
        let firstPageHeader = Self.header(
            id: "newest-page-one",
            rfcID: "newest@example.org",
            date: wakeAt.addingTimeInterval(-60)
        )
        let candidates = [
            LocalMessageWorkflowCandidate(sourceID: Self.source, header: anchor),
            LocalMessageWorkflowCandidate(sourceID: Self.source, header: oldInboxHeader),
            LocalMessageWorkflowCandidate(sourceID: Self.source, header: firstPageHeader),
        ]
        let rule = LocalMessageSnooze(
            messageID: SourceMessageID(sourceID: Self.source, messageID: anchor.id),
            wakeAt: wakeAt,
            conversationMetadata: .init(rfcIdentifiers: ["anchor@example.org"])
        )

        #expect(MessageListSnoozeWakePolicy.expiredInboxWakeCandidates(
            from: candidates,
            sourceID: Self.source,
            inboxFolderID: "Inbox",
            loadedHeaders: [firstPageHeader],
            snoozes: [rule],
            now: wakeAt.addingTimeInterval(-1)
        ).isEmpty)

        let awakened = MessageListSnoozeWakePolicy.expiredInboxWakeCandidates(
            from: candidates,
            sourceID: Self.source,
            inboxFolderID: "Inbox",
            loadedHeaders: [firstPageHeader],
            snoozes: [rule],
            now: wakeAt
        )
        #expect(awakened == [oldInboxHeader])
        #expect(awakened.first?.date == oldInboxHeader.date)
    }

    @Test("future snoozes and unrelated cached Inbox headers are not wake candidates")
    func futureAndUnrelatedCachedHeadersAreExcluded() {
        let anchor = Self.header(
            id: "future-anchor",
            rfcID: "future@example.org",
            date: Self.now.addingTimeInterval(-86400),
            folderID: "Sent"
        )
        let futureMember = Self.header(
            id: "future-member",
            rfcID: "future-reply@example.org",
            date: Self.now.addingTimeInterval(-172_800),
            inReplyTo: "future@example.org"
        )
        let unrelated = Self.header(
            id: "unrelated",
            rfcID: "unrelated@example.org",
            date: Self.now.addingTimeInterval(-172_800)
        )
        let candidates = [
            LocalMessageWorkflowCandidate(sourceID: Self.source, header: anchor),
            LocalMessageWorkflowCandidate(sourceID: Self.source, header: futureMember),
            LocalMessageWorkflowCandidate(sourceID: Self.source, header: unrelated),
        ]
        let rule = LocalMessageSnooze(
            messageID: SourceMessageID(sourceID: Self.source, messageID: anchor.id),
            wakeAt: Self.now.addingTimeInterval(60),
            conversationMetadata: .init(rfcIdentifiers: ["future@example.org"])
        )

        #expect(MessageListSnoozeWakePolicy.expiredInboxWakeCandidates(
            from: candidates,
            sourceID: Self.source,
            inboxFolderID: "Inbox",
            loadedHeaders: [],
            snoozes: [rule],
            now: Self.now
        ).isEmpty)
    }

    @Test("cached wake candidates remain isolated across colliding source message IDs")
    func cachedWakeCandidateSourceIsolation() {
        let otherSource = MailSourceID(accountID: "other-account", mailboxID: "other-mailbox")
        let firstAnchor = Self.header(
            id: "anchor",
            rfcID: "shared@example.org",
            date: Self.now.addingTimeInterval(-172_800),
            folderID: "Sent"
        )
        let otherAnchor = Self.header(
            id: "anchor",
            rfcID: "shared@example.org",
            date: Self.now.addingTimeInterval(-172_800),
            folderID: "Sent"
        )
        let firstInbox = Self.header(
            id: "collision",
            rfcID: "first@example.org",
            date: Self.now.addingTimeInterval(-86400),
            inReplyTo: "shared@example.org"
        )
        let otherInbox = Self.header(
            id: "collision",
            rfcID: "other@example.org",
            date: Self.now.addingTimeInterval(-86400),
            inReplyTo: "shared@example.org"
        )
        let candidates = [
            LocalMessageWorkflowCandidate(sourceID: Self.source, header: firstAnchor),
            LocalMessageWorkflowCandidate(sourceID: Self.source, header: firstInbox),
            LocalMessageWorkflowCandidate(sourceID: otherSource, header: otherAnchor),
            LocalMessageWorkflowCandidate(sourceID: otherSource, header: otherInbox),
        ]
        let rule = LocalMessageSnooze(
            messageID: SourceMessageID(sourceID: Self.source, messageID: firstAnchor.id),
            wakeAt: Self.now,
            conversationMetadata: .init(rfcIdentifiers: ["shared@example.org"])
        )

        #expect(MessageListSnoozeWakePolicy.expiredInboxWakeCandidates(
            from: candidates,
            sourceID: Self.source,
            inboxFolderID: "Inbox",
            loadedHeaders: [],
            snoozes: [rule],
            now: Self.now
        ) == [firstInbox])
        #expect(MessageListSnoozeWakePolicy.expiredInboxWakeCandidates(
            from: candidates,
            sourceID: otherSource,
            inboxFolderID: "Inbox",
            loadedHeaders: [],
            snoozes: [rule],
            now: Self.now
        ).isEmpty)
    }

    @Test("loaded rows and duplicate cached headers are not appended again")
    func cachedWakeCandidatesDeduplicateAgainstLoadedRows() {
        let loaded = Self.header(
            id: "loaded",
            rfcID: "loaded@example.org",
            date: Self.now.addingTimeInterval(-86400)
        )
        let cached = Self.header(
            id: "cached",
            rfcID: "cached@example.org",
            date: Self.now.addingTimeInterval(-172_800)
        )
        let candidates = [
            LocalMessageWorkflowCandidate(sourceID: Self.source, header: loaded),
            LocalMessageWorkflowCandidate(sourceID: Self.source, header: cached),
            LocalMessageWorkflowCandidate(sourceID: Self.source, header: cached),
        ]
        let snoozes = [
            LocalMessageSnooze(
                messageID: SourceMessageID(sourceID: Self.source, messageID: loaded.id),
                wakeAt: Self.now
            ),
            LocalMessageSnooze(
                messageID: SourceMessageID(sourceID: Self.source, messageID: cached.id),
                wakeAt: Self.now
            ),
        ]

        #expect(MessageListSnoozeWakePolicy.expiredInboxWakeCandidates(
            from: candidates,
            sourceID: Self.source,
            inboxFolderID: "Inbox",
            loadedHeaders: [loaded],
            snoozes: snoozes,
            now: Self.now
        ) == [cached])
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

    @Test("legacy thread promotion preserves a newer conversation wake without leaking it")
    func legacyAndConversationWakeDatesStaySeparate() {
        let legacyWake = Self.now.addingTimeInterval(-3600)
        let conversationWake = Self.now.addingTimeInterval(-1800)
        let legacy = Self.header(id: "legacy", rfcID: "legacy@example.org", date: Self.now.addingTimeInterval(-86400))
        let conversation = Self.header(
            id: "conversation",
            rfcID: "conversation@example.org",
            date: Self.now.addingTimeInterval(-90000)
        )
        let unrelated = Self.header(id: "unrelated", rfcID: "unrelated@example.org", date: Self.now.addingTimeInterval(-100_000))
        let entries = [legacy, conversation, unrelated].map {
            MessageListSnoozeWakeEntry(
                sourceMessageID: .init(sourceID: Self.source, messageID: $0.id),
                headerDate: $0.date, threadID: "shared-thread", header: $0
            )
        }
        let overrides = MessageListSnoozeWakePolicy.effectiveDateOverrides(
            for: entries,
            snoozes: [
                LocalMessageSnooze(
                    messageID: .init(sourceID: Self.source, messageID: legacy.id), wakeAt: legacyWake
                ),
                LocalMessageSnooze(
                    messageID: .init(sourceID: Self.source, messageID: conversation.id),
                    wakeAt: conversationWake, createdAt: Self.now.addingTimeInterval(-10),
                    conversationMetadata: .init(rfcIdentifiers: ["conversation@example.org"])
                )
            ],
            now: Self.now
        )

        #expect(overrides[.init(sourceID: Self.source, messageID: legacy.id)] == legacyWake)
        #expect(overrides[.init(sourceID: Self.source, messageID: conversation.id)] == conversationWake)
        #expect(overrides[.init(sourceID: Self.source, messageID: unrelated.id)] == legacyWake)
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
        references: [String]? = nil,
        folderID: String = "Inbox"
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "same-thread",
            folderID: folderID,
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
