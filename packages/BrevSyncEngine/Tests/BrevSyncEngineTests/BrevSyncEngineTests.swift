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
import SQLite3
import XCTest

// MARK: - Helpers

private func testAccount(id: String = "acc1") -> BrevAccount {
    BrevAccount(id: id, displayName: "Test", emailAddress: "test@example.com")
}

private func testFolder(id: String = "INBOX") -> Folder {
    Folder(id: id, name: "Inbox", role: .inbox, parentID: nil)
}

private func testHeader(
    uid: Int,
    folderID: String = "INBOX",
    date: Date = Date(),
    isRead: Bool = false,
    subject: String? = nil,
    from: Correspondent = Correspondent(name: "Sender", email: "sender@example.com"),
    to: [Correspondent] = [],
    cc: [Correspondent] = [],
    bcc: [Correspondent] = [],
    isFlagged: Bool = false,
    hasAttachments: Bool = false
) -> MessageHeader {
    MessageHeader(
        id: "\(folderID):\(uid)",
        threadID: "thread-\(uid)",
        folderID: folderID,
        from: from,
        to: to,
        cc: cc,
        bcc: bcc,
        subject: subject ?? "Subject \(uid)",
        snippet: "",
        date: date,
        isRead: isRead,
        isFlagged: isFlagged,
        hasAttachments: hasAttachments
    )
}

