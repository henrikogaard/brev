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

import Foundation

// MARK: - Pending mutation

/// One intended mailbox change captured for offline replay (ADR-0022).
///
/// Deliberately provider-neutral: the payload is expressed in message IDs
/// and an enum, never storage or provider-specific types, so it can cross the
/// view ↔ backend seam without violating ADR-0028 invariants 1 and 5.
public struct PendingMutation: Codable, Sendable, Identifiable, Equatable {
    /// The kind of change, with its minimal payload.
    public enum Kind: Codable, Sendable, Equatable {
        case setRead(Bool)
        case setFlagged(Bool)
        case setFlagColor(FlagColor?)
        case move(folderID: String)
        case copy(folderID: String)
        case delete
        case setJunk(Bool)
        /// Add (`isEnabled == true`) or remove provider labels (Gmail
        /// `X-GM-LABELS`) on the target messages.
        case setLabels([String], isEnabled: Bool)
        /// Legacy in-memory form. It is encoded as a staged-draft reference,
        /// so draft headers/body/recipients never enter UserDefaults.
        case send(draft: Draft)
        /// Send the draft persisted in the account's draft staging store.
        case sendStagedDraft(stagedDraftID: String)

        /// Human-readable summary of the intended change, safe for display
        /// in a conflict review UI.
        public var operationDescription: String {
            switch self {
            case .setRead(true): return "Mark read"
            case .setRead(false): return "Mark unread"
            case .setFlagged(true): return "Flag"
            case .setFlagged(false): return "Unflag"
            case .setFlagColor(let color):
                if let color {
                    return "Set flag color (\(color))"
                }
                return "Clear flag color"
            case .move(let folderID): return "Move to \(folderID)"
            case .copy(let folderID): return "Copy to \(folderID)"
            case .delete: return "Delete"
            case .setJunk(true): return "Mark as junk"
            case .setJunk(false): return "Mark as not junk"
            case .setLabels(let labels, let isEnabled):
                let joined = labels.joined(separator: ", ")
                return isEnabled ? "Add label \(joined)" : "Remove label \(joined)"
            case .send(draft:), .sendStagedDraft: return "Send draft"
            }
        }

        /// Short stable token used to group same-target mutations for
        /// duplicate suppression.
        var dedupToken: String {
            switch self {
            case .setRead: return "setRead"
            case .setFlagged: return "setFlagged"
            case .setFlagColor: return "setFlagColor"
            case .move(let folderID): return "move:\(folderID)"
            case .copy(let folderID): return "copy:\(folderID)"
            case .delete: return "delete"
            case .setJunk: return "setJunk"
            case .setLabels(let labels, _): return "setLabels:\(labels.sorted().joined(separator: ","))"
            case .send(draft: let draft): return "send:\(draft.remoteID ?? draft.id)"
            case .sendStagedDraft(let stagedDraftID): return "send:\(stagedDraftID)"
            }
        }

        private enum CodingKeys: String, CodingKey {
            case setRead, setFlagged, setFlagColor, move, copy, delete, setJunk, setLabels, send
        }

        private enum SendCodingKeys: String, CodingKey {
            case draft, stagedDraftID
            case legacyValue = "_0"
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .setRead(let value):
                var nested = container.nestedContainer(keyedBy: LegacyCodingKeys.self, forKey: .setRead)
                try nested.encode(value, forKey: .legacyValue)
            case .setFlagged(let value):
                var nested = container.nestedContainer(keyedBy: LegacyCodingKeys.self, forKey: .setFlagged)
                try nested.encode(value, forKey: .legacyValue)
            case .setFlagColor(let value):
                var nested = container.nestedContainer(keyedBy: LegacyCodingKeys.self, forKey: .setFlagColor)
                try nested.encode(value, forKey: .legacyValue)
            case .move(let folderID):
                var nested = container.nestedContainer(keyedBy: MoveCodingKeys.self, forKey: .move)
                try nested.encode(folderID, forKey: .folderID)
            case .copy(let folderID):
                var nested = container.nestedContainer(keyedBy: MoveCodingKeys.self, forKey: .copy)
                try nested.encode(folderID, forKey: .folderID)
            case .delete: try container.encodeNil(forKey: .delete)
            case .setJunk(let value):
                var nested = container.nestedContainer(keyedBy: LegacyCodingKeys.self, forKey: .setJunk)
                try nested.encode(value, forKey: .legacyValue)
            case .setLabels(let labels, let isEnabled):
                var nested = container.nestedContainer(keyedBy: LabelCodingKeys.self, forKey: .setLabels)
                try nested.encode(labels, forKey: .legacyValue)
                try nested.encode(isEnabled, forKey: .isEnabled)
            case .send(draft: let draft):
                var nested = container.nestedContainer(keyedBy: SendCodingKeys.self, forKey: .send)
                try nested.encode(draft.id, forKey: .stagedDraftID)
            case .sendStagedDraft(let stagedDraftID):
                var nested = container.nestedContainer(keyedBy: SendCodingKeys.self, forKey: .send)
                try nested.encode(stagedDraftID, forKey: .stagedDraftID)
            }
        }

