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

/// Lightweight, provider-neutral metrics for a local mail search index.
///
/// Counts describe Brev-owned local records only. They intentionally avoid
/// exposing subjects, addresses, folder names, query text, or message content.
public struct LocalSearchIndexMetrics: Sendable, Hashable, Codable {
    public let databaseBytes: Int64
    public let indexedHeaderCount: Int
    public let cachedBodyCount: Int
    public let searchDocumentCount: Int
    public let syncedFolderCount: Int

    public init(
        databaseBytes: Int64,
        indexedHeaderCount: Int,
        cachedBodyCount: Int,
        searchDocumentCount: Int,
        syncedFolderCount: Int
    ) {
        self.databaseBytes = databaseBytes
        self.indexedHeaderCount = indexedHeaderCount
        self.cachedBodyCount = cachedBodyCount
        self.searchDocumentCount = searchDocumentCount
        self.syncedFolderCount = syncedFolderCount
    }
}

/// Provider-neutral local mail index used by standards-first backends.
///
/// The concrete implementation lives outside `BrevBackend` so the backend
/// package never imports a SQLite engine directly. Methods are best-effort:
/// callers keep the existing cache/network fallback behavior when an index is
/// absent or cold.
public protocol MailLocalSearchIndex: Sendable {
    func cachedHeaders(
        for folder: Folder,
        account: BrevAccount,
        pageToken: String?
    ) async -> (headers: [MessageHeader], nextPageToken: String?)?

    func cachedRawMessage(
        for messageID: MessageHeader.ID,
        account: BrevAccount
    ) async -> Data?

    func search(
        _ query: SearchQuery,
        account: BrevAccount,
        limit: Int
    ) async -> [MessageHeader]

    func storeHeaders(
        _ headers: [MessageHeader],
        account: BrevAccount
    ) async

    func storeRawMessage(
        _ data: Data,
        for messageID: MessageHeader.ID,
        account: BrevAccount
    ) async

    func deleteMessages(
        _ messageIDs: [MessageHeader.ID],
        account: BrevAccount
    ) async

    func deleteRawMessages(
        _ messageIDs: [MessageHeader.ID],
        account: BrevAccount
    ) async

    func deleteRawMessages(
        inFolder folderID: Folder.ID,
        account: BrevAccount
    ) async

    /// Like `deleteRawMessages(inFolder:account:)` but keeps every body
    /// whose ID is in `except`. Also evicts orphan bodies (bodies with no
    /// matching header row) because the purge is prefix-based.
    func deleteRawMessages(
        inFolder folderID: Folder.ID,
        except exceptMessageIDs: Set<MessageHeader.ID>,
        account: BrevAccount
    ) async

    func clearFolder(
        folderID: Folder.ID,
        account: BrevAccount
    ) async

    func clearAccount(_ account: BrevAccount) async

    /// Returns privacy-safe persistence metrics for rebuild/readiness validation.
    ///
    /// Implementations must provide metrics so long-running download/index
    /// operations can prove headers, bodies, and search documents were actually
    /// persisted before reporting a ready local index.
    func metrics(for account: BrevAccount) async -> LocalSearchIndexMetrics?
}

public extension MailLocalSearchIndex {
    func search(
        _ query: SearchQuery,
        account: BrevAccount
    ) async -> [MessageHeader] {
        await search(query, account: account, limit: 200)
    }
}
