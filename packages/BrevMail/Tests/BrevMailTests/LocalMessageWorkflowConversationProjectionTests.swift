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

@Suite("LocalMessageWorkflowConversationProjection")
struct LocalMessageWorkflowConversationProjectionTests {
    private let source = MailSourceID(accountID: "acct-1", mailboxID: "personal")
    private let otherSource = MailSourceID(accountID: "acct-1", mailboxID: "work")
    private let now = Date(timeIntervalSince1970: 10000)

    @Test("RFC-linked cached parents and arrivals match but equal subjects and thread IDs do not")
    func linkedMembersMatchWithoutSubjectOrThreadFallback() {
        let parent = Self.header(id: "archive-parent", folder: "Archive", rfcID: "parent@example")
        let anchor = Self.header(
            id: "inbox-anchor",
            folder: "Inbox",
            rfcID: "anchor@example",
            references: ["parent@example"]
        )
        let arrival = Self.header(
            id: "new-arrival",
            folder: "Inbox",
            rfcID: "arrival@example",
            inReplyTo: "parent@example"
        )
        let unrelated = Self.header(
            id: "unrelated",
            folder: "Inbox",
            rfcID: "unrelated@example"
        )
        let metadata = LocalMessageSnoozeConversationMetadata(
            rfcIdentifiers: ["anchor@example", "parent@example"]
        )
        let state = Self.state(anchor: anchor, source: source, metadata: metadata, wakeAt: now.addingTimeInterval(60))

        let projection = LocalMessageWorkflowConversationProjection(
            candidates: [parent, anchor, arrival, unrelated].map { .init(sourceID: source, header: $0) },
            state: state,
            now: now
        )

        #expect(projection.isSnoozed(.init(sourceID: source, messageID: parent.id)))
        #expect(projection.isSnoozed(.init(sourceID: source, messageID: anchor.id)))
        #expect(projection.isSnoozed(.init(sourceID: source, messageID: arrival.id)))
        #expect(!projection.isSnoozed(.init(sourceID: source, messageID: unrelated.id)))
    }

    @Test("new arrivals traverse a cached cross-folder bridge")
    func arrivalsTraverseCachedBridge() {
        let seed = Self.header(id: "old", folder: "Inbox", rfcID: "old@example")
        let bridge = Self.header(
            id: "unloaded-parent",
            folder: "Archive",
            rfcID: "bridge@example",
            references: ["old@example"]
        )
        let arrival = Self.header(
            id: "arrival",
            folder: "Inbox",
            rfcID: "arrival@example",
            inReplyTo: "bridge@example"
        )
        let state = Self.state(
            anchor: seed,
            source: source,
            metadata: .init(rfcIdentifiers: ["old@example"]),
            wakeAt: now.addingTimeInterval(60)
        )

        let projection = LocalMessageWorkflowConversationProjection(
            candidates: [seed, bridge, arrival].map { .init(sourceID: source, header: $0) },
            state: state,
            now: now
        )

        #expect(projection.isSnoozed(.init(sourceID: source, messageID: arrival.id)))
    }

    @Test("References-only replies parse each bare and bracketed token independently")
    func referencesOnlyRepliesUseProductionIdentifierParser() {
        let parent = Self.header(id: "parent", folder: "Archive", rfcID: "parent@example")
        let reply = Self.header(
            id: "reply",
            folder: "Inbox",
            rfcID: "reply@example",
            references: ["parent@example", "<ancestor@example>", "malformed token"]
        )
        let state = Self.state(
            anchor: parent,
            source: source,
            metadata: .init(rfcIdentifiers: ["ancestor@example"]),
            wakeAt: now.addingTimeInterval(60)
        )

        let projection = LocalMessageWorkflowConversationProjection(
            candidates: [parent, reply].map { .init(sourceID: source, header: $0) },
            state: state,
            now: now
        )

        #expect(projection.isSnoozed(.init(sourceID: source, messageID: reply.id)))
    }

    @Test("source collisions and unrelated RFCs stay separate")
    func sourceCollisionStaysSeparate() {
        let anchor = Self.header(id: "same-row", folder: "Inbox", rfcID: "anchor@example")
        let other = Self.header(id: "same-row", folder: "Inbox", rfcID: "different@example")
        let state = Self.state(
            anchor: anchor,
            source: source,
            metadata: .init(rfcIdentifiers: ["anchor@example"]),
            wakeAt: now.addingTimeInterval(60)
        )

        let projection = LocalMessageWorkflowConversationProjection(
            candidates: [
                .init(sourceID: source, header: anchor),
                .init(sourceID: otherSource, header: other),
            ],
            state: state,
            now: now
        )

        #expect(projection.isSnoozed(.init(sourceID: source, messageID: anchor.id)))
        #expect(!projection.isSnoozed(.init(sourceID: otherSource, messageID: other.id)))
    }

