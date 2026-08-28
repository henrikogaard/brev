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
@testable import BrevMail
import Foundation
import Testing

@Suite("MailboxStorageInfo")
struct MailboxStorageInfoTests {
    @Test("directorySize totals every regular file under the directory")
    func directorySizeTotalsFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-storage-test-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(repeating: 0, count: 1000).write(to: root.appendingPathComponent("a.bin"))
        try Data(repeating: 0, count: 2000).write(to: nested.appendingPathComponent("b.bin"))

        // File allocation rounds up to block size, so assert a lower bound on
        // the logical byte total rather than an exact match.
        #expect(MailboxStorageInfo.directorySize(at: root) >= 3000)
        #expect(MailboxStorageInfo.directoryObjectCount(at: root) == 2)
    }

    @Test("directorySize is zero for a directory that does not exist")
    func directorySizeMissingDirectory() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-missing-\(UUID().uuidString)", isDirectory: true)
        #expect(MailboxStorageInfo.directorySize(at: missing) == 0)
    }

    // The draft staging store and the file caches must use the same hex-key
    // derivation, or the Storage panel would total the wrong drafts directory.
    @Test("cache and drafts directories share the hex-key but live under distinct roots")
    func cacheAndDraftsPathDerivation() throws {
        let accountID = "henrik@ogard.no"
        let key = MailboxStorageInfo.hexKey(accountID)
        let cache = try #require(MailboxStorageInfo.accountDirectory(accountID: accountID))
        let drafts = try #require(MailboxStorageInfo.draftsDirectory(accountID: accountID))

        #expect(cache.lastPathComponent == key)
        #expect(drafts.lastPathComponent == key)
        #expect(cache.deletingLastPathComponent().lastPathComponent == "Cache")
        #expect(drafts.deletingLastPathComponent().lastPathComponent == "Drafts")
    }

    @Test("cache location display redacts account storage key")
    func cacheLocationDisplayRedactsAccountStorageKey() throws {
        let accountID = "mail-settings-storage-account"
        let url = try #require(MailboxStorageInfo.accountDirectory(accountID: accountID))
        let displayPath = MailboxStorageInfo.displayPath(for: url)

        #expect(displayPath.hasSuffix("/account-cache"))
        #expect(displayPath.contains("Brev/Cache"))
        #expect(!displayPath.contains(MailboxStorageInfo.hexKey(accountID)))
    }

    @Test("display path keeps ordinary paths readable")
    func displayPathKeepsOrdinaryPathsReadable() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Brev/Cache", isDirectory: true)

        #expect(MailboxStorageInfo.displayPath(for: url).hasSuffix("Brev/Cache"))
    }

    @Test("total account size includes offline mutation and conflict metadata")
    func totalAccountSizeIncludesOfflineMetadata() throws {
        let accountID = "offline@example.org"
        let defaultsName = "brev-storage-defaults-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
        }
        defaults.set(
            Data(repeating: 1, count: 123),
            forKey: OfflineMutationQueueStorage.storageKey(accountID: accountID)
        )
        defaults.set(
            Data(repeating: 2, count: 456),
            forKey: OfflineMutationQueueStorage.conflictStorageKey(accountID: accountID)
        )

        #expect(MailboxStorageInfo.totalAccountSize(
            accountID: accountID,
            defaults: defaults
        ) >= 579)
        #expect(MailboxStorageInfo.storageBreakdown(
            accountID: accountID,
            defaults: defaults
        ).offlineMetadataObjectCount == 2)
    }

    @Test("cache object count includes folder header and source records")
    func cacheObjectCountIncludesKnownCacheRecords() throws {
        let accountID = "records-\(UUID().uuidString)"
        let cacheURL = try #require(MailboxStorageInfo.accountDirectory(accountID: accountID))
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        try FileManager.default.createDirectory(
            at: cacheURL.appendingPathComponent("headers", isDirectory: true),
            withIntermediateDirectories: true
        )
        let folders = IMAPFolderCacheSnapshot(folders: [
            Folder(id: "inbox", name: "Inbox", role: .inbox),
            Folder(id: "archive", name: "Archive", role: .archive)
        ])
        try JSONEncoder().encode(folders)
            .write(to: cacheURL.appendingPathComponent("folders.json"))
        let headers = IMAPMailboxHeaderCacheSnapshot(headers: [
            Self.makeHeader(id: "inbox:1"),
            Self.makeHeader(id: "inbox:2")
        ])
        try JSONEncoder().encode(headers)
            .write(to: cacheURL.appendingPathComponent("headers/INBOX.json"))
        try JSONEncoder().encode(IMAPMessageSource(uid: 1, rawMessage: "Subject: Cached\r\n\r\nBody"))
            .write(to: cacheURL.appendingPathComponent("source.json"))

        let breakdown = MailboxStorageInfo.storageBreakdown(accountID: accountID)

        #expect(breakdown.cacheObjectCount == 5)
    }

    @Test("cache object count follows the real file-backed source cache layout")
    func cacheObjectCountFollowsFileBackedSourceCacheLayout() async throws {
        let accountID = "source-records-\(UUID().uuidString)"
        let cacheRoot = try #require(MailboxStorageInfo.cacheRoot())
        let cacheURL = try #require(MailboxStorageInfo.accountDirectory(accountID: accountID))
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let sourceCache = FileBackedIMAPMessageSourceCache(rootDirectory: cacheRoot)
        await sourceCache.setSource(
            IMAPMessageSource(uid: 42, rawMessage: "Subject: Cached\r\n\r\nBody"),
            accountID: accountID,
            messageID: "INBOX:42"
        )

        let breakdown = MailboxStorageInfo.storageBreakdown(accountID: accountID)

        #expect(breakdown.cacheObjectCount == 1)
    }

    @Test("cache object count includes nested source cache files")
    func cacheObjectCountIncludesNestedSourceCacheFiles() throws {
        let accountID = "nested-source-records-\(UUID().uuidString)"
        let cacheURL = try #require(MailboxStorageInfo.accountDirectory(accountID: accountID))
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let headersURL = cacheURL.appendingPathComponent("headers", isDirectory: true)
        let sourcesURL = cacheURL.appendingPathComponent("sources/nested", isDirectory: true)
        try FileManager.default.createDirectory(at: headersURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
        try JSONEncoder().encode(IMAPMailboxHeaderCacheSnapshot(headers: [
            Self.makeHeader(id: "inbox:1")
        ])).write(to: headersURL.appendingPathComponent("INBOX.json"))
        try Data("nested source".utf8).write(to: sourcesURL.appendingPathComponent("source.json"))

        let breakdown = MailboxStorageInfo.storageBreakdown(accountID: accountID)

        #expect(breakdown.cacheObjectCount == 2)
    }

    private static func makeHeader(id: String) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: id,
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            subject: "Cached",
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600)
        )
    }
}
