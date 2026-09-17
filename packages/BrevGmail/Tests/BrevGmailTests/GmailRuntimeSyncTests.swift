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

@Suite("Gmail runtime sync")
struct GmailRuntimeSyncTests {
    @Test("connect runs a bounded full sync when no history cursor exists")
    func connectRunsFullSync() async throws {
        let client = RuntimeClient()
        let store = InMemoryGmailAccountStore()
        let backend = Self.backend(client: client, store: store)

        try await backend.connect()

        #expect(try await store.accountState(accountID: Self.account.id)?.historyID == "h1")
        #expect(try await store.messages(accountID: Self.account.id).map(\.id) == ["m1"])
        #expect(await client.fullListCalls() == 1)
    }

    @Test("delta history changes commit and emit bounded MailBackend events")
    func deltaSyncEmitsEvents() async throws {
        let client = RuntimeClient()
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(GmailAccountSnapshot(
            accountID: Self.account.id,
            state: GmailAccountState(accountID: Self.account.id, emailAddress: Self.account.emailAddress, historyID: "h0"),
            labels: Self.labels,
            messages: [Self.message(labels: ["INBOX"])]
        ))
        await client.setDelta(message: Self.message(labels: ["INBOX", "STARRED"]))
        let backend = Self.backend(client: client, store: store)
        let stream = backend.subscribeToChanges()
        let eventTask = Task { var iterator = stream.makeAsyncIterator(); return await iterator.next() }

        try await backend.connect()

        let receivedEvent = await eventTask.value
        let event = try #require(receivedEvent)
        guard case .messagesUpdated(_, let messageIDs) = event else {
            Issue.record("Expected a committed messagesUpdated event")
            return
        }
        #expect(messageIDs == ["m1"])
        #expect(try await store.messageLabelIDs(accountID: Self.account.id, messageID: "m1") == ["INBOX", "STARRED"])
        #expect(await client.historyCalls() == 1)
    }

    @Test("expired history cursor performs one full reconciliation")
    func expiredCursorFallsBackToFullSync() async throws {
        let client = RuntimeClient(historyExpired: true)
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(GmailAccountSnapshot(
            accountID: Self.account.id,
            state: GmailAccountState(accountID: Self.account.id, emailAddress: Self.account.emailAddress, historyID: "expired"),
            labels: Self.labels,
            messages: [Self.message(labels: ["INBOX"])]
        ))
        let backend = Self.backend(client: client, store: store)

        try await backend.connect()

        #expect(try await store.accountState(accountID: Self.account.id)?.historyID == "h1")
        #expect(await client.historyCalls() == 1)
        #expect(await client.fullListCalls() == 1)
    }

    @Test("cancellation does not advance the persisted cursor")
    func cancellationDoesNotAdvanceCursor() async throws {
        let client = RuntimeClient(cancelFullSync: true)
        let store = InMemoryGmailAccountStore()
        let backend = Self.backend(client: client, store: store)

        await #expect(throws: CancellationError.self) {
            try await backend.connect()
        }
        #expect(try await store.accountState(accountID: Self.account.id) == nil)
    }

    @Test("background refresh and sync health use the same reconciler")
    func backgroundRefreshAndHealth() async throws {
        let client = RuntimeClient()
        let store = InMemoryGmailAccountStore()
        let backend = Self.backend(client: client, store: store)
        try await backend.connect()
        let source = MailSourceID(accountID: Self.account.id, mailboxID: Self.account.id)
        let refresh = try #require(backend.extensionService(MailboxBackgroundRefreshing.self))
        try await refresh.refreshMailbox(for: source)
        let health = try #require(backend.extensionService(SyncHealthReporting.self))
        #expect(await health.syncHealth(for: source).state == .healthy)
    }

    private static let account = BrevAccount(
        id: "gmail-api:runtime-subject",
        displayName: "Runtime User",
        emailAddress: "runtime@example.work",
        backendIdentifier: "gmail-api",
        backendDisplayName: "Gmail"
    )

    private static let labels = [
        GmailLabel(id: "INBOX", name: "Inbox", type: "system"),
        GmailLabel(id: "STARRED", name: "Starred", type: "system")
    ]

    private static func message(labels: [String]) -> GmailMessage {
        GmailMessage(id: "m1", threadID: "t1", labelIDs: labels, snippet: "Runtime")
    }

    private static func backend(client: RuntimeClient, store: InMemoryGmailAccountStore) -> GmailAPIBackend {
        let reconciler = GmailSyncReconciler(client: client, store: store, accountID: account.id)
        return GmailAPIBackend(
            account: account,
            transport: client,
            store: store,
            client: client,
            syncReconciler: reconciler
        )
    }
}

private actor RuntimeClient: GmailAPIClientProtocol, GmailAPITransporting {
    private var deltaMessage: GmailMessage?
    private let historyExpired: Bool
    private let cancelFullSync: Bool
    private var fullCalls = 0
    private var historyCallsValue = 0

    init(historyExpired: Bool = false, cancelFullSync: Bool = false) {
        self.historyExpired = historyExpired
        self.cancelFullSync = cancelFullSync
    }

    func setDelta(message: GmailMessage) { deltaMessage = message }
    func fullListCalls() -> Int { fullCalls }
    func historyCalls() -> Int { historyCallsValue }

    func profile() async throws -> GmailProfile { GmailProfile(emailAddress: "runtime@example.work", historyID: "h1") }
    func getProfile() async throws -> GmailProfile { try await profile() }
    func listLabels() async throws -> [GmailLabel] {
        [GmailLabel(id: "INBOX", name: "Inbox", type: "system"), GmailLabel(id: "STARRED", name: "Starred", type: "system")]
    }

    func getLabel(id: String) async throws -> GmailLabel { try #require(try await (listLabels()).first { $0.id == id }) }
    func listMessages(maxResults: Int, pageToken: String?, labelIDs: [String], query: String?,
                      includeSpamTrash: Bool) async throws -> GmailMessagePage {
        fullCalls += 1
        if cancelFullSync { throw CancellationError() }
        return GmailMessagePage(messages: [GmailMessageReference(id: "m1", threadID: "t1")])
    }

    func listMessages(labelID: String?, query: String?, pageToken: String?,
                      maxResults: Int) async throws -> GmailMessagePage { GmailMessagePage() }
    func getMessage(id: String, format: GmailMessageFormat, metadataHeaders: [String]) async throws -> GmailMessage {
        deltaMessage ?? GmailMessage(id: id, threadID: "t1", labelIDs: ["INBOX"], snippet: "Runtime")
    }

    func getMessage(messageID: String, format: GmailMessageFormat) async throws -> GmailMessage { try await getMessage(
        id: messageID,
        format: format,
        metadataHeaders: []
    ) }
    func getAttachment(messageID: String, attachmentID: String) async throws -> GmailAttachment { GmailAttachment(
        id: attachmentID,
        data: ""
    ) }
    func listHistory(
        startHistoryID: String,
        maxResults: Int,
        pageToken: String?,
        labelID: String?,
        historyTypes: [GmailHistoryType]
    ) async throws -> GmailHistoryPage {
        historyCallsValue += 1
        if historyExpired { throw GmailAPIError.httpFailure(statusCode: 404) }
        let message = deltaMessage ?? GmailMessage(id: "m1", threadID: "t1", labelIDs: ["INBOX", "STARRED"], snippet: "Runtime")
        return GmailHistoryPage(
            history: [GmailHistory(
                id: "h1",
                labelsAdded: [GmailHistoryLabelChange(message: GmailMessageReference(id: message.id), labelIDs: ["STARRED"])]
            )],
            historyID: "h1"
        )
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
