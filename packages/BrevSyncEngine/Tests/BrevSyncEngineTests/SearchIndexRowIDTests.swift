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
@testable import BrevSyncEngine
import Foundation
import SQLite3
import Testing

@Suite("SQLite search rowid index and v11 migration")
struct SearchIndexRowIDTests {
    @Test("bulk upsert, flag flip, header update, body upsert, and deletes keep FTS and index in sync")
    func fullLifecycleSearchParity() throws {
        try withDatabase { url in
            let store = try SQLiteSyncStore(databaseURL: url)
            try store.ensureAccount(id: "acc-a")
            try store.ensureAccount(id: "acc-b")

            let inboxHeaders = (1 ... 100).map { uid in
                header(uid, folder: "INBOX", subject: "Bulk invoice \(uid)")
            }
            let archiveHeaders = [
                header(1, folder: "Archive", subject: "Archived invoice"),
            ]
            try store.upsertHeaders(inboxHeaders + archiveHeaders, accountID: "acc-a")
            try store.upsertHeaders(
                [header(1, folder: "INBOX", subject: "Other account invoice")],
                accountID: "acc-b"
            )

            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search;") == 102)
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search_index;") == 102)
            #expect(store.metrics(accountID: "acc-a")?.searchDocumentCount == 101)
            #expect(store.metrics(accountID: "acc-b")?.searchDocumentCount == 1)
            #expect(store.searchHeaders(SearchQuery(text: "invoice 42"), accountID: "acc-a", limit: 10).map(\.id) == ["INBOX:42"])

            // Body upsert replaces the FTS row without duplicating rows and advances fts_rowid.
            let rowIDBeforeBody = try scalar(
                url,
                "SELECT fts_rowid FROM message_search_index WHERE account_id = 'acc-a' AND message_id = 'INBOX:42';"
            )
            try store.storeBody(
                Data("Content-Type: text/plain; charset=utf-8\r\n\r\nQuarterly cobalt ledger".utf8),
                accountID: "acc-a",
                messageID: "INBOX:42"
            )
            let rowIDAfterBody = try scalar(
                url,
                "SELECT fts_rowid FROM message_search_index WHERE account_id = 'acc-a' AND message_id = 'INBOX:42';"
            )
            #expect(rowIDAfterBody != rowIDBeforeBody)
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search;") == 102)
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search_index;") == 102)
            #expect(store.searchHeaders(SearchQuery(text: "cobalt"), accountID: "acc-a", limit: 10).map(\.id) == ["INBOX:42"])

            // Flag-only update preserves the exact FTS rowid and search results.
            var flagged = header(42, folder: "INBOX", subject: "Bulk invoice 42")
            flagged.isRead = true
            flagged.isFlagged = true
            try store.upsertHeaders([flagged], accountID: "acc-a")
            let rowIDAfterFlag = try scalar(
                url,
                "SELECT fts_rowid FROM message_search_index WHERE account_id = 'acc-a' AND message_id = 'INBOX:42';"
            )
            #expect(rowIDAfterFlag == rowIDAfterBody)
            #expect(store.searchHeaders(SearchQuery(text: "cobalt"), accountID: "acc-a", limit: 10).map(\.id) == ["INBOX:42"])

            // Subject update rewrites the FTS row, keeps fts_rowid aligned with message_search.rowid,
            // and preserves the indexed body text.
            var renamed = header(42, folder: "INBOX", subject: "Renamed zephyr statement")
            renamed.isRead = flagged.isRead
            renamed.isFlagged = flagged.isFlagged
            try store.upsertHeaders([renamed], accountID: "acc-a")
            let indexedRowIDAfterRename = try scalar(
                url,
                "SELECT fts_rowid FROM message_search_index WHERE account_id = 'acc-a' AND message_id = 'INBOX:42';"
            )
            let actualFTSRowIDAfterRename = try scalar(
                url,
                "SELECT rowid FROM message_search WHERE account_id = 'acc-a' AND message_id = 'INBOX:42';"
            )
            #expect(indexedRowIDAfterRename == actualFTSRowIDAfterRename)
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search;") == 102)
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search_index;") == 102)
            #expect(store.searchHeaders(SearchQuery(text: "zephyr"), accountID: "acc-a", limit: 10).map(\.id) == ["INBOX:42"])
            #expect(store.searchHeaders(SearchQuery(text: "cobalt"), accountID: "acc-a", limit: 10).map(\.id) == ["INBOX:42"])
            #expect(store.searchHeaders(SearchQuery(text: "Bulk invoice 42"), accountID: "acc-a", limit: 10).isEmpty)

            // Structured indexBodyText updates a header without a raw body and preserves 1:1 count.
            try store.indexBodyText("Structured tangerine note", accountID: "acc-a", messageID: "INBOX:7")
            #expect(store.searchHeaders(SearchQuery(text: "tangerine"), accountID: "acc-a", limit: 10).map(\.id) == ["INBOX:7"])
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search;") == 102)
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search_index;") == 102)

            // Deleting a single header removes both FTS and index rows.
            try store.deleteHeaders(messageIDs: ["INBOX:42"], accountID: "acc-a")
            #expect(store.searchHeaders(SearchQuery(text: "zephyr"), accountID: "acc-a", limit: 10).isEmpty)
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search;") == 101)
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search_index;") == 101)

            // Clearing one folder removes only that folder's FTS and index rows.
            try store.clearHeaders(accountID: "acc-a", folderID: "INBOX")
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search;") == 2)
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search_index;") == 2)
            #expect(store.searchHeaders(SearchQuery(text: "Archived"), accountID: "acc-a", limit: 10).map(\.id) == ["Archive:1"])
            #expect(store.searchHeaders(SearchQuery(text: "Other account"), accountID: "acc-b", limit: 10)
                .map(\.id) == ["INBOX:1"])

            // Clearing account cache removes only that account's rows.
            try store.clearIMAPCache(accountID: "acc-a")
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search;") == 1)
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search_index;") == 1)
            #expect(store.searchHeaders(SearchQuery(text: "Other account"), accountID: "acc-b", limit: 10)
                .map(\.id) == ["INBOX:1"])