        private enum LegacyCodingKeys: String, CodingKey { case legacyValue = "_0" }
        private enum MoveCodingKeys: String, CodingKey {
            case folderID
            case legacyValue = "_0"
        }

        private enum LabelCodingKeys: String, CodingKey { case legacyValue = "_0", isEnabled }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let value = try Self.decode(Bool.self, from: container, key: .setRead) { self = .setRead(value); return }
            if let value = try Self.decode(Bool.self, from: container, key: .setFlagged) { self = .setFlagged(value); return }
            if container.contains(.setFlagColor) {
                let nested = try container.nestedContainer(keyedBy: LegacyCodingKeys.self, forKey: .setFlagColor)
                self = try .setFlagColor(nested.decodeIfPresent(FlagColor.self, forKey: .legacyValue))
                return
            }
            if let value = try Self.decodeFolderID(from: container, key: .move) {
                self = .move(folderID: value)
                return
            }
            if let value = try Self.decodeFolderID(from: container, key: .copy) {
                self = .copy(folderID: value)
                return
            }
            if container.contains(.delete) { self = .delete; return }
            if let value = try Self.decode(Bool.self, from: container, key: .setJunk) { self = .setJunk(value); return }
            if container.contains(.setLabels) {
                let nested = try container.nestedContainer(keyedBy: LabelCodingKeys.self, forKey: .setLabels)
                self = try .setLabels(
                    nested.decode([String].self, forKey: .legacyValue),
                    isEnabled: nested.decode(Bool.self, forKey: .isEnabled)
                )
                return
            }
            if container.contains(.send) {
                let nested = try container.nestedContainer(keyedBy: SendCodingKeys.self, forKey: .send)
                if let id = try nested.decodeIfPresent(String.self, forKey: .stagedDraftID) {
                    self = .sendStagedDraft(stagedDraftID: id)
                    return
                }
                // Keep the legacy draft in memory until the owning IMAP
                // backend can persist it in the account's staging store.
                if let draft = try nested.decodeIfPresent(Draft.self, forKey: .draft) {
                    self = .send(draft: draft)
                    return
                }
                if let draft = try nested.decodeIfPresent(Draft.self, forKey: .legacyValue) {
                    self = .send(draft: draft)
                    return
                }
            }
            throw DecodingError.dataCorruptedError(
                forKey: .send,
                in: container,
                debugDescription: "Unknown pending mutation kind"
            )
        }

        private static func decode<T: Decodable>(
            _ type: T.Type,
            from container: KeyedDecodingContainer<CodingKeys>,
            key: CodingKeys
        ) throws -> T? {
            if let direct = try? container.decodeIfPresent(T.self, forKey: key) { return direct }
            guard container.contains(key) else { return nil }
            let nested = try container.nestedContainer(keyedBy: LegacyCodingKeys.self, forKey: key)
            return try nested.decodeIfPresent(T.self, forKey: .legacyValue)
        }

        /// Decodes move/copy payloads written by both the canonical encoder
        /// (`folderID`) and the synthesized enum representation (`_0` or a
        /// direct string value) used by older persisted queue records.
        private static func decodeFolderID(
            from container: KeyedDecodingContainer<CodingKeys>,
            key: CodingKeys
        ) throws -> String? {
            if let direct = try? container.decodeIfPresent(String.self, forKey: key) {
                return direct
            }
            guard container.contains(key) else { return nil }
            let nested = try container.nestedContainer(keyedBy: MoveCodingKeys.self, forKey: key)
            if let canonical = try nested.decodeIfPresent(String.self, forKey: .folderID) {
                return canonical
            }
            return try nested.decodeIfPresent(String.self, forKey: .legacyValue)
        }
    }

    public let id: UUID
    public let kind: Kind
    /// Optional source scope for multi-source workspaces. When present,
    /// duplicate suppression and replay are isolated per account/mailbox.
    public let sourceID: MailSourceID?
    /// Message IDs the mutation applies to. Empty for `send`.
    public let messageIDs: [String]
    public let createdAt: Date
    /// Number of delivery attempts so far.
    public var attempt: Int

    public init(
        id: UUID = UUID(),
        kind: Kind,
        sourceID: MailSourceID? = nil,
        messageIDs: [String],
        createdAt: Date = Date(),
        attempt: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.sourceID = sourceID
        self.messageIDs = messageIDs
        self.createdAt = createdAt
        self.attempt = attempt
    }

    /// Key identifying mutations that target the same logical change.
    ///
    /// Two `setRead` mutations on the same message set collapse to one;
    /// the newest wins. `send` is keyed by draft so re-queuing the same
    /// draft never sends twice.
    public var dedupKey: String {
        let sourceScope = sourceID
            .map { "\($0.accountID)|\($0.mailboxID)" }
            ?? "active-source"
        switch kind {
        case .send(draft:), .sendStagedDraft:
            return "\(sourceScope)|\(kind.dedupToken)"
        default:
            return "\(sourceScope)|\(kind.dedupToken)|\(messageIDs.sorted().joined(separator: ","))"
        }
    }
}

