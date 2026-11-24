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

    @Test("offline cached search matches cached bodies and indexed attachments while respecting label and metadata filters")
    func offlineCachedSearchMatchesBodiesAndIndexedAttachments() async throws {
        let store = InMemoryGmailAccountStore()
        let index = StubLocalSearchIndex()
        let labels = [
            GmailLabel(id: "INBOX", name: "INBOX", type: "system"),
            GmailLabel(id: "TRASH", name: "TRASH", type: "system"),
            GmailLabel(id: "SPAM", name: "SPAM", type: "system"),
            GmailLabel(id: "Label_Work", name: "Work", type: "user")
        ]

        let bodyMessage = GmailMessage(
            id: "msg-body",
            threadID: "t-body",
            labelIDs: ["INBOX"],
            snippet: "Generic preview",
            internalDate: "1750000000000",
            payload: GmailMessagePart(
                partID: "",
                mimeType: "text/plain",
                filename: nil,
                headers: [
                    GmailMessageHeader(name: "From", value: "Alice <alice@example.org>"),
                    GmailMessageHeader(name: "Subject", value: "Status update")
                ],
                body: GmailMessageBody(
                    size: 40,
                    data: Data("Hidden body-only token: aurora-borealis-77".utf8)
                        .base64EncodedString()
                        .replacingOccurrences(of: "+", with: "-")
                        .replacingOccurrences(of: "/", with: "_")
                        .replacingOccurrences(of: "=", with: ""),
                    attachmentID: nil
                ),
                parts: []
            )
        )
        let attachmentMessage = GmailMessage(
            id: "msg-att",
            threadID: "t-att",
            labelIDs: ["INBOX", "Label_Work"],
            snippet: "See attached",
            internalDate: "1750000001000",
            payload: GmailMessagePart(
                partID: "",
                mimeType: "text/plain",
                filename: nil,
                headers: [
                    GmailMessageHeader(name: "From", value: "Bob <bob@example.org>"),
                    GmailMessageHeader(name: "Subject", value: "Contract")
                ],
                body: nil,
                parts: []
            )
        )
        let trashedDualLabelMessage = GmailMessage(
            id: "msg-trash-work",
            threadID: "t-trash",
            labelIDs: ["Label_Work", "TRASH"],
            snippet: "Old draft",
            internalDate: "1750000002000",
            payload: GmailMessagePart(
                partID: "",
                mimeType: "text/plain",
                filename: nil,
                headers: [
                    GmailMessageHeader(name: "From", value: "Bob <bob@example.org>"),
                    GmailMessageHeader(name: "Subject", value: "Deleted contract")
                ],
                body: nil,
                parts: []
            )
        )

        try await store.replaceSnapshot(GmailAccountSnapshot(
            accountID: Self.account.id,
            state: GmailAccountState(
                accountID: Self.account.id,
                emailAddress: Self.account.emailAddress,
                historyID: "1"
            ),
            labels: labels,
            messages: [bodyMessage, attachmentMessage, trashedDualLabelMessage]
        ))
        try await index.indexAttachmentText(
            accountID: Self.account.id,
            messageID: "msg-att",
            folderID: "INBOX",
            attachmentID: "att-1",
            name: "spec.pdf",
            text: "Confidential solstice-clause-88 inside PDF"
        )
        try await index.indexAttachmentText(
            accountID: Self.account.id,
            messageID: "msg-trash-work",
            folderID: "Label_Work",
            attachmentID: "att-trash",
            name: "old.pdf",
            text: "Confidential solstice-clause-88 inside trashed PDF"
        )

        let transport = OfflineSearchTransport(labels: labels)
        let backend = GmailAPIBackend(
            account: Self.account,
            transport: transport,
            store: store,
            localSearchIndex: index
        )
        try await backend.connect()

        // Body-only offline hit.
        let bodyHits: [MessageHeader] = try await backend.search(SearchQuery(text: "aurora-borealis-77"))
        #expect(bodyHits.map(\.id) == ["msg-body"])

        // Metadata filter still excludes body hit when sender doesn't match.
        let wrongSender: [MessageHeader] = try await backend.search(SearchQuery(
            text: "aurora-borealis-77",
            from: "bob@example.org"
        ))
        #expect(wrongSender.isEmpty)

        // Indexed-attachment-only offline hit respects ALL_MAIL Trash exclusion.
        let attHitsAllMail: [MessageHeader] = try await backend.search(SearchQuery(
            text: "solstice-clause-88",
            folderID: "ALL_MAIL"
        ))
        #expect(attHitsAllMail.map(\.id) == ["msg-att"])

        // Custom label query exposes canonical \Trash membership on dual-labeled messages.
        let workFolder = Folder(id: "Label_Work", name: "Work", role: .custom)
        let mailbox = try await backend.currentMailbox()
        let workHeaders = try await backend.cachedMessageHeaders(
            in: workFolder,
            sourceID: backend.sourceID(for: mailbox)
        )
        let dualLabeled = try #require(workHeaders.first { $0.id == "msg-trash-work" })
        #expect(dualLabeled.labels.contains { $0.caseInsensitiveCompare("\\Trash") == .orderedSame })
    }
}

