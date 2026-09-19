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
    @Test("cached Gmail conversations include other folders and retain an uncached selected anchor")
    func cachedConversationUsesNativeThread() async throws {
        let source = MailSourceID(accountID: Self.account.id, mailboxID: Self.account.id)
        let anchor = ConversationMember(
            sourceID: source,
            header: MessageHeader(
                id: "selected",
                threadID: "thread",
                folderID: "INBOX",
                from: Correspondent(email: "sender@example.org"),
                to: [],
                subject: "Topic",
                snippet: "",
                date: Date()
            ),
            folderGeneration: 7
        )
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(Self.snapshot(messages: [
            Self.message(id: "sent", threadID: "thread", labels: ["UNREAD", "SENT"]),
            Self.message(id: "archive", threadID: "thread", labels: ["projects"]),
            Self.message(id: "trash", threadID: "thread", labels: ["TRASH"]),
            Self.message(id: "unrelated", threadID: "other", labels: ["INBOX"])
        ]))
        try await store.apply(GmailStoreDelta(accountID: Self.account.id, upsertedLabels: [
            GmailLabel(id: "UNREAD", name: "Unread"), GmailLabel(id: "SENT", name: "Sent"), GmailLabel(
                id: "projects",
                name: "Projects",
                type: "user"
            ), GmailLabel(
                id: "TRASH",
                name: "Trash"
            )
        ]))
        let transport = StubGmailTransport()
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        #expect(backend.extendedCapabilities.contains(.cachedConversations))
        let provider = try #require(backend.extensionService(CachedConversationProviding.self))
        let snapshot = try await provider.cachedConversation(around: anchor, includeSpamAndTrash: false)
        #expect(Set(snapshot.members.map { $0.header.id }) == ["selected", "sent", "archive"])
        #expect(snapshot.anchor == anchor.location)
        #expect(snapshot.members.first { $0.header.id == "sent" }?.location.folderID == "SENT")
        #expect(snapshot.members.first { $0.header.id == "archive" }?.location.folderID == "projects")
        #expect(snapshot.coverage == .cached)
        let includingTrash = try await provider.cachedConversation(around: anchor, includeSpamAndTrash: true)
        #expect(includingTrash.members.count == 4)
        #expect(await transport.networkCalls == 0)
        #expect(backend.extensionService(RelatedConversationLoading.self) == nil)
        try await store.apply(GmailStoreDelta(accountID: Self.account.id, upsertedMessages: [
            Self.message(id: "selected", threadID: "thread", labels: ["UNREAD", "SENT"])
        ]))
        let moved = try await provider.cachedConversation(around: anchor, includeSpamAndTrash: false)
        #expect(moved.anchor.folderID == "SENT")
        #expect(moved.anchor.messageID == anchor.header.id)
        #expect(moved.members.first { $0.header.id == "selected" }?.header.subject == "Topic")
        try await store.apply(GmailStoreDelta(accountID: Self.account.id, upsertedMessages: [
            Self.message(id: "selected", threadID: "thread", labels: ["UNREAD", "INBOX", "projects"]),
            Self.message(id: "sent", threadID: "thread", labels: ["SENT", "projects"])
        ]))
        let projectAnchor = ConversationMember(sourceID: source,
                                               header: anchor.header.withIdentity(anchor.header.id, folderID: "projects"))
        let project = try await provider.cachedConversation(around: projectAnchor, includeSpamAndTrash: false)
        #expect(project.anchor.folderID == "projects")
        #expect(project.members.first { $0.header.id == "sent" }?.location.folderID == "projects")
        #expect(await transport.networkCalls == 0)
    }

    @Test("related loading needs consent, then resolves the native thread metadata-only")
    func relatedConversationLoadsThreadMetadataOnly() async throws {
        let source = MailSourceID(accountID: Self.account.id, mailboxID: Self.account.id)
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(Self.snapshot(messages: [
            Self.message(id: "selected", threadID: "thread", labels: ["INBOX"])
        ]))
        let transport = StubGmailTransport()
        await transport.setThreadResult(GmailThread(id: "thread", historyID: "9", messages: [
            Self.message(id: "selected", threadID: "thread", labels: ["INBOX"]),
            Self.message(
                id: "sent", threadID: "thread", labels: ["SENT"],
                payload: GmailMessagePart(headers: [
                    GmailMessageHeader(name: "Subject", value: "Re: Topic"),
                    GmailMessageHeader(name: "From", value: "henrik@example.work"),
                    GmailMessageHeader(name: "Message-ID", value: "<sent-1@example.org>"),
                    GmailMessageHeader(name: "References", value: "<root@example.org>")
                ])
            ),
            Self.message(id: "spam", threadID: "thread", labels: ["SPAM"])
        ]))
        let consent = StubGmailRelatedConsent(consented: false)
        let backend = GmailAPIBackend(
            account: Self.account, transport: transport, store: store,
            relatedConversationConsent: consent
        )
        try await backend.connect()
        #expect(backend.extendedCapabilities.contains(.relatedConversationLoading))
        let provider = try #require(backend.extensionService(RelatedConversationLoading.self))
        let anchor = ConversationMember(
            sourceID: source,
            header: MessageHeader(
                id: "selected", threadID: "thread", folderID: "INBOX",
                from: Correspondent(email: "sender@example.org"), to: [],
                subject: "Topic", snippet: "", date: Date()
            )
        )

        // Without consent the remote path never runs.
        await #expect(throws: ConversationLookupError.self) {
            _ = try await provider.loadRelatedConversation(
                around: anchor, includeSpamAndTrash: false, continuation: nil
            ) { _ in }
        }
        #expect(await transport.threadRequests.isEmpty)

        await consent.setConsented(true)
        let updates = GmailConversationCoverageCollector()
        let snapshot = try await provider.loadRelatedConversation(
            around: anchor, includeSpamAndTrash: false, continuation: nil
        ) { update in
            await updates.append(update.coverage)
        }

        #expect(snapshot.coverage == .completeForScope)
        #expect(Set(snapshot.members.map(\.header.id)) == ["selected", "sent"])
        // The selected message keeps its anchor identity and folder context.
        #expect(snapshot.anchor == anchor.location)
        #expect(snapshot.members.first { $0.header.id == "selected" }?.header.folderID == "INBOX")
        #expect(snapshot.members.first { $0.header.id == "sent" }?.header.folderID == "SENT")
        #expect(snapshot.excludedFolderIDs == ["SPAM", "TRASH"])
        let threadRequests = await transport.threadRequests
        #expect(threadRequests.count == 1)
        #expect(threadRequests.first?.threadID == "thread")
        #expect(threadRequests.first?.metadataHeaders.contains("References") == true)
        #expect(await transport.fullMessageRequestCount() == 0)
        #expect(await updates.values.last == .completeForScope)
        // Discovered metadata is persisted through the provider-owned store.
        #expect(try await store.message(accountID: Self.account.id, messageID: "sent") != nil)
    }

    @Test("related loading stays absent without a consent boundary")
    func relatedConversationLoadingUnadvertisedWithoutConsent() async throws {
        let transport = StubGmailTransport()
        let store = InMemoryGmailAccountStore()
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        try await backend.connect()
        #expect(!backend.extendedCapabilities.contains(.relatedConversationLoading))
        #expect(backend.extensionService(RelatedConversationLoading.self) == nil)
    }

    @Test("saved views enumerate secondary label membership without fetching messages")
    func savedViewUsesCachedLabelMembership() async throws {
        let transport = StubGmailTransport()
        let store = InMemoryGmailAccountStore()
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        try await backend.connect()
        try await store.replaceSnapshot(GmailAccountSnapshot(
            accountID: Self.account.id,
            state: GmailAccountState(accountID: Self.account.id, emailAddress: Self.account.emailAddress),
            labels: [GmailLabel(id: "INBOX", name: "Inbox", type: "system"),
                     GmailLabel(id: "projects", name: "Projects", type: "user")],
            messages: [Self.message(id: "both", threadID: "thread", labels: ["INBOX", "projects"])]
        ))
        await transport.failListings()
        let source = MailSourceID(accountID: Self.account.id, mailboxID: Self.account.id)
        let results = try await backend.cachedMessageHeaders(
            in: Folder(id: "projects", name: "Projects", role: .custom), sourceID: source
        )
        #expect(results.map(\.id) == ["both"])
        #expect(results.first?.folderID == "projects")
        #expect(await transport.fullMessageRequestCount() == 0)
        await #expect(throws: MailBackendError.self) {
            try await backend.cachedMessageHeaders(in: Folder(id: "projects", name: "Projects", role: .custom),
                                                   sourceID: MailSourceID(accountID: Self.account.id, mailboxID: "other"))
        }
    }

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
        #expect(await transport.metadataMessageRequestCount() == 8)
        #expect(await transport.fullMessageRequestCount() == 0)
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

    @Test("Auto search previews one cache page, while offline fallback completes every cache page", arguments: [false, true])
    func autoSearchCachePreviewIsBounded(offline: Bool) async throws {
        let base = InMemoryGmailAccountStore()
        let messages = (0 ..< 250).map { Self.message(id: String(format: "m%03d", $0), threadID: "t", labels: ["INBOX"]) }
        try await base.replaceSnapshot(Self.snapshot(messages: messages))
        let store = SearchPagingGmailStore(base: base)
        let transport = StubGmailTransport(pages: [GmailMessagePage()], pageObserver: { _ in
            #expect(await store.pageLimits.count == 1)
            if offline { throw GmailAPIError.transportFailure }
        })
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        let progress = GmailSearchProgressRecorder()
        try await backend.connect()
        defer { Task { await backend.disconnect() } }
        let results = try await backend.searchWithProgress(
            SearchQuery(folderID: "INBOX", execution: .cacheThenServer),
            sourceID: nil
        ) { await progress.record($0) }
        #expect(results.count == (offline ? 250 : 0))
        let limits = await store.pageLimits
        #expect(limits.count == (offline ? 5 : 1))
        #expect(limits.allSatisfy { $0 == 100 })
        #expect(await progress.updates.last?.coverage == (offline ? .cached : .server))
        #expect(await progress.updates.last?.isComplete == true)
    }

    @Test("later-page authentication and retry errors keep their recovery type", arguments: [false, true])
    func searchPreservesProviderRecoveryErrors(authentication: Bool) async throws {
        let transport = StubGmailTransport(pages: [GmailMessagePage(nextPageToken: "1")], pageObserver: { token in
            if token != nil {
                if authentication { throw GmailAPIError.reauthenticationRequired }
                throw GmailAPIError.retryable(statusCode: 503, retryAfter: 30)
            }
        })
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: InMemoryGmailAccountStore())
        try await backend.connect()
        defer { Task { await backend.disconnect() } }
        do {
            _ = try await backend.search(SearchQuery(text: "invoice", execution: .serverOnly))
            Issue.record("Expected typed provider error")
        } catch {
            if authentication {
                guard case MailBackendError.authenticationRequired = error
                else { Issue.record("Lost reauthentication error"); return }
            } else {
                #expect(error as? GmailAPIError == .retryable(statusCode: 503, retryAfter: 30))
            }
        }
    }

    @Test("a retired search cannot publish or store a late message in a replacement account")
    func retiredSearchRejectsLateFetch() async throws {
        let gate = GmailSearchFetchGate()
        let message = Self.message(id: "old", threadID: "t", labels: ["INBOX"])
        let transport = StubGmailTransport(
            pages: [GmailMessagePage(messages: [.init(id: "old")])],
            messages: [message],
            messageObserver: { _ in await gate.pause() }
        )
        let store = InMemoryGmailAccountStore()
        let progress = GmailSearchProgressRecorder()
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        try await backend.connect()
        let request = Task {
            try await backend
                .searchWithProgress(SearchQuery(folderID: "INBOX", execution: .serverOnly), sourceID: nil) {
                    await progress.record($0)
                }
        }
        await gate.waitForStart()
        await backend.disconnect()
        try await store.replaceSnapshot(Self.snapshot(messages: [Self.message(
            id: "replacement",
            threadID: "new",
            labels: ["INBOX"]
        )]))
        await gate.release()
        await #expect(throws: MailBackendError.self) { _ = try await request.value }
        #expect(await progress.updates.isEmpty)
        #expect(try await store.messages(accountID: Self.account.id).map(\.id) == ["replacement"])
    }

    @Test("later page failure preserves partial progress without cached or server completion")
    func latePageFailureDoesNotComplete() async throws {
        let message = Self.message(id: "first", threadID: "t", labels: ["INBOX"])
        let transport = StubGmailTransport(
            pages: [GmailMessagePage(messages: [.init(id: "first")], nextPageToken: "1")],
            messages: [message],
            pageObserver: { token in
                if token != nil { throw URLError(.notConnectedToInternet) }
            }
        )
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(Self.snapshot(messages: [Self.message(id: "cached", threadID: "c", labels: ["INBOX"])]))
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        let progress = GmailSearchProgressRecorder()
        try await backend.connect()
        defer { Task { await backend.disconnect() } }
        await #expect(throws: URLError.self) {
            _ = try await backend
                .searchWithProgress(SearchQuery(folderID: "INBOX", execution: .cacheThenServer), sourceID: nil) {
                    await progress.record($0)
                }
        }
        let updates = await progress.updates
        #expect(updates.first?.coverage == .cached)
        #expect(updates.last?.headers.first?.id == "first")
        #expect(!updates.contains { $0.isComplete })
    }

    @Test("custom label searches use stable IDs and preserve negative predicates")
    func searchUsesStableLabelAndNegativePredicates() async throws {
        let transport = StubGmailTransport(
            labels: [GmailLabel(id: "projects", name: "Team \"Plans\"", type: "user")],
            pages: [GmailMessagePage()]
        )
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: InMemoryGmailAccountStore())
        try await backend.connect()
        defer { Task { await backend.disconnect() } }
        _ = try await backend.search(SearchQuery(
            folderID: "projects",
            hasAttachments: false,
            isUnread: false,
            isFlagged: false,
            execution: .serverOnly
        ))
        #expect(await transport.requestedLabelID == "projects")
        #expect(await transport.lastQuery() == "-has:attachment is:read -is:starred")
    }

    @Test("All Mail consistently excludes Spam and Trash online and offline")
    func allMailScopeIsConsistent() async throws {
        let messages = [Self.message(id: "kept", threadID: "t", labels: ["INBOX"]),
                        Self.message(id: "spam", threadID: "s", labels: ["SPAM"]),
                        Self.message(id: "trash", threadID: "r", labels: ["TRASH"])]
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(Self.snapshot(messages: messages))
        let transport = StubGmailTransport(
            labels: [GmailLabel(id: "ALL_MAIL", name: "All Mail", type: "system")],
            pages: [GmailMessagePage(messages: [.init(id: "kept")])]
        )
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        let local = try await backend.search(SearchQuery(folderID: "ALL_MAIL", execution: .cacheOnly))
        #expect(local.map(\.id) == ["kept"])
        try await backend.connect()
        defer { Task { await backend.disconnect() } }
        let online = try await backend.search(SearchQuery(folderID: "ALL_MAIL", execution: .serverOnly))
        #expect(online.map(\.id) == ["kept"])
        #expect(online.first?.folderID == "ALL_MAIL")
        #expect(await transport.lastQuery() == "-in:spam -in:trash")
        #expect(await transport.lastIncludeSpamTrash() == false)
    }

    @Test("Gmail progress arrives before later pages and cancellation stops paging", arguments: [false, true])
    func progressiveSearchCanCancel(cancel: Bool) async throws {
        let progress = GmailSearchProgressRecorder()
        let first = Self.message(id: "first", threadID: "t1", labels: ["INBOX"])
        let last = Self.message(id: "last", threadID: "t2", labels: ["INBOX"])
        let transport = StubGmailTransport(pages: [
            GmailMessagePage(messages: [.init(id: first.id)], nextPageToken: "1"),
            GmailMessagePage(messages: [], nextPageToken: "2"),
            GmailMessagePage(messages: [.init(id: last.id)])
        ], messages: [first, last], pageObserver: { token in
            if token != nil { #expect(await progress.updates.first?.headers.first?.id == "first") }
        })
        let store = InMemoryGmailAccountStore()
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        try await backend.connect()
        defer { Task { await backend.disconnect() } }
        let service = try #require(backend.extensionService(ProgressiveMailSearching.self))
        let task = Task {
            try await service.searchWithProgress(
                SearchQuery(folderID: "INBOX", execution: .serverOnly),
                sourceID: MailSourceID(accountID: Self.account.id, mailboxID: Self.account.id)
            ) {
                await progress.record($0)
                if cancel { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        if cancel {
            await #expect(throws: CancellationError.self) { _ = try await task.value }
            #expect(await transport.requestedTokens == [nil])
            #expect(await progress.updates.count == 1)
        } else {
            let result = try await task.value
            #expect(result.map(\.id) == ["first", "last"])
            #expect(await progress.updates.last?.isComplete == true)
            #expect(await progress.updates.last?.coverage == .server)
            #expect(await transport.requestedTokens == [nil, "1", "2"])
        }
        let limits = await transport.requestedLimits
        #expect(limits.allSatisfy { $0 == 50 })
        #expect(try await store.messages(accountID: Self.account.id).isEmpty)
        #expect(await transport.attachmentRequestCount() == 0)
    }

    @Test("Gmail cursor cycles fail instead of claiming complete search")
    func searchCursorCycleFails() async throws {
        let transport = StubGmailTransport(pages: [GmailMessagePage(nextPageToken: "1"), GmailMessagePage(nextPageToken: "1")])
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: InMemoryGmailAccountStore())
        try await backend.connect()
        defer { Task { await backend.disconnect() } }
        await #expect(throws: MailBackendError.self) { _ = try await backend.search(SearchQuery(
            text: "invoice",
            execution: .serverOnly
        )) }
        #expect(await transport.requestedTokens == [nil, "1"])
    }

    @Test("search message fetching is concurrent but bounded")
    func searchFetchConcurrencyIsBounded() async throws {
        let messages = (0 ..< 12).map { Self.message(id: "m\($0)", threadID: "t", labels: ["INBOX"]) }
        let transport = StubGmailTransport(
            pages: [GmailMessagePage(messages: messages.map { .init(id: $0.id) })],
            messages: messages,
            messageDelay: 10_000_000
        )
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: InMemoryGmailAccountStore())
        try await backend.connect()
        defer { Task { await backend.disconnect() } }
        #expect(try await backend.search(SearchQuery(folderID: "INBOX", execution: .serverOnly)).count == 12)
        let maximum = await transport.maximumConcurrentRequests()
        #expect(maximum > 1)
        #expect(maximum <= 4)
    }

    @Test("cached search works disconnected and respects secondary label membership")
    func cachedSearchUsesMembershipOffline() async throws {
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(Self.snapshot(messages: [Self.message(
            id: "both",
            threadID: "t",
            labels: ["INBOX", "projects"]
        )]))
        let backend = GmailAPIBackend(account: Self.account, transport: StubGmailTransport(), store: store)
        let results = try await backend.search(SearchQuery(folderID: "projects", execution: .cacheOnly))
        #expect(results.map(\.id) == ["both"])
        #expect(results.first?.folderID == "projects")
    }

    @Test("Gmail search returns a match beyond the former five-thousand cap")
    func searchBeyondFormerCap() async throws {
        let messages = (0 ..< 5001).map { Self.message(id: "m\($0)", threadID: "t\($0)", labels: ["INBOX"]) }
        var pages: [GmailMessagePage] = []
        for start in stride(from: 0, to: messages.count, by: 50) {
            let end = min(start + 50, messages.count)
            let references: [GmailMessageReference] = messages[start ..< end].map { GmailMessageReference(id: $0.id) }
            let nextToken: String? = end < messages.count ? String(start / 50 + 1) : nil
            pages.append(GmailMessagePage(messages: references, nextPageToken: nextToken))
        }
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(Self.snapshot(messages: messages))
        let backend = GmailAPIBackend(account: Self.account, transport: StubGmailTransport(pages: pages), store: store)
        try await backend.connect()
        defer { Task { await backend.disconnect() } }
        let results = try await backend.search(SearchQuery(folderID: "INBOX", execution: .serverOnly))
        #expect(results.count == 5001)
        #expect(results.last?.id == "m5000")
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

    @Test("Gmail original MIME bytes survive restart and are available offline")
    func originalMIMEBytesSurviveRestart() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-raw-mime-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let raw = Data("Content-Type: text/plain; charset=iso-8859-1\r\n\r\n".utf8) + Data([0xE5, 0xF8, 0xE6])
        let encoded = raw.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let message = GmailMessage(id: "raw-eight-bit", threadID: "thread", labelIDs: ["INBOX"], raw: encoded)
        let transport = StubGmailTransport(messages: [message])
        let source = MailSourceID(accountID: Self.account.id, mailboxID: Self.account.id)
        do {
            let store = try SQLiteGmailAccountStore(databaseURL: url)
            try await store.replaceSnapshot(Self.snapshot(messages: [message]))
            try await store.storeRawSource("Legacy decoded text", accountID: Self.account.id, messageID: message.id)
            let backend: any MailBackend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
            try await backend.connect()
            #expect(try await backend.rawMessageData(for: message.id, sourceID: source) == raw)
            await backend.disconnect()
        }
        let reopened = try SQLiteGmailAccountStore(databaseURL: url)
        let offline: any MailBackend = GmailAPIBackend(account: Self.account, transport: transport, store: reopened)
        #expect(offline.extendedCapabilities.contains(.rawMessageBytes))
        #expect(try await offline.rawSource(for: message.id, sourceID: source).hasSuffix("åøæ"))
        #expect(try await offline.rawMessageData(for: message.id, sourceID: source) == raw)
        #expect(await transport.rawMessageRequestCount() == 1)
        await #expect(throws: MailBackendError.self) {
            _ = try await offline.rawMessageData(for: message.id, sourceID: MailSourceID(accountID: "other", mailboxID: "other"))
        }
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

