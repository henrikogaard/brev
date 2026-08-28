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

// MARK: - Error

enum SyncStoreError: Error {
    case openFailed(String)
    case prepareFailed(String)
    case executeFailed(String)
    case encodingFailed(any Error)
    /// The on-disk schema is newer than this build knows how to read
    /// (`PRAGMA user_version` exceeds `currentSchemaVersion`). Refuse to open
    /// rather than corrupt data written by a future version.
    case unknownSchemaVersion(found: Int, supported: Int)
}

// MARK: - SQLite sync store

/// Persistent SQLite-backed implementation of `SyncStoreProtocol` (ADR-0030).
///
/// Schema version 3. All writes use WAL journal mode for concurrent-read safety.
/// The NSLock serialises access from the BrevSyncEngine actor, which is the sole
/// owner of this store in production.
final class SQLiteSyncStore: SyncStoreProtocol, @unchecked Sendable {
    let currentSchemaVersion = 3

    private let lock = NSLock()
    private let db: OpaquePointer?
    private let databaseURL: URL

    // Shared encoder/decoder. DateEncodingStrategy must match SQLite date_ts extraction.
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    /// "No `LIMIT`" sentinel for the candidate scan (`-1` is SQLite's documented
    /// unbounded value). The metadata-only path (no free-text token) must
    /// over-fetch because the final predicates (isUnread/isFlagged/from/to) are
    /// applied in Swift, not SQL. The folder and date-range predicates are pushed
    /// into SQL to shrink the scan; capping further needs is_unread/is_flagged
    /// columns (schema migration). The FTS-miss path no longer falls through here
    /// — when FTS returns empty for a text query, the search short-circuits.
    private static let unboundedSearchCandidateLimit = -1

