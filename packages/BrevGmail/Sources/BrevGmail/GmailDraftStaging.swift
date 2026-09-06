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

/// An attachment staged locally until Gmail receives the complete MIME draft.
public struct GmailStagedAttachment: Sendable, Hashable, Codable {
    /// Stable staging identifier included in the draft's attachment list.
    public let id: String
    /// Local draft identifier owning this attachment.
    public let draftID: String
    /// Display filename.
    public let filename: String
    /// MIME content type.
    public let mimeType: String
    /// Raw attachment bytes.
    public let data: Data
    /// Whether the MIME part is inline.
    public let isInline: Bool
    /// RFC 2392 Content-ID without angle brackets.
    public let contentID: String?

    /// Creates a staged Gmail attachment.
    public init(
        id: String,
        draftID: String,
        filename: String,
        mimeType: String,
        data: Data,
        isInline: Bool = false,
        contentID: String? = nil
    ) {
        self.id = id
        self.draftID = draftID
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.isInline = isInline
        self.contentID = contentID
    }
}

/// Errors from the explicitly bounded in-memory Gmail draft staging seam.
public enum GmailDraftStagingError: Error, Sendable, Equatable, LocalizedError {
    /// The aggregate staged bytes would exceed the configured bound.
    case capacityExceeded(limit: Int)
    /// A required draft or attachment identifier was empty.
    case invalidIdentifier

    public var errorDescription: String? {
        switch self {
        case .capacityExceeded(let limit):
            return String(localized: "Gmail draft attachments exceed the local staging limit of \(limit) bytes.", bundle: .module)
        case .invalidIdentifier:
            return String(localized: "The Gmail draft staging identifier is invalid.", bundle: .module)
        }
    }
}

/// Stores local Gmail drafts and MIME attachments until a write operation.
public protocol GmailDraftStagingStore: Sendable {
    /// Returns a draft by local or remote ID.
    func draft(accountID: String, draftID: String) async throws -> Draft?
    /// Persists a draft under its local and remote IDs.
    func setDraft(_ draft: Draft, accountID: String) async throws
    /// Returns one staged attachment.
    func attachment(accountID: String, attachmentID: String) async throws -> GmailStagedAttachment?
    /// Stores one staged attachment or throws when the byte cap is exceeded.
    func setAttachment(_ attachment: GmailStagedAttachment, accountID: String) async throws
    /// Removes a draft and all attachments owned by it.
    func removeDraft(accountID: String, draftID: String) async throws
    /// Clears all staging records for an account.
    func clear(accountID: String) async throws
}

/// Explicitly bounded in-memory staging for Gmail compose attachments.
public actor InMemoryGmailDraftStagingStore: GmailDraftStagingStore {
    private let maxBytes: Int
    private var drafts: [String: [String: Draft]] = [:]
    private var attachments: [String: [String: GmailStagedAttachment]] = [:]
    private var byteCounts: [String: Int] = [:]

    /// Creates staging with a 25 MiB aggregate attachment limit by default.
    public init(maxBytes: Int = 25 * 1024 * 1024) {
        self.maxBytes = max(1, maxBytes)
    }

    public func draft(accountID: String, draftID: String) -> Draft? {
        drafts[accountID]?[draftID]
    }

    public func setDraft(_ draft: Draft, accountID: String) {
        var accountDrafts = (drafts[accountID] ?? [:]).filter { $0.value.id != draft.id }
        accountDrafts[draft.id] = draft
        if let remoteID = draft.remoteID { accountDrafts[remoteID] = draft }
        drafts[accountID] = accountDrafts
    }

    public func attachment(accountID: String, attachmentID: String) -> GmailStagedAttachment? {
        attachments[accountID]?[attachmentID]
    }

    public func setAttachment(_ attachment: GmailStagedAttachment, accountID: String) throws {
        guard !attachment.id.isEmpty, !attachment.draftID.isEmpty else {
            throw GmailDraftStagingError.invalidIdentifier
        }
        let oldSize = attachments[accountID]?[attachment.id]?.data.count ?? 0
        let nextCount = (byteCounts[accountID] ?? 0) - oldSize + attachment.data.count
        guard nextCount <= maxBytes else {
            throw GmailDraftStagingError.capacityExceeded(limit: maxBytes)
        }
        attachments[accountID, default: [:]][attachment.id] = attachment
        byteCounts[accountID] = nextCount
    }

    public func removeDraft(accountID: String, draftID: String) {
        let accountDrafts = drafts[accountID] ?? [:]
        let stored = accountDrafts[draftID]
        let IDs = Set([draftID, stored?.id, stored?.remoteID].compactMap { $0 })
        drafts[accountID] = accountDrafts.filter { !IDs.contains($0.key) && !IDs.contains($0.value.id) }
        let owned = attachments[accountID]?.filter { IDs.contains($0.value.draftID) } ?? [:]
        byteCounts[accountID] = max(0, (byteCounts[accountID] ?? 0) - owned.values.reduce(0) { $0 + $1.data.count })
        attachments[accountID] = attachments[accountID]?.filter { !IDs.contains($0.value.draftID) }
    }

    public func clear(accountID: String) {
        drafts[accountID] = nil
        attachments[accountID] = nil
        byteCounts[accountID] = nil
    }
}
