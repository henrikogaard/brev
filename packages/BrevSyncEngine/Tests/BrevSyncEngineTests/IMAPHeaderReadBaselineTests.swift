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
import Testing

/// ADR-0087 baseline: fresh store instances, not a purged OS page cache or app launch.
@Suite("IMAP header read baselines", .serialized)
struct IMAPHeaderReadBaselineTests {
    private static let accountID = "imap-baseline"
    private static let folderID = "INBOX"
    private static let pageSize = 50
    private static let sampleCount = 4

    @Test("reopened JSON and SQLite return the same first 50 headers", arguments: [10000, 50000])
    func coldHeaderReads(rowCount: Int) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-header-read-baseline-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await Self.seed(rowCount: rowCount, root: root)
        var jsonDurations: [Duration] = []
        var sqliteOpenDurations: [Duration] = []
        var sqliteQueryDurations: [Duration] = []
        var sqliteTotalDurations: [Duration] = []
        var jsonThreadDurations: [Duration] = []
        var sqliteThreadDurations: [Duration] = []
        var backendDurations: [Duration] = []

        for sample in 0 ..< Self.sampleCount {
            let json: JSONRead
            let sqlite: SQLiteRead
            if sample.isMultiple(of: 2) {
                json = try await Self.readJSON(fixture: fixture)
                sqlite = try await Self.readSQLite(fixture: fixture)
            } else {
                sqlite = try await Self.readSQLite(fixture: fixture)
                json = try await Self.readJSON(fixture: fixture)
            }
            #expect(json.page == fixture.expectedFirstPage)
            #expect(sqlite.page == fixture.expectedFirstPage)
            #expect(json.page == sqlite.page)
            #expect(sqlite.nextPage == fixture.expectedSecondPage)
            #expect(Set(sqlite.page.map(\.id)).isDisjoint(with: sqlite.nextPage.map(\.id)))

            jsonDurations.append(json.duration)
            sqliteOpenDurations.append(sqlite.openDuration)
            sqliteQueryDurations.append(sqlite.queryDuration)
            sqliteTotalDurations.append(sqlite.totalDuration)
            jsonThreadDurations.append(json.threadDuration)
            sqliteThreadDurations.append(sqlite.threadDuration)
            try await backendDurations.append(Self.readBackend(fixture: fixture))
            let order = sample.isMultiple(of: 2) ? "json-first" : "sqlite-first"
            print(
                "PERF header-read.sample rows=\(rowCount) page_size=\(Self.pageSize) sample=\(sample + 1) order=\(order) cold=store-reopen os_cache=uncontrolled build=\(Self.buildMode) json_read_ms=\(Self.ms(json.duration)) sqlite_open_ms=\(Self.ms(sqlite.openDuration)) sqlite_query_ms=\(Self.ms(sqlite.queryDuration)) sqlite_total_ms=\(Self.ms(sqlite.totalDuration)) json_threads_ms=\(Self.ms(json.threadDuration)) sqlite_threads_ms=\(Self.ms(sqlite.threadDuration)) backend_total_ms=\(Self.ms(backendDurations.last!))"
            )
        }