/// Transport that allows `connect()` (profile/labels) and fails `listMessages` with an
/// offline URL error so `GmailAPIBackend.search` exercises its local `cachedSearch` fallback.
private actor OfflineSearchTransport: GmailAPITransporting {
    private let labels: [GmailLabel]
    init(labels: [GmailLabel]) { self.labels = labels }
    func profile() async throws -> GmailProfile {
        GmailProfile(emailAddress: "person@example.org", messagesTotal: 3, threadsTotal: 3, historyID: "1")
    }

    func listLabels() async throws -> [GmailLabel] { labels }
    func listMessages(
        labelID _: String?,
        query _: String?,
        pageToken _: String?,
        maxResults _: Int
    ) async throws -> GmailMessagePage {
        throw URLError(.notConnectedToInternet)
    }

    func getMessage(messageID _: String, format _: GmailMessageFormat) async throws -> GmailMessage {
        throw URLError(.notConnectedToInternet)
    }

    func getThread(threadID _: String, metadataHeaders _: [String]) async throws -> GmailThread {
        throw URLError(.notConnectedToInternet)
    }

    func getAttachment(messageID _: String, attachmentID _: String) async throws -> GmailAttachment {
        throw URLError(.notConnectedToInternet)
    }

    func createDraft(rawMIME _: String, threadID _: String?) async throws -> GmailDraft {
        throw URLError(.notConnectedToInternet)
    }

    func updateDraft(id _: String, rawMIME _: String, threadID _: String?) async throws -> GmailDraft {
        throw URLError(.notConnectedToInternet)
    }

    func deleteDraft(id _: String) async throws { throw URLError(.notConnectedToInternet) }
    func sendDraft(id _: String) async throws -> GmailMessage { throw URLError(.notConnectedToInternet) }
    func sendMessage(rawMIME _: String, threadID _: String?) async throws -> GmailMessage {
        throw URLError(.notConnectedToInternet)
    }

    func listSendAs() async throws -> [GmailSendAs] { [] }
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

/// Minimal local-index stub supporting attachment FTS storage and lookup.
private actor StubLocalSearchIndex: MailLocalSearchIndex {
    private var attachments: [String: [(attachmentID: String, text: String)]] = [:]

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

    func indexAttachmentText(
        accountID _: String,
        messageID: MessageHeader.ID,
        folderID _: Folder.ID,
        attachmentID: String,
        name _: String,
        text: String
    ) async throws {
        attachments[messageID, default: []].append((attachmentID, text))
    }

    func indexedAttachmentIDs(accountID _: String) async -> [MessageHeader.ID: Set<String>] {
        attachments.mapValues { Set($0.map(\.attachmentID)) }
    }

    func matchingAttachmentMessageIDs(
        for query: SearchQuery,
        account _: BrevAccount
    ) async -> Set<MessageHeader.ID> {
        var hits = Set<MessageHeader.ID>()
        for (messageID, entries) in attachments {
            if entries.contains(where: { query.matchesText($0.text) }) {
                hits.insert(messageID)
            }
        }
        return hits
    }
}
