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
        let oldSnooze = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: anchor.id),
            wakeAt: now.addingTimeInterval(60),
            createdAt: now,
            conversationMetadata: .init(rfcIdentifiers: ["root@example", "reused@example"])
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

    @Test("persisted seed sets connect evicted bridge candidates")
    func persistedSeedsConnectEvictedBridges() {
        let left = Self.header(id: "left", folder: "Inbox", rfcID: "a@example")
        let right = Self.header(id: "right", folder: "Sent", rfcID: "c@example")
        let older = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "old-rule"),
            wakeAt: now.addingTimeInterval(900), createdAt: now.addingTimeInterval(-20),
            conversationMetadata: .init(rfcIdentifiers: ["a@example", "b@example"])
        )
        let newer = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "new-rule"),
            wakeAt: now.addingTimeInterval(300), createdAt: now.addingTimeInterval(-10),
            conversationMetadata: .init(rfcIdentifiers: ["b@example", "c@example"])
        )
        let state = LocalMessageWorkflowState(snoozes: [older, newer])
        let candidates = [left, right].map { LocalMessageWorkflowCandidate(sourceID: source, header: $0) }
        let projection = LocalMessageWorkflowConversationProjection(candidates: candidates, state: state, now: now)
        let leftID = SourceMessageID(sourceID: source, messageID: left.id)

        #expect(projection.snooze(for: leftID, header: left) == newer)
        #expect(projection.snooze(for: .init(sourceID: source, messageID: right.id), header: right) == newer)
        #expect(projection.overlappingSnoozes(for: leftID, header: left, in: state).count == 2)
        let rescheduled = LocalMessageWorkflowConversationMutationPolicy.snoozing(
            [.init(sourceID: source, header: left)],
            until: now.addingTimeInterval(1200), now: now, projection: projection, in: state
        )
        #expect(rescheduled.state.snoozes.count == 1)
        #expect(rescheduled.state.snoozes[0].conversationMetadata?.rfcIdentifiers == [
            "a@example", "b@example", "c@example"
        ])
        #expect(LocalMessageWorkflowConversationMutationPolicy.clearingSnooze(
            [.init(sourceID: source, header: right)], projection: projection, in: state
        ).snoozes.isEmpty)
    }

    @Test("a new cached reply bridges independently snoozed persisted branches")
    func cachedReplyBridgesPersistedRules() {
        let reply = Self.header(id: "bridge", folder: "Archive", rfcID: "reply@example", references: ["b@example", "c@example"])
        let older = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "old-rule"),
            wakeAt: now.addingTimeInterval(900), createdAt: now.addingTimeInterval(-20),
            conversationMetadata: .init(rfcIdentifiers: ["a@example", "b@example"])
        )
        let newer = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "new-rule"),
            wakeAt: now.addingTimeInterval(300), createdAt: now.addingTimeInterval(-10),
            conversationMetadata: .init(rfcIdentifiers: ["c@example", "d@example"])
        )
        let state = LocalMessageWorkflowState(snoozes: [older, newer])
        let projection = LocalMessageWorkflowConversationProjection(
            candidates: [.init(sourceID: source, header: reply)], state: state, now: now
        )

        #expect(projection.snooze(for: .init(sourceID: source, messageID: reply.id), header: reply) == newer)
        #expect(projection.overlappingSnoozes(
            for: .init(sourceID: source, messageID: reply.id), header: reply, in: state
        ).count == 2)
    }

    @Test("overlapping persisted seed chains are order independent with multiple cached links")
    func overlappingPersistedSeedChainsAreOrderIndependent() {
        let left = Self.header(id: "left", folder: "Inbox", rfcID: "a@example")
        let bridge = Self.header(id: "bridge", folder: "Archive", rfcID: "x@example", references: ["b@example", "c@example"])
        let arrival = Self.header(id: "arrival", folder: "Sent", rfcID: "y@example", inReplyTo: "x@example")
        let right = Self.header(id: "right", folder: "Inbox", rfcID: "d@example")
        let rules = [
            LocalMessageSnooze(
                messageID: .init(sourceID: source, messageID: "ab"),
                wakeAt: now,
                createdAt: now.addingTimeInterval(-30),
                conversationMetadata: .init(rfcIdentifiers: ["a@example", "b@example"])
            ),
            LocalMessageSnooze(
                messageID: .init(sourceID: source, messageID: "cd"),
                wakeAt: now,
                createdAt: now.addingTimeInterval(-20),
                conversationMetadata: .init(rfcIdentifiers: ["c@example", "d@example"])
            ),
            LocalMessageSnooze(
                messageID: .init(sourceID: source, messageID: "bc"),
                wakeAt: now,
                createdAt: now.addingTimeInterval(-10),
                conversationMetadata: .init(rfcIdentifiers: ["b@example", "c@example"])
            )
        ]
        let headers = [left, bridge, arrival, right]
        let newest = rules[2]
        let first = LocalMessageWorkflowConversationProjection(
            candidates: headers.map { .init(sourceID: source, header: $0) },
            state: .init(snoozes: rules), now: now
        )
        let reversed = LocalMessageWorkflowConversationProjection(
            candidates: headers.reversed().map { .init(sourceID: source, header: $0) },
            state: .init(snoozes: rules.reversed()), now: now
        )

        for header in headers {
            let id = SourceMessageID(sourceID: source, messageID: header.id)
            #expect(first.snooze(for: id, header: header) == newest)
            #expect(reversed.snooze(for: id, header: header) == newest)
        }
    }

    @Test("reconciliation revokes all known-conflicting persisted seeds")
    func reconciliationRevokesFullyConflictingSeeds() {
        let first = Self.header(id: "first", folder: "Inbox", rfcID: "shared@example", sender: "first@example")
        let second = Self.header(id: "second", folder: "Archive", rfcID: "shared@example", sender: "second@example")
        let snooze = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "evicted-anchor"),
            wakeAt: now.addingTimeInterval(600), createdAt: now.addingTimeInterval(-5),
            conversationMetadata: .init(rfcIdentifiers: ["shared@example"])
        )
        let state = LocalMessageWorkflowState(snoozes: [snooze])
        let projection = LocalMessageWorkflowConversationProjection(
            candidates: [first, second].map { .init(sourceID: source, header: $0) }, state: state, now: now
        )
        let reconciled = LocalMessageWorkflowConversationMutationPolicy.reconcilingActiveSnoozes(
            in: state, projection: projection, at: now
        )
        #expect(reconciled.snoozes[0].conversationMetadata?.rfcIdentifiers == [])
        let loneCopy = LocalMessageWorkflowConversationProjection(
            candidates: [.init(sourceID: source, header: first)], state: reconciled, now: now
        )
        #expect(!loneCopy.isSnoozed(.init(sourceID: source, messageID: first.id), header: first))
    }

    @Test("fresh transaction state preserves unrelated injected-store edits")
    @MainActor
    func freshTransactionPreservesUnrelatedInjectedStoreEdits() throws {
        let suiteName = "LocalMessageWorkflowSnoozeTransaction-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let anchor = Self.header(id: "anchor", folder: "Inbox", rfcID: "anchor@example")
        let candidate = LocalMessageWorkflowCandidate(sourceID: source, header: anchor)
        let messageID = SourceMessageID(sourceID: source, messageID: anchor.id)
        let originalSnooze = LocalMessageSnooze(
            messageID: messageID,
            wakeAt: now.addingTimeInterval(300),
            createdAt: now,
            conversationMetadata: .init(rfcIdentifiers: ["anchor@example"])
        )
        let staleViewState = LocalMessageWorkflowState(snoozes: [originalSnooze])
        LocalMessageWorkflowStateStorage.save(staleViewState, to: defaults)
        let done = LocalMessageDone(messageID: .init(sourceID: otherSource, messageID: "new-done"))
        let note = LocalMessageNote(messageID: .init(sourceID: otherSource, messageID: "new-note"), body: "external edit")
        let latestPersistedState = LocalMessageWorkflowState(
            snoozes: [originalSnooze], doneMessages: [done], notes: [note]
        )
        LocalMessageWorkflowStateStorage.save(latestPersistedState, to: defaults)

        let transaction = LocalMessageWorkflowSnoozeTransaction.applying(
            candidates: [candidate],
            affectedCandidates: [candidate],
            basedOn: staleViewState,
            latestState: { LocalMessageWorkflowStateStorage.load(from: defaults) }
        ) { state, projection in
            let result = LocalMessageWorkflowConversationMutationPolicy.snoozing(
                [candidate], until: now.addingTimeInterval(900), now: now, projection: projection, in: state
            )
            return (state: result.state, value: result)
        }

        #expect(staleViewState == LocalMessageWorkflowState(snoozes: [originalSnooze]))
        #expect(transaction?.previousState == latestPersistedState)
        #expect(transaction?.state.doneMessages == [done])
        #expect(transaction?.state.notes == [note])
        if let committedState = transaction?.state {
            LocalMessageWorkflowStateStorage.save(committedState, to: defaults)
        }
        #expect(LocalMessageWorkflowStateStorage.load(from: defaults).doneMessages == [done])
        #expect(LocalMessageWorkflowStateStorage.load(from: defaults).notes == [note])
    }

    @Test("fresh transactions reject removed and rescheduled overlapping snoozes")
    @MainActor
    func freshTransactionRejectsRemovedOrRescheduledSnooze() throws {
        let suiteName = "LocalMessageWorkflowSnoozeRuleConflict-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let anchor = Self.header(id: "anchor", folder: "Inbox", rfcID: "anchor@example")
        let candidate = LocalMessageWorkflowCandidate(sourceID: source, header: anchor)
        let snooze = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "old-rule"),
            wakeAt: now.addingTimeInterval(300), createdAt: now,
            conversationMetadata: .init(rfcIdentifiers: ["anchor@example"])
        )
        let baseline = LocalMessageWorkflowState(snoozes: [snooze])
        let rescheduledSnooze = LocalMessageSnooze(
            messageID: snooze.messageID,
            wakeAt: now.addingTimeInterval(1200), createdAt: now.addingTimeInterval(1),
            conversationMetadata: snooze.conversationMetadata
        )

        for currentState in [LocalMessageWorkflowState(), LocalMessageWorkflowState(snoozes: [rescheduledSnooze])] {
            LocalMessageWorkflowStateStorage.save(currentState, to: defaults)
            let transaction = LocalMessageWorkflowSnoozeTransaction.applying(
                candidates: [candidate],
                affectedCandidates: [candidate],
                basedOn: baseline,
                latestState: { LocalMessageWorkflowStateStorage.load(from: defaults) }
            ) { state, projection in
                let result = LocalMessageWorkflowConversationMutationPolicy.snoozing(
                    [candidate], until: now.addingTimeInterval(900), now: now, projection: projection, in: state
                )
                return (state: result.state, value: result)
            }

            #expect(transaction.map { _ in false } ?? true)
            #expect(LocalMessageWorkflowStateStorage.load(from: defaults) == currentState)
        }
    }

    @Test("fresh reconciliation preserves external edits and expands only unchanged rules")
    @MainActor
    func freshReconciliationPreservesExternalEdits() throws {
        let suiteName = "LocalMessageWorkflowSnoozeReconciliation-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let rule = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "old-rule"),
            wakeAt: now.addingTimeInterval(300), createdAt: now,
            conversationMetadata: .init(rfcIdentifiers: ["ancestor@example"])
        )
        let unrelatedSnooze = LocalMessageSnooze(
            messageID: .init(sourceID: otherSource, messageID: "other-rule"),
            wakeAt: now.addingTimeInterval(300), createdAt: now,
            conversationMetadata: .init(rfcIdentifiers: ["other@example"])
        )
        let staleViewState = LocalMessageWorkflowState(snoozes: [rule])
        LocalMessageWorkflowStateStorage.save(staleViewState, to: defaults)
        let done = LocalMessageDone(messageID: .init(sourceID: otherSource, messageID: "new-done"))
        let note = LocalMessageNote(messageID: .init(sourceID: otherSource, messageID: "new-note"), body: "external edit")
        let latestPersistedState = LocalMessageWorkflowState(
            snoozes: [rule, unrelatedSnooze], doneMessages: [done], notes: [note]
        )
        LocalMessageWorkflowStateStorage.save(latestPersistedState, to: defaults)
        let bridge = Self.header(id: "bridge", folder: "Archive", rfcID: "bridge@example", references: ["ancestor@example"])
        let candidates = [LocalMessageWorkflowCandidate(sourceID: source, header: bridge)]

        let transaction = LocalMessageWorkflowSnoozeTransaction.reconciling(
            candidates: candidates,
            rules: [rule],
            basedOn: staleViewState,
            latestState: { LocalMessageWorkflowStateStorage.load(from: defaults) }
        ) { state, projection, ruleIDs in
            let reconciled = LocalMessageWorkflowConversationMutationPolicy.reconcilingActiveSnoozes(
                in: state, projection: projection, at: now, only: ruleIDs
            )
            return (state: reconciled, value: ())
        }

        #expect(transaction?.previousState == latestPersistedState)
        #expect(transaction?.state.doneMessages == [done])
        #expect(transaction?.state.notes == [note])
        #expect(transaction?.state.snoozes.contains(unrelatedSnooze) == true)
        #expect(transaction?.state.snoozes.first(where: { $0.messageID == rule.messageID })?.conversationMetadata?
            .rfcIdentifiers == [
                "ancestor@example",
                "bridge@example"
            ])

        let rescheduledRule = LocalMessageSnooze(
            messageID: rule.messageID,
            wakeAt: now.addingTimeInterval(1200),
            createdAt: now.addingTimeInterval(1),
            conversationMetadata: rule.conversationMetadata
        )
        let rescheduledState = LocalMessageWorkflowState(
            snoozes: [rescheduledRule, unrelatedSnooze], doneMessages: [done], notes: [note]
        )
        LocalMessageWorkflowStateStorage.save(rescheduledState, to: defaults)
        let staleReconciliation = LocalMessageWorkflowSnoozeTransaction.reconciling(
            candidates: candidates,
            rules: [rule],
            basedOn: staleViewState,
            latestState: { LocalMessageWorkflowStateStorage.load(from: defaults) }
        ) { state, projection, ruleIDs in
            let reconciled = LocalMessageWorkflowConversationMutationPolicy.reconcilingActiveSnoozes(
                in: state, projection: projection, at: now, only: ruleIDs
            )
            return (state: reconciled, value: ())
        }
        #expect(staleReconciliation.map { _ in false } ?? true)
        #expect(LocalMessageWorkflowStateStorage.load(from: defaults) == rescheduledState)
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

    @Test("reconciliation requests coalesce and lifetime cancellation is generation-owned")
    func reconciliationCoordinatorCoalescesAndCancelsByGeneration() {
        var coordinator = LocalMessageWorkflowSnoozeReconciliationCoordinator()
        let generation = coordinator.request()!
        for _ in 0 ..< 20 {
            let overlappingRequest = coordinator.request()
            #expect(overlappingRequest == nil)
        }
        let needsFollowUp = coordinator.finishPass(generation: generation)
        #expect(needsFollowUp)
        let finished = coordinator.finishPass(generation: generation)
        #expect(!finished)

        let staleGeneration = coordinator.request()!
        let canceledFollowUp = coordinator.request()
        #expect(canceledFollowUp == nil)
        coordinator.cancel()
        let currentGeneration = coordinator.request()!
        #expect(!coordinator.owns(staleGeneration))
        #expect(coordinator.owns(currentGeneration))
        let staleCompletion = coordinator.finishPass(generation: staleGeneration)
        #expect(!staleCompletion)
        #expect(coordinator.owns(currentGeneration))
    }

    @Test("a changed source rule does not block healthy-source reconciliation")
    @MainActor
    func reconciliationSourcesAreIndependent() throws {
        let anchor = Self.header(id: "source-anchor", folder: "Inbox", rfcID: "seed@example")
        let arrival = Self.header(
            id: "healthy-arrival",
            folder: "Archive",
            rfcID: "new@example",
            inReplyTo: "healthy-seed@example"
        )
        let sourceRule = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "source-anchor"),
            wakeAt: now.addingTimeInterval(600),
            createdAt: now,
            conversationMetadata: .init(rfcIdentifiers: ["seed@example"])
        )
        let healthyRule = LocalMessageSnooze(
            messageID: .init(sourceID: otherSource, messageID: "healthy-anchor"),
            wakeAt: now.addingTimeInterval(600),
            createdAt: now,
            conversationMetadata: .init(rfcIdentifiers: ["healthy-seed@example"])
        )
        let baseline = LocalMessageWorkflowState(snoozes: [sourceRule, healthyRule])
        let rescheduled = LocalMessageSnooze(
            messageID: sourceRule.messageID,
            wakeAt: sourceRule.wakeAt.addingTimeInterval(30),
            createdAt: sourceRule.createdAt,
            conversationMetadata: sourceRule.conversationMetadata
        )
        let latest = LocalMessageWorkflowState(snoozes: [rescheduled, healthyRule])
        let result = try #require(LocalMessageWorkflowSnoozeTransaction.reconcilingSources(
            candidatesBySource: [
                source: [.init(sourceID: source, header: anchor)],
                otherSource: [.init(sourceID: otherSource, header: arrival)],
            ],
            rulesBySource: [source: [sourceRule], otherSource: [healthyRule]],
            basedOn: baseline,
            latestState: { latest },
            mutation: { state, projection, ruleIDs in
                (
                    state: LocalMessageWorkflowConversationMutationPolicy.reconcilingActiveSnoozes(
                        in: state, projection: projection, at: now, only: ruleIDs
                    ),
                    value: ()
                )
            }
        ))
        #expect(result.state.snoozes.contains(rescheduled))
        #expect(result.state.snoozes.first { $0.messageID.sourceID == otherSource }?.conversationMetadata?.rfcIdentifiers
            .contains("new@example") == true)
    }

    @Test("Snoozed cache snapshots preserve failed sources and reject replaced owners")
    func snoozedCacheSnapshotsMergeAndValidateOwners() {
        let oldBackend = NSObject()
        let healthyBackend = NSObject()
        let replacementBackend = NSObject()
        let oldCandidate = Self.header(id: "old", folder: "Inbox", rfcID: "old@example")
        let newCandidate = Self.header(id: "new", folder: "Inbox", rfcID: "new@example")
        let healthyCandidate = Self.header(id: "healthy", folder: "Inbox", rfcID: "healthy@example")
        let previous: [MailSourceID: LocalMessageWorkflowSnoozedCacheSourceSnapshot] = [
            source: .init(
                backendIdentity: ObjectIdentifier(oldBackend),
                folderIDs: ["Inbox"],
                candidates: [.init(sourceID: source, header: oldCandidate)]
            ),
            otherSource: .init(
                backendIdentity: ObjectIdentifier(healthyBackend),
                folderIDs: ["Inbox"],
                candidates: [.init(sourceID: otherSource, header: healthyCandidate)]
            ),
        ]
        let refreshed = LocalMessageWorkflowSnoozedCachePolicy.mergingSuccessfulSources(
            [source: .init(
                backendIdentity: ObjectIdentifier(oldBackend),
                folderIDs: ["Inbox"],
                candidates: [.init(sourceID: source, header: newCandidate)]
            )],
            into: previous,
            availableSources: [source, otherSource]
        )
        let candidates = LocalMessageWorkflowSnoozedCachePolicy.publishableCandidates(
            from: refreshed,
            availableSources: [source, otherSource],
            backendIdentities: [source: ObjectIdentifier(replacementBackend), otherSource: ObjectIdentifier(healthyBackend)],
            folderIDs: [source: ["Inbox"], otherSource: ["Inbox"]]
        )
        #expect(Set(candidates.map(\.header.id)) == ["healthy"])
        let updated = LocalMessageWorkflowSnoozedCachePolicy.mergingSuccessfulSources(
            [source: .init(
                backendIdentity: ObjectIdentifier(replacementBackend),
                folderIDs: ["Inbox"],
                candidates: [.init(sourceID: source, header: newCandidate)]
            )],
            into: refreshed,
            availableSources: [source, otherSource]
        )
        #expect(Set(LocalMessageWorkflowSnoozedCachePolicy.publishableCandidates(
            from: updated,
            availableSources: [source, otherSource],
            backendIdentities: [source: ObjectIdentifier(replacementBackend), otherSource: ObjectIdentifier(healthyBackend)],
            folderIDs: [source: ["Inbox"], otherSource: ["Inbox"]]
        ).map(\.header.id)) == ["new", "healthy"])

        let revokedAfterScan = LocalMessageWorkflowSnoozedCachePolicy.mergingSuccessfulSources(
            [source: .init(
                backendIdentity: ObjectIdentifier(replacementBackend),
                folderIDs: ["Inbox"],
                candidates: [.init(sourceID: source, header: newCandidate)]
            )],
            into: updated,
            availableSources: [otherSource]
        )
        #expect(revokedAfterScan[source] == nil)
        #expect(Set(revokedAfterScan[otherSource]?.candidates.map(\.header.id) ?? []) == ["healthy"])
    }

    @Test("cached bridge candidates reproject after another-window snooze changes")
    func snoozedCandidatesReprojectFromCompleteSnapshot() {
        let parent = Self.header(id: "cached-parent", folder: "Archive", rfcID: "parent@example")
        let arrival = Self.header(id: "new-arrival", folder: "Inbox", rfcID: "arrival@example", inReplyTo: "parent@example")
        let candidates = [parent, arrival].map { LocalMessageWorkflowCandidate(sourceID: source, header: $0) }
        let rule = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "anchor-not-loaded"),
            wakeAt: now.addingTimeInterval(600),
            createdAt: now,
            conversationMetadata: .init(rfcIdentifiers: ["parent@example"])
        )
        let snoozed = LocalMessageWorkflowConversationProjection(
            candidates: candidates,
            state: LocalMessageWorkflowState(snoozes: [rule]),
            now: now
        )
        #expect(snoozed.isSnoozed(.init(sourceID: source, messageID: "new-arrival"), header: arrival, at: now))
        let unsnoozed = LocalMessageWorkflowConversationProjection(candidates: candidates, state: .defaults, now: now)
        #expect(!unsnoozed.isSnoozed(.init(sourceID: source, messageID: "new-arrival"), header: arrival, at: now))
    }

    @Test("detached reader candidate selection preserves explicit source ownership")
    func detachedReaderCandidatesStaySourceOwned() {
        let targetHeader = Self.header(id: "target", folder: "Inbox", rfcID: "target@example")
        let foreignHeader = Self.header(id: "foreign", folder: "Inbox", rfcID: "foreign@example")
        let candidates = LocalMessageWorkflowReaderCandidatePolicy.candidates(
            targetSourceID: otherSource,
            targetHeader: targetHeader,
            selectedSourceID: source,
            loadedHeaders: [foreignHeader],
            relatedMembers: [ConversationMember(sourceID: source, header: foreignHeader)]
        )
        #expect(candidates.count == 1)
        #expect(candidates[0].sourceID == otherSource)
        #expect(candidates[0].header.id == targetHeader.id)
    }

    @Test("search snooze targets may come from any known source folder")
    func snoozeTargetValidationAllowsKnownSearchFolders() {
        let searchHit = Self.header(id: "archive-hit", folder: "Archive", rfcID: "archive@example")
        let candidate = LocalMessageWorkflowCandidate(sourceID: source, header: searchHit)
        #expect(LocalMessageWorkflowSnoozeTargetPolicy.areValid(
            [candidate], sourceID: source, knownFolderIDs: ["Inbox", "Archive"]
        ))
        #expect(!LocalMessageWorkflowSnoozeTargetPolicy.areValid(
            [candidate], sourceID: source, knownFolderIDs: ["Inbox"]
        ))
    }

    @Test("large linked conversation projects every seeded member")
    func largeLinkedConversationProjectsEverySeededMember() {
        let count = 512
        let headers = (0 ..< count).map { index in
            Self.header(
                id: "large-\(index)",
                folder: "Inbox",
                rfcID: "member-\(index)@example.org",
                inReplyTo: index == 0 ? nil : "member-\(index - 1)@example.org"
            )
        }
        let rule = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "large-anchor"),
            wakeAt: now.addingTimeInterval(600),
            createdAt: now,
            conversationMetadata: .init(rfcIdentifiers: (0 ..< count).map { "member-\($0)@example.org" })
        )
        let projection = LocalMessageWorkflowConversationProjection(
            candidates: headers.map { .init(sourceID: source, header: $0) },
            state: LocalMessageWorkflowState(snoozes: [rule]),
            now: now
        )

        for index in [0, count / 2, count - 1] {
            #expect(projection.isSnoozed(
                .init(sourceID: source, messageID: headers[index].id),
                header: headers[index],
                at: now
            ))
        }
    }

    @Test("cached conversation projection invalidates for state and candidate changes")
    func conversationProjectionCacheInvalidatesForStateAndCandidates() {
        let parent = Self.header(id: "cached-parent", folder: "Inbox", rfcID: "parent@example.org")
        let reply = Self.header(
            id: "cached-reply",
            folder: "Inbox",
            rfcID: "reply@example.org",
            inReplyTo: "parent@example.org"
        )
        let cache = LocalMessageWorkflowConversationProjectionCache()
        let initialHeaders = [parent]
        let initial = cache.projection(for: initialHeaders, sourceID: source, state: .defaults, now: now)
        #expect(!initial.isSnoozed(.init(sourceID: source, messageID: parent.id), header: parent, at: now))

        let rule = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "cache-anchor"),
            wakeAt: now.addingTimeInterval(600),
            createdAt: now,
            conversationMetadata: .init(rfcIdentifiers: ["parent@example.org"])
        )
        let state = LocalMessageWorkflowState(snoozes: [rule])
        let updatedState = cache.projection(for: initialHeaders, sourceID: source, state: state, now: now)
        #expect(updatedState.isSnoozed(.init(sourceID: source, messageID: parent.id), header: parent, at: now))

        let expandedHeaders = [parent, reply]
        let expanded = cache.projection(for: expandedHeaders, sourceID: source, state: state, now: now)
        #expect(expanded.isSnoozed(.init(sourceID: source, messageID: reply.id), header: reply, at: now))

        let folder = Folder(id: "Inbox", name: "Inbox", role: .inbox)
        let parentItem = UnifiedInboxItem(
            sourceID: source,
            folder: folder,
            header: parent,
            sourceTitle: "Personal",
            sourceSubtitle: "",
            archiveFolder: folder
        )
        let replyItem = UnifiedInboxItem(
            sourceID: source,
            folder: folder,
            header: reply,
            sourceTitle: "Personal",
            sourceSubtitle: "",
            archiveFolder: folder
        )
        let itemCache = LocalMessageWorkflowConversationProjectionCache()
        let initialItems = [parentItem]
        let initialItemProjection = itemCache.projection(for: initialItems, state: .defaults, now: now)
        #expect(!initialItemProjection.isSnoozed(.init(sourceID: source, messageID: parent.id), header: parent, at: now))
        let updatedItemProjection = itemCache.projection(for: initialItems, state: state, now: now)
        #expect(updatedItemProjection.isSnoozed(.init(sourceID: source, messageID: parent.id), header: parent, at: now))
        let expandedItems = [parentItem, replyItem]
        let expandedItemProjection = itemCache.projection(for: expandedItems, state: state, now: now)
        #expect(expandedItemProjection.isSnoozed(.init(sourceID: source, messageID: reply.id), header: reply, at: now))
    }

    @Test("visibility and wake policies reuse a prebuilt complete projection")
    func visibilityAndWakePoliciesReusePrebuiltProjection() {
        let parent = Self.header(id: "reuse-parent", folder: "Inbox", rfcID: "reuse-a@example.org")
        let bridge = Self.header(
            id: "reuse-bridge",
            folder: "Inbox",
            rfcID: "reuse-b@example.org",
            inReplyTo: "reuse-a@example.org"
        )
        let reply = Self.header(
            id: "reuse-reply",
            folder: "Inbox",
            rfcID: "reuse-c@example.org",
            inReplyTo: "reuse-b@example.org"
        )
        let candidates = [parent, bridge, reply].map { LocalMessageWorkflowCandidate(sourceID: source, header: $0) }
        let activeRule = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "active-reuse-anchor"),
            wakeAt: now.addingTimeInterval(600),
            createdAt: now,
            conversationMetadata: .init(rfcIdentifiers: ["reuse-a@example.org"])
        )
        let activeProjection = LocalMessageWorkflowConversationProjection(
            candidates: candidates,
            state: LocalMessageWorkflowState(snoozes: [activeRule]),
            now: now
        )
        #expect(LocalMessageWorkflowVisibilityPolicy.headers(
            [reply],
            candidates: [reply],
            sourceID: source,
            mode: .snoozed,
            state: LocalMessageWorkflowState(snoozes: [activeRule]),
            now: now,
            projection: activeProjection
        ) == [reply])
        let folder = Folder(id: "Inbox", name: "Inbox", role: .inbox)
        let replyItem = UnifiedInboxItem(
            sourceID: source,
            folder: folder,
            header: reply,
            sourceTitle: "Personal",
            sourceSubtitle: "",
            archiveFolder: folder
        )
        #expect(LocalMessageWorkflowVisibilityPolicy.snoozedCacheItems(
            [replyItem],
            state: LocalMessageWorkflowState(snoozes: [activeRule]),
            now: now,
            projection: activeProjection
        ).map(\.header.id) == [reply.id])

        let expiredRule = LocalMessageSnooze(
            messageID: .init(sourceID: source, messageID: "expired-reuse-anchor"),
            wakeAt: now.addingTimeInterval(-60),
            createdAt: now,
            conversationMetadata: .init(rfcIdentifiers: ["reuse-a@example.org"])
        )
        let expiredProjection = LocalMessageWorkflowConversationProjection(
            candidates: candidates,
            state: LocalMessageWorkflowState(snoozes: [expiredRule]),
            now: now
        )
        let replyID = SourceMessageID(sourceID: source, messageID: reply.id)
        let overrides = MessageListSnoozeWakePolicy.effectiveDateOverrides(
            for: [.init(sourceMessageID: replyID, headerDate: reply.date, threadID: nil, header: reply)],
            snoozes: [expiredRule],
            now: now,
            projection: expiredProjection
        )
        #expect(overrides[replyID] == expiredRule.wakeAt)
    }

    @Test("invalid and empty canonical seeds are rejected")
    func canonicalSeedValidationRejectsInvalidAndEmptyMetadata() {
        #expect(LocalMessageWorkflowConversationProjection.validSeeds(.init(rfcIdentifiers: [])) == nil)
        #expect(LocalMessageWorkflowConversationProjection.validSeeds(.init(rfcIdentifiers: ["invalid id"])) == nil)
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
