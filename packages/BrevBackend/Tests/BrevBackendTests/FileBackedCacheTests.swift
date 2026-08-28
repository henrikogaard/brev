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

// MARK: - FileBackedIMAPMailboxHeaderCache

@Suite("FileBackedIMAPMailboxHeaderCache")
struct FileBackedIMAPMailboxHeaderCacheTests {
    @Test("write then read returns same snapshot")
    func writeThenReadReturnsSameSnapshot() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = FileBackedIMAPMailboxHeaderCache(rootDirectory: dir)
        let snapshot = IMAPMailboxHeaderCacheSnapshot(
            headers: [Self.makeHeader(id: "INBOX:1")],
            uidValidity: 12345,
            nextPageToken: "before:1",
            firstPageHeaderIDs: ["INBOX:1"],
            pageHeaderIDsByToken: ["before:2": ["INBOX:1"]]
        )

        await cache.setSnapshot(snapshot, accountID: "acc1", folderID: "INBOX")
        let read = await cache.snapshot(accountID: "acc1", folderID: "INBOX")

        #expect(read?.headers.map(\.id) == ["INBOX:1"])
        #expect(read?.uidValidity == 12345)
        #expect(read?.nextPageToken == "before:1")
        #expect(read?.firstPageHeaderIDs == ["INBOX:1"])
        #expect(read?.pageHeaderIDsByToken == ["before:2": ["INBOX:1"]])
    }

    @Test("cross-instance read (simulates fresh launch)")
    func crossInstanceReadReturnsSameData() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let writer = FileBackedIMAPMailboxHeaderCache(rootDirectory: dir)
        let snapshot = IMAPMailboxHeaderCacheSnapshot(
            headers: [Self.makeHeader(id: "INBOX:99")],
            uidValidity: 77777
        )
        await writer.setSnapshot(snapshot, accountID: "acc", folderID: "INBOX")

        // Simulate a fresh app launch by creating a new instance over the same directory.
        let reader = FileBackedIMAPMailboxHeaderCache(rootDirectory: dir)
        let read = await reader.snapshot(accountID: "acc", folderID: "INBOX")

        #expect(read?.headers.map(\.id) == ["INBOX:99"])
        #expect(read?.uidValidity == 77777)
    }

    @Test("clear removes data from disk")
    func clearRemovesDataFromDisk() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = FileBackedIMAPMailboxHeaderCache(rootDirectory: dir)
        let snapshot = IMAPMailboxHeaderCacheSnapshot(
            headers: [Self.makeHeader(id: "INBOX:5")]
        )
        await cache.setSnapshot(snapshot, accountID: "acc", folderID: "INBOX")
        await cache.clear(accountID: "acc")

        let read = await cache.snapshot(accountID: "acc", folderID: "INBOX")
        #expect(read == nil)

        // A new instance over the same directory should also see nothing.
        let freshCache = FileBackedIMAPMailboxHeaderCache(rootDirectory: dir)
        let freshRead = await freshCache.snapshot(accountID: "acc", folderID: "INBOX")
        #expect(freshRead == nil)
    }

    @Test("multiple folders are cached independently")
    func multipleFoldersAreCachedIndependently() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = FileBackedIMAPMailboxHeaderCache(rootDirectory: dir)
        await cache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [Self.makeHeader(id: "INBOX:1")]),
            accountID: "acc", folderID: "INBOX"
        )
        await cache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [Self.makeHeader(id: "Sent:1")]),
            accountID: "acc", folderID: "Sent"
        )

        let inbox = await cache.snapshot(accountID: "acc", folderID: "INBOX")
        let sent = await cache.snapshot(accountID: "acc", folderID: "Sent")
        #expect(inbox?.headers.map(\.id) == ["INBOX:1"])
        #expect(sent?.headers.map(\.id) == ["Sent:1"])
    }

    @Test("clear(folderID:) removes only that folder and keeps the account")
    func clearSingleFolderKeepsOtherFolders() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = FileBackedIMAPMailboxHeaderCache(rootDirectory: dir)
        await cache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [Self.makeHeader(id: "INBOX:1")]),
            accountID: "acc", folderID: "INBOX"
        )
        await cache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [Self.makeHeader(id: "Sent:1")]),
            accountID: "acc", folderID: "Sent"
        )

        await cache.clear(accountID: "acc", folderID: "INBOX")

        #expect(await cache.snapshot(accountID: "acc", folderID: "INBOX") == nil)
        #expect(await cache.snapshot(accountID: "acc", folderID: "Sent")?.headers.map(\.id) == ["Sent:1"])

        // The surviving folder is still there after a fresh launch.
        let fresh = FileBackedIMAPMailboxHeaderCache(rootDirectory: dir)
        #expect(await fresh.snapshot(accountID: "acc", folderID: "INBOX") == nil)
        #expect(await fresh.snapshot(accountID: "acc", folderID: "Sent")?.headers.map(\.id) == ["Sent:1"])
    }

    @Test("in-memory clear(folderID:) removes only that folder and keeps the account")
    func inMemoryClearSingleFolderKeepsOtherFolders() async throws {
        let cache = InMemoryIMAPMailboxHeaderCache()
        await cache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [Self.makeHeader(id: "INBOX:1")]),
            accountID: "acc", folderID: "INBOX"
        )
        await cache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [Self.makeHeader(id: "Sent:1")]),
            accountID: "acc", folderID: "Sent"
        )

        await cache.clear(accountID: "acc", folderID: "INBOX")

        #expect(await cache.snapshot(accountID: "acc", folderID: "INBOX") == nil)
        #expect(await cache.snapshot(accountID: "acc", folderID: "Sent")?.headers.map(\.id) == ["Sent:1"])
    }

    private static func makeHeader(id: MessageHeader.ID) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "<\(id)@example.org>",
            folderID: "INBOX",
            from: Correspondent(email: "sender@example.org"),
            to: [Correspondent(email: "recipient@example.org")],
            cc: [],
            bcc: [],
            subject: "Test",
            snippet: "",
            date: Date(timeIntervalSince1970: 1_780_000_000),
            isRead: false,
            isFlagged: false,
            hasAttachments: false
        )
    }
}

