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
import SQLite3

protocol AvatarCacheStoring: Sendable {
    func cachedAvatar(
        for email: String,
        preferences: AvatarPreferences,
        now: Date
    ) async -> ResolvedAvatar?

    func store(
        _ avatar: ResolvedAvatar,
        preferences: AvatarPreferences,
        expiresAt: Date,
        now: Date
    ) async

    func clear() async
}

struct NoAvatarCache: AvatarCacheStoring {
    func cachedAvatar(
        for email: String,
        preferences: AvatarPreferences,
        now: Date
    ) async -> ResolvedAvatar? {
        nil
    }

    func store(
        _ avatar: ResolvedAvatar,
        preferences: AvatarPreferences,
        expiresAt: Date,
        now: Date
    ) async {}

    func clear() async {}
}

final class SQLiteAvatarCache: AvatarCacheStoring, @unchecked Sendable {
    enum CacheError: Error {
        case openFailed(String)
        case prepareFailed(String)
        case executeFailed(String)
    }

    private let lock = NSLock()
    private let database: OpaquePointer?
    private var lastExpiredRowPruneAt = Date.distantPast

    init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(database)
            throw CacheError.openFailed(message)
        }

        self.database = database
        try execute(Self.createTableSQL)
        try migrateLegacySchemaIfNeeded()
    }

    deinit {
        sqlite3_close(database)
    }

    static func defaultDatabaseURL() -> URL {
        let cachesDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return cachesDirectory
            .appendingPathComponent("Brev", isDirectory: true)
            .appendingPathComponent("avatars.sqlite")
    }

    func cachedAvatar(
        for email: String,
        preferences: AvatarPreferences,
        now: Date = Date()
    ) async -> ResolvedAvatar? {
        lock.withLock {
            guard let database else { return nil }
            pruneExpiredRowsIfNeeded(now: now)
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, Self.selectSQL, -1, &statement, nil) == SQLITE_OK else {
                return nil
            }
            defer { sqlite3_finalize(statement) }

            bind(email, to: statement, at: 1)
            bind(Self.preferenceKey(for: preferences), to: statement, at: 2)

            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            guard let sourceTextPointer = sqlite3_column_text(statement, 0),
                  let source = AvatarSource(rawValue: String(cString: sourceTextPointer)) else {
                delete(email: email, preferences: preferences)
                return nil
            }

            let expiresAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 2)))
            guard expiresAt > now else {
                delete(email: email, preferences: preferences)
                return nil
            }

            let imageData: Data?
            if sqlite3_column_type(statement, 1) == SQLITE_NULL {
                imageData = nil
            } else if let bytes = sqlite3_column_blob(statement, 1) {
                imageData = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
            } else {
                imageData = nil
            }

            return ResolvedAvatar(email: email, source: source, imageData: imageData)
        }
    }

    func store(
        _ avatar: ResolvedAvatar,
        preferences: AvatarPreferences,
        expiresAt: Date,
        now: Date = Date()
    ) async {
        lock.withLock {
            guard let database else { return }
            pruneExpiredRowsIfNeeded(now: now)
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, Self.upsertSQL, -1, &statement, nil) == SQLITE_OK else {
                return
            }
            defer { sqlite3_finalize(statement) }

            bind(avatar.email, to: statement, at: 1)
            bind(Self.preferenceKey(for: preferences), to: statement, at: 2)
            bind(avatar.source.rawValue, to: statement, at: 3)
            bind(avatar.imageData, to: statement, at: 4)
            sqlite3_bind_int64(statement, 5, Int64(now.timeIntervalSince1970.rounded(.down)))
            sqlite3_bind_int64(statement, 6, Int64(expiresAt.timeIntervalSince1970.rounded(.down)))
            _ = sqlite3_step(statement)
        }
    }

    func clear() async {
        lock.withLock {
            try? execute(Self.clearSQL)
        }
    }

    private func execute(_ sql: String) throws {
        guard let database else { return }
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(error)
            throw CacheError.executeFailed(message)
        }
    }

    /// Older cache databases carried an `etag` column that was never read or
    /// populated by the resolver. Rebuild that table without the dead column
    /// instead of relying on `DROP COLUMN`, which is unavailable on older
    /// SQLite versions. The copy keeps all useful cached avatar bytes.
    private func migrateLegacySchemaIfNeeded() throws {
        guard try tableColumns().contains("etag") else { return }
        try execute("BEGIN IMMEDIATE;")
        do {
            try execute("ALTER TABLE sender_avatar RENAME TO sender_avatar_legacy;")
            try execute(Self.createTableSQL)
            try execute(Self.copyLegacyRowsSQL)
            try execute("DROP TABLE sender_avatar_legacy;")
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func tableColumns() throws -> Set<String> {
        guard let database else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(sender_avatar);", -1, &statement, nil) == SQLITE_OK else {
            throw CacheError.prepareFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = sqlite3_column_text(statement, 1) else { continue }
            columns.insert(String(cString: name))
        }
        return columns
    }

    private func delete(email: String, preferences: AvatarPreferences) {
        guard let database else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, Self.deleteSQL, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }

        bind(email, to: statement, at: 1)
        bind(Self.preferenceKey(for: preferences), to: statement, at: 2)
        _ = sqlite3_step(statement)
    }

    /// Keep old senders from accumulating forever when they are not resolved
    /// again. Pruning is throttled because avatar rows are read once per
    /// visible sender during list rendering.
    private func pruneExpiredRowsIfNeeded(now: Date) {
        guard now.timeIntervalSince(lastExpiredRowPruneAt) >= 300,
              let database else {
            return
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, Self.deleteExpiredSQL, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(now.timeIntervalSince1970.rounded(.down)))
        _ = sqlite3_step(statement)
        lastExpiredRowPruneAt = now
    }

    private func bind(_ value: String, to statement: OpaquePointer?, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func bind(_ data: Data?, to statement: OpaquePointer?, at index: Int32) {
        guard let data else {
            sqlite3_bind_null(statement, index)
            return
        }

        _ = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), sqliteTransient)
        }
    }

    private static func preferenceKey(for preferences: AvatarPreferences) -> String {
        [
            preferences.useContacts ? "contacts=1" : "contacts=0",
            preferences.useBIMI ? "bimi=1" : "bimi=0",
            preferences.useGravatar ? "gravatar=1" : "gravatar=0",
            preferences.useFavicon ? "favicon=1" : "favicon=0"
        ].joined(separator: ";")
    }

    private static let createTableSQL = """
    CREATE TABLE IF NOT EXISTS sender_avatar (
        email TEXT NOT NULL,
        preference_key TEXT NOT NULL,
        source TEXT NOT NULL,
        image_data BLOB,
        fetched_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        PRIMARY KEY (email, preference_key)
    );
    """

    private static let copyLegacyRowsSQL = """
    INSERT INTO sender_avatar (email, preference_key, source, image_data, fetched_at, expires_at)
    SELECT email, preference_key, source, image_data, fetched_at, expires_at
    FROM sender_avatar_legacy;
    """

    private static let selectSQL = """
    SELECT source, image_data, expires_at
    FROM sender_avatar
    WHERE email = ? AND preference_key = ?
    LIMIT 1;
    """

    private static let upsertSQL = """
    INSERT INTO sender_avatar (email, preference_key, source, image_data, fetched_at, expires_at)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(email, preference_key) DO UPDATE SET
        source = excluded.source,
        image_data = excluded.image_data,
        fetched_at = excluded.fetched_at,
        expires_at = excluded.expires_at;
    """

    private static let deleteSQL = """
    DELETE FROM sender_avatar
    WHERE email = ? AND preference_key = ?;
    """

    private static let deleteExpiredSQL = """
    DELETE FROM sender_avatar
    WHERE expires_at <= ?;
    """

    private static let clearSQL = "DELETE FROM sender_avatar;"
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
