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
@testable import BrevGmail
import Foundation
import Testing

@Suite("Gmail API read backend")
struct GmailAPIBackendTests {
    @Test("cached folder pagination returns every row once across multiple pages")
    func cachedPaginationDoesNotApplyOffsetTwice() async throws {
        let transport = StubGmailTransport(labels: [GmailLabel(id: "INBOX", name: "Inbox", type: "system")])
        let store = InMemoryGmailAccountStore()
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        try await backend.connect()
        let messages = (0 ..< 120).map { Self.message(id: String(format: "m%03d", $0), threadID: "thread", labels: ["INBOX"]) }
        try await store.replaceSnapshot(GmailAccountSnapshot(
            accountID: Self.account.id,
            state: GmailAccountState(accountID: Self.account.id, emailAddress: Self.account.emailAddress, lastFullSyncAt: Date()),
            labels: [GmailLabel(id: "INBOX", name: "Inbox", type: "system")],
            messages: messages
        ))
        await transport.failListings()
        let folder = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let first = try await backend.messages(in: folder, pageToken: nil)
        let second = try await backend.messages(in: folder, pageToken: first.nextPageToken)
        let third = try await backend.messages(in: folder, pageToken: second.nextPageToken)
        #expect(first.headers.count == 50)
        #expect(second.headers.count == 50)
        #expect(third.headers.count == 20)
        #expect((first.headers + second.headers + third.headers).map(\.id) == messages.map(\.id))
        #expect(third.nextPageToken == nil)
    }