// MARK: - FileBackedIMAPFolderSnapshotCache

@Suite("FileBackedIMAPFolderSnapshotCache")
struct FileBackedIMAPFolderSnapshotCacheTests {
    @Test("write then read returns same snapshot")
    func writeThenReadReturnsSameSnapshot() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = FileBackedIMAPFolderSnapshotCache(rootDirectory: dir)
        let folder = Folder(id: "INBOX", name: "Inbox", role: .inbox, unreadCount: 3)
        let snapshot = IMAPFolderCacheSnapshot(
            folders: [folder],
            folderDelimitersByID: ["INBOX": "/"]
        )

        await cache.setSnapshot(snapshot, accountID: "acc")
        let read = await cache.snapshot(accountID: "acc")

        #expect(read?.folders == [folder])
        #expect(read?.folderDelimitersByID == ["INBOX": "/"])
    }

    @Test("cross-instance read (simulates fresh launch)")
    func crossInstanceReadReturnsSameData() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let writer = FileBackedIMAPFolderSnapshotCache(rootDirectory: dir)
        let folder = Folder(id: "Sent", name: "Sent", role: .sent, unreadCount: 0)
        await writer.setSnapshot(
            IMAPFolderCacheSnapshot(folders: [folder]),
            accountID: "acc"
        )

        let reader = FileBackedIMAPFolderSnapshotCache(rootDirectory: dir)
        let read = await reader.snapshot(accountID: "acc")

        #expect(read?.folders.map(\.id) == ["Sent"])
    }

    @Test("clear removes data from disk")
    func clearRemovesDataFromDisk() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = FileBackedIMAPFolderSnapshotCache(rootDirectory: dir)
        let folder = Folder(id: "INBOX", name: "Inbox", role: .inbox, unreadCount: 0)
        await cache.setSnapshot(
            IMAPFolderCacheSnapshot(folders: [folder]),
            accountID: "acc"
        )
        await cache.clear(accountID: "acc")

        let read = await cache.snapshot(accountID: "acc")
        #expect(read == nil)

        let freshCache = FileBackedIMAPFolderSnapshotCache(rootDirectory: dir)
        let freshRead = await freshCache.snapshot(accountID: "acc")
        #expect(freshRead == nil)
    }
}

// MARK: - FileBackedIMAPMessageSourceCache

@Suite("FileBackedIMAPMessageSourceCache")
struct FileBackedIMAPMessageSourceCacheTests {
    @Test("write then read returns same source")
    func writeThenReadReturnsSameSource() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = FileBackedIMAPMessageSourceCache(rootDirectory: dir)
        let source = IMAPMessageSource(uid: 42, rawMessage: "From: a@b.com\r\n\r\nHello")

        await cache.setSource(source, accountID: "acc", messageID: "INBOX:42")
        let read = await cache.source(accountID: "acc", messageID: "INBOX:42")

