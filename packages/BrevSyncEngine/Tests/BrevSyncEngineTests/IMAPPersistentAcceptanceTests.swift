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
import Testing

@Suite("Persistent IMAP cutover acceptance", .serialized)
struct IMAPPersistentAcceptanceTests {
    private let helpers = IMAPLegacyRecoveryTests()
    private let account = IMAPLegacyRecoveryTests.account
    private let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

    @Test("10k historical headers survive failed archival, reopen and public recovery without stale content")
    func persistentLifecycle() async throws {
        let fixture = try IMAPLegacyRecoveryTests.Fixture(sqlite: true)
        defer { fixture.cleanUp() }
        let sourceRoot = fixture.root.appendingPathComponent("sources")
        let bodyRoot = fixture.root.appendingPathComponent("bodies")
        let legacyRoot = fixture.root.appendingPathComponent("legacy")
        let directory = legacyRoot.appendingPathComponent(MailCacheKeyNaming.hexKey(account.id))
            .appendingPathComponent("headers")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(MailCacheKeyNaming.hexKey(inbox.id)).json")
        let headers = (1 ... 10000).map { uid in
            helpers.header(uid, subject: "Quarantined historical \(uid)", date: TimeInterval(uid))
        }
        let data = try JSONEncoder().encode(helpers.snapshot(headers))
        try data.write(to: file)
        let initial = BrevSyncEngine(store: fixture.store)
        let current = (1 ... 50).map { helpers.header($0, subject: "Current server \($0)", date: 20000, isRead: true) }
        try await initial.storeIMAPPage(helpers.page(current, next: "before:1"), account: account)
        let other = BrevAccount(id: "isolated", displayName: "Other", emailAddress: "other@example.test")
        try await initial.storeIMAPPage(helpers.page([helpers.header(10000, subject: "Other account")]), account: other)
        let id = "INBOX:10000"
        await FileIMAPMessageSourceCache(rootDirectory: sourceRoot).setSource(
            IMAPMessageSource(uid: 10000, rawMessage: "Content-Type: text/plain\r\n\r\nstalesecret"),
            accountID: account.id, messageID: id
        )
        await FileIMAPMessageBodyCache(rootDirectory: bodyRoot).setBody(
            MessageBody(messageID: id, plainText: "stalesecret"), accountID: account.id, messageID: id
        )
        let legacy = LegacyIMAPMailboxHeaderCache(rootDirectory: legacyRoot)
        let adapter = IndexedIMAPMailboxHeaderCache(index: initial, account: account, legacy: legacy)
        try helpers.sql(fixture.databaseURL, """
        CREATE TRIGGER fail_large_archive BEFORE INSERT ON imap_legacy_recovery
        WHEN NEW.message_id = 'INBOX:9999' BEGIN SELECT RAISE(ABORT, 'synthetic interruption'); END;
        """)
        await #expect(throws: (any Error).self) { try await adapter.prepare(folderID: inbox.id) }
        #expect(try Data(contentsOf: file) == data)
        #expect(try helpers.scalar(fixture.databaseURL, "SELECT COUNT(*) FROM imap_legacy_recovery;") == 0)
        try helpers.sql(fixture.databaseURL, "DROP TRIGGER fail_large_archive;")
        let started = ContinuousClock.now
        try await adapter.prepare(folderID: inbox.id)
        let migration = ContinuousClock.now - started
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try helpers.scalar(fixture.databaseURL, "SELECT COUNT(*) FROM imap_legacy_recovery;") == 9950)

