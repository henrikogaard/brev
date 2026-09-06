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
@testable import BrevMail
import Foundation
import Testing

@Suite("Mail Undo selection restoration")
@MainActor
struct MailUndoSelectionTests {
    @Test("Undo reselects the restored message using the provider's new identity")
    func restoresSelectedMessage() async {
        let fixture = SelectionUndoFixture()
        fixture.register()
        #expect(await fixture.queue.undo()?.value == true)
        #expect(fixture.navigation.selectedSourceID == fixture.source)
        #expect(fixture.navigation.selectedMessageID == "INBOX:99")
        #expect(fixture.navigation.selectedHeader?.subject == "Original message")
        #expect(fixture.navigation.selectedHeader?.rfcMessageID == nil)
        #expect(fixture.navigation.selectedHeader?.replyTo.first?.email == "reply@example.org")
        #expect(fixture.navigation.selectedHeader?.hasAttachments == true)

        // Refresh may initially contain only a page of newer messages.
        fixture.navigation.replaceCurrentFolderHeaders([fixture.neighbor])
        #expect(fixture.navigation.selectedMessageID == "INBOX:99")
        #expect(fixture.navigation.selectedHeader?.id == "INBOX:99")
    }

    @Test("Undo of a junk fallback restores the selected message")
    func restoresJunkSelection() async throws {
        let fixture = SelectionUndoFixture()
        let spam = Folder(id: "Spam", name: "Spam", role: .spam)
        let account = BrevAccount(id: fixture.source.accountID, displayName: "Test", emailAddress: "user@example.org")
        let mailbox = Mailbox(id: fixture.source.mailboxID, email: account.emailAddress, displayName: "Test", isPrimary: true)
        let backend = MockBackend(account: account, capabilities: [], folders: [fixture.inbox, spam],
                                  messagesByFolder: [fixture.inbox.id: [fixture.original, fixture.neighbor]],
                                  mailboxes: [mailbox])
        try await backend.connect()
        let action = try await MailJunkUndo.perform(true, header: fixture.original, folders: [fixture.inbox, spam],
                                                    sourceID: fixture.source, backend: backend, lease: fixture.lease)
        fixture.queue.registerBatch([action], description: "Junk", lease: fixture.lease)
        fixture.queue.endMutation(fixture.lease)
        #expect(await fixture.queue.undo()?.value == true)
        #expect(fixture.navigation.selectedMessageID == fixture.original.id)
    }

    @Test("Undo restores server state without changing a different folder")
    func preservesAnotherFolder() async {
        let fixture = SelectionUndoFixture()
        fixture.register()
        fixture.navigation.selectFolder("Sent", in: fixture.source)
        #expect(await fixture.queue.undo()?.value == true)
        #expect(fixture.navigation.selectedFolderID == "Sent")
        #expect(fixture.navigation.selectedMessageID == nil)
    }

    @Test("a same-view selection made while Undo runs keeps focus")
    func preservesSelectionDuringUndo() async {
        let fixture = SelectionUndoFixture()
        let gate = SelectionUndoGate()
        fixture.register { await gate.restore() }
        let task = fixture.queue.undo()
        await gate.waitUntilStarted()
        let chosen = fixture.neighbor.withIdentity("INBOX:45", folderID: "INBOX")
        fixture.navigation.selectMessage(chosen, in: fixture.source, headers: [fixture.neighbor, chosen])
        await gate.finish()
        #expect(await task?.value == true)
        #expect(fixture.navigation.selectedMessageID == "INBOX:45")
    }

    @Test("same provider IDs in another mailbox never restore the wrong reader")
    func preservesSourceOwnership() async {
        let fixture = SelectionUndoFixture()
        fixture.register(source: MailSourceID(accountID: "other", mailboxID: "other"))
        #expect(await fixture.queue.undo()?.value == true)
        #expect(fixture.navigation.selectedSourceID == fixture.source)
        #expect(fixture.navigation.selectedMessageID == fixture.neighbor.id)
    }

