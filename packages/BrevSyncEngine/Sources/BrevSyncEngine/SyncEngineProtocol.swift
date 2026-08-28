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

// MARK: - Folder sync operation

/// Async callback the sync engine invokes to execute one round of IMAP
/// protocol work for a given folder (SELECT, FETCH, SEARCH).
///
/// The closure receives the account configuration and credential already held
/// by `IMAPSMTPBackend` and returns a `FolderSyncResult` describing what the
/// server reported. The engine uses the result to update `FolderSyncState`
/// and emit `MailEvent` stream entries. The closure is injected rather than
/// baked into the engine so tests can provide scripted responses without
/// opening real sockets.
public typealias FolderSyncOperation =
    @Sendable (BrevAccount, Folder) async throws -> FolderSyncResult

// MARK: - Sync result

/// Summary of one completed folder sync round-trip returned by `FolderSyncOperation`.
public struct FolderSyncResult: Sendable {
    /// UIDVALIDITY value from the SELECT response (RFC 3501 §6.3.1).
    public var uidValidity: Int
    /// UIDNEXT value from the SELECT response.
    public var uidNext: Int
    /// HIGHESTMODSEQ if the server supports CONDSTORE (RFC 7162); `nil` otherwise.
    ///
    /// `UInt64` to hold the full 63-bit mod-sequence range and match
    /// `IMAPMailboxHeaderCacheSnapshot.highestModSeq` without a cast.
    public var highestModSeq: UInt64?
    /// Headers for messages added or updated during this sync round.
    public var updatedHeaders: [MessageHeader]
    /// Message IDs that the server reports as expunged since the last sync.
    public var expungedMessageIDs: [MessageHeader.ID]

    public init(
        uidValidity: Int,
        uidNext: Int,
        highestModSeq: UInt64? = nil,
        updatedHeaders: [MessageHeader] = [],
        expungedMessageIDs: [MessageHeader.ID] = []
    ) {
        self.uidValidity = uidValidity
        self.uidNext = uidNext
        self.highestModSeq = highestModSeq
        self.updatedHeaders = updatedHeaders
        self.expungedMessageIDs = expungedMessageIDs
    }
}

// MARK: - Invalidation reason

/// Reason passed to `SyncEngineProtocol.invalidate(folder:reason:)` so the
/// engine can choose the appropriate cleanup action.
public enum SyncInvalidationReason: Sendable {
    /// UIDVALIDITY changed; all cached UIDs for this folder are invalid.
    case uidValidityChanged
    /// The folder was renamed or deleted; all cached state is stale.
    case folderRemoved
    /// A mutation was applied to the folder; the engine should re-sync
    /// at the next opportunity instead of relying on its cached modseq.
    case mutationApplied
}

// MARK: - Protocol

/// The public interface `IMAPSMTPBackend` holds to drive folder-wide IMAP sync.
///
/// Conforming types own a persistent SQLite index of message headers and bodies
/// (ADR-0030 §Decision 1), implement the two-tier CONDSTORE / UID-scan sync
/// protocol (§Decision 2), and update `FolderSyncState` after each cycle.
///
/// `BrevBackend` imports this protocol type but not any concrete conformance.
/// The concrete `BrevSyncEngine` implementation lives in this package.
///
/// Thread safety: all methods are `async` and are safe to call from any
/// concurrency context. Concrete conformances are expected to be actors.
public protocol SyncEngineProtocol: Sendable {
    // MARK: Sync

    /// Execute one sync cycle for `folder` using the provided operation closure.
    ///
    /// The engine selects the appropriate tier (CONDSTORE or UID-scan) based on
    /// the stored `FolderSyncState.syncTier` for this folder, calls `operation`
    /// to perform the IMAP work, reconciles the result against the local store,
    /// and emits `MailEvent` entries through the backend's change stream.
    ///
    /// - Parameters:
    ///   - folder: The folder to sync. Must belong to `account`.
    ///   - account: The account that owns this folder.
    ///   - operation: A closure that performs the actual IMAP protocol work
    ///     and returns a `FolderSyncResult`. Injected for testability.
    func syncFolder(
        _ folder: Folder,
        for account: BrevAccount,
        using operation: FolderSyncOperation
    ) async throws

