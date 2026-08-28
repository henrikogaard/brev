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
import SQLite3

/// Account-level sync state owned by the Gmail API store.
public struct GmailAccountState: Sendable, Equatable {
    /// Stable Brev account identifier, normally `gmail-api:<Google subject>`.
    public let accountID: String
    /// Current verified mailbox address.
    public let emailAddress: String
    /// Most recent committed Gmail history cursor.
    public let historyID: String?
    /// Time of the most recent successful full reconciliation.
    public let lastFullSyncAt: Date?
    /// Time of the most recent successful history delta.
    public let lastDeltaSyncAt: Date?

    /// Creates account sync state.
    public init(
        accountID: String,
        emailAddress: String,
        historyID: String? = nil,
        lastFullSyncAt: Date? = nil,
        lastDeltaSyncAt: Date? = nil
    ) {
        self.accountID = accountID
        self.emailAddress = emailAddress
        self.historyID = historyID
        self.lastFullSyncAt = lastFullSyncAt
        self.lastDeltaSyncAt = lastDeltaSyncAt
    }
}

/// An atomic full Gmail account snapshot.
public struct GmailAccountSnapshot: Sendable, Equatable {
    /// Stable account identifier.
    public let accountID: String
    /// Account cursor and sync timestamps.
    public let state: GmailAccountState
    /// Current Gmail label catalog.
    public let labels: [GmailLabel]
    /// Current account-wide messages. Label membership is represented by each
    /// message's `labelIDs` and persisted as a many-to-many join.
    public let messages: [GmailMessage]

    /// Creates a full account snapshot.
    public init(accountID: String, state: GmailAccountState, labels: [GmailLabel], messages: [GmailMessage]) {
        self.accountID = accountID
        self.state = state
        self.labels = labels
        self.messages = messages
    }
}

/// An atomic history delta applied after a committed full or previous delta.
public struct GmailStoreDelta: Sendable, Equatable {
    /// Stable account identifier receiving this delta.
    public let accountID: String
    /// Label records to insert or replace by Gmail label ID.
    public let upsertedLabels: [GmailLabel]
    /// Label IDs to remove from the catalog.
    public let removedLabelIDs: [String]
    /// Message records to insert or replace by Gmail message ID.
    public let upsertedMessages: [GmailMessage]
    /// Message IDs to remove account-wide.
    public let removedMessageIDs: [String]
    /// New committed Gmail history cursor, if supplied.
    public let historyID: String?
    /// Delta completion timestamp.
    public let lastDeltaSyncAt: Date?

    /// Creates a history delta.
    public init(
        accountID: String,
        upsertedLabels: [GmailLabel] = [],
        removedLabelIDs: [String] = [],
        upsertedMessages: [GmailMessage] = [],
        removedMessageIDs: [String] = [],
        historyID: String? = nil,
        lastDeltaSyncAt: Date? = nil
    ) {
        self.accountID = accountID
        self.upsertedLabels = upsertedLabels
        self.removedLabelIDs = removedLabelIDs
        self.upsertedMessages = upsertedMessages
        self.removedMessageIDs = removedMessageIDs
        self.historyID = historyID
        self.lastDeltaSyncAt = lastDeltaSyncAt
    }
}

/// Errors that preserve the store's all-or-nothing update contract.
public enum GmailAccountStoreError: Error, Sendable, Equatable, LocalizedError {
    /// A required account identifier was empty.
    case invalidAccountID
    /// A required Gmail message identifier was empty.
    case invalidMessageID
    /// A required Gmail label identifier was empty.
    case invalidLabelID
    /// A snapshot or delta contained records for a different account.
    case accountMismatch
    /// The SQLite database could not be opened.
    case openFailed
    /// SQLite schema setup or migration failed.
    case migrationFailed
    /// SQLite statement preparation or execution failed.
    case databaseFailure
    /// A stored message could not be decoded.
    case malformedStoredMessage

    /// A safe user-facing description without database details or message data.
    public var errorDescription: String? {
        switch self {
        case .invalidAccountID: return String(localized: "The Gmail account identifier is invalid.", bundle: .module)
        case .invalidMessageID: return String(localized: "The Gmail message identifier is invalid.", bundle: .module)
        case .invalidLabelID: return String(localized: "The Gmail label identifier is invalid.", bundle: .module)
        case .accountMismatch: return String(localized: "The Gmail update belongs to another account.", bundle: .module)
        case .openFailed: return String(localized: "The Gmail local store could not be opened.", bundle: .module)
        case .migrationFailed: return String(localized: "The Gmail local store could not be prepared.", bundle: .module)
        case .databaseFailure: return String(localized: "The Gmail local store could not be updated.", bundle: .module)
        case .malformedStoredMessage: return String(localized: "The Gmail local store contains unreadable data.", bundle: .module)
        }
    }
}

