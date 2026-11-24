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

/// In-memory `MailLocalSearchIndex` recording `indexBodyText` writes and supporting
/// body-text search for IMAP background indexing verification.
private actor RecordingBodySearchIndex: MailLocalSearchIndex {
    private var headersByID: [MessageHeader.ID: MessageHeader] = [:]
    private var bodyTextByID: [MessageHeader.ID: String] = [:]

    func cachedHeaders(
        for folder: Folder,
        account _: BrevAccount,
        pageToken _: String?
    ) async -> (headers: [MessageHeader], nextPageToken: String?)? {
        let matching = headersByID.values.filter { $0.folderID == folder.id }
        return matching.isEmpty ? nil : (Array(matching), nil)
    }

    func cachedRawMessage(for _: MessageHeader.ID, account _: BrevAccount) async -> Data? { nil }
    func storeRawMessage(_: Data, for _: MessageHeader.ID, account _: BrevAccount) async {}

    func indexBodyText(_ bodyText: String, for messageID: MessageHeader.ID, account _: BrevAccount) async {
        bodyTextByID[messageID] = bodyText
    }

    func search(_ query: SearchQuery, account _: BrevAccount, limit: Int) async -> [MessageHeader] {
        var results: [MessageHeader] = []
        for header in headersByID.values {
            if query.matches(header) {
                results.append(header)
            } else if query.matchesMetadata(header),
                      let text = bodyTextByID[header.id],
                      query.matchesText(text) {
                results.append(header)
            }
            if results.count >= limit { break }
        }
        return results
    }

    func storeHeaders(_ headers: [MessageHeader], account _: BrevAccount) async {
        for header in headers {
            headersByID[header.id] = header
        }
    }

    func deleteMessages(_ messageIDs: [MessageHeader.ID], account _: BrevAccount) async {
        for id in messageIDs {
            headersByID.removeValue(forKey: id)
            bodyTextByID.removeValue(forKey: id)
        }
    }

    func deleteRawMessages(_: [MessageHeader.ID], account _: BrevAccount) async {}
    func deleteRawMessages(inFolder _: Folder.ID, account _: BrevAccount) async {}
    func deleteRawMessages(inFolder _: Folder.ID, except _: Set<MessageHeader.ID>, account _: BrevAccount) async {}
    func clearFolder(folderID _: Folder.ID, account _: BrevAccount) async {}
    func clearAccount(_: BrevAccount) async {}
    func metrics(for _: BrevAccount) async -> LocalSearchIndexMetrics? { nil }
}

private final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.withLock { value += 1 }
    }

    var count: Int {
        lock.withLock { value }
    }
}

@Suite("IMAP background body indexing")
struct IMAPBackgroundIndexingTests {
    private static let account = BrevAccount(
        id: "imap-smtp:ada@example.org",
        displayName: "Ada",
        emailAddress: "ada@example.org"
    )

    private static let configuration = IMAPAccountConfiguration(
        accountID: "imap-smtp:ada@example.org",
        emailAddress: "ada@example.org",
        displayName: "Ada",
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
        credentialID: "imap-smtp:ada@example.org"
    )

    private static let credential = MailAccountCredential(
        incomingUsername: "ada@example.org",
        outgoingUsername: "ada@example.org",
        secret: "secret",
        authentication: .password
    )

    private static let inboxListing = IMAPFolderListing(
        path: "INBOX",
        displayName: "Inbox",
        delimiter: "/",
        flags: [],
        role: .inbox
    )

