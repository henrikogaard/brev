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

// MARK: - Sync tier

/// The IMAP sync protocol tier the engine uses for a given folder.
///
/// Tier selection is determined by whether the server advertised CONDSTORE
/// support in response to `SELECT ... (CONDSTORE)` (RFC 7162). Once
/// determined, the tier is persisted in the local store and re-evaluated
/// at most once per week or after account re-setup.
public enum SyncTier: Int, Codable, Sendable, CustomStringConvertible {
    /// The server supports CONDSTORE (RFC 7162). Delta sync via
    /// `HIGHESTMODSEQ` and `CHANGEDSINCE` is available. This is the
    /// preferred tier because it fetches only changed messages.
    case condstore = 0

    /// The server does not support CONDSTORE. A full `UID SEARCH 1:*`
    /// is required on each sync cycle to detect additions and deletions.
    case uidScan = 1

    public var description: String {
        switch self {
        case .condstore: return "condstore"
        case .uidScan: return "uid-scan"
        }
    }
}

// MARK: - FolderSyncState

/// Persistent record of the last known IMAP sync state for one folder.
///
/// Stored in the `folder_sync_state` SQLite table (ADR-0030 §Decision 1 schema).
/// Updated at the end of each successful sync cycle by `SyncEngineProtocol.syncFolder(_:using:)`.
///
/// This is a value type; the engine reads and writes it atomically via the
/// `SyncStoreProtocol` actor.
public struct FolderSyncState: Codable, Hashable, Sendable {
    /// The folder this state belongs to. Matches `Folder.id` (IMAP mailbox path).
    public var folderID: Folder.ID

    /// The account this folder belongs to.
    public var accountID: BrevAccount.ID

    /// Last seen UIDVALIDITY from the SELECT response (RFC 3501 §6.3.1).
    ///
    /// A value of `nil` means this folder has never been synced. A change in
    /// UIDVALIDITY between sync cycles means all cached UIDs are invalid and
    /// the engine must drop the folder's cached headers and start a fresh full
    /// sync.
    public var uidValidity: Int?

    /// Last confirmed HIGHESTMODSEQ from the SELECT response (RFC 7162 §3.1.1).
    ///
    /// `nil` when `syncTier` is `.uidScan` or when CONDSTORE has not yet been
    /// probed. `0` when CONDSTORE is confirmed but no modseq has been recorded
    /// yet (triggers a full CONDSTORE fetch on the next sync cycle).
    ///
    /// Typed `UInt64` because CONDSTORE mod-sequences are 63-bit unsigned values
    /// (RFC 7162 §3.1.1) that overflow a 32-bit `Int`. This also matches
    /// `IMAPMailboxHeaderCacheSnapshot.highestModSeq` and the rest of BrevBackend,
    /// so the value flows between the cache and sync layers without a cast.
    public var highestModSeq: UInt64?

    /// Smallest UID the server will assign to the next new message (RFC 3501 §6.3.1).
    ///
    /// Used as a short-circuit: if the server reports the same UIDNEXT and the
    /// same HIGHESTMODSEQ as the cached values, the folder has not changed and
    /// the sync cycle can skip the FETCH round-trip.
    public var uidNext: Int?

    /// Timestamp of the last completed, successful sync cycle.
    ///
    /// `nil` if this folder has never synced successfully. Used by
    /// `SyncScheduler` to deprioritise recently synced folders relative to
    /// stale ones.
    public var lastSyncDate: Date?

    /// The sync protocol tier in use for this folder (ADR-0030 §Decision 2).
    public var syncTier: SyncTier

    public init(
        folderID: Folder.ID,
        accountID: BrevAccount.ID,
        uidValidity: Int? = nil,
        highestModSeq: UInt64? = nil,
        uidNext: Int? = nil,
        lastSyncDate: Date? = nil,
        syncTier: SyncTier = .condstore
    ) {
        self.folderID = folderID
        self.accountID = accountID
        self.uidValidity = uidValidity
        self.highestModSeq = highestModSeq
        self.uidNext = uidNext
        self.lastSyncDate = lastSyncDate
        self.syncTier = syncTier
    }
}