/// Canonical account-wide storage seam used by future Gmail sync and backend
/// slices.
public protocol GmailAccountStore: Sendable {
    /// Removes all canonical records and cached content for `accountID`.
    func removeAccount(accountID: String) async throws
    /// Returns the current state for `accountID`, if the account exists.
    func accountState(accountID: String) async throws -> GmailAccountState?
    /// Atomically replaces all account records and commits the supplied cursor.
    func replaceSnapshot(_ snapshot: GmailAccountSnapshot) async throws
    /// Atomically applies a history delta and commits its cursor only on success.
    func apply(_ delta: GmailStoreDelta) async throws
    /// Lists account-wide messages without duplicating label projections.
    func messages(accountID: String) async throws -> [GmailMessage]
    /// Looks up one account-wide Gmail message.
    func message(accountID: String, messageID: String) async throws -> GmailMessage?
    /// Lists the current label catalog.
    func labels(accountID: String) async throws -> [GmailLabel]
    /// Returns the many-to-many label IDs attached to one message.
    func messageLabelIDs(accountID: String, messageID: String) async throws -> [String]
}

/// Optional content-cache surface used by read backends.
///
/// The canonical account store remains useful for sync-only implementations;
/// read backends use this narrower refinement when body/source/attachment bytes
/// should survive a transport round trip.
public protocol GmailReadCacheStore: GmailAccountStore {
    /// Returns a cached parsed body, when available.
    func cachedBody(accountID: String, messageID: String) async throws -> MessageBody?
    /// Persists a parsed body for cache-first reads.
    func storeBody(_ body: MessageBody, accountID: String) async throws
    /// Returns cached raw RFC 5322 source, when available.
    func cachedRawSource(accountID: String, messageID: String) async throws -> String?
    /// Persists raw RFC 5322 source for cache-first reads.
    func storeRawSource(_ source: String, accountID: String, messageID: String) async throws
    /// Returns cached attachment bytes, when available.
    func cachedAttachment(accountID: String, attachmentID: String) async throws -> Data?
    /// Persists attachment bytes for cache-first download.
    func storeAttachment(_ data: Data, accountID: String, attachmentID: String) async throws
    /// Removes cached body, raw-source, and attachment content for messages.
    func removeCachedContent(accountID: String, messageIDs: Set<String>) async throws
    /// Removes every cached body, raw source, and attachment for an account.
    func removeAllCachedContent(accountID: String) async throws
}

