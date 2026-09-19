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

/// `MailLocalSearchIndex` adapter that defers opening the real index until
/// the first indexed operation, so session bootstrap never blocks first
/// paint on the store's disk I/O (SQLite open, pragmas, and migrations).
/// The index is only needed for search and attachment indexing.
///
/// A `nil` factory result is cached just like a resolved index, so an
/// open failure behaves exactly like passing `nil` at bootstrap: reads
/// miss, writes no-op, and no retry cost is paid per call.
public final class DeferredLocalSearchIndex: MailLocalSearchIndex, @unchecked Sendable {
    private let lock = NSLock()
    private let factory: @Sendable () -> (any MailLocalSearchIndex)?
    private var resolved = false
    private var underlying: (any MailLocalSearchIndex)?

    /// - Parameter factory: Opens the real index on first use. Called at
    ///   most once; a `nil` result disables the index permanently.
    public init(factory: @escaping @Sendable () -> (any MailLocalSearchIndex)?) {
        self.factory = factory
    }

    private var index: (any MailLocalSearchIndex)? {
        lock.withLock {
            if !resolved {
                underlying = factory()
                resolved = true
            }
            return underlying
        }
    }

    public func cachedHeaders(
        for folder: Folder,
        account: BrevAccount,
        pageToken: String?
    ) async -> (headers: [MessageHeader], nextPageToken: String?)? {
        await index?.cachedHeaders(for: folder, account: account, pageToken: pageToken)
    }

    public func cachedRawMessage(
        for messageID: MessageHeader.ID,
        account: BrevAccount
    ) async -> Data? {
        await index?.cachedRawMessage(for: messageID, account: account)
    }

    public func cachedOriginalRawMessage(
        for messageID: MessageHeader.ID,
        account: BrevAccount
    ) async -> Data? {
        await index?.cachedOriginalRawMessage(for: messageID, account: account)
    }

    public func storeOriginalRawMessage(
        _ data: Data,
        for messageID: MessageHeader.ID,
        account: BrevAccount
    ) async {
        await index?.storeOriginalRawMessage(data, for: messageID, account: account)
    }

    public func search(
        _ query: SearchQuery,
        account: BrevAccount,
        limit: Int
    ) async -> [MessageHeader] {
        await index?.search(query, account: account, limit: limit) ?? []
    }

    public func storeHeaders(
        _ headers: [MessageHeader],
        account: BrevAccount
    ) async {
        await index?.storeHeaders(headers, account: account)
    }

    public func storeRawMessage(
        _ data: Data,
        for messageID: MessageHeader.ID,
        account: BrevAccount
    ) async {
        await index?.storeRawMessage(data, for: messageID, account: account)
    }

    public func deleteMessages(
        _ messageIDs: [MessageHeader.ID],
        account: BrevAccount
    ) async {
        await index?.deleteMessages(messageIDs, account: account)
    }

    public func deleteRawMessages(
        _ messageIDs: [MessageHeader.ID],
        account: BrevAccount
    ) async {
        await index?.deleteRawMessages(messageIDs, account: account)
    }

    public func deleteRawMessages(
        inFolder folderID: Folder.ID,
        account: BrevAccount
    ) async {
        await index?.deleteRawMessages(inFolder: folderID, account: account)
    }

    public func deleteRawMessages(
        inFolder folderID: Folder.ID,
        except exceptMessageIDs: Set<MessageHeader.ID>,
        account: BrevAccount
    ) async {
        await index?.deleteRawMessages(inFolder: folderID, except: exceptMessageIDs, account: account)
    }

    public func clearFolder(
        folderID: Folder.ID,
        account: BrevAccount
    ) async {
        await index?.clearFolder(folderID: folderID, account: account)
    }

    public func clearAccount(_ account: BrevAccount) async {
        await index?.clearAccount(account)
    }

    public func metrics(for account: BrevAccount) async -> LocalSearchIndexMetrics? {
        await index?.metrics(for: account)
    }

    public func indexAttachmentText(
        accountID: String,
        messageID: MessageHeader.ID,
        folderID: Folder.ID,
        attachmentID: String,
        name: String,
        text: String
    ) async throws {
        try await index?.indexAttachmentText(
            accountID: accountID,
            messageID: messageID,
            folderID: folderID,
            attachmentID: attachmentID,
            name: name,
            text: text
        )
    }

    public func removeAttachmentText(accountID: String, messageIDs: [MessageHeader.ID]) async throws {
        try await index?.removeAttachmentText(accountID: accountID, messageIDs: messageIDs)
    }

    public func removeAllAttachmentText(accountID: String) async throws {
        try await index?.removeAllAttachmentText(accountID: accountID)
    }

    public func attachmentIndexBytes(accountID: String) async -> Int {
        await index?.attachmentIndexBytes(accountID: accountID) ?? 0
    }

    public func indexedAttachmentMessageIDs(accountID: String) async -> Set<MessageHeader.ID> {
        await index?.indexedAttachmentMessageIDs(accountID: accountID) ?? []
    }

    public func matchedAttachmentNames(
        matching query: SearchQuery,
        account: BrevAccount,
        messageIDs: [MessageHeader.ID]
    ) async -> [MessageHeader.ID: String] {
        await index?.matchedAttachmentNames(
            matching: query,
            account: account,
            messageIDs: messageIDs
        ) ?? [:]
    }
}
