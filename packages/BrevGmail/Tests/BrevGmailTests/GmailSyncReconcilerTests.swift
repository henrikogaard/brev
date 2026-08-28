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

@testable import BrevGmail
import Foundation
import Testing

@Suite("Gmail sync reconciler")
struct GmailSyncReconcilerTests {
    @Test("default initial sync stays below Gmail's per-user minute quota")
    func defaultInitialSyncFitsQuota() {
        let configuration = GmailSyncConfiguration()
        let detailUnits = configuration.maxInitialMessages * 20
        let listPages = Int(ceil(Double(configuration.maxInitialMessages) / Double(configuration.pageSize)))
        let listUnits = listPages * 5
        let profileAndLabelsUnits = 2

        #expect(configuration.maxConcurrentDetailFetches == 10)
        #expect(configuration.maxInitialMessages == 250)
        #expect(detailUnits + listUnits + profileAndLabelsUnits <= 6000)
    }

    @Test("full sync paginates references, deduplicates IDs, and commits cursor atomically")
    func fullSync() async throws {
        let client = FakeGmailClient(
            profile: GmailProfile(emailAddress: "user@example.com", historyID: "20"),
            labels: [GmailLabel(id: "INBOX", name: "Inbox")],
            messagePages: [
                GmailMessagePage(
                    messages: [GmailMessageReference(id: "m1"), GmailMessageReference(id: "m2")],
                    nextPageToken: "next"
                ),
                GmailMessagePage(messages: [GmailMessageReference(id: "m2"), GmailMessageReference(id: "m3")])
            ],
            messages: [
                "m1": GmailMessage(id: "m1", threadID: "t1"),
                "m2": GmailMessage(id: "m2", threadID: "t2"),
                "m3": GmailMessage(id: "m3", threadID: "t3")
            ]
        )
        let store = InMemoryGmailAccountStore()
        let reconciler = GmailSyncReconciler(client: client, store: store, accountID: "acct")

        _ = try await reconciler.fullSync()

        #expect(try await store.messages(accountID: "acct").map(\.id) == ["m1", "m2", "m3"])
        #expect(try await store.accountState(accountID: "acct")?.historyID == "20")
        #expect(await client.maxConcurrentDetails() <= 50)
        #expect(await client.requestedMessageIDs().sorted() == ["m1", "m2", "m3"])
    }

    @Test("full sync stops enumerating when the initial cache limit is reached")
    func fullSyncInitialCacheLimit() async throws {
        let client = FakeGmailClient(
            profile: GmailProfile(emailAddress: "user@example.com", historyID: "20"),
            messagePages: [
                GmailMessagePage(
                    messages: [
                        GmailMessageReference(id: "m1"),
                        GmailMessageReference(id: "m2"),
                        GmailMessageReference(id: "m3")
                    ],
                    nextPageToken: "next"
                ),
                GmailMessagePage(messages: [GmailMessageReference(id: "m4")])
            ]
        )
        let store = InMemoryGmailAccountStore()
        let reconciler = GmailSyncReconciler(
            client: client,
            store: store,
            accountID: "acct",
            configuration: GmailSyncConfiguration(
                maxConcurrentDetailFetches: 2,
                pageSize: 100,
                maxInitialMessages: 2
            )
        )

        _ = try await reconciler.fullSync()

        #expect(try await store.messages(accountID: "acct").map(\.id) == ["m1", "m2"])
        #expect(await client.listMessageRequestCount() == 1)
        #expect(await client.requestedMessageIDs().sorted() == ["m1", "m2"])
    }

    @Test("full sync requests the metadata headers needed by cached headers")
    func fullSyncRequestsRequiredMetadataHeaders() async throws {
        let client = FakeGmailClient(
            profile: GmailProfile(emailAddress: "user@example.com", historyID: "20"),
            messagePages: [GmailMessagePage(messages: [.init(id: "m1")])]
        )
        let store = InMemoryGmailAccountStore()
        _ = try await GmailSyncReconciler(client: client, store: store, accountID: "acct").fullSync()

        #expect(await client.metadataHeaders() == GmailAPIClient.requiredMetadataHeaders)
    }