/// In-memory implementation for tests and deterministic previews.
public actor InMemoryGmailAccountStore: GmailAccountStore {
    private var snapshots: [String: GmailAccountSnapshot] = [:]
    private var bodies: [String: MessageBody] = [:]
    private var rawSources: [String: String] = [:]
    private var attachments: [String: Data] = [:]

    /// Creates an empty in-memory store.
    public init() {}

    /// Removes the account snapshot and every account-scoped cache entry.
    public func removeAccount(accountID: String) async throws {
        try validate(accountID: accountID)
        snapshots[accountID] = nil
        let prefix = "\(accountID)|"
        bodies = bodies.filter { !$0.key.hasPrefix(prefix) }
        rawSources = rawSources.filter { !$0.key.hasPrefix(prefix) }
        attachments = attachments.filter { !$0.key.hasPrefix(prefix) }
    }

    /// Returns current account state.
    public func accountState(accountID: String) async throws -> GmailAccountState? {
        try validate(accountID: accountID)
        return snapshots[accountID]?.state
    }

    /// Atomically replaces one account snapshot.
    public func replaceSnapshot(_ snapshot: GmailAccountSnapshot) async throws {
        try validate(snapshot: snapshot)
        snapshots[snapshot.accountID] = snapshot
        let prefix = "\(snapshot.accountID)|"
        let messageIDs = Set(snapshot.messages.map(\.id))
        let attachmentIDs = Set(snapshot.messages.flatMap(Self.attachmentIDs))
        bodies = bodies.filter { key, _ in
            !key.hasPrefix(prefix) || messageIDs.contains(String(key.dropFirst(prefix.count)))
        }
        rawSources = rawSources.filter { key, _ in
            !key.hasPrefix(prefix) || messageIDs.contains(String(key.dropFirst(prefix.count)))
        }
        attachments = attachments.filter { key, _ in
            !key.hasPrefix(prefix) || attachmentIDs.contains(String(key.dropFirst(prefix.count)))
                || messageIDs.contains { messageID in
                    String(key.dropFirst(prefix.count)).hasPrefix("gmail-attachment:\(messageID):")
                }
        }
    }

    /// Applies a delta to a copied snapshot, committing only if validation and
    /// every record update succeeds.
    public func apply(_ delta: GmailStoreDelta) async throws {
        try validate(accountID: delta.accountID)
        guard var current = snapshots[delta.accountID] else {
            throw GmailAccountStoreError.accountMismatch
        }
        var labels = Dictionary(uniqueKeysWithValues: current.labels.map { ($0.id, $0) })
        var messages = Dictionary(uniqueKeysWithValues: current.messages.map { ($0.id, $0) })
        for label in delta.upsertedLabels {
            try validate(label: label)
            labels[label.id] = label
        }
        for id in delta.removedLabelIDs {
            try validate(labelID: id)
            labels.removeValue(forKey: id)
            for (messageID, message) in messages where message.labelIDs.contains(id) {
                messages[messageID] = message.withLabelIDs(message.labelIDs.filter { $0 != id })
            }
        }
        for message in delta.upsertedMessages {
            try validate(message: message)
            messages[message.id] = message.preservingCachedContent(from: messages[message.id])
        }
        for id in delta.removedMessageIDs {
            try validate(messageID: id)
            messages.removeValue(forKey: id)
        }
        current = GmailAccountSnapshot(
            accountID: current.accountID,
            state: GmailAccountState(
                accountID: current.state.accountID,
                emailAddress: current.state.emailAddress,
                historyID: delta.historyID ?? current.state.historyID,
                lastFullSyncAt: current.state.lastFullSyncAt,
                lastDeltaSyncAt: delta.lastDeltaSyncAt ?? current.state.lastDeltaSyncAt
            ),
            labels: labels.values.sorted { $0.id < $1.id },
            messages: messages.values.sorted { $0.id < $1.id }
        )
        snapshots[delta.accountID] = current
    }

    /// Lists account messages.
    public func messages(accountID: String) async throws -> [GmailMessage] {
        try validate(accountID: accountID)
        return snapshots[accountID]?.messages ?? []
    }

    /// Looks up one message.
    public func message(accountID: String, messageID: String) async throws -> GmailMessage? {
        try validate(accountID: accountID)
        try validate(messageID: messageID)
        return snapshots[accountID]?.messages.first { $0.id == messageID }
    }

    /// Lists labels.
    public func labels(accountID: String) async throws -> [GmailLabel] {
        try validate(accountID: accountID)
        return snapshots[accountID]?.labels ?? []
    }

    /// Returns label joins for one message.
    public func messageLabelIDs(accountID: String, messageID: String) async throws -> [String] {
        try validate(accountID: accountID)
        try validate(messageID: messageID)
        return snapshots[accountID]?.messages.first { $0.id == messageID }?.labelIDs ?? []
    }

    public func cachedBody(accountID: String, messageID: String) async throws -> MessageBody? {
        try validate(accountID: accountID)
        try validate(messageID: messageID)
        return bodies[cacheKey(accountID: accountID, value: messageID)]
    }

    public func storeBody(_ body: MessageBody, accountID: String) async throws {
        try validate(accountID: accountID)
        try validate(messageID: body.messageID)
        bodies[cacheKey(accountID: accountID, value: body.messageID)] = body
    }

    public func cachedRawSource(accountID: String, messageID: String) async throws -> String? {
        try validate(accountID: accountID)
        try validate(messageID: messageID)
        return rawSources[cacheKey(accountID: accountID, value: messageID)]
    }

    public func storeRawSource(_ source: String, accountID: String, messageID: String) async throws {
        try validate(accountID: accountID)
        try validate(messageID: messageID)
        rawSources[cacheKey(accountID: accountID, value: messageID)] = source
    }

    public func cachedAttachment(accountID: String, attachmentID: String) async throws -> Data? {
        try validate(accountID: accountID)
        try validate(messageID: attachmentID)
        return attachments[cacheKey(accountID: accountID, value: attachmentID)]
    }

    public func storeAttachment(_ data: Data, accountID: String, attachmentID: String) async throws {
        try validate(accountID: accountID)
        try validate(messageID: attachmentID)
        attachments[cacheKey(accountID: accountID, value: attachmentID)] = data
    }

    public func removeCachedContent(accountID: String, messageIDs: Set<String>) async throws {
        try validate(accountID: accountID)
        let prefix = "\(accountID)|"
        bodies = bodies.filter { key, _ in
            !key.hasPrefix(prefix) || !messageIDs.contains(String(key.dropFirst(prefix.count)))
        }
        rawSources = rawSources.filter { key, _ in
            !key.hasPrefix(prefix) || !messageIDs.contains(String(key.dropFirst(prefix.count)))
        }
        attachments = attachments.filter { key, _ in
            guard key.hasPrefix(prefix) else { return true }
            let attachmentID = String(key.dropFirst(prefix.count))
            return !messageIDs.contains { messageID in
                attachmentID == messageID || attachmentID.hasPrefix("gmail-attachment:\(messageID):")
            }
        }
        if var current = snapshots[accountID] {
            current = GmailAccountSnapshot(
                accountID: current.accountID,
                state: current.state,
                labels: current.labels,
                messages: current.messages.map { message in
                    messageIDs.contains(message.id) ? message.withoutContent() : message
                }
            )
            snapshots[accountID] = current
        }
    }

    public func removeAllCachedContent(accountID: String) async throws {
        try validate(accountID: accountID)
        let prefix = "\(accountID)|"
        bodies = bodies.filter { !$0.key.hasPrefix(prefix) }
        rawSources = rawSources.filter { !$0.key.hasPrefix(prefix) }
        attachments = attachments.filter { !$0.key.hasPrefix(prefix) }
        if var current = snapshots[accountID] {
            current = GmailAccountSnapshot(
                accountID: current.accountID,
                state: current.state,
                labels: current.labels,
                messages: current.messages.map { $0.withoutContent() }
            )
            snapshots[accountID] = current
        }
    }

    private static func attachmentIDs(_ message: GmailMessage) -> [String] {
        var result: [String] = []
        collectAttachmentIDs(message.payload, messageID: message.id, into: &result)
        return result
    }

    private static func collectAttachmentIDs(
        _ part: GmailMessagePart?,
        messageID: String,
        into result: inout [String]
    ) {
        guard let part else { return }
        if let filename = part.filename, !filename.isEmpty {
            result.append("gmail-attachment:\(messageID):\(part.partID ?? filename)")
        }
        for child in part.parts {
            collectAttachmentIDs(child, messageID: messageID, into: &result)
        }
    }

    private func cacheKey(accountID: String, value: String) -> String {
        "\(accountID)|\(value)"
    }
}

