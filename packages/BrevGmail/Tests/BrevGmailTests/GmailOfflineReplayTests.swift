/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 */

import BrevBackend
@testable import BrevGmail
import Foundation
import Testing

@Suite("Gmail offline mutation replay")
struct GmailOfflineReplayTests {
    @Test("queues only retryable idempotent mutations without content")
    func queuesRetryableMutation() async throws {
        let client = OfflineClient(failure: .transportFailure)
        let queue = InMemoryMutationQueue()
        let store = InMemoryGmailAccountStore()
        let backend = try await Self.backend(client: client, store: store, queue: queue)

        try await backend.setRead(false, for: ["m1"])

        let pending = try await queue.pending()
        #expect(pending.count == 1)
        #expect(pending[0].kind == .setRead(false))
        #expect(pending[0].messageIDs == ["m1"])
    }

    @Test("replays mutations in order and removes only confirmed successes")
    func replaysInOrder() async throws {
        let client = OfflineClient()
        let queue = InMemoryMutationQueue()
        let store = InMemoryGmailAccountStore()
        let backend = try await Self.backend(client: client, store: store, queue: queue)
        try await queue.enqueue(PendingMutation(kind: .setRead(false), messageIDs: ["m1"]))
        try await queue.enqueue(PendingMutation(kind: .setFlagged(true), messageIDs: ["m1"]))

        await backend.replayOfflineMutations()

        #expect(try await queue.pending().isEmpty)
        #expect(try await Set(store.messageLabelIDs(accountID: Self.account.id, messageID: "m1")) == [
            "INBOX",
            "UNREAD",
            "STARRED"
        ])
        #expect(await client.operationOrder() == ["UNREAD", "STARRED"])
    }

    @Test("permanent authentication failure becomes a conflict and send is never queued")
    func recordsConflictAndExcludesSend() async throws {
        let client = OfflineClient(failure: .reauthenticationRequired)
        let queue = InMemoryMutationQueue()
        let conflicts = InMemoryConflictStore()
        let store = InMemoryGmailAccountStore()
        let backend = try await Self.backend(client: client, store: store, queue: queue, conflicts: conflicts)
        try await queue.enqueue(PendingMutation(kind: .setFlagged(true), messageIDs: ["m1"]))

        await backend.replayOfflineMutations()

        #expect(try await queue.pending().isEmpty)
        #expect(try await conflicts.conflicts().count == 1)
        await #expect(throws: DraftValidationError.self) {
            try await backend.send(draft: Draft(id: "draft-1", subject: "No queue"))
        }
        #expect(try await queue.pending().isEmpty)
    }

    @Test("never queues a failed permanent delete as a trash replay")
    func excludesPermanentDeleteFromQueue() async throws {
        let client = OfflineClient(failure: .transportFailure, messageLabels: ["TRASH"])
        let queue = InMemoryMutationQueue()
        let store = InMemoryGmailAccountStore()
        let backend = try await Self.backend(
            client: client,
            store: store,
            queue: queue,
            messageLabels: ["TRASH"],
            grantedScopes: ["https://mail.google.com/"]
        )

        await #expect(throws: GmailAPIError.transportFailure) {
            try await backend.delete(messageIDs: ["m1"])
        }

        #expect(try await queue.pending().isEmpty)
    }

    private static let account = BrevAccount(
        id: "gmail-api:offline-subject",
        displayName: "Offline User",
        emailAddress: "offline@example.work",
        backendIdentifier: "gmail-api",
        backendDisplayName: "Gmail"
    )

    private static func backend(
        client: OfflineClient,
        store: InMemoryGmailAccountStore,
        queue: InMemoryMutationQueue,
        conflicts: InMemoryConflictStore = InMemoryConflictStore(),
        messageLabels: [String] = ["INBOX"],
        grantedScopes: Set<String> = []
    ) async throws -> GmailAPIBackend {
        try await store.replaceSnapshot(GmailAccountSnapshot(
            accountID: account.id,
            state: GmailAccountState(accountID: account.id, emailAddress: account.emailAddress, historyID: "h1"),
            labels: [
                GmailLabel(id: "INBOX", name: "Inbox", type: "system"),
                GmailLabel(id: "STARRED", name: "Starred", type: "system")
            ],
            messages: [GmailMessage(id: "m1", threadID: "t1", labelIDs: messageLabels)]
        ))
        let backend = GmailAPIBackend(
            account: account,
            transport: client,
            store: store,
            client: client,
            grantedScopes: grantedScopes,
            syncReconciler: nil,
            offlineMutationQueue: queue,
            offlineMutationConflictStore: conflicts
        )
        try await backend.connect()
        return backend
    }
}

