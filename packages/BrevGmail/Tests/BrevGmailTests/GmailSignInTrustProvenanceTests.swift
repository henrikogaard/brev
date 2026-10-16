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

/// Fresh-delivery provenance and backend gates for ADR-0088 Gmail trust.
@Suite("Gmail sign-in trust provenance")
struct GmailSignInTrustProvenanceTests {
    @Test("delta messagesAdded marks the ID fresh")
    func deltaAddedIsFresh() async throws {
        let client = ProvenanceClient(
            historyPages: [GmailHistoryPage(history: [
                GmailHistory(id: "21", messagesAdded: [.init(message: .init(id: "fresh"))])
            ], historyID: "21")],
            messages: ["fresh": GmailMessage(id: "fresh", labelIDs: ["INBOX"])]
        )
        let store = try await Self.seededStore()
        let outcome = try await GmailSyncReconciler(client: client, store: store, accountID: "acct").syncWithProvenance()
        #expect(outcome.freshDeliveryIDs == ["fresh"])
    }

    @Test("labelsAdded only is not a fresh delivery")
    func labelsAddedNotFresh() async throws {
        let client = ProvenanceClient(
            historyPages: [GmailHistoryPage(history: [
                GmailHistory(id: "21", labelsAdded: [.init(message: .init(id: "old"), labelIDs: ["STARRED"])])
            ], historyID: "21")],
            messages: ["old": GmailMessage(id: "old", labelIDs: ["INBOX", "STARRED"])]
        )
        let store = try await Self.seededStore()
        let outcome = try await GmailSyncReconciler(client: client, store: store, accountID: "acct").syncWithProvenance()
        #expect(outcome.freshDeliveryIDs.isEmpty)
    }

    @Test("added then deleted in the same delta is not fresh")
    func addedThenDeletedNotFresh() async throws {
        let client = ProvenanceClient(
            historyPages: [GmailHistoryPage(history: [
                GmailHistory(id: "21", messagesAdded: [.init(message: .init(id: "ghost"))]),
                GmailHistory(id: "22", messagesDeleted: [.init(message: .init(id: "ghost"))])
            ], historyID: "22")]
        )
        let store = try await Self.seededStore()
        let outcome = try await GmailSyncReconciler(client: client, store: store, accountID: "acct").syncWithProvenance()
        #expect(outcome.freshDeliveryIDs.isEmpty)
    }

    @Test("fullSync reports no fresh deliveries")
    func fullSyncEmptyProvenance() async throws {
        let client = ProvenanceClient(
            messagePages: [GmailMessagePage(messages: [GmailMessageReference(id: "m1")])],
            messages: ["m1": GmailMessage(id: "m1", labelIDs: ["INBOX"])]
        )
        let store = InMemoryGmailAccountStore()
        let outcome = try await GmailSyncReconciler(client: client, store: store, accountID: "acct").syncWithProvenance()
        #expect(outcome.freshDeliveryIDs.isEmpty)
    }

    @Test("sync() delegates to the provenance path and keeps its signature")
    func syncDelegates() async throws {
        let client = ProvenanceClient(
            historyPages: [GmailHistoryPage(history: [
                GmailHistory(id: "21", messagesAdded: [.init(message: .init(id: "fresh"))])
            ], historyID: "21")],
            messages: ["fresh": GmailMessage(id: "fresh", labelIDs: ["INBOX"])]
        )
        let store = try await Self.seededStore()
        let state = try await GmailSyncReconciler(client: client, store: store, accountID: "acct").sync()
        #expect(state.historyID == "21")
    }

    @Test("reconcile 404 fallback registers no fresh deliveries")
    func reconcile404FallbackEmpty() async throws {
        let client = ProvenanceBackendClient(historyError: .httpFailure(statusCode: 404))
        let store = try await Self.seededStore(accountID: Self.account.id)
        let backend = Self.backend(client: client, store: store)
        try await backend.connect()
        await backend.initialSyncSettled()
        let result = await backend.signInTrustAssessment(for: "m1")
        #expect(result == .unavailable(.notFreshDelivery))
    }