        let reopened = try BrevSyncEngine(databaseURL: fixture.databaseURL)
        #expect(try await reopened.imapHeaders(ids: current.map(\.id), folderID: inbox.id, account: account)
            .sorted { $0.id < $1.id } == current.sorted { $0.id < $1.id })
        #expect(try await reopened.imapHeaderMetadata(folderID: inbox.id, account: account)?.highestModSeq == 4)
        #expect(try await reopened.imapHeaderMetadata(folderID: inbox.id, account: account)?.nextPageToken == "before:1")
        #expect(await reopened.search(SearchQuery(text: "Quarantined"), account: account).isEmpty)
        #expect(try await reopened.imapThreadingHeaders(for: current, folderID: inbox.id, account: account).count == 50)
        let offline = helpers.backend(reopened, legacy: LegacyIMAPMailboxHeaderCache(rootDirectory: legacyRoot),
                                      sources: FileIMAPMessageSourceCache(rootDirectory: sourceRoot),
                                      bodies: FileIMAPMessageBodyCache(rootDirectory: bodyRoot))
        await #expect(throws: (any Error).self) { _ = try await offline.body(for: id) }
        await #expect(throws: (any Error).self) { _ = try await offline.rawSource(for: id) }
        #expect(await offline.cachedAttachmentMessages(in: [inbox]).allSatisfy { $0.header.id != id })

        let recorder = IMAPLegacyRecoveryTests.FetchRecorder()
        let mutations = IMAPLegacyRecoveryTests.FetchRecorder()
        let online = helpers.backend(reopened, legacy: legacy,
                                     sources: FileIMAPMessageSourceCache(rootDirectory: sourceRoot),
                                     bodies: FileIMAPMessageBodyCache(rootDirectory: bodyRoot),
                                     fetch: { _, _, _, uid in
                                         IMAPMessageSource(uid: uid, rawMessage: "Content-Type: text/plain\r\n\r\nFresh server")
                                     }, messages: { _, _, _, token, _ in
                                         await recorder.record(token)
                                         return IMAPMessageListingPage(messages: [IMAPMessageListing(
                                             uid: 10000, messageID: "current@example.test", subject: "Recovered current",
                                             from: Correspondent(email: "sender@example.test"), to: [], cc: [], bcc: [],
                                             date: Date(timeIntervalSince1970: 30000), isRead: true, isFlagged: true,
                                             isAnswered: false
                                         )], uidValidity: 777, highestModSeq: 4, nextPageToken: nil)
                                     }, condstore: { _, _, _, _ in (highestModSeq: 4, uidValidity: 777, changes: []) },
                                     flag: { _, _, _, _, _, _ in await mutations.record("flag") },
                                     move: { _, _, source, uids, destination, _ in
                                         await mutations.record("\(source)->\(destination)")
                                         return IMAPMoveResult(uidValidity: 777,
                                                               uidMappings: Dictionary(uniqueKeysWithValues: uids
                                                                   .map { ($0, $0) }))
                                     })
        try await online.refresh(folder: inbox)
        try await online.refresh(folder: inbox)
        #expect(await recorder.tokens == ["first", "first"])
        #expect(try await reopened.imapHeaders(ids: [id], folderID: inbox.id, account: account).first?
            .subject == "Recovered current")
        await #expect(throws: (any Error).self) { _ = try await offline.rawSource(for: id) }
        #expect(try await online.rawSource(for: id).contains("Fresh server"))
        #expect(try await offline.body(for: id).plainText?.contains("Fresh server") == true)
        try await online.connect()
        try await online.setRead(false, for: [id])
        #expect(try await reopened.imapHeaders(ids: [id], folderID: inbox.id, account: account).first?.isRead == false)
        let undo = try #require(try await online.moveWithUndo(
            messageIDs: [id], from: inbox, to: Folder(id: "Archive", name: "Archive", role: .archive),
            sourceID: MailSourceID(accountID: account.id, mailboxID: account.id)
        ))
        #expect(try await reopened.imapHeaders(ids: [id], folderID: inbox.id, account: account).isEmpty)
        #expect(try await undo.restore() == [id: id])
        #expect(await mutations.tokens == ["flag", "INBOX->Archive", "Archive->INBOX"])
        try await online.refresh(folder: inbox)
        #expect(try await reopened.imapHeaders(ids: [id], folderID: inbox.id, account: account).first?.isRead == true)
        #expect(await recorder.tokens == ["first", "first", "first"])
        await online.disconnect()

        try await offline.resetLocalCacheAndIndex(for: MailSourceID(accountID: account.id, mailboxID: account.id))
        let cleared = try BrevSyncEngine(databaseURL: fixture.databaseURL)
        #expect(try helpers.scalar(
            fixture.databaseURL,
            "SELECT COUNT(*) FROM imap_legacy_recovery WHERE header_json IS NOT NULL;"
        ) == 0)
        #expect(try await cleared.hasIMAPRecoveryRecord(messageID: id, account: account))
        #expect(await cleared.cachedRawMessage(for: id, account: account) == nil)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file)
        try await IndexedIMAPMailboxHeaderCache(index: cleared, account: account,
                                                legacy: LegacyIMAPMailboxHeaderCache(rootDirectory: legacyRoot))
            .prepare(folderID: inbox.id)
        #expect(try await cleared.imapHeaders(ids: [id], folderID: inbox.id, account: account).isEmpty)
        #expect(try await cleared.imapHeaders(ids: [id], folderID: inbox.id, account: other).count == 1)
        let accounts = InMemoryAccountStore()
        await accounts.add(account)
        await accounts.add(other)
        let connector = IMAPAccountConnector(accountStore: accounts,
                                             configurationStore: InMemoryIMAPAccountConfigurationStore(),
                                             credentialStore: InMemoryMailCredentialStore(), listFolders: { _, _ in [] },
                                             sourceCache: FileIMAPMessageSourceCache(rootDirectory: sourceRoot),
                                             bodyCache: FileIMAPMessageBodyCache(rootDirectory: bodyRoot),
                                             localSearchIndex: { _ in cleared })
        await connector.removeAccount(account.id)
        #expect(try helpers.scalar(fixture.databaseURL, "SELECT COUNT(*) FROM imap_legacy_recovery;") == 0)
        #expect(try await cleared.imapHeaders(ids: [id], folderID: inbox.id, account: other).count == 1)
        print(
            "PERF persistent-recovery rows=10000 indexed=50 quarantine=9950 legacy_bytes=\(data.count) archive_duration=\(migration) first_page_requests=3 mutations=3 isolation=passed restart=passed"
        )
    }
}