    // MARK: Init / deinit

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var ptr: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &ptr, flags, nil) == SQLITE_OK else {
            let msg = ptr.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(ptr)
            throw SyncStoreError.openFailed(msg)
        }
        db = ptr
        // Retry instead of throwing SQLITE_BUSY when another connection (WAL
        // checkpoint or an App-Group extension) holds a write lock.
        sqlite3_busy_timeout(ptr, 3000)
        try applyPragmas()
        try migrateIfNeeded()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: Default URL

    static func defaultURL(accountID: String) -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return defaultURL(accountID: accountID, applicationSupportDirectory: appSupport)
    }

    static func defaultURL(
        accountID: String,
        applicationSupportDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let directory = applicationSupportDirectory
            .appendingPathComponent("Brev", isDirectory: true)
            .appendingPathComponent("sync-cache", isDirectory: true)
        let encodedURL = directory.appendingPathComponent("\(hexKey(accountID)).sqlite")
        migrateLegacyDefaultFilesIfNeeded(
            accountID: accountID,
            directory: directory,
            encodedURL: encodedURL,
            fileManager: fileManager
        )
        return encodedURL
    }

    private static func migrateLegacyDefaultFilesIfNeeded(
        accountID: String,
        directory: URL,
        encodedURL: URL,
        fileManager: FileManager
    ) {
        let legacyURL = directory.appendingPathComponent("\(accountID).sqlite")
        guard legacyURL != encodedURL,
              fileManager.fileExists(atPath: legacyURL.path),
              !fileManager.fileExists(atPath: encodedURL.path)
        else { return }

        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        for suffix in ["", "-wal", "-shm"] {
            let legacyFileURL = URL(fileURLWithPath: legacyURL.path + suffix)
            let encodedFileURL = URL(fileURLWithPath: encodedURL.path + suffix)
            guard fileManager.fileExists(atPath: legacyFileURL.path),
                  !fileManager.fileExists(atPath: encodedFileURL.path)
            else { continue }
            try? fileManager.moveItem(at: legacyFileURL, to: encodedFileURL)
        }
    }

    private static func hexKey(_ value: String) -> String {
        value.utf8.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: SyncStoreProtocol — accounts

    func ensureAccount(id: String) throws {
        try lock.withLock {
            var stmt: OpaquePointer?
            let sql = "INSERT OR IGNORE INTO accounts (id, created_at) VALUES (?, ?);"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SyncStoreError.prepareFailed("ensureAccount prepare failed")
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id, -1, Self.transient)
            sqlite3_bind_int64(stmt, 2, Int64(Date().timeIntervalSince1970))
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SyncStoreError.executeFailed(errMsg())
            }
        }
    }

    func clearAccount(id: String) throws {
        try lock.withLock {
            try execSQL("BEGIN IMMEDIATE;")
            do {
                try execStmt(
                    "DELETE FROM message_search WHERE account_id = ?;",
                    bindings: [.text(id)]
                )
                try execStmt(
                    "DELETE FROM message_bodies WHERE account_id = ?;",
                    bindings: [.text(id)]
                )
                try execStmt(
                    "DELETE FROM message_headers WHERE account_id = ?;",
                    bindings: [.text(id)]
                )
                try execStmt(
                    "DELETE FROM folder_sync_state WHERE account_id = ?;",
                    bindings: [.text(id)]
                )
                try execStmt(
                    "DELETE FROM accounts WHERE id = ?;",
                    bindings: [.text(id)]
                )
            } catch {
                try? execSQL("ROLLBACK;")
                throw error
            }
            try execSQL("COMMIT;")
        }
    }

    // MARK: SyncStoreProtocol — folder sync state

    func syncState(accountID: String, folderID: String) -> FolderSyncState? {
        lock.withLock {
            var stmt: OpaquePointer?
            let sql = """
                SELECT uid_validity, highest_mod_seq, uid_next,
                       last_sync_date, sync_tier
                FROM folder_sync_state
                WHERE account_id = ? AND folder_id = ?
                LIMIT 1;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, accountID, -1, Self.transient)
            sqlite3_bind_text(stmt, 2, folderID, -1, Self.transient)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            // `Int` is 64-bit on every supported platform (macOS 14 / iOS 17),
            // so the int64 round-trip for uid_validity / uid_next is lossless.
            let uidValidity = sqlite3_column_type(stmt, 0) != SQLITE_NULL
                ? Int(sqlite3_column_int64(stmt, 0)) : nil
            // highest_mod_seq is stored as a signed int64 via its bit pattern;
            // reinterpret it as UInt64 so the full 63-bit CONDSTORE range survives.
            let highestModSeq = sqlite3_column_type(stmt, 1) != SQLITE_NULL
                ? UInt64(bitPattern: sqlite3_column_int64(stmt, 1)) : nil
            let uidNext = sqlite3_column_type(stmt, 2) != SQLITE_NULL
                ? Int(sqlite3_column_int64(stmt, 2)) : nil
            let lastSyncTs = sqlite3_column_type(stmt, 3) != SQLITE_NULL
                ? TimeInterval(sqlite3_column_int64(stmt, 3)) : nil
            let syncTierRaw = Int(sqlite3_column_int64(stmt, 4))

            return FolderSyncState(
                folderID: folderID,
                accountID: accountID,
                uidValidity: uidValidity,
                highestModSeq: highestModSeq,
                uidNext: uidNext,
                lastSyncDate: lastSyncTs.map { Date(timeIntervalSince1970: $0) },
                syncTier: SyncTier(rawValue: syncTierRaw) ?? .condstore
            )
        }
    }

    func setSyncState(_ state: FolderSyncState) throws {
        try lock.withLock {
            var stmt: OpaquePointer?
            let sql = """
                INSERT INTO folder_sync_state
                    (account_id, folder_id, uid_validity, highest_mod_seq, uid_next,
                     last_sync_date, sync_tier)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(account_id, folder_id) DO UPDATE SET
                    uid_validity    = excluded.uid_validity,
                    highest_mod_seq = excluded.highest_mod_seq,
                    uid_next        = excluded.uid_next,
                    last_sync_date  = excluded.last_sync_date,
                    sync_tier       = excluded.sync_tier;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SyncStoreError.prepareFailed(errMsg())
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, state.accountID, -1, Self.transient)
            sqlite3_bind_text(stmt, 2, state.folderID, -1, Self.transient)
            bindNullableInt(stmt, 3, state.uidValidity)
            bindNullableModSeq(stmt, 4, state.highestModSeq)
            bindNullableInt(stmt, 5, state.uidNext)
            if let d = state.lastSyncDate {
                sqlite3_bind_int64(stmt, 6, Int64(d.timeIntervalSince1970))
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            sqlite3_bind_int64(stmt, 7, Int64(state.syncTier.rawValue))

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SyncStoreError.executeFailed(errMsg())
            }
        }
    }

    func deleteSyncState(accountID: String, folderID: String) throws {
        try lock.withLock {
            try execStmt(
                "DELETE FROM folder_sync_state WHERE account_id = ? AND folder_id = ?;",
                bindings: [.text(accountID), .text(folderID)]
            )
        }
    }

    // MARK: SyncStoreProtocol — message headers

    func headers(
        accountID: String,
        folderID: String,
        limit: Int,
        offset: Int
    ) -> [MessageHeader] {
        lock.withLock {
            headersUnlocked(
                accountID: accountID,
                folderID: folderID,
                limit: limit,
                offset: offset
            )
        }
    }

    func upsertHeaders(_ headers: [MessageHeader], accountID: String) throws {
        guard !headers.isEmpty else { return }
        try lock.withLock {
            let sql = """
                INSERT INTO message_headers
                    (account_id, folder_id, uid, message_id, date_ts, header_json)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(account_id, folder_id, uid) DO UPDATE SET
                    message_id  = excluded.message_id,
                    date_ts     = excluded.date_ts,
                    header_json = excluded.header_json
                WHERE is_dirty = 0;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SyncStoreError.prepareFailed(errMsg())
            }
            defer { sqlite3_finalize(stmt) }

            // Wrap the batch in one transaction so a crash mid-loop cannot leave a
            // partially-written index; roll back on any error before rethrowing.
            try execSQL("BEGIN IMMEDIATE;")
            do {
                for header in headers {
                    let uid = Self.uid(from: header.id)
                    let previousMessageID = messageID(
                        accountID: accountID,
                        folderID: header.folderID,
                        uid: uid
                    )
                    let data: Data
                    do {
                        data = try Self.encoder.encode(header)
                    } catch {
                        throw SyncStoreError.encodingFailed(error)
                    }
                    sqlite3_bind_text(stmt, 1, accountID, -1, Self.transient)
                    sqlite3_bind_text(stmt, 2, header.folderID, -1, Self.transient)
                    sqlite3_bind_int64(stmt, 3, Int64(uid))
                    sqlite3_bind_text(stmt, 4, header.id, -1, Self.transient)
                    sqlite3_bind_int64(stmt, 5, Int64(header.date.timeIntervalSince1970))
                    _ = data.withUnsafeBytes { bytes in
                        sqlite3_bind_blob(stmt, 6, bytes.baseAddress, Int32(data.count), Self.transient)
                    }
                    guard sqlite3_step(stmt) == SQLITE_DONE else {
                        throw SyncStoreError.executeFailed(errMsg())
                    }
                    let headerWasStored = sqlite3_changes(db) > 0
                    sqlite3_reset(stmt)
                    sqlite3_clear_bindings(stmt)
                    if headerWasStored {
                        if let previousMessageID, previousMessageID != header.id {
                            let staleMessageIDs = [previousMessageID][...]
                            try deleteSearchRows(messageIDs: staleMessageIDs, accountID: accountID)
                            try deleteBodies(messageIDs: staleMessageIDs, accountID: accountID)
                        }
                        // On CONDSTORE refreshes (flag-only updates) the already-indexed
                        // body text is reused to avoid re-running the full MIME parser
                        // while the store lock is held. Falls back to bodyTextForSearch
                        // only when no search row exists yet (e.g. body arrived before
                        // this header via storeBody, which didn't create the row).
                        let bodyText = existingSearchBodyText(
                            accountID: accountID,
                            messageID: header.id
                        ) ?? bodyTextForSearch(accountID: accountID, messageID: header.id)
                        try upsertSearchRow(header, accountID: accountID, bodyText: bodyText)
                    }
                }
            } catch {
                try? execSQL("ROLLBACK;")
                throw error
            }
            try execSQL("COMMIT;")
        }
    }

    /// SQLite caps bound variables per prepared statement
    /// (`SQLITE_MAX_VARIABLE_NUMBER` — 999 on older builds, 32766 on newer). A
    /// folder that expunges or dirties more messages than that in one cycle would
    /// otherwise overflow a single `IN (?, …)` and fail `prepare`, aborting the
    /// whole sync write. Chunk well under the floor.
    private static let messageIDChunkSize = 400

    private func forEachMessageIDChunk(
        _ messageIDs: [MessageHeader.ID],
        _ body: (ArraySlice<MessageHeader.ID>) throws -> Void
    ) throws {
        var start = messageIDs.startIndex
        while start < messageIDs.endIndex {
            let end = messageIDs.index(
                start, offsetBy: Self.messageIDChunkSize, limitedBy: messageIDs.endIndex
            ) ?? messageIDs.endIndex
            try body(messageIDs[start ..< end])
            start = end
        }
    }

    func deleteHeaders(messageIDs: [MessageHeader.ID], accountID: String) throws {
        guard !messageIDs.isEmpty else { return }
        try lock.withLock {
            // One transaction across all chunks so a partial failure can't leave
            // some of the expunged headers behind.
            try execSQL("BEGIN IMMEDIATE;")
            do {
                try forEachMessageIDChunk(messageIDs) { chunk in
                    try deleteSearchRows(messageIDs: chunk, accountID: accountID)
                    try deleteBodies(messageIDs: chunk, accountID: accountID)
                    let placeholders = chunk.map { _ in "?" }.joined(separator: ", ")
                    let sql = """
                        DELETE FROM message_headers
                        WHERE account_id = ? AND message_id IN (\(placeholders));
                    """
                    var stmt: OpaquePointer?
                    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                        throw SyncStoreError.prepareFailed(errMsg())
                    }
                    defer { sqlite3_finalize(stmt) }

                    sqlite3_bind_text(stmt, 1, accountID, -1, Self.transient)
                    for (index, id) in chunk.enumerated() {
                        sqlite3_bind_text(stmt, Int32(index + 2), id, -1, Self.transient)
                    }
                    guard sqlite3_step(stmt) == SQLITE_DONE else {
                        throw SyncStoreError.executeFailed(errMsg())
                    }
                }
            } catch {
                try? execSQL("ROLLBACK;")
                throw error
            }
            try execSQL("COMMIT;")
        }
    }

    func clearHeaders(accountID: String, folderID: String) throws {
        try lock.withLock {
            try execSQL("BEGIN IMMEDIATE;")
            do {
                try deleteBodiesForFolder(accountID: accountID, folderID: folderID)
                try deleteBodiesByMessageIDPrefix(accountID: accountID, folderID: folderID)
                try execStmt(
                    "DELETE FROM message_search WHERE account_id = ? AND folder_id = ?;",
                    bindings: [.text(accountID), .text(folderID)]
                )
                try execStmt(
                    "DELETE FROM message_headers WHERE account_id = ? AND folder_id = ?;",
                    bindings: [.text(accountID), .text(folderID)]
                )
            } catch {
                try? execSQL("ROLLBACK;")
                throw error
            }
            try execSQL("COMMIT;")
        }
    }

    func clearFolder(accountID: String, folderID: String) throws {
        try lock.withLock {
            // Both deletes in one transaction so an interrupted invalidation cannot
            // leave a ghost folder (headers without sync state, or vice versa).
            try execSQL("BEGIN IMMEDIATE;")
            do {
                try deleteBodiesForFolder(accountID: accountID, folderID: folderID)
                try deleteBodiesByMessageIDPrefix(accountID: accountID, folderID: folderID)
                try execStmt(
                    "DELETE FROM message_search WHERE account_id = ? AND folder_id = ?;",
                    bindings: [.text(accountID), .text(folderID)]
                )
                try execStmt(
                    "DELETE FROM message_headers WHERE account_id = ? AND folder_id = ?;",
                    bindings: [.text(accountID), .text(folderID)]
                )
                try execStmt(
                    "DELETE FROM folder_sync_state WHERE account_id = ? AND folder_id = ?;",
                    bindings: [.text(accountID), .text(folderID)]
                )
            } catch {
                try? execSQL("ROLLBACK;")
                throw error
            }
            try execSQL("COMMIT;")
        }
    }

    func allUIDs(accountID: String, folderID: String) -> [Int] {
        lock.withLock {
            var stmt: OpaquePointer?
            let sql = "SELECT uid FROM message_headers WHERE account_id = ? AND folder_id = ?;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, accountID, -1, Self.transient)
            sqlite3_bind_text(stmt, 2, folderID, -1, Self.transient)

            var uids: [Int] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                uids.append(Int(sqlite3_column_int64(stmt, 0)))
            }
            return uids
        }
    }

    func setDirty(_ isDirty: Bool, messageIDs: [MessageHeader.ID], accountID: String) throws {
        guard !messageIDs.isEmpty else { return }
        try lock.withLock {
            try execSQL("BEGIN IMMEDIATE;")
            do {
                try forEachMessageIDChunk(messageIDs) { chunk in
                    let placeholders = chunk.map { _ in "?" }.joined(separator: ", ")
                    let sql = """
                        UPDATE message_headers
                        SET is_dirty = ?
                        WHERE account_id = ? AND message_id IN (\(placeholders));
                    """
                    var stmt: OpaquePointer?
                    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                        throw SyncStoreError.prepareFailed(errMsg())
                    }
                    defer { sqlite3_finalize(stmt) }

                    sqlite3_bind_int64(stmt, 1, isDirty ? 1 : 0)
                    sqlite3_bind_text(stmt, 2, accountID, -1, Self.transient)
                    for (index, id) in chunk.enumerated() {
                        sqlite3_bind_text(stmt, Int32(index + 3), id, -1, Self.transient)
                    }
                    guard sqlite3_step(stmt) == SQLITE_DONE else {
                        throw SyncStoreError.executeFailed(errMsg())
                    }
                }
            } catch {
                try? execSQL("ROLLBACK;")
                throw error
            }
            try execSQL("COMMIT;")
        }
    }

    func dirtyMessageIDs(accountID: String) -> [MessageHeader.ID] {
        lock.withLock {
            var stmt: OpaquePointer?
            let sql = """
                SELECT message_id FROM message_headers
                WHERE account_id = ? AND is_dirty = 1;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, accountID, -1, Self.transient)

            var ids: [MessageHeader.ID] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(stmt, 0) {
                    ids.append(String(cString: ptr))
                }
            }
            return ids
        }
    }

    // MARK: SyncStoreProtocol — message bodies

    func body(accountID: String, messageID: MessageHeader.ID) -> Data? {
        lock.withLock {
            var stmt: OpaquePointer?
            let sql = """
                SELECT raw_source FROM message_bodies
                WHERE account_id = ? AND message_id = ?
                LIMIT 1;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, accountID, -1, Self.transient)
            sqlite3_bind_text(stmt, 2, messageID, -1, Self.transient)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            guard let bytes = sqlite3_column_blob(stmt, 0) else { return nil }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))
        }
    }

    func storeBody(_ data: Data, accountID: String, messageID: MessageHeader.ID) throws {
        try lock.withLock {
            var stmt: OpaquePointer?
            let sql = """
                INSERT INTO message_bodies (account_id, message_id, raw_source, fetched_at, size_bytes)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(account_id, message_id) DO UPDATE SET
                    raw_source = excluded.raw_source,
                    fetched_at = excluded.fetched_at,
                    size_bytes = excluded.size_bytes;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SyncStoreError.prepareFailed(errMsg())
            }
            defer { sqlite3_finalize(stmt) }

            try execSQL("BEGIN IMMEDIATE;")
            do {
                sqlite3_bind_text(stmt, 1, accountID, -1, Self.transient)
                sqlite3_bind_text(stmt, 2, messageID, -1, Self.transient)
                _ = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(stmt, 3, bytes.baseAddress, Int32(data.count), Self.transient)
                }
                sqlite3_bind_int64(stmt, 4, Int64(Date().timeIntervalSince1970))
                sqlite3_bind_int64(stmt, 5, Int64(data.count))
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw SyncStoreError.executeFailed(errMsg())
                }
                if let header = header(accountID: accountID, messageID: messageID) {
                    try upsertSearchRow(
                        header,
                        accountID: accountID,
                        bodyText: Self.searchableBodyText(from: data, messageID: messageID)
                    )
                }
            } catch {
                try? execSQL("ROLLBACK;")
                throw error
            }
            try execSQL("COMMIT;")
        }
    }

    func deleteBodies(messageIDs: [MessageHeader.ID], accountID: String) throws {
        guard !messageIDs.isEmpty else { return }
        try lock.withLock {
            try execSQL("BEGIN IMMEDIATE;")
            do {
                try forEachMessageIDChunk(messageIDs) { chunk in
                    try deleteBodies(messageIDs: chunk, accountID: accountID)
                }
                for messageID in messageIDs {
                    if let header = header(accountID: accountID, messageID: messageID) {
                        try upsertSearchRow(header, accountID: accountID, bodyText: nil)
                    }
                }
            } catch {
                try? execSQL("ROLLBACK;")
                throw error
            }
            try execSQL("COMMIT;")
        }
    }

    func deleteBodies(accountID: String, folderID: String) throws {
        try lock.withLock {
            try execSQL("BEGIN IMMEDIATE;")
            do {
                let headers = headersUnlocked(
                    accountID: accountID,
                    folderID: folderID,
                    limit: Int.max,
                    offset: 0
                )
                try deleteBodiesByMessageIDPrefix(
                    accountID: accountID,
                    folderID: folderID
                )
                for header in headers {
                    try upsertSearchRow(header, accountID: accountID, bodyText: nil)
                }
            } catch {
                try? execSQL("ROLLBACK;")
                throw error
            }
            try execSQL("COMMIT;")
        }
    }

    func deleteBodies(accountID: String, folderID: String, exceptMessageIDs: Set<MessageHeader.ID>) throws {
        try lock.withLock {
            try execSQL("BEGIN IMMEDIATE;")
            do {
                let allHeaders = headersUnlocked(
                    accountID: accountID,
                    folderID: folderID,
                    limit: Int.max,
                    offset: 0
                )
                try deleteBodiesByMessageIDPrefix(
                    accountID: accountID,
                    folderID: folderID,
                    exceptMessageIDs: exceptMessageIDs
                )
                for header in allHeaders where !exceptMessageIDs.contains(header.id) {
                    try upsertSearchRow(header, accountID: accountID, bodyText: nil)
                }
            } catch {
                try? execSQL("ROLLBACK;")
                throw error
            }
            try execSQL("COMMIT;")
        }
    }

    func metrics(accountID: String) -> LocalSearchIndexMetrics? {
        lock.withLock {
            LocalSearchIndexMetrics(
                databaseBytes: Self.databaseBytes(at: databaseURL),
                indexedHeaderCount: countRows(
                    "SELECT COUNT(*) FROM message_headers WHERE account_id = ?;",
                    bindings: [.text(accountID)]
                ),
                cachedBodyCount: countRows(
                    "SELECT COUNT(*) FROM message_bodies WHERE account_id = ?;",
                    bindings: [.text(accountID)]
                ),
                searchDocumentCount: countRows(
                    "SELECT COUNT(*) FROM message_search WHERE account_id = ?;",
                    bindings: [.text(accountID)]
                ),
                syncedFolderCount: countRows(
                    "SELECT COUNT(*) FROM folder_sync_state WHERE account_id = ?;",
                    bindings: [.text(accountID)]
                )
            )
        }
    }

    // MARK: SyncStoreProtocol — search

    func searchHeaders(
        _ query: SearchQuery,
        accountID: String,
        limit: Int
    ) -> [MessageHeader] {
        guard query.hasSearchCriteria, limit > 0 else { return [] }
        return lock.withLock {
            let candidates: [(MessageHeader, String?)]
            let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let ftsQueries = Self.ftsQueries(for: text)
            if !ftsQueries.isEmpty {
                let ftsResults = Self.deduplicatedSearchCandidates(ftsQueries.flatMap {
                    ftsCandidates(
                        ftsQuery: $0,
                        accountID: accountID,
                        folderID: query.folderID,
                        limit: Self.unboundedSearchCandidateLimit
                    )
                })
                // FTS is the authoritative text index: if it finds nothing, there are
                // no text matches — the full-scan fallback would also yield nothing
                // after Swift-side text filtering, so skip it.
                guard !ftsResults.isEmpty else { return [] }
                candidates = ftsResults
            } else {
                candidates = headerCandidates(
                    accountID: accountID,
                    folderID: query.folderID,
                    dateRange: query.dateRange,
                    limit: Self.unboundedSearchCandidateLimit
                )
            }

            var seen = Set<MessageHeader.ID>()
            return candidates
                .filter { header, bodyText in
                    guard seen.insert(header.id).inserted else { return false }
                    return Self.searchQuery(query, matches: header, bodyText: bodyText)
                }
                .prefix(limit)
                .map(\.0)
        }
    }

    // MARK: Private helpers

    /// Reads `PRAGMA user_version` and brings the schema up to date:
    /// - 0 (fresh database): create the schema and stamp `currentSchemaVersion`.
    /// - equal to `currentSchemaVersion`: nothing to do.
    /// - older: run forward migrations (none defined yet — see the `switch`).
    /// - newer: refuse to open so we never write with an outdated layout.
    private func migrateIfNeeded() throws {
        let version = userVersion()
        switch version {
        case 0:
            // Fresh database: create everything and record the schema version.
            try createSchema()
            try execSQL("PRAGMA user_version = \(currentSchemaVersion);")
        case currentSchemaVersion:
            // Up to date.
            break
        case 1 ..< currentSchemaVersion:
            // Each migration step and its `user_version` bump run in one
            // transaction (PRAGMA user_version is transactional in SQLite), so a
            // crash mid-backfill can never leave a partially-built search index
            // recorded at the new version — the step re-runs cleanly on reopen.
            if version < 2 {
                try inTransaction {
                    try migrateV1ToV2()
                    try execSQL("PRAGMA user_version = 2;")
                }
            }
            if version < 3 {
                try inTransaction {
                    try migrateV2ToV3()
                    try execSQL("PRAGMA user_version = 3;")
                }
            }
        default:
            // version > currentSchemaVersion: written by a newer build.
            throw SyncStoreError.unknownSchemaVersion(
                found: version, supported: currentSchemaVersion
            )
        }
    }

    private func userVersion() -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func createSchema() throws {
        // Wrap the DDL in a transaction so a crash cannot leave a half-created
        // schema that would then mismatch `user_version`.
        try inTransaction {
            try createSchemaDDL()
        }
    }

    /// Runs `body` inside a single `BEGIN IMMEDIATE` … `COMMIT`, rolling back on
    /// any thrown error so the database is never left in a partial state.
    private func inTransaction(_ body: () throws -> Void) throws {
        try execSQL("BEGIN IMMEDIATE;")
        do {
            try body()
        } catch {
            try? execSQL("ROLLBACK;")
            throw error
        }
        try execSQL("COMMIT;")
    }

    private func createSchemaDDL() throws {
        try execSQL("""
            CREATE TABLE IF NOT EXISTS accounts (
                id         TEXT PRIMARY KEY,
                created_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS folder_sync_state (
                account_id      TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                folder_id       TEXT NOT NULL,
                uid_validity    INTEGER,
                highest_mod_seq INTEGER,
                uid_next        INTEGER,
                last_sync_date  INTEGER,
                sync_tier       INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (account_id, folder_id)
            );

            CREATE TABLE IF NOT EXISTS message_headers (
                account_id  TEXT    NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                folder_id   TEXT    NOT NULL,
                uid         INTEGER NOT NULL,
                message_id  TEXT    NOT NULL,
                date_ts     INTEGER NOT NULL,
                is_dirty    INTEGER NOT NULL DEFAULT 0,
                header_json BLOB    NOT NULL,
                PRIMARY KEY (account_id, folder_id, uid)
            );
            CREATE INDEX IF NOT EXISTS idx_msg_message_id
                ON message_headers (account_id, message_id);
            CREATE INDEX IF NOT EXISTS idx_msg_date
                ON message_headers (account_id, folder_id, date_ts DESC);

            CREATE TABLE IF NOT EXISTS message_bodies (
                account_id  TEXT    NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                message_id  TEXT    NOT NULL,
                raw_source  BLOB    NOT NULL,
                fetched_at  INTEGER NOT NULL,
                size_bytes  INTEGER NOT NULL,
                PRIMARY KEY (account_id, message_id)
            );
        """)
        try createSearchSchema()
    }

    private func createSearchSchema() throws {
        try execSQL("""
            CREATE VIRTUAL TABLE IF NOT EXISTS message_search USING fts5(
                account_id UNINDEXED,
                message_id UNINDEXED,
                folder_id UNINDEXED,
                subject,
                snippet,
                participants,
                body,
                subject_normalized,
                snippet_normalized,
                participants_normalized,
                body_normalized
            );
        """)
    }

    private func migrateV1ToV2() throws {
        try createSearchSchema()
        try rebuildSearchRowsFromStoredMessages()
    }

    private func migrateV2ToV3() throws {
        try execSQL("DROP TABLE IF EXISTS message_search;")
        try createSearchSchema()
        try rebuildSearchRowsFromStoredMessages()
    }

    private func rebuildSearchRowsFromStoredMessages() throws {
        let rows = storedHeaderRows()
        for row in rows {
            try upsertSearchRow(
                row.header,
                accountID: row.accountID,
                bodyText: bodyTextForSearch(accountID: row.accountID, messageID: row.header.id)
            )
        }
    }

    private func storedHeaderRows() -> [(accountID: String, header: MessageHeader)] {
        var stmt: OpaquePointer?
        let sql = "SELECT account_id, header_json FROM message_headers;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [(String, MessageHeader)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let accountPtr = sqlite3_column_text(stmt, 0),
                  let bytes = sqlite3_column_blob(stmt, 1)
            else { continue }
            let accountID = String(cString: accountPtr)
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 1)))
            guard let header = try? Self.decoder.decode(MessageHeader.self, from: data) else {
                continue
            }
            rows.append((accountID, header))
        }
        return rows
    }

    private func header(accountID: String, messageID: MessageHeader.ID) -> MessageHeader? {
        var stmt: OpaquePointer?
        let sql = """
            SELECT header_json FROM message_headers
            WHERE account_id = ? AND message_id = ?
            LIMIT 1;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, accountID, -1, Self.transient)
        sqlite3_bind_text(stmt, 2, messageID, -1, Self.transient)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(stmt, 0)
        else { return nil }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))
        return try? Self.decoder.decode(MessageHeader.self, from: data)
    }

    private func messageID(accountID: String, folderID: String, uid: Int) -> MessageHeader.ID? {
        var stmt: OpaquePointer?
        let sql = """
            SELECT message_id FROM message_headers
            WHERE account_id = ? AND folder_id = ? AND uid = ?
            LIMIT 1;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, accountID, -1, Self.transient)
        sqlite3_bind_text(stmt, 2, folderID, -1, Self.transient)
        sqlite3_bind_int64(stmt, 3, Int64(uid))
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let ptr = sqlite3_column_text(stmt, 0)
        else { return nil }
        return String(cString: ptr)
    }

    private func headersUnlocked(
        accountID: String,
        folderID: String,
        limit: Int,
        offset: Int
    ) -> [MessageHeader] {
        var stmt: OpaquePointer?
        let sql = """
            SELECT header_json FROM message_headers
            WHERE account_id = ? AND folder_id = ?
            ORDER BY date_ts DESC, uid DESC
            LIMIT ? OFFSET ?;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, accountID, -1, Self.transient)
        sqlite3_bind_text(stmt, 2, folderID, -1, Self.transient)
        sqlite3_bind_int64(stmt, 3, Int64(limit))
        sqlite3_bind_int64(stmt, 4, Int64(offset))

        var result: [MessageHeader] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(stmt, 0) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))
            if let header = try? Self.decoder.decode(MessageHeader.self, from: data) {
                result.append(header)
            }
        }
        return result
    }

    private func bodyTextForSearch(accountID: String, messageID: MessageHeader.ID) -> String? {
        var stmt: OpaquePointer?
        let sql = """
            SELECT raw_source FROM message_bodies
            WHERE account_id = ? AND message_id = ?
            LIMIT 1;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, accountID, -1, Self.transient)
        sqlite3_bind_text(stmt, 2, messageID, -1, Self.transient)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(stmt, 0)
        else { return nil }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))
        return Self.searchableBodyText(from: data, messageID: messageID)
    }

    /// Returns the already-indexed body text from `message_search.body`, or
    /// `nil` if no search row exists for this message yet.
    private func existingSearchBodyText(accountID: String, messageID: MessageHeader.ID) -> String? {
        var stmt: OpaquePointer?
        let sql = """
            SELECT body FROM message_search
            WHERE account_id = ? AND message_id = ?
            LIMIT 1;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, accountID, -1, Self.transient)
        sqlite3_bind_text(stmt, 2, messageID, -1, Self.transient)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let ptr = sqlite3_column_text(stmt, 0)
        else { return nil }
        return String(cString: ptr)
    }

    private func upsertSearchRow(
        _ header: MessageHeader,
        accountID: String,
        bodyText: String?
    ) throws {
        try execStmt(
            "DELETE FROM message_search WHERE account_id = ? AND message_id = ?;",
            bindings: [.text(accountID), .text(header.id)]
        )
        var stmt: OpaquePointer?
        let sql = """
            INSERT INTO message_search
                (
                    account_id,
                    message_id,
                    folder_id,
                    subject,
                    snippet,
                    participants,
                    body,
                    subject_normalized,
                    snippet_normalized,
                    participants_normalized,
                    body_normalized
                )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SyncStoreError.prepareFailed(errMsg())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, accountID, -1, Self.transient)
        sqlite3_bind_text(stmt, 2, header.id, -1, Self.transient)
        sqlite3_bind_text(stmt, 3, header.folderID, -1, Self.transient)
        let participants = Self.participantSearchText(for: header)
        let body = bodyText ?? ""
        sqlite3_bind_text(stmt, 4, header.subject, -1, Self.transient)
        sqlite3_bind_text(stmt, 5, header.snippet, -1, Self.transient)
        sqlite3_bind_text(stmt, 6, participants, -1, Self.transient)
        sqlite3_bind_text(stmt, 7, body, -1, Self.transient)
        sqlite3_bind_text(stmt, 8, Self.normalizedSearchText(header.subject), -1, Self.transient)
        sqlite3_bind_text(stmt, 9, Self.normalizedSearchText(header.snippet), -1, Self.transient)
        sqlite3_bind_text(stmt, 10, Self.normalizedSearchText(participants), -1, Self.transient)
        sqlite3_bind_text(stmt, 11, Self.normalizedSearchText(body), -1, Self.transient)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SyncStoreError.executeFailed(errMsg())
        }
    }

    private func deleteSearchRows(messageIDs: ArraySlice<MessageHeader.ID>, accountID: String) throws {
        let placeholders = messageIDs.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            DELETE FROM message_search
            WHERE account_id = ? AND message_id IN (\(placeholders));
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SyncStoreError.prepareFailed(errMsg())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, accountID, -1, Self.transient)
        for (index, id) in messageIDs.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 2), id, -1, Self.transient)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SyncStoreError.executeFailed(errMsg())
        }
    }

    private func deleteBodies(messageIDs: ArraySlice<MessageHeader.ID>, accountID: String) throws {
        let placeholders = messageIDs.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            DELETE FROM message_bodies
            WHERE account_id = ? AND message_id IN (\(placeholders));
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SyncStoreError.prepareFailed(errMsg())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, accountID, -1, Self.transient)
        for (index, id) in messageIDs.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 2), id, -1, Self.transient)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SyncStoreError.executeFailed(errMsg())
        }
    }

    private func deleteBodiesForFolder(accountID: String, folderID: String) throws {
        try execStmt(
            """
            DELETE FROM message_bodies
            WHERE account_id = ?
              AND message_id IN (
                  SELECT message_id FROM message_headers
                  WHERE account_id = ? AND folder_id = ?
              );
            """,
            bindings: [.text(accountID), .text(accountID), .text(folderID)]
        )
    }

    private func deleteBodiesByMessageIDPrefix(accountID: String, folderID: String) throws {
        try execStmt(
            """
            DELETE FROM message_bodies
            WHERE account_id = ?
              AND substr(message_id, 1, length(?) + 1) = ? || ':'
              AND substr(message_id, length(?) + 2) != ''
              AND substr(message_id, length(?) + 2) NOT GLOB '*[^0-9]*';
            """,
            bindings: [
                .text(accountID),
                .text(folderID),
                .text(folderID),
                .text(folderID),
                .text(folderID),
            ]
        )
    }

    private func deleteBodiesByMessageIDPrefix(
        accountID: String,
        folderID: String,
        exceptMessageIDs: Set<MessageHeader.ID>
    ) throws {
        guard !exceptMessageIDs.isEmpty else {
            try deleteBodiesByMessageIDPrefix(accountID: accountID, folderID: folderID)
            return
        }
        let placeholders = exceptMessageIDs.map { _ in "?" }.joined(separator: ", ")
        let sql = """
        DELETE FROM message_bodies
        WHERE account_id = ?
          AND substr(message_id, 1, length(?) + 1) = ? || ':'
          AND substr(message_id, length(?) + 2) != ''
          AND substr(message_id, length(?) + 2) NOT GLOB '*[^0-9]*'
          AND message_id NOT IN (\(placeholders));
        """
        var bindings: [Binding] = [
            .text(accountID),
            .text(folderID),
            .text(folderID),
            .text(folderID),
            .text(folderID),
        ]
        bindings.append(contentsOf: exceptMessageIDs.map { .text($0) })
        try execStmt(sql, bindings: bindings)
    }

    private func ftsCandidates(
        ftsQuery: String,
        accountID: String,
        folderID: String?,
        limit: Int
    ) -> [(MessageHeader, String?)] {
        var stmt: OpaquePointer?
        let folderPredicate = folderID == nil ? "" : "AND message_search.folder_id = ?"
        let sql = """
            SELECT h.header_json, message_search.body
            FROM message_search
            JOIN message_headers h
              ON h.account_id = message_search.account_id
             AND h.message_id = message_search.message_id
            WHERE message_search MATCH ?
              AND message_search.account_id = ?
              \(folderPredicate)
            ORDER BY h.date_ts DESC, h.uid DESC
            LIMIT ?;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, ftsQuery, -1, Self.transient)
        sqlite3_bind_text(stmt, 2, accountID, -1, Self.transient)
        if let folderID {
            sqlite3_bind_text(stmt, 3, folderID, -1, Self.transient)
            sqlite3_bind_int64(stmt, 4, Int64(limit))
        } else {
            sqlite3_bind_int64(stmt, 3, Int64(limit))
        }
        return decodeSearchCandidateRows(stmt)
    }

    private func headerCandidates(
        accountID: String,
        folderID: String?,
        dateRange: ClosedRange<Date>?,
        limit: Int
    ) -> [(MessageHeader, String?)] {
        var stmt: OpaquePointer?
        // Push the column-backed predicates (folder, date range) into SQL to
        // shrink the candidate set; non-column predicates are filtered in Swift.
        var predicates = ["h.account_id = ?"]
        if folderID != nil { predicates.append("h.folder_id = ?") }
        if dateRange != nil { predicates.append("h.date_ts BETWEEN ? AND ?") }
        let sql = """
            SELECT h.header_json, message_search.body
            FROM message_headers h
            LEFT JOIN message_search
              ON message_search.account_id = h.account_id
             AND message_search.message_id = h.message_id
            WHERE \(predicates.joined(separator: "\n              AND "))
            ORDER BY h.date_ts DESC, h.uid DESC
            LIMIT ?;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var index: Int32 = 1
        sqlite3_bind_text(stmt, index, accountID, -1, Self.transient)
        index += 1
        if let folderID {
            sqlite3_bind_text(stmt, index, folderID, -1, Self.transient)
            index += 1
        }
        if let dateRange {
            sqlite3_bind_int64(stmt, index, Int64(dateRange.lowerBound.timeIntervalSince1970))
            index += 1
            sqlite3_bind_int64(stmt, index, Int64(dateRange.upperBound.timeIntervalSince1970))
            index += 1
        }
        sqlite3_bind_int64(stmt, index, Int64(limit))
        return decodeSearchCandidateRows(stmt)
    }

    private func decodeSearchCandidateRows(_ stmt: OpaquePointer?) -> [(MessageHeader, String?)] {
        var rows: [(MessageHeader, String?)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(stmt, 0) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))
            guard let header = try? Self.decoder.decode(MessageHeader.self, from: data) else {
                continue
            }
            let bodyText: String?
            if let text = sqlite3_column_text(stmt, 1) {
                bodyText = String(cString: text)
            } else {
                bodyText = nil
            }
            rows.append((header, bodyText))
        }
        return rows
    }

    private static func searchQuery(
        _ query: SearchQuery,
        matches header: MessageHeader,
        bodyText: String?
    ) -> Bool {
        var metadataQuery = query
        metadataQuery.text = ""
        guard metadataQuery.matches(header) else { return false }

        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        if query.matches(header) { return true }
        let searchableText = normalizedSearchText(searchableText(for: header, bodyText: bodyText))
        let normalizedText = normalizedSearchText(text)
        if searchableText.contains(normalizedText) {
            return true
        }
        let tokens = searchTokens(for: text)
        return !tokens.isEmpty && tokens.allSatisfy {
            searchableText.contains(normalizedSearchText($0))
        }
    }

    private static func ftsQueries(for text: String) -> [String] {
        [ftsQuery(for: text), ftsQuery(for: normalizedSearchText(text))]
            .compactMap(\.self)
            .reduce(into: []) { queries, query in
                guard !queries.contains(query) else { return }
                queries.append(query)
            }
    }

    private static func ftsQuery(for text: String) -> String? {
        let tokens = searchTokens(for: text)
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\($0)*" }.joined(separator: " ")
    }

    private static func searchTokens(for text: String) -> [String] {
        text
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func searchableText(
        for header: MessageHeader,
        bodyText: String?
    ) -> String {
        [
            header.subject,
            header.snippet,
            participantSearchText(for: header),
            bodyText ?? "",
        ].joined(separator: " ")
    }

    private static func normalizedSearchText(_ value: String) -> String {
        // Shared with `SearchQuery`'s cache fallback so the FTS index and the
        // in-memory matcher normalize identically (BrevBackend.SearchTextNormalizer).
        SearchTextNormalizer.normalized(value)
    }

    private static func searchableBodyText(
        from rawData: Data,
        messageID: MessageHeader.ID
    ) -> String {
        let parser = IMAPMessageBodyParser()
        let rawMessage = parser.rawMessageString(from: rawData)
        let parsed = parser.parse(messageID: messageID, rawMessage: rawMessage)
        let searchableParts: [String?] = [
            parsed.plainText,
            parsed.html.map(htmlSearchText),
        ]
            + parsed.attachments.map { Optional($0.name) }
        let parsedText = searchableParts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return parsedText.isEmpty ? rawMessage : parsedText
    }

    private static func deduplicatedSearchCandidates(
        _ candidates: [(MessageHeader, String?)]
    ) -> [(MessageHeader, String?)] {
        var seen = Set<MessageHeader.ID>()
        return candidates
            .filter { header, _ in
                seen.insert(header.id).inserted
            }
            .sorted { first, second in
                if first.0.date != second.0.date {
                    return first.0.date > second.0.date
                }
                return first.0.id > second.0.id
            }
    }

    private static func htmlSearchText(_ html: String) -> String {
        decodeNumericHTMLEntities(in: html)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    private static func decodeNumericHTMLEntities(in html: String) -> String {
        let pattern = #"&#([xX][0-9A-Fa-f]+|[0-9]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        var result = html
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
            guard let range = Range(match.range(at: 1), in: html),
                  let fullRange = Range(match.range, in: html)
            else { continue }
            let rawValue = String(html[range])
            let scalarValue: UInt32?
            if rawValue.lowercased().hasPrefix("x") {
                scalarValue = UInt32(rawValue.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(rawValue, radix: 10)
            }
            guard let scalarValue,
                  let scalar = UnicodeScalar(scalarValue)
            else { continue }
            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return result
    }

    private static func participantSearchText(for header: MessageHeader) -> String {
        ([header.from] + header.to + header.cc + header.bcc)
            .flatMap { correspondent in
                [correspondent.name, correspondent.email]
            }
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private func applyPragmas() throws {
        try execSQL("PRAGMA foreign_keys = ON;")
        try execSQL("PRAGMA journal_mode = WAL;")
    }

    private func execSQL(_ sql: String) throws {
        guard let db else { return }
        var errPtr: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errPtr) == SQLITE_OK else {
            let msg = errPtr.map { String(cString: $0) } ?? errMsg()
            sqlite3_free(errPtr)
            throw SyncStoreError.executeFailed(msg)
        }
    }

    // Binding helper for simple one-shot statements.
    private enum Binding {
        case text(String)
        case int64(Int64)
        case null
    }

    private func execStmt(_ sql: String, bindings: [Binding]) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SyncStoreError.prepareFailed(errMsg())
        }
        defer { sqlite3_finalize(stmt) }
        for (i, binding) in bindings.enumerated() {
            let col = Int32(i + 1)
            switch binding {
            case .text(let s): sqlite3_bind_text(stmt, col, s, -1, Self.transient)
            case .int64(let n): sqlite3_bind_int64(stmt, col, n)
            case .null: sqlite3_bind_null(stmt, col)
            }
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SyncStoreError.executeFailed(errMsg())
        }
    }

    private func countRows(_ sql: String, bindings: [Binding]) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        for (i, binding) in bindings.enumerated() {
            let col = Int32(i + 1)
            switch binding {
            case .text(let s): sqlite3_bind_text(stmt, col, s, -1, Self.transient)
            case .int64(let n): sqlite3_bind_int64(stmt, col, n)
            case .null: sqlite3_bind_null(stmt, col)
            }
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private static func databaseBytes(at url: URL) -> Int64 {
        let urls = [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm")
        ]
        return urls.reduce(into: Int64(0)) { total, fileURL in
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
    }

    private func bindNullableInt(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let v = value {
            sqlite3_bind_int64(stmt, index, Int64(v))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    /// Binds a CONDSTORE mod-sequence as an int64 via its bit pattern, preserving
    /// the full 63-bit unsigned range that `Int64` could not represent directly.
    private func bindNullableModSeq(_ stmt: OpaquePointer?, _ index: Int32, _ value: UInt64?) {
        if let v = value {
            sqlite3_bind_int64(stmt, index, Int64(bitPattern: v))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func errMsg() -> String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "db is nil"
    }

    private static func uid(from messageID: MessageHeader.ID) -> Int {
        guard let sep = messageID.lastIndex(of: ":"),
              let uid = Int(String(messageID[messageID.index(after: sep)...]))
        else { return 0 }
        return uid
    }
}