    @Test("identical physical copies link while contradictory owners do not")
    func conflictingIdentifiersDoNotMerge() {
        let copyA = Self.header(id: "copy-a", folder: "Inbox", rfcID: "shared@example")
        let copyB = Self.header(id: "copy-b", folder: "Archive", rfcID: "shared@example")
        let reply = Self.header(id: "reply", folder: "Inbox", rfcID: "reply@example", inReplyTo: "shared@example")
        let state = Self.state(
            anchor: copyA,
            source: source,
            metadata: .init(rfcIdentifiers: ["shared@example"]),
            wakeAt: now.addingTimeInterval(60)
        )
        let identical = LocalMessageWorkflowConversationProjection(
            candidates: [copyA, copyB].map { .init(sourceID: source, header: $0) },
            state: state,
            now: now
        )
        #expect(identical.isSnoozed(.init(sourceID: source, messageID: copyB.id)))

        let contradictory = Self.header(
            id: "conflicting-owner",
            folder: "Archive",
            rfcID: "shared@example",
            sender: "different@example.org"
        )
        let conflicted = LocalMessageWorkflowConversationProjection(
            candidates: [copyA, contradictory, reply].map { .init(sourceID: source, header: $0) },
            state: state,
            now: now
        )
        #expect(!conflicted.isSnoozed(.init(sourceID: source, messageID: reply.id)))
        #expect(!conflicted.isSnoozed(.init(sourceID: source, messageID: contradictory.id)))
    }

