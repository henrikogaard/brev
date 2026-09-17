/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the conditions of the LICENSE file.
 */

import BrevBackend
@testable import BrevSyncEngine
import Foundation
import SQLite3
import Testing

/// ADR-0078: the `attachment_search` FTS5 table stores extracted attachment
/// text per message, unions into `searchHeaders`, and cascades out with every
/// message/folder/account purge.
@Suite("Attachment search index")
struct AttachmentSearchIndexTests {
    private static func header(_ id: String, folder: String, subject: String = "Subject") -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: folder,
            from: Correspondent(email: "sender@example.org"),
            to: [],
            subject: subject,
            snippet: "",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            isRead: false,
            isFlagged: false,
            hasAttachments: true
        )
    }

    private static func account(_ id: String = "a") -> BrevAccount {
        BrevAccount(id: id, displayName: "A", emailAddress: "a@example.org")
    }

    private static func databaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-attach-\(UUID().uuidString).sqlite")
    }

    private static func removeDatabase(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    @Test("migration creates attachment_search so indexing works on a v5 database")
    func migrationCreatesTable() async throws {
        let url = Self.databaseURL()
        defer { Self.removeDatabase(at: url) }
        let account = Self.account()
        let header = Self.header("INBOX:1", folder: "INBOX")

        let store = try SQLiteSyncStore(databaseURL: url)
        try store.ensureAccount(id: account.id)
        try store.upsertHeaders([header], accountID: account.id)

        // Simulate a v5 database: drop the FTS table and rewind user_version.
        var database: OpaquePointer?
        #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
        #expect(
            sqlite3_exec(
                database,
                "DROP TABLE attachment_search; PRAGMA user_version = 5;",
                nil, nil, nil
            ) == SQLITE_OK
        )
        sqlite3_close(database)

        let reopened = try SQLiteSyncStore(databaseURL: url)
        try reopened.indexAttachmentText(
            accountID: account.id,
            messageID: header.id,
            folderID: "INBOX",
            attachmentID: "att-1",
            name: "invoice.txt",
            text: "quarterly ledger totals"
        )
        #expect(reopened.indexedAttachmentMessageIDs(accountID: account.id) == [header.id])
        let hits = reopened.searchHeaders(
            SearchQuery(text: "ledger"), accountID: account.id, limit: 10
        )
        #expect(hits.map(\.id) == [header.id])
    }

    @Test("search unions attachment-content hits and reports attachment-only names")
    func searchUnionAndMatchNames() async throws {
        let url = Self.databaseURL()
        defer { Self.removeDatabase(at: url) }
        let account = Self.account()
        let store = try SQLiteSyncStore(databaseURL: url)

        let attachmentHit = Self.header("INBOX:1", folder: "INBOX", subject: "Hello")
        let messageHit = Self.header("INBOX:2", folder: "INBOX", subject: "ledger update")
        try store.ensureAccount(id: account.id)
        try store.upsertHeaders([attachmentHit, messageHit], accountID: account.id)
        try store.indexAttachmentText(
            accountID: account.id,
            messageID: attachmentHit.id,
            folderID: "INBOX",
            attachmentID: "att-1",
            name: "report.pdf",
            text: "the ledger appendix"
        )
        // The same word also lives in attachment content on the message hit —
        // its name must not surface because the message itself matched.
        try store.indexAttachmentText(
            accountID: account.id,
            messageID: messageHit.id,
            folderID: "INBOX",
            attachmentID: "att-2",
            name: "notes.txt",
            text: "ledger scribbles"
        )

        let hits = store.searchHeaders(
            SearchQuery(text: "ledger"), accountID: account.id, limit: 10
        )
        #expect(Set(hits.map(\.id)) == [attachmentHit.id, messageHit.id])

        let names = store.attachmentMatchNames(
            SearchQuery(text: "ledger"),
            accountID: account.id,
            messageIDs: [attachmentHit.id, messageHit.id]
        )
        #expect(names[attachmentHit.id] == "report.pdf")
        #expect(names[messageHit.id] == nil)
    }

    @Test("attachment hits respect the query folder scope")
    func folderScopeRespected() async throws {
        let url = Self.databaseURL()
        defer { Self.removeDatabase(at: url) }
        let account = Self.account()
        let store = try SQLiteSyncStore(databaseURL: url)

        let inbox = Self.header("INBOX:1", folder: "INBOX")
        let archive = Self.header("Archive:1", folder: "Archive")
        try store.ensureAccount(id: account.id)
        try store.upsertHeaders([inbox, archive], accountID: account.id)
        for header in [inbox, archive] {
            try store.indexAttachmentText(
                accountID: account.id,
                messageID: header.id,
                folderID: header.folderID,
                attachmentID: "att-\(header.id)",
                name: "doc.txt",
                text: "needle inside both folders"
            )
        }

        let scoped = store.searchHeaders(
            SearchQuery(text: "needle", folderID: "INBOX"),
            accountID: account.id,
            limit: 10
        )
        #expect(scoped.map(\.id) == [inbox.id])
    }

    @Test("clearFolder removes attachment rows for that folder only")
    func clearFolderCascades() async throws {
        let url = Self.databaseURL()
        defer { Self.removeDatabase(at: url) }
        let account = Self.account()
        let store = try SQLiteSyncStore(databaseURL: url)

        let inbox = Self.header("INBOX:1", folder: "INBOX")
        let archive = Self.header("Archive:1", folder: "Archive")
        try store.ensureAccount(id: account.id)
        try store.upsertHeaders([inbox, archive], accountID: account.id)
        for header in [inbox, archive] {
            try store.indexAttachmentText(
                accountID: account.id,
                messageID: header.id,
                folderID: header.folderID,
                attachmentID: "att-\(header.id)",
                name: "doc.txt",
                text: "kept or purged"
            )
        }

        try store.clearFolder(accountID: account.id, folderID: "INBOX")

        #expect(store.indexedAttachmentMessageIDs(accountID: account.id) == [archive.id])
    }

    @Test("deleting messages removes their attachment rows")
    func deleteMessagesCascades() async throws {
        let url = Self.databaseURL()
        defer { Self.removeDatabase(at: url) }
        let account = Self.account()
        let store = try SQLiteSyncStore(databaseURL: url)

        let keep = Self.header("INBOX:1", folder: "INBOX")
        let drop = Self.header("INBOX:2", folder: "INBOX")
        try store.ensureAccount(id: account.id)
        try store.upsertHeaders([keep, drop], accountID: account.id)
        for header in [keep, drop] {
            try store.indexAttachmentText(
                accountID: account.id,
                messageID: header.id,
                folderID: "INBOX",
                attachmentID: "att-\(header.id)",
                name: "doc.txt",
                text: "message-scoped text"
            )
        }

        try store.deleteHeaders(messageIDs: [drop.id], accountID: account.id)

        #expect(store.indexedAttachmentMessageIDs(accountID: account.id) == [keep.id])
    }

    @Test("clearAccount and removeAllAttachmentText remove every account row")
    func accountCascades() async throws {
        let url = Self.databaseURL()
        defer { Self.removeDatabase(at: url) }
        let account = Self.account()
        let other = Self.account("b")
        let store = try SQLiteSyncStore(databaseURL: url)

        let header = Self.header("INBOX:1", folder: "INBOX")
        try store.ensureAccount(id: account.id)
        try store.ensureAccount(id: other.id)
        try store.upsertHeaders([header], accountID: account.id)
        try store.upsertHeaders([header], accountID: other.id)
        for accountID in [account.id, other.id] {
            try store.indexAttachmentText(
                accountID: accountID,
                messageID: header.id,
                folderID: "INBOX",
                attachmentID: "att-1",
                name: "doc.txt",
                text: "account-scoped text"
            )
        }

        try store.removeAllAttachmentText(accountID: account.id)
        #expect(store.indexedAttachmentMessageIDs(accountID: account.id).isEmpty)
        #expect(store.indexedAttachmentMessageIDs(accountID: other.id) == [header.id])
        #expect(store.attachmentIndexBytes(accountID: account.id) == 0)
        #expect(store.attachmentIndexBytes(accountID: other.id) > 0)

        try store.indexAttachmentText(
            accountID: account.id,
            messageID: header.id,
            folderID: "INBOX",
            attachmentID: "att-1",
            name: "doc.txt",
            text: "account-scoped text"
        )
        try store.clearAccount(id: account.id)
        #expect(store.indexedAttachmentMessageIDs(accountID: account.id).isEmpty)
        #expect(store.indexedAttachmentMessageIDs(accountID: other.id) == [header.id])
    }
}