        #expect(read?.uid == 42)
        #expect(read?.rawMessage == "From: a@b.com\r\n\r\nHello")
    }

    @Test("cross-instance read (simulates fresh launch)")
    func crossInstanceReadReturnsSameData() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let writer = FileBackedIMAPMessageSourceCache(rootDirectory: dir)
        let source = IMAPMessageSource(uid: 7, rawMessage: "Subject: Hi\r\n\r\nBody")
        await writer.setSource(source, accountID: "acc", messageID: "INBOX:7")

        let reader = FileBackedIMAPMessageSourceCache(rootDirectory: dir)
        let read = await reader.source(accountID: "acc", messageID: "INBOX:7")

        #expect(read?.uid == 7)
        #expect(read?.rawMessage == "Subject: Hi\r\n\r\nBody")
    }

    @Test("clear removes data from disk")
    func clearRemovesDataFromDisk() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = FileBackedIMAPMessageSourceCache(rootDirectory: dir)
        let source = IMAPMessageSource(uid: 1, rawMessage: "Hello")
        await cache.setSource(source, accountID: "acc", messageID: "INBOX:1")
        await cache.clear(accountID: "acc")

        let read = await cache.source(accountID: "acc", messageID: "INBOX:1")
        #expect(read == nil)

        let freshCache = FileBackedIMAPMessageSourceCache(rootDirectory: dir)
        let freshRead = await freshCache.source(accountID: "acc", messageID: "INBOX:1")
        #expect(freshRead == nil)
    }

    @Test("remove sources in folder preserves colon nested folders")
    func removeSourcesInFolderPreservesColonNestedFolders() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = FileBackedIMAPMessageSourceCache(rootDirectory: dir)
        let parentSource = IMAPMessageSource(uid: 42, rawMessage: "Subject: Parent\r\n\r\nParent body")
        let nestedSource = IMAPMessageSource(uid: 7, rawMessage: "Subject: Nested\r\n\r\nNested body")
        let siblingSource = IMAPMessageSource(uid: 9, rawMessage: "Subject: Sibling\r\n\r\nSibling body")
        await cache.setSource(parentSource, accountID: "acc", messageID: "Projects:42")
        await cache.setSource(nestedSource, accountID: "acc", messageID: "Projects:2026:7")
        await cache.setSource(siblingSource, accountID: "other", messageID: "Projects:9")

        await cache.removeSources(inFolder: "Projects", accountID: "acc")

        #expect(await cache.source(accountID: "acc", messageID: "Projects:42") == nil)
        #expect(await cache.source(accountID: "acc", messageID: "Projects:2026:7")?.uid == 7)
        #expect(await cache.source(accountID: "other", messageID: "Projects:9")?.uid == 9)
    }

    @Test("remove sources in folder except keeps excluded IDs and nested folders")
    func removeSourcesInFolderExceptKeepsExcludedAndNestedFolders() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = FileBackedIMAPMessageSourceCache(rootDirectory: dir)
        let pinned = IMAPMessageSource(uid: 1, rawMessage: "Subject: Pinned\r\n\r\nPinned body")
        let evicted = IMAPMessageSource(uid: 2, rawMessage: "Subject: Evicted\r\n\r\nEvicted body")
        let orphan = IMAPMessageSource(uid: 99, rawMessage: "Subject: Orphan\r\n\r\nOrphan body")
        let nested = IMAPMessageSource(uid: 7, rawMessage: "Subject: Nested\r\n\r\nNested body")
        await cache.setSource(pinned, accountID: "acc", messageID: "INBOX:1")
        await cache.setSource(evicted, accountID: "acc", messageID: "INBOX:2")
        await cache.setSource(orphan, accountID: "acc", messageID: "INBOX:99")
        await cache.setSource(nested, accountID: "acc", messageID: "INBOX:2026:7")

        await cache.removeSources(inFolder: "INBOX", accountID: "acc", exceptMessageIDs: ["INBOX:1"])

        // Excluded id survives; other folder members (including the orphan-style
        // id with no header) are evicted; colon-nested folders are preserved.
        #expect(await cache.source(accountID: "acc", messageID: "INBOX:1")?.uid == 1)
        #expect(await cache.source(accountID: "acc", messageID: "INBOX:2") == nil)
        #expect(await cache.source(accountID: "acc", messageID: "INBOX:99") == nil)
        #expect(await cache.source(accountID: "acc", messageID: "INBOX:2026:7")?.uid == 7)
    }

    @Test("50 MiB cap evicts oldest entries")
    func fiftyMiBCapEvictsOldestEntries() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Use a tiny cap of 512 bytes to test eviction without large data.
        let cache = FileBackedIMAPMessageSourceCache(
            rootDirectory: dir,
            maximumAccountSizeBytes: 512
        )

        // Each message has a ~300-byte raw body — two will exceed the 512-byte cap.
        let body = String(repeating: "X", count: 300)
        let source1 = IMAPMessageSource(uid: 1, rawMessage: body)
        let source2 = IMAPMessageSource(uid: 2, rawMessage: body)

        await cache.setSource(source1, accountID: "acc", messageID: "INBOX:1")
        await cache.setSource(source2, accountID: "acc", messageID: "INBOX:2")

        // After eviction the total must be at or under the cap.
        let size = await cache.sizeBytes(accountID: "acc")
        #expect(size <= 512)
    }
}

// MARK: - Helpers

private func makeTempDirectory() -> URL {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("BrevTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    return tmp
}
