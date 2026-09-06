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

// MARK: - BrevSyncEngine

/// Concrete implementation of `SyncEngineProtocol` backed by a persistent
/// SQLite store (ADR-0030).
///
/// ## Sync algorithm
///
/// Each `syncFolder` call executes one complete sync cycle for the given folder:
///
/// 1. Call the injected `FolderSyncOperation` to obtain a `FolderSyncResult`.
/// 2. Detect UIDVALIDITY changes; clear the local cache when one is found.
/// 3. Upsert received headers, skipping messages with queued local mutations
///    (`is_dirty = 1`).
/// 4. Delete expunged message IDs.
/// 5. Persist the updated `FolderSyncState`.
///
/// ## Tier selection
///
/// Tier is inferred from `FolderSyncResult.highestModSeq`: a non-nil value
/// means the server supports CONDSTORE and the sync engine records
/// `.condstore`; `nil` records `.uidScan`. The IMAP work itself (the
/// CHANGEDSINCE fetch vs. full UID SEARCH) is performed by the
/// `FolderSyncOperation` closure injected at call time — the engine only
/// interprets the result.
///
/// ## Pagination
///
/// `cachedHeaders` uses LIMIT/OFFSET pagination ordered by `(date DESC, uid
/// DESC)`. The page token is a string-encoded integer offset (`"50"`, `"100"`,
/// etc.).  `nil` token requests the first page.
///
/// ## Body storage
///
/// `cachedBody` reads raw RFC 5322 source bytes stored via `storeBody(_:for:account:)`,
/// which is a public method on the concrete type (not part of `SyncEngineProtocol`).
/// `IMAPSMTPBackend` can call it after fetching a message body to populate the cache.
public actor BrevSyncEngine: SyncEngineProtocol, MailLocalSearchIndex {
    private static let pageSize = 50

    let store: any SyncStoreProtocol

    // MARK: Init

    /// Creates an engine backed by a new SQLite store at `databaseURL`.
    public init(databaseURL: URL) throws {
        store = try SQLiteSyncStore(databaseURL: databaseURL)
    }

    /// Creates an engine with a custom store. Intended for unit tests.
    init(store: any SyncStoreProtocol) {
        self.store = store
    }

    // MARK: Convenience factory

    /// Returns the default database URL for a given account.
    public static func defaultDatabaseURL(accountID: String) -> URL {
        SQLiteSyncStore.defaultURL(accountID: accountID)
    }

    // MARK: SyncEngineProtocol — sync

    public func syncFolder(
        _ folder: Folder,
        for account: BrevAccount,
        using operation: FolderSyncOperation
    ) async throws {
        try await store.ensureAccount(id: account.id)

        let result = try await operation(account, folder)

        // Detect UIDVALIDITY change and clear stale cache.
        let existingState = await store.syncState(accountID: account.id, folderID: folder.id)
        if let prev = existingState?.uidValidity, prev != result.uidValidity {
            // Clear headers and sync state atomically so a crash cannot leave a
            // ghost folder (stale headers with no sync state, or vice versa).
            try await store.clearFolder(accountID: account.id, folderID: folder.id)
        }

        // Skip headers for messages that have queued local mutations.
        let dirtyIDs = await Set(store.dirtyMessageIDs(accountID: account.id))
        let headersToStore = result.updatedHeaders.filter { !dirtyIDs.contains($0.id) }
        if !headersToStore.isEmpty {
            try await store.upsertHeaders(headersToStore, accountID: account.id)
        }

        if !result.expungedMessageIDs.isEmpty {
            try await store.deleteHeaders(
                messageIDs: result.expungedMessageIDs,
                accountID: account.id
            )
        }

        // Persist the updated sync state.
        let tier: SyncTier = result.highestModSeq != nil ? .condstore : .uidScan
        let newState = FolderSyncState(
            folderID: folder.id,
            accountID: account.id,
            uidValidity: result.uidValidity,
            highestModSeq: result.highestModSeq,
            uidNext: result.uidNext,
            lastSyncDate: Date(),
            syncTier: tier
        )
        try await store.setSyncState(newState)
    }

    // MARK: SyncEngineProtocol — reading cached data

    public func cachedHeaders(
        for folder: Folder,
        account: BrevAccount,
        pageToken: String?
    ) async -> (headers: [MessageHeader], nextPageToken: String?)? {
        // Return nil (not an empty page) when no sync has ever completed for this folder.
        guard await store.syncState(accountID: account.id, folderID: folder.id) != nil else {
            return nil
        }

        let offset: Int
        if let pageToken {
            guard let parsedOffset = Int(pageToken) else { return nil }
            offset = parsedOffset
        } else {
            offset = 0
        }
        // Fetch one extra row to determine whether a next page exists.
        let fetched = await store.headers(
            accountID: account.id,
            folderID: folder.id,
            limit: Self.pageSize + 1,
            offset: offset
        )

        if fetched.count > Self.pageSize {
            return (
                headers: Array(fetched.prefix(Self.pageSize)),
                nextPageToken: "\(offset + Self.pageSize)"
            )
        }
        return (headers: fetched, nextPageToken: nil)
    }

    public func cachedBody(
        for messageID: MessageHeader.ID,
        account: BrevAccount
    ) async -> Data? {
        await store.body(accountID: account.id, messageID: messageID)
    }

    public func cachedRawMessage(
        for messageID: MessageHeader.ID,
        account: BrevAccount
    ) async -> Data? {
        await cachedBody(for: messageID, account: account)
    }

    /// Returns source bytes only when the cache records their original MIME provenance.
    public func cachedOriginalRawMessage(for messageID: MessageHeader.ID, account: BrevAccount) async -> Data? {
        await store.originalBody(accountID: account.id, messageID: messageID)
    }

    /// Persists original source and provenance together using the normal content-cache lifecycle.
    public func storeOriginalRawMessage(_ data: Data, for messageID: MessageHeader.ID, account: BrevAccount) async {
        do {
            try await store.ensureAccount(id: account.id)
            try await store.storeOriginalBody(data, accountID: account.id, messageID: messageID)
        } catch { return }
    }

    public func search(
        _ query: SearchQuery,
        account: BrevAccount,
        limit: Int = 200
    ) async -> [MessageHeader] {
        guard query.hasSearchCriteria else { return [] }
        return await store.searchHeaders(query, accountID: account.id, limit: limit)
    }

    public func storeHeaders(
        _ headers: [MessageHeader],
        account: BrevAccount
    ) async {
        guard !headers.isEmpty else { return }
        do {
            try await store.ensureAccount(id: account.id)
            let dirtyIDs = await Set(store.dirtyMessageIDs(accountID: account.id))
            let headersToStore = headers.filter { !dirtyIDs.contains($0.id) }
            guard !headersToStore.isEmpty else { return }
            try await store.upsertHeaders(headersToStore, accountID: account.id)
            await markFoldersCached(Set(headersToStore.map(\.folderID)), account: account)
        } catch {
            return
        }
    }

    private func markFoldersCached(_ folderIDs: Set<Folder.ID>, account: BrevAccount) async {
        for folderID in folderIDs {
            guard await store.syncState(accountID: account.id, folderID: folderID) == nil else {
                continue
            }
            try? await store.setSyncState(FolderSyncState(
                folderID: folderID,
                accountID: account.id,
                lastSyncDate: Date(),
                syncTier: .uidScan
            ))
        }
    }

    public func storeRawMessage(
        _ data: Data,
        for messageID: MessageHeader.ID,
        account: BrevAccount
    ) async {
        await storeBody(data, for: messageID, account: account)
    }

    public func deleteMessages(
        _ messageIDs: [MessageHeader.ID],
        account: BrevAccount
    ) async {
        try? await store.deleteHeaders(messageIDs: messageIDs, accountID: account.id)
    }

    public func deleteRawMessages(
        _ messageIDs: [MessageHeader.ID],
        account: BrevAccount
    ) async {
        try? await store.deleteBodies(messageIDs: messageIDs, accountID: account.id)
    }

    public func deleteRawMessages(
        inFolder folderID: Folder.ID,
        account: BrevAccount
    ) async {
        try? await store.deleteBodies(accountID: account.id, folderID: folderID)
    }

    public func deleteRawMessages(
        inFolder folderID: Folder.ID,
        except exceptMessageIDs: Set<MessageHeader.ID>,
        account: BrevAccount
    ) async {
        try? await store.deleteBodies(
            accountID: account.id,
            folderID: folderID,
            exceptMessageIDs: exceptMessageIDs
        )
    }

    public func clearFolder(
        folderID: Folder.ID,
        account: BrevAccount
    ) async {
        try? await store.clearFolder(accountID: account.id, folderID: folderID)
    }

    public func clearAccount(_ account: BrevAccount) async {
        try? await store.clearAccount(id: account.id)
    }

    public func metrics(for account: BrevAccount) async -> LocalSearchIndexMetrics? {
        await store.metrics(accountID: account.id)
    }

    // MARK: SyncEngineProtocol — invalidation

    public func invalidate(
        folder: Folder,
        account: BrevAccount,
        reason: SyncInvalidationReason
    ) async {
        switch reason {
        case .uidValidityChanged, .folderRemoved:
            // Single transaction: avoids a ghost-folder window on crash.
            try? await store.clearFolder(accountID: account.id, folderID: folder.id)

        case .mutationApplied:
            // Reset HIGHESTMODSEQ to 0 so the next sync performs a full CONDSTORE
            // fetch rather than relying on a potentially stale watermark.
            if var state = await store.syncState(accountID: account.id, folderID: folder.id) {
                state.highestModSeq = 0
                try? await store.setSyncState(state)
            }
        }
    }

    // MARK: SyncEngineProtocol — state inspection

    public func syncState(
        for folder: Folder,
        account: BrevAccount
    ) async -> FolderSyncState? {
        await store.syncState(accountID: account.id, folderID: folder.id)
    }

    public func markDirty(
        messageIDs: [MessageHeader.ID],
        account: BrevAccount
    ) async {
        try? await store.setDirty(true, messageIDs: messageIDs, accountID: account.id)
    }

    public func clearDirty(
        messageIDs: [MessageHeader.ID],
        account: BrevAccount
    ) async {
        try? await store.setDirty(false, messageIDs: messageIDs, accountID: account.id)
    }

    // MARK: Body storage (beyond protocol)

    /// Persists raw RFC 5322 message source bytes so `cachedBody(for:account:)` can
    /// serve them without an IMAP round-trip.
    ///
    /// Call this from `IMAPSMTPBackend` after a successful body fetch, passing the
    /// same `account` and `messageID` used in the fetch.
    public func storeBody(
        _ data: Data,
        for messageID: MessageHeader.ID,
        account: BrevAccount
    ) async {
        try? await store.ensureAccount(id: account.id)
        try? await store.storeBody(data, accountID: account.id, messageID: messageID)
    }
}
