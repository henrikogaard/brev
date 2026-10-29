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

@Suite("IMAP selective cache regressions")
struct IMAPSelectiveCacheRegressionTests {
    @Test("indexed date repair starts only when the returned page has a sentinel", arguments: [false, true])
    func pageGatedDateRepair(invalidOnPage: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brev-page-repair-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = try BrevSyncEngine(databaseURL: root.appendingPathComponent("index.sqlite"))
        let validHeaders = (2 ... 51).map { uid in
            MessageHeader(
                id: "INBOX:\(uid)",
                threadID: "t\(uid)",
                folderID: "INBOX",
                from: Correspondent(email: "a@example.test"),
                subject: "Valid",
                snippet: "",
                date: Date(timeIntervalSince1970: -1)
            )
        }
        let valid = try #require(validHeaders.first)
        let invalid = MessageHeader(
            id: "INBOX:1",
            threadID: "t1",
            folderID: "INBOX",
            from: Correspondent(email: "a@example.test"),
            subject: "Invalid",
            snippet: "",
            date: .distantPast
        )
        try await engine.storeIMAPPage(IMAPHeaderPageWrite(folderID: "INBOX", pageToken: nil, headers: validHeaders,
                                                           uidValidity: 777, highestModSeq: nil, nextPageToken: "before:2"),
                                       account: Self.account)
        try await engine.storeIMAPPage(IMAPHeaderPageWrite(folderID: "INBOX", pageToken: "before:2", headers: [invalid],
                                                           uidValidity: 777, highestModSeq: nil, nextPageToken: nil),
                                       account: Self.account)
        let sources = InMemoryIMAPMessageSourceCache()
        await sources.setSource(IMAPMessageSource(uid: 1, rawMessage: "Date: Mon, 8 Jun 2026 08:51:02 +0000\r\n\r\nSynthetic"),
                                accountID: Self.account.id, messageID: invalid.id)
        let backend = backend(index: engine, legacy: LegacyIMAPMailboxHeaderCache(rootDirectory: root), sourceCache: sources)
        let firstPage = try await backend.messages(in: Self.folders[0], pageToken: nil)
        #expect(Set(firstPage.headers.map(\.id)) == Set(validHeaders.map(\.id)))
        if invalidOnPage {
            let nextToken = try #require(firstPage.nextPageToken)
            let page = try await backend.messages(in: Self.folders[0], pageToken: nextToken)
            #expect(page.headers.map(\.id) == [invalid.id])
            for _ in 0 ..< 100 {
                if try await engine.imapHeaders(ids: [invalid.id], folderID: "INBOX", account: Self.account).first?
                    .date != .distantPast { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(try await engine.imapHeaders(ids: [invalid.id], folderID: "INBOX", account: Self.account).first?
                .date == ISO8601DateFormatter().date(from: "2026-06-08T08:51:02Z"))
        } else {
            try await Task.sleep(for: .milliseconds(200))
            #expect(try await engine.imapHeaders(ids: [invalid.id], folderID: "INBOX", account: Self.account).first?
                .date == .distantPast)
            #expect(try await engine.imapHeaders(ids: [valid.id], folderID: "INBOX", account: Self.account).first?.date == valid
                .date)
        }
        await backend.disconnect()
    }

    @Test("cache-only search migrates unopened legacy folders offline", arguments: ["account", "folderID", "folderIDs"])
    func unopenedFolderSearch(scope: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brev-unopened-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = try BrevSyncEngine(databaseURL: root.appendingPathComponent("index.sqlite"))
        let legacy = try seedLegacy(root: root)
        let backend = backend(index: engine, legacy: legacy)
        let scoped = scope != "account"
        var query = SearchQuery(text: "Needle", folderID: scope == "folderID" ? "Archive" : nil, execution: .cacheOnly)
        if scope == "folderIDs" { query.folderIDs = ["Archive"] }
        let results = try await backend.search(query)
        #expect(Set(results.map(\.id)) == Set(scoped ? ["Archive:1"] : ["INBOX:1", "Archive:1"]))
        #expect(await legacy.snapshot(accountID: Self.account.id, folderID: "Archive") == nil)
        if scoped {
            #expect(await legacy.snapshot(accountID: Self.account.id, folderID: "INBOX") != nil)
        }
        #expect(await engine.metrics(for: Self.account)?.indexedHeaderCount == (scoped ? 1 : 2))
    }

    @Test("saved-view enumeration migrates its unopened folder without a connection")
    func unopenedFolderEnumeration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brev-unopened-view-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = try BrevSyncEngine(databaseURL: root.appendingPathComponent("index.sqlite"))
        let legacy = try seedLegacy(root: root)
        let backend = backend(index: engine, legacy: legacy)
        let results = try await backend.cachedMessageHeaders(in: Self.folders[1], sourceID: Self.source)
        #expect(results.map(\.id) == ["Archive:1"])
        #expect(await engine.metrics(for: Self.account)?.indexedHeaderCount == 1)
        #expect(await legacy.snapshot(accountID: Self.account.id, folderID: "INBOX") != nil)
    }

    private func seedLegacy(root: URL) throws -> LegacyIMAPMailboxHeaderCache {
        let directory = root.appendingPathComponent(MailCacheKeyNaming.hexKey(Self.account.id))
            .appendingPathComponent("headers")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for folder in Self.folders {
            let header = MessageHeader(id: "\(folder.id):1", threadID: "t", folderID: folder.id,
                                       from: Correspondent(email: "sender@example.test"), subject: "Needle", snippet: "",
                                       date: Date(timeIntervalSince1970: 100))
            let snapshot = IMAPMailboxHeaderCacheSnapshot(headers: [header], uidValidity: 777)
            try JSONEncoder().encode(snapshot)
                .write(to: directory.appendingPathComponent("\(MailCacheKeyNaming.hexKey(folder.id)).json"))
        }
        return LegacyIMAPMailboxHeaderCache(rootDirectory: root)
    }

    private static let account = BrevAccount(id: "synthetic", displayName: "Synthetic", emailAddress: "reader@example.test")
    private static let source = MailSourceID(accountID: account.id, mailboxID: account.id)
    private static let folders = [
        Folder(id: "INBOX", name: "Inbox", role: .inbox),
        Folder(id: "Archive", name: "Archive", role: .archive)
    ]

    private func backend(index: BrevSyncEngine, legacy: LegacyIMAPMailboxHeaderCache,
                         sourceCache: (any IMAPMessageSourceCache)? = nil) -> IMAPSMTPBackend {
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
            ),
            credentialID: Self.account.id
        )
        let credential = MailAccountCredential(
            incomingUsername: "synthetic",
            outgoingUsername: "synthetic",
            secret: "fixture",
            authentication: .password
        )
        let folders =
            InMemoryIMAPFolderSnapshotCache(snapshotsByAccount: [Self.account.id: IMAPFolderCacheSnapshot(folders: Self.folders)])
        return IMAPSMTPBackend(account: Self.account, configuration: configuration, credential: credential,
                               listFolders: { _, _ in
                                   Issue.record("Cache-only reads must not connect")
                                   return []
                               }, folderCache: folders, headerCache: legacy, sourceCache: sourceCache, localSearchIndex: index)
    }
}