    @Test("folder rows fetch missing MIME data with bounded concurrency")
    func folderRowsUseConcurrentMetadata() async throws {
        let messages = (0 ..< 8).map { Self.message(id: "m\($0)", threadID: "t\($0)", labels: ["INBOX"]) }
        let transport = StubGmailTransport(
            labels: [GmailLabel(id: "INBOX", name: "Inbox", type: "system")],
            pages: [GmailMessagePage(messages: messages.map { GmailMessageReference(id: $0.id) })],
            messages: messages,
            messageDelay: 20_000_000
        )
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: InMemoryGmailAccountStore())
        try await backend.connect()
        let page = try await backend.messages(in: Folder(id: "INBOX", name: "Inbox", role: .inbox), pageToken: nil)
        #expect(page.headers.map(\.id) == messages.map(\.id))
        #expect(await transport.fullMessageRequestCount() == 8)
        #expect(await transport.maximumConcurrentRequests() > 1)
        #expect(await transport.maximumConcurrentRequests() <= 4)
    }

    @Test("cached folder rows remain readable when the remote listing fails")
    func cachedFolderSurvivesListingFailure() async throws {
        let transport = StubGmailTransport(labels: [GmailLabel(id: "INBOX", name: "Inbox", type: "system")])
        let store = InMemoryGmailAccountStore()
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        try await backend.connect()
        try await store.replaceSnapshot(GmailAccountSnapshot(
            accountID: Self.account.id,
            state: GmailAccountState(accountID: Self.account.id, emailAddress: Self.account.emailAddress, lastFullSyncAt: Date()),
            labels: [GmailLabel(id: "INBOX", name: "Inbox", type: "system")],
            messages: [Self.message(id: "cached", threadID: "thread", labels: ["INBOX"])]
        ))
        await transport.failListings()
        let page = try await backend.messages(in: Folder(id: "INBOX", name: "Inbox", role: .inbox), pageToken: nil)
        #expect(page.headers.map(\.id) == ["cached"])
        #expect(page.nextPageToken == nil)
    }

    @Test("maps Workspace labels, display identity, and native capabilities")
    func mapsWorkspaceLabelsAndCapabilities() async throws {
        let transport = StubGmailTransport(
            profile: GmailProfile(
                emailAddress: "henrik@example.work",
                historyID: "history-1"
            ),
            labels: [
                GmailLabel(id: "INBOX", name: "Inbox", type: "system", messagesUnread: 3),
                GmailLabel(id: "ALL_MAIL", name: "All Mail", type: "system"),
                GmailLabel(id: "label-projects", name: "Projects", type: "user")
            ]
        )
        let backend = GmailAPIBackend(
            account: Self.account,
            transport: transport,
            store: InMemoryGmailAccountStore()
        )
        let mailBackend: any MailBackend = backend

        try await mailBackend.connect()
        let folders = try await mailBackend.folders()
        let inbox = try #require(folders.first { $0.id == "INBOX" })
        let allMail = try #require(folders.first { $0.id == "ALL_MAIL" })

        #expect(inbox.role == .inbox)
        #expect(inbox.unreadCount == 3)
        #expect(allMail.role == .allMail)
        #expect(mailBackend.capabilities.contains(.providerAPI))
        #expect(mailBackend.capabilities.contains(.oauthAuth))
        #expect(mailBackend.capabilities.contains(.serverSideSearch))
        #expect(mailBackend.capabilities.contains(.serverSideThreading))
        #expect(mailBackend.capabilities.contains(.labels))
        #expect(mailBackend.capabilities.contains(.historyDeltaSync))
        #expect(try await mailBackend.currentMailbox().displayName == "Henrik Workspace")
    }

    @Test("lists each account-wide Gmail message once and preserves thread identity")
    func listsAccountWideMessagesWithoutDuplicates() async throws {
        let message = Self.message(
            id: "message-1",
            threadID: "thread-7",
            labels: ["INBOX", "label-projects"]
        )
        let transport = StubGmailTransport(
            labels: [GmailLabel(id: "INBOX", name: "Inbox", type: "system")],
            pages: [GmailMessagePage(
                messages: [
                    GmailMessageReference(id: "message-1", threadID: "thread-7"),
                    GmailMessageReference(id: "message-1", threadID: "thread-7")
                ]
            )],
            messages: [message]
        )
        let backend = GmailAPIBackend(
            account: Self.account,
            transport: transport,
            store: InMemoryGmailAccountStore()
        )
        let mailBackend: any MailBackend = backend
        try await mailBackend.connect()
        let folder = try #require(try await mailBackend.folders().first)

        let page = try await mailBackend.messages(in: folder, pageToken: nil)

        #expect(page.headers.count == 1)
        #expect(page.headers[0].id == "message-1")
        #expect(page.headers[0].threadID == "thread-7")
        #expect(page.headers[0].labels == ["\\Inbox", "label-projects"])
        #expect(page.nextPageToken == nil)
    }

    @Test("maps Gmail MIME parts and returns body from the store on a cache hit")
    func mapsBodyAndUsesCache() async throws {
        let message = Self.message(
            id: "message-2",
            threadID: "thread-2",
            labels: ["INBOX"],
            payload: GmailMessagePart(
                mimeType: "multipart/alternative",
                headers: [
                    GmailMessageHeader(name: "From", value: "Alice Example <alice@example.com>"),
                    GmailMessageHeader(name: "To", value: "Henrik <henrik@example.work>"),
                    GmailMessageHeader(name: "Subject", value: "Workspace update"),
                    GmailMessageHeader(name: "Date", value: "Tue, 25 Aug 2026 09:00:00 +0000"),
                    GmailMessageHeader(name: "Message-ID", value: "<message-2@example.com>")
                ],
                parts: [
                    GmailMessagePart(
                        partID: "plain",
                        mimeType: "text/plain",
                        body: GmailMessageBody(data: Self.base64URL("Hello from Gmail"))
                    ),
                    GmailMessagePart(
                        partID: "html",
                        mimeType: "text/html",
                        body: GmailMessageBody(data: Self.base64URL("<p>Hello from Gmail</p>"))
                    ),
                    GmailMessagePart(
                        partID: "attachment",
                        mimeType: "application/pdf",
                        filename: "invoice.pdf",
                        body: GmailMessageBody(size: 3)
                    )
                ]
            )
        )
        let transport = StubGmailTransport(
            labels: [GmailLabel(id: "INBOX", name: "Inbox", type: "system")],
            messages: [message]
        )
        let store = InMemoryGmailAccountStore()
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        let mailBackend: any MailBackend = backend
        try await mailBackend.connect()

        let first = try await mailBackend.body(for: "message-2")
        let second = try await mailBackend.body(for: "message-2")

        #expect(first.messageID == "message-2")
        #expect(first.plainText == "Hello from Gmail")
        #expect(first.html == "<p>Hello from Gmail</p>")
        #expect(first.attachments.map(\.name) == ["invoice.pdf"])
        #expect(second == first)
        #expect(await transport.fullMessageRequestCount() == 1)
    }

    @Test("upgrades a metadata-only cached message before building its body")
    func upgradesMetadataOnlyMessage() async throws {
        let fullMessage = Self.message(
            id: "message-upgrade",
            threadID: "thread-upgrade",
            labels: ["INBOX"],
            payload: GmailMessagePart(
                mimeType: "text/plain",
                body: GmailMessageBody(data: Self.base64URL("Fetched body"))
            )
        )
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(Self.snapshot(messages: [
            Self.message(id: "message-upgrade", threadID: "thread-upgrade", labels: ["INBOX"])
        ]))
        let transport = StubGmailTransport(
            labels: [GmailLabel(id: "INBOX", name: "Inbox", type: "system")],
            messages: [fullMessage]
        )
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        let mailBackend: any MailBackend = backend
        try await mailBackend.connect()

        let body = try await mailBackend.body(for: "message-upgrade")

        #expect(body.plainText == "Fetched body")
        #expect(await transport.fullMessageRequestCount() == 1)
        #expect(try await store.cachedBody(accountID: Self.account.id, messageID: "message-upgrade") == body)
    }

    @Test("upgrades a cached message whose payload is metadata-only headers")
    func upgradesMetadataPayloadMessage() async throws {
        // Label sync stores messages fetched with format=metadata: the payload
        // exists but carries only headers — no parts and no body data. Serving
        // it as the message body must trigger a full fetch, not return an
        // empty body without error.
        let fullMessage = Self.message(
            id: "message-metadata",
            threadID: "thread-metadata",
            labels: ["INBOX"],
            payload: GmailMessagePart(
                mimeType: "text/plain",
                body: GmailMessageBody(data: Self.base64URL("Fetched full body"))
            )
        )
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(Self.snapshot(messages: [
            Self.message(
                id: "message-metadata",
                threadID: "thread-metadata",
                labels: ["INBOX"],
                payload: GmailMessagePart(
                    mimeType: "multipart/alternative",
                    headers: [
                        GmailMessageHeader(name: "From", value: "Alice Example <alice@example.com>"),
                        GmailMessageHeader(name: "Subject", value: "Metadata only")
                    ]
                )
            )
        ]))
        let transport = StubGmailTransport(
            labels: [GmailLabel(id: "INBOX", name: "Inbox", type: "system")],
            messages: [fullMessage]
        )
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        let mailBackend: any MailBackend = backend
        try await mailBackend.connect()

        let body = try await mailBackend.body(for: "message-metadata")

        #expect(body.plainText == "Fetched full body")
        #expect(await transport.fullMessageRequestCount() == 1)
    }

    @Test("uses Gmail q syntax for server search and deduplicates results")
    func searchesWithGmailQuery() async throws {
        let message = Self.message(id: "message-3", threadID: "thread-3", labels: ["INBOX"])
        let transport = StubGmailTransport(
            labels: [GmailLabel(id: "INBOX", name: "Inbox", type: "system")],
            pages: [GmailMessagePage(messages: [GmailMessageReference(id: "message-3")])],
            messages: [message]
        )
        let backend = GmailAPIBackend(
            account: Self.account,
            transport: transport,
            store: InMemoryGmailAccountStore()
        )
        let mailBackend: any MailBackend = backend
        try await mailBackend.connect()

        let results = try await mailBackend.search(SearchQuery(
            text: "status:open",
            from: "alice@example.com",
            hasAttachments: true,
            isUnread: true
        ))

        #expect(results.map(\.id) == ["message-3"])
        #expect(await transport.lastQuery() == "status:open from:alice@example.com has:attachment is:unread")
    }

    @Test("paginates server search and scopes native folders")
    func paginatesAndScopesSearch() async throws {
        let first = Self.message(id: "message-page-1", threadID: "thread-1", labels: ["INBOX"])
        let second = Self.message(id: "message-page-2", threadID: "thread-2", labels: ["INBOX"])
        let transport = StubGmailTransport(
            labels: [GmailLabel(id: "INBOX", name: "Inbox", type: "system")],
            pages: [
                GmailMessagePage(messages: [.init(id: first.id)], nextPageToken: "1"),
                GmailMessagePage(messages: [.init(id: second.id)])
            ],
            messages: [first, second]
        )
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: InMemoryGmailAccountStore())
        let mailBackend: any MailBackend = backend
        try await mailBackend.connect()

        let results = try await mailBackend.search(SearchQuery(folderID: "INBOX"))

        #expect(results.map(\.id) == [first.id, second.id])
        #expect(await transport.lastQuery() == "in:inbox")
        #expect(await transport.lastIncludeSpamTrash() == false)
    }

    @Test("retention evicts Gmail body, raw, and attachment caches by age and pins")
    func retentionEvictsCachedContent() async throws {
        let old = Self.message(
            id: "old",
            threadID: "old-thread",
            labels: ["INBOX"],
            payload: GmailMessagePart(mimeType: "text/plain"),
            internalDate: "0"
        )
        let recent = Self.message(
            id: "recent",
            threadID: "recent-thread",
            labels: ["INBOX"],
            payload: GmailMessagePart(mimeType: "text/plain"),
            internalDate: "4102444800000"
        )
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(Self.snapshot(messages: [old, recent]))
        try await store.storeBody(MessageBody(messageID: old.id, plainText: "old"), accountID: Self.account.id)
        try await store.storeBody(MessageBody(messageID: recent.id, plainText: "recent"), accountID: Self.account.id)
        try await store.storeRawSource("old", accountID: Self.account.id, messageID: old.id)
        try await store.storeAttachment(Data("old".utf8), accountID: Self.account.id, attachmentID: "gmail-attachment:old:part")
        let backend = GmailAPIBackend(account: Self.account, transport: StubGmailTransport(), store: store)

        await backend.applyRetention(folderID: "INBOX", retentionDays: 7, keepsBodies: true, keepingMessageIDs: [old.id])
        #expect(try await store.cachedBody(accountID: Self.account.id, messageID: old.id) != nil)

        await backend.applyRetention(folderID: "INBOX", retentionDays: nil, keepsBodies: false, keepingMessageIDs: [])
        #expect(try await store.cachedBody(accountID: Self.account.id, messageID: old.id) == nil)
        #expect(try await store.cachedBody(accountID: Self.account.id, messageID: recent.id) == nil)
        #expect(try await store.cachedRawSource(accountID: Self.account.id, messageID: old.id) == nil)
        #expect(try await store.cachedAttachment(accountID: Self.account.id, attachmentID: "gmail-attachment:old:part") == nil)
        #expect(try await store.message(accountID: Self.account.id, messageID: old.id)?.payload == nil)
        #expect(try await store.message(accountID: Self.account.id, messageID: recent.id)?.payload == nil)
    }

    @Test("uses raw-source and attachment caches before transport fetches")
    func cachesRawSourceAndAttachmentBytes() async throws {
        let message = Self.message(
            id: "message-raw",
            threadID: "thread-raw",
            labels: ["INBOX"],
            payload: GmailMessagePart(
                partID: "attachment",
                mimeType: "application/pdf",
                filename: "report.pdf",
                body: GmailMessageBody(size: 2)
            ),
            raw: Self.base64URL("Subject: Raw\r\n\r\nHello")
        )
        let transport = StubGmailTransport(
            labels: [GmailLabel(id: "INBOX", name: "Inbox", type: "system")],
            messages: [message]
        )
        let backend = GmailAPIBackend(
            account: Self.account,
            transport: transport,
            store: InMemoryGmailAccountStore()
        )
        let mailBackend: any MailBackend = backend
        try await mailBackend.connect()
        let attachment = Attachment(
            id: "gmail-attachment:message-raw:attachment",
            name: "report.pdf",
            mimeType: "application/pdf",
            sizeBytes: 2,
            resource: "message-raw|attachment"
        )

        #expect(try await mailBackend.rawSource(for: "message-raw") == "Subject: Raw\r\n\r\nHello")
        #expect(try await mailBackend.rawSource(for: "message-raw") == "Subject: Raw\r\n\r\nHello")
        #expect(try await mailBackend.downloadAttachment(attachment) == Data("Hi".utf8))
        #expect(try await mailBackend.downloadAttachment(attachment) == Data("Hi".utf8))
        #expect(await transport.rawMessageRequestCount() == 1)
        #expect(await transport.attachmentRequestCount() == 1)
    }

    @Test("read-only slice rejects mutations through the public backend contract")
    func rejectsMutations() async throws {
        let backend = GmailAPIBackend(
            account: Self.account,
            transport: StubGmailTransport(),
            store: InMemoryGmailAccountStore()
        )
        let mailBackend: any MailBackend = backend

        do {
            try await mailBackend.setRead(true, for: ["message-1"])
            Issue.record("Expected setRead to be unsupported")
        } catch let error as MailBackendError {
            guard case .notSupported = error else { Issue.record("Unexpected backend error"); return }
        }
    }

    private static let account = BrevAccount(
        id: "gmail-api:google-subject-1",
        displayName: "Henrik Workspace",
        emailAddress: "henrik@example.work",
        backendIdentifier: "gmail-api",
        backendDisplayName: "Gmail"
    )

    private static func snapshot(messages: [GmailMessage]) -> GmailAccountSnapshot {
        GmailAccountSnapshot(
            accountID: account.id,
            state: GmailAccountState(accountID: account.id, emailAddress: account.emailAddress, historyID: "1"),
            labels: [GmailLabel(id: "INBOX", name: "Inbox", type: "system")],
            messages: messages
        )
    }

    private static func message(
        id: String,
        threadID: String,
        labels: [String],
        payload: GmailMessagePart? = nil,
        raw: String? = nil,
        internalDate: String = "1787648400000"
    ) -> GmailMessage {
        GmailMessage(
            id: id,
            threadID: threadID,
            labelIDs: labels,
            snippet: "Snippet for \(id)",
            internalDate: internalDate,
            payload: payload,
            raw: raw
        )
    }

    private static func base64URL(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

private actor StubGmailTransport: GmailAPITransporting {
    private let profileValue: GmailProfile
    private let labelsValue: [GmailLabel]
    private let pages: [GmailMessagePage]
    private let messages: [String: GmailMessage]
    private var listingFailure = false
    private let messageDelay: UInt64
    private var concurrentRequests = 0
    private var maximumRequests = 0
    func failListings() { listingFailure = true }
    func maximumConcurrentRequests() -> Int { maximumRequests }
    private var nextPageIndex = 0
    private var query: String?
    private var fullRequests = 0
    private var rawRequests = 0
    private var attachmentRequests = 0
    private var includeSpamTrash = false

    init(
        profile: GmailProfile = GmailProfile(emailAddress: "henrik@example.work", historyID: "history-1"),
        labels: [GmailLabel] = [],
        pages: [GmailMessagePage] = [],
        messages: [GmailMessage] = [],
        messageDelay: UInt64 = 0
    ) {
        self.messageDelay = messageDelay
        profileValue = profile
        labelsValue = labels
        self.pages = pages
        self.messages = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
    }

    func profile() async throws -> GmailProfile { profileValue }
    func listLabels() async throws -> [GmailLabel] { labelsValue }

    func listMessages(
        labelID: String?,
        query: String?,
        pageToken: String?,
        maxResults: Int
    ) async throws -> GmailMessagePage {
        if listingFailure { throw URLError(.notConnectedToInternet) }
        self.query = query
        includeSpamTrash = false
        if let pageToken, let index = Int(pageToken) {
            return pages.indices.contains(index) ? pages[index] : GmailMessagePage()
        }
        defer { nextPageIndex += 1 }
        return pages.indices.contains(nextPageIndex) ? pages[nextPageIndex] : GmailMessagePage()
    }

    func listMessages(
        labelID: String?,
        query: String?,
        pageToken: String?,
        maxResults: Int,
        includeSpamTrash: Bool
    ) async throws -> GmailMessagePage {
        self.includeSpamTrash = includeSpamTrash
        return try await listMessages(labelID: labelID, query: query, pageToken: pageToken, maxResults: maxResults)
    }

    func getMessage(messageID: String, format: GmailMessageFormat) async throws -> GmailMessage {
        concurrentRequests += 1
        maximumRequests = max(maximumRequests, concurrentRequests)
        defer { concurrentRequests -= 1 }
        if messageDelay > 0 { try await Task.sleep(nanoseconds: messageDelay) }
        if format == .full { fullRequests += 1 }
        if format == .raw { rawRequests += 1 }
        guard let message = messages[messageID] else { throw GmailAPIError.httpFailure(statusCode: 404) }
        return message
    }

    func getAttachment(messageID: String, attachmentID: String) async throws -> GmailAttachment {
        attachmentRequests += 1
        return GmailAttachment(id: attachmentID, messageID: messageID, data: "SGk=")
    }

    func lastQuery() -> String? { query }
    func lastIncludeSpamTrash() -> Bool { includeSpamTrash }
    func fullMessageRequestCount() -> Int { fullRequests }
    func rawMessageRequestCount() -> Int { rawRequests }
    func attachmentRequestCount() -> Int { attachmentRequests }
}