    @Test("delta sync applies chronological add/delete/label changes and is idempotent")
    func deltaSync() async throws {
        let client = FakeGmailClient(
            profile: GmailProfile(emailAddress: "user@example.com", historyID: "30"),
            historyPages: [GmailHistoryPage(history: [
                GmailHistory(id: "21", messagesAdded: [.init(message: .init(id: "new"))]),
                GmailHistory(id: "22", labelsAdded: [.init(message: .init(id: "old"), labelIDs: ["STARRED"])]),
                GmailHistory(id: "23", messagesDeleted: [.init(message: .init(id: "gone"))])
            ], historyID: "23")],
            messages: [
                "new": GmailMessage(id: "new", labelIDs: ["INBOX"]),
                "old": GmailMessage(id: "old", labelIDs: ["STARRED"])
            ]
        )
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(GmailAccountSnapshot(
            accountID: "acct",
            state: GmailAccountState(accountID: "acct", emailAddress: "user@example.com", historyID: "20"),
            labels: [GmailLabel(id: "INBOX", name: "Inbox"), GmailLabel(id: "STARRED", name: "Starred")],
            messages: [GmailMessage(id: "old"), GmailMessage(id: "gone")]
        ))
        let reconciler = GmailSyncReconciler(client: client, store: store, accountID: "acct")

        _ = try await reconciler.deltaSync()
        _ = try await reconciler.deltaSync()

        #expect(try await store.messages(accountID: "acct").map(\.id) == ["new", "old"])
        #expect(try await store.messageLabelIDs(accountID: "acct", messageID: "old") == ["STARRED"])
        #expect(try await store.accountState(accountID: "acct")?.historyID == "23")
    }

    @Test("delta sync refreshes the label catalog and removes stale label joins")
    func deltaSyncRefreshesLabels() async throws {
        let client = FakeGmailClient(
            profile: GmailProfile(emailAddress: "user@example.com", historyID: "30"),
            labels: [GmailLabel(id: "INBOX", name: "Inbox")],
            historyPages: [GmailHistoryPage(historyID: "21")]
        )
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(GmailAccountSnapshot(
            accountID: "acct",
            state: GmailAccountState(accountID: "acct", emailAddress: "user@example.com", historyID: "20"),
            labels: [GmailLabel(id: "INBOX", name: "Inbox"), GmailLabel(id: "old", name: "Old")],
            messages: [GmailMessage(id: "m1", labelIDs: ["old"])]
        ))

        _ = try await GmailSyncReconciler(client: client, store: store, accountID: "acct").deltaSync()

        #expect(try await store.labels(accountID: "acct").map(\.id) == ["INBOX"])
        #expect(try await store.messageLabelIDs(accountID: "acct", messageID: "m1").isEmpty)
    }

    @Test("history 404 preserves cursor and requests a full sync")
    func expiredHistory() async throws {
        let client = FakeGmailClient(
            profile: GmailProfile(emailAddress: "user@example.com", historyID: "30"),
            historyError: .httpFailure(statusCode: 404)
        )
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(GmailAccountSnapshot(
            accountID: "acct",
            state: GmailAccountState(accountID: "acct", emailAddress: "user@example.com", historyID: "20"),
            labels: [],
            messages: []
        ))
        let reconciler = GmailSyncReconciler(client: client, store: store, accountID: "acct")

        do {
            _ = try await reconciler.deltaSync()
            Issue.record("Expected a full-sync-required error")
        } catch let error as GmailSyncError {
            #expect(error == .fullSyncRequired(historyID: "20"))
        }
        #expect(try await store.accountState(accountID: "acct")?.historyID == "20")
    }

    @Test("history pagination rejects repeated cursors without committing")
    func repeatedHistoryCursor() async throws {
        let client = FakeGmailClient(
            profile: GmailProfile(emailAddress: "user@example.com", historyID: "30"),
            historyPages: [GmailHistoryPage(nextPageToken: "same")]
        )
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(GmailAccountSnapshot(
            accountID: "acct",
            state: GmailAccountState(accountID: "acct", emailAddress: "user@example.com", historyID: "20"),
            labels: [],
            messages: []
        ))

        do {
            _ = try await GmailSyncReconciler(
                client: client,
                store: store,
                accountID: "acct",
                configuration: GmailSyncConfiguration(maxHistoryPages: 3)
            ).deltaSync()
            Issue.record("Expected repeated cursor rejection")
        } catch let error as GmailSyncError {
            guard case .repeatedHistoryPageToken("same") = error else {
                Issue.record("Unexpected sync error: \(error)")
                return
            }
        }
        #expect(try await store.accountState(accountID: "acct")?.historyID == "20")
    }