private actor StubGmailRelatedConsent: RelatedConversationConsenting {
    private var consented: Bool

    init(consented: Bool) {
        self.consented = consented
    }

    func setConsented(_ value: Bool) {
        consented = value
    }

    func isRelatedConversationConsented(accountID: BrevAccount.ID) async -> Bool {
        consented
    }
}

private actor GmailConversationCoverageCollector {
    private(set) var values: [ConversationCoverage] = []

    func append(_ coverage: ConversationCoverage) {
        values.append(coverage)
    }
}

private actor StubGmailTransport: GmailAPITransporting {
    private let profileValue: GmailProfile
    private let labelsValue: [GmailLabel]
    private let pages: [GmailMessagePage]
    private let messages: [String: GmailMessage]
    private var listingFailure = false
    private(set) var networkCalls = 0
    private let messageDelay: UInt64
    private let messageObserver: (@Sendable (String) async -> Void)?
    private let pageObserver: (@Sendable (String?) async throws -> Void)?
    private(set) var requestedTokens: [String?] = []
    private(set) var requestedLimits: [Int] = []
    private var concurrentRequests = 0
    private var maximumRequests = 0
    func failListings() { listingFailure = true }
    func maximumConcurrentRequests() -> Int { maximumRequests }
    private var nextPageIndex = 0
    private var query: String?
    private(set) var requestedLabelID: String?
    private var fullRequests = 0
    private var metadataRequests = 0
    private var rawRequests = 0
    private var attachmentRequests = 0
    private var includeSpamTrash = false

    init(
        profile: GmailProfile = GmailProfile(emailAddress: "henrik@example.work", historyID: "history-1"),
        labels: [GmailLabel] = [],
        pages: [GmailMessagePage] = [],
        messages: [GmailMessage] = [],
        messageDelay: UInt64 = 0,
        pageObserver: (@Sendable (String?) async throws -> Void)? = nil,
        messageObserver: (@Sendable (String) async -> Void)? = nil
    ) {
        self.messageDelay = messageDelay
        self.pageObserver = pageObserver
        self.messageObserver = messageObserver
        profileValue = profile
        labelsValue = labels
        self.pages = pages
        self.messages = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
    }

    func profile() async throws -> GmailProfile { networkCalls += 1; return profileValue }
    func listLabels() async throws -> [GmailLabel] { networkCalls += 1; return labelsValue }

    func listMessages(
        labelID: String?,
        query: String?,
        pageToken: String?,
        maxResults: Int
    ) async throws -> GmailMessagePage {
        networkCalls += 1
        requestedTokens.append(pageToken)
        requestedLimits.append(maxResults)
        try await pageObserver?(pageToken)
        if listingFailure { throw URLError(.notConnectedToInternet) }
        self.query = query
        requestedLabelID = labelID
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
        networkCalls += 1
        concurrentRequests += 1
        maximumRequests = max(maximumRequests, concurrentRequests)
        defer { concurrentRequests -= 1 }
        await messageObserver?(messageID)
        if messageDelay > 0 { try await Task.sleep(nanoseconds: messageDelay) }
        if format == .full { fullRequests += 1 }
        if format == .metadata { metadataRequests += 1 }
        if format == .raw { rawRequests += 1 }
        guard let message = messages[messageID] else { throw GmailAPIError.httpFailure(statusCode: 404) }
        return message
    }

    func getAttachment(messageID: String, attachmentID: String) async throws -> GmailAttachment {
        networkCalls += 1
        attachmentRequests += 1
        return GmailAttachment(id: attachmentID, messageID: messageID, data: "SGk=")
    }

    private var threadResult: GmailThread?
    private var threadFailure: Error?
    private(set) var threadRequests: [(threadID: String, metadataHeaders: [String])] = []

    func setThreadResult(_ thread: GmailThread?) {
        threadResult = thread
    }

    func setThreadFailure(_ error: Error?) {
        threadFailure = error
    }

    func getThread(threadID: String, metadataHeaders: [String]) async throws -> GmailThread {
        networkCalls += 1
        threadRequests.append((threadID: threadID, metadataHeaders: metadataHeaders))
        if let threadFailure { throw threadFailure }
        guard let threadResult else { throw GmailAPIError.httpFailure(statusCode: 404) }
        return threadResult
    }

    func lastQuery() -> String? { query }
    func lastIncludeSpamTrash() -> Bool { includeSpamTrash }
    func fullMessageRequestCount() -> Int { fullRequests }
    func metadataMessageRequestCount() -> Int { metadataRequests }
    func rawMessageRequestCount() -> Int { rawRequests }
    func attachmentRequestCount() -> Int { attachmentRequests }
}

