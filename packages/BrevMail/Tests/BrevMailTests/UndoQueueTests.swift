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
