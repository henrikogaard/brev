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

@Suite("Indexed IMAP conversations")
struct ConversationIndexTests {
    @Test("cached reply chains cross folders, survive restart and follow deletion")
    func persistedReplyGraph() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-conversation-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let account = BrevAccount(id: "a", displayName: "A", emailAddress: "a@example.org")
        let source = MailSourceID(accountID: "a", mailboxID: "a")
        let root = MessageHeader(id: "Inbox:1", threadID: "<root>", folderID: "Inbox",
                                 from: Correspondent(email: "sender@example.org"), to: [], subject: "Legacy parent", snippet: "",
                                 date: Date(timeIntervalSince1970: 0))
        let reply = Self.header("Sent:2", folder: "Sent", own: "<reply>", parent: "<root>")
        let leaf = Self.header("Archive:3", folder: "Archive", own: "<leaf>", parent: "<reply>")
        let unrelated = Self.header("Inbox:4", folder: "Inbox", own: "<unrelated>")
        let engine = try BrevSyncEngine(databaseURL: url)
        await engine.storeHeaders([root, reply, leaf, unrelated], account: account)
        let original = Data("Original MIME bytes".utf8)
        await engine.storeOriginalRawMessage(original, for: root.id, account: account)
        // Simulate the existing v4 cache: headers/bodies remain, relationship index does not.
        var database: OpaquePointer?
        #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
        #expect(sqlite3_exec(database, "DROP TABLE conversation_links; PRAGMA user_version = 4;", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(database)
        let reopened = try BrevSyncEngine(databaseURL: url)
        #expect(await reopened.cachedOriginalRawMessage(for: root.id, account: account) == original)
        let anchor = ConversationMember(sourceID: source, header: leaf)
        let found = try await reopened.cachedConversation(around: anchor, excludingFolderIDs: [])
        #expect(Set(found.members.map { $0.header.id }) == ["Inbox:1", "Sent:2", "Archive:3"])
        #expect(found.coverage == .cached)
        let excluded = try await reopened.cachedConversation(around: anchor, excludingFolderIDs: ["Sent"])
        #expect(excluded.members.map { $0.header.id } == ["Archive:3"])
        await reopened.deleteMessages(["Sent:2"], account: account)
        let deleted = try await reopened.cachedConversation(around: anchor, excludingFolderIDs: [])
        #expect(deleted.members.map { $0.header.id } == ["Archive:3"])
        let foreign = ConversationMember(sourceID: MailSourceID(accountID: "other", mailboxID: "other"), header: leaf)
        let isolated = try await reopened.cachedConversation(around: foreign, excludingFolderIDs: [])
        #expect(isolated.members.count == 1)
    }

    @Test("a References-only reply chain resolves across folders after a cache restart")
    func referencesOnlyChain() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-references-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let account = BrevAccount(id: "a", displayName: "A", emailAddress: "a@example.org")
        let source = MailSourceID(accountID: "a", mailboxID: "a")
        let root = Self.header("Inbox:1", folder: "Inbox", own: "<root>")
        // Neither reply carries In-Reply-To; only indexed References edges can
        // connect them to the root they cite.
        let middle = Self.header("Archive:2", folder: "Archive", own: "<middle>", references: ["<root>"])
        let leaf = Self.header("Sent:3", folder: "Sent", own: "<leaf>", references: ["<root>"])
        let grandchild = Self.header("Inbox:4", folder: "Inbox", own: "<gc>", parent: "<middle>")
        let engine = try BrevSyncEngine(databaseURL: url)
        await engine.storeHeaders([root, middle, leaf, grandchild], account: account)
        let reopened = try BrevSyncEngine(databaseURL: url)
        let anchor = ConversationMember(sourceID: source, header: leaf)
        let found = try await reopened.cachedConversation(around: anchor, excludingFolderIDs: [])
        #expect(Set(found.members.map { $0.header.id }) == ["Inbox:1", "Archive:2", "Sent:3", "Inbox:4"])
        #expect(found.coverage == .cached)
        #expect(found.anchor == anchor.location)
    }

    @Test("a refresh without References keeps known links; known-absent stays absent", arguments: [false, true])
    func referencesSurvivePartialRefresh(sqlite: Bool) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-references-refresh-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let store: any SyncStoreProtocol = sqlite ? try SQLiteSyncStore(databaseURL: url) : InMemorySyncStore()
        let engine = BrevSyncEngine(store: store)
        let account = BrevAccount(id: "a", displayName: "A", emailAddress: "a@example.org")
        let source = MailSourceID(accountID: "a", mailboxID: "a")
        let root = Self.header("Inbox:1", folder: "Inbox", own: "<root>")
        let reply = Self.header("Sent:2", folder: "Sent", own: "<reply>", references: ["<root>"])
        let absent = Self.header("Inbox:3", folder: "Inbox", own: "<absent>", references: [])
        await engine.storeHeaders([root, reply, absent], account: account)
        // A flag-style refresh rewrites the row from a header that never had
        // References fetched; the stored linkage must survive (unknown ≠ absent).
        var refreshed = reply
        refreshed.isRead = true
        refreshed.references = nil
        await engine.storeHeaders([refreshed], account: account)
        #expect(await store.headers(accountID: "a", folderID: "Sent", limit: 10, offset: 0)
            .first { $0.id == "Sent:2" }?.references == ["<root>"])
        #expect(await store.headers(accountID: "a", folderID: "Inbox", limit: 10, offset: 0)
            .first { $0.id == "Inbox:3" }?.references == [])
        let anchor = ConversationMember(sourceID: source, header: root)
        let found = try await engine.cachedConversation(around: anchor, excludingFolderIDs: [])
        #expect(Set(found.members.map { $0.header.id }) == ["Inbox:1", "Sent:2"])
    }

    @Test("malformed metadata cannot break a valid chain or prevent normal caching", arguments: [false, true])
    func malformedNeighbor(sqlite: Bool) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-invalid-links-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let store: any SyncStoreProtocol = sqlite ? try SQLiteSyncStore(databaseURL: url) : InMemorySyncStore()
        let engine = BrevSyncEngine(store: store)
        let account = BrevAccount(id: "a", displayName: "A", emailAddress: "a@example.org")
        let root = Self.header("Inbox:1", folder: "Inbox", own: "<root>")
        let bad = Self.header("Inbox:2", folder: "Inbox", own: "<broken", parent: "<root>")
        await engine.storeHeaders([root, bad], account: account)
        let anchor = ConversationMember(sourceID: MailSourceID(accountID: "a", mailboxID: "a"), header: root)
        let found = try await engine.cachedConversation(around: anchor, excludingFolderIDs: [])
        #expect(found.members.map { $0.header.id } == ["Inbox:1"])
        #expect(await store.headers(accountID: "a", folderID: "Inbox", limit: 10, offset: 0).count == 2)
    }

    @Test("a changed folder generation cannot reuse the selected UID")
    func rejectsStaleAnchor() async throws {
        let store = InMemorySyncStore()
        let engine = BrevSyncEngine(store: store)
        let root = Self.header("Inbox:1", folder: "Inbox", own: "<root>")
        try await store.upsertHeaders([root], accountID: "a")
        try await store.setSyncState(FolderSyncState(folderID: "Inbox", accountID: "a", uidValidity: 2,
                                                     highestModSeq: nil, uidNext: nil, lastSyncDate: Date(), syncTier: .uidScan))
        let anchor = ConversationMember(sourceID: MailSourceID(accountID: "a", mailboxID: "a"),
                                        header: root, folderGeneration: 1)
        await #expect(throws: ConversationLookupError.self) {
            try await engine.cachedConversation(around: anchor, excludingFolderIDs: [])
        }
    }

    @Test("a large identifier fanout reports partial coverage instead of truncating silently")
    func boundedFanout() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = BrevAccount(id: "a", displayName: "A", emailAddress: "a@example.org")
        var headers: [MessageHeader] = []
        for index in 1 ... 501 {
            headers.append(Self.header("Sent:\(index)", folder: "Sent", own: "<reply-\(index)>", parent: "<root>"))
        }
        await engine.storeHeaders(headers, account: account)
        let anchor = ConversationMember(sourceID: MailSourceID(accountID: "a", mailboxID: "a"),
                                        header: Self.header("Inbox:1", folder: "Inbox", own: "<root>"))
        let found = try await engine.cachedConversation(around: anchor, excludingFolderIDs: [])
        #expect(found.coverage == .partial)
        #expect(found.members.count == 501)
    }

    @Test("a small conversation remains reachable in a larger SQLite cache")
    func largerCacheLookup() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-large-links-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let engine = try BrevSyncEngine(databaseURL: url)
        let account = BrevAccount(id: "a", displayName: "A", emailAddress: "a@example.org")
        var headers: [MessageHeader] = []
        for index in 1 ... 2000 {
            headers.append(Self.header("Inbox:\(index)", folder: "Inbox", own: "<unique-\(index)>"))
        }
        let reply = Self.header("Sent:1", folder: "Sent", own: "<reply>", parent: "<unique-2000>")
        headers.append(reply)
        await engine.storeHeaders(headers, account: account)
        let anchor = ConversationMember(sourceID: MailSourceID(accountID: "a", mailboxID: "a"), header: reply)
        let found = try await engine.cachedConversation(around: anchor, excludingFolderIDs: [])
        #expect(Set(found.members.map { $0.header.id }) == ["Inbox:2000", "Sent:1"])
        #expect(found.coverage == .cached)
    }

    static func header(_ id: String, folder: String, own: String, parent: String? = nil,
                       references: [String]? = nil) -> MessageHeader {
        MessageHeader(id: id, threadID: own, folderID: folder,
                      from: Correspondent(email: "sender@example.org"), to: [], subject: "Same subject", snippet: "",
                      date: Date(timeIntervalSince1970: 0), messageID: own, inReplyTo: parent, references: references)
    }
}