    @Test("restoring inside All Inboxes keeps the aggregate view")
    func preservesUnifiedInbox() async {
        let fixture = SelectionUndoFixture(unified: true)
        fixture.register()
        let other = MailSourceID(accountID: "other", mailboxID: "other")
        fixture.navigation.selectMessage(fixture.neighbor, in: other, headers: [fixture.neighbor])
        #expect(await fixture.queue.undo()?.value == true)
        #expect(fixture.navigation.isUnifiedInboxSelected)
        #expect(fixture.navigation.selectedSourceID == fixture.source)
        #expect(fixture.navigation.selectedMessageID == "INBOX:99")
    }

    @Test("an explicit removal releases the restored reader header")
    func removesRetainedHeader() async {
        let fixture = SelectionUndoFixture()
        fixture.register()
        _ = await fixture.queue.undo()?.value
        fixture.navigation.removeHeaders(ids: ["INBOX:99"])
        fixture.navigation.replaceCurrentFolderHeaders([fixture.neighbor])
        #expect(fixture.navigation.selectedMessageID != "INBOX:99")
        #expect(!fixture.navigation.currentFolderHeaders.contains { $0.id == "INBOX:99" })
    }

    @Test("a fetched header supersedes the temporary restoration header")
    func acceptsFreshHeader() async {
        let fixture = SelectionUndoFixture()
        fixture.register()
        _ = await fixture.queue.undo()?.value
        var fresh = fixture.original.withIdentity("INBOX:99", folderID: "INBOX")
        fresh.isFlagged = false
        fixture.navigation.replaceCurrentFolderHeaders([fixture.neighbor, fresh])
        #expect(fixture.navigation.selectedHeader?.isFlagged == false)
        fixture.navigation.replaceCurrentFolderHeaders([fixture.neighbor])
        #expect(fixture.navigation.selectedMessageID != fresh.id)
    }
}

@MainActor
private final class SelectionUndoFixture {
    let source = MailSourceID(accountID: "account", mailboxID: "mailbox")
    let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
    let original = MessageHeader(id: "INBOX:43", threadID: "INBOX:43", folderID: "INBOX",
                                 from: .init(name: "Sender", email: "sender@example.org"),
                                 replyTo: [.init(email: "reply@example.org")], to: [.init(email: "user@example.org")],
                                 subject: "Original message", snippet: "Message body", date: Date(timeIntervalSince1970: 0),
                                 isFlagged: true, hasAttachments: true, flagColor: .orange)
    let neighbor: MessageHeader
    let navigation: MailNavigationState
    let queue = UndoQueue(timeout: 60)
    let lease: UndoMutationLease

    init(unified: Bool = false) {
        neighbor = original.withIdentity("INBOX:44", folderID: "INBOX")
        navigation = MailNavigationState(selectedSourceID: source, selectedFolderID: inbox.id,
                                         selectedMessageID: original.id, currentFolderHeaders: [original, neighbor])
        if unified {
            navigation.selectUnifiedInbox()
            navigation.selectMessage(original, in: source, headers: [original, neighbor])
        }
        lease = queue.beginMutation(navigation: navigation)
        navigation.removeHeaders(ids: [original.id])
    }

    func register(source: MailSourceID? = nil,
                  action: @escaping @Sendable () async throws -> [String: String] = { ["INBOX:43": "INBOX:99"] }) {
        queue.registerMoves([MailMoveUndo(sourceID: source ?? self.source, originalFolder: inbox, action: action)],
                            description: "Moved", lease: lease)
        queue.endMutation(lease)
    }
}

private actor SelectionUndoGate {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var continuation: CheckedContinuation<[String: String], Never>?

    func restore() async -> [String: String] {
        await withCheckedContinuation {
            continuation = $0
            started = true
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finish() {
        continuation?.resume(returning: ["INBOX:43": "INBOX:99"])
        continuation = nil
    }
}
