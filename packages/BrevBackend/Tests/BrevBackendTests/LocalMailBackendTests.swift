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

@Suite("LocalMailBackend")
struct LocalMailBackendTests {
    private static let message = """
    From: Alice <alice@example.com>
    To: Bob <bob@example.com>
    Subject: Hello Bob
    Date: Thu, 1 Jan 2026 10:00:00 +0000
    Message-ID: <m1@example.com>

    Body text.
    """

    private static func makeBackend(
        index: (any MailLocalSearchIndex)? = nil
    ) -> (LocalMailBackend, LocalMaildirStore) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("localbackend-\(UUID().uuidString)", isDirectory: true)
        let store = LocalMaildirStore(rootURL: root)
        return (LocalMailBackend(store: store, localSearchIndex: index), store)
    }

    @Test("account is the synthetic local account with folder capabilities only")
    func accountAndCapabilities() {
        let (backend, _) = Self.makeBackend()
        #expect(backend.account.id == LocalMailBackend.accountID)
        #expect(backend.account.backendIdentifier == "local")
        #expect(backend.capabilities == [.folderCreate, .folderRename, .folderDelete])
        #expect(backend.hasFolders == false)
    }

    @Test("createFolder then folders() lists it and flips hasFolders")
    func folderLifecycle() async throws {
        let (backend, _) = Self.makeBackend()
        #expect(try await backend.folders().isEmpty)
        let folder = try await backend.createFolder(name: "Saved", parentID: nil)
        #expect(folder.name == "Saved")
        #expect(try await backend.folders().map(\.id) == [folder.id])
        #expect(backend.hasFolders)
    }

    @Test("importMessages indexes headers with folderID:uniqueID message ids")
    func importAndList() async throws {
        let (backend, _) = Self.makeBackend()
        try await backend.connect()
        let folder = try await backend.createFolder(name: "Saved", parentID: nil)
        let imported = ImportedMessage(
            headers: [
                ("From", "Alice <alice@example.com>"),
                ("To", "Bob <bob@example.com>"),
                ("Subject", "Hello Bob"),
                ("Date", "Thu, 1 Jan 2026 10:00:00 +0000"),
                ("Message-ID", "<m1@example.com>")
            ],
            bodyData: Data("Body text.".utf8)
        )
        let summary = try await backend.importMessages([imported], into: folder)
        #expect(summary.importedCount == 1)

        let page = try await backend.messages(in: folder, pageToken: nil)
        #expect(page.headers.count == 1)
        let header = page.headers[0]
        #expect(header.subject == "Hello Bob")
        #expect(header.from.email == "alice@example.com")
        #expect(header.messageID == "<m1@example.com>")
        #expect(header.folderID == folder.id)
        #expect(header.id.hasPrefix("\(folder.id):"))
    }

    @Test("body and rawSource return stored bytes")
    func bodyAndSource() async throws {
        let (backend, _) = Self.makeBackend()
        try await backend.connect()
        let folder = try await backend.createFolder(name: "Saved", parentID: nil)
        let id = try await backend.importRaw(Data(Self.message.utf8), into: folder)
        let body = try await backend.body(for: id)
        #expect(body.plainText?.contains("Body text") == true)
        let source = try await backend.rawSource(for: id)
        #expect(source.contains("Subject: Hello Bob"))
    }

    @Test("setRead/setFlagged persist via Maildir renames")
    func flagMutations() async throws {
        let (backend, _) = Self.makeBackend()
        try await backend.connect()
        let folder = try await backend.createFolder(name: "Saved", parentID: nil)
        let id = try await backend.importRaw(Data(Self.message.utf8), into: folder)
        try await backend.setFlagged(true, for: [id])
        let page = try await backend.messages(in: folder, pageToken: nil)
        #expect(page.headers[0].isFlagged)
        try await backend.setFlagged(false, for: [id])
        try await backend.setRead(false, for: [id])
        let page2 = try await backend.messages(in: folder, pageToken: nil)
        #expect(!page2.headers[0].isFlagged)
        #expect(!page2.headers[0].isRead)
    }

    @Test("delete is permanent — message file is gone")
    func permanentDelete() async throws {
        let (backend, _) = Self.makeBackend()
        try await backend.connect()
        let folder = try await backend.createFolder(name: "Saved", parentID: nil)
        let id = try await backend.importRaw(Data(Self.message.utf8), into: folder)
        try await backend.delete(messageIDs: [id])
        #expect(try await backend.messages(in: folder, pageToken: nil).headers.isEmpty)
        await #expect(throws: (any Error).self) {
            _ = try await backend.rawMessageData(for: id)
        }
    }

    @Test("in-memory search fallback matches subject")
    func searchFallback() async throws {
        let (backend, _) = Self.makeBackend()
        try await backend.connect()
        let folder = try await backend.createFolder(name: "Saved", parentID: nil)
        _ = try await backend.importRaw(Data(Self.message.utf8), into: folder)
        let hits = try await backend.search(SearchQuery(text: "Hello Bob"))
        #expect(hits.count == 1)
        #expect(try await backend.search(SearchQuery(text: "no-such-thing")).isEmpty)
    }

    @Test("connect rebuilds the index from Maildir files")
    func indexRebuildFromFiles() async throws {
        let index = InMemoryLocalSearchIndex()
        let (backend, _) = Self.makeBackend(index: index)
        try await backend.connect()
        let folder = try await backend.createFolder(name: "Saved", parentID: nil)
        _ = try await backend.importRaw(Data(Self.message.utf8), into: folder)
        #expect(index.storedHeaders.count == 1)

        // Simulate index loss: a fresh empty index plus a fresh backend on
        // the same root must repopulate the index during connect().
        let freshIndex = InMemoryLocalSearchIndex()
        let reopened = LocalMailBackend(store: backend.store, localSearchIndex: freshIndex)
        try await reopened.connect()
        #expect(freshIndex.storedHeaders.count == 1)
        #expect(freshIndex.storedHeaders[0].subject == "Hello Bob")
    }

    @Test("unsupported server features throw or return empty")
    func unsupportedFeatures() async throws {
        let (backend, _) = Self.makeBackend()
        try await backend.connect()
        await #expect(throws: (any Error).self) {
            _ = try await backend.calendarEvent(from: "x")
        }
        #expect(backend.capabilities.isDisjoint(with: [.labels, .serverSideSearch]))
    }

    @Test("move between local folders preserves the message")
    func moveBetweenLocalFolders() async throws {
        let (backend, _) = Self.makeBackend()
        try await backend.connect()
        let source = try await backend.createFolder(name: "A", parentID: nil)
        let destination = try await backend.createFolder(name: "B", parentID: nil)
        let id = try await backend.importRaw(Data(Self.message.utf8), into: source)
        try await backend.move(messageIDs: [id], to: destination)
        #expect(try await backend.messages(in: source, pageToken: nil).headers.isEmpty)
        let moved = try await backend.messages(in: destination, pageToken: nil).headers
        #expect(moved.count == 1)
        #expect(moved[0].subject == "Hello Bob")
    }
}

