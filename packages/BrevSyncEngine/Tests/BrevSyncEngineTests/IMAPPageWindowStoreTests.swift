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

@Suite("Transactional IMAP page windows")
struct IMAPPageWindowStoreTests {
    @Test("attachment and cached-body selection uses indexed candidates without folder scans")
    func attachmentSelectionPlan() throws {
        try withDatabase { url in
            let store = try SQLiteSyncStore(databaseURL: url)
            for account in ["a", "other"] {
                try store.ensureAccount(id: account)
                for folder in ["INBOX", "Archive"] {
                    let headers = (1 ... 1000).map { header($0, folder: folder, hasAttachments: $0 == 1 || $0 == 3) }
                    try store.upsertHeaders(headers, accountID: account)
                    for uid in [2, 3, 2000] {
                        try store.storeBody(Data("Synthetic".utf8), accountID: account, messageID: "\(folder):\(uid)")
                    }
                }
            }
            let selected = try store.selectIMAPHeaders(.attachmentsOrCachedBodies, accountID: "a", folderID: "INBOX")
            #expect(selected.map(\.id) == ["INBOX:3", "INBOX:2", "INBOX:1"])
            let plan = try queryPlan(url, SQLiteSyncStore.attachmentOrCachedBodyHeadersSQL)
            #expect(plan.contains { $0.contains("idx_imap_attachment_headers") && $0.contains("<expr>=?") })
            #expect(plan.contains { $0.contains("sqlite_autoindex_message_bodies_1") && $0.contains("account_id=?") })
            #expect(plan.contains { $0.contains("idx_msg_message_id") && $0.contains("message_id=?") })
            #expect(plan.contains { $0.contains("sqlite_autoindex_message_headers_1") && $0.contains("uid=?") })
            #expect(!plan.contains { $0.hasPrefix("SCAN h") || $0.hasPrefix("SCAN message_headers") || $0.hasPrefix("SCAN b") })
            print("IMAP attachment selection EXPLAIN QUERY PLAN: \(plan.joined(separator: "; "))")
        }
    }

    @Test("replacing first window preserves older windows and survives reopen")
    func replacementAndRestart() throws {
        try withDatabase { url in
            do {
                let store = try SQLiteSyncStore(databaseURL: url)
                try store.ensureAccount(id: "a")
                try write([3, 4], to: store)
                try write([1, 2, 3], to: store, key: "before:3")
                try write([4, 5], to: store, next: nil)
            }
            let store = try SQLiteSyncStore(databaseURL: url)
            #expect(try store.imapPageUIDs(accountID: "a", folderID: "INBOX", pageKey: "first") == [4, 5])
            #expect(try store.imapPageUIDs(accountID: "a", folderID: "INBOX", pageKey: "before:3") == [1, 2, 3])
            let persistedState = try store.imapPageState(accountID: "a", folderID: "INBOX")
            let state = try #require(persistedState)
            #expect(state.uidValidity == 777)
            #expect(state.highestModSeq == UInt64.max)
            #expect(state.nextPageToken == nil)
            #expect(store.headers(accountID: "a", folderID: "INBOX", limit: 20, offset: 0).count == 5)
            try write([], to: store)
            #expect(try store.imapPageUIDs(accountID: "a", folderID: "INBOX", pageKey: "first").isEmpty)
            #expect(try store.imapPageUIDs(accountID: "a", folderID: "INBOX", pageKey: "before:3") == [1, 2, 3])
        }
    }

    @Test("window failure rolls back headers, search rows and metadata")
    func rollback() throws {
        try withDatabase { url in
            let store = try SQLiteSyncStore(databaseURL: url)
            try store.ensureAccount(id: "a")
            try write([1], to: store, next: "original")
            try sql(url, """
            CREATE TRIGGER reject_window BEFORE INSERT ON imap_page_windows
            WHEN NEW.uid = 2 BEGIN SELECT RAISE(ABORT, 'injected window failure'); END;
            """)
            #expect(throws: (any Error).self) { try write([2], to: store) }
            #expect(store.headers(accountID: "a", folderID: "INBOX", limit: 20, offset: 0).map(\.id) == ["INBOX:1"])
            #expect(try store.imapPageUIDs(accountID: "a", folderID: "INBOX", pageKey: "first") == [1])
            #expect(try store.imapPageState(accountID: "a", folderID: "INBOX")?.nextPageToken == "original")
            #expect(try count(url, "SELECT COUNT(*) FROM message_search WHERE message_id = 'INBOX:2';") == 0)
        }
    }

    @Test("message, folder and account cleanup preserve other sources")
    func cleanupAndIsolation() throws {
        try withDatabase { url in
            let store = try SQLiteSyncStore(databaseURL: url)
            for account in ["a", "b"] {
                try store.ensureAccount(id: account)
                try write([1, 2], to: store, account: account)
                try write([1], to: store, account: account, folder: "Archive")
            }
            try store.deleteHeaders(messageIDs: ["INBOX:1"], accountID: "a")
            #expect(try store.imapPageUIDs(accountID: "a", folderID: "INBOX", pageKey: "first") == [2])
            try store.clearFolder(accountID: "a", folderID: "INBOX")
            #expect(try store.imapPageState(accountID: "a", folderID: "INBOX") == nil)
            #expect(try store.imapPageUIDs(accountID: "a", folderID: "Archive", pageKey: "first") == [1])
            try store.clearAccount(id: "a")
            #expect(try store.imapPageUIDs(accountID: "a", folderID: "Archive", pageKey: "first").isEmpty)
            #expect(try store.imapPageUIDs(accountID: "b", folderID: "INBOX", pageKey: "first") == [1, 2])
        }
    }

