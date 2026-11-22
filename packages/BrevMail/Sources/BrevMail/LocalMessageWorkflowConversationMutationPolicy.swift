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
        let overlappingIDs = Set(candidates.flatMap { candidate in
            let messageID = SourceMessageID(sourceID: candidate.sourceID, messageID: candidate.header.id)
            return projection.overlappingSnoozes(
                for: messageID,
                header: candidate.header,
                in: state
            ).map(\.messageID)
        })
        return LocalMessageWorkflowStatePolicy.clearingSnooze(Array(overlappingIDs), in: state)
    }

    static func reconcilingActiveSnoozes(
        in state: LocalMessageWorkflowState,
        projection: LocalMessageWorkflowConversationProjection,
        at now: Date = Date()
    ) -> LocalMessageWorkflowState {
        var snoozes = state.snoozes
        for index in snoozes.indices where snoozes[index].isActive(at: now)
            && snoozes[index].conversationMetadata != nil {
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
