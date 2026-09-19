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
import Foundation
import Testing

@Suite("DeferredLocalSearchIndex")
struct DeferredLocalSearchIndexTests {
    private let account = BrevAccount(
        id: "acct",
        displayName: "Test",
        emailAddress: "test@example.org"
    )

    @Test("factory is not invoked until the first indexed operation")
    func factoryIsNotInvokedUntilFirstUse() async {
        let calls = FactoryCallCounter()
        let index = DeferredLocalSearchIndex {
            calls.bump()
            return nil
        }
        #expect(calls.value == 0)
        _ = await index.metrics(for: account)
        #expect(calls.value == 1)
        _ = await index.metrics(for: account)
        // The result is cached — repeated calls do not reopen the store.
        #expect(calls.value == 1)
    }

    @Test("a nil factory result behaves like an absent index")
    func nilFactoryResultBehavesLikeAbsentIndex() async {
        let index = DeferredLocalSearchIndex { nil }
        #expect(await index.search(SearchQuery(), account: account, limit: 10) == [])
        #expect(await index.attachmentIndexBytes(accountID: account.id) == 0)
        #expect(await index.indexedAttachmentMessageIDs(accountID: account.id) == [])
        #expect(await index.metrics(for: account) == nil)
    }

    @Test("resolved index receives forwarded calls")
    func resolvedIndexReceivesCalls() async {
        let underlying = RecordingIndex()
        let index = DeferredLocalSearchIndex { underlying }
        let header = MessageHeader(
            id: "m1",
            threadID: "m1",
            folderID: "INBOX",
            from: Correspondent(name: "Sender", email: "sender@example.org"),
            subject: "Hello",
            snippet: "Hello",
            date: Date(timeIntervalSince1970: 100)
        )
        await index.storeHeaders([header], account: account)
        #expect(underlying.storedCount == 1)
    }
}

/// Thread-safe counter for the `@Sendable` factory closure.
private final class FactoryCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var value = 0
    func bump() { lock.withLock { value += 1 } }
}

/// Minimal `MailLocalSearchIndex` that records stored headers.
private final class RecordingIndex: MailLocalSearchIndex, @unchecked Sendable {
    private let lock = NSLock()
    private var headers: [MessageHeader] = []

    var storedCount: Int {
        lock.withLock { headers.count }
    }

    func cachedHeaders(
        for _: Folder,
        account _: BrevAccount,
        pageToken _: String?
    ) async -> (headers: [MessageHeader], nextPageToken: String?)? { nil }

    func cachedRawMessage(for _: MessageHeader.ID, account _: BrevAccount) async -> Data? { nil }

    func search(
        _: SearchQuery,
        account _: BrevAccount,
        limit _: Int
    ) async -> [MessageHeader] { [] }

    func storeHeaders(_ newHeaders: [MessageHeader], account _: BrevAccount) async {
        lock.withLock { headers.append(contentsOf: newHeaders) }
    }

    func storeRawMessage(_: Data, for _: MessageHeader.ID, account _: BrevAccount) async {}
    func deleteMessages(_: [MessageHeader.ID], account _: BrevAccount) async {}
    func deleteRawMessages(_: [MessageHeader.ID], account _: BrevAccount) async {}
    func deleteRawMessages(inFolder _: Folder.ID, account _: BrevAccount) async {}
    func deleteRawMessages(
        inFolder _: Folder.ID,
        except _: Set<MessageHeader.ID>,
        account _: BrevAccount
    ) async {}
    func clearFolder(folderID _: Folder.ID, account _: BrevAccount) async {}
    func clearAccount(_: BrevAccount) async {}
    func metrics(for _: BrevAccount) async -> LocalSearchIndexMetrics? { nil }
}