private actor GmailSearchProgressRecorder {
    var updates: [MailSearchUpdate] = []
    func record(_ update: MailSearchUpdate) { updates.append(update) }
}

private actor GmailSearchFetchGate {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func pause() async {
        started = true
        startWaiter?.resume(); startWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitForStart() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}

private actor SearchPagingGmailStore: GmailAccountStore {
    let base: any GmailAccountStore
    private(set) var pageLimits: [Int] = []
    init(base: any GmailAccountStore) { self.base = base }
    func removeAccount(accountID: String) async throws { try await base.removeAccount(accountID: accountID) }
    func accountState(accountID: String) async throws -> GmailAccountState? { try await base.accountState(accountID: accountID) }
    func replaceSnapshot(_ snapshot: GmailAccountSnapshot) async throws { try await base.replaceSnapshot(snapshot) }
    func apply(_ delta: GmailStoreDelta) async throws { try await base.apply(delta) }
    func messages(accountID: String) async throws -> [GmailMessage] {
        Issue.record("Search must not materialize the entire account cache")
        throw GmailAccountStoreError.databaseFailure
    }

    func cachedSearchPage(accountID: String, afterMessageID: String?, limit: Int) async throws -> [GmailMessage] {
        pageLimits.append(limit)
        return try await base.cachedSearchPage(accountID: accountID, afterMessageID: afterMessageID, limit: limit)
    }

    func message(accountID: String, messageID: String) async throws -> GmailMessage? { try await base.message(
        accountID: accountID,
        messageID: messageID
    ) }
    func labels(accountID: String) async throws -> [GmailLabel] { try await base.labels(accountID: accountID) }
    func messageLabelIDs(accountID: String, messageID: String) async throws -> [String] { try await base.messageLabelIDs(
        accountID: accountID,
        messageID: messageID
    ) }
}
