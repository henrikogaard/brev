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
import Foundation

struct LocalMessageWorkflowConversationSnoozeResult: Sendable {
    let state: LocalMessageWorkflowState
    let limitedMessageIDs: Set<SourceMessageID>
}

struct LocalMessageWorkflowSnoozeTransactionResult<Value> {
    let previousState: LocalMessageWorkflowState
    let state: LocalMessageWorkflowState
    let value: Value
}

enum LocalMessageWorkflowSnoozeTargetPolicy {
    static func areValid(
        _ candidates: [LocalMessageWorkflowCandidate],
        sourceID: MailSourceID,
        knownFolderIDs: Set<Folder.ID>
    ) -> Bool {
        !candidates.isEmpty && candidates.allSatisfy {
            $0.sourceID == sourceID && knownFolderIDs.contains($0.header.folderID)
        }
    }
}

struct LocalMessageWorkflowSnoozeReconciliationCoordinator {
    private(set) var generation = 0
    private(set) var isRunning = false
    private var needsAnotherPass = false

    mutating func request() -> Int? {
        guard !isRunning else {
            needsAnotherPass = true
            return nil
        }
        generation += 1
        isRunning = true
        return generation
    }

    mutating func finishPass(generation: Int) -> Bool {
        guard self.generation == generation, isRunning else { return false }
        guard needsAnotherPass else {
            isRunning = false
            return false
        }
        needsAnotherPass = false
        return true
    }

    mutating func cancel() {
        generation += 1
        isRunning = false
        needsAnotherPass = false
    }

    func owns(_ generation: Int) -> Bool {
        self.generation == generation
    }
}

struct LocalMessageWorkflowSnoozedCacheSourceSnapshot {
    let backendIdentity: ObjectIdentifier
    let folderIDs: Set<Folder.ID>
    let candidates: [LocalMessageWorkflowCandidate]
}

enum LocalMessageWorkflowSnoozedCachePolicy {
    static func mergingSuccessfulSources(
        _ successful: [MailSourceID: LocalMessageWorkflowSnoozedCacheSourceSnapshot],
        into existing: [MailSourceID: LocalMessageWorkflowSnoozedCacheSourceSnapshot],
        availableSources: Set<MailSourceID>
    ) -> [MailSourceID: LocalMessageWorkflowSnoozedCacheSourceSnapshot] {
        var snapshots = existing.filter { availableSources.contains($0.key) }
        snapshots.merge(successful.filter { availableSources.contains($0.key) }) { _, new in new }
        return snapshots
    }

    static func publishableCandidates(
        from snapshots: [MailSourceID: LocalMessageWorkflowSnoozedCacheSourceSnapshot],
        availableSources: Set<MailSourceID>,
        backendIdentities: [MailSourceID: ObjectIdentifier],
        folderIDs: [MailSourceID: Set<Folder.ID>]
    ) -> [LocalMessageWorkflowCandidate] {
        var candidates: [LocalMessageWorkflowCandidate] = []
        for sourceID in snapshots.keys.sorted(by: {
            "\($0.accountID)\u{0}\($0.mailboxID)" < "\($1.accountID)\u{0}\($1.mailboxID)"
        }) {
            guard let snapshot = snapshots[sourceID],
                  availableSources.contains(sourceID),
                  backendIdentities[sourceID] == snapshot.backendIdentity,
                  folderIDs[sourceID] == snapshot.folderIDs,
                  snapshot.candidates.allSatisfy({
                      $0.sourceID == sourceID && snapshot.folderIDs.contains($0.header.folderID)
                  }) else { continue }
            candidates.append(contentsOf: snapshot.candidates)
        }
        return candidates
    }
}

@MainActor
enum LocalMessageWorkflowSnoozeTransaction {
    static func applying<Value>(
        candidates: [LocalMessageWorkflowCandidate],
        affectedCandidates: [LocalMessageWorkflowCandidate],
        basedOn baselineState: LocalMessageWorkflowState,
        latestState: @MainActor () -> LocalMessageWorkflowState,
        mutation: (
            LocalMessageWorkflowState,
            LocalMessageWorkflowConversationProjection
        ) -> (state: LocalMessageWorkflowState, value: Value)
    ) -> LocalMessageWorkflowSnoozeTransactionResult<Value>? {
        let projection = LocalMessageWorkflowConversationProjection(
            candidates: candidates,
            state: baselineState
        )
        let currentState = latestState()
        let currentProjection = LocalMessageWorkflowConversationProjection(
            candidates: candidates,
            state: currentState
        )
        guard snoozesAreUnchanged(
            for: affectedCandidates,
            baselineState: baselineState,
            baselineProjection: projection,
            currentState: currentState,
            currentProjection: currentProjection
        ) else { return nil }

        let result = mutation(currentState, currentProjection)
        return .init(previousState: currentState, state: result.state, value: result.value)
    }