@Suite("Local mail backup restore")
struct LocalMailBackupRestoreTests {
    private static let mbox = """
    From alice@example.com Thu Jan  1 10:00:00 2026
    From: Alice <alice@example.com>
    Subject: Archived 1
    Message-ID: <a1@example.com>

    One.
    From alice@example.com Thu Jan  1 10:01:00 2026
    From: Alice <alice@example.com>
    Subject: Archived 2
    Message-ID: <a2@example.com>

    Two.
    """

    private static func makeBackend() throws -> (LocalMailBackend, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("localrestore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let mboxURL = root.appendingPathComponent("folder1.mbox")
        try Data(Self.mbox.utf8).write(to: mboxURL)
        let storeRoot = root.appendingPathComponent("store", isDirectory: true)
        let backend = LocalMailBackend(store: LocalMaildirStore(rootURL: storeRoot))
        return (backend, mboxURL)
    }

    @Test("merge restores messages and dedupes by Message-ID on a second run")
    func mergeDedupe() async throws {
        let (backend, mboxURL) = try Self.makeBackend()
        try await backend.connect()
        let payload = LocalMailBackupPayload(
            fileName: "mail/folder1.mbox", folderName: "Saved", fileURL: mboxURL
        )
        let first = await LocalMailBackupImporter.restore(payloads: [payload], into: backend, mode: .merge)
        #expect(first.messagesImported == 2)
        let second = await LocalMailBackupImporter.restore(payloads: [payload], into: backend, mode: .merge)
        #expect(second.messagesImported == 0)
        #expect(second.skippedDuplicates == 2)
        let folder = try #require(try await backend.folders().first)
        #expect(try await backend.messages(in: folder, pageToken: nil).headers.count == 2)
    }

    @Test("replace recreates the folder and re-imports everything")
    func replaceRecreates() async throws {
        let (backend, mboxURL) = try Self.makeBackend()
        try await backend.connect()
        let payload = LocalMailBackupPayload(
            fileName: "mail/folder1.mbox", folderName: "Saved", fileURL: mboxURL
        )
        _ = await LocalMailBackupImporter.restore(payloads: [payload], into: backend, mode: .merge)
        let folderID = try #require(try await backend.folders().first?.id)
        let again = await LocalMailBackupImporter.restore(payloads: [payload], into: backend, mode: .replace)
        #expect(again.messagesImported == 2)
        let folders = try await backend.folders()
        #expect(folders.count == 1)
        #expect(folders[0].id != folderID) // folder was recreated
        #expect(try await backend.messages(in: folders[0], pageToken: nil).headers.count == 2)
    }
}

/// Minimal in-memory `MailLocalSearchIndex` for local-backend tests.
private final class InMemoryLocalSearchIndex: MailLocalSearchIndex, @unchecked Sendable {
    private let lock = NSLock()
    private var headers: [MessageHeader.ID: MessageHeader] = [:]