    @Test("structured background body fetch persists body-only words to localSearchIndex without raw-source fetch")
    func structuredFetchIndexesBodyTextForOfflineSearch() async throws {
        let index = RecordingBodySearchIndex()
        let rawSourceCalls = AtomicCounter()
        let structuredCalls = AtomicCounter()

        let header = MessageHeader(
            id: "INBOX:101",
            threadID: "t-101",
            folderID: "INBOX",
            from: Correspondent(name: "Grace", email: "grace@example.org"),
            subject: "Quarterly notes",
            snippet: "Short preview",
            date: Date(timeIntervalSince1970: 1_750_000_000)
        )
        await index.storeHeaders([header], account: Self.account)

        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [Self.inboxListing] },
            fetchMessageSource: { _, _, _, _ in
                rawSourceCalls.increment()
                return IMAPMessageSource(uid: 101, rawMessage: "Raw")
            },
            fetchMessageBody: { _, _, _, _ in
                structuredCalls.increment()
                return MessageBody(
                    messageID: "INBOX:101",
                    html: "<p>HTML alternative token: <strong>albatross-deck-42</strong></p>",
                    plainText: "Hidden body-only keyword: zeppelin-horizon-99.",
                    attachments: [
                        Attachment(
                            id: "att-floorplan",
                            name: "floorplan.png",
                            mimeType: "image/png",
                            sizeBytes: 2048
                        )
                    ]
                )
            },
            localSearchIndex: index
        )
        try await backend.connect()

        let mailbox = try await backend.currentMailbox()
        let sourceID = backend.sourceID(for: mailbox)

        // Before background indexing, offline search misses the body-only keyword.
        let before = await index.search(SearchQuery(text: "zeppelin-horizon-99"), account: Self.account, limit: 10)
        #expect(before.isEmpty)

        // Run background body indexing through the capability-driven extension seam.
        let service = try #require(backend.extensionService(BackgroundBodyIndexing.self))
        let body = try await service.indexBackgroundBody(
            for: "INBOX:101",
            sourceID: sourceID,
            maxFallbackSourceBytes: 10 * 1024 * 1024
        )
        #expect(body?.plainText?.contains("zeppelin-horizon-99") == true)
        #expect(structuredCalls.count == 1)
        #expect(rawSourceCalls.count == 0)

        // Offline local search now matches plain text, stripped HTML alternative, and attachment filename.
        let plainResults: [MessageHeader] = try await backend.search(SearchQuery(text: "zeppelin-horizon-99"))
        #expect(plainResults.map(\.id) == ["INBOX:101"])
        let htmlResults: [MessageHeader] = try await backend.search(SearchQuery(text: "albatross-deck-42"))
        #expect(htmlResults.map(\.id) == ["INBOX:101"])
        let filenameResults: [MessageHeader] = try await backend.search(SearchQuery(text: "floorplan.png"))
        #expect(filenameResults.map(\.id) == ["INBOX:101"])
    }

    @Test("structured fetch failure in background indexing skips unbounded full-source fallback")
    func structuredFetchFailureSkipsFullSourceFallback() async throws {
        let rawSourceCalls = AtomicCounter()
        let structuredCalls = AtomicCounter()

        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [Self.inboxListing] },
            fetchMessageSource: { _, _, _, _ in
                rawSourceCalls.increment()
                return IMAPMessageSource(uid: 202, rawMessage: "Huge raw message")
            },
            fetchMessageBody: { _, _, _, _ in
                structuredCalls.increment()
                throw MailBackendError.backendSpecific(message: "malformed BODYSTRUCTURE")
            }
        )
        try await backend.connect()

        let mailbox = try await backend.currentMailbox()
        let sourceID = backend.sourceID(for: mailbox)
        let service = try #require(backend.extensionService(BackgroundBodyIndexing.self))

        let result = try await service.indexBackgroundBody(
            for: "INBOX:202",
            sourceID: sourceID,
            maxFallbackSourceBytes: 10 * 1024 * 1024
        )
        #expect(result == nil)
        #expect(structuredCalls.count == 1)
        #expect(rawSourceCalls.count == 0)
    }

    @Test("background body indexing does not cancel in-flight folder refreshes")
    func backgroundBodyIndexingDoesNotCancelFolderRefresh() async throws {
        let refreshCancelled = AtomicCounter()
        let refreshCompleted = AtomicCounter()

        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [Self.inboxListing] },
            listMessages: { _, _, _, _, _ in
                do {
                    try await Task.sleep(for: .milliseconds(80))
                } catch is CancellationError {
                    refreshCancelled.increment()
                    throw CancellationError()
                }
                refreshCompleted.increment()
                return IMAPMessageListingPage(messages: [], nextPageToken: nil)
            },
            fetchMessageBody: { _, _, _, _ in
                MessageBody(messageID: "INBOX:303", html: nil, plainText: "background body", attachments: [])
            }
        )
        try await backend.connect()

        let mailbox = try await backend.currentMailbox()
        let sourceID = backend.sourceID(for: mailbox)
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let service = try #require(backend.extensionService(BackgroundBodyIndexing.self))

        async let refreshTask: Void = backend.refresh(folder: inbox)
        try await Task.sleep(for: .milliseconds(15))
        _ = try await service.indexBackgroundBody(
            for: "INBOX:303",
            sourceID: sourceID,
            maxFallbackSourceBytes: 10 * 1024 * 1024
        )
        try await refreshTask

        #expect(refreshCancelled.count == 0)
        #expect(refreshCompleted.count == 1)
    }
}
