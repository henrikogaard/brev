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

@Suite("Full folder export")
struct MailFolderExporterTests {
    @Test("MBOX follows empty intermediate pages and retains complete original MIME messages")
    func mboxPreservesEveryMessage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("brev-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = FolderExportFixture()
        let backend = fixture.backend()
        try await backend.connect()
        let target = directory.appendingPathComponent("Inbox.mbox")
        let result = try await MailFolderExporter(backend: backend, sourceID: fixture.source, folder: fixture.folder)
            .export(to: target, format: .mbox)
        let data = try Data(contentsOf: result.url)
        #expect(result.messageCount == 2)
        #expect(data.starts(with: Data("From sender@example.org Thu Jan  1 00:00:00 1970\n".utf8)))
        #expect(data.range(of: FolderExportFixture.raw(1)) != nil)
        #expect(data.range(of: FolderExportFixture.raw(2)) != nil)
        #expect(await fixture.events == ["page:first", "body:1", "page:second", "page:third", "body:2"])
    }

    @Test("cancellation after the last message leaves the previous archive intact")
    func cancellationDoesNotPublish() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("brev-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = FolderExportFixture()
        let backend = fixture.backend()
        try await backend.connect()
        let target = directory.appendingPathComponent("Inbox.mbox")
        let original = Data("Existing archive".utf8)
        try original.write(to: target)
        let exporter = MailFolderExporter(backend: backend, sourceID: fixture.source, folder: fixture.folder)
        let task = Task {
            try await exporter.export(to: target, format: .mbox) { completed in
                if completed == 2 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(try Data(contentsOf: target) == original)
    }

    @Test("an offline partial header cache cannot publish a complete folder export")
    func offlinePartialCacheDoesNotPublish() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("brev-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = FolderExportFixture()
        let backend = fixture.backend(
            headerCache: InMemoryIMAPMailboxHeaderCache(),
            sourceCache: InMemoryIMAPMessageSourceCache()
        )
        try await backend.connect()
        let firstPage = try await backend.messages(in: fixture.folder, pageToken: nil)
        let first = try #require(firstPage.headers.first)
        _ = try await backend.rawMessageData(for: first.id, sourceID: fixture.source)
        await backend.disconnect()
        let target = directory.appendingPathComponent("Inbox.mbox")
        let original = Data("Existing complete archive".utf8)
        try original.write(to: target)
        await #expect(throws: (any Error).self) {
            _ = try await MailFolderExporter(backend: backend, sourceID: fixture.source, folder: fixture.folder)
                .export(to: target, format: .mbox)
        }
        #expect(try Data(contentsOf: target) == original)
    }

    @Test("a failed body fetch cannot replace an existing archive")
    func failedFetchDoesNotPublish() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("brev-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = FolderExportFixture()
        await fixture.failSecondMessage()
        let backend = fixture.backend()
        try await backend.connect()
        let target = directory.appendingPathComponent("Inbox.mbox")
        let original = Data("Existing archive".utf8)
        try original.write(to: target)
        await #expect(throws: MailFolderExportError.self) {
            _ = try await MailFolderExporter(backend: backend, sourceID: fixture.source, folder: fixture.folder)
                .export(to: target, format: .mbox)
        }
        #expect(try Data(contentsOf: target) == original)
    }

    @Test("losing the server on a later page cannot publish a partial archive")
    func laterPageFailureDoesNotPublish() async throws {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("brev-export-\(UUID().uuidString).mbox")
        defer { try? FileManager.default.removeItem(at: target) }
        let original = Data("Existing complete archive".utf8)
        try original.write(to: target)
        let fixture = FolderExportFixture()
        await fixture.failSecondPage()
        let backend = fixture.backend(headerCache: InMemoryIMAPMailboxHeaderCache())
        try await backend.connect()
        await #expect(throws: (any Error).self) {
            _ = try await MailFolderExporter(backend: backend, sourceID: fixture.source, folder: fixture.folder)
                .export(to: target, format: .mbox)
        }
        #expect(await fixture.events == ["page:first", "body:1", "page:second"])
        #expect(try Data(contentsOf: target) == original)
    }

    @Test("EML export groups complete messages without replacing existing files")
    func emlPreservesBytesAndExistingOutput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("brev-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = directory.appendingPathComponent("Inbox Export")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let sentinel = existing.appendingPathComponent("keep.eml")
        try Data("Keep this export".utf8).write(to: sentinel)
        let fixture = FolderExportFixture()
        await fixture.setSubject("../" + String(repeating: "👨‍👩‍👧‍👦", count: 100))
        let backend = fixture.backend()
        try await backend.connect()
        let result = try await MailFolderExporter(backend: backend, sourceID: fixture.source, folder: fixture.folder)
            .export(to: directory, format: .emlDirectory)
        #expect(result.url.lastPathComponent == "Inbox Export (2)")
        #expect(result.messageCount == 2)
        let files = try FileManager.default.contentsOfDirectory(at: result.url, includingPropertiesForKeys: nil)
        #expect(files.count == 2)
        #expect(files.allSatisfy { $0.lastPathComponent.utf8.count <= 255 && $0.pathExtension == "eml" })
        let contents = try Set(files.map { try Data(contentsOf: $0) })
        #expect(contents == Set([FolderExportFixture.raw(1), FolderExportFixture.raw(2)]))
        #expect(try Data(contentsOf: sentinel) == Data("Keep this export".utf8))
    }

    @Test("folder-picker exports cannot replace an existing archive without overwrite consent")
    func unapprovedReplacementIsRejected() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("brev-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = FolderExportFixture()
        let backend = fixture.backend()
        try await backend.connect()
        let target = directory.appendingPathComponent("Inbox.mbox")
        let original = Data("Keep existing".utf8)
        try original.write(to: target)
        await #expect(throws: (any Error).self) {
            _ = try await MailFolderExporter(backend: backend, sourceID: fixture.source, folder: fixture.folder)
                .export(to: target, format: .mbox, replacingExistingFile: false)
        }
        #expect(try Data(contentsOf: target) == original)
    }
}