    @Test("v6 upgrade preserves header rows and unknown future schema is not wiped")
    func upgrade() throws {
        try withDatabase { url in
            do {
                let store = try SQLiteSyncStore(databaseURL: url)
                try store.ensureAccount(id: "a")
                try store.upsertHeaders([header(1, folder: "INBOX")], accountID: "a")
            }
            // Reconstruct v6 from the current schema without changing its header data.
            try sql(url, """
            DROP TABLE imap_page_windows;
            ALTER TABLE folder_sync_state DROP COLUMN next_page_token;
            PRAGMA user_version = 6;
            """)
            do {
                let store = try SQLiteSyncStore(databaseURL: url)
                #expect(store.currentSchemaVersion == 7)
                #expect(store.headers(accountID: "a", folderID: "INBOX", limit: 20, offset: 0).map(\.id) == ["INBOX:1"])
                #expect(try store.imapPageState(accountID: "a", folderID: "INBOX") == nil)
                try write([2], to: store)
            }
            try sql(url, "PRAGMA user_version = 99;")
            #expect(throws: SyncStoreError.self) { _ = try SQLiteSyncStore(databaseURL: url) }
            try sql(url, "PRAGMA user_version = 7;")
            let reopened = try SQLiteSyncStore(databaseURL: url)
            #expect(reopened.headers(accountID: "a", folderID: "INBOX", limit: 20, offset: 0).count == 2)
        }
    }

    @Test("invalid folder membership and generation changes fail without touching the old page")
    func validation() throws {
        try withDatabase { url in
            let store = try SQLiteSyncStore(databaseURL: url)
            try store.ensureAccount(id: "a")
            try write([1], to: store)
            #expect(throws: (any Error).self) {
                try store.storeIMAPPage([header(2, folder: "Archive")], accountID: "a", folderID: "INBOX",
                                        pageKey: "first", uidValidity: 777, highestModSeq: nil, nextPageToken: nil)
            }
            #expect(throws: (any Error).self) {
                try store.storeIMAPPage([header(2, folder: "INBOX")], accountID: "a", folderID: "INBOX",
                                        pageKey: "first", uidValidity: 999, highestModSeq: nil, nextPageToken: nil)
            }
            #expect(try store.imapPageUIDs(accountID: "a", folderID: "INBOX", pageKey: "first") == [1])
        }
    }

    @Test("failed v6 migration rolls back the column and schema stamp and can retry")
    func migrationRollback() throws {
        try withDatabase { url in
            do { _ = try SQLiteSyncStore(databaseURL: url) }
            try sql(url, """
            DROP TABLE imap_page_windows;
            ALTER TABLE folder_sync_state DROP COLUMN next_page_token;
            PRAGMA user_version = 6;
            CREATE TABLE imap_page_windows (invalid TEXT);
            """)
            #expect(throws: SyncStoreError.self) { _ = try SQLiteSyncStore(databaseURL: url) }
            #expect(try count(url, "PRAGMA user_version;") == 6)
            let columnQuery = "SELECT COUNT(*) FROM pragma_table_info('folder_sync_state') "
                + "WHERE name = 'next_page_token';"
            let columns = try count(url, columnQuery)
            #expect(columns == 0)
            try sql(url, "DROP TABLE imap_page_windows;")
            let store = try SQLiteSyncStore(databaseURL: url)
            try store.ensureAccount(id: "a")
            try write([1], to: store)
            #expect(try store.imapPageUIDs(accountID: "a", folderID: "INBOX", pageKey: "first") == [1])
        }
    }

    @Test("scheduler updates preserve page metadata and page writes preserve scheduler fields")
    func schedulerStateCoexists() throws {
        try withDatabase { url in
            let store = try SQLiteSyncStore(databaseURL: url)
            try store.ensureAccount(id: "a")
            let sync = FolderSyncState(folderID: "INBOX", accountID: "a", uidValidity: 777,
                                       highestModSeq: UInt64.max, uidNext: 9,
                                       lastSyncDate: Date(timeIntervalSince1970: 123), syncTier: .uidScan)
            try store.setSyncState(sync)
            try write([1], to: store, next: "saved-cursor")
            #expect(store.syncState(accountID: "a", folderID: "INBOX") == sync)
            try store.setSyncState(sync)
            #expect(try store.imapPageState(accountID: "a", folderID: "INBOX")?.nextPageToken == "saved-cursor")
            try store.upsertHeaders([header(1, folder: "INBOX")], accountID: "a")
            #expect(try store.imapPageUIDs(accountID: "a", folderID: "INBOX", pageKey: "first") == [1])
        }
    }

    private func write(_ uids: [Int], to store: SQLiteSyncStore, account: String = "a", folder: String = "INBOX",
                       key: String = "first", next: String? = "before:1") throws {
        try store.storeIMAPPage(uids.map { header($0, folder: folder) }, accountID: account, folderID: folder,
                                pageKey: key, uidValidity: 777, highestModSeq: UInt64.max, nextPageToken: next)
    }

    private func header(_ uid: Int, folder: String, hasAttachments: Bool = false) -> MessageHeader {
        MessageHeader(id: "\(folder):\(uid)", threadID: "thread-\(uid)", folderID: folder,
                      from: Correspondent(email: "sender@example.test"), subject: "Synthetic \(uid)", snippet: "",
                      date: Date(timeIntervalSince1970: TimeInterval(uid)), hasAttachments: hasAttachments)
    }

    private func withDatabase(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brev-imap-windows-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root.appendingPathComponent("headers.sqlite"))
    }

    private func sql(_ url: URL, _ sql: String) throws {
        var db: OpaquePointer?
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    }

    private func count(_ url: URL, _ sql: String) throws -> Int {
        var db: OpaquePointer?
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        try #require(sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_step(stmt) == SQLITE_ROW)
        return Int(sqlite3_column_int64(stmt, 0))
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
