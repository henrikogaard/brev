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

@Suite("Gmail API native mutations")
struct GmailAPIMutationTests {
    @Test("sets read/starred and preserves unrelated labels")
    func setsFlags() async throws {
        let client = MutationClient(messages: [Self.message(labels: ["INBOX", "IMPORTANT"])])
        let store = InMemoryGmailAccountStore()
        let backend = try await Self.backend(client: client, store: store)
        let mailBackend: any MailBackend = backend

        try await mailBackend.setRead(false, for: ["m1"])
        try await mailBackend.setFlagged(true, for: ["m1"])

        let labels = try await store.messageLabelIDs(accountID: Self.account.id, messageID: "m1")
        #expect(Set(labels) == ["INBOX", "IMPORTANT", "UNREAD", "STARRED"])
    }

    @Test("archive and move use canonical labels without dropping unrelated labels")
    func archivesAndMoves() async throws {
        let client = MutationClient(messages: [Self.message(labels: ["INBOX", "ALL_MAIL", "IMPORTANT", "label-work"])])
        let store = InMemoryGmailAccountStore()
        let backend = try await Self.backend(client: client, store: store)
        let mailBackend: any MailBackend = backend
        let archive = Folder(id: "ALL_MAIL", name: "All Mail", role: .allMail)
        let project = Folder(id: "label-projects", name: "Projects", role: .custom)

        try await mailBackend.move(messageIDs: ["m1"], to: archive)
        try await mailBackend.move(messageIDs: ["m1"], to: project)

        let labels = try await store.messageLabelIDs(accountID: Self.account.id, messageID: "m1")
        #expect(Set(labels) == ["ALL_MAIL", "IMPORTANT", "label-work", "label-projects"])
    }