extension InMemoryGmailAccountStore: GmailReadCacheStore {}

private extension GmailMessage {
    func withLabelIDs(_ labels: [String]) -> GmailMessage {
        GmailMessage(
            id: id,
            threadID: threadID,
            labelIDs: labels,
            snippet: snippet,
            historyID: historyID,
            internalDate: internalDate,
            sizeEstimate: sizeEstimate,
            payload: payload,
            raw: raw
        )
    }
}

public extension GmailAccountStore {
    /// Default no-op cache for stores that only implement canonical metadata.
    func cachedBody(accountID: String, messageID: String) async throws -> MessageBody? { nil }
    /// Default no-op cache write for metadata-only stores.
    func storeBody(_ body: MessageBody, accountID: String) async throws {}
    /// Default no-op raw-source cache.
    func cachedRawSource(accountID: String, messageID: String) async throws -> String? { nil }
    /// Default no-op raw-source write.
    func storeRawSource(_ source: String, accountID: String, messageID: String) async throws {}
    /// Default no-op attachment cache.
    func cachedAttachment(accountID: String, attachmentID: String) async throws -> Data? { nil }
    /// Default no-op attachment write.
    func storeAttachment(_ data: Data, accountID: String, attachmentID: String) async throws {}
    func removeCachedContent(accountID: String, messageIDs: Set<String>) async throws {}
    func removeAllCachedContent(accountID: String) async throws {}
}

func validate(accountID: String) throws {
    guard !accountID.isEmpty else { throw GmailAccountStoreError.invalidAccountID }
}

func validate(messageID: String) throws {
    guard !messageID.isEmpty else { throw GmailAccountStoreError.invalidMessageID }
}

func validate(labelID: String) throws {
    guard !labelID.isEmpty else { throw GmailAccountStoreError.invalidLabelID }
}

func validate(message: GmailMessage) throws {
    try validate(messageID: message.id)
    for labelID in message.labelIDs {
        try validate(labelID: labelID)
    }
}

func validate(label: GmailLabel) throws {
    try validate(labelID: label.id)
}

func validate(snapshot: GmailAccountSnapshot) throws {
    try validate(accountID: snapshot.accountID)
    guard snapshot.state.accountID == snapshot.accountID else {
        throw GmailAccountStoreError.accountMismatch
    }
    for label in snapshot.labels {
        try validate(label: label)
    }
    for message in snapshot.messages {
        try validate(message: message)
    }
}