    @Test("registry entries expire after ten minutes")
    func registryExpiry() async throws {
        let clock = TestClock()
        let registry = GmailFreshDeliveryRegistry(now: { clock.now })
        registry.record(["m1"])
        #expect(registry.contains("m1"))
        clock.now = clock.now.addingTimeInterval(599)
        #expect(registry.contains("m1"))
        clock.now = clock.now.addingTimeInterval(2)
        #expect(!registry.contains("m1"))
    }

    @Test("registry caps at 200 entries, evicting the oldest")
    func registryCap() {
        let clock = TestClock()
        let registry = GmailFreshDeliveryRegistry(now: { clock.now })
        // Recorded one at a time so insertion order is deterministic: the
        // 201st entry must evict exactly the oldest.
        for index in 0 ..< 200 {
            registry.record(["m\(index)"])
        }
        clock.now = clock.now.addingTimeInterval(1)
        registry.record(["m-new"])
        #expect(registry.contains("m-new"))
        #expect(!registry.contains("m0"))
        #expect(registry.contains("m1"))
    }

    @Test("backend gates on fresh registry, labels, and internalDate")
    func backendGates() async throws {
        let clock = TestClock()
        let freshMessage = GmailMessage(
            id: "m1",
            labelIDs: ["INBOX"],
            internalDate: String(Int64(clock.now.timeIntervalSince1970 * 1000)),
            payload: GmailMessagePart(headers: [
                GmailMessageHeader(name: "Authentication-Results",
                                   value: "mx.google.com; dmarc=pass header.from=bank.example"),
                GmailMessageHeader(name: "From", value: "alerts@bank.example")
            ])
        )
        let client = ProvenanceBackendClient(
            historyPages: [GmailHistoryPage(history: [
                GmailHistory(id: "21", messagesAdded: [.init(message: .init(id: "m1"))])
            ], historyID: "21")],
            messages: ["m1": freshMessage]
        )
        let store = try await Self.seededStore(accountID: Self.account.id)
        let backend = Self.backend(client: client, store: store, now: { clock.now })
        try await backend.connect()
        await backend.initialSyncSettled()
        let result = await backend.signInTrustAssessment(for: "m1")
        let unknown = await backend.signInTrustAssessment(for: "unknown")
        #expect(result == .pass(fromDomain: "bank.example"))
        #expect(unknown == .unavailable(.notFreshDelivery))
    }

    @Test("INBOX message carrying SPAM is rejected")
    func spamLabelRejects() async throws {
        let clock = TestClock()
        let msg = GmailMessage(
            id: "m1",
            labelIDs: ["INBOX", "SPAM"],
            internalDate: String(Int64(clock.now.timeIntervalSince1970 * 1000))
        )
        let client = ProvenanceBackendClient(
            historyPages: [GmailHistoryPage(history: [
                GmailHistory(id: "21", messagesAdded: [.init(message: .init(id: "m1"))])
            ], historyID: "21")],
            messages: ["m1": msg]
        )
        let store = try await Self.seededStore(accountID: Self.account.id)
        let backend = Self.backend(client: client, store: store, now: { clock.now })
        try await backend.connect()
        await backend.initialSyncSettled()
        let result = await backend.signInTrustAssessment(for: "m1")
        #expect(result == .unavailable(.wrongFolder))
    }

    @Test("internalDate older than ten minutes is stale")
    func staleInternalDate() async throws {
        let clock = TestClock()
        let msg = GmailMessage(
            id: "m1",
            labelIDs: ["INBOX"],
            internalDate: String(Int64(clock.now.addingTimeInterval(-601).timeIntervalSince1970 * 1000))
        )
        let client = ProvenanceBackendClient(
            historyPages: [GmailHistoryPage(history: [
                GmailHistory(id: "21", messagesAdded: [.init(message: .init(id: "m1"))])
            ], historyID: "21")],
            messages: ["m1": msg]
        )
        let store = try await Self.seededStore(accountID: Self.account.id)
        let backend = Self.backend(client: client, store: store, now: { clock.now })
        try await backend.connect()
        await backend.initialSyncSettled()
        let result = await backend.signInTrustAssessment(for: "m1")
        #expect(result == .unavailable(.stale))
    }

    @Test("the trusted assessment capability is not advertised")
    func capabilityStaysOff() async throws {
        let client = ProvenanceBackendClient()
        let store = InMemoryGmailAccountStore()
        let backend = Self.backend(client: client, store: store)
        try await backend.connect()
        #expect(!backend.extendedCapabilities.contains(.trustedSignInAssessment))
    }