    @Test("move Undo restores label changes without dropping pre-existing labels")
    func moveUndoRestoresLabels() async throws {
        let original = ["INBOX", "ALL_MAIL", "IMPORTANT", "label-work"]
        let client = MutationClient(messages: [Self.message(labels: original)])
        let store = InMemoryGmailAccountStore()
        let backend = try await Self.backend(client: client, store: store)
        let receipt = try #require(try await backend.moveWithUndo(
            messageIDs: ["m1"], from: Folder(id: "INBOX", name: "Inbox", role: .inbox),
            to: Folder(id: "label-projects", name: "Projects", role: .custom),
            sourceID: MailSourceID(accountID: Self.account.id, mailboxID: Self.account.id)
        ))
        #expect(try await Set(store.messageLabelIDs(accountID: Self.account.id, messageID: "m1"))
            == ["ALL_MAIL", "IMPORTANT", "label-work", "label-projects"])
        let restored = try await receipt.restore()
        #expect(restored == ["m1": "m1"])
        #expect(try await Set(store.messageLabelIDs(accountID: Self.account.id, messageID: "m1")) == Set(original))
    }

    @Test("retrying a partially restored Gmail move skips completed messages")
    func moveUndoRetrySkipsRestoredMessages() async throws {
        let messages = ["m1", "m2"].map { GmailMessage(id: $0, threadID: $0, labelIDs: ["INBOX"], snippet: "") }
        let client = MutationClient(messages: messages)
        let store = InMemoryGmailAccountStore()
        let backend = try await Self.backend(client: client, store: store)
        try await store.apply(GmailStoreDelta(accountID: Self.account.id, upsertedMessages: messages))
        let receipt = try #require(try await backend.moveWithUndo(
            messageIDs: ["m1", "m2"], from: Folder(id: "INBOX", name: "Inbox", role: .inbox),
            to: Folder(id: "ALL_MAIL", name: "All Mail", role: .allMail),
            sourceID: MailSourceID(accountID: Self.account.id, mailboxID: Self.account.id)
        ))
        await client.failNextModify(id: "m2")
        await #expect(throws: GmailAPIError.self) { _ = try await receipt.restore() }
        _ = try await receipt.restore()
        #expect(await client.modifiedMessageIDs() == ["m1", "m2", "m2"])
    }

    @Test("junk, trash, restore, and scope-gated permanent delete are native")
    func junkTrashRestoreAndPermanentDelete() async throws {
        let client = MutationClient(messages: [Self.message(labels: ["INBOX"])])
        let store = InMemoryGmailAccountStore()
        let backend = try await Self.backend(client: client, store: store)
        let mailBackend: any MailBackend = backend

        try await mailBackend.setJunk(true, for: ["m1"])
        #expect(try await Set(store.messageLabelIDs(accountID: Self.account.id, messageID: "m1")) == ["SPAM"])
        try await mailBackend.setJunk(false, for: ["m1"])
        #expect(try await Set(store.messageLabelIDs(accountID: Self.account.id, messageID: "m1")) == ["INBOX"])
        try await mailBackend.delete(messageIDs: ["m1"])
        #expect(await client.trashCount() == 1)

        try await mailBackend.move(
            messageIDs: ["m1"],
            to: Folder(id: "INBOX", name: "Inbox", role: .inbox)
        )
        try await mailBackend.delete(messageIDs: ["m1"])

        let noDeleteScope = GmailAPIBackend(
            account: Self.account,
            transport: client,
            store: store,
            client: client,
            grantedScopes: []
        )
        try await noDeleteScope.connect()
        do {
            try await noDeleteScope.delete(messageIDs: ["m1"])
            Issue.record("Expected permanent deletion to require mail.google.com")
        } catch let error as MailBackendError {
            guard case .notSupported = error else { Issue.record("Unexpected error"); return }
        }

        let permanentDeleteBackend = GmailAPIBackend(
            account: Self.account,
            transport: client,
            store: store,
            client: client,
            grantedScopes: ["https://mail.google.com/"]
        )
        try await permanentDeleteBackend.connect()
        try await permanentDeleteBackend
            .delete(messageIDs: ["m1"])
        #expect(await client.deleteCount() == 1)
    }

    @Test("message labels and catalog are exposed through provider-neutral extensions")
    func exposesLabelExtensions() async throws {
        let client = MutationClient(messages: [Self.message(labels: ["INBOX"])])
        let store = InMemoryGmailAccountStore()
        let backend = try await Self.backend(client: client, store: store)
        let mailBackend: any MailBackend = backend
        let source = MailSourceID(accountID: Self.account.id, mailboxID: Self.account.id)
        let labels = try #require(mailBackend.extensionService(ProviderLabelCatalogManaging.self))
        let messageLabels = try #require(mailBackend.extensionService(MessageLabelManaging.self))

        let catalog = try await labels.labelCatalog(for: source)
        let work = try #require(catalog.first { $0.id == "label-work" })
        let inbox = try #require(catalog.first { $0.id == "INBOX" })
        #expect(work.parentID == "label-parent")
        #expect(work.color?.backgroundHex == "#123456")
        #expect(work.canRename)
        #expect(inbox.isSystem)
        #expect(inbox.canRename == false)
        #expect(inbox.canDelete == false)

        try await messageLabels.setLabels(["Work"], isEnabled: true, for: ["m1"], sourceID: source)
        #expect(try await Set(store.messageLabelIDs(accountID: Self.account.id, messageID: "m1")) == ["INBOX", "label-work"])
        _ = try await labels.createLabel(name: "Child", parentID: "label-parent", sourceID: source)
        _ = try await labels.updateLabel(
            id: "label-work",
            visibility: ProviderLabelVisibility(sidebar: .hidden, messageList: .shown),
            color: ProviderLabelColor(backgroundHex: "#abcdef"),
            sourceID: source
        )
        try await labels.deleteLabel(id: "label-work", sourceID: source)
        #expect(await client.createdLabelNames() == ["Parent/Child"])
    }

    @Test("provider failure leaves local labels unchanged")
    func rollsBackOnProviderFailure() async throws {
        let client = MutationClient(messages: [Self.message(labels: ["INBOX"])], shouldFailWrites: true)
        let store = InMemoryGmailAccountStore()
        let backend = try await Self.backend(client: client, store: store)
        let mailBackend: any MailBackend = backend
        do {
            try await mailBackend.setFlagged(true, for: ["m1"])
            Issue.record("Expected provider failure")
        } catch is GmailAPIError {
            // Expected; the local canonical message must remain unchanged.
        }
        #expect(try await store.messageLabelIDs(accountID: Self.account.id, messageID: "m1") == ["INBOX"])
    }

    private static let account = BrevAccount(
        id: "gmail-api:subject",
        displayName: "Workspace User",
        emailAddress: "user@example.work",
        backendIdentifier: "gmail-api",
        backendDisplayName: "Gmail"
    )

    private static func message(labels: [String]) -> GmailMessage {
        GmailMessage(id: "m1", threadID: "t1", labelIDs: labels, snippet: "Test")
    }

    private static func backend(
        client: MutationClient,
        store: InMemoryGmailAccountStore,
        grantedScopes: Set<String> = ["https://mail.google.com/"]
    ) async throws -> GmailAPIBackend {
        try await store.replaceSnapshot(GmailAccountSnapshot(
            accountID: account.id,
            state: GmailAccountState(accountID: account.id, emailAddress: account.emailAddress),
            labels: client.labelCatalog,
            messages: [message(labels: ["INBOX"])].map { original in
                client.messageSnapshot ?? original
            }
        ))
        let backend = GmailAPIBackend(
            account: account,
            transport: client,
            store: store,
            client: client,
            grantedScopes: grantedScopes
        )
        try await backend.connect()
        return backend
    }
}

