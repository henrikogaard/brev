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

struct LocalMessageWorkflowCandidate: Sendable {
    let sourceID: MailSourceID
    let header: MessageHeader
}

struct LocalMessageWorkflowConversationProjection: Sendable {
    private struct CandidateKey: Hashable {
        let sourceID: MailSourceID
        let folderID: String
        let messageID: String

        init(sourceID: MailSourceID, header: MessageHeader) {
            self.sourceID = sourceID
            folderID = header.folderID
            messageID = header.id
        }

        var sourceMessageID: SourceMessageID {
            SourceMessageID(sourceID: sourceID, messageID: messageID)
        }
    }

    private struct Fingerprint: Hashable {
        let sender: String
        let recipients: [String]
        let date: Date
        let subject: String

        init(_ header: MessageHeader) {
            sender = header.from.email.lowercased()
            recipients = header.to.map { $0.email.lowercased() }.sorted()
            date = header.date
            subject = header.subject
        }
    }

    private struct Component {
        var candidateKeys: Set<CandidateKey> = []
        var messageIDs: Set<SourceMessageID> = []
        var rfcIdentifiers: Set<String> = []
        var conflictingIdentifiers: Set<String> = []
    }

    private let effectiveSnoozes: [CandidateKey: LocalMessageSnooze]
    private let legacySnoozes: [SourceMessageID: LocalMessageSnooze]
    private let componentsByCandidateKey: [CandidateKey: Component]
    private let candidateKeysByMessageID: [SourceMessageID: Set<CandidateKey>]
    private let componentsBySource: [MailSourceID: [Component]]
    private let now: Date