private actor InMemoryMutationQueue: OfflineMutationQueue {
    private var values: [PendingMutation] = []
    func enqueue(_ mutation: PendingMutation) throws { values.append(mutation) }
    func pending() throws -> [PendingMutation] { values }
    func update(_ mutation: PendingMutation) throws {
        if let index = values.firstIndex(where: { $0.id == mutation.id }) { values[index] = mutation }
    }

    func remove(id: UUID) throws { values.removeAll { $0.id == id } }
    func removeAll() throws { values.removeAll() }
}

private actor InMemoryConflictStore: OfflineMutationConflictStore {
    private var values: [MutationConflict] = []
    func append(_ conflicts: [MutationConflict]) throws { values.append(contentsOf: conflicts) }
    func conflicts() throws -> [MutationConflict] { values }
    func remove(id: UUID) throws { values.removeAll { $0.id == id } }
    func removeAll() throws { values.removeAll() }
}

private actor OfflineClient: GmailAPIClientProtocol, GmailAPITransporting {
    private let failure: GmailAPIError?
    private var order: [String] = []
    private var messageValue: GmailMessage

    init(failure: GmailAPIError? = nil, messageLabels: [String] = ["INBOX"]) {
        self.failure = failure
        messageValue = GmailMessage(id: "m1", threadID: "t1", labelIDs: messageLabels)
    }

    func operationOrder() -> [String] { order }
    func profile() async throws -> GmailProfile { GmailProfile(emailAddress: "offline@example.work", historyID: "h1") }
    func getProfile() async throws -> GmailProfile { try await profile() }
    func listLabels() async throws -> [GmailLabel] { [
        GmailLabel(id: "INBOX", name: "Inbox", type: "system"),
        GmailLabel(id: "STARRED", name: "Starred", type: "system")
    ] }
    func getLabel(id: String) async throws -> GmailLabel { GmailLabel(id: id, name: id, type: "system") }
    func listMessages(maxResults: Int, pageToken: String?, labelIDs: [String], query: String?,
                      includeSpamTrash: Bool) async throws -> GmailMessagePage { GmailMessagePage() }
    func listMessages(labelID: String?, query: String?, pageToken: String?,
                      maxResults: Int) async throws -> GmailMessagePage { GmailMessagePage() }
    func getMessage(id: String, format: GmailMessageFormat,
                    metadataHeaders: [String]) async throws -> GmailMessage { messageValue }
    func getMessage(messageID: String, format: GmailMessageFormat) async throws -> GmailMessage { messageValue }
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
    ) async throws -> GmailHistoryPage { GmailHistoryPage() }

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

    func modifyMessageLabels(id: String, addLabelIDs: [String], removeLabelIDs: [String]) async throws -> GmailMessage {
        if let failure { throw failure }
        order.append(contentsOf: addLabelIDs)
        let labels = Set(messageValue.labelIDs).subtracting(removeLabelIDs).union(addLabelIDs).sorted()
        messageValue = GmailMessage(id: messageValue.id, threadID: messageValue.threadID, labelIDs: labels)
        return messageValue
    }

    func batchModifyMessageLabels(messageIDs: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {
        if let failure { throw failure }
        _ = try await modifyMessageLabels(id: "m1", addLabelIDs: addLabelIDs, removeLabelIDs: removeLabelIDs)
    }

    func deleteMessage(id: String) async throws {
        if let failure { throw failure }
    }
}
