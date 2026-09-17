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

@Suite("Mail action Undo")
@MainActor
struct UndoQueueTests {
    @Test("failed reversal is visible and does not masquerade as success")
    func reversalFailureIsVisible() async {
        let queue = UndoQueue(timeout: 60)
        queue.push(UndoableMutation(description: "Archived") { throw UndoTestError.offline })
        _ = await queue.undo()?.value
        #expect(queue.errorMessage == "The mailbox is offline.")
    }

    @Test("retry reverses the original action once and clears its failure")
    func retryOriginalAction() async {
        let queue = UndoQueue(timeout: 60)
        let probe = UndoProbe()
        queue.push(UndoableMutation(description: "Moved") { try await probe.reverse() })
        _ = await queue.undo()?.value
        #expect(queue.canRetry)
        #expect(await probe.attempts == 1)
        _ = await queue.retry()?.value
        #expect(queue.errorMessage == nil)
        #expect(!queue.canRetry)
        #expect(await probe.attempts == 2)
    }

    @Test("undo is single-flight and does not consume a subsequently queued action")
    func singleFlight() async {
        let queue = UndoQueue(timeout: 60)
        let probe = UndoProbe()
        queue.push(UndoableMutation(description: "First") { try await probe.reverse() })
        let first = queue.undo()
        #expect(queue.isUndoing)
        queue.push(UndoableMutation(description: "Second") {})
        #expect(queue.undo() == nil)
        _ = await first?.value
        #expect(!queue.isUndoing)
        #expect(queue.current?.description == "Second")
        #expect(await probe.attempts == 1)
        queue.dismissFailure()
        #expect(queue.current?.description == "Second")
    }

    @Test("a new action replaces a settled failure instead of hiding its Undo")
    func newActionReplacesFailure() async {
        let queue = UndoQueue(timeout: 60)
        queue.push(UndoableMutation(description: "First") { throw UndoTestError.offline })
        _ = await queue.undo()?.value
        queue.push(UndoableMutation(description: "Second") {})
        #expect(queue.errorMessage == nil)
        #expect(!queue.canRetry)
        #expect(queue.current?.description == "Second")
    }

    @Test("retrying a move batch does not repeat already completed reversals")
    func retryMoveBatchResumes() async {
        let first = UndoMoveProbe(failFirst: false)
        let second = UndoMoveProbe(failFirst: true)
        let queue = UndoQueue(timeout: 60)
        let source = MailSourceID(accountID: "account", mailboxID: "mailbox")
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        queue.registerMoves([
            MailMoveUndo(sourceID: source, originalFolder: folder) { try await first.restore() },
            MailMoveUndo(sourceID: source, originalFolder: folder) { try await second.restore() }
        ], description: "Moved")
        _ = await queue.undo()?.value
        #expect(queue.canRetry)
        _ = await queue.retry()?.value
        #expect(await first.attempts == 1)
        #expect(await second.attempts == 2)
        #expect(queue.errorMessage == nil)
    }

    @Test("bulk read Undo leaves messages unchanged by the original action alone")
    func readUndoPreservesUnchangedMessages() async throws {
        let account = BrevAccount(id: "undo-account", displayName: "Undo", emailAddress: "undo@example.org")
        let mailbox = Mailbox(id: account.id, email: account.emailAddress, displayName: "Undo", isPrimary: true)
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let headers = [false, true].enumerated().map { index, isRead in
            MessageHeader(id: "m\(index)", threadID: "t\(index)", folderID: inbox.id,
                          from: .init(email: "sender@example.org"), subject: "Subject", snippet: "",
                          date: Date(timeIntervalSince1970: 0), isRead: isRead)
        }
        let backend = MockBackend(account: account, folders: [inbox], messagesByFolder: [inbox.id: headers], mailboxes: [mailbox])
        let source = MailSourceID(accountID: account.id, mailboxID: mailbox.id)
        try await backend.connect()
        try await backend.setRead(true, for: ["m0", "m1"], sourceID: source)
        // Another device changes a message that our original command did not change.
        try await backend.setRead(false, for: ["m1"], sourceID: source)
        let queue = UndoQueue(timeout: 60)
        queue.push(MailFlagUndo.action(
            .read,
            originals: headers,
            newValue: true,
            sourceID: source,
            backend: backend,
            description: "Read"
        ))
        _ = await queue.undo()?.value
        let restored = try await backend.messages(in: inbox, sourceID: source, pageToken: nil).headers
        #expect(restored.allSatisfy { !$0.isRead })
    }