    @Test("history pagination is bounded before commit")
    func historyPageLimit() async throws {
        let client = FakeGmailClient(
            profile: GmailProfile(emailAddress: "user@example.com", historyID: "30"),
            historyPages: [GmailHistoryPage(nextPageToken: "next")]
        )
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(GmailAccountSnapshot(
            accountID: "acct",
            state: GmailAccountState(accountID: "acct", emailAddress: "user@example.com", historyID: "20"),
            labels: [],
            messages: []
        ))

        do {
            _ = try await GmailSyncReconciler(
                client: client,
                store: store,
                accountID: "acct",
                configuration: GmailSyncConfiguration(maxHistoryPages: 1)
            ).deltaSync()
            Issue.record("Expected history page limit")
        } catch let error as GmailSyncError {
            guard case .historyPaginationLimitExceeded(limit: 1) = error else {
                Issue.record("Unexpected sync error: \(error)")
                return
            }
        }
        #expect(try await store.accountState(accountID: "acct")?.historyID == "20")
    }

    @Test("cancellation stops a full sync before replacing the snapshot")
    func cancellation() async throws {
        let client = FakeGmailClient(
            profile: GmailProfile(emailAddress: "user@example.com", historyID: "20"),
            messagePages: [GmailMessagePage(messages: [.init(id: "m1")])],
            messages: ["m1": GmailMessage(id: "m1")]
        )
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(GmailAccountSnapshot(
            accountID: "acct",
            state: GmailAccountState(accountID: "acct", emailAddress: "user@example.com", historyID: "10"),
            labels: [],
            messages: [GmailMessage(id: "old")]
        ))
        let reconciler = GmailSyncReconciler(client: client, store: store, accountID: "acct")
        let task = Task { try await reconciler.fullSync() }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
        #expect(try await store.accountState(accountID: "acct")?.historyID == "10")
        #expect(try await store.messages(accountID: "acct").map(\.id) == ["old"])
    }
}

private final class FakeGmailClient: GmailAPIClientProtocol, @unchecked Sendable {
    let profileValue: GmailProfile
    let labelsValue: [GmailLabel]
    let messagePagesValue: [GmailMessagePage]
    let historyPagesValue: [GmailHistoryPage]
    let messagesValue: [String: GmailMessage]
    let historyError: GmailAPIError?
    private let lock = NSLock()
    private var ids: [String] = []
    private var active = 0
    private var maximum = 0
    private var listMessageRequests = 0
    private var metadataHeaderValues: [[String]] = []

    init(
        profile: GmailProfile,
        labels: [GmailLabel] = [],
        messagePages: [GmailMessagePage] = [GmailMessagePage()],
        historyPages: [GmailHistoryPage] = [GmailHistoryPage()],
        messages: [String: GmailMessage] = [:],
        historyError: GmailAPIError? = nil
    ) {
        profileValue = profile
        labelsValue = labels
        messagePagesValue = messagePages
        historyPagesValue = historyPages
        messagesValue = messages
        self.historyError = historyError
    }

    func getProfile() async throws -> GmailProfile { profileValue }
    func listLabels() async throws -> [GmailLabel] { labelsValue }
    func getLabel(id: String) async throws -> GmailLabel { labelsValue.first { $0.id == id }! }
    func listMessages(maxResults: Int, pageToken: String?, labelIDs: [String], query: String?,
                      includeSpamTrash: Bool) async throws -> GmailMessagePage {
        lock.withLock { listMessageRequests += 1 }
        let index = pageToken == nil ? 0 : 1
        return messagePagesValue[min(index, messagePagesValue.count - 1)]
    }

    func getMessage(id: String, format: GmailMessageFormat, metadataHeaders: [String]) async throws -> GmailMessage {
        lock.withLock { metadataHeaderValues.append(metadataHeaders) }
        recordStart(id)
        defer { recordEnd() }
        return messagesValue[id] ?? GmailMessage(id: id)
    }

    func getAttachment(messageID: String, attachmentID: String) async throws -> GmailAttachment { .init(
        id: attachmentID,
        messageID: messageID
    ) }
    func listHistory(
        startHistoryID: String,
        maxResults: Int,
        pageToken: String?,
        labelID: String?,
        historyTypes: [GmailHistoryType]
    ) async throws -> GmailHistoryPage {
        if let historyError { throw historyError }
        return historyPagesValue[0]
    }

    func requestedMessageIDs() async -> [String] { lock.withLock { ids } }
    func maxConcurrentDetails() async -> Int { lock.withLock { maximum } }
    func listMessageRequestCount() async -> Int { lock.withLock { listMessageRequests } }
    func metadataHeaders() async -> [String] { lock.withLock { metadataHeaderValues.last ?? [] } }

    private func recordStart(_ id: String) {
        lock.withLock {
            active += 1
            maximum = max(maximum, active)
            ids.append(id)
        }
    }

    private func recordEnd() {
        lock.withLock { active -= 1 }
    }
}