private actor MutationClient: GmailAPIClientProtocol, GmailAPITransporting {
    private var messages: [String: GmailMessage]
    let labelCatalog: [GmailLabel] = [
        GmailLabel(id: "INBOX", name: "Inbox", type: "system"),
        GmailLabel(id: "SPAM", name: "Spam", type: "system"),
        GmailLabel(id: "TRASH", name: "Trash", type: "system"),
        GmailLabel(id: "IMPORTANT", name: "Important", type: "system"),
        GmailLabel(id: "label-parent", name: "Parent", type: "user"),
        GmailLabel(id: "label-work", name: "Parent/Work", type: "user", color: GmailLabelColor(backgroundColor: "#123456"))
    ]
    let messageSnapshot: GmailMessage?
    private let shouldFailWrites: Bool
    private var trashOperations = 0
    private var permanentDeletes = 0
    private var createdNames: [String] = []
    private var failedModifyID: String?
    private var modifiedIDs: [String] = []

    func failNextModify(id: String) { failedModifyID = id; modifiedIDs = [] }
    func modifiedMessageIDs() -> [String] { modifiedIDs }

    init(messages: [GmailMessage], shouldFailWrites: Bool = false) {
        self.messages = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        messageSnapshot = messages.first
        self.shouldFailWrites = shouldFailWrites
    }

    func profile() async throws -> GmailProfile { GmailProfile(emailAddress: "user@example.work", historyID: "h1") }
    func getProfile() async throws -> GmailProfile { try await profile() }
    func listLabels() async throws -> [GmailLabel] { labelCatalog }
    func getLabel(id: String) async throws -> GmailLabel { try #require(labelCatalog.first { $0.id == id }) }
    func listMessages(maxResults: Int, pageToken: String?, labelIDs: [String], query: String?,
                      includeSpamTrash: Bool) async throws -> GmailMessagePage { GmailMessagePage() }
    func listMessages(labelID: String?, query: String?, pageToken: String?,
                      maxResults: Int) async throws -> GmailMessagePage { GmailMessagePage() }
    func getMessage(id: String, format: GmailMessageFormat,
                    metadataHeaders: [String]) async throws -> GmailMessage { try message(id: id) }
    func getMessage(messageID: String, format: GmailMessageFormat) async throws -> GmailMessage { try message(id: messageID) }
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
        modifiedIDs.append(id)
        if failedModifyID == id {
            failedModifyID = nil
            throw GmailAPIError.invalidRequest
        }
        return try mutate(id: id, add: addLabelIDs, remove: removeLabelIDs)
    }

    func batchModifyMessageLabels(messageIDs: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {
        for id in messageIDs {
            _ = try mutate(id: id, add: addLabelIDs, remove: removeLabelIDs)
        }
    }

    func trashMessage(id: String) async throws -> GmailMessage { trashOperations += 1; return try mutate(
        id: id,
        add: ["TRASH"],
        remove: ["INBOX"]
    ) }
    func untrashMessage(id: String) async throws -> GmailMessage { try mutate(id: id, add: ["INBOX"], remove: ["TRASH"]) }
    func deleteMessage(id: String) async throws {
        if shouldFailWrites { throw GmailAPIError.httpFailure(statusCode: 500) }; permanentDeletes += 1; messages
            .removeValue(forKey: id)
    }

    func createLabel(_ label: GmailLabelWrite) async throws -> GmailLabel {
        if shouldFailWrites { throw GmailAPIError.httpFailure(statusCode: 500) }
        let created = GmailLabel(id: "label-created", name: label.name ?? "")
        createdNames.append(created.name)
        return created
    }

    func patchLabel(id: String, with label: GmailLabelWrite) async throws -> GmailLabel {
        if shouldFailWrites { throw GmailAPIError.httpFailure(statusCode: 500) }
        let current = try #require(labelCatalog.first { $0.id == id })
        return GmailLabel(
            id: id,
            name: label.name ?? current.name,
            type: current.type,
            labelListVisibility: label.labelListVisibility ?? current.labelListVisibility,
            messageListVisibility: label.messageListVisibility ?? current.messageListVisibility,
            color: label.color ?? current.color
        )
    }

    func deleteLabel(id: String) async throws { if shouldFailWrites { throw GmailAPIError.httpFailure(statusCode: 500) } }

    func message(id: String) throws -> GmailMessage { try #require(messages[id]) }
    func mutate(id: String, add: [String], remove: [String]) throws -> GmailMessage {
        if shouldFailWrites { throw GmailAPIError.httpFailure(statusCode: 500) }
        let current = try message(id: id)
        let labels = (Set(current.labelIDs).subtracting(remove).union(add)).sorted()
        let updated = GmailMessage(
            id: current.id,
            threadID: current.threadID,
            labelIDs: labels,
            snippet: current.snippet,
            historyID: current.historyID,
            internalDate: current.internalDate,
            sizeEstimate: current.sizeEstimate,
            payload: current.payload,
            raw: current.raw
        )
        messages[id] = updated
        return updated
    }

    func trashCount() -> Int { trashOperations }
    func deleteCount() -> Int { permanentDeletes }
    func createdLabelNames() -> [String] { createdNames }
}