    // MARK: Reading cached data

    /// Returns cached message headers for `folder`, applying the same
    /// page-token pagination used by the live `MailBackend.messages(in:pageToken:)`
    /// path so callers see a consistent interface.
    ///
    /// Returns `nil` when no data is available for this folder (cold start or
    /// after a UIDVALIDITY invalidation). Callers should fall back to the live
    /// IMAP fetch path in that case.
    ///
    /// - Parameters:
    ///   - folder: The folder to read headers for.
    ///   - account: The account that owns this folder.
    ///   - pageToken: Opaque token from a previous call; `nil` requests the
    ///     first page (newest messages first).
    /// - Returns: A tuple of headers and the next page token, or `nil` if the
    ///   local store has no data for this folder.
    func cachedHeaders(
        for folder: Folder,
        account: BrevAccount,
        pageToken: String?
    ) async -> (headers: [MessageHeader], nextPageToken: String?)?

    /// Returns the cached raw RFC 5322 message source bytes for `messageID`,
    /// or `nil` if the body has not yet been fetched and stored locally.
    ///
    /// The caller is responsible for parsing the raw bytes into a `MessageBody`;
    /// the sync engine stores the raw source to avoid coupling to any particular
    /// MIME parser.
    ///
    /// - Parameters:
    ///   - messageID: The stable `MessageHeader.ID` for the message.
    ///   - account: The account that owns this message.
    func cachedBody(
        for messageID: MessageHeader.ID,
        account: BrevAccount
    ) async -> Data?

    /// Searches the local persistent sync index for headers matching `query`.
    ///
    /// Implementations search cached headers and any locally cached raw message
    /// bodies without making a provider/network request. This is the durable
    /// local-search surface used by generic IMAP once `BrevSyncEngine` is
    /// injected at runtime.
    func search(
        _ query: SearchQuery,
        account: BrevAccount,
        limit: Int
    ) async -> [MessageHeader]

    // MARK: Invalidation

    /// Clears or marks stale the cached state for `folder` according to `reason`.
    ///
    /// Called by `IMAPSMTPBackend` when it detects a UIDVALIDITY change, after a
    /// folder rename or delete, or after applying a mutation that should prompt
    /// an early re-sync.
    ///
    /// - Parameters:
    ///   - folder: The folder whose cached state should be invalidated.
    ///   - account: The account that owns this folder.
    ///   - reason: The reason for invalidation; determines whether UIDs are
    ///     cleared immediately or only flagged for re-verification.
    func invalidate(
        folder: Folder,
        account: BrevAccount,
        reason: SyncInvalidationReason
    ) async

    // MARK: State inspection

    /// Returns the current sync state for `folder`, or `nil` if the folder has
    /// never been synced.
    func syncState(
        for folder: Folder,
        account: BrevAccount
    ) async -> FolderSyncState?

    /// Marks `messageIDs` as dirty so the sync engine skips overwriting their
    /// flags until the queued mutations are flushed (ADR-0030 §Decision 6).
    ///
    /// Called by `IMAPSMTPBackend` when it enqueues a mutation for a message.
    func markDirty(
        messageIDs: [MessageHeader.ID],
        account: BrevAccount
    ) async

    /// Clears the dirty flag for `messageIDs` after the offline mutation
    /// processor successfully replays the corresponding mutations.
    func clearDirty(
        messageIDs: [MessageHeader.ID],
        account: BrevAccount
    ) async
}

public extension SyncEngineProtocol {
    func search(
        _ query: SearchQuery,
        account: BrevAccount
    ) async -> [MessageHeader] {
        await search(query, account: account, limit: 200)
    }
}
