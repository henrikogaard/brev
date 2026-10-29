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

@Suite("IMAP page index bridge")
struct IMAPPageIndexTests {
    @Test("engine commits page state and membership through either store", arguments: [false, true])
    func enginePageWrites(sqlite: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brev-page-index-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store: any SyncStoreProtocol = sqlite
            ? try SQLiteSyncStore(databaseURL: root.appendingPathComponent("index.sqlite")) : InMemorySyncStore()
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

    private func page(_ uids: [Int], token: String?) -> IMAPHeaderPageWrite {
        IMAPHeaderPageWrite(folderID: "INBOX", pageToken: token, headers: uids.map {
            MessageHeader(id: "INBOX:\($0)", threadID: "thread-\($0)", folderID: "INBOX",
                          from: Correspondent(email: "sender@example.test"), subject: "Synthetic \($0)", snippet: "",
                          date: Date(timeIntervalSince1970: TimeInterval($0)))
        }, uidValidity: 777, highestModSeq: 888, nextPageToken: "before:1")
    }
}