// MARK: - Conflict

/// A surfaced, recoverable conflict encountered while replaying a
/// mutation (ADR-0022, the related feature request "conflicts are visible and
/// recoverable").
public struct MutationConflict: Codable, Sendable, Equatable, Identifiable {
    public enum Reason: String, Codable, Sendable {
        /// The target message/draft no longer exists on the provider.
        case targetMissing
        /// The server rejected the change as no longer applicable.
        case rejectedByServer
        /// Retries were exhausted without success.
        case retriesExhausted
    }

    public let id: UUID
    public let mutation: PendingMutation
    public let reason: Reason
    /// Human-readable detail safe to show in the UI.
    public let message: String
    public let detectedAt: Date

    public init(
        id: UUID = UUID(),
        mutation: PendingMutation,
        reason: Reason,
        message: String,
        detectedAt: Date = Date()
    ) {
        self.id = id
        self.mutation = mutation
        self.reason = reason
        self.message = message
        self.detectedAt = detectedAt
    }
}

// MARK: - Queue protocol

/// Persistent store of pending mutations. Storage-engine agnostic so the
/// backing store can be swapped (per ADR-0022) without touching callers.
public protocol OfflineMutationQueue: Sendable {
    /// Appends a mutation, collapsing any existing mutation that shares
    /// its `dedupKey` so only the newest intention is retained.
    func enqueue(_ mutation: PendingMutation) async throws
    /// Returns all pending mutations in insertion order.
    func pending() async throws -> [PendingMutation]
    /// Replaces the stored record for `mutation.id` (e.g. to bump
    /// `attempt`). No-op if the id is absent.
    func update(_ mutation: PendingMutation) async throws
    /// Removes the mutation with `id`.
    func remove(id: UUID) async throws
    /// Removes all pending mutations.
    func removeAll() async throws
}

/// Persistent store of surfaced mutation conflicts. Kept separate from the
/// pending queue so failed replay work remains visible after the queue removes
/// the conflicted mutation.
public protocol OfflineMutationConflictStore: Sendable {
    func append(_ conflicts: [MutationConflict]) async throws
    func conflicts() async throws -> [MutationConflict]
    func remove(id: UUID) async throws
    func removeAll() async throws
}

// MARK: - UserDefaults reference implementation