private func syncResult(
    uidValidity: Int = 1,
    uidNext: Int = 100,
    highestModSeq: UInt64? = 42,
    headers: [MessageHeader] = [],
    expunged: [String] = []
) -> FolderSyncResult {
    FolderSyncResult(
        uidValidity: uidValidity,
        uidNext: uidNext,
        highestModSeq: highestModSeq,
        updatedHeaders: headers,
        expungedMessageIDs: expunged
    )
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - BrevSyncEngineTests

final class BrevSyncEngineTests: XCTestCase {
    // MARK: default database URL

    func testDefaultDatabaseURLUsesStablePrivacySafeAccountKey() {
        let url = BrevSyncEngine.defaultDatabaseURL(accountID: "imap-smtp:person@example.com")

        XCTAssertEqual(url.lastPathComponent, "696d61702d736d74703a706572736f6e406578616d706c652e636f6d.sqlite")
        XCTAssertFalse(url.path.contains("person@example.com"))
        XCTAssertEqual(
            url,
            BrevSyncEngine.defaultDatabaseURL(accountID: "imap-smtp:person@example.com")
        )
    }

    func testDefaultDatabaseURLMigratesLegacyRawAccountFilename() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root
            .appendingPathComponent("Brev", isDirectory: true)
            .appendingPathComponent("sync-cache", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let legacy = directory.appendingPathComponent("imap-smtp:person@example.com.sqlite")
        try Data("legacy-db".utf8).write(to: legacy)
        try Data("legacy-wal".utf8).write(to: URL(fileURLWithPath: legacy.path + "-wal"))
        try Data("legacy-shm".utf8).write(to: URL(fileURLWithPath: legacy.path + "-shm"))

        let encoded = SQLiteSyncStore.defaultURL(
            accountID: "imap-smtp:person@example.com",
            applicationSupportDirectory: root
        )

        XCTAssertEqual(encoded.lastPathComponent, "696d61702d736d74703a706572736f6e406578616d706c652e636f6d.sqlite")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path + "-shm"))
        XCTAssertEqual(try Data(contentsOf: encoded), Data("legacy-db".utf8))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: encoded.path + "-wal")), Data("legacy-wal".utf8))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: encoded.path + "-shm")), Data("legacy-shm".utf8))
    }

    func testDefaultDatabaseURLDoesNotOverwriteExistingEncodedDatabase() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root
            .appendingPathComponent("Brev", isDirectory: true)
            .appendingPathComponent("sync-cache", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let legacy = directory.appendingPathComponent("imap-smtp:person@example.com.sqlite")
        let encoded = directory.appendingPathComponent(
            "696d61702d736d74703a706572736f6e406578616d706c652e636f6d.sqlite"
        )
        try Data("legacy-db".utf8).write(to: legacy)
        try Data("encoded-db".utf8).write(to: encoded)

        let resolved = SQLiteSyncStore.defaultURL(
            accountID: "imap-smtp:person@example.com",
            applicationSupportDirectory: root
        )

        XCTAssertEqual(resolved, encoded)
        XCTAssertEqual(try Data(contentsOf: legacy), Data("legacy-db".utf8))
        XCTAssertEqual(try Data(contentsOf: encoded), Data("encoded-db".utf8))
    }

    // MARK: InMemorySyncStore contract parity

    func testInMemoryStoreReportsCurrentSchemaVersion() async {
        let store = InMemorySyncStore()
        let version = await store.currentSchemaVersion
        XCTAssertEqual(version, 4)
    }

    // MARK: cachedHeaders returns nil before first sync

    func testCachedHeadersReturnsNilBeforeFirstSync() async {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()

        let result = await engine.cachedHeaders(for: folder, account: account, pageToken: nil)
        XCTAssertNil(result, "cachedHeaders must return nil when no sync state exists for the folder")
    }

    // MARK: syncFolder stores headers

    func testSyncFolderStoresHeaders() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()
        let now = Date()
        let headers = [
            testHeader(uid: 1, date: now - 1),
            testHeader(uid: 2, date: now)
        ]

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: headers)
        }

        let cached = await engine.cachedHeaders(for: folder, account: account, pageToken: nil)
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.headers.count, 2)
        // Newest first
        XCTAssertEqual(cached?.headers.first?.id, "INBOX:2")
    }

    // MARK: syncFolder respects dirty flag

    func testSyncFolderSkipsDirtyHeaders() async throws {
        let store = InMemorySyncStore()
        let engine = BrevSyncEngine(store: store)
        let account = testAccount()
        let folder = testFolder()

        // Prime the cache with two messages.
        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [testHeader(uid: 1, isRead: true), testHeader(uid: 2, isRead: true)])
        }

        // Mark message 1 as dirty (pending local mutation).
        await engine.markDirty(messageIDs: ["INBOX:1"], account: account)

        // Sync again with updated flags for both messages.
        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(
                highestModSeq: 99,
                headers: [
                    testHeader(uid: 1, isRead: false),
                    testHeader(uid: 2, isRead: false)
                ]
            )
        }

        let cached = await engine.cachedHeaders(for: folder, account: account, pageToken: nil)
        let byID = Dictionary(uniqueKeysWithValues: cached!.headers.map { ($0.id, $0) })

        // Message 1 is dirty — its flags must not be overwritten.
        XCTAssertTrue(byID["INBOX:1"]?.isRead == true, "Dirty message flag must not be overwritten")
        // Message 2 is not dirty — its flag must be updated.
        XCTAssertTrue(byID["INBOX:2"]?.isRead == false, "Non-dirty message flag must reflect server state")
    }

    func testInMemoryHeaderMessageIDChangeRemovesStaleBodyAndSearchRows() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount(id: "acc")
        let original = testHeader(uid: 7, folderID: "INBOX", subject: "Original stale subject")
        let replacement = MessageHeader(
            id: "Recovered:7",
            threadID: "thread-recovered-7",
            folderID: "INBOX",
            from: Correspondent(name: "Sender", email: "sender@example.com"),
            subject: "Replacement fresh subject",
            snippet: "",
            date: original.date,
            isRead: false,
            isFlagged: false
        )

        await engine.storeHeaders([original], account: account)
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nstale body needle".utf8),
            for: original.id,
            account: account
        )

        await engine.storeHeaders([replacement], account: account)

        let staleMatches = await engine.search(SearchQuery(text: "stale"), account: account)
        let freshMatches = await engine.search(SearchQuery(text: "fresh"), account: account)
        let staleBody = await engine.cachedBody(for: "INBOX:7", account: account)
        let metrics = await engine.metrics(for: account)

        XCTAssertEqual(staleMatches, [])
        XCTAssertEqual(freshMatches.map(\.id), ["Recovered:7"])
        XCTAssertNil(staleBody)
        XCTAssertEqual(metrics?.indexedHeaderCount, 1)
        XCTAssertEqual(metrics?.cachedBodyCount, 0)
        XCTAssertEqual(metrics?.searchDocumentCount, 1)
    }

    func testInMemoryDeleteRawMessagesInFolderDoesNotDeleteColonNestedFolders() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount(id: "acc")

        await engine.storeHeaders([
            testHeader(uid: 1, folderID: "Projects", subject: "Parent subject"),
            testHeader(uid: 1, folderID: "Projects:2026", subject: "Nested subject")
        ], account: account)
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nparent body needle".utf8),
            for: "Projects:1",
            account: account
        )
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nnested body needle".utf8),
            for: "Projects:2026:1",
            account: account
        )

        await engine.deleteRawMessages(inFolder: "Projects", account: account)

        let parentBodySearchResults = await engine.search(SearchQuery(text: "parent body needle"), account: account)
        let nestedBodySearchResults = await engine.search(SearchQuery(text: "nested body needle"), account: account)
        let parentBody = await engine.cachedBody(for: "Projects:1", account: account)
        let nestedBody = await engine.cachedBody(for: "Projects:2026:1", account: account)

        XCTAssertEqual(parentBodySearchResults, [])
        XCTAssertEqual(nestedBodySearchResults.map(\.id), ["Projects:2026:1"])
        XCTAssertNil(parentBody)
        XCTAssertNotNil(nestedBody)
    }

    func testInMemoryClearFolderRemovesBodyOnlyRows() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount(id: "acc")
        let folder = testFolder(id: "INBOX")

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [testHeader(uid: 1, folderID: "INBOX")])
        }
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nbody without header".utf8),
            for: "INBOX:42",
            account: account
        )

        await engine.invalidate(folder: folder, account: account, reason: .uidValidityChanged)

        let body = await engine.cachedBody(for: "INBOX:42", account: account)
        let metrics = await engine.metrics(for: account)

        XCTAssertNil(body)
        XCTAssertEqual(metrics?.cachedBodyCount, 0)
    }

    // MARK: syncFolder removes expunged messages

    func testSyncFolderRemovesExpungedMessages() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [testHeader(uid: 1), testHeader(uid: 2)])
        }

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(expunged: ["INBOX:1"])
        }

        let cached = await engine.cachedHeaders(for: folder, account: account, pageToken: nil)
        XCTAssertEqual(cached?.headers.count, 1)
        XCTAssertNil(cached?.headers.first(where: { $0.id == "INBOX:1" }))
    }

    func testSyncFolderRemovesBodiesAndSearchTextForExpungedMessages() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [
                testHeader(uid: 1, subject: "Retained"),
                testHeader(uid: 2, subject: "Deleted")
            ])
        }
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nexpunged body needle".utf8),
            for: "INBOX:2",
            account: account
        )

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(expunged: ["INBOX:2"])
        }

        let body = await engine.cachedBody(for: "INBOX:2", account: account)
        let bodySearch = await engine.search(SearchQuery(text: "needle"), account: account)

        XCTAssertNil(body)
        XCTAssertTrue(bodySearch.isEmpty)
    }

    // MARK: syncFolder clears cache on UIDVALIDITY change

    func testSyncFolderClearsCacheOnUIDValidityChange() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(uidValidity: 1, headers: [testHeader(uid: 1), testHeader(uid: 2)])
        }

        // New UIDVALIDITY — all cached UIDs are now invalid.
        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(uidValidity: 2, headers: [testHeader(uid: 10)])
        }

        let cached = await engine.cachedHeaders(for: folder, account: account, pageToken: nil)
        XCTAssertEqual(cached?.headers.count, 1)
        XCTAssertEqual(cached?.headers.first?.id, "INBOX:10")
    }

    // MARK: syncState reflects CONDSTORE tier

    func testSyncStateReflectsCONDSTORETier() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(highestModSeq: 77)
        }

        let state = await engine.syncState(for: folder, account: account)
        XCTAssertEqual(state?.syncTier, .condstore)
        XCTAssertEqual(state?.highestModSeq, 77)
    }

    func testSyncStateReflectsUIDScanTierWhenNoModSeq() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(highestModSeq: nil)
        }

        let state = await engine.syncState(for: folder, account: account)
        XCTAssertEqual(state?.syncTier, .uidScan)
    }

    // MARK: invalidate — uidValidityChanged

    func testInvalidateUIDValidityChangedClearsState() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [testHeader(uid: 1)])
        }

        await engine.invalidate(folder: folder, account: account, reason: .uidValidityChanged)

        let state = await engine.syncState(for: folder, account: account)
        let cached = await engine.cachedHeaders(for: folder, account: account, pageToken: nil)
        XCTAssertNil(state, "Sync state must be cleared after uidValidityChanged invalidation")
        XCTAssertNil(cached, "Headers must be cleared after uidValidityChanged invalidation")
    }

    func testInvalidateUIDValidityChangedClearsBodiesAndSearchText() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [testHeader(uid: 1)])
        }
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nstale body needle".utf8),
            for: "INBOX:1",
            account: account
        )

        await engine.invalidate(folder: folder, account: account, reason: .uidValidityChanged)

        let body = await engine.cachedBody(for: "INBOX:1", account: account)
        let bodySearch = await engine.search(SearchQuery(text: "needle"), account: account)

        XCTAssertNil(body)
        XCTAssertTrue(bodySearch.isEmpty)
    }

    // MARK: invalidate — mutationApplied

    func testInvalidateMutationAppliedResetsModSeq() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(highestModSeq: 50)
        }

        await engine.invalidate(folder: folder, account: account, reason: .mutationApplied)

        let state = await engine.syncState(for: folder, account: account)
        XCTAssertEqual(state?.highestModSeq, 0, "mutationApplied must reset highestModSeq to 0")
    }

    // MARK: markDirty / clearDirty round-trip

    func testMarkAndClearDirty() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [testHeader(uid: 1)])
        }

        await engine.markDirty(messageIDs: ["INBOX:1"], account: account)

        // Sync — message 1 should be skipped.
        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [testHeader(uid: 1, isRead: true)])
        }
        var cached = await engine.cachedHeaders(for: folder, account: account, pageToken: nil)
        XCTAssertFalse(cached?.headers.first?.isRead ?? true, "Dirty message must not be overwritten")

        await engine.clearDirty(messageIDs: ["INBOX:1"], account: account)

        // Sync again — now message 1 should be updated.
        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [testHeader(uid: 1, isRead: true)])
        }
        cached = await engine.cachedHeaders(for: folder, account: account, pageToken: nil)
        XCTAssertTrue(cached?.headers.first?.isRead ?? false, "Cleared message must accept server state")
    }

    // MARK: Pagination

    func testCachedHeadersPagination() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()
        let now = Date()
        // 55 headers to force two pages (page size = 50).
        let headers = (1 ... 55).map { testHeader(uid: $0, date: now - Double($0)) }

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: headers)
        }

        let page1 = await engine.cachedHeaders(for: folder, account: account, pageToken: nil)
        XCTAssertEqual(page1?.headers.count, 50)
        XCTAssertNotNil(page1?.nextPageToken)

        let page2 = await engine.cachedHeaders(
            for: folder,
            account: account,
            pageToken: page1?.nextPageToken
        )
        XCTAssertEqual(page2?.headers.count, 5)
        XCTAssertNil(page2?.nextPageToken)
    }

    // MARK: Body storage

    func testBodyStorageRoundTrip() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let messageID = "INBOX:1"
        let raw = Data("From: test@example.com\r\n\r\nHello".utf8)

        await engine.storeBody(raw, for: messageID, account: account)
        let retrieved = await engine.cachedBody(for: messageID, account: account)

        XCTAssertEqual(retrieved, raw)
    }

    // MARK: Local search

    func testSearchFindsHeaderAndCachedBodyText() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [
                testHeader(uid: 1, folderID: "INBOX", date: Date(timeIntervalSince1970: 2)),
                testHeader(uid: 2, folderID: "Archive", date: Date(timeIntervalSince1970: 1)),
            ])
        }
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nQuarterly roadmap details".utf8),
            for: "Archive:2",
            account: account
        )

        let subjectMatches = await engine.search(SearchQuery(text: "Subject 1"), account: account)
        let bodyMatches = await engine.search(SearchQuery(text: "roadmap"), account: account)
        let scopedMiss = await engine.search(
            SearchQuery(text: "roadmap", folderID: "INBOX"),
            account: account
        )

        XCTAssertEqual(subjectMatches.map(\.id), ["INBOX:1"])
        XCTAssertEqual(bodyMatches.map(\.id), ["Archive:2"])
        XCTAssertTrue(scopedMiss.isEmpty)
    }

    func testInMemorySearchMatchesCachedBodyAcrossDiacriticsAndTokens() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [
                testHeader(
                    uid: 1,
                    folderID: "INBOX",
                    date: Date(timeIntervalSince1970: 1),
                    subject: "Flytteplan"
                ),
            ])
        }
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nNeste møte er flyttet.".utf8),
            for: "INBOX:1",
            account: account
        )

        let bodyMatches = await engine.search(SearchQuery(text: "mote flyttet"), account: account)
        let headerAndBodyMatches = await engine.search(SearchQuery(text: "flytteplan mote"), account: account)

        XCTAssertEqual(bodyMatches.map(\.id), ["INBOX:1"])
        XCTAssertEqual(headerAndBodyMatches.map(\.id), ["INBOX:1"])
    }

    func testInMemorySearchIndexesDecodedMimeBodyText() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [
                testHeader(uid: 1, folderID: "INBOX", subject: "Encoded"),
            ])
        }
        await engine.storeBody(
            Data("""
            Content-Type: text/plain; charset=utf-8
            Content-Transfer-Encoding: base64

            Q2FjaGVkIGJvZHkgbmVlZGxl
            """.utf8),
            for: "INBOX:1",
            account: account
        )

        let decodedMatches = await engine.search(SearchQuery(text: "cached body needle"), account: account)
        let rawEncodingMatches = await engine.search(SearchQuery(text: "q2fjz2vk"), account: account)

        XCTAssertEqual(decodedMatches.map(\.id), ["INBOX:1"])
        XCTAssertTrue(rawEncodingMatches.isEmpty)
    }

    func testInMemorySearchIndexesNumericHTMLEntitiesFromDownloadedSource() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [
                testHeader(uid: 1, folderID: "INBOX", subject: "HTML only"),
            ])
        }
        await engine.storeBody(
            Data("""
            Content-Type: text/html; charset=utf-8
            Content-Transfer-Encoding: 8bit

            <html><body>Kj&#XE6;re &#216;g&#229;rd invoice&nbsp;#123 &amp; ready</body></html>
            """.utf8),
            for: "INBOX:1",
            account: account
        )

        let matches = await engine.search(SearchQuery(text: "kjaere ogard invoice 123 ready"), account: account)

        XCTAssertEqual(matches.map(\.id), ["INBOX:1"])
    }

    func testInMemorySearchIndexesLegacyEightBitBodyText() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [
                testHeader(uid: 1, folderID: "INBOX", subject: "Legacy charset"),
            ])
        }
        let rawMessage = [
            "Content-Type: text/plain; charset=iso-8859-1",
            "Content-Transfer-Encoding: 8bit",
            "",
            "Kjære Henrik Øgård",
        ].joined(separator: "\r\n")
        let rawData = try XCTUnwrap(rawMessage.data(using: .isoLatin1))
        await engine.storeBody(rawData, for: "INBOX:1", account: account)

        let matches = await engine.search(SearchQuery(text: "kjaere ogard"), account: account)

        XCTAssertEqual(matches.map(\.id), ["INBOX:1"])
    }

    func testInMemorySearchIndexesMultipartLegacyEightBitBodyText() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [
                testHeader(uid: 1, folderID: "INBOX", subject: "Multipart legacy charset"),
            ])
        }
        await engine.storeBody(Self.multipartWindows1251Body(), for: "INBOX:1", account: account)

        let matches = await engine.search(SearchQuery(text: "привет"), account: account)

        XCTAssertEqual(matches.map(\.id), ["INBOX:1"])
    }

    func testInMemorySearchIndexesAttachmentFilenamesFromDownloadedSource() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [
                testHeader(uid: 1, folderID: "INBOX", subject: "Plain body", hasAttachments: true),
            ])
        }
        await engine.storeBody(
            Data("""
            Content-Type: multipart/mixed; boundary="brev-boundary"

            --brev-boundary
            Content-Type: text/plain; charset=utf-8

            Body text does not mention the file name.
            --brev-boundary
            Content-Type: application/pdf
            Content-Disposition: attachment; filename="Quarterly-Receipt.pdf"
            Content-Transfer-Encoding: base64

            SGVsbG8=
            --brev-boundary--
            """.utf8),
            for: "INBOX:1",
            account: account
        )

        let matches = await engine.search(SearchQuery(text: "quarterly receipt"), account: account)

        XCTAssertEqual(matches.map(\.id), ["INBOX:1"])
    }

    func testMetricsReportIndexedHeadersBodiesAndFolders() async throws {
        let engine = BrevSyncEngine(store: InMemorySyncStore())
        let account = testAccount()
        let folder = testFolder()

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [
                testHeader(uid: 1, folderID: "INBOX"),
                testHeader(uid: 2, folderID: "INBOX"),
            ])
        }
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nCached source".utf8),
            for: "INBOX:2",
            account: account
        )

        let metrics = await engine.metrics(for: account)

        XCTAssertEqual(metrics?.indexedHeaderCount, 2)
        XCTAssertEqual(metrics?.cachedBodyCount, 1)
        XCTAssertEqual(metrics?.searchDocumentCount, 2)
        XCTAssertEqual(metrics?.syncedFolderCount, 1)
    }

    func testStoreHeadersMarksFoldersCachedForSQLiteLocalIndexPaging() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        await engine.storeHeaders([
            testHeader(uid: 1, folderID: "INBOX"),
            testHeader(uid: 2, folderID: "Archive"),
        ], account: account)

        let inboxPage = await engine.cachedHeaders(
            for: testFolder(id: "INBOX"),
            account: account,
            pageToken: nil
        )
        let archivePage = await engine.cachedHeaders(
            for: testFolder(id: "Archive"),
            account: account,
            pageToken: nil
        )
        let metrics = await engine.metrics(for: account)

        XCTAssertEqual(inboxPage?.headers.map(\.id), ["INBOX:1"])
        XCTAssertEqual(archivePage?.headers.map(\.id), ["Archive:2"])
        XCTAssertEqual(metrics?.syncedFolderCount, 2)
    }

    func testStoreHeadersDoesNotOverwriteExistingSyncState() async throws {
        let store = InMemorySyncStore()
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let existingDate = Date(timeIntervalSince1970: 1_700_000_000)
        let existingState = FolderSyncState(
            folderID: "INBOX",
            accountID: account.id,
            uidValidity: 42,
            highestModSeq: 99,
            uidNext: 200,
            lastSyncDate: existingDate,
            syncTier: .condstore
        )
        try await store.setSyncState(existingState)

        await engine.storeHeaders([testHeader(uid: 1, folderID: "INBOX")], account: account)

        let loaded = await store.syncState(accountID: account.id, folderID: "INBOX")
        XCTAssertEqual(loaded, existingState)
    }

    func testStoreHeadersSkipsDirtyInMemoryRows() async throws {
        let store = InMemorySyncStore()
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let folder = testFolder(id: "INBOX")

        await engine.storeHeaders([
            testHeader(uid: 1, folderID: "INBOX", subject: "Original dirty subject"),
            testHeader(uid: 2, folderID: "INBOX", subject: "Original clean subject"),
        ], account: account)
        await engine.markDirty(messageIDs: ["INBOX:1"], account: account)

        await engine.storeHeaders([
            testHeader(uid: 1, folderID: "INBOX", subject: "Server dirty replacement"),
            testHeader(uid: 2, folderID: "INBOX", subject: "Server clean replacement"),
        ], account: account)

        let page = await engine.cachedHeaders(for: folder, account: account, pageToken: nil)
        let byID = Dictionary(uniqueKeysWithValues: (page?.headers ?? []).map { ($0.id, $0) })
        XCTAssertEqual(byID["INBOX:1"]?.subject, "Original dirty subject")
        XCTAssertEqual(byID["INBOX:2"]?.subject, "Server clean replacement")
    }

    func testStoreHeadersSkipsDirtySQLiteRows() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let folder = testFolder(id: "INBOX")

        await engine.storeHeaders([
            testHeader(uid: 1, folderID: "INBOX", subject: "Original dirty subject"),
            testHeader(uid: 2, folderID: "INBOX", subject: "Original clean subject"),
        ], account: account)
        await engine.markDirty(messageIDs: ["INBOX:1"], account: account)

        await engine.storeHeaders([
            testHeader(uid: 1, folderID: "INBOX", subject: "Server dirty replacement"),
            testHeader(uid: 2, folderID: "INBOX", subject: "Server clean replacement"),
        ], account: account)

        let page = await engine.cachedHeaders(for: folder, account: account, pageToken: nil)
        let byID = Dictionary(uniqueKeysWithValues: (page?.headers ?? []).map { ($0.id, $0) })
        XCTAssertEqual(byID["INBOX:1"]?.subject, "Original dirty subject")
        XCTAssertEqual(byID["INBOX:2"]?.subject, "Server clean replacement")
    }

    func testSQLiteDirtyHeaderUpsertDoesNotRefreshSearchRow() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let account = testAccount(id: "acc")
        try store.ensureAccount(id: account.id)
        try store.upsertHeaders([
            testHeader(uid: 1, folderID: "INBOX", subject: "Original dirty subject")
        ], accountID: account.id)
        try store.setDirty(true, messageIDs: ["INBOX:1"], accountID: account.id)

        try store.upsertHeaders([
            testHeader(uid: 1, folderID: "INBOX", subject: "Server dirty replacement")
        ], accountID: account.id)

        let headers = store.headers(accountID: account.id, folderID: "INBOX", limit: 10, offset: 0)
        let replacementHits = store.searchHeaders(
            SearchQuery(text: "Server dirty replacement", execution: .cacheOnly),
            accountID: account.id,
            limit: 10
        )
        let originalHits = store.searchHeaders(
            SearchQuery(text: "Original dirty subject", execution: .cacheOnly),
            accountID: account.id,
            limit: 10
        )

        XCTAssertEqual(headers.map(\.subject), ["Original dirty subject"])
        XCTAssertEqual(replacementHits, [])
        XCTAssertEqual(originalHits.map(\.id), ["INBOX:1"])
    }

    // MARK: SQLiteSyncStore round-trip

    func testSQLiteSyncStoreRoundTrip() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        XCTAssertEqual(store.currentSchemaVersion, 4)

        let accountID = "acc"
        try store.ensureAccount(id: accountID)

        // Round-trip folder sync state.
        let folderID = "INBOX"
        let state = FolderSyncState(
            folderID: folderID,
            accountID: accountID,
            uidValidity: 42,
            highestModSeq: 99,
            uidNext: 200,
            lastSyncDate: Date(timeIntervalSince1970: 1_700_000_000),
            syncTier: .condstore
        )
        try store.setSyncState(state)

        let loaded = store.syncState(accountID: accountID, folderID: folderID)
        XCTAssertEqual(loaded?.uidValidity, 42)
        XCTAssertEqual(loaded?.highestModSeq, 99)
        XCTAssertEqual(loaded?.uidNext, 200)
        XCTAssertEqual(loaded?.syncTier, .condstore)

        // Round-trip headers.
        let header = testHeader(uid: 5)
        try store.upsertHeaders([header], accountID: accountID)

        let fetched = store.headers(accountID: accountID, folderID: folderID, limit: 10, offset: 0)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, "INBOX:5")

        // Delete header.
        try store.deleteHeaders(messageIDs: ["INBOX:5"], accountID: accountID)
        let afterDelete = store.headers(
            accountID: accountID, folderID: folderID, limit: 10, offset: 0
        )
        XCTAssertEqual(afterDelete.count, 0)

        // Body round-trip.
        let raw = Data("raw bytes".utf8)
        try store.storeBody(raw, accountID: accountID, messageID: "INBOX:5")
        let loadedBody = store.body(accountID: accountID, messageID: "INBOX:5")
        XCTAssertEqual(loadedBody, raw)
    }

    func testSQLiteStoreRoundTripsGmailLabelsAndReadsLegacyRowsWithoutLabels() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        // A pre-labels row: `header_json` written before `labels` existed.
        try Self.createV1Database(
            at: url,
            accountID: "acc",
            header: testHeader(uid: 9, folderID: "INBOX"),
            body: Data("legacy".utf8)
        )

        let store = try SQLiteSyncStore(databaseURL: url)
        XCTAssertEqual(store.currentSchemaVersion, 4)

        let legacy = store.headers(accountID: "acc", folderID: "INBOX", limit: 10, offset: 0)
        XCTAssertEqual(legacy.map(\.id), ["INBOX:9"])
        XCTAssertEqual(legacy.first?.labels, [])

        var labelled = testHeader(uid: 10, folderID: "INBOX")
        labelled.labels = ["\\Inbox", "Work"]
        try store.upsertHeaders([labelled], accountID: "acc")

        let fetched = store.headers(accountID: "acc", folderID: "INBOX", limit: 10, offset: 0)
            .first { $0.id == "INBOX:10" }
        XCTAssertEqual(fetched?.labels, ["\\Inbox", "Work"])
    }

    func testSQLiteSearchUsesFTSForHeadersAndBodies() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let inbox = testFolder(id: "INBOX")

        try await engine.syncFolder(inbox, for: account) { _, _ in
            syncResult(headers: [
                testHeader(uid: 1, folderID: "INBOX", date: Date(timeIntervalSince1970: 3)),
                testHeader(uid: 2, folderID: "Archive", date: Date(timeIntervalSince1970: 2)),
                testHeader(uid: 3, folderID: "INBOX", date: Date(timeIntervalSince1970: 1)),
            ])
        }
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nNeedle appears only in the body".utf8),
            for: "INBOX:3",
            account: account
        )

        let headerMatches = await engine.search(SearchQuery(text: "Subject 1"), account: account)
        let bodyMatches = await engine.search(SearchQuery(text: "needle"), account: account)
        let folderMatches = await engine.search(
            SearchQuery(text: "Subject", folderID: "Archive"),
            account: account
        )

        XCTAssertEqual(headerMatches.map(\.id), ["INBOX:1"])
        XCTAssertEqual(bodyMatches.map(\.id), ["INBOX:3"])
        XCTAssertEqual(folderMatches.map(\.id), ["Archive:2"])
    }

    func testSQLiteBodyStoredBeforeHeaderBecomesSearchableWhenHeaderArrives() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")

        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nBody arrived before header needle".utf8),
            for: "INBOX:88",
            account: account
        )
        await engine.storeHeaders([
            testHeader(uid: 88, folderID: "INBOX", subject: "Late header"),
        ], account: account)

        let matches = await engine.search(SearchQuery(text: "before header needle"), account: account)
        let metrics = await engine.metrics(for: account)

        XCTAssertEqual(matches.map(\.id), ["INBOX:88"])
        XCTAssertEqual(metrics?.indexedHeaderCount, 1)
        XCTAssertEqual(metrics?.cachedBodyCount, 1)
        XCTAssertEqual(metrics?.searchDocumentCount, 1)
    }

    func testSQLiteHeaderMessageIDChangeRemovesStaleBodyAndSearchRows() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let accountID = "acc"
        try store.ensureAccount(id: accountID)
        let original = testHeader(uid: 7, folderID: "INBOX", subject: "Original stale subject")
        let replacement = MessageHeader(
            id: "Recovered:7",
            threadID: "thread-recovered-7",
            folderID: "INBOX",
            from: Correspondent(name: "Sender", email: "sender@example.com"),
            subject: "Replacement fresh subject",
            snippet: "",
            date: original.date,
            isRead: false,
            isFlagged: false
        )

        try store.upsertHeaders([original], accountID: accountID)
        try store.storeBody(
            Data("From: sender@example.com\r\n\r\nstale body needle".utf8),
            accountID: accountID,
            messageID: original.id
        )

        try store.upsertHeaders([replacement], accountID: accountID)

        let headers = store.headers(accountID: accountID, folderID: "INBOX", limit: 10, offset: 0)
        let staleMatches = store.searchHeaders(SearchQuery(text: "stale"), accountID: accountID, limit: 10)
        let freshMatches = store.searchHeaders(SearchQuery(text: "fresh"), accountID: accountID, limit: 10)
        let metrics = try XCTUnwrap(store.metrics(accountID: accountID))

        XCTAssertEqual(headers.map(\.id), ["Recovered:7"])
        XCTAssertEqual(staleMatches, [])
        XCTAssertEqual(freshMatches.map(\.id), ["Recovered:7"])
        XCTAssertNil(store.body(accountID: accountID, messageID: "INBOX:7"))
        XCTAssertEqual(metrics.indexedHeaderCount, 1)
        XCTAssertEqual(metrics.cachedBodyCount, 0)
        XCTAssertEqual(metrics.searchDocumentCount, 1)
    }

    func testSQLiteCondstoreRefreshPreservesBodySearchIndex() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let accountID = "acc"
        try store.ensureAccount(id: accountID)

        let initial = testHeader(uid: 1, folderID: "INBOX", isRead: false, subject: "CONDSTORE subject")
        try store.upsertHeaders([initial], accountID: accountID)
        try store.storeBody(
            Data("From: sender@example.com\r\n\r\nCondstore body needle".utf8),
            accountID: accountID,
            messageID: initial.id
        )

        // Simulate CONDSTORE refresh: same UID, only isRead flag changed.
        let refreshed = testHeader(uid: 1, folderID: "INBOX", isRead: true, subject: "CONDSTORE subject")
        try store.upsertHeaders([refreshed], accountID: accountID)

        let bodyMatches = store.searchHeaders(
            SearchQuery(text: "condstore body needle", execution: .cacheOnly),
            accountID: accountID,
            limit: 10
        )
        let metrics = try XCTUnwrap(store.metrics(accountID: accountID))

        XCTAssertEqual(bodyMatches.map(\.id), ["INBOX:1"])
        XCTAssertEqual(metrics.searchDocumentCount, 1)
    }

    func testSQLiteLocalIndexSurvivesEngineRestartForOfflineSearch() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
        }

        let account = testAccount(id: "acc")
        let originalEngine = try BrevSyncEngine(databaseURL: url)
        await originalEngine.storeHeaders([
            testHeader(
                uid: 42,
                folderID: "Archive",
                subject: "Restart durable header"
            ),
        ], account: account)
        await originalEngine.storeRawMessage(
            Data("From: sender@example.com\r\n\r\nDurable offline body needle".utf8),
            for: "Archive:42",
            account: account
        )

        let restartedEngine = try BrevSyncEngine(databaseURL: url)
        let headerMatches = await restartedEngine.search(
            SearchQuery(text: "durable header"),
            account: account
        )
        let bodyMatches = await restartedEngine.search(
            SearchQuery(text: "offline body needle"),
            account: account
        )
        let cachedArchive = await restartedEngine.cachedHeaders(
            for: testFolder(id: "Archive"),
            account: account,
            pageToken: nil
        )
        let metrics = await restartedEngine.metrics(for: account)

        XCTAssertEqual(headerMatches.map(\.id), ["Archive:42"])
        XCTAssertEqual(bodyMatches.map(\.id), ["Archive:42"])
        XCTAssertEqual(cachedArchive?.headers.map(\.id), ["Archive:42"])
        XCTAssertEqual(metrics?.indexedHeaderCount, 1)
        XCTAssertEqual(metrics?.cachedBodyCount, 1)
        XCTAssertEqual(metrics?.searchDocumentCount, 1)
        XCTAssertEqual(metrics?.syncedFolderCount, 1)
    }

    func testSQLiteSearchMatchesDownloadedBodyAcrossPunctuation() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let inbox = testFolder(id: "INBOX")

        try await engine.syncFolder(inbox, for: account) { _, _ in
            syncResult(headers: [
                testHeader(uid: 1, folderID: "INBOX", subject: "Receipt"),
            ])
        }
        await engine.storeBody(
            Data("Your invoice #123 is ready for download.".utf8),
            for: "INBOX:1",
            account: account
        )

        let matches = await engine.search(SearchQuery(text: "invoice 123"), account: account)

        XCTAssertEqual(matches.map(\.id), ["INBOX:1"])
    }

    func testSQLiteSearchMatchesDownloadedBodyAcrossDiacritics() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let inbox = testFolder(id: "INBOX")

        try await engine.syncFolder(inbox, for: account) { _, _ in
            syncResult(headers: [
                testHeader(uid: 1, folderID: "INBOX", subject: "Oppsummering"),
            ])
        }
        await engine.storeBody(
            Data("Content-Type: text/plain; charset=utf-8\r\n\r\nNeste møte er flyttet.".utf8),
            for: "INBOX:1",
            account: account
        )

        let matches = await engine.search(SearchQuery(text: "mote flyttet"), account: account)

        XCTAssertEqual(matches.map(\.id), ["INBOX:1"])
    }

    func testSQLiteSearchUsesNormalizedFTSCandidatesAcrossDiacritics() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let inbox = testFolder(id: "INBOX")

        try await engine.syncFolder(inbox, for: account) { _, _ in
            syncResult(headers: [
                testHeader(
                    uid: 1,
                    folderID: "INBOX",
                    date: Date(timeIntervalSince1970: 200),
                    subject: "Accentless body"
                ),
                testHeader(
                    uid: 2,
                    folderID: "INBOX",
                    date: Date(timeIntervalSince1970: 100),
                    subject: "Accented body"
                ),
            ])
        }
        await engine.storeBody(
            Data("Content-Type: text/plain; charset=utf-8\r\n\r\nmote alpha".utf8),
            for: "INBOX:1",
            account: account
        )
        await engine.storeBody(
            Data("Content-Type: text/plain; charset=utf-8\r\n\r\nmøte alpha".utf8),
            for: "INBOX:2",
            account: account
        )

        let matches = await engine.search(SearchQuery(text: "møte alpha"), account: account)

        XCTAssertEqual(matches.map(\.id), ["INBOX:1", "INBOX:2"])
    }

    func testSQLiteSearchIndexesDecodedMimeBodyText() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let inbox = testFolder(id: "INBOX")

        try await engine.syncFolder(inbox, for: account) { _, _ in
            syncResult(headers: [
                testHeader(uid: 1, folderID: "INBOX", subject: "Encoded"),
            ])
        }
        await engine.storeBody(
            Data("""
            Content-Type: text/plain; charset=utf-8
            Content-Transfer-Encoding: base64

            SGVsbG8sIHdvcmxkIQ==
            """.utf8),
            for: "INBOX:1",
            account: account
        )

        let matches = await engine.search(SearchQuery(text: "hello world"), account: account)

        XCTAssertEqual(matches.map(\.id), ["INBOX:1"])
    }

    func testSQLiteSearchIndexesNumericHTMLEntitiesFromDownloadedSource() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let inbox = testFolder(id: "INBOX")

        try await engine.syncFolder(inbox, for: account) { _, _ in
            syncResult(headers: [
                testHeader(uid: 1, folderID: "INBOX", subject: "HTML only"),
            ])
        }
        await engine.storeBody(
            Data("""
            Content-Type: text/html; charset=utf-8
            Content-Transfer-Encoding: 8bit

            <html><body>Kj&#XE6;re &#216;g&#229;rd invoice&nbsp;#123 &amp; ready</body></html>
            """.utf8),
            for: "INBOX:1",
            account: account
        )

        let matches = await engine.search(SearchQuery(text: "kjaere ogard invoice 123 ready"), account: account)

        XCTAssertEqual(matches.map(\.id), ["INBOX:1"])
    }

    func testSQLiteSearchIndexesLegacyEightBitBodyText() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let inbox = testFolder(id: "INBOX")

        try await engine.syncFolder(inbox, for: account) { _, _ in
            syncResult(headers: [
                testHeader(uid: 1, folderID: "INBOX", subject: "Legacy charset"),
            ])
        }
        let rawMessage = [
            "Content-Type: text/plain; charset=iso-8859-1",
            "Content-Transfer-Encoding: 8bit",
            "",
            "Kjære Henrik Øgård",
        ].joined(separator: "\r\n")
        let rawData = try XCTUnwrap(rawMessage.data(using: .isoLatin1))
        await engine.storeBody(rawData, for: "INBOX:1", account: account)

        let matches = await engine.search(SearchQuery(text: "kjaere ogard"), account: account)

        XCTAssertEqual(matches.map(\.id), ["INBOX:1"])
    }

    func testSQLiteSearchIndexesMultipartLegacyEightBitBodyText() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let inbox = testFolder(id: "INBOX")

        try await engine.syncFolder(inbox, for: account) { _, _ in
            syncResult(headers: [
                testHeader(uid: 1, folderID: "INBOX", subject: "Multipart legacy charset"),
            ])
        }
        await engine.storeBody(Self.multipartWindows1251Body(), for: "INBOX:1", account: account)

        let matches = await engine.search(SearchQuery(text: "привет"), account: account)

        XCTAssertEqual(matches.map(\.id), ["INBOX:1"])
    }

    func testSQLiteSearchIndexesAttachmentFilenamesFromDownloadedSource() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let inbox = testFolder(id: "INBOX")

        try await engine.syncFolder(inbox, for: account) { _, _ in
            syncResult(headers: [
                testHeader(uid: 1, folderID: "INBOX", subject: "Plain body", hasAttachments: true),
            ])
        }
        await engine.storeBody(
            Data("""
            Content-Type: multipart/mixed; boundary="brev-boundary"

            --brev-boundary
            Content-Type: text/plain; charset=utf-8

            Body text does not mention the file name.
            --brev-boundary
            Content-Type: application/pdf
            Content-Disposition: attachment; filename="Quarterly-Receipt.pdf"
            Content-Transfer-Encoding: base64

            SGVsbG8=
            --brev-boundary--
            """.utf8),
            for: "INBOX:1",
            account: account
        )

        let matches = await engine.search(SearchQuery(text: "quarterly receipt"), account: account)

        XCTAssertEqual(matches.map(\.id), ["INBOX:1"])
    }

    func testSQLiteSearchCombinesBodyTextWithMetadataPredicates() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let folder = testFolder(id: "INBOX")
        let targetDate = Date(timeIntervalSince1970: 1_779_960_600)
        let outsideRangeDate = Date(timeIntervalSince1970: 1_700_000_000)

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [
                testHeader(
                    uid: 1,
                    date: targetDate,
                    from: Correspondent(name: "Ava Ledger", email: "ava@example.com"),
                    hasAttachments: true
                ),
                testHeader(
                    uid: 2,
                    date: targetDate,
                    from: Correspondent(name: "Ava Ledger", email: "ava@example.com"),
                    hasAttachments: false
                ),
                testHeader(
                    uid: 3,
                    date: outsideRangeDate,
                    from: Correspondent(name: "Ava Ledger", email: "ava@example.com"),
                    hasAttachments: true
                ),
                testHeader(
                    uid: 4,
                    date: targetDate,
                    from: Correspondent(name: "Blake", email: "blake@example.com"),
                    hasAttachments: true
                ),
            ])
        }
        for uid in 1 ... 4 {
            await engine.storeBody(
                Data("From: sender@example.com\r\n\r\nquarterly roadmap needle".utf8),
                for: "INBOX:\(uid)",
                account: account
            )
        }

        let matches = await engine.search(
            SearchQuery(
                text: "roadmap needle",
                from: "ava",
                dateRange: targetDate ... targetDate,
                hasAttachments: true
            ),
            account: account
        )

        XCTAssertEqual(matches.map(\.id), ["INBOX:1"])
    }

    func testSQLiteSearchMatchesCcBccRecipientsAndStatePredicates() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let folder = testFolder(id: "INBOX")
        let targetDate = Date(timeIntervalSince1970: 1_780_790_400)
        let outsideDate = Date(timeIntervalSince1970: 1_700_000_000)
        let ccRecipient = Correspondent(name: "Casey Copy", email: "casey.copy@example.com")
        let bccRecipient = Correspondent(name: "Bailey Blind", email: "bailey.blind@example.com")

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [
                testHeader(
                    uid: 1,
                    date: targetDate,
                    isRead: false,
                    subject: "Predicate target",
                    cc: [ccRecipient],
                    isFlagged: true
                ),
                testHeader(
                    uid: 2,
                    date: targetDate,
                    isRead: false,
                    subject: "Predicate target",
                    bcc: [bccRecipient],
                    isFlagged: true
                ),
                testHeader(
                    uid: 3,
                    date: targetDate,
                    isRead: true,
                    subject: "Predicate read miss",
                    cc: [ccRecipient],
                    isFlagged: true
                ),
                testHeader(
                    uid: 4,
                    date: outsideDate,
                    isRead: false,
                    subject: "Predicate date miss",
                    bcc: [bccRecipient],
                    isFlagged: true
                ),
            ])
        }

        let ccMatches = await engine.search(
            SearchQuery(
                to: "casey.copy",
                dateRange: targetDate ... targetDate,
                isUnread: true,
                isFlagged: true
            ),
            account: account
        )
        let bccMatches = await engine.search(
            SearchQuery(
                to: "bailey.blind",
                dateRange: targetDate ... targetDate,
                isUnread: true,
                isFlagged: true
            ),
            account: account
        )

        XCTAssertEqual(ccMatches.map(\.id), ["INBOX:1"])
        XCTAssertEqual(bccMatches.map(\.id), ["INBOX:2"])
    }

    func testSQLiteSearchFiltersFullDownloadedCorpusBeforeLimitingResults() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let inbox = testFolder(id: "INBOX")
        let newerReadHeaders = (1 ... 260).map { uid in
            testHeader(
                uid: uid,
                folderID: "INBOX",
                date: Date(timeIntervalSince1970: TimeInterval(10000 - uid)),
                isRead: true,
                subject: "Shared needle \(uid)"
            )
        }
        let olderUnreadHeader = testHeader(
            uid: 999,
            folderID: "INBOX",
            date: Date(timeIntervalSince1970: 1),
            isRead: false,
            subject: "Shared needle old unread"
        )

        try await engine.syncFolder(inbox, for: account) { _, _ in
            syncResult(headers: newerReadHeaders + [olderUnreadHeader])
        }

        let metadataOnlyMatches = await engine.search(
            SearchQuery(isUnread: true),
            account: account,
            limit: 10
        )
        let textAndMetadataMatches = await engine.search(
            SearchQuery(text: "shared needle", isUnread: true),
            account: account,
            limit: 10
        )

        XCTAssertEqual(metadataOnlyMatches.map(\.id), ["INBOX:999"])
        XCTAssertEqual(textAndMetadataMatches.map(\.id), ["INBOX:999"])
    }

    func testSQLiteMetricsReportDatabaseAndRecordCounts() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
        }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let folder = testFolder(id: "INBOX")

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [
                testHeader(uid: 1, folderID: "INBOX"),
                testHeader(uid: 2, folderID: "INBOX"),
            ])
        }
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nCached source".utf8),
            for: "INBOX:2",
            account: account
        )

        let reportedMetrics = await engine.metrics(for: account)
        let metrics = try XCTUnwrap(reportedMetrics)

        XCTAssertGreaterThan(metrics.databaseBytes, 0)
        XCTAssertEqual(metrics.indexedHeaderCount, 2)
        XCTAssertEqual(metrics.cachedBodyCount, 1)
        XCTAssertEqual(metrics.searchDocumentCount, 2)
        XCTAssertEqual(metrics.syncedFolderCount, 1)
    }

    func testSQLiteMetricsIncludeDatabaseSidecarBytes() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        let walURL = URL(fileURLWithPath: url.path + "-wal")
        let shmURL = URL(fileURLWithPath: url.path + "-shm")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: walURL)
            try? FileManager.default.removeItem(at: shmURL)
        }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        try Data(repeating: 1, count: 1234).write(to: walURL)
        try Data(repeating: 2, count: 5678).write(to: shmURL)

        let reportedMetrics = await engine.metrics(for: account)
        let metrics = try XCTUnwrap(reportedMetrics)
        let mainBytes = try Self.allocatedSize(url)
        let walBytes = try Self.allocatedSize(walURL)
        let shmBytes = try Self.allocatedSize(shmURL)

        XCTAssertEqual(metrics.databaseBytes, mainBytes + walBytes + shmBytes)
    }

    func testSQLiteMigrationBackfillsSearchRows() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        try Self.createV1Database(
            at: url,
            accountID: "acc",
            header: testHeader(uid: 9, folderID: "INBOX"),
            body: Data("From: sender@example.com\r\n\r\nMigrated body needle".utf8)
        )

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")

        let subjectMatches = await engine.search(SearchQuery(text: "Subject 9"), account: account)
        let bodyMatches = await engine.search(SearchQuery(text: "needle"), account: account)

        XCTAssertEqual(store.currentSchemaVersion, 4)
        XCTAssertTrue(try Self.searchTableColumns(at: url).isSuperset(of: [
            "subject_normalized",
            "snippet_normalized",
            "participants_normalized",
            "body_normalized",
        ]))
        XCTAssertEqual(subjectMatches.map(\.id), ["INBOX:9"])
        XCTAssertEqual(bodyMatches.map(\.id), ["INBOX:9"])
        let originalBytes = await engine.cachedOriginalRawMessage(for: "INBOX:9", account: account)
        let legacyBytes = await engine.cachedRawMessage(for: "INBOX:9", account: account)
        XCTAssertNil(originalBytes)
        XCTAssertEqual(legacyBytes, Data("From: sender@example.com\r\n\r\nMigrated body needle".utf8))
    }

    func testSQLiteV2MigrationAddsNormalizedSearchColumns() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        try Self.createV2Database(
            at: url,
            accountID: "acc",
            header: testHeader(uid: 10, folderID: "INBOX", subject: "Møteplan"),
            body: Data("Content-Type: text/plain; charset=utf-8\r\n\r\nNeste møte er flyttet.".utf8)
        )

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")

        let headerMatches = await engine.search(SearchQuery(text: "moteplan"), account: account)
        let bodyMatches = await engine.search(SearchQuery(text: "mote flyttet"), account: account)

        XCTAssertEqual(store.currentSchemaVersion, 4)
        XCTAssertTrue(try Self.searchTableColumns(at: url).isSuperset(of: [
            "subject_normalized",
            "snippet_normalized",
            "participants_normalized",
            "body_normalized",
        ]))
        XCTAssertEqual(headerMatches.map(\.id), ["INBOX:10"])
        XCTAssertEqual(bodyMatches.map(\.id), ["INBOX:10"])
    }

    func testSQLiteDeleteHeadersRemovesBodyAndSearchRows() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let folder = testFolder(id: "INBOX")

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [testHeader(uid: 1, folderID: "INBOX")])
        }
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nDeleted body needle".utf8),
            for: "INBOX:1",
            account: account
        )

        try store.deleteHeaders(messageIDs: ["INBOX:1"], accountID: account.id)

        let searchResults = await engine.search(SearchQuery(text: "needle"), account: account)
        let metrics = await engine.metrics(for: account)

        XCTAssertTrue(searchResults.isEmpty)
        XCTAssertNil(store.body(accountID: account.id, messageID: "INBOX:1"))
        XCTAssertEqual(metrics?.indexedHeaderCount, 0)
        XCTAssertEqual(metrics?.cachedBodyCount, 0)
        XCTAssertEqual(metrics?.searchDocumentCount, 0)
    }

    func testSQLiteDeleteRawMessagesRemovesBodySearchButKeepsHeaderSearch() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let folder = testFolder(id: "INBOX")

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(headers: [testHeader(uid: 1, folderID: "INBOX", subject: "Retained subject")])
        }
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nretention body needle".utf8),
            for: "INBOX:1",
            account: account
        )

        await engine.deleteRawMessages(["INBOX:1"], account: account)

        let bodySearchResults = await engine.search(SearchQuery(text: "needle"), account: account)
        let subjectSearchResults = await engine.search(SearchQuery(text: "Retained subject"), account: account)
        let metrics = await engine.metrics(for: account)

        XCTAssertTrue(bodySearchResults.isEmpty)
        XCTAssertEqual(subjectSearchResults.map(\.id), ["INBOX:1"])
        XCTAssertNil(store.body(accountID: account.id, messageID: "INBOX:1"))
        XCTAssertEqual(metrics?.indexedHeaderCount, 1)
        XCTAssertEqual(metrics?.cachedBodyCount, 0)
        XCTAssertEqual(metrics?.searchDocumentCount, 1)
    }

    func testSQLiteDeleteRawMessagesInFolderRemovesBodyOnlyRowsAndKeepsHeaders() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let inbox = testFolder(id: "INBOX")
        let archive = testFolder(id: "Archive")

        try await engine.syncFolder(inbox, for: account) { _, _ in
            syncResult(headers: [testHeader(uid: 1, folderID: "INBOX", subject: "Retained inbox subject")])
        }
        try await engine.syncFolder(archive, for: account) { _, _ in
            syncResult(headers: [testHeader(uid: 1, folderID: "Archive", subject: "Archive subject")])
        }
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\ninbox body needle".utf8),
            for: "INBOX:1",
            account: account
        )
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nbody before header needle".utf8),
            for: "INBOX:99",
            account: account
        )
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\narchive body needle".utf8),
            for: "Archive:1",
            account: account
        )

        await engine.deleteRawMessages(inFolder: "INBOX", account: account)

        let inboxBodySearchResults = await engine.search(SearchQuery(text: "inbox body needle"), account: account)
        let inboxSubjectSearchResults = await engine.search(SearchQuery(text: "Retained inbox subject"), account: account)
        let archiveBodySearchResults = await engine.search(SearchQuery(text: "archive body needle"), account: account)
        let metrics = await engine.metrics(for: account)

        XCTAssertTrue(inboxBodySearchResults.isEmpty)
        XCTAssertEqual(inboxSubjectSearchResults.map(\.id), ["INBOX:1"])
        XCTAssertEqual(archiveBodySearchResults.map(\.id), ["Archive:1"])
        XCTAssertNil(store.body(accountID: account.id, messageID: "INBOX:1"))
        XCTAssertNil(store.body(accountID: account.id, messageID: "INBOX:99"))
        XCTAssertNotNil(store.body(accountID: account.id, messageID: "Archive:1"))
        XCTAssertEqual(metrics?.indexedHeaderCount, 2)
        XCTAssertEqual(metrics?.cachedBodyCount, 1)
        XCTAssertEqual(metrics?.searchDocumentCount, 2)
    }

    func testSQLiteDeleteRawMessagesInFolderDoesNotDeleteSimilarPrefixFolders() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let inbox = testFolder(id: "INBOX")
        let sibling = testFolder(id: "INBOX-Archive")

        try await engine.syncFolder(inbox, for: account) { _, _ in
            syncResult(headers: [testHeader(uid: 1, folderID: "INBOX", subject: "Inbox subject")])
        }
        try await engine.syncFolder(sibling, for: account) { _, _ in
            syncResult(headers: [testHeader(uid: 1, folderID: "INBOX-Archive", subject: "Sibling subject")])
        }
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\ninbox body needle".utf8),
            for: "INBOX:1",
            account: account
        )
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nsibling body needle".utf8),
            for: "INBOX-Archive:1",
            account: account
        )

        await engine.deleteRawMessages(inFolder: "INBOX", account: account)

        let inboxBodySearchResults = await engine.search(SearchQuery(text: "inbox body needle"), account: account)
        let siblingBodySearchResults = await engine.search(SearchQuery(text: "sibling body needle"), account: account)

        XCTAssertTrue(inboxBodySearchResults.isEmpty)
        XCTAssertEqual(siblingBodySearchResults.map(\.id), ["INBOX-Archive:1"])
        XCTAssertNil(store.body(accountID: account.id, messageID: "INBOX:1"))
        XCTAssertNotNil(store.body(accountID: account.id, messageID: "INBOX-Archive:1"))
    }

    func testSQLiteDeleteRawMessagesInFolderDoesNotDeleteColonNestedFolders() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let parent = testFolder(id: "Projects")
        let nested = testFolder(id: "Projects:2026")

        try await engine.syncFolder(parent, for: account) { _, _ in
            syncResult(headers: [testHeader(uid: 1, folderID: "Projects", subject: "Parent subject")])
        }
        try await engine.syncFolder(nested, for: account) { _, _ in
            syncResult(headers: [testHeader(uid: 1, folderID: "Projects:2026", subject: "Nested subject")])
        }
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nparent body needle".utf8),
            for: "Projects:1",
            account: account
        )
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nnested body needle".utf8),
            for: "Projects:2026:1",
            account: account
        )

        await engine.deleteRawMessages(inFolder: "Projects", account: account)

        let parentBodySearchResults = await engine.search(SearchQuery(text: "parent body needle"), account: account)
        let nestedBodySearchResults = await engine.search(SearchQuery(text: "nested body needle"), account: account)

        XCTAssertTrue(parentBodySearchResults.isEmpty)
        XCTAssertEqual(nestedBodySearchResults.map(\.id), ["Projects:2026:1"])
        XCTAssertNil(store.body(accountID: account.id, messageID: "Projects:1"))
        XCTAssertNotNil(store.body(accountID: account.id, messageID: "Projects:2026:1"))
    }

    func testSQLiteDeleteRawMessagesInFolderExceptKeepsPinnedAndEvictsOrphan() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount(id: "acc")
        let inbox = testFolder(id: "INBOX")
        let archive = testFolder(id: "Archive")

        try await engine.syncFolder(inbox, for: account) { _, _ in
            syncResult(headers: [
                testHeader(uid: 1, folderID: "INBOX", subject: "Pinned inbox subject"),
                testHeader(uid: 2, folderID: "INBOX", subject: "Evicted inbox subject"),
            ])
        }
        try await engine.syncFolder(archive, for: account) { _, _ in
            syncResult(headers: [testHeader(uid: 1, folderID: "Archive", subject: "Archive subject")])
        }
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\npinned body needle".utf8),
            for: "INBOX:1",
            account: account
        )
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\nevicted body needle".utf8),
            for: "INBOX:2",
            account: account
        )
        // Orphan: a cached body with no matching header row in the index.
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\norphan body needle".utf8),
            for: "INBOX:99",
            account: account
        )
        await engine.storeBody(
            Data("From: sender@example.com\r\n\r\narchive body needle".utf8),
            for: "Archive:1",
            account: account
        )

        await engine.deleteRawMessages(inFolder: "INBOX", except: ["INBOX:1"], account: account)

        // Pinned body survives; the headed non-pinned body and the orphan body
        // are both reclaimed; other folders are untouched.
        XCTAssertNotNil(store.body(accountID: account.id, messageID: "INBOX:1"))
        XCTAssertNil(store.body(accountID: account.id, messageID: "INBOX:2"))
        XCTAssertNil(store.body(accountID: account.id, messageID: "INBOX:99"))
        XCTAssertNotNil(store.body(accountID: account.id, messageID: "Archive:1"))

        // Search reflects body removal: the pinned body is still searchable, the
        // evicted body is not, and header rows remain for both.
        let pinnedBodyResults = await engine.search(SearchQuery(text: "pinned body needle"), account: account)
        let evictedBodyResults = await engine.search(SearchQuery(text: "evicted body needle"), account: account)
        let pinnedSubjectResults = await engine.search(SearchQuery(text: "Pinned inbox subject"), account: account)
        let evictedSubjectResults = await engine.search(SearchQuery(text: "Evicted inbox subject"), account: account)
        XCTAssertEqual(pinnedBodyResults.map(\.id), ["INBOX:1"])
        XCTAssertTrue(evictedBodyResults.isEmpty)
        XCTAssertEqual(pinnedSubjectResults.map(\.id), ["INBOX:1"])
        XCTAssertEqual(evictedSubjectResults.map(\.id), ["INBOX:2"])
    }

    func testSQLiteClearAccountRemovesLocalIndexRowsForOnlyThatAccount() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let accountA = testAccount(id: "acc-a")
        let accountB = testAccount(id: "acc-b")
        let folder = testFolder(id: "INBOX")

        for account in [accountA, accountB] {
            try await engine.syncFolder(folder, for: account) { _, _ in
                syncResult(headers: [
                    testHeader(uid: 1, folderID: "INBOX", subject: "Reset subject \(account.id)")
                ])
            }
            await engine.storeBody(
                Data("From: sender@example.com\r\n\r\nreset body needle \(account.id)".utf8),
                for: "INBOX:1",
                account: account
            )
        }

        await engine.clearAccount(accountA)

        let rawAccountAMetrics = await engine.metrics(for: accountA)
        let rawAccountBMetrics = await engine.metrics(for: accountB)
        let accountASyncState = await engine.syncState(for: folder, account: accountA)
        let accountABody = await engine.cachedBody(for: "INBOX:1", account: accountA)
        let accountASearchResults = await engine.search(SearchQuery(text: "reset"), account: accountA)
        let accountBSyncState = await engine.syncState(for: folder, account: accountB)
        let accountBBody = await engine.cachedBody(for: "INBOX:1", account: accountB)
        let accountBSearchResultIDs = await engine.search(SearchQuery(text: "reset"), account: accountB).map(\.id)
        let accountAMetrics = try XCTUnwrap(rawAccountAMetrics)
        let accountBMetrics = try XCTUnwrap(rawAccountBMetrics)

        XCTAssertNil(accountASyncState)
        XCTAssertNil(accountABody)
        XCTAssertEqual(accountASearchResults, [])
        XCTAssertEqual(accountAMetrics.indexedHeaderCount, 0)
        XCTAssertEqual(accountAMetrics.cachedBodyCount, 0)
        XCTAssertEqual(accountAMetrics.searchDocumentCount, 0)
        XCTAssertEqual(accountAMetrics.syncedFolderCount, 0)
        XCTAssertNotNil(accountBSyncState)
        XCTAssertNotNil(accountBBody)
        XCTAssertEqual(accountBSearchResultIDs, ["INBOX:1"])
        XCTAssertEqual(accountBMetrics.indexedHeaderCount, 1)
        XCTAssertEqual(accountBMetrics.cachedBodyCount, 1)
        XCTAssertEqual(accountBMetrics.searchDocumentCount, 1)
        XCTAssertEqual(accountBMetrics.syncedFolderCount, 1)
    }

    /// A delete/dirty batch larger than SQLite's bound-variable limit
    /// (`SQLITE_MAX_VARIABLE_NUMBER`, 999 on older builds) must be chunked, not
    /// crammed into a single `IN (?, …)` that overflows `prepare` and aborts the
    /// whole sync write.
    func testLargeMessageIDBatchChunksWithoutOverflow() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let accountID = "acc"
        try store.ensureAccount(id: accountID)

        let headers = (1 ... 1500).map { testHeader(uid: $0) }
        try store.upsertHeaders(headers, accountID: accountID)
        let ids = headers.map(\.id)

        // setDirty over the whole batch succeeds and marks every row.
        try store.setDirty(true, messageIDs: ids, accountID: accountID)
        XCTAssertEqual(Set(store.dirtyMessageIDs(accountID: accountID)), Set(ids))

        // deleteHeaders over the whole batch succeeds and removes every row.
        try store.deleteHeaders(messageIDs: ids, accountID: accountID)
        XCTAssertEqual(
            store.headers(accountID: accountID, folderID: "INBOX", limit: 2000, offset: 0).count,
            0
        )
    }

    // MARK: SQLite large CONDSTORE mod-seq round-trip

    /// A HIGHESTMODSEQ above 2^31 must survive the SQLite round-trip intact.
    /// Storing it through a 32-bit `Int` would truncate; `UInt64` keeps all bits.
    func testSQLiteLargeModSeqRoundTrip() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let accountID = "acc"
        try store.ensureAccount(id: accountID)

        let bigModSeq: UInt64 = 715_194_045_007
        let state = FolderSyncState(
            folderID: "INBOX",
            accountID: accountID,
            uidValidity: 4_000_000_000, // exceeds Int32, valid UIDVALIDITY
            highestModSeq: bigModSeq,
            uidNext: 200,
            syncTier: .condstore
        )
        try store.setSyncState(state)

        let loaded = store.syncState(accountID: accountID, folderID: "INBOX")
        XCTAssertEqual(loaded?.highestModSeq, bigModSeq, "Large modseq must round-trip without truncation")
        XCTAssertEqual(loaded?.uidValidity, 4_000_000_000, "Large UIDVALIDITY must round-trip without truncation")
    }

    // MARK: SQLite atomic clearFolder

    /// `clearHeaders` keeps the folder sync state but removes local header/body/search rows.
    func testSQLiteClearHeadersRemovesBodiesAndSearchRowsButKeepsState() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let accountID = "acc"
        try store.ensureAccount(id: accountID)
        try store.setSyncState(FolderSyncState(
            folderID: "INBOX",
            accountID: accountID,
            uidValidity: 1,
            highestModSeq: 5,
            uidNext: 10,
            syncTier: .condstore
        ))
        let header = testHeader(uid: 1, subject: "Clearable subject")
        try store.upsertHeaders([header], accountID: accountID)
        try store.storeBody(
            Data("From: sender@example.com\r\n\r\nclearable body needle".utf8),
            accountID: accountID,
            messageID: header.id
        )
        try store.storeBody(
            Data("From: sender@example.com\r\n\r\nbody only needle".utf8),
            accountID: accountID,
            messageID: "INBOX:42"
        )

        try store.clearHeaders(accountID: accountID, folderID: "INBOX")

        XCTAssertNotNil(store.syncState(accountID: accountID, folderID: "INBOX"))
        XCTAssertEqual(store.headers(accountID: accountID, folderID: "INBOX", limit: 10, offset: 0), [])
        XCTAssertNil(store.body(accountID: accountID, messageID: header.id))
        XCTAssertEqual(
            store.searchHeaders(SearchQuery(text: "clearable"), accountID: accountID, limit: 10),
            []
        )
        let metrics = try XCTUnwrap(store.metrics(accountID: accountID))
        XCTAssertEqual(metrics.indexedHeaderCount, 0)
        XCTAssertEqual(metrics.cachedBodyCount, 0)
        XCTAssertEqual(metrics.searchDocumentCount, 0)
        XCTAssertEqual(metrics.syncedFolderCount, 1)
    }

    func testSQLiteClearHeadersDoesNotDeleteColonNestedBodyOnlyRows() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let accountID = "acc"
        try store.ensureAccount(id: accountID)
        try store.storeBody(
            Data("From: sender@example.com\r\n\r\nparent body only".utf8),
            accountID: accountID,
            messageID: "Projects:42"
        )
        try store.storeBody(
            Data("From: sender@example.com\r\n\r\nnested body only".utf8),
            accountID: accountID,
            messageID: "Projects:2026:42"
        )

        try store.clearHeaders(accountID: accountID, folderID: "Projects")

        XCTAssertNil(store.body(accountID: accountID, messageID: "Projects:42"))
        XCTAssertNotNil(store.body(accountID: accountID, messageID: "Projects:2026:42"))
        let metrics = try XCTUnwrap(store.metrics(accountID: accountID))
        XCTAssertEqual(metrics.cachedBodyCount, 1)
    }

    /// `clearFolder` must delete both headers and sync state for the folder.
    func testSQLiteClearFolderRemovesHeadersAndState() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let accountID = "acc"
        try store.ensureAccount(id: accountID)

        let state = FolderSyncState(
            folderID: "INBOX",
            accountID: accountID,
            uidValidity: 1,
            highestModSeq: 5,
            uidNext: 10,
            syncTier: .condstore
        )
        try store.setSyncState(state)
        try store.upsertHeaders([testHeader(uid: 1), testHeader(uid: 2)], accountID: accountID)

        try store.clearFolder(accountID: accountID, folderID: "INBOX")

        XCTAssertNil(
            store.syncState(accountID: accountID, folderID: "INBOX"),
            "clearFolder must delete the sync state row"
        )
        XCTAssertEqual(
            store.headers(accountID: accountID, folderID: "INBOX", limit: 10, offset: 0).count,
            0,
            "clearFolder must delete all headers"
        )
    }

    // MARK: invalidate(uidValidityChanged) clears via clearFolder on SQLite

    /// Exercises the full engine + SQLite invalidation path: a UIDVALIDITY change
    /// must atomically clear headers and sync state.
    func testSQLiteUIDValidityChangeTriggersInvalidation() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteSyncStore(databaseURL: url)
        let engine = BrevSyncEngine(store: store)
        let account = testAccount()
        let folder = testFolder()

        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(uidValidity: 1, headers: [testHeader(uid: 1), testHeader(uid: 2)])
        }

        // UIDVALIDITY flips — the engine must clear and re-seed from the new sync.
        try await engine.syncFolder(folder, for: account) { _, _ in
            syncResult(uidValidity: 2, headers: [testHeader(uid: 10)])
        }

        let cached = await engine.cachedHeaders(for: folder, account: account, pageToken: nil)
        XCTAssertEqual(cached?.headers.count, 1, "Stale headers must be cleared on UIDVALIDITY change")
        XCTAssertEqual(cached?.headers.first?.id, "INBOX:10")

        let state = await engine.syncState(for: folder, account: account)
        XCTAssertEqual(state?.uidValidity, 2, "Sync state must reflect the new UIDVALIDITY")
    }

    private static func createV1Database(
        at url: URL,
        accountID: String,
        header: MessageHeader,
        body: Data
    ) throws {
        var db: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil),
            SQLITE_OK
        )
        defer { sqlite3_close(db) }

        try execSQL(db, """
            CREATE TABLE accounts (
                id         TEXT PRIMARY KEY,
                created_at INTEGER NOT NULL
            );
            CREATE TABLE folder_sync_state (
                account_id      TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                folder_id       TEXT NOT NULL,
                uid_validity    INTEGER,
                highest_mod_seq INTEGER,
                uid_next        INTEGER,
                last_sync_date  INTEGER,
                sync_tier       INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (account_id, folder_id)
            );
            CREATE TABLE message_headers (
                account_id  TEXT    NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                folder_id   TEXT    NOT NULL,
                uid         INTEGER NOT NULL,
                message_id  TEXT    NOT NULL,
                date_ts     INTEGER NOT NULL,
                is_dirty    INTEGER NOT NULL DEFAULT 0,
                header_json BLOB    NOT NULL,
                PRIMARY KEY (account_id, folder_id, uid)
            );
            CREATE TABLE message_bodies (
                account_id  TEXT    NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                message_id  TEXT    NOT NULL,
                raw_source  BLOB    NOT NULL,
                fetched_at  INTEGER NOT NULL,
                size_bytes  INTEGER NOT NULL,
                PRIMARY KEY (account_id, message_id)
            );
            INSERT INTO accounts (id, created_at) VALUES ('\(accountID)', 0);
            PRAGMA user_version = 1;
        """)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let headerData = try encoder.encode(header)
        try insertV1Header(db, accountID: accountID, header: header, data: headerData)
        try insertV1Body(db, accountID: accountID, messageID: header.id, data: body)
    }

    private static func multipartWindows1251Body() -> Data {
        var data = Data("""
        Content-Type: multipart/mixed; boundary="brev-boundary"

        --brev-boundary
        Content-Type: text/plain; charset=windows-1251
        Content-Transfer-Encoding: 8bit

        """.utf8)
        data.append(contentsOf: [0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2])
        data.append(Data("""

        --brev-boundary--
        """.utf8))
        return data
    }

    private static func createV2Database(
        at url: URL,
        accountID: String,
        header: MessageHeader,
        body: Data
    ) throws {
        try createV1Database(at: url, accountID: accountID, header: header, body: body)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        defer { sqlite3_close(db) }
        try execSQL(db, """
            CREATE VIRTUAL TABLE message_search USING fts5(
                account_id UNINDEXED,
                message_id UNINDEXED,
                folder_id UNINDEXED,
                subject,
                snippet,
                participants,
                body
            );
            PRAGMA user_version = 2;
        """)
        try insertV2SearchRow(db, accountID: accountID, header: header)
    }

    private static func searchTableColumns(at url: URL) throws -> Set<String> {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "PRAGMA table_info(message_search);", -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        var columns = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1) {
                columns.insert(String(cString: name))
            }
        }
        return columns
    }

    private static func insertV1Header(
        _ db: OpaquePointer?,
        accountID: String,
        header: MessageHeader,
        data: Data
    ) throws {
        var stmt: OpaquePointer?
        let sql = """
            INSERT INTO message_headers
                (account_id, folder_id, uid, message_id, date_ts, header_json)
            VALUES (?, ?, ?, ?, ?, ?);
        """
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, accountID, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, header.folderID, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 3, Int64(Self.uid(from: header.id)))
        sqlite3_bind_text(stmt, 4, header.id, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 5, Int64(header.date.timeIntervalSince1970))
        _ = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(stmt, 6, bytes.baseAddress, Int32(data.count), sqliteTransient)
        }
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE)
    }

    private static func insertV1Body(
        _ db: OpaquePointer?,
        accountID: String,
        messageID: MessageHeader.ID,
        data: Data
    ) throws {
        var stmt: OpaquePointer?
        let sql = """
            INSERT INTO message_bodies (account_id, message_id, raw_source, fetched_at, size_bytes)
            VALUES (?, ?, ?, 0, ?);
        """
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, accountID, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, messageID, -1, sqliteTransient)
        _ = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(stmt, 3, bytes.baseAddress, Int32(data.count), sqliteTransient)
        }
        sqlite3_bind_int64(stmt, 4, Int64(data.count))
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE)
    }

    private static func insertV2SearchRow(
        _ db: OpaquePointer?,
        accountID: String,
        header: MessageHeader
    ) throws {
        var stmt: OpaquePointer?
        let sql = """
            INSERT INTO message_search
                (account_id, message_id, folder_id, subject, snippet, participants, body)
            VALUES (?, ?, ?, ?, ?, '', '');
        """
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, accountID, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, header.id, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 3, header.folderID, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 4, header.subject, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 5, header.snippet, -1, sqliteTransient)
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE)
    }

    private static func execSQL(_ db: OpaquePointer?, _ sql: String) throws {
        var errPtr: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errPtr)
        if result != SQLITE_OK {
            let message = errPtr.map { String(cString: $0) } ?? "unknown sqlite error"
            sqlite3_free(errPtr)
            XCTFail(message)
        }
    }

    private static func allocatedSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
    }

    private static func uid(from messageID: MessageHeader.ID) -> Int {
        guard let sep = messageID.lastIndex(of: ":"),
              let uid = Int(String(messageID[messageID.index(after: sep)...]))
        else { return 0 }
        return uid
    }
}
