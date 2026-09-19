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
@testable import BrevGmail
import Foundation
import SQLite3
import Testing

@Suite("Gmail account store")
struct GmailAccountStoreTests {
    @Test("conversation index migration preserves mail and scheduled drafts")
    func conversationIndexMigratesVersionThree() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gmail-conversations-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("mail.sqlite")
        let draft = Draft(
            id: "unsent",
            to: [Correspondent(email: "recipient@example.org")],
            subject: "Keep draft",
            htmlBody: "Body",
            scheduledFor: .distantFuture
        )
        do {
            let store = try SQLiteGmailAccountStore(databaseURL: url)
            try await store.replaceSnapshot(Self.snapshot(
                labels: [GmailLabel(id: "INBOX", name: "Inbox"), GmailLabel(id: "SENT", name: "Sent")],
                messages: [
                    GmailMessage(id: "a", threadID: "thread", labelIDs: ["INBOX"]),
                    GmailMessage(id: "b", threadID: "thread", labelIDs: ["SENT"]),
                    GmailMessage(id: "c", threadID: "other", labelIDs: ["INBOX"])
                ]
            ))
            try await store.enqueueScheduledSend(
                draft,
                rawMIME: Data("From: test@example.org\r\n\r\nBody".utf8),
                accountID: "acct-1"
            )
        }
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        guard let db else { return }
        #expect(sqlite3_exec(db, "DROP INDEX gmail_conversation_idx; PRAGMA user_version=3;", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let migrated = try SQLiteGmailAccountStore(databaseURL: url)
        #expect(try await migrated.cachedConversationMessages(
            accountID: "acct-1",
            threadID: "thread",
            afterMessageID: nil,
            limit: 1
        ).map(\.id) == ["a"])
        #expect(try await migrated.cachedConversationMessages(
            accountID: "acct-1",
            threadID: "thread",
            afterMessageID: "a",
            limit: 1
        ).map(\.id) == ["b"])
        #expect(try await migrated.cachedConversationMessages(
            accountID: "absent",
            threadID: "thread",
            afterMessageID: nil,
            limit: 100
        ).isEmpty)
        #expect(try await migrated.scheduledDraft(accountID: "acct-1", draftID: "unsent") == draft)
        try await migrated.apply(GmailStoreDelta(
            accountID: "acct-1",
            upsertedMessages: [GmailMessage(id: "b", threadID: "other", labelIDs: ["SENT"])],
            removedMessageIDs: ["a"]
        ))
        #expect(try await migrated.cachedConversationMessages(
            accountID: "acct-1",
            threadID: "thread",
            afterMessageID: nil,
            limit: 100
        ).isEmpty)
        #expect(try await migrated.cachedConversationMessages(
            accountID: "acct-1",
            threadID: "other",
            afterMessageID: nil,
            limit: 100
        ).map(\.id) == ["b", "c"])
    }

    @Test("SQLite search pages use exclusive stable cursors and isolate accounts")
    func sqliteSearchPagesUseStableCursors() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gmail-search-pages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store: any GmailAccountStore = try SQLiteGmailAccountStore(databaseURL: directory
            .appendingPathComponent("mail.sqlite"))
        try await store.replaceSnapshot(Self.snapshot(messages: [
            Self.message(id: "c"),
            Self.message(id: "a"),
            Self.message(id: "b")
        ]))
        #expect(try await store.cachedSearchPage(accountID: "acct-1", afterMessageID: nil, limit: 2).map(\.id) == ["a", "b"])
        #expect(try await store.cachedSearchPage(accountID: "acct-1", afterMessageID: "b", limit: 2).map(\.id) == ["c"])
        #expect(try await store.cachedSearchPage(accountID: "acct-1", afterMessageID: "c", limit: 2).isEmpty)
        #expect(try await store.cachedSearchPage(accountID: "other", afterMessageID: nil, limit: 2).isEmpty)
    }

    @Test("SQLite pages filter labels and order numeric dates before applying the limit")
    func sqliteLabelPagesAreBounded() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-label-page-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store: any GmailAccountStore = try SQLiteGmailAccountStore(databaseURL: url)
        try await store.replaceSnapshot(Self.snapshot(
            labels: [GmailLabel(id: "INBOX", name: "Inbox"), GmailLabel(id: "SENT", name: "Sent")],
            messages: [
                GmailMessage(id: "old", labelIDs: ["INBOX"], internalDate: "9"),
                GmailMessage(id: "new", labelIDs: ["INBOX"], internalDate: "100"),
                GmailMessage(id: "sent", labelIDs: ["SENT"], internalDate: "1000")
            ]
        ))
        #expect(try await store.messages(accountID: "acct-1", labelID: "INBOX", offset: 0, limit: 1).map(\.id) == ["new"])
        #expect(try await store.messages(accountID: "acct-1", labelID: "INBOX", offset: 1, limit: 1).map(\.id) == ["old"])
        #expect(try await store.messages(accountID: "absent", labelID: "INBOX", offset: 0, limit: 1).isEmpty)
    }

    @Test("materialized-date migration backfills and preserves label page order")
    func internalDateMigrationBackfillsAndOrders() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-internal-date-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let store = try SQLiteGmailAccountStore(databaseURL: url)
            try await store.replaceSnapshot(Self.snapshot(
                labels: [GmailLabel(id: "INBOX", name: "Inbox"), GmailLabel(id: "SENT", name: "Sent")],
                messages: [
                    GmailMessage(id: "old", labelIDs: ["INBOX"], internalDate: "9"),
                    GmailMessage(id: "new", labelIDs: ["INBOX"], internalDate: "100"),
                    GmailMessage(id: "undated", labelIDs: ["INBOX"]),
                    GmailMessage(id: "sent", labelIDs: ["SENT"], internalDate: "1000")
                ]
            ))
        }
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        guard let db else { return }
        // Simulate a pre-v5 database: drop the materialized columns and the
        // index, then rewind user_version so reopening re-runs the migration.
        #expect(sqlite3_exec(
            db,
            "DROP INDEX gmail_messages_received_idx; "
                + "ALTER TABLE gmail_messages DROP COLUMN internal_date; "
                + "ALTER TABLE gmail_messages DROP COLUMN content_hash; "
                + "PRAGMA user_version=4;",
            nil, nil, nil
        ) == SQLITE_OK)
        sqlite3_close(db)

        let migrated = try SQLiteGmailAccountStore(databaseURL: url)
        // Descending received order with NULLs last, identical to the former
        // json_extract sort.
        #expect(try await migrated.messages(accountID: "acct-1", labelID: "INBOX", offset: 0, limit: 10)
            .map(\.id) == ["new", "old", "undated"])
        #expect(try await migrated.messages(accountID: "acct-1", labelID: "INBOX", offset: 1, limit: 1)
            .map(\.id) == ["old"])
        // Upserts keep the materialized columns current.
        try await migrated.apply(GmailStoreDelta(
            accountID: "acct-1",
            upsertedMessages: [GmailMessage(id: "newest", labelIDs: ["INBOX"], internalDate: "200")]
        ))
        #expect(try await migrated.messages(accountID: "acct-1", labelID: "INBOX", offset: 0, limit: 1)
            .map(\.id) == ["newest"])
    }

    @Test("message summaries expose change markers and label order without decoding")
    func sqliteMessageSummariesTrackChanges() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-summaries-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteGmailAccountStore(databaseURL: url)
        try await store.replaceSnapshot(Self.snapshot(messages: [
            Self.message(id: "a", labels: ["INBOX", "STARRED"]),
            Self.message(id: "b", labels: [])
        ]))

        let first = try await store.messageSummaries(accountID: "acct-1")
        let byID = Dictionary(uniqueKeysWithValues: first.map { ($0.id, $0) })
        #expect(byID["a"]?.labelIDs == ["INBOX", "STARRED"])
        #expect(byID["b"]?.labelIDs == [])
        #expect(byID["a"]?.contentHash != byID["b"]?.contentHash)

        // An identical re-upsert keeps the hash; a label change flips it.
        let original = try #require(byID["a"])
        try await store.apply(GmailStoreDelta(
            accountID: "acct-1",
            upsertedMessages: [Self.message(id: "a", labels: ["INBOX", "STARRED"])]
        ))
        var summaries = try await Dictionary(uniqueKeysWithValues: store
            .messageSummaries(accountID: "acct-1").map { ($0.id, $0) })
        #expect(summaries["a"]?.contentHash == original.contentHash)
        try await store.apply(GmailStoreDelta(
            accountID: "acct-1",
            upsertedMessages: [Self.message(id: "a", labels: ["INBOX"])]
        ))
        summaries = try await Dictionary(uniqueKeysWithValues: store
            .messageSummaries(accountID: "acct-1").map { ($0.id, $0) })
        #expect(summaries["a"]?.contentHash != original.contentHash)
        #expect(summaries["a"]?.labelIDs == ["INBOX"])
        #expect(try await store.messageSummaries(accountID: "other").isEmpty)
    }

    @Test("stores one message once while retaining two label joins")
    func storesManyToManyMessageLabels() async throws {
        let store = InMemoryGmailAccountStore()
        let message = Self.message(id: "message-1", labels: ["INBOX", "STARRED"])
        try await store.replaceSnapshot(Self.snapshot(messages: [message]))

        #expect(try await store.messages(accountID: "acct-1").count == 1)
        #expect(try await store.messageLabelIDs(accountID: "acct-1", messageID: "message-1") == ["INBOX", "STARRED"])
    }

    @Test("renaming a label preserves message joins")
    func renamingLabelPreservesJoins() async throws {
        let store = InMemoryGmailAccountStore()
        let message = Self.message(id: "message-1", labels: ["label-1"])
        try await store.replaceSnapshot(Self.snapshot(
            labels: [GmailLabel(id: "label-1", name: "Projects")],
            messages: [message]
        ))
        try await store.apply(GmailStoreDelta(
            accountID: "acct-1",
            upsertedLabels: [GmailLabel(id: "label-1", name: "Work")],
            historyID: "11"
        ))

        #expect(try await store.labels(accountID: "acct-1").first?.name == "Work")
        #expect(try await store.messageLabelIDs(accountID: "acct-1", messageID: "message-1") == ["label-1"])
    }

    @Test("metadata refresh preserves a richer cached payload and label deletion scrubs joins")
    func metadataRefreshPreservesPayloadAndDeletedLabel() async throws {
        let store = InMemoryGmailAccountStore()
        let rich = GmailMessage(
            id: "message-1",
            threadID: "thread-1",
            labelIDs: ["label-1"],
            payload: GmailMessagePart(mimeType: "text/plain"),
            raw: "raw"
        )
        try await store.replaceSnapshot(Self.snapshot(
            labels: [GmailLabel(id: "label-1", name: "Projects")],
            messages: [rich]
        ))
        try await store.apply(GmailStoreDelta(
            accountID: "acct-1",
            removedLabelIDs: ["label-1"],
            upsertedMessages: [GmailMessage(id: "message-1", labelIDs: [])]
        ))

        let message = try #require(try await store.message(accountID: "acct-1", messageID: "message-1"))
        #expect(message.payload == rich.payload)
        #expect(message.raw == "raw")
        #expect(try await store.messageLabelIDs(accountID: "acct-1", messageID: "message-1").isEmpty)
    }

    @Test("full snapshot replacement removes orphaned content cache")
    func snapshotReplacementPrunesOrphanedCache() async throws {
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(Self.snapshot(messages: [Self.message(id: "old")]))
        try await store.storeBody(MessageBody(messageID: "old", plainText: "old"), accountID: "acct-1")
        try await store.storeRawSource("old", accountID: "acct-1", messageID: "old")
        try await store.storeAttachment(Data("old".utf8), accountID: "acct-1", attachmentID: "gmail-attachment:old:part")
        try await store.replaceSnapshot(Self.snapshot(messages: [Self.message(id: "new")]))

        #expect(try await store.cachedBody(accountID: "acct-1", messageID: "old") == nil)
        #expect(try await store.cachedRawSource(accountID: "acct-1", messageID: "old") == nil)
        #expect(try await store.cachedAttachment(accountID: "acct-1", attachmentID: "gmail-attachment:old:part") == nil)
    }

    @Test("a failed delta rolls back writes and leaves the history cursor unchanged")
    func failedDeltaRollsBack() async throws {
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(Self.snapshot(
            state: GmailAccountState(accountID: "acct-1", emailAddress: "user@example.com", historyID: "10"),
            messages: [Self.message(id: "existing")]
        ))

        do {
            try await store.apply(GmailStoreDelta(
                accountID: "acct-1",
                upsertedMessages: [Self.message(id: "new"), Self.message(id: "")],
                historyID: "11"
            ))
            Issue.record("Expected invalid message ID")
        } catch let error as GmailAccountStoreError {
            #expect(error == .invalidMessageID)
        }

        #expect(try await store.accountState(accountID: "acct-1")?.historyID == "10")
        #expect(try await store.messages(accountID: "acct-1").map(\.id) == ["existing"])
    }

    @Test("SQLite state and joins survive a store restart")
    func sqliteRestartPersistsState() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-gmail-store-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let store = try SQLiteGmailAccountStore(databaseURL: url)
            try await store.replaceSnapshot(Self.snapshot(
                labels: [GmailLabel(id: "label-1", name: "Projects")],
                messages: [Self.message(id: "message-1", labels: ["label-1"])]
            ))
        }

        let reopened = try SQLiteGmailAccountStore(databaseURL: url)
        #expect(try await reopened.accountState(accountID: "acct-1")?.historyID == "10")
        #expect(try await reopened.messages(accountID: "acct-1").map(\.id) == ["message-1"])
        #expect(try await reopened.messageLabelIDs(accountID: "acct-1", messageID: "message-1") == ["label-1"])
    }

    @Test("SQLite keeps accounts isolated even when Gmail IDs are equal")
    func sqliteAccountIsolation() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-gmail-store-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteGmailAccountStore(databaseURL: url)

        try await store.replaceSnapshot(Self.snapshot(accountID: "acct-1", messages: [Self.message(id: "same")]))
        try await store.replaceSnapshot(Self.snapshot(accountID: "acct-2", messages: [Self.message(id: "same")]))

        #expect(try await store.messages(accountID: "acct-1").map(\.id) == ["same"])
        #expect(try await store.messages(accountID: "acct-2").map(\.id) == ["same"])
        #expect(try await store.accountState(accountID: "acct-3") == nil)
    }

    @Test("SQLite rollback keeps the cursor and prior messages")
    func sqliteDeltaRollback() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-gmail-store-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteGmailAccountStore(databaseURL: url)
        try await store.replaceSnapshot(Self.snapshot(messages: [Self.message(id: "existing")]))

        do {
            try await store.apply(GmailStoreDelta(
                accountID: "acct-1",
                upsertedMessages: [Self.message(id: "new"), Self.message(id: "")],
                historyID: "11"
            ))
            Issue.record("Expected invalid message ID")
        } catch let error as GmailAccountStoreError {
            #expect(error == .invalidMessageID)
        }

        #expect(try await store.accountState(accountID: "acct-1")?.historyID == "10")
        #expect(try await store.messages(accountID: "acct-1").map(\.id) == ["existing"])
    }

    @Test("an empty SQLite file migrates to the current schema")
    func emptySchemaMigration() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-gmail-store-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        FileManager.default.createFile(atPath: url.path, contents: Data())

        let store = try SQLiteGmailAccountStore(databaseURL: url)
        #expect(try await store.accountState(accountID: "acct-1") == nil)
    }

    @Test("SQLite content cache survives a store restart")
    func sqliteContentCacheSurvivesRestart() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-gmail-content-cache-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let body = MessageBody(messageID: "message-1", plainText: "Cached body")

        do {
            let store = try SQLiteGmailAccountStore(databaseURL: url)
            try await store.replaceSnapshot(Self.snapshot(messages: [Self.message(id: "message-1")]))
            try await store.storeBody(body, accountID: "acct-1")
            try await store.storeRawSource("Subject: Cached", accountID: "acct-1", messageID: "message-1")
            try await store.storeAttachment(Data("bytes".utf8), accountID: "acct-1", attachmentID: "attachment-1")
        }

        let reopened = try SQLiteGmailAccountStore(databaseURL: url)
        #expect(try await reopened.cachedBody(accountID: "acct-1", messageID: "message-1") == body)
        #expect(try await reopened.cachedRawSource(accountID: "acct-1", messageID: "message-1") == "Subject: Cached")
        #expect(try await reopened.cachedAttachment(accountID: "acct-1", attachmentID: "attachment-1") == Data("bytes".utf8))
    }

    @Test("SQLite removes canonical records and account-scoped cache")
    func sqliteRemovesAccountState() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-gmail-remove-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteGmailAccountStore(databaseURL: url)
        try await store.replaceSnapshot(Self.snapshot(messages: [Self.message(id: "message-1")]))
        try await store.storeRawSource("Subject: cached", accountID: "acct-1", messageID: "message-1")

        try await store.removeAccount(accountID: "acct-1")

        #expect(try await store.accountState(accountID: "acct-1") == nil)
        #expect(try await store.messages(accountID: "acct-1").isEmpty)
        #expect(try await store.cachedRawSource(accountID: "acct-1", messageID: "message-1") == nil)
    }

    @Test("SQLite metadata refresh preserves content and scrubs deleted labels")
    func sqliteMetadataRefreshPreservesContentAndScrubsLabels() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-gmail-label-scrub-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteGmailAccountStore(databaseURL: url)
        let message = GmailMessage(
            id: "message-1",
            threadID: "thread-1",
            labelIDs: ["label-1"],
            payload: GmailMessagePart(mimeType: "text/plain"),
            raw: "raw"
        )
        try await store.replaceSnapshot(Self.snapshot(
            labels: [GmailLabel(id: "label-1", name: "Projects")],
            messages: [message]
        ))
        try await store.apply(GmailStoreDelta(
            accountID: "acct-1",
            removedLabelIDs: ["label-1"],
            upsertedMessages: [GmailMessage(id: "message-1", labelIDs: [])]
        ))

        let stored = try #require(try await store.message(accountID: "acct-1", messageID: "message-1"))
        #expect(stored.payload == message.payload)
        #expect(stored.raw == "raw")
        #expect(try await store.messageLabelIDs(accountID: "acct-1", messageID: "message-1").isEmpty)
    }

    private static func snapshot(
        accountID: String = "acct-1",
        state: GmailAccountState? = nil,
        labels: [GmailLabel] = [
            GmailLabel(id: "INBOX", name: "Inbox"),
            GmailLabel(id: "STARRED", name: "Starred")
        ],
        messages: [GmailMessage] = []
    ) -> GmailAccountSnapshot {
        GmailAccountSnapshot(
            accountID: accountID,
            state: state ?? GmailAccountState(
                accountID: accountID,
                emailAddress: "user@example.com",
                historyID: "10"
            ),
            labels: labels,
            messages: messages
        )
    }

    private static func message(id: String, labels: [String] = []) -> GmailMessage {
        GmailMessage(id: id, threadID: "thread-\(id)", labelIDs: labels)
    }
}