            try store.clearAccount(id: "acc-b")
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search;") == 0)
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search_index;") == 0)
        }
    }

    @Test("v10 to v11 migration backfills search index, prunes duplicates, and rolls back on failure")
    func v10MigrationAndRollback() throws {
        try withDatabase { url in
            do {
                let store = try SQLiteSyncStore(databaseURL: url)
                try store.ensureAccount(id: "a")
                try store.upsertHeaders([
                    header(1, folder: "INBOX", subject: "Alpha migration"),
                    header(2, folder: "INBOX", subject: "Beta migration"),
                ], accountID: "a")
                try store.storeBody(
                    Data("Content-Type: text/plain; charset=utf-8\r\n\r\nPersisted saffron payload".utf8),
                    accountID: "a",
                    messageID: "INBOX:1"
                )
            }

            // Simulate a v10 database (no message_search_index) with a stale duplicate FTS row,
            // and inject a blocking view to verify rollback safety.
            try sql(url, """
                DROP TABLE message_search_index;
                INSERT INTO message_search (
                    account_id, message_id, folder_id,
                    subject, snippet, participants, body,
                    subject_normalized, snippet_normalized, participants_normalized, body_normalized
                ) VALUES (
                    'a', 'INBOX:2', 'INBOX',
                    'Beta migration', '', '', 'Latest duplicate body',
                    'beta migration', '', '', 'latest duplicate body'
                );
                PRAGMA user_version = 10;
                CREATE VIEW message_search_index AS SELECT 1;
            """)

            #expect(throws: SyncStoreError.self) { _ = try SQLiteSyncStore(databaseURL: url) }
            #expect(try scalar(url, "PRAGMA user_version;") == 10)
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search;") == 3)

            try sql(url, "DROP VIEW message_search_index;")
            let upgraded = try SQLiteSyncStore(databaseURL: url)
            #expect(upgraded.currentSchemaVersion == 11)
            #expect(try scalar(url, "PRAGMA user_version;") == 11)
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search;") == 2)
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search_index;") == 2)
            #expect(upgraded.searchHeaders(SearchQuery(text: "saffron"), accountID: "a", limit: 10).map(\.id) == ["INBOX:1"])
            #expect(upgraded.searchHeaders(SearchQuery(text: "Beta migration"), accountID: "a", limit: 10)
                .map(\.id) == ["INBOX:2"])

            // Post-migration flag update preserves rowid via message_search_index.
            let initialRowID = try scalar(
                url,
                "SELECT fts_rowid FROM message_search_index WHERE account_id = 'a' AND message_id = 'INBOX:1';"
            )
            var flagOnly = header(1, folder: "INBOX", subject: "Alpha migration")
            flagOnly.isRead = true
            try upgraded.upsertHeaders([flagOnly], accountID: "a")
            let afterFlagRowID = try scalar(
                url,
                "SELECT fts_rowid FROM message_search_index WHERE account_id = 'a' AND message_id = 'INBOX:1';"
            )
            #expect(afterFlagRowID == initialRowID)

            // Post-migration delete removes both FTS and index rows.
            try upgraded.deleteHeaders(messageIDs: ["INBOX:1"], accountID: "a")
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search;") == 1)
            #expect(try scalar(url, "SELECT COUNT(*) FROM message_search_index;") == 1)
            #expect(upgraded.searchHeaders(SearchQuery(text: "saffron"), accountID: "a", limit: 10).isEmpty)
        }
    }

    @Test("search index lookup, FTS rowid operations, and tokenless body join avoid full FTS scans")
    func indexedRowIDQueryPlans() throws {
        try withDatabase { url in
            let store = try SQLiteSyncStore(databaseURL: url)
            try store.ensureAccount(id: "a")
            try store.upsertHeaders([header(1, folder: "INBOX", subject: "Plan check")], accountID: "a")

            let lookupPlan = try queryPlan(
                url,
                "SELECT fts_rowid FROM message_search_index WHERE account_id = ? AND message_id = ? LIMIT 1;"
            )
            #expect(lookupPlan.contains { $0.contains("sqlite_autoindex_message_search_index_1") })
            #expect(!lookupPlan.contains { $0.hasPrefix("SCAN ") })

            let folderPlan = try queryPlan(
                url,
                "SELECT fts_rowid FROM message_search_index WHERE account_id = ? AND folder_id = ?;"
            )
            #expect(folderPlan.contains { $0.contains("idx_message_search_folder") })
            #expect(!folderPlan.contains { $0.hasPrefix("SCAN ") })

            let readBodyPlan = try queryPlan(
                url,
                "SELECT body FROM message_search WHERE rowid = ? LIMIT 1;"
            )
            #expect(readBodyPlan.contains { $0.contains("VIRTUAL TABLE INDEX 0:=") })

            let deletePlan = try queryPlan(
                url,
                "DELETE FROM message_search WHERE rowid = ?;"
            )
            #expect(deletePlan.contains { $0.contains("VIRTUAL TABLE INDEX 0:=") })

            let tokenlessJoinPlan = try queryPlan(
                url,
                """
                SELECT h.header_json, h.date_ts, message_search.body
                FROM message_headers h
                LEFT JOIN message_search_index msi
                  ON msi.account_id = h.account_id
                 AND msi.message_id = h.message_id
                LEFT JOIN message_search
                  ON message_search.rowid = msi.fts_rowid
                WHERE h.account_id = ?
                ORDER BY h.date_ts DESC, h.uid DESC;
                """
            )
            #expect(tokenlessJoinPlan.contains { $0.contains("sqlite_autoindex_message_search_index_1") })
            #expect(tokenlessJoinPlan.contains { $0.contains("VIRTUAL TABLE INDEX 0:=") })

            let dirtyPlan = try queryPlan(
                url,
                "SELECT message_id FROM message_headers WHERE account_id = ? AND is_dirty = 1;"
            )
            #expect(dirtyPlan.contains { $0.contains("idx_msg_dirty") })
            #expect(!dirtyPlan.contains { $0.hasPrefix("SCAN ") })
        }
    }

    private func header(_ uid: Int, folder: String, subject: String) -> MessageHeader {
        MessageHeader(
            id: "\(folder):\(uid)",
            threadID: "thread-\(uid)",
            folderID: folder,
            from: Correspondent(email: "sender@example.test"),
            subject: subject,
            snippet: "",
            date: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + uid * 60))
        )
    }

    private func withDatabase(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brev-search-rowid-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root.appendingPathComponent("search.sqlite"))
    }

    private func sql(_ url: URL, _ sql: String) throws {
        var db: OpaquePointer?
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    }

    private func scalar(_ url: URL, _ sql: String) throws -> Int64 {
        var db: OpaquePointer?
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        try #require(sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_step(stmt) == SQLITE_ROW)
        return sqlite3_column_int64(stmt, 0)
    }

    private func queryPlan(_ url: URL, _ sql: String) throws -> [String] {
        var db: OpaquePointer?
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        try #require(sqlite3_prepare_v2(db, "EXPLAIN QUERY PLAN " + sql, -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        var details: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let text = try #require(sqlite3_column_text(stmt, 3))
            details.append(String(cString: text))
        }
        return details
    }
}
