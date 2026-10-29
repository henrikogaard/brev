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

@testable import BrevBackend
@testable import BrevSyncEngine
import Foundation
import SQLite3
import Testing

@Suite("Unverified legacy recovery quarantine")
struct IMAPLegacyRecoveryTests {
    static let account = BrevAccount(id: "recovery", displayName: "Synthetic", emailAddress: "reader@example.test")

    @Test("missing legacy rows stay hidden, without trusting cursor or generation", arguments: [false, true])
    func quarantinesMissing(sqlite: Bool) async throws {
        let fixture = try Fixture(sqlite: sqlite)
        defer { fixture.cleanUp() }
        let store = fixture.store
        try await store.ensureAccount(id: Self.account.id)
        try await store.storeIMAPPage(page([header(7)], next: "before:7"), accountID: Self.account.id)
        try await store.deleteHeaders(messageIDs: ["INBOX:7"], accountID: Self.account.id)
        try await store.storeOriginalBody(Data("old private body".utf8), accountID: Self.account.id, messageID: "INBOX:7")
        try await store.storeIMAPSnapshot(snapshot([header(1), header(7), header(99)]),
                                          accountID: Self.account.id, folderID: "INBOX", importingLegacy: true)
        #expect(await store.headers(accountID: Self.account.id, folderID: "INBOX", limit: 100, offset: 0).isEmpty)
        #expect(try await store.headersByID(["INBOX:1", "INBOX:7", "INBOX:99"], accountID: Self.account.id, folderID: "INBOX")
            .isEmpty)
        #expect(await store.searchHeaders(SearchQuery(text: "Legacy"), accountID: Self.account.id, limit: 100).isEmpty)
        #expect(try await store.selectIMAPHeaders(.attachmentsOrCachedBodies, accountID: Self.account.id, folderID: "INBOX")
            .isEmpty)
        #expect(try await store.conversationCandidates(
            identifier: "shared@example.test",
            source: MailSourceID(accountID: Self.account.id, mailboxID: Self.account.id),
            limit: 100
        ).isEmpty)
        #expect(await store.body(accountID: Self.account.id, messageID: "INBOX:7") == nil)
        #expect(await store.originalBody(accountID: Self.account.id, messageID: "INBOX:7") == nil)
        try await store.upsertHeaders([header(7)], accountID: Self.account.id)
        try await store.storeBody(Data("local rewrite".utf8), accountID: Self.account.id, messageID: "INBOX:7")
        #expect(try await store.headersByID(["INBOX:7"], accountID: Self.account.id, folderID: "INBOX").isEmpty)
        #expect(await store.body(accountID: Self.account.id, messageID: "INBOX:7") == nil)
    }

    @Test("legacy metadata cannot skip server recovery or overwrite indexed metadata", arguments: [false, true])
    func rejectsLegacyMetadata(sqlite: Bool) async throws {
        let fixture = try Fixture(sqlite: sqlite)
        defer { fixture.cleanUp() }
        let store = fixture.store
        try await store.ensureAccount(id: Self.account.id)
        try await store.storeIMAPSnapshot(
            snapshot([header(99)]),
            accountID: Self.account.id,
            folderID: "INBOX",
            importingLegacy: true
        )
        #expect(try await store.imapPageState(accountID: Self.account.id, folderID: "INBOX") == nil)
        #expect(try await store.imapPageUIDs(accountID: Self.account.id, folderID: "INBOX", pageKey: "first").isEmpty)
        let current = header(99, subject: "Server current", date: 900, isRead: true)
        try await store.storeIMAPPage(page([current], next: "before:99"), accountID: Self.account.id)
        #expect(try await store.headersByID([current.id], accountID: Self.account.id, folderID: "INBOX") == [current])
        #expect(try await store.imapPageUIDs(accountID: Self.account.id, folderID: "INBOX", pageKey: "first") == [99])
        try await store.storeIMAPSnapshot(
            snapshot([header(99)]),
            accountID: Self.account.id,
            folderID: "INBOX",
            importingLegacy: true
        )
        #expect(try await store.headersByID([current.id], accountID: Self.account.id, folderID: "INBOX") == [current])
        #expect(try await store.imapPageState(accountID: Self.account.id, folderID: "INBOX")?.nextPageToken == "before:99")
    }

    @Test("partial indexed rows keep current flags, dates, links and windows", arguments: [false, true])
    func preservesIndexed(sqlite: Bool) async throws {
        let fixture = try Fixture(sqlite: sqlite)
        defer { fixture.cleanUp() }
        let store = fixture.store
        try await store.ensureAccount(id: Self.account.id)
        let current = header(7, subject: "Server current", date: 900, isRead: true)
        try await store.storeIMAPPage(page([current], next: "before:7"), accountID: Self.account.id)
        try await store.storeIMAPSnapshot(
            snapshot([header(7), header(99)]),
            accountID: Self.account.id,
            folderID: "INBOX",
            importingLegacy: true
        )
        #expect(try await store.headersByID(["INBOX:7", "INBOX:99"], accountID: Self.account.id, folderID: "INBOX") == [current])
        #expect(try await store.imapPageUIDs(accountID: Self.account.id, folderID: "INBOX", pageKey: "first") == [7])
        #expect(try await store.imapPageState(accountID: Self.account.id, folderID: "INBOX")?.highestModSeq == 4)
    }

    @Test("header confirmation never unlocks stale body or attachment text", arguments: [false, true])
    func contentConfirmation(sqlite: Bool) async throws {
        let fixture = try Fixture(sqlite: sqlite)
        defer { fixture.cleanUp() }
        let store = fixture.store
        let id = "INBOX:99"
        try await store.ensureAccount(id: Self.account.id)
        try await store.storeOriginalBody(
            Data("Content-Type: text/plain\r\n\r\noldbodytoken".utf8),
            accountID: Self.account.id,
            messageID: id
        )
        try await store.storeIMAPSnapshot(
            snapshot([header(99)]),
            accountID: Self.account.id,
            folderID: "INBOX",
            importingLegacy: true
        )
        try await store.indexAttachmentText(
            accountID: Self.account.id,
            messageID: id,
            folderID: "INBOX",
            attachmentID: "old",
            name: "old.pdf",
            text: "oldattachmenttoken"
        )
        try await store.storeIMAPPage(page([header(99, subject: "Current", date: 900, isRead: true)]), accountID: Self.account.id)
        #expect(await store.body(accountID: Self.account.id, messageID: id) == nil)
        #expect(await store.searchHeaders(SearchQuery(text: "oldbodytoken"), accountID: Self.account.id, limit: 100).isEmpty)
        #expect(await store.searchHeaders(SearchQuery(text: "oldattachmenttoken"), accountID: Self.account.id, limit: 100)
            .isEmpty)
        let fresh = Data("Content-Type: text/plain\r\n\r\nfreshbodytoken".utf8)
        try await store.storeConfirmedIMAPSource(fresh, isOriginal: true, accountID: Self.account.id, messageID: id)
        try await store.storeOriginalBody(Data("old local overwrite".utf8), accountID: Self.account.id, messageID: id)
        #expect(await store.originalBody(accountID: Self.account.id, messageID: id) == fresh)
        #expect(await store.searchHeaders(SearchQuery(text: "freshbodytoken"), accountID: Self.account.id, limit: 100)
            .map(\.id) == [id])
    }

    @Test("unknown and mismatched generations never install legacy payload", arguments: [false, true])
    func generations(sqlite: Bool) async throws {
        for old: Int? in [nil, 777, 999] {
            let fixture = try Fixture(sqlite: sqlite)
            defer { fixture.cleanUp() }
            let store = fixture.store
            try await store.ensureAccount(id: Self.account.id)
            try await store.storeIMAPPage(page([header(1, subject: "Current")], generation: 777), accountID: Self.account.id)
            try await store.storeIMAPSnapshot(
                snapshot([header(1), header(99)], generation: old),
                accountID: Self.account.id,
                folderID: "INBOX",
                importingLegacy: true
            )
            #expect(try await store.headersByID(["INBOX:99"], accountID: Self.account.id, folderID: "INBOX").isEmpty)
            try await store.storeIMAPPage(page([header(99, subject: "Fresh")], generation: nil), accountID: Self.account.id)
            #expect(try await store.headersByID(["INBOX:99"], accountID: Self.account.id, folderID: "INBOX").first?
                .subject == "Fresh")
            try await store.clearFolder(accountID: Self.account.id, folderID: "INBOX")
            try await store.storeIMAPSnapshot(
                snapshot([header(99)], generation: old),
                accountID: Self.account.id,
                folderID: "INBOX",
                importingLegacy: true
            )
            #expect(try await store.headersByID(["INBOX:99"], accountID: Self.account.id, folderID: "INBOX").isEmpty)
            try await store.storeIMAPPage(
                page([header(99, subject: "New generation")], generation: 1000),
                accountID: Self.account.id
            )
            #expect(try await store.headersByID(["INBOX:99"], accountID: Self.account.id, folderID: "INBOX").first?
                .subject == "New generation")
        }
    }

    @Test("archive and source confirmation rollback, retry and survive restart")
    func transactions() async throws {
        let fixture = try Fixture(sqlite: true)
        defer { fixture.cleanUp() }
        let store = fixture.store
        let id = "INBOX:99"
        try await store.ensureAccount(id: Self.account.id)
        try sql(
            fixture.databaseURL,
            "CREATE TRIGGER fail_archive BEFORE INSERT ON imap_legacy_recovery BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END;"
        )
        await #expect(throws: (any Error).self) {
            try await store.storeIMAPSnapshot(
                snapshot([header(99)]),
                accountID: Self.account.id,
                folderID: "INBOX",
                importingLegacy: true
            )
        }
        #expect(try scalar(fixture.databaseURL, "SELECT COUNT(*) FROM imap_legacy_imports;") == 0)
        try sql(fixture.databaseURL, "DROP TRIGGER fail_archive;")
        try await store.storeIMAPSnapshot(
            snapshot([header(99)]),
            accountID: Self.account.id,
            folderID: "INBOX",
            importingLegacy: true
        )
        let reopened = try SQLiteSyncStore(databaseURL: fixture.databaseURL)
        #expect(try reopened.hasPendingIMAPRecovery(accountID: Self.account.id, folderID: "INBOX"))
        #expect(try scalar(
            fixture.databaseURL,
            "SELECT COUNT(*) FROM imap_legacy_recovery WHERE header_json LIKE '%Legacy private%';"
        ) == 1)
        try sql(
            fixture.databaseURL,
            "CREATE TRIGGER fail_confirmation BEFORE UPDATE OF source_confirmed ON imap_legacy_recovery BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END;"
        )
        let fresh = Data("fresh".utf8)
        #expect(throws: (any Error).self) { try reopened.storeConfirmedIMAPSource(
            fresh,
            isOriginal: true,
            accountID: Self.account.id,
            messageID: id
        ) }
        #expect(try scalar(fixture.databaseURL, "SELECT COUNT(*) FROM message_bodies;") == 0)
        #expect(await (reopened as any SyncStoreProtocol).originalBody(accountID: Self.account.id, messageID: id) == nil)
        try sql(fixture.databaseURL, "DROP TRIGGER fail_confirmation;")
        try reopened.storeConfirmedIMAPSource(fresh, isOriginal: true, accountID: Self.account.id, messageID: id)
        let again = try SQLiteSyncStore(databaseURL: fixture.databaseURL)
        #expect(await (again as any SyncStoreProtocol).originalBody(accountID: Self.account.id, messageID: id) == fresh)
        try again.deleteHeaders(messageIDs: [id], accountID: Self.account.id)
        #expect(try scalar(fixture.databaseURL, "SELECT COUNT(*) FROM imap_legacy_recovery WHERE header_json IS NOT NULL;") == 0)
        try again.storeIMAPSnapshot(snapshot([header(99)]), accountID: Self.account.id, folderID: "INBOX", importingLegacy: true)
        #expect(try again.headersByID([id], accountID: Self.account.id, folderID: "INBOX").isEmpty)
        #expect(again.body(accountID: Self.account.id, messageID: id) == nil)
        try again.clearAccount(id: Self.account.id)
        #expect(try scalar(fixture.databaseURL, "SELECT COUNT(*) FROM imap_legacy_recovery;") == 0)
    }

    @Test("direct reader and attachment paths cannot escape quarantine, even after header confirmation")
    func backendContent() async throws {
        let fixture = try Fixture(sqlite: true)
        defer { fixture.cleanUp() }
        let engine = BrevSyncEngine(store: fixture.store)
        let legacy = InMemoryIMAPMailboxHeaderCache(headersByFolderByAccount: [Self.account.id: ["INBOX": [header(99)]]])
        let sources = FileIMAPMessageSourceCache(rootDirectory: fixture.root.appendingPathComponent("sources"))
        let bodies = FileIMAPMessageBodyCache(rootDirectory: fixture.root.appendingPathComponent("bodies"))
        let id = "INBOX:99"
        await sources.setSource(IMAPMessageSource(uid: 99, rawMessage: "old secret"), accountID: Self.account.id, messageID: id)
        await bodies.setBody(
            MessageBody(
                messageID: id,
                plainText: "old secret",
                attachments: [Attachment(id: "old", name: "old.pdf", mimeType: "application/pdf", sizeBytes: 3)]
            ),
            accountID: Self.account.id,
            messageID: id
        )
        let backend = backend(engine, legacy: legacy, sources: sources, bodies: bodies)
        await #expect(throws: (any Error).self) { _ = try await backend.body(for: id) }
        await #expect(throws: (any Error).self) { _ = try await backend.rawSource(for: id) }
        #expect(await backend.cachedAttachmentMessages(in: [Folder(id: "INBOX", name: "Inbox", role: .inbox)]).isEmpty)
        try await engine.storeIMAPPage(page([header(99, subject: "Fresh")]), account: Self.account)
        await #expect(throws: (any Error).self) { _ = try await backend.body(for: id) }
        #expect(await backend.cachedAttachmentMessages(in: [Folder(id: "INBOX", name: "Inbox", role: .inbox)]).isEmpty)
        let fresh = "Content-Type: text/plain\r\n\r\nFresh server body"
        let online = self.backend(
            engine,
            legacy: legacy,
            sources: sources,
            bodies: bodies,
            fetch: { _, _, _, _ in IMAPMessageSource(uid: 99, rawMessage: fresh) }
        )
        try await online.connect()
        try sql(
            fixture.databaseURL,
            "CREATE TRIGGER fail_source BEFORE UPDATE OF source_confirmed ON imap_legacy_recovery BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END;"
        )
        #expect(try await online.rawSource(for: id) == fresh)
        let restarted = try self.backend(BrevSyncEngine(databaseURL: fixture.databaseURL), legacy: legacy,
                                         sources: FileIMAPMessageSourceCache(rootDirectory: fixture.root
                                             .appendingPathComponent("sources")),
                                         bodies: FileIMAPMessageBodyCache(rootDirectory: fixture.root
                                             .appendingPathComponent("bodies")))
        await #expect(throws: (any Error).self) { _ = try await restarted.body(for: id) }
        await #expect(throws: (any Error).self) { _ = try await restarted.rawSource(for: id) }
        try sql(fixture.databaseURL, "DROP TRIGGER fail_source;")
        #expect(try await online.rawSource(for: id) == fresh)
        #expect(try await restarted.rawSource(for: id) == fresh)
        #expect(try await restarted.body(for: id).plainText?.contains("Fresh server body") == true)
        try await restarted.resetLocalCacheAndIndex(for: MailSourceID(accountID: Self.account.id, mailboxID: Self.account.id))
        #expect(try scalar(fixture.databaseURL, "SELECT COUNT(*) FROM imap_legacy_recovery WHERE header_json IS NOT NULL;") == 0)
        #expect(try await engine.hasIMAPRecoveryRecord(messageID: id, account: Self.account))
        #expect(await engine.cachedRawMessage(for: id, account: Self.account) == nil)
        try await engine.storeIMAPPage(page([header(99, subject: "After reset")]), account: Self.account)
        #expect(try await engine.imapHeaders(ids: [id], folderID: "INBOX", account: Self.account).count == 1)
    }

    @Test("failed index initialization never unlocks external content", arguments: [false, true])
    func unavailableIndex(online: Bool) async throws {
        let fixture = try Fixture(sqlite: true)
        defer { fixture.cleanUp() }
        let engine = BrevSyncEngine(store: fixture.store)
        let id = "INBOX:99"
        try await engine.storeIMAPSnapshot(snapshot([header(99)]), folderID: "INBOX", account: Self.account,
                                           importingLegacy: true)
        let sources = FileIMAPMessageSourceCache(rootDirectory: fixture.root.appendingPathComponent("sources"))
        let bodies = FileIMAPMessageBodyCache(rootDirectory: fixture.root.appendingPathComponent("bodies"))
        await sources.setSource(IMAPMessageSource(uid: 99, rawMessage: "old secret"), accountID: Self.account.id, messageID: id)
        await bodies.setBody(MessageBody(messageID: id, plainText: "old secret"), accountID: Self.account.id, messageID: id)
        try sql(fixture.databaseURL, "PRAGMA user_version = \(fixture.store.currentSchemaVersion + 1);")
        #expect(throws: (any Error).self) { _ = try BrevSyncEngine(databaseURL: fixture.databaseURL) }

        let accounts = InMemoryAccountStore()
        let configurations = InMemoryIMAPAccountConfigurationStore()
        let credentials = InMemoryMailCredentialStore()
        await accounts.add(Self.account)
        await configurations.setConfiguration(IMAPAccountConfiguration(
            accountID: Self.account.id, emailAddress: Self.account.emailAddress, displayName: Self.account.displayName,
            incoming: MailServerSettings(kind: .imap, host: "imap.example.test", port: 993, tlsMode: .implicit,
                                         authentication: .password),
            outgoing: MailServerSettings(kind: .smtp, host: "smtp.example.test", port: 587, tlsMode: .startTLS,
                                         authentication: .password), credentialID: Self.account.id
        ))
        try await credentials.setCredential(MailAccountCredential(incomingUsername: "synthetic", outgoingUsername: "synthetic",
                                                                  secret: "fixture", authentication: .password),
                                            for: Self.account.id)
        let fresh = "Content-Type: text/plain\r\n\r\nFresh server body"
        let connector = IMAPAccountConnector(
            accountStore: accounts, configurationStore: configurations, credentialStore: credentials,
            listFolders: { _, _ in [] },
            fetchMessageSource: { _, _, _, uid in
                guard online else { throw MailBackendError.notFound(id: id) }
                return IMAPMessageSource(uid: uid, rawMessage: fresh)
            }, sourceCache: sources, bodyCache: bodies,
            localSearchIndex: { _ in try? BrevSyncEngine(databaseURL: fixture.databaseURL) }
        )
        let restored = try await connector.restore(Self.account)
        let backend = try #require(restored)
        if online {
            #expect(try await backend.body(for: id).plainText?.contains("Fresh server body") == true)
            #expect(try await backend.rawSource(for: id) == fresh)
        } else {
            await #expect(throws: (any Error).self) { _ = try await backend.body(for: id) }
            await #expect(throws: (any Error).self) { _ = try await backend.rawSource(for: id) }
        }
        await backend.disconnect()
        #expect(try scalar(fixture.databaseURL,
                           "SELECT COUNT(*) FROM imap_legacy_recovery WHERE source_confirmed = 0;") == 1)
        #expect(await sources.source(accountID: Self.account.id, messageID: id)?.rawMessage == "old secret")
    }

    @Test("connector removal erases quarantine and external content only for the removed account")
    func connectorRemoval() async throws {
        let fixture = try Fixture(sqlite: true)
        defer { fixture.cleanUp() }
        let engine = BrevSyncEngine(store: fixture.store)
        let other = BrevAccount(id: "other", displayName: "Other", emailAddress: "other@example.test")
        for account in [Self.account, other] {
            try await engine.storeIMAPSnapshot(snapshot([header(99)]), folderID: "INBOX", account: account, importingLegacy: true)
        }
        let accounts = InMemoryAccountStore()
        await accounts.add(Self.account)
        await accounts.add(other)
        let bodies = FileIMAPMessageBodyCache(rootDirectory: fixture.root.appendingPathComponent("bodies"))
        let sources = FileIMAPMessageSourceCache(rootDirectory: fixture.root.appendingPathComponent("sources"))
        for account in [Self.account, other] {
            await bodies.setBody(
                MessageBody(messageID: "INBOX:99", plainText: "private"),
                accountID: account.id,
                messageID: "INBOX:99"
            )
            await sources.setSource(
                IMAPMessageSource(uid: 99, rawMessage: "private"),
                accountID: account.id,
                messageID: "INBOX:99"
            )
        }
        let connector = IMAPAccountConnector(accountStore: accounts, configurationStore: InMemoryIMAPAccountConfigurationStore(),
                                             credentialStore: InMemoryMailCredentialStore(), listFolders: { _, _ in [] },
                                             sourceCache: sources, bodyCache: bodies, localSearchIndex: { _ in engine })
        await connector.removeAccount(Self.account.id)
        #expect(try await !engine.hasIMAPRecoveryRecord(messageID: "INBOX:99", account: Self.account))
        #expect(try await engine.hasIMAPRecoveryRecord(messageID: "INBOX:99", account: other))
        #expect(await sources.source(accountID: Self.account.id, messageID: "INBOX:99") == nil)
        #expect(await bodies.body(accountID: Self.account.id, messageID: "INBOX:99") == nil)
        #expect(await bodies.body(accountID: other.id, messageID: "INBOX:99") != nil)
        #expect(await accounts.accounts.map(\.id) == [other.id])
    }

    @Test("schema v10 upgrades after v9 and rolls back on failure")
    func schemaUpgrade() throws {
        let fixture = try Fixture(sqlite: true)
        defer { fixture.cleanUp() }
        try sql(
            fixture.databaseURL,
            "DROP TABLE imap_legacy_recovery; PRAGMA user_version = 9; CREATE VIEW imap_legacy_recovery AS SELECT 1;"
        )
        #expect(throws: (any Error).self) { _ = try SQLiteSyncStore(databaseURL: fixture.databaseURL) }
        #expect(try scalar(fixture.databaseURL, "PRAGMA user_version;") == 9)
        #expect(try scalar(
            fixture.databaseURL,
            "SELECT COUNT(*) FROM sqlite_master WHERE name = 'idx_imap_attachment_headers';"
        ) ==
            1)
        try sql(fixture.databaseURL, "DROP VIEW imap_legacy_recovery;")
        let upgraded = try SQLiteSyncStore(databaseURL: fixture.databaseURL)
        #expect(upgraded.currentSchemaVersion == 10)
        #expect(try scalar(fixture.databaseURL, "PRAGMA user_version;") == 10)
        #expect(try scalar(fixture.databaseURL, "SELECT COUNT(*) FROM imap_legacy_recovery;") == 0)
    }

    @Test("failed archival retains legacy JSON and a successful retry removes it")
    func legacyFileRetry() async throws {
        let fixture = try Fixture(sqlite: true)
        defer { fixture.cleanUp() }
        let directory = fixture.root.appendingPathComponent(MailCacheKeyNaming.hexKey(Self.account.id))
            .appendingPathComponent("headers")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(MailCacheKeyNaming.hexKey("INBOX")).json")
        try JSONEncoder().encode(snapshot([header(99)])).write(to: file)
        let legacy = LegacyIMAPMailboxHeaderCache(rootDirectory: fixture.root)
        let adapter = IndexedIMAPMailboxHeaderCache(
            index: BrevSyncEngine(store: fixture.store),
            account: Self.account,
            legacy: legacy
        )
        try sql(
            fixture.databaseURL,
            "CREATE TRIGGER fail_archive BEFORE INSERT ON imap_legacy_recovery BEGIN SELECT RAISE(ABORT, 'synthetic'); END;"
        )
        await #expect(throws: (any Error).self) { try await adapter.prepare(folderID: "INBOX") }
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try scalar(fixture.databaseURL, "SELECT COUNT(*) FROM imap_legacy_imports;") == 0)
        try sql(fixture.databaseURL, "DROP TRIGGER fail_archive;")
        try await adapter.prepare(folderID: "INBOX")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try scalar(fixture.databaseURL, "SELECT COUNT(*) FROM imap_legacy_recovery WHERE header_json IS NOT NULL;") == 1)
    }

    @Test("normal refresh, unchanged CONDSTORE, pagination and explicit rebuild recover server headers", arguments: [false, true])
    func serverRecovery(rebuild: Bool) async throws {
        let fixture = try Fixture(sqlite: true)
        defer { fixture.cleanUp() }
        let engine = BrevSyncEngine(store: fixture.store)
        try await engine.storeIMAPPage(page([], next: "before:99"), account: Self.account)
        let legacy = InMemoryIMAPMailboxHeaderCache(snapshotsByFolderByAccount: [Self.account.id: ["INBOX": snapshot([
            header(1),
            header(99)
        ])]])
        let recorder = FetchRecorder()
        let backend = backend(
            engine,
            legacy: legacy,
            sources: InMemoryIMAPMessageSourceCache(),
            bodies: InMemoryIMAPMessageBodyCache(),
            fetch: { _, _, _, uid in IMAPMessageSource(uid: uid, rawMessage: "Content-Type: text/plain\r\n\r\nFresh") },
            messages: { _, _, _, token, _ in
                await recorder.record(token)
                let uid = token == nil ? 99 : 1
                let listing = IMAPMessageListing(
                    uid: uid,
                    messageID: "server-\(uid)@example.test",
                    subject: "Fresh \(uid)",
                    from: Correspondent(email: "sender@example.test"),
                    to: [],
                    cc: [],
                    bcc: [],
                    date: Date(timeIntervalSince1970: 900),
                    isRead: true,
                    isFlagged: false,
                    isAnswered: false
                )
                return IMAPMessageListingPage(messages: [listing], uidValidity: 777, highestModSeq: 4,
                                              nextPageToken: token == nil ? "before:99" : nil)
            },
            condstore: { _, _, _, _ in (highestModSeq: 4, uidValidity: 777, changes: []) }
        )
        let folder = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        if rebuild {
            try await backend.rebuildSearchIndex(for: MailSourceID(accountID: Self.account.id, mailboxID: Self.account.id))
        } else {
            try await backend.refresh(folder: folder)
            #expect(try await engine.imapHeaders(ids: ["INBOX:99"], folderID: "INBOX", account: Self.account).first?
                .subject == "Fresh 99")
            let first = try await backend.messages(in: folder, pageToken: nil)
            #expect(first.headers.map(\.id) == ["INBOX:99"])
            let token = try #require(first.nextPageToken)
            let older = try await backend.messages(in: folder, pageToken: token)
            #expect(older.headers.map(\.id) == ["INBOX:1"])
        }
        #expect(try await !engine.hasPendingIMAPRecovery(folderID: "INBOX", account: Self.account))
        #expect(try await engine.imapHeaders(ids: ["INBOX:1", "INBOX:99"], folderID: "INBOX", account: Self.account)
            .allSatisfy(\.isRead))
        #expect(await recorder.tokens == ["first", "before:99"])
        await backend.disconnect()
    }

    @Test("unconfirmed historical records cost one existing first-page request per refresh, without recovery sweeps")
    func repeatedRefreshTradeoff() async throws {
        let fixture = try Fixture(sqlite: true)
        defer { fixture.cleanUp() }
        let engine = BrevSyncEngine(store: fixture.store)
        try await engine.storeIMAPPage(page([], next: nil), account: Self.account)
        let legacy =
            InMemoryIMAPMailboxHeaderCache(snapshotsByFolderByAccount: [Self.account.id: ["INBOX": snapshot([header(99)])]])
        let recorder = FetchRecorder()
        let backend = backend(
            engine,
            legacy: legacy,
            sources: InMemoryIMAPMessageSourceCache(),
            bodies: InMemoryIMAPMessageBodyCache(),
            messages: { _, _, _, token, _ in
                await recorder.record(token)
                return IMAPMessageListingPage(
                    messages: [],
                    uidValidity: 777,
                    highestModSeq: 4,
                    nextPageToken: nil
                )
            },
            condstore: { _, _, _, _ in (highestModSeq: 4, uidValidity: 777, changes: []) }
        )
        for _ in 0 ..< 2 {
            try await backend.refresh(folder: Folder(id: "INBOX", name: "Inbox", role: .inbox))
        }
        #expect(try await engine.hasPendingIMAPRecovery(folderID: "INBOX", account: Self.account))
        #expect(await recorder.tokens == ["first", "first"])
        await backend.disconnect()
    }

    actor FetchRecorder {
        var tokens: [String] = []
        func record(_ token: String?) { tokens.append(token ?? "first") }
    }

    func backend(_ engine: BrevSyncEngine, legacy: any IMAPMailboxHeaderCache,
                 sources: any IMAPMessageSourceCache, bodies: any IMAPMessageBodyCache,
                 fetch: IMAPSMTPBackend.MessageSourceFetchOperation? = nil,
                 messages: IMAPSMTPBackend.MessageListingOperation? = nil,
                 condstore: IMAPSMTPBackend.CONDSTORESyncOperation? = nil) -> IMAPSMTPBackend {
        let configuration = IMAPAccountConfiguration(
            accountID: Self.account.id, emailAddress: Self.account.emailAddress, displayName: Self.account.displayName,
            incoming: MailServerSettings(
                kind: .imap,
                host: "imap.example.test",
                port: 993,
                tlsMode: .implicit,
                authentication: .password
            ),
            outgoing: MailServerSettings(
                kind: .smtp,
                host: "smtp.example.test",
                port: 587,
                tlsMode: .startTLS,
                authentication: .password
            ), credentialID: Self.account.id
        )
        let credential = MailAccountCredential(
            incomingUsername: "synthetic",
            outgoingUsername: "synthetic",
            secret: "fixture",
            authentication: .password
        )
        return IMAPSMTPBackend(account: Self.account, configuration: configuration, credential: credential,
                               listFolders: { _, _ in [IMAPFolderListing(
                                   path: "INBOX",
                                   displayName: "Inbox",
                                   delimiter: "/",
                                   flags: [],
                                   role: .inbox
                               )] },
                               listMessages: messages, fetchMessageSource: fetch, condstoreSync: condstore, headerCache: legacy,
                               sourceCache: sources, bodyCache: bodies, localSearchIndex: engine)
    }

    func sql(_ url: URL, _ query: String) throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, query, nil, nil, nil) == SQLITE_OK else {
            throw SyncStoreError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func scalar(_ url: URL, _ query: String) throws -> Int {
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        return Int(sqlite3_column_int(stmt, 0))
    }

    func header(_ uid: Int, subject: String = "Legacy private", date: TimeInterval = 10, isRead: Bool = false) -> MessageHeader {
        MessageHeader(
            id: "INBOX:\(uid)",
            threadID: "shared",
            folderID: "INBOX",
            from: Correspondent(email: "sender@example.test"),
            subject: subject,
            snippet: "",
            date: Date(timeIntervalSince1970: date),
            isRead: isRead,
            hasAttachments: true,
            references: ["shared@example.test"]
        )
    }

    func page(_ headers: [MessageHeader], next: String? = nil, generation: Int? = 777,
              token: String? = nil) -> IMAPHeaderPageWrite {
        IMAPHeaderPageWrite(
            folderID: "INBOX",
            pageToken: token,
            headers: headers,
            uidValidity: generation,
            highestModSeq: 4,
            nextPageToken: next
        )
    }

    func snapshot(_ headers: [MessageHeader], generation: Int? = 777) -> IMAPMailboxHeaderCacheSnapshot {
        IMAPMailboxHeaderCacheSnapshot(headers: headers, uidValidity: generation, highestModSeq: 999, nextPageToken: "before:1",
                                       firstPageHeaderIDs: ["INBOX:9999"], pageHeaderIDsByToken: ["before:7": ["Other:7"]])
    }

    struct Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brev-quarantine-\(UUID())")
        let store: any SyncStoreProtocol
        var databaseURL: URL { root.appendingPathComponent("index.sqlite") }
        init(sqlite: Bool) throws {
            store = sqlite ? try SQLiteSyncStore(databaseURL: root.appendingPathComponent("index.sqlite")) : InMemorySyncStore()
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }
}