    @Test("invalid metadata is unmatched and legacy snooze remains message-only")
    func invalidAndLegacyRulesStayConservative() {
        let anchor = Self.header(id: "anchor", folder: "Inbox", rfcID: "anchor@example")
        let related = Self.header(id: "related", folder: "Inbox", rfcID: "related@example", inReplyTo: "anchor@example")
        let invalidState = Self.state(
            anchor: anchor,
            source: source,
            metadata: .init(rfcIdentifiers: ["not a valid id"]),
            wakeAt: now.addingTimeInterval(60)
        )
        let invalidProjection = LocalMessageWorkflowConversationProjection(
            candidates: [anchor, related].map { .init(sourceID: source, header: $0) },
            state: invalidState,
            now: now
        )
        #expect(!invalidProjection.isSnoozed(.init(sourceID: source, messageID: related.id)))

        let legacy = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: anchor.id),
            wakeAt: now.addingTimeInterval(60),
            createdAt: now
        )
        let legacyProjection = LocalMessageWorkflowConversationProjection(
            candidates: [anchor, related].map { .init(sourceID: source, header: $0) },
            state: .init(snoozes: [legacy]),
            now: now
        )
        #expect(legacyProjection.isSnoozed(.init(sourceID: source, messageID: anchor.id)))
        #expect(!legacyProjection.isSnoozed(.init(sourceID: source, messageID: related.id)))
    }

    @Test("newer expired overlapping action overrides an older active action")
    func newestExpiredRuleWins() {
        let anchor = Self.header(id: "anchor", folder: "Inbox", rfcID: "anchor@example")
        let older = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "older-anchor"),
            wakeAt: now.addingTimeInterval(600),
            createdAt: now.addingTimeInterval(-20),
            conversationMetadata: .init(rfcIdentifiers: ["anchor@example"])
        )
        let newer = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "newer-anchor"),
            wakeAt: now,
            createdAt: now.addingTimeInterval(-10),
            conversationMetadata: .init(rfcIdentifiers: ["anchor@example"])
        )
        let projection = LocalMessageWorkflowConversationProjection(
            candidates: [.init(sourceID: source, header: anchor)],
            state: .init(snoozes: [older, newer]),
            now: now
        )

        #expect(projection.snooze(for: .init(sourceID: source, messageID: anchor.id)) == newer)
        #expect(!projection.isSnoozed(.init(sourceID: source, messageID: anchor.id)))
    }

    @Test("rescheduling a derived member replaces overlaps and preserves safe seeds")
    func reschedulingDerivedMemberReplacesOverlaps() {
        let anchor = Self.header(id: "anchor", folder: "Inbox", rfcID: "anchor@example")
        let reply = Self.header(id: "reply", folder: "Archive", rfcID: "reply@example", inReplyTo: "anchor@example")
        let unrelated = Self.header(id: "unrelated", folder: "Inbox", rfcID: "other@example")
        let older = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "older-anchor"),
            wakeAt: now.addingTimeInterval(600),
            createdAt: now.addingTimeInterval(-20),
            conversationMetadata: .init(rfcIdentifiers: ["anchor@example", "retained@example"])
        )
        let newerExpired = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "newer-anchor"),
            wakeAt: now,
            createdAt: now.addingTimeInterval(-10),
            conversationMetadata: .init(rfcIdentifiers: ["anchor@example"])
        )
        let otherRule = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: unrelated.id),
            wakeAt: now.addingTimeInterval(300),
            createdAt: now.addingTimeInterval(-5),
            conversationMetadata: .init(rfcIdentifiers: ["other@example"])
        )
        let initialState = LocalMessageWorkflowState(snoozes: [older, newerExpired, otherRule])
        let projection = LocalMessageWorkflowConversationProjection(
            candidates: [anchor, reply, unrelated].map { .init(sourceID: source, header: $0) },
            state: initialState,
            now: now
        )
        let replyID = SourceMessageID(sourceID: source, messageID: reply.id)
        let wakeAt = now.addingTimeInterval(1200)

        let result = LocalMessageWorkflowConversationMutationPolicy.snoozing(
            [.init(sourceID: source, header: reply)],
            until: wakeAt,
            now: now,
            projection: projection,
            in: initialState
        )

        #expect(result.state.snoozes.count == 2)
        #expect(result.state.snoozes.contains(otherRule))
        let replacement = result.state.snoozes.first { $0.messageID == replyID }
        #expect(replacement?.wakeAt == wakeAt)
        #expect(replacement?.createdAt == now)
        #expect(replacement?.conversationMetadata?.rfcIdentifiers == [
            "anchor@example", "reply@example", "retained@example"
        ])
        #expect(result.limitedMessageIDs.isEmpty)
    }

    @Test("rescheduling drops identifiers known to conflict anywhere in the source")
    func reschedulingDropsSourceConflicts() {
        let anchor = Self.header(id: "anchor", folder: "Inbox", rfcID: "root@example")
        let reply = Self.header(
            id: "reply",
            folder: "Sent",
            rfcID: "reply@example",
            inReplyTo: "root@example"
        )
        let firstOwner = Self.header(
            id: "first-owner",
            folder: "Archive",
            rfcID: "reused@example",
            sender: "first@example"
        )
        let secondOwner = Self.header(
            id: "second-owner",
            folder: "Archive",
            rfcID: "reused@example",
            sender: "second@example"
        )
        let oldSnooze = Self.snooze(
            anchor: anchor,
            source: source,
            metadata: .init(rfcIdentifiers: ["root@example", "reused@example"]),
            wakeAt: now.addingTimeInterval(60),
            createdAt: now
        )
        let state = LocalMessageWorkflowState(snoozes: [oldSnooze])
        let projection = LocalMessageWorkflowConversationProjection(
            candidates: [anchor, reply, firstOwner, secondOwner].map { .init(sourceID: source, header: $0) },
            state: state,
            now: now
        )

        let result = LocalMessageWorkflowConversationMutationPolicy.snoozing(
            [.init(sourceID: source, header: reply)],
            until: now.addingTimeInterval(120),
            now: now,
            projection: projection,
            in: state
        )

        #expect(result.state.snoozes.first?.conversationMetadata?.rfcIdentifiers == [
            "reply@example", "root@example"
        ])
    }

    @Test("unsnoozing a derived member clears older overlaps without resurrection")
    func unsnoozingDerivedMemberClearsOverlaps() {
        let anchor = Self.header(id: "anchor", folder: "Inbox", rfcID: "anchor@example")
        let reply = Self.header(id: "reply", folder: "Archive", rfcID: "reply@example", inReplyTo: "anchor@example")
        let older = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "older-anchor"),
            wakeAt: now.addingTimeInterval(600),
            createdAt: now.addingTimeInterval(-20),
            conversationMetadata: .init(rfcIdentifiers: ["anchor@example"])
        )
        let newerExpired = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "newer-anchor"),
            wakeAt: now,
            createdAt: now.addingTimeInterval(-10),
            conversationMetadata: .init(rfcIdentifiers: ["anchor@example"])
        )
        let initialState = LocalMessageWorkflowState(snoozes: [older, newerExpired])
        let projection = LocalMessageWorkflowConversationProjection(
            candidates: [anchor, reply].map { .init(sourceID: source, header: $0) },
            state: initialState,
            now: now
        )

        let clearedState = LocalMessageWorkflowConversationMutationPolicy.clearingSnooze(
            [.init(sourceID: source, header: reply)],
            projection: projection,
            in: initialState
        )
        let afterClear = LocalMessageWorkflowConversationProjection(
            candidates: [anchor, reply].map { .init(sourceID: source, header: $0) },
            state: clearedState,
            now: now
        )

        #expect(clearedState.snoozes.isEmpty)
        #expect(!afterClear.isSnoozed(.init(sourceID: source, messageID: reply.id)))
    }

    @Test("messages without usable RFC links receive a limited message-only snooze")
    func unusableRFCLinksRemainMessageOnly() {
        let header = MessageHeader(
            id: "plain-message",
            threadID: "shared-provider-thread",
            folderID: "Inbox",
            from: Correspondent(email: "sender@example.org"),
            to: [],
            subject: "Same subject",
            snippet: "",
            date: now
        )
        let messageID = SourceMessageID(sourceID: source, messageID: header.id)
        let projection = LocalMessageWorkflowConversationProjection(
            candidates: [.init(sourceID: source, header: header)],
            state: .defaults,
            now: now
        )

        let result = LocalMessageWorkflowConversationMutationPolicy.snoozing(
            [.init(sourceID: source, header: header)],
            until: now.addingTimeInterval(60),
            now: now,
            projection: projection,
            in: .defaults
        )

        #expect(result.state.snoozes.count == 1)
        #expect(result.state.snoozes[0].conversationMetadata == nil)
        #expect(result.limitedMessageIDs == Set([messageID]))
    }

    @Test("reconciliation expands active seeds without changing dates or expired rules")
    func reconciliationExpandsActiveSeedsPreservingSchedule() {
        let parent = Self.header(id: "archive-parent", folder: "Archive", rfcID: "parent@example", references: ["seed@example"])
        let arrival = Self.header(id: "arrival", folder: "Inbox", rfcID: "arrival@example", inReplyTo: "parent@example")
        let active = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "anchor-not-cached"),
            wakeAt: now.addingTimeInterval(600),
            createdAt: now.addingTimeInterval(-20),
            conversationMetadata: .init(rfcIdentifiers: ["seed@example"])
        )
        let expired = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "expired"),
            wakeAt: now,
            createdAt: now.addingTimeInterval(-10),
            conversationMetadata: .init(rfcIdentifiers: ["other@example"])
        )
        let initialState = LocalMessageWorkflowState(snoozes: [active, expired])
        let projection = LocalMessageWorkflowConversationProjection(
            candidates: [parent, arrival].map { .init(sourceID: source, header: $0) },
            state: initialState,
            now: now
        )

        let reconciled = LocalMessageWorkflowConversationMutationPolicy.reconcilingActiveSnoozes(
            in: initialState,
            projection: projection,
            at: now
        )

        let expanded = reconciled.snoozes.first { $0.messageID == active.messageID }
        #expect(expanded?.conversationMetadata?.rfcIdentifiers == [
            "arrival@example", "parent@example", "seed@example"
        ])
        #expect(expanded?.createdAt == active.createdAt)
        #expect(expanded?.wakeAt == active.wakeAt)
        #expect(reconciled.snoozes.contains(expired))
    }

    private static func state(
        anchor: MessageHeader,
        source: MailSourceID,
        metadata: LocalMessageSnoozeConversationMetadata,
        wakeAt: Date
    ) -> LocalMessageWorkflowState {
        LocalMessageWorkflowState(snoozes: [LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: anchor.id),
            wakeAt: wakeAt,
            createdAt: Date(timeIntervalSince1970: 9000),
            conversationMetadata: metadata
        )])
    }

    private static func header(
        id: String,
        folder: String,
        rfcID: String,
        references: [String]? = nil,
        inReplyTo: String? = nil,
        sender: String = "sender@example.org"
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "shared-provider-thread",
            folderID: folder,
            from: Correspondent(email: sender),
            to: [],
            subject: "Same subject",
            snippet: "",
            date: Date(timeIntervalSince1970: 100),
            messageID: rfcID,
            inReplyTo: inReplyTo,
            references: references
        )
    }
}
