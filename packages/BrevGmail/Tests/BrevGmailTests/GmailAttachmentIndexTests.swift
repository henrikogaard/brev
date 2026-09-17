/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the conditions of the LICENSE file.
 */

import BrevBackend
@testable import BrevGmail
import Foundation
import Testing

/// `.localAttachmentIndex` (ADR-0078 §8) is advertised only when a local
/// search index is wired; every indexing control in the UI gates on it.
@Suite("Gmail attachment index capability")
struct GmailAttachmentIndexTests {
    private static let account = BrevAccount(
        id: "gmail:person@example.org",
        displayName: "Person",
        emailAddress: "person@example.org"
    )

    @Test("capability is present with a local index, absent without")
    func capabilityGating() {
        let withIndex = GmailAPIBackend(
            account: Self.account,
            transport: ThrowingTransport(),
            store: InMemoryGmailAccountStore(),
            localSearchIndex: StubLocalSearchIndex()
        )
        #expect(withIndex.extendedCapabilities.contains(.localAttachmentIndex))

        let without = GmailAPIBackend(
            account: Self.account,
            transport: ThrowingTransport(),
            store: InMemoryGmailAccountStore()
        )
        #expect(!without.extendedCapabilities.contains(.localAttachmentIndex))
    }
}

/// Transport that never performs network I/O in these tests.
private actor ThrowingTransport: GmailAPITransporting {
    func profile() async throws -> GmailProfile { throw GmailAPIError.invalidRequest }
    func listLabels() async throws -> [GmailLabel] { throw GmailAPIError.invalidRequest }
    func listMessages(
        labelID: String?,
        query: String?,
        pageToken: String?,
        maxResults: Int
    ) async throws -> GmailMessagePage { throw GmailAPIError.invalidRequest }
    func getMessage(messageID: String, format: GmailMessageFormat) async throws -> GmailMessage {
        throw GmailAPIError.invalidRequest
    }

    func getThread(threadID: String, metadataHeaders: [String]) async throws -> GmailThread {
        throw GmailAPIError.invalidRequest
    }

    func getAttachment(messageID: String, attachmentID: String) async throws -> GmailAttachment {
        throw GmailAPIError.invalidRequest
    }

    func createDraft(rawMIME: String, threadID: String?) async throws -> GmailDraft {
        throw GmailAPIError.invalidRequest
    }

    func updateDraft(id: String, rawMIME: String, threadID: String?) async throws -> GmailDraft {
        throw GmailAPIError.invalidRequest
    }

    func deleteDraft(id: String) async throws { throw GmailAPIError.invalidRequest }
    func sendDraft(id: String) async throws -> GmailMessage { throw GmailAPIError.invalidRequest }
    func sendMessage(rawMIME: String, threadID: String?) async throws -> GmailMessage {
        throw GmailAPIError.invalidRequest
    }

    func listSendAs() async throws -> [GmailSendAs] { throw GmailAPIError.invalidRequest }
}

/// Minimal local-index stub; the capability check only needs the protocol.
private actor StubLocalSearchIndex: MailLocalSearchIndex {
    func cachedHeaders(
        for folder: Folder, account: BrevAccount, pageToken: String?
    ) async -> (headers: [MessageHeader], nextPageToken: String?)? { nil }
    func cachedRawMessage(for messageID: MessageHeader.ID, account: BrevAccount) async -> Data? { nil }
    func storeRawMessage(_ data: Data, for messageID: MessageHeader.ID, account: BrevAccount) async {}
    func search(_ query: SearchQuery, account: BrevAccount, limit: Int) async -> [MessageHeader] { [] }
    func storeHeaders(_ newHeaders: [MessageHeader], account: BrevAccount) async {}
    func deleteMessages(_ messageIDs: [MessageHeader.ID], account: BrevAccount) async {}
    func deleteRawMessages(_ messageIDs: [MessageHeader.ID], account: BrevAccount) async {}
    func deleteRawMessages(inFolder folderID: Folder.ID, account: BrevAccount) async {}
    func deleteRawMessages(
        inFolder folderID: Folder.ID,
        except exceptMessageIDs: Set<MessageHeader.ID>,
        account: BrevAccount
    ) async {}
    func clearFolder(folderID: Folder.ID, account: BrevAccount) async {}
    func clearAccount(_ account: BrevAccount) async {}
    func metrics(for account: BrevAccount) async -> LocalSearchIndexMetrics? { nil }
}