    static func reconciling<Value>(
        candidates: [LocalMessageWorkflowCandidate],
        rules: [LocalMessageSnooze],
        basedOn baselineState: LocalMessageWorkflowState,
        latestState: @MainActor () -> LocalMessageWorkflowState,
        mutation: (
            LocalMessageWorkflowState,
            LocalMessageWorkflowConversationProjection,
            Set<SourceMessageID>
        ) -> (state: LocalMessageWorkflowState, value: Value)
    ) -> LocalMessageWorkflowSnoozeTransactionResult<Value>? {
        let currentState = latestState()
        guard rules.allSatisfy({ rule in
            currentState.snoozes.contains { $0.messageID == rule.messageID && $0 == rule }
        }) else { return nil }

        let projection = LocalMessageWorkflowConversationProjection(
            candidates: candidates,
            state: baselineState
        )
        let currentProjection = LocalMessageWorkflowConversationProjection(
            candidates: candidates,
            state: currentState
        )
        let ruleIDs = Set(rules.map(\.messageID))
        let affectedCandidates = candidates.filter { candidate in
            let messageID = SourceMessageID(sourceID: candidate.sourceID, messageID: candidate.header.id)
            return projection.overlappingSnoozes(for: messageID, header: candidate.header, in: baselineState)
                .contains { ruleIDs.contains($0.messageID) }
        }
        guard snoozesAreUnchanged(
            for: affectedCandidates,
            baselineState: baselineState,
            baselineProjection: projection,
            currentState: currentState,
            currentProjection: currentProjection
        ) else { return nil }

        let result = mutation(currentState, currentProjection, ruleIDs)
        return .init(previousState: currentState, state: result.state, value: result.value)
    }

    static func reconcilingSources(
        candidatesBySource: [MailSourceID: [LocalMessageWorkflowCandidate]],
        rulesBySource: [MailSourceID: [LocalMessageSnooze]],
        basedOn baselineState: LocalMessageWorkflowState,
        latestState: @MainActor () -> LocalMessageWorkflowState,
        mutation: (
            LocalMessageWorkflowState,
            LocalMessageWorkflowConversationProjection,
            Set<SourceMessageID>
        ) -> (state: LocalMessageWorkflowState, value: Void)
    ) -> LocalMessageWorkflowSnoozeTransactionResult<Void>? {
        let previousState = latestState()
        var state = previousState
        let sources = candidatesBySource.keys.filter { rulesBySource[$0]?.isEmpty == false }.sorted {
            "\($0.accountID)\u{0}\($0.mailboxID)" < "\($1.accountID)\u{0}\($1.mailboxID)"
        }
        for sourceID in sources {
            guard let candidates = candidatesBySource[sourceID],
                  let rules = rulesBySource[sourceID],
                  let transaction = reconciling(
                      candidates: candidates,
                      rules: rules,
                      basedOn: baselineState,
                      latestState: { state },
                      mutation: mutation
                  ) else { continue }
            state = transaction.state
        }
        return .init(previousState: previousState, state: state, value: ())
    }

    private static func snoozesAreUnchanged(
        for candidates: [LocalMessageWorkflowCandidate],
        baselineState: LocalMessageWorkflowState,
        baselineProjection: LocalMessageWorkflowConversationProjection,
        currentState: LocalMessageWorkflowState,
        currentProjection: LocalMessageWorkflowConversationProjection
    ) -> Bool {
        candidates.allSatisfy { candidate in
            let messageID = SourceMessageID(sourceID: candidate.sourceID, messageID: candidate.header.id)
            let baseline = baselineProjection.overlappingSnoozes(
                for: messageID,
                header: candidate.header,
                in: baselineState
            )
            let current = currentProjection.overlappingSnoozes(
                for: messageID,
                header: candidate.header,
                in: currentState
            )
            return ordered(baseline) == ordered(current)
        }
    }

