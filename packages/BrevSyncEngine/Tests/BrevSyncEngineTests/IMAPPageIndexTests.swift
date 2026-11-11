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

@Suite("IMAP page index bridge")
struct IMAPPageIndexTests {
    @Test("engine commits page state and membership through either store", arguments: [false, true])
    func enginePageWrites(sqlite: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brev-page-index-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store: any SyncStoreProtocol = sqlite
            ? try SQLiteSyncStore(databaseURL: root.appendingPathComponent("index.sqlite")) : InMemorySyncStore()
        #expect(store.currentSchemaVersion == 10)
        let engine = BrevSyncEngine(store: store)
        let account = BrevAccount(id: "synthetic", displayName: "Synthetic", emailAddress: "reader@example.test")
        let first = page([3, 4], token: nil)
        try await engine.storeIMAPPage(first, account: account)
        try await engine.storeIMAPPage(page([1, 2], token: "before:3"), account: account)
        #expect(try await store.imapPageUIDs(accountID: account.id, folderID: "INBOX", pageKey: "first") == [3, 4])
        #expect(try await store.imapPageUIDs(accountID: account.id, folderID: "INBOX", pageKey: "before:3") == [1, 2])
        let state = try await store.imapPageState(accountID: account.id, folderID: "INBOX")
        #expect(state?.uidValidity == 777)
        #expect(state?.highestModSeq == 888)
        try await engine.storeIMAPPage(page([], token: nil), account: account)
        #expect(try await store.imapPageUIDs(accountID: account.id, folderID: "INBOX", pageKey: "first").isEmpty)
        #expect(try await store.imapPageUIDs(accountID: account.id, folderID: "INBOX", pageKey: "before:3") == [1, 2])
        await #expect(throws: (any Error).self) {
            try await engine.storeIMAPPage(IMAPHeaderPageWrite(
                folderID: "INBOX", pageToken: nil, headers: first.headers,
                uidValidity: 999, highestModSeq: nil, nextPageToken: nil
            ), account: account)
        }
        try await store.deleteHeaders(messageIDs: ["INBOX:1"], accountID: account.id)
        #expect(try await store.imapPageUIDs(accountID: account.id, folderID: "INBOX", pageKey: "before:3") == [2])
        try await store.clearAccount(id: account.id)
        #expect(try await store.imapPageState(accountID: account.id, folderID: "INBOX") == nil)
    }

    @Test("legacy retry after cleanup failure never restores deleted rows", arguments: [false, true])
    func legacyRetryAfterDeletion(sqlite: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brev-import-retry-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("index.sqlite")
        var store: any SyncStoreProtocol = sqlite
            ? try SQLiteSyncStore(databaseURL: databaseURL) : InMemorySyncStore()
        let account = BrevAccount(id: "synthetic", displayName: "Synthetic", emailAddress: "reader@example.test")
        let snapshot = IMAPMailboxHeaderCacheSnapshot(headers: page([1, 2], token: nil).headers,
                                                      uidValidity: 777, firstPageHeaderIDs: ["INBOX:1", "INBOX:2"])
        let legacy = NonClearingLegacyCache(value: snapshot)
        try await IndexedIMAPMailboxHeaderCache(index: BrevSyncEngine(store: store), account: account, legacy: legacy)
            .prepare(folderID: "INBOX")
        #expect(await legacy.snapshot(accountID: account.id, folderID: "INBOX") != nil)
        try await store.deleteHeaders(messageIDs: ["INBOX:1"], accountID: "synthetic")
        if sqlite { store = try SQLiteSyncStore(databaseURL: databaseURL) }
        try await IndexedIMAPMailboxHeaderCache(index: BrevSyncEngine(store: store), account: account, legacy: legacy)
            .prepare(folderID: "INBOX")
        #expect(try await store.headersByID(["INBOX:1"], accountID: "synthetic", folderID: "INBOX").isEmpty)
        #expect(try await store.imapPageUIDs(accountID: "synthetic", folderID: "INBOX", pageKey: "first").isEmpty)
        #expect(try await store.hasPendingIMAPRecovery(accountID: "synthetic", folderID: "INBOX"))
        try await store.clearFolder(accountID: "synthetic", folderID: "INBOX")
        try await store.storeIMAPPage(IMAPHeaderPageWrite(folderID: "INBOX", pageToken: nil, headers: [],
                                                          uidValidity: 999, highestModSeq: nil, nextPageToken: nil),
                                      accountID: "synthetic")
        try await store.storeIMAPSnapshot(snapshot, accountID: "synthetic", folderID: "INBOX", importingLegacy: true)
        #expect(try await store.headersByID(["INBOX:1", "INBOX:2"], accountID: "synthetic", folderID: "INBOX").isEmpty)
    }

    private func page(_ uids: [Int], token: String?) -> IMAPHeaderPageWrite {
        IMAPHeaderPageWrite(folderID: "INBOX", pageToken: token, headers: uids.map {
            MessageHeader(id: "INBOX:\($0)", threadID: "thread-\($0)", folderID: "INBOX",
                          from: Correspondent(email: "sender@example.test"), subject: "Synthetic \($0)", snippet: "",
                          date: Date(timeIntervalSince1970: TimeInterval($0)))
        }, uidValidity: 777, highestModSeq: 888, nextPageToken: "before:1")
    }

    private struct NonClearingLegacyCache: IMAPMailboxHeaderCache {
        let value: IMAPMailboxHeaderCacheSnapshot
        func snapshot(accountID _: BrevAccount.ID, folderID _: Folder.ID) async -> IMAPMailboxHeaderCacheSnapshot? { value }
        func setSnapshot(_: IMAPMailboxHeaderCacheSnapshot, accountID _: BrevAccount.ID, folderID _: Folder.ID) async {}
        func clear(accountID _: BrevAccount.ID, folderID _: Folder.ID) async {}
        func clear(accountID _: BrevAccount.ID) async {}
    }

    @Test("selective maintenance reads and row writes preserve unrelated rows and windows", arguments: [false, true])
    func selectiveMaintenance(sqlite: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brev-selective-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store: any SyncStoreProtocol = sqlite
            ? try SQLiteSyncStore(databaseURL: root.appendingPathComponent("index.sqlite")) : InMemorySyncStore()
        let account = BrevAccount(id: "synthetic", displayName: "Synthetic", emailAddress: "reader@example.test")
        let engine = BrevSyncEngine(store: store)
        let headers = (1 ... 3).map { uid in
            MessageHeader(id: "INBOX:\(uid)", threadID: "thread-\(uid)", folderID: "INBOX",
                          from: Correspondent(email: "sender@example.test"), subject: "Synthetic", snippet: "",
                          date: uid == 1 ? .distantPast : Date(timeIntervalSince1970: TimeInterval(uid)),
                          hasAttachments: uid == 3)
        }
        try await engine.storeIMAPPage(IMAPHeaderPageWrite(folderID: "INBOX", pageToken: nil, headers: headers,
                                                           uidValidity: 777, highestModSeq: 888, nextPageToken: "saved"),
                                       account: account)
        await engine.storeRawMessage(Data("Synthetic body".utf8), for: "INBOX:2", account: account)
        #expect(try await engine.selectIMAPHeaders(.attachmentsOrCachedBodies, folderID: "INBOX", account: account).map(\.id) == [
            "INBOX:3",
            "INBOX:2"
        ])
        #expect(try await engine.selectIMAPHeaders(.invalidDates, folderID: "INBOX", account: account).map(\.id) == ["INBOX:1"])
        #expect(try await engine.selectIMAPHeaders(
            .olderThan(Date(timeIntervalSince1970: 2.5)),
            folderID: "INBOX",
            account: account
        ).map(\.id) == ["INBOX:2", "INBOX:1"])
        #expect(try await engine.selectIMAPHeaders(.excludingIDs(["INBOX:1", "INBOX:3"]), folderID: "INBOX", account: account)
            .map(\.id) == ["INBOX:2"])
        var changed = headers[1]
        changed.isRead = true
        await engine.storeHeaders([changed], account: account)
        try await engine.updateIMAPModSeq(999, folderID: "INBOX", account: account)
        #expect(try await engine.imapHeaders(ids: ["INBOX:1"], folderID: "INBOX", account: account).first?.isRead == false)
        #expect(try await store.imapPageUIDs(accountID: account.id, folderID: "INBOX", pageKey: "first") == [1, 2, 3])
        #expect(try await engine.imapHeaderMetadata(folderID: "INBOX", account: account)?.nextPageToken == "saved")
        #expect(try await engine.imapHeaderMetadata(folderID: "INBOX", account: account)?.highestModSeq == 999)
    }

    @Test("date selections preserve sentinel and fractional retention semantics", arguments: [false, true])
    func exactDateSelections(sqlite: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brev-exact-dates-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store: any SyncStoreProtocol = sqlite
            ? try SQLiteSyncStore(databaseURL: root.appendingPathComponent("index.sqlite")) : InMemorySyncStore()
        let dates = [Date.distantPast, Date.distantPast.addingTimeInterval(0.5)]
            + [-2.8, -2.5, -2.2, -0.5, 0, 0.5, 2.2, 2.5, 2.8].map { Date(timeIntervalSince1970: $0) }
        let headers = dates.enumerated().map { offset, date in
            MessageHeader(id: "INBOX:\(offset + 1)", threadID: "t", folderID: "INBOX",
                          from: Correspondent(email: "sender@example.test"), subject: "Synthetic", snippet: "", date: date)
        }
        try await store.ensureAccount(id: "synthetic")
        try await store.upsertHeaders(headers, accountID: "synthetic")
        #expect(try await store.selectIMAPHeaders(.invalidDates, accountID: "synthetic", folderID: "INBOX")
            .map(\.id) == ["INBOX:1"])
        for cutoff in [-2.5, -2.0, 0, 0.5, 2.5, 3.0].map({ Date(timeIntervalSince1970: $0) }) {
            let selected = try await store.selectIMAPHeaders(.olderThan(cutoff), accountID: "synthetic", folderID: "INBOX")
            #expect(Set(selected.map(\.id)) == Set(headers.filter { $0.date < cutoff }.map(\.id)))
        }
    }

    @Test("legacy import preserves newer rows and only removes the source after success", arguments: [false, true])
    func legacyImport(sqlite: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brev-page-import-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store: any SyncStoreProtocol = sqlite
            ? try SQLiteSyncStore(databaseURL: root.appendingPathComponent("index.sqlite")) : InMemorySyncStore()
        let engine = BrevSyncEngine(store: store)
        let account = BrevAccount(id: "synthetic", displayName: "Synthetic", emailAddress: "reader@example.test")
        try await engine.storeIMAPPage(page([3], token: nil), account: account)
        var stale = page([1, 3], token: nil).headers
        stale[1].isRead = true
        let legacy = InMemoryIMAPMailboxHeaderCache()
        let wrongFolder = IMAPMailboxHeaderCacheSnapshot(headers: [MessageHeader(
            id: "Other:1", threadID: "t", folderID: "Other", from: Correspondent(email: "sender@example.test"),
            subject: "Malformed", snippet: "", date: Date(timeIntervalSince1970: 1)
        )])
        await legacy.setSnapshot(wrongFolder, accountID: account.id, folderID: "INBOX")
        let retry = IndexedIMAPMailboxHeaderCache(index: engine, account: account, legacy: legacy)
        await #expect(throws: (any Error).self) { try await retry.prepare(folderID: "INBOX") }
        #expect(await legacy.snapshot(accountID: account.id, folderID: "INBOX") != nil)
        let snapshot = IMAPMailboxHeaderCacheSnapshot(headers: stale, uidValidity: 777, highestModSeq: 1,
                                                      nextPageToken: "stale", firstPageHeaderIDs: ["INBOX:1", "INBOX:3"],
                                                      pageHeaderIDsByToken: ["before:3": ["INBOX:1"]])
        await legacy.setSnapshot(snapshot, accountID: account.id, folderID: "INBOX")
        let adapter = IndexedIMAPMailboxHeaderCache(index: engine, account: account, legacy: legacy)
        try await adapter.prepare(folderID: "INBOX")
        #expect(await legacy.snapshot(accountID: account.id, folderID: "INBOX") == nil)
        let restored = try await engine.imapHeaders(ids: ["INBOX:1", "INBOX:3"], folderID: "INBOX", account: account)
        #expect(restored.count == 1)
        #expect(try await engine.hasPendingIMAPRecovery(folderID: "INBOX", account: account))
        #expect(restored.last?.isRead == false)
        #expect(try await engine.imapHeaderMetadata(folderID: "INBOX", account: account)?.nextPageToken == "before:1")
        #expect(try await store.imapPageUIDs(accountID: account.id, folderID: "INBOX", pageKey: "first") == [3])
        #expect(try await store.imapPageUIDs(accountID: account.id, folderID: "INBOX", pageKey: "before:3").isEmpty)
    }
}
