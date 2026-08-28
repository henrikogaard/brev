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

@testable import BrevAvatars
import Foundation
import SQLite3
import Testing

@Suite("AvatarCache schema")
struct AvatarCacheSchemaTests {
    @Test("legacy etag column is migrated away without losing cached rows")
    func migratesLegacyEtagColumn() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevAvatarsSchemaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("avatars.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        var database: OpaquePointer?
        #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        let legacySQL = """
        CREATE TABLE sender_avatar (
            email TEXT NOT NULL,
            preference_key TEXT NOT NULL,
            source TEXT NOT NULL,
            image_data BLOB,
            fetched_at INTEGER NOT NULL,
            expires_at INTEGER NOT NULL,
            etag TEXT,
            PRIMARY KEY (email, preference_key)
        );
        INSERT INTO sender_avatar (email, preference_key, source, image_data, fetched_at, expires_at, etag)
        VALUES ('alex@example.test', 'contacts=0;bimi=0;gravatar=0;favicon=1', 'favicon', X'010203', 100, 4102444800, 'stale');
        """
        #expect(sqlite3_exec(database, legacySQL, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(database)
        database = nil

        let cache = try SQLiteAvatarCache(databaseURL: databaseURL)
        let avatar = await cache.cachedAvatar(
            for: "alex@example.test",
            preferences: AvatarPreferences(useContacts: false, useFavicon: true),
            now: Date(timeIntervalSince1970: 200)
        )
        #expect(avatar?.source == .favicon)
        #expect(avatar?.imageData == Data([1, 2, 3]))

        var migratedDatabase: OpaquePointer?
        #expect(sqlite3_open(databaseURL.path, &migratedDatabase) == SQLITE_OK)
        defer { sqlite3_close(migratedDatabase) }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(migratedDatabase, "PRAGMA table_info(sender_avatar);", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        var columns: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) {
                columns.append(String(cString: name))
            }
        }
        #expect(!columns.contains("etag"))
    }
}