    private static func ordered(_ snoozes: [LocalMessageSnooze]) -> [LocalMessageSnooze] {
        snoozes.sorted { lhs, rhs in
            if lhs.messageID.sourceID.accountID != rhs.messageID.sourceID.accountID {
                return lhs.messageID.sourceID.accountID < rhs.messageID.sourceID.accountID
            }
            if lhs.messageID.sourceID.mailboxID != rhs.messageID.sourceID.mailboxID {
                return lhs.messageID.sourceID.mailboxID < rhs.messageID.sourceID.mailboxID
            }
            if lhs.messageID.messageID != rhs.messageID.messageID {
                return lhs.messageID.messageID < rhs.messageID.messageID
            }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.wakeAt < rhs.wakeAt
        }
    }
}

enum LocalMessageWorkflowSnoozeOwnership {
    static func isCurrentBackend(
        backendIdentity: ObjectIdentifier,
        sourceID: MailSourceID,
        in backends: [any MailBackend]
    ) -> Bool {
        guard let backend = backends.first(where: { $0.account.id == sourceID.accountID }) else { return false }
        return ObjectIdentifier(backend) == backendIdentity
    }
}

enum LocalMessageWorkflowConversationMutationPolicy {
    private enum ComponentKey: Hashable {
        case conversation(sourceID: MailSourceID, identifiers: [String])
        case message(SourceMessageID)
    }

    static func snoozing(
        _ candidates: [LocalMessageWorkflowCandidate],
        until wakeAt: Date,
        now: Date = Date(),
        projection: LocalMessageWorkflowConversationProjection,
        in initialState: LocalMessageWorkflowState
    ) -> LocalMessageWorkflowConversationSnoozeResult {
        var state = initialState
        var handledComponents: Set<ComponentKey> = []
        var limitedMessageIDs: Set<SourceMessageID> = []

        for candidate in candidates {
            let messageID = SourceMessageID(sourceID: candidate.sourceID, messageID: candidate.header.id)
            let metadata = projection.metadataForReschedule(
                from: messageID,
                header: candidate.header,
                state: initialState
            )
            let key = metadata.map {
                ComponentKey.conversation(sourceID: messageID.sourceID, identifiers: $0.rfcIdentifiers)
            } ?? .message(messageID)
            guard handledComponents.insert(key).inserted else { continue }

            let overlappingIDs = projection.overlappingSnoozes(
                for: messageID,
                header: candidate.header,
                in: initialState
            ).map(\.messageID)
            state = LocalMessageWorkflowStatePolicy.clearingSnooze(overlappingIDs, in: state)
            state = LocalMessageWorkflowStatePolicy.snoozing(
                messageID,
                until: wakeAt,
                now: now,
                conversationMetadata: metadata,
                in: state
            )
            if metadata == nil { limitedMessageIDs.insert(messageID) }
        }

        return LocalMessageWorkflowConversationSnoozeResult(
            state: state,
            limitedMessageIDs: limitedMessageIDs
        )
    }

    static func clearingSnooze(
        _ candidates: [LocalMessageWorkflowCandidate],
        projection: LocalMessageWorkflowConversationProjection,
        in state: LocalMessageWorkflowState
    ) -> LocalMessageWorkflowState {
        var snoozeIDs: Set<SourceMessageID> = []
        for candidate in candidates {
            let messageID = SourceMessageID(sourceID: candidate.sourceID, messageID: candidate.header.id)
            let overlappingSnoozes = projection.overlappingSnoozes(
                for: messageID,
                header: candidate.header,
                in: state
            )
            if overlappingSnoozes.contains(where: { $0.conversationMetadata != nil }) {
                snoozeIDs.formUnion(overlappingSnoozes.map(\.messageID))
            } else {
                snoozeIDs.insert(messageID)
            }
        }
        return LocalMessageWorkflowStatePolicy.clearingSnooze(Array(snoozeIDs), in: state)
    }

    static func reconcilingActiveSnoozes(
        in state: LocalMessageWorkflowState,
        projection: LocalMessageWorkflowConversationProjection,
        at now: Date = Date(),
        only ruleIDs: Set<SourceMessageID>? = nil
    ) -> LocalMessageWorkflowState {
        var snoozes = state.snoozes
        for index in snoozes.indices where snoozes[index].isActive(at: now)
            && (ruleIDs.map { $0.contains(snoozes[index].messageID) } ?? true)
            && snoozes[index].conversationMetadata?.rfcIdentifiers.isEmpty == false {
            guard let metadata = projection.expandedMetadata(for: snoozes[index]) else { continue }
            snoozes[index].conversationMetadata = metadata
        }
        return LocalMessageWorkflowState(
            snoozes: snoozes,
            doneMessages: state.doneMessages,
            notes: state.notes
        )
    }
}