    @Test("an unchanged bulk flag selection preserves the prior Undo")
    func unchangedFlagsDoNotReplaceUndo() {
        let queue = UndoQueue(timeout: 60)
        queue.push(UndoableMutation(description: "Earlier move") {})
        let backend = MockBackend()
        let source = MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)
        let header = MessageHeader(id: "m", threadID: "t", folderID: "inbox", from: .init(email: "sender@example.org"),
                                   subject: "", snippet: "", date: Date(), isRead: true)
        queue.registerFlag(.read, originals: [header], newValue: true, sourceID: source, backend: backend)
        #expect(queue.current?.description == "Earlier move")
    }

    @Test("junk fallback Undo returns the message to its original folder in its owning mailbox")
    func junkFallbackRestoresOrigin() async throws {
        let account = BrevAccount(id: "junk", displayName: "Junk test", emailAddress: "junk@example.org")
        let source = MailSourceID(accountID: account.id, mailboxID: account.id)
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let spam = Folder(id: "spam", name: "Spam", role: .spam)
        let mailbox = Mailbox(id: account.id, email: account.emailAddress, displayName: "Test", isPrimary: true)
        let header = MessageHeader(id: "m", threadID: "t", folderID: inbox.id, from: .init(email: "sender@example.org"),
                                   subject: "Subject", snippet: "", date: Date())
        let backend = MockBackend(account: account, capabilities: [], folders: [inbox, spam],
                                  messagesByFolder: [inbox.id: [header]], mailboxes: [mailbox])
        try await backend.connect()
        let action = try #require(try await MailJunkUndo.perform(true, header: header, folders: [inbox, spam],
                                                                 sourceID: source, backend: backend))
        #expect(try await backend.messages(in: spam, sourceID: source, pageToken: nil).headers.map(\.id) == [header.id])
        let queue = UndoQueue(timeout: 60)
        queue.push(action)
        #expect(await queue.undo()?.value == true)
        #expect(try await backend.messages(in: inbox, sourceID: source, pageToken: nil).headers.map(\.id) == [header.id])
    }

    @Test("retiring a session before Undo starts prevents the provider action")
    func retiredTaskDoesNotStartProviderAction() async {
        let queue = UndoQueue(timeout: 60)
        let probe = UndoMoveProbe(failFirst: false)
        queue.push(UndoableMutation(description: "Move") { _ = try await probe.restore() })
        let task = queue.undo()
        queue.discardAll()
        _ = await task?.value
        #expect(await probe.attempts == 0)
    }

    @Test("a retired session cannot publish an Undo error or clear a replacement operation")
    func discardedSessionCannotPublishLateUndo() async {
        let old = PausedUndoOperation()
        let replacement = PausedUndoOperation()
        let queue = UndoQueue(timeout: 60)
        queue.push(UndoableMutation(description: "Old mailbox") { try await old.run(fail: true) })
        let oldTask = queue.undo()
        await old.waitForStart()
        queue.discardAll()
        queue.push(UndoableMutation(description: "New mailbox") { try await replacement.run(fail: false) })
        let newTask = queue.undo()
        await replacement.waitForStart()
        await old.finish()
        _ = await oldTask?.value
        #expect(queue.errorMessage == nil)
        #expect(queue.isUndoing)
        await replacement.finish()
        _ = await newTask?.value
        #expect(!queue.isUndoing)
        #expect(queue.errorMessage == nil)
    }

    @Test("dismissing the transient toast retains the latest native mail Undo")
    func dismissToastRetainsNativeUndo() async {
        let probe = UndoMoveProbe(failFirst: false)
        let queue = UndoQueue(timeout: 60)
        queue.push(UndoableMutation(description: "Archived") { _ = try await probe.restore() })
        queue.dismiss()
        #expect(queue.current == nil)
        #expect(queue.canUndo)
        _ = await queue.undo()?.value
        #expect(await probe.attempts == 1)
    }

    @Test("forward mutations suspend Undo until every owning token finishes")
    func forwardMutationsSuspendUndo() async {
        let queue = UndoQueue(timeout: 60)
        queue.push(UndoableMutation(description: "Archived") {})
        let first = queue.beginMutation()
        let second = queue.beginMutation()
        #expect(!queue.canUndo)
        let premature = queue.undo()
        #expect(premature == nil)
        _ = await premature?.value
        queue.endMutation(UndoQueue(timeout: 60).beginMutation())
        queue.endMutation(first)
        #expect(queue.isMutationInFlight)
        queue.endMutation(second)
        #expect(!queue.isMutationInFlight)
        #expect(queue.canUndo)
    }

    @Test("late completion cannot replace the Undo for a more recent user action")
    func invocationOrderWinsOverCompletionOrder() async {
        let queue = UndoQueue(timeout: 60)
        let earlier = queue.beginMutation()
        let later = queue.beginMutation()
        queue.push(UndoableMutation(description: "Later action") {}, lease: later)
        queue.endMutation(later)
        queue.push(UndoableMutation(description: "Earlier action") {}, lease: earlier)
        queue.discardPendingUndo(lease: earlier)
        queue.endMutation(earlier)
        #expect(queue.current?.description == "Later action")
        #expect(queue.canUndo)
    }

    @Test("a late forward result cannot register Undo for a retired backend")
    func retiredLeaseCannotRegisterUndo() {
        let queue = UndoQueue(timeout: 60)
        let retired = queue.beginMutation()
        queue.discardAll()
        queue.push(UndoableMutation(description: "Current account") {})
        queue.push(UndoableMutation(description: "Retired account") {}, lease: retired)
        queue.discardPendingUndo(lease: retired)
        queue.endMutation(retired)
        #expect(queue.current?.description == "Current account")
        #expect(!queue.isMutationInFlight)
    }

    @Test("dismissing a failure removes its retry action")
    func dismissFailure() async {
        let queue = UndoQueue(timeout: 60)
        queue.push(UndoableMutation(description: "Deleted") { throw UndoTestError.offline })
        _ = await queue.undo()?.value
        queue.dismissFailure()
        #expect(queue.errorMessage == nil)
        #expect(!queue.canRetry)
        #expect(queue.retry() == nil)
    }
}

private enum UndoTestError: LocalizedError {
    case offline
    var errorDescription: String? { "The mailbox is offline." }
}

private actor UndoProbe {
    private(set) var attempts = 0
    func reverse() throws {
        attempts += 1
        if attempts == 1 { throw UndoTestError.offline }
    }
}

private actor UndoMoveProbe {
    private(set) var attempts = 0
    let failFirst: Bool
    init(failFirst: Bool) { self.failFirst = failFirst }
    func restore() throws -> [String: String] {
        attempts += 1
        if failFirst, attempts == 1 { throw UndoTestError.offline }
        return ["old": "restored"]
    }
}

private actor PausedUndoOperation {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var finishWaiter: CheckedContinuation<Void, Never>?

    func run(fail: Bool) async throws {
        await withCheckedContinuation { continuation in
            finishWaiter = continuation
            started = true
            startWaiter?.resume()
            startWaiter = nil
        }
        if fail { throw UndoTestError.offline }
    }

    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finish() {
        finishWaiter?.resume()
        finishWaiter = nil
    }
}