        print(
            "PERF header-read.summary rows=\(rowCount) page_size=\(Self.pageSize) samples=\(Self.sampleCount) fixture_json_bytes=\(fixture.jsonBytes) cold=store-reopen os_cache=uncontrolled build=\(Self.buildMode) json_read_median_ms=\(Self.ms(Self.median(jsonDurations))) sqlite_open_median_ms=\(Self.ms(Self.median(sqliteOpenDurations))) sqlite_query_median_ms=\(Self.ms(Self.median(sqliteQueryDurations))) sqlite_total_median_ms=\(Self.ms(Self.median(sqliteTotalDurations))) json_threads_median_ms=\(Self.ms(Self.median(jsonThreadDurations))) sqlite_threads_median_ms=\(Self.ms(Self.median(sqliteThreadDurations))) backend_total_median_ms=\(Self.ms(Self.median(backendDurations)))"
        )
        try await Self.flagPersistence(fixture: fixture)
    }

    private struct Fixture {
        let rowCount: Int
        let cacheRoot: URL
        let databaseURL: URL
        let jsonBytes: Int
        let expectedFirstPage: [MessageHeader]
        let expectedSecondPage: [MessageHeader]
        let expectedThreadedPage: [MessageHeader]

        var nextPageToken: String { "before:\(rowCount - IMAPHeaderReadBaselineTests.pageSize + 1)" }
    }

    private struct JSONRead {
        let page: [MessageHeader]
        let duration: Duration
        let threadDuration: Duration
    }

    private struct SQLiteRead {
        let page: [MessageHeader]
        let nextPage: [MessageHeader]
        let openDuration: Duration
        let queryDuration: Duration
        let totalDuration: Duration
        let threadDuration: Duration
    }

    /// Seed work and the full source array leave scope before any read is timed.
    private static func seed(rowCount: Int, root: URL) async throws -> Fixture {
        let headers = (1 ... rowCount).reversed().map { uid in
            MessageHeader(
                id: "\(folderID):\(uid)",
                threadID: "<baseline-\(uid)@example.test>",
                folderID: folderID,
                from: Correspondent(email: "sender@example.test"),
                to: [Correspondent(email: "reader@example.test")],
                subject: "Synthetic subject \(uid)",
                snippet: "Synthetic preview",
                date: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + uid * 60)),
                isRead: uid.isMultiple(of: 2),
                isFlagged: uid.isMultiple(of: 7),
                messageID: "<baseline-\(uid)@example.test>",
                inReplyTo: uid > rowCount - pageSize ? "<baseline-\(uid - rowCount + pageSize)@example.test>" : nil,
                references: uid > rowCount - pageSize ? ["<baseline-\(uid - rowCount + pageSize)@example.test>"] : []
            )
        }
        let firstPage = Array(headers.prefix(pageSize))
        let snapshot = IMAPMailboxHeaderCacheSnapshot(
            headers: headers,
            uidValidity: 777,
            highestModSeq: 888,
            nextPageToken: "before:\(rowCount - pageSize + 1)",
            firstPageHeaderIDs: Set(firstPage.map(\.id))
        )
        let cacheRoot = root.appendingPathComponent("legacy", isDirectory: true)
        let legacyDirectory = cacheRoot.appendingPathComponent(MailCacheKeyNaming.hexKey(accountID))
            .appendingPathComponent("headers", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(
            to: legacyDirectory.appendingPathComponent("\(MailCacheKeyNaming.hexKey(folderID)).json"), options: .atomic
        )
        let databaseURL = root.appendingPathComponent("headers.sqlite")
        do {
            let store = try SQLiteSyncStore(databaseURL: databaseURL)
            try store.ensureAccount(id: accountID)
            try store.upsertHeaders(headers, accountID: accountID)
            try store.storeIMAPPage(IMAPHeaderPageWrite(folderID: folderID, pageToken: nil, headers: firstPage,
                                                        uidValidity: 777, highestModSeq: 888,
                                                        nextPageToken: snapshot.nextPageToken), accountID: accountID)
            try store.storeIMAPSnapshot(IMAPMailboxHeaderCacheSnapshot(headers: []), accountID: accountID,
                                        folderID: folderID, importingLegacy: true)
        }
        return try Fixture(
            rowCount: rowCount,
            cacheRoot: cacheRoot,
            databaseURL: databaseURL,
            jsonBytes: JSONEncoder().encode(snapshot).count,
            expectedFirstPage: firstPage,
            expectedSecondPage: Array(headers.dropFirst(pageSize).prefix(pageSize)),
            expectedThreadedPage: Array(MessageThreadResolver.resolved(headers).prefix(pageSize))
        )
    }

    private static func readJSON(fixture: Fixture) async throws -> JSONRead {
        let clock = ContinuousClock()
        let start = clock.now
        let cache = LegacyIMAPMailboxHeaderCache(rootDirectory: fixture.cacheRoot)
        let result = await cache.snapshot(accountID: accountID, folderID: folderID)
        let duration = clock.now - start
        let snapshot = try #require(result)
        #expect(snapshot.headers.count == fixture.rowCount)
        #expect(snapshot.uidValidity == 777)
        #expect(snapshot.highestModSeq == 888)
        #expect(snapshot.nextPageToken == fixture.nextPageToken)
        #expect(snapshot.firstPageHeaderIDs == Set(fixture.expectedFirstPage.map(\.id)))
        let threadStart = clock.now
        let threaded = Array(MessageThreadResolver.resolved(snapshot.headers).prefix(pageSize))
        let threadDuration = clock.now - threadStart
        #expect(threaded == fixture.expectedThreadedPage)
        return JSONRead(page: Array(snapshot.headers.prefix(pageSize)), duration: duration, threadDuration: threadDuration)
    }

    private static func readSQLite(fixture: Fixture) async throws -> SQLiteRead {
        let clock = ContinuousClock()
        let start = clock.now
        let store = try SQLiteSyncStore(databaseURL: fixture.databaseURL)
        let opened = clock.now
        let page = store.headers(accountID: accountID, folderID: folderID, limit: pageSize, offset: 0)
        let finished = clock.now
        let nextPage = store.headers(accountID: accountID, folderID: folderID, limit: pageSize, offset: pageSize)
        let threadStart = clock.now
        let engine = BrevSyncEngine(store: store)
        let linked = try await engine.imapThreadingHeaders(for: page, folderID: folderID, account: account)
        let resolved = MessageThreadResolver.resolved(linked)
        let byID = Dictionary(uniqueKeysWithValues: resolved.map { ($0.id, $0) })
        let threaded = page.compactMap { byID[$0.id] }
        let threadDuration = clock.now - threadStart
        #expect(linked.count == pageSize * 2)
        #expect(threaded == fixture.expectedThreadedPage)
        return SQLiteRead(
            page: page,
            nextPage: nextPage,
            openDuration: opened - start,
            queryDuration: finished - opened,
            totalDuration: finished - start,
            threadDuration: threadDuration
        )
    }

    private static var account: BrevAccount {
        BrevAccount(id: accountID, displayName: "Baseline", emailAddress: "reader@example.test")
    }

    private static func readBackend(fixture: Fixture) async throws -> Duration {
        let start = ContinuousClock.now
        let engine = try BrevSyncEngine(databaseURL: fixture.databaseURL)
        let legacy = LegacyReadCounter(root: fixture.cacheRoot.appendingPathComponent("migrated"))
        let backend = IMAPLegacyRecoveryTests().backend(engine, legacy: legacy,
                                                        sources: InMemoryIMAPMessageSourceCache(),
                                                        bodies: InMemoryIMAPMessageBodyCache(), account: account)
        let result = try await backend.messages(in: Folder(id: folderID, name: "Inbox", role: .inbox), pageToken: nil)
        let duration = ContinuousClock.now - start
        #expect(result.headers == fixture.expectedThreadedPage)
        #expect(result.nextPageToken != nil)
        #expect(await legacy.probes == 1)
        #expect(await legacy.decodes == 0)
        await backend.disconnect()
        return duration
    }

    private static func flagPersistence(fixture: Fixture) async throws {
        let engine = try BrevSyncEngine(databaseURL: fixture.databaseURL)
        let legacy = LegacyReadCounter(root: fixture.cacheRoot.appendingPathComponent("migrated"))
        let backend = IMAPLegacyRecoveryTests().backend(engine, legacy: legacy,
                                                        sources: InMemoryIMAPMessageSourceCache(),
                                                        bodies: InMemoryIMAPMessageBodyCache(),
                                                        flag: { _, _, _, _, _, _ in }, account: account)
        try await backend.connect()
        let id = fixture.expectedFirstPage[0].id
        var durations: [Duration] = []
        for sample in 0 ..< 6 {
            let value = !sample.isMultiple(of: 2)
            let start = ContinuousClock.now
            try await backend.setRead(value, for: [id])
            let duration = ContinuousClock.now - start
            durations.append(duration)
            let reopened = try BrevSyncEngine(databaseURL: fixture.databaseURL)
            #expect(try await reopened.imapHeaders(ids: [id], folderID: folderID, account: account).first?.isRead == value)
        }
        #expect(await legacy.probes == 1)
        #expect(await legacy.decodes == 0)
        #expect(await legacy.writes == 0)
        await backend.disconnect()
        await print(
            "PERF flag-persist rows=\(fixture.rowCount) samples=6 stub_server=true median_ms=\(ms(median(durations))) max_ms=\(ms(durations.max()!)) legacy_probes=\(legacy.probes) legacy_decodes=\(legacy.decodes) legacy_writes=\(legacy.writes)"
        )
    }

    private actor LegacyReadCounter: IMAPMailboxHeaderCache {
        private let cache: LegacyIMAPMailboxHeaderCache
        var probes = 0
        var decodes = 0
        var writes = 0
        init(root: URL) { cache = LegacyIMAPMailboxHeaderCache(rootDirectory: root) }
        func snapshot(accountID: String, folderID: String) async -> IMAPMailboxHeaderCacheSnapshot? {
            probes += 1
            let snapshot = await cache.snapshot(accountID: accountID, folderID: folderID)
            if snapshot != nil { decodes += 1 }
            return snapshot
        }

        func setSnapshot(_: IMAPMailboxHeaderCacheSnapshot, accountID _: String, folderID _: String) { writes += 1 }
        func clear(accountID _: String, folderID _: String) {}
        func clear(accountID _: String) {}
    }

    private static func median(_ durations: [Duration]) -> Duration {
        let ordered = durations.sorted()
        return (ordered[ordered.count / 2 - 1] + ordered[ordered.count / 2]) / 2
    }

    private static func ms(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        let value = Double(seconds) * 1000 + Double(attoseconds) / 1e15
        return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static var buildMode: String {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }
}