private actor FolderExportFixture {
    nonisolated let account = BrevAccount(id: "export", displayName: "Export", emailAddress: "export@example.org")
    nonisolated let source = MailSourceID(accountID: "export", mailboxID: "export")
    nonisolated let folder = Folder(id: "INBOX", name: "Inbox", role: .inbox)
    private(set) var events: [String] = []
    private var failsSecond = false
    private var failsSecondPage = false
    private var subject = "Same subject"
    func setSubject(_ value: String) { subject = value }
    func failSecondMessage() { failsSecond = true }
    func failSecondPage() { failsSecondPage = true }

    nonisolated func backend(headerCache: (any IMAPMailboxHeaderCache)? = nil,
                             sourceCache: (any IMAPMessageSourceCache)? = nil) -> IMAPSMTPBackend {
        let configuration = IMAPAccountConfiguration(
            accountID: account.id, emailAddress: account.emailAddress, displayName: account.displayName,
            incoming: MailServerSettings(
                kind: .imap,
                host: "imap.example.org",
                port: 993,
                tlsMode: .implicit,
                authentication: .password
            ),
            outgoing: MailServerSettings(
                kind: .smtp,
                host: "smtp.example.org",
                port: 587,
                tlsMode: .startTLS,
                authentication: .password
            ),
            credentialID: account.id
        )
        let credential = MailAccountCredential(incomingUsername: account.emailAddress, outgoingUsername: account.emailAddress,
                                               secret: "fixture", authentication: .password)
        return IMAPSMTPBackend(account: account, configuration: configuration, credential: credential,
                               listFolders: { _, _ in [IMAPFolderListing(
                                   path: "INBOX",
                                   displayName: "Inbox",
                                   delimiter: "/",
                                   flags: [],
                                   role: .inbox
                               )] },
                               listMessages: { _, _, _, token, _ in try await self.page(token) },
                               fetchMessageSource: { _, _, _, uid in try await self.message(uid) },
                               headerCache: headerCache, sourceCache: sourceCache)
    }

    func page(_ token: String?) throws -> IMAPMessageListingPage {
        events.append("page:\(token ?? "first")")
        if token == "second", failsSecondPage { throw MailBackendError.notConnected }
        if token == "second" { return IMAPMessageListingPage(messages: [], nextPageToken: "third") }
        let uid = token == nil ? 1 : 2
        let listing = IMAPMessageListing(uid: uid, messageID: "<original-\(uid)@example.org>", subject: subject,
                                         from: .init(email: "sender@example.org"), to: [.init(email: account.emailAddress)],
                                         cc: [], bcc: [],
                                         date: Date(timeIntervalSince1970: 0), isRead: false, isFlagged: false, isAnswered: false)
        return IMAPMessageListingPage(messages: [listing], nextPageToken: token == nil ? "second" : nil)
    }

    func message(_ uid: Int) throws -> IMAPMessageSource {
        events.append("body:\(uid)")
        if failsSecond && uid == 2 { throw MailFolderExportError.emptyMessage }
        return IMAPMessageSource(uid: uid, rawMessageData: Self.raw(uid))
    }

    static func raw(_ uid: Int) -> Data {
        if uid == 2 {
            return Data("Message-ID: <original-2@example.org>\r\nContent-Type: text/plain; charset=iso-8859-1\r\n\r\n".utf8)
                + Data([0xE5, 0xF8, 0xE6]) + Data("\r\n".utf8)
        }
        return Data(("Message-ID: <original-1@example.org>\r\nMIME-Version: 1.0\r\n"
                + "Content-Type: multipart/mixed; boundary=export\r\n\r\n--export\r\n"
                + "Content-Type: application/octet-stream\r\nContent-Disposition: attachment; filename=bytes.bin\r\n"
                + "Content-Transfer-Encoding: base64\r\n\r\nAAECAwQ=\r\n--export--\r\n").utf8)
    }
}