    init(
        candidates: [LocalMessageWorkflowCandidate],
        state: LocalMessageWorkflowState,
        now: Date = Date()
    ) {
        self.now = now
        var componentsByCandidateKey: [CandidateKey: Component] = [:]
        var candidateKeysByMessageID: [SourceMessageID: Set<CandidateKey>] = [:]
        var componentsBySource: [MailSourceID: [Component]] = [:]
        var effectiveSnoozes: [CandidateKey: LocalMessageSnooze] = [:]
        var legacySnoozes: [SourceMessageID: LocalMessageSnooze] = [:]

        let candidatesBySource = Dictionary(grouping: candidates, by: \.sourceID)
        for (sourceID, sourceCandidates) in candidatesBySource {
            let uniqueCandidates = Dictionary(
                sourceCandidates.map { (CandidateKey(sourceID: sourceID, header: $0.header), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let entries = Array(uniqueCandidates.values)
            let links = entries.map(Self.rfcLinks)
            var owners: [String: Set<Fingerprint>] = [:]
            for entry in entries {
                guard let own = Self.explicitOwnIdentifier(entry.header) else { continue }
                owners[own, default: []].insert(Fingerprint(entry.header))
            }
            let conflicting = Set(owners.compactMap { identifier, fingerprints in
                fingerprints.count > 1 ? identifier : nil
            })

            var parent = Array(entries.indices)
            func find(_ index: Int) -> Int {
                var current = index
                while parent[current] != current {
                    parent[current] = parent[parent[current]]
                    current = parent[current]
                }
                return current
            }
            func unite(_ left: Int, _ right: Int) {
                let leftRoot = find(left)
                let rightRoot = find(right)
                if leftRoot != rightRoot { parent[rightRoot] = leftRoot }
            }

            var firstIndexByIdentifier: [String: Int] = [:]
            for (index, identifiers) in links.enumerated() {
                for identifier in identifiers where !conflicting.contains(identifier) {
                    if let firstIndex = firstIndexByIdentifier[identifier] {
                        unite(index, firstIndex)
                    } else {
                        firstIndexByIdentifier[identifier] = index
                    }
                }
            }

            var components: [Int: Component] = [:]
            for index in entries.indices {
                let root = find(index)
                let candidateKey = CandidateKey(sourceID: sourceID, header: entries[index].header)
                let messageID = candidateKey.sourceMessageID
                components[root, default: Component()].candidateKeys.insert(candidateKey)
                components[root, default: Component()].messageIDs.insert(messageID)
                components[root, default: Component()].rfcIdentifiers.formUnion(
                    links[index].subtracting(conflicting)
                )
                components[root, default: Component()].conflictingIdentifiers.formUnion(
                    links[index].intersection(conflicting)
                )
            }

            let sourceComponents = Array(components.values)
            componentsBySource[sourceID] = sourceComponents
            let sourceSnoozes = state.snoozes.filter { $0.messageID.sourceID == sourceID }
            for component in sourceComponents {
                for candidateKey in component.candidateKeys {
                    componentsByCandidateKey[candidateKey] = component
                    candidateKeysByMessageID[candidateKey.sourceMessageID, default: []].insert(candidateKey)
                }
                let matchingConversationRules = sourceSnoozes.filter { snooze in
                    guard let metadata = snooze.conversationMetadata else { return false }
                    guard let seeds = Self.validSeeds(metadata) else { return false }
                    return !component.rfcIdentifiers.isDisjoint(with: seeds)
                }
                for candidateKey in component.candidateKeys {
                    let matching = matchingConversationRules + sourceSnoozes.filter {
                        $0.conversationMetadata == nil && $0.messageID == candidateKey.sourceMessageID
                    }
                    if let newest = Self.newest(matching) {
                        effectiveSnoozes[candidateKey] = newest
                    }
                }
            }
        }

        for snooze in state.snoozes where snooze.conversationMetadata == nil {
            legacySnoozes[snooze.messageID] = Self.newest([legacySnoozes[snooze.messageID], snooze].compactMap { $0 })
        }
        self.effectiveSnoozes = effectiveSnoozes
        self.legacySnoozes = legacySnoozes
        self.componentsByCandidateKey = componentsByCandidateKey
        self.candidateKeysByMessageID = candidateKeysByMessageID
        self.componentsBySource = componentsBySource
    }

    func snooze(for messageID: SourceMessageID) -> LocalMessageSnooze? {
        guard let candidateKeys = candidateKeysByMessageID[messageID], candidateKeys.count == 1,
              let candidateKey = candidateKeys.first else { return legacySnoozes[messageID] }
        return effectiveSnoozes[candidateKey] ?? legacySnoozes[messageID]
    }

    func snooze(for messageID: SourceMessageID, header: MessageHeader) -> LocalMessageSnooze? {
        let candidateKey = CandidateKey(sourceID: messageID.sourceID, header: header)
        return effectiveSnoozes[candidateKey] ?? legacySnoozes[messageID]
    }

    func isSnoozed(_ messageID: SourceMessageID, at date: Date? = nil) -> Bool {
        snooze(for: messageID)?.isActive(at: date ?? now) == true
    }

    func isSnoozed(_ messageID: SourceMessageID, header: MessageHeader, at date: Date? = nil) -> Bool {
        snooze(for: messageID, header: header)?.isActive(at: date ?? now) == true
    }

    func conversationMetadata(for messageID: SourceMessageID) -> LocalMessageSnoozeConversationMetadata? {
        guard let candidateKeys = candidateKeysByMessageID[messageID], candidateKeys.count == 1,
              let candidateKey = candidateKeys.first else { return nil }
        return conversationMetadata(for: candidateKey)
    }

    func conversationMetadata(for messageID: SourceMessageID, header: MessageHeader) -> LocalMessageSnoozeConversationMetadata? {
        conversationMetadata(for: CandidateKey(sourceID: messageID.sourceID, header: header))
    }

    func overlappingSnoozes(for messageID: SourceMessageID, in state: LocalMessageWorkflowState) -> [LocalMessageSnooze] {
        guard let candidateKeys = candidateKeysByMessageID[messageID], candidateKeys.count == 1,
              let candidateKey = candidateKeys.first else {
            return state.snoozes.filter { $0.messageID == messageID && $0.conversationMetadata == nil }
        }
        return overlappingSnoozes(for: candidateKey, in: state)
    }

    func overlappingSnoozes(
        for messageID: SourceMessageID,
        header: MessageHeader,
        in state: LocalMessageWorkflowState
    ) -> [LocalMessageSnooze] {
        overlappingSnoozes(for: CandidateKey(sourceID: messageID.sourceID, header: header), in: state)
    }

    private func conversationMetadata(for candidateKey: CandidateKey) -> LocalMessageSnoozeConversationMetadata? {
        guard let identifiers = componentsByCandidateKey[candidateKey]?.rfcIdentifiers,
              !identifiers.isEmpty else { return nil }
        return LocalMessageSnoozeConversationMetadata(rfcIdentifiers: Array(identifiers))
    }

    private func overlappingSnoozes(
        for candidateKey: CandidateKey,
        in state: LocalMessageWorkflowState
    ) -> [LocalMessageSnooze] {
        let messageID = candidateKey.sourceMessageID
        guard let component = componentsByCandidateKey[candidateKey] else {
            return state.snoozes.filter { $0.messageID == messageID && $0.conversationMetadata == nil }
        }
        return state.snoozes.filter { snooze in
            guard snooze.messageID.sourceID == messageID.sourceID else { return false }
            guard let metadata = snooze.conversationMetadata else {
                return component.messageIDs.contains(snooze.messageID)
            }
            guard let seeds = Self.validSeeds(metadata) else { return false }
            return !component.rfcIdentifiers.isDisjoint(with: seeds)
        }
    }

    func metadataForReschedule(
        from messageID: SourceMessageID,
        state: LocalMessageWorkflowState
    ) -> LocalMessageSnoozeConversationMetadata? {
        guard let candidateKeys = candidateKeysByMessageID[messageID], candidateKeys.count == 1,
              let candidateKey = candidateKeys.first else { return nil }
        return metadataForReschedule(from: candidateKey, state: state)
    }

    func metadataForReschedule(
        from messageID: SourceMessageID,
        header: MessageHeader,
        state: LocalMessageWorkflowState
    ) -> LocalMessageSnoozeConversationMetadata? {
        metadataForReschedule(from: CandidateKey(sourceID: messageID.sourceID, header: header), state: state)
    }

    private func metadataForReschedule(
        from candidateKey: CandidateKey,
        state: LocalMessageWorkflowState
    ) -> LocalMessageSnoozeConversationMetadata? {
        guard let component = componentsByCandidateKey[candidateKey], !component.rfcIdentifiers.isEmpty else { return nil }
        let messageID = candidateKey.sourceMessageID
        let sourceConflicts = (componentsBySource[messageID.sourceID] ?? []).reduce(into: Set<String>()) {
            $0.formUnion($1.conflictingIdentifiers)
        }
        var identifiers = component.rfcIdentifiers
        for snooze in overlappingSnoozes(for: candidateKey, in: state) {
            guard let metadata = snooze.conversationMetadata,
                  let seeds = Self.validSeeds(metadata) else { continue }
            identifiers.formUnion(seeds.subtracting(sourceConflicts))
        }
        return LocalMessageSnoozeConversationMetadata(rfcIdentifiers: Array(identifiers))
    }

    func expandedMetadata(for snooze: LocalMessageSnooze) -> LocalMessageSnoozeConversationMetadata? {
        guard let metadata = snooze.conversationMetadata,
              let seeds = Self.validSeeds(metadata) else { return nil }
        let sourceComponents = componentsBySource[snooze.messageID.sourceID] ?? []
        let conflicts = sourceComponents.reduce(into: Set<String>()) { result, component in
            result.formUnion(component.conflictingIdentifiers)
        }
        let usableSeeds = seeds.subtracting(conflicts)
        guard !usableSeeds.isEmpty else { return .init(rfcIdentifiers: Array(seeds)) }

        var identifiers = usableSeeds
        for component in sourceComponents where !component.rfcIdentifiers.isDisjoint(with: usableSeeds) {
            identifiers.formUnion(component.rfcIdentifiers.subtracting(conflicts))
        }
        return LocalMessageSnoozeConversationMetadata(rfcIdentifiers: Array(identifiers))
    }

    private static func rfcLinks(_ candidate: LocalMessageWorkflowCandidate) -> Set<String> {
        var identifiers = Set<String>()
        if let own = explicitOwnIdentifier(candidate.header) { identifiers.insert(own) }
        if let inReplyTo = try? ConversationMembershipResolver.identifiers(in: candidate.header.inReplyTo) {
            identifiers.formUnion(inReplyTo)
        }
        for reference in candidate.header.references ?? [] {
            if let parsed = try? ConversationMembershipResolver.identifiers(in: reference) {
                identifiers.formUnion(parsed)
            }
        }
        return identifiers
    }

    private static func explicitOwnIdentifier(_ header: MessageHeader) -> String? {
        guard let parsed = try? ConversationMembershipResolver.identifiers(in: header.messageID),
              parsed.count == 1 else { return nil }
        return parsed[0]
    }

    private static func validSeeds(_ metadata: LocalMessageSnoozeConversationMetadata) -> Set<String>? {
        let identifiers = metadata.rfcIdentifiers
        guard !identifiers.isEmpty,
              identifiers == Array(Set(identifiers)).sorted(),
              identifiers.allSatisfy({
                  (try? ConversationMembershipResolver.identifiers(in: $0)) == [$0]
              }) else { return nil }
        return Set(identifiers)
    }

    private static func newest(_ snoozes: [LocalMessageSnooze]) -> LocalMessageSnooze? {
        snoozes.max { left, right in
            if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
            return stableKey(left.messageID) < stableKey(right.messageID)
        }
    }

    private static func stableKey(_ messageID: SourceMessageID) -> String {
        "\(messageID.sourceID.accountID)\u{0}\(messageID.sourceID.mailboxID)\u{0}\(messageID.messageID)"
    }
}
