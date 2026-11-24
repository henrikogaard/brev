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

        // Reconstruct v5, including removal of the later IMAP paging schema.
        var database: OpaquePointer?
        #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
        #expect(
            sqlite3_exec(
                database,
                """
                DROP TABLE attachment_search;
                DROP TABLE imap_page_windows;
                ALTER TABLE folder_sync_state DROP COLUMN next_page_token;
                PRAGMA user_version = 5;
                """,
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

    @Test("indexBodyText makes body-only words searchable without storing raw MIME bytes")
    func indexBodyTextEnablesOfflineSearch() throws {
        let url = Self.databaseURL()
        defer { Self.removeDatabase(at: url) }
        let account = Self.account()
        let store = try SQLiteSyncStore(databaseURL: url)
        let header = Self.header("INBOX:42", folder: "INBOX", subject: "Weekly check-in")
        try store.ensureAccount(id: account.id)
        try store.upsertHeaders([header], accountID: account.id)

        // Before body indexing, the body-only keyword does not match.
        #expect(store.searchHeaders(SearchQuery(text: "platypus-budget"), accountID: account.id, limit: 20).isEmpty)

        // Structured body text indexing persists into FTS without touching message_bodies.
        try store.indexBodyText("Please review the platypus-budget appendix.", accountID: account.id, messageID: header.id)
        let hits = store.searchHeaders(SearchQuery(text: "platypus-budget"), accountID: account.id, limit: 20)
        #expect(hits.map(\.id) == [header.id])
        #expect(store.body(accountID: account.id, messageID: header.id) == nil)
    }

    @Test("indexBodyText preserves raw-MIME search rows including attachment filenames")
    func indexBodyTextPreservesRawMIMESearchRow() throws {
        let url = Self.databaseURL()
        defer { Self.removeDatabase(at: url) }
        let account = Self.account()
        let store = try SQLiteSyncStore(databaseURL: url)
        let header = Self.header("INBOX:43", folder: "INBOX", subject: "Office layout")
        try store.ensureAccount(id: account.id)
        try store.upsertHeaders([header], accountID: account.id)

        let rawMIME = Data("""
        From: sender@example.org\r
        Subject: Office layout\r
        MIME-Version: 1.0\r
        Content-Type: multipart/mixed; boundary="mix-bound"\r
        \r
        --mix-bound\r
        Content-Type: text/plain; charset="utf-8"\r
        \r
        See the attached drawing.\r
        --mix-bound\r
        Content-Type: image/png; name="floorplan.png"\r
        Content-Disposition: attachment; filename="floorplan.png"\r
        Content-Transfer-Encoding: base64\r
        \r
        iVBORw0KGgo=\r
        --mix-bound--\r
        """.utf8)
        try store.storeBody(rawMIME, accountID: account.id, messageID: header.id)

        // Filename-only search succeeds before background indexing.
        let before = store.searchHeaders(SearchQuery(text: "floorplan.png"), accountID: account.id, limit: 20)
        #expect(before.map(\.id) == [header.id])

        // Background structured-body write must not overwrite the richer raw-MIME search row.
        try store.indexBodyText("See the attached drawing.", accountID: account.id, messageID: header.id)

        let after = store.searchHeaders(SearchQuery(text: "floorplan.png"), accountID: account.id, limit: 20)
        #expect(after.map(\.id) == [header.id])
    }

    @Test("indexBodyText populates FTS when an unconfirmed legacy raw body is quarantined without unlocking it")
    func indexBodyTextAllowsStructuredBodyWhenLegacyRawBodyIsQuarantined() throws {
        let url = Self.databaseURL()
        defer { Self.removeDatabase(at: url) }
        let account = Self.account()
        let store = try SQLiteSyncStore(databaseURL: url)
        let header = Self.header("INBOX:7", folder: "INBOX", subject: "Current subject")
        try store.ensureAccount(id: account.id)

        // Seed an old raw body and quarantine it via legacy snapshot import.
        try store.storeOriginalBody(
            Data("quarantined-legacy-secret".utf8),
            accountID: account.id,
            messageID: header.id
        )
        let legacySnapshot = IMAPMailboxHeaderCacheSnapshot(
            headers: [header],
            uidValidity: 1
        )
        try store.storeIMAPSnapshot(legacySnapshot, accountID: account.id, folderID: "INBOX", importingLegacy: true)

        // Confirm the current server header while its legacy raw body remains unconfirmed/quarantined.
        let page = IMAPHeaderPageWrite(
            folderID: "INBOX",
            pageToken: nil,
            headers: [header],
            uidValidity: 1,
            highestModSeq: nil,
            nextPageToken: nil
        )
        try store.storeIMAPPage(page, accountID: account.id)

        #expect(store.body(accountID: account.id, messageID: header.id) == nil)
        #expect(store.searchHeaders(SearchQuery(text: "quarantined-legacy-secret"), accountID: account.id, limit: 20).isEmpty)

        // Fresh structured body text must populate FTS without unlocking the quarantined raw body.
        try store.indexBodyText("fresh-structured-body-token", accountID: account.id, messageID: header.id)

        #expect(store.searchHeaders(SearchQuery(text: "fresh-structured-body-token"), accountID: account.id, limit: 20)
            .map(\.id) == [header.id])
        #expect(store.searchHeaders(SearchQuery(text: "quarantined-legacy-secret"), accountID: account.id, limit: 20).isEmpty)
        #expect(store.body(accountID: account.id, messageID: header.id) == nil)
    }

    @Test("indexedAttachmentIDs tracks per-attachment IDs and matchingAttachmentMessageIDs works without message_headers")
    func perAttachmentIDsAndAttachmentOnlyMatching() throws {
        let url = Self.databaseURL()
        defer { Self.removeDatabase(at: url) }
        let account = Self.account()
        let store = try SQLiteSyncStore(databaseURL: url)
        try store.ensureAccount(id: account.id)

        // Simulate Gmail: rows in attachment_search with no rows in message_headers.
        try store.indexAttachmentText(
            accountID: account.id,
            messageID: "gmail-msg-1",
            folderID: "INBOX",
            attachmentID: "att-1",
            name: "contract.pdf",
            text: "unique-quartz-clause"
        )
        try store.indexAttachmentText(
            accountID: account.id,
            messageID: "gmail-msg-1",
            folderID: "INBOX",
            attachmentID: "att-2",
            name: "addendum.txt",
            text: "second attachment body"
        )

        let perMessage = store.indexedAttachmentIDs(accountID: account.id)
        #expect(perMessage["gmail-msg-1"] == ["att-1", "att-2"])

        let matches = store.matchingAttachmentMessageIDs(
            SearchQuery(text: "unique-quartz-clause"),
            accountID: account.id
        )
        #expect(matches == ["gmail-msg-1"])
    }
}