    var storedHeaders: [MessageHeader] {
        lock.withLock { Array(headers.values) }
    }

    func cachedHeaders(
        for folder: Folder,
        account: BrevAccount,
        pageToken: String?
    ) async -> (headers: [MessageHeader], nextPageToken: String?)? {
        let all = lock.withLock {
            headers.values.filter { $0.folderID == folder.id }.sorted { $0.date > $1.date }
        }
        return all.isEmpty ? nil : (all, nil)
    }

    func cachedRawMessage(for messageID: MessageHeader.ID, account: BrevAccount) async -> Data? { nil }
    func cachedOriginalRawMessage(for messageID: MessageHeader.ID, account: BrevAccount) async -> Data? { nil }
    func storeOriginalRawMessage(_ data: Data, for messageID: MessageHeader.ID, account: BrevAccount) async {}

    func search(_ query: SearchQuery, account: BrevAccount, limit: Int) async -> [MessageHeader] {
        lock.withLock { Array(headers.values.filter { query.matches($0) }.prefix(limit)) }
    }

    func storeHeaders(_ newHeaders: [MessageHeader], account: BrevAccount) async {
        lock.withLock {
            for header in newHeaders {
                headers[header.id] = header
            }
        }
    }

    func storeRawMessage(_ data: Data, for messageID: MessageHeader.ID, account: BrevAccount) async {}
    func deleteMessages(_ messageIDs: [MessageHeader.ID], account: BrevAccount) async {
        lock.withLock { for id in messageIDs {
            headers.removeValue(forKey: id)
        } }
    }

    func deleteRawMessages(_ messageIDs: [MessageHeader.ID], account: BrevAccount) async {}
    func deleteRawMessages(inFolder folderID: Folder.ID, account: BrevAccount) async {}
    func deleteRawMessages(
        inFolder folderID: Folder.ID,
        except exceptMessageIDs: Set<MessageHeader.ID>,
        account: BrevAccount
    ) async {}

    func clearFolder(folderID: Folder.ID, account: BrevAccount) async {
        lock.withLock {
            headers = headers.filter { $0.value.folderID != folderID }
        }
    }

    func clearAccount(_ account: BrevAccount) async {
        lock.withLock { headers.removeAll() }
    }

    func metrics(for account: BrevAccount) async -> LocalSearchIndexMetrics? { nil }
}