    private static let account = BrevAccount(
        id: "gmail-api:trust-subject",
        displayName: "Trust User",
        emailAddress: "trust@example.test",
        backendIdentifier: "gmail-api",
        backendDisplayName: "Gmail"
    )

    private static func seededStore(accountID: String = "acct") async throws -> InMemoryGmailAccountStore {
        let store = InMemoryGmailAccountStore()
        try await store.replaceSnapshot(GmailAccountSnapshot(
            accountID: accountID,
            state: GmailAccountState(accountID: accountID, emailAddress: "u@example.test", historyID: "20"),
            labels: [
                GmailLabel(id: "INBOX", name: "Inbox", type: "system"),
                GmailLabel(id: "SPAM", name: "Spam", type: "system")
            ],
            messages: []
        ))
        return store
    }

    private static func backend(
        client: ProvenanceBackendClient,
        store: any GmailAccountStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> GmailAPIBackend {
        let reconciler = GmailSyncReconciler(client: client, store: store, accountID: account.id)
        return GmailAPIBackend(
            account: account,
            transport: client,
            store: store,
            client: client,
            syncReconciler: reconciler,
            signInTrustNow: now
        )
    }
}

/// Mutable clock for expiry tests.
final class TestClock: @unchecked Sendable {
    var now = Date()
}

private actor ProvenanceClient: GmailAPIClientProtocol {
    private let messagePagesValue: [GmailMessagePage]
    private let historyPagesValue: [GmailHistoryPage]
    private let messagesValue: [String: GmailMessage]

    init(
        messagePages: [GmailMessagePage] = [GmailMessagePage()],
        historyPages: [GmailHistoryPage] = [GmailHistoryPage()],
        messages: [String: GmailMessage] = [:]
    ) {
        messagePagesValue = messagePages
        historyPagesValue = historyPages
        messagesValue = messages
    }

    func getProfile() async throws -> GmailProfile { GmailProfile(emailAddress: "u@example.test", historyID: "20") }
    func listLabels() async throws -> [GmailLabel] { [GmailLabel(id: "INBOX", name: "Inbox", type: "system")] }
    func getLabel(id: String) async throws -> GmailLabel { GmailLabel(id: id, name: id) }
    func listMessages(maxResults: Int, pageToken: String?, labelIDs: [String], query: String?,
                      includeSpamTrash: Bool) async throws -> GmailMessagePage {
        messagePagesValue[min(pageToken == nil ? 0 : 1, messagePagesValue.count - 1)]
    }

    func getMessage(id: String, format: GmailMessageFormat, metadataHeaders: [String]) async throws -> GmailMessage {
        messagesValue[id] ?? GmailMessage(id: id)
    }

    func getAttachment(messageID: String, attachmentID: String) async throws -> GmailAttachment {
        .init(id: attachmentID, messageID: messageID)
    }

    func listHistory(startHistoryID: String, maxResults: Int, pageToken: String?, labelID: String?,
                     historyTypes: [GmailHistoryType]) async throws -> GmailHistoryPage {
        historyPagesValue[min(pageToken == nil ? 0 : 1, historyPagesValue.count - 1)]
    }

    func modifyMessageLabels(id: String, addLabelIDs: [String], removeLabelIDs: [String]) async throws -> GmailMessage {
        throw GmailAPIError.invalidRequest
    }

    func modifyThreadLabels(id: String, addLabelIDs: [String], removeLabelIDs: [String]) async throws -> GmailThread {
        throw GmailAPIError.invalidRequest
    }

    func trashMessage(id: String) async throws -> GmailMessage { throw GmailAPIError.invalidRequest }
    func untrashMessage(id: String) async throws -> GmailMessage { throw GmailAPIError.invalidRequest }
    func deleteMessage(id: String) async throws { throw GmailAPIError.invalidRequest }
    func trashThread(id: String) async throws -> GmailThread { throw GmailAPIError.invalidRequest }
    func untrashThread(id: String) async throws -> GmailThread { throw GmailAPIError.invalidRequest }
    func deleteThread(id: String) async throws { throw GmailAPIError.invalidRequest }
    func batchModifyMessageLabels(messageIDs: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {
        throw GmailAPIError.invalidRequest
    }

    func createLabel(_ label: GmailLabelWrite) async throws -> GmailLabel { throw GmailAPIError.invalidRequest }
    func patchLabel(id: String, with label: GmailLabelWrite) async throws -> GmailLabel {
        throw GmailAPIError.invalidRequest
    }

    func deleteLabel(id: String) async throws { throw GmailAPIError.invalidRequest }
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

    func listSendAs() async throws -> [GmailSendAs] { [] }
}

/// Backend-shaped fake covering the client plus transport protocols.
private actor ProvenanceBackendClient: GmailAPIClientProtocol, GmailAPITransporting {
    private let historyPagesValue: [GmailHistoryPage]
    private let messagesValue: [String: GmailMessage]
    private let historyError: GmailAPIError?

    init(
        historyPages: [GmailHistoryPage] = [GmailHistoryPage()],
        messages: [String: GmailMessage] = [:],
        historyError: GmailAPIError? = nil
    ) {
        historyPagesValue = historyPages
        messagesValue = messages
        self.historyError = historyError
    }

    func profile() async throws -> GmailProfile { GmailProfile(emailAddress: "u@example.test", historyID: "20") }
    func getProfile() async throws -> GmailProfile { GmailProfile(emailAddress: "u@example.test", historyID: "20") }
    func listLabels() async throws -> [GmailLabel] { [GmailLabel(id: "INBOX", name: "Inbox", type: "system")] }
    func getLabel(id: String) async throws -> GmailLabel { GmailLabel(id: id, name: id) }
    func listMessages(labelID: String?, query: String?, pageToken: String?,
                      maxResults: Int) async throws -> GmailMessagePage { GmailMessagePage() }
    func listMessages(maxResults: Int, pageToken: String?, labelIDs: [String], query: String?,
                      includeSpamTrash: Bool) async throws -> GmailMessagePage { GmailMessagePage() }
    func getMessage(messageID: String, format: GmailMessageFormat) async throws -> GmailMessage {
        messagesValue[messageID] ?? GmailMessage(id: messageID)
    }

    func getMessage(messageID: String, format: GmailMessageFormat, metadataHeaders: [String]) async throws -> GmailMessage {
        messagesValue[messageID] ?? GmailMessage(id: messageID)
    }

    func getMessage(id: String, format: GmailMessageFormat, metadataHeaders: [String]) async throws -> GmailMessage {
        messagesValue[id] ?? GmailMessage(id: id)
    }

    func getAttachment(messageID: String, attachmentID: String) async throws -> GmailAttachment {
        .init(id: attachmentID, messageID: messageID)
    }

    func listHistory(startHistoryID: String, maxResults: Int, pageToken: String?, labelID: String?,
                     historyTypes: [GmailHistoryType]) async throws -> GmailHistoryPage {
        if let historyError { throw historyError }
        return historyPagesValue[0]
    }

    func modifyMessageLabels(id: String, addLabelIDs: [String], removeLabelIDs: [String]) async throws -> GmailMessage {
        throw GmailAPIError.invalidRequest
    }

    func modifyThreadLabels(id: String, addLabelIDs: [String], removeLabelIDs: [String]) async throws -> GmailThread {
        throw GmailAPIError.invalidRequest
    }

    func trashMessage(id: String) async throws -> GmailMessage { throw GmailAPIError.invalidRequest }
    func untrashMessage(id: String) async throws -> GmailMessage { throw GmailAPIError.invalidRequest }
    func deleteMessage(id: String) async throws { throw GmailAPIError.invalidRequest }
    func trashThread(id: String) async throws -> GmailThread { throw GmailAPIError.invalidRequest }
    func untrashThread(id: String) async throws -> GmailThread { throw GmailAPIError.invalidRequest }
    func deleteThread(id: String) async throws { throw GmailAPIError.invalidRequest }
    func batchModifyMessageLabels(messageIDs: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {
        throw GmailAPIError.invalidRequest
    }

    func createLabel(_ label: GmailLabelWrite) async throws -> GmailLabel { throw GmailAPIError.invalidRequest }
    func patchLabel(id: String, with label: GmailLabelWrite) async throws -> GmailLabel {
        throw GmailAPIError.invalidRequest
    }

    func deleteLabel(id: String) async throws { throw GmailAPIError.invalidRequest }
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

    func listSendAs() async throws -> [GmailSendAs] { [] }
}