/// `UserDefaults`-backed `OfflineMutationQueue`. Pending mutations are
/// low-volume and short-lived, so a JSON blob is sufficient (ADR-0022).
public actor UserDefaultsMutationQueue: OfflineMutationQueue {
    private let defaults: UserDefaults
    private let storageKey: String

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "backend.offlineMutationQueue.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    public func enqueue(_ mutation: PendingMutation) async throws {
        var items = load()
        // Duplicate suppression: drop any existing same-target mutation
        // so the newest intention wins.
        items.removeAll { $0.dedupKey == mutation.dedupKey }
        items.append(mutation)
        try save(items)
    }

    public func pending() async throws -> [PendingMutation] {
        // Legacy send payloads remain available in memory until the owning
        // backend copies them into its draft staging store. Any queue rewrite
        // still strips their content through Kind's hardened encoder.
        return load()
    }

    public func update(_ mutation: PendingMutation) async throws {
        var items = load()
        guard let index = items.firstIndex(where: { $0.id == mutation.id }) else { return }
        items[index] = mutation
        try save(items)
    }

    public func remove(id: UUID) async throws {
        var items = load()
        items.removeAll { $0.id == id }
        try save(items)
    }

    public func removeAll() async throws {
        defaults.removeObject(forKey: storageKey)
    }

    // MARK: Storage

    private func load() -> [PendingMutation] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        if let all = try? JSONDecoder().decode([PendingMutation].self, from: data) {
            return all
        }
        // One corrupt/unknown entry must not brick the entire queue (which would
        // stop ALL offline replay). Decode element-wise and skip undecodable ones.
        let lenient = (try? JSONDecoder().decode([FailableDecodable<PendingMutation>].self, from: data)) ?? []
        return lenient.compactMap(\.value)
    }

    private func save(_ items: [PendingMutation]) throws {
        let data = try JSONEncoder().encode(items)
        defaults.set(data, forKey: storageKey)
    }
}

/// Decodes `T` or yields `nil` if that element can't be decoded, so a single
/// bad array element doesn't fail the whole array decode.
private struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) throws {
        value = try? decoder.singleValueContainer().decode(T.self)
    }
}

/// `UserDefaults`-backed mutation conflict store. Conflicts are tiny, already
/// user-safe summaries, and account-scoped by the storage key chosen by the
/// caller.
public actor UserDefaultsMutationConflictStore: OfflineMutationConflictStore {
    private let defaults: UserDefaults
    private let storageKey: String

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "backend.offlineMutationConflicts.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    public func append(_ conflicts: [MutationConflict]) async throws {
        guard !conflicts.isEmpty else { return }
        var items = try load()
        let newIDs = Set(conflicts.map(\.id))
        let newMutationIDs = Set(conflicts.map(\.mutation.id))
        let newStagedDraftIDs = Set(conflicts.compactMap { conflict -> String? in
            guard case .sendStagedDraft(let stagedDraftID) = conflict.mutation.kind else {
                return nil
            }
            return stagedDraftID
        })
        items.removeAll {
            newIDs.contains($0.id)
                || newMutationIDs.contains($0.mutation.id)
                || {
                    guard case .sendStagedDraft(let stagedDraftID) = $0.mutation.kind else {
                        return false
                    }
                    return newStagedDraftIDs.contains(stagedDraftID)
                }($0)
        }
        items.append(contentsOf: conflicts)
        try save(items.sorted { $0.detectedAt > $1.detectedAt })
    }

    public func conflicts() async throws -> [MutationConflict] {
        let items = try load()
        if defaults.data(forKey: storageKey) != nil { try save(items) }
        return items
    }

    public func remove(id: UUID) async throws {
        var items = try load()
        items.removeAll { $0.id == id }
        try save(items)
    }

    public func removeAll() async throws {
        defaults.removeObject(forKey: storageKey)
    }

    private func load() throws -> [MutationConflict] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return try JSONDecoder().decode([MutationConflict].self, from: data)
    }

    private func save(_ items: [MutationConflict]) throws {
        let data = try JSONEncoder().encode(items)
        defaults.set(data, forKey: storageKey)
    }
}
