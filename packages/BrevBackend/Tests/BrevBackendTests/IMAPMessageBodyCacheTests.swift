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

@Suite("IMAP structured body cache")
struct IMAPMessageBodyCacheTests {
    @Test("file cache persists structured bodies and removes a folder scope")
    func fileCacheRoundTripAndFolderRemoval() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = FileIMAPMessageBodyCache(rootDirectory: root)
        let body = MessageBody(messageID: "INBOX:43", html: "<p>Hello</p>")

        await cache.setBody(body, accountID: "account", messageID: body.messageID)

        #expect(await cache.body(accountID: "account", messageID: body.messageID) == body)
        await cache.removeBodies(inFolder: "INBOX", accountID: "account")
        #expect(await cache.body(accountID: "account", messageID: body.messageID) == nil)
    }

    @Test("file cache keeps byte-budget eviction correct across repeated writes")
    func fileCacheKeepsByteBudgetEvictionCorrectAcrossRepeatedWrites() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = FileIMAPMessageBodyCache(rootDirectory: root, maximumAccountSizeBytes: 12000)
        let first = MessageBody(messageID: "INBOX:1", plainText: String(repeating: "a", count: 5000))
        let second = MessageBody(messageID: "INBOX:2", plainText: String(repeating: "b", count: 5000))
        let third = MessageBody(messageID: "INBOX:3", plainText: String(repeating: "c", count: 5000))

        await cache.setBody(first, accountID: "account", messageID: first.messageID)
        try await Task.sleep(nanoseconds: 20_000_000)
        await cache.setBody(second, accountID: "account", messageID: second.messageID)
        try await Task.sleep(nanoseconds: 20_000_000)
        await cache.setBody(third, accountID: "account", messageID: third.messageID)

        #expect(await cache.body(accountID: "account", messageID: first.messageID) == nil)
        #expect(await cache.body(accountID: "account", messageID: second.messageID) == second)
        #expect(await cache.body(accountID: "account", messageID: third.messageID) == third)
        #expect(cache.sizeBytes(accountID: "account") <= 12000)
    }

    @Test("backend prefers and caches structured bodies before full raw source")
    func backendPrefersStructuredBody() async throws {
        let recorder = StructuredBodyFetchRecorder()
        let cache = InMemoryIMAPMessageBodyCache()
        let backend = IMAPSMTPBackend(
            account: BrevAccount(id: "account", displayName: "Account", emailAddress: "person@example.org"),
            configuration: IMAPAccountConfiguration(
                accountID: "account",
                emailAddress: "person@example.org",
                displayName: "Account",
                incoming: MailServerSettings(kind: .imap, host: "imap.example.org", port: 993, tlsMode: .implicit),
                outgoing: MailServerSettings(kind: .smtp, host: "smtp.example.org", port: 465, tlsMode: .implicit),
                credentialID: "credential"
            ),
            credential: MailAccountCredential(
                incomingUsername: "person@example.org",
                outgoingUsername: "person@example.org",
                secret: "secret",
                authentication: .password
            ),
            listFolders: { _, _ in [] },
            fetchMessageSource: { _, _, _, _ in
                throw MailBackendError.backendSpecific(message: "full source should not be fetched")
            },
            fetchMessageBody: { _, _, _, _ in
                await recorder.fetch()
            },
            bodyCache: cache
        )
        try await backend.connect()

        let first = try await backend.body(for: "INBOX:43")
        let second = try await backend.body(for: "INBOX:43")

        #expect(first.plainText == "Fast body")
        #expect(second == first)
        #expect(await recorder.fetchCount == 1)
    }

    @Test("backend routes structured attachment resources to a part-only fetch")
    func backendFetchesDeferredAttachmentPart() async throws {
        let partRecorder = StructuredPartFetchRecorder()
        let backend = IMAPSMTPBackend(
            account: BrevAccount(id: "account", displayName: "Account", emailAddress: "person@example.org"),
            configuration: IMAPAccountConfiguration(
                accountID: "account",
                emailAddress: "person@example.org",
                displayName: "Account",
                incoming: MailServerSettings(kind: .imap, host: "imap.example.org", port: 993, tlsMode: .implicit),
                outgoing: MailServerSettings(kind: .smtp, host: "smtp.example.org", port: 465, tlsMode: .implicit),
                credentialID: "credential"
            ),
            credential: MailAccountCredential(
                incomingUsername: "person@example.org",
                outgoingUsername: "person@example.org",
                secret: "secret",
                authentication: .password
            ),
            listFolders: { _, _ in [] },
            fetchMessagePart: { _, _, folderID, uid, section, encoding in
                await partRecorder.fetch(folderID: folderID, uid: uid, section: section, encoding: encoding)
            }
        )
        try await backend.connect()
        let reference = IMAPMessagePartReference(
            messageID: "INBOX:43",
            section: "2",
            transferEncoding: "base64"
        )
        let attachment = Attachment(
            id: "INBOX:43:attachment:1",
            name: "report.pdf",
            mimeType: "application/pdf",
            sizeBytes: 5,
            resource: reference.resource
        )

        #expect(try await backend.downloadAttachment(attachment) == Data("Hello".utf8))
        #expect(await partRecorder.lastRequest == StructuredPartFetchRecorder.Request(
            folderID: "INBOX",
            uid: 43,
            section: "2",
            encoding: "base64"
        ))
    }
}

private actor StructuredBodyFetchRecorder {
    private(set) var fetchCount = 0

    func fetch() -> MessageBody {
        fetchCount += 1
        return MessageBody(messageID: "INBOX:43", plainText: "Fast body")
    }
}

private actor StructuredPartFetchRecorder {
    struct Request: Equatable {
        let folderID: Folder.ID
        let uid: Int
        let section: String
        let encoding: String
    }

    private(set) var lastRequest: Request?

    func fetch(folderID: Folder.ID, uid: Int, section: String, encoding: String) -> Data {
        lastRequest = Request(folderID: folderID, uid: uid, section: section, encoding: encoding)
        return Data("Hello".utf8)
    }
}
