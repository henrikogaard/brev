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

@Suite("Original message bytes in the local index")
struct OriginalMessageCacheTests {
    @Test("index-only original bytes survive offline restart without trusting legacy entries")
    func indexOnlySourceSurvivesRestart() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-original-index-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let raw = Data("Content-Type: text/plain; charset=iso-8859-1\r\n\r\n".utf8) + Data([0xE5, 0xF8, 0xE6])
        let engine = try BrevSyncEngine(databaseURL: url)
        await engine.storeRawMessage(Data("Legacy decoded text".utf8), for: "INBOX:43", account: Self.account)
        let backend = Self.backend(index: engine, raw: raw)
        try await backend.connect()
        #expect(try await backend.rawMessageData(for: "INBOX:43", sourceID: Self.source) == raw)
        await backend.disconnect()
        #expect(try await backend.rawMessageData(for: "INBOX:43", sourceID: Self.source) == raw)

        let reopenedIndex = try BrevSyncEngine(databaseURL: url)
        let offline = Self.backend(index: reopenedIndex, raw: raw)
        #expect(try await offline.rawMessageData(for: "INBOX:43", sourceID: Self.source) == raw)
        await reopenedIndex.storeRawMessage(Data("A later legacy write".utf8), for: "INBOX:43", account: Self.account)
        await #expect(throws: MailBackendError.self) {
            _ = try await offline.rawMessageData(for: "INBOX:43", sourceID: Self.source)
        }
    }

    @Test("original-byte provenance resets on legacy overwrite and follows cache deletion", arguments: [false, true])
    func provenanceFollowsCacheLifecycle(sqlite: Bool) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-provenance-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let store: any SyncStoreProtocol = sqlite ? try SQLiteSyncStore(databaseURL: url) : InMemorySyncStore()
        try await store.ensureAccount(id: Self.account.id)
        let raw = Data([0xE5, 0xF8, 0xE6])
        try await store.storeOriginalBody(raw, accountID: Self.account.id, messageID: "INBOX:43")
        #expect(await store.originalBody(accountID: Self.account.id, messageID: "INBOX:43") == raw)
        try await store.storeBody(Data("Reconstructed".utf8), accountID: Self.account.id, messageID: "INBOX:43")
        #expect(await store.originalBody(accountID: Self.account.id, messageID: "INBOX:43") == nil)
        try await store.storeOriginalBody(raw, accountID: Self.account.id, messageID: "INBOX:44")
        try await store.deleteBodies(messageIDs: ["INBOX:44"], accountID: Self.account.id)
        #expect(await store.originalBody(accountID: Self.account.id, messageID: "INBOX:44") == nil)
        try await store.storeOriginalBody(raw, accountID: Self.account.id, messageID: "INBOX:45")
        try await store.clearAccount(id: Self.account.id)
        #expect(await store.originalBody(accountID: Self.account.id, messageID: "INBOX:45") == nil)
    }

    private static let account = BrevAccount(
        id: "imap-smtp:bytes@example.org",
        displayName: "Bytes",
        emailAddress: "bytes@example.org"
    )
    private static let source = MailSourceID(accountID: account.id, mailboxID: account.id)

    private static func backend(index: BrevSyncEngine, raw: Data) -> IMAPSMTPBackend {
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
                               fetchMessageSource: { _, _, _, uid in IMAPMessageSource(uid: uid, rawMessageData: raw) },
                               localSearchIndex: index)
    }
}
