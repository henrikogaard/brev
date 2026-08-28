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

@testable import BrevBackend
import Foundation
import Testing

// MARK: - Fake applier

/// Records applied mutations and yields scripted outcomes per attempt.
private actor FakeApplier: MutationApplying {
    enum Outcome: Sendable {
        case success
        case fail(MailBackendError)
    }

    /// Queue of outcomes consumed in order, one per `apply` call.
    private var outcomes: [Outcome]
    private(set) var appliedIDs: [UUID] = []
    private(set) var callCount = 0

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func apply(_ mutation: PendingMutation) async throws {
        callCount += 1
        appliedIDs.append(mutation.id)
        let outcome = outcomes.isEmpty ? .success : outcomes.removeFirst()
        if case .fail(let error) = outcome { throw error }
    }
}

private func makeQueue() throws -> UserDefaultsMutationQueue {
    let suite = "OfflineProcessorTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    return UserDefaultsMutationQueue(defaults: defaults, storageKey: "q")
}

@Suite("OfflineMutationProcessor", .serialized)
struct OfflineMutationProcessorTests {
    @Test("successful mutation is applied and removed from the queue")
    func successDrains() async throws {
        let queue = try makeQueue()
        try await queue.enqueue(PendingMutation(kind: .setRead(true), messageIDs: ["a"]))
        let applier = FakeApplier(outcomes: [.success])
        let processor = OfflineMutationProcessor(queue: queue, applier: applier)

        let result = try await processor.process()
        #expect(result.succeeded.count == 1)
        #expect(result.conflicts.isEmpty)
        #expect(try await queue.pending().isEmpty)
    }

    @Test("transient failure keeps the mutation queued and bumps attempt")
    func transientRetries() async throws {
        let queue = try makeQueue()
        try await queue.enqueue(PendingMutation(kind: .delete, messageIDs: ["a"]))
        let applier = FakeApplier(outcomes: [.fail(.network(underlying: "offline"))])
        let processor = OfflineMutationProcessor(queue: queue, applier: applier)

        let result = try await processor.process()
        #expect(result.retrying.count == 1)
        let pending = try await queue.pending()
        #expect(pending.count == 1)
        #expect(pending[0].attempt == 1)
    }

    @Test("a later pass succeeds after an earlier transient failure")
    func retrySucceedsLater() async throws {
        let queue = try makeQueue()
        try await queue.enqueue(PendingMutation(kind: .setFlagged(true), messageIDs: ["a"]))
        let applier = FakeApplier(outcomes: [.fail(.notConnected), .success])
        let processor = OfflineMutationProcessor(queue: queue, applier: applier)

        _ = try await processor.process() // fails, retries
        let second = try await processor.process() // succeeds
        #expect(second.succeeded.count == 1)
        #expect(try await queue.pending().isEmpty)
    }

    @Test("permanent notFound becomes a recoverable targetMissing conflict")
    func notFoundConflict() async throws {
        let queue = try makeQueue()
        try await queue.enqueue(PendingMutation(kind: .delete, messageIDs: ["gone"]))
        let applier = FakeApplier(outcomes: [.fail(.notFound(id: "gone"))])
        let processor = OfflineMutationProcessor(queue: queue, applier: applier)

        let result = try await processor.process()
        #expect(result.conflicts.count == 1)
        #expect(result.conflicts.first?.reason == .targetMissing)
        // Removed from the queue so it is not retried forever.
        #expect(try await queue.pending().isEmpty)
    }

    @Test("permissionDenied becomes a rejectedByServer conflict")
    func rejectedConflict() async throws {
        let queue = try makeQueue()
        try await queue.enqueue(PendingMutation(kind: .move(folderID: "f"), messageIDs: ["a"]))
        let applier = FakeApplier(outcomes: [.fail(.permissionDenied(message: "no access"))])
        let processor = OfflineMutationProcessor(queue: queue, applier: applier)

        let result = try await processor.process()
        #expect(result.conflicts.first?.reason == .rejectedByServer)
        #expect(result.conflicts.first?.message == "no access")
    }

    @Test("retries exhaust into a permanent conflict after maxAttempts")
    func retriesExhausted() async throws {
        let queue = try makeQueue()
        try await queue.enqueue(PendingMutation(kind: .delete, messageIDs: ["a"]))
        let applier = FakeApplier(outcomes: [
            .fail(.network(underlying: "x")),
            .fail(.network(underlying: "x")),
            .fail(.network(underlying: "x"))
        ])
        let processor = OfflineMutationProcessor(queue: queue, applier: applier, maxAttempts: 3)

        _ = try await processor.process() // attempt -> 1, retrying
        _ = try await processor.process() // attempt -> 2, retrying
        let third = try await processor.process() // attempt -> 3 == max -> conflict
        #expect(third.conflicts.count == 1)
        #expect(third.conflicts.first?.reason == .retriesExhausted)
        #expect(try await queue.pending().isEmpty)
    }

    @Test("cancellation removes a mutation without applying it")
    func cancellation() async throws {
        let queue = try makeQueue()
        let m = PendingMutation(kind: .delete, messageIDs: ["a"])
        try await queue.enqueue(m)
        let applier = FakeApplier(outcomes: [])
        let processor = OfflineMutationProcessor(queue: queue, applier: applier)

        let removed = try await processor.cancel(id: m.id)
        #expect(removed)
        let result = try await processor.process()
        #expect(result.succeeded.isEmpty)
        #expect(await applier.callCount == 0)
        #expect(try await queue.pending().isEmpty)
    }

    @Test("cancelling an unknown id reports false")
    func cancelUnknown() async throws {
        let queue = try makeQueue()
        let applier = FakeApplier(outcomes: [])
        let processor = OfflineMutationProcessor(queue: queue, applier: applier)
        #expect(try await processor.cancel(id: UUID()) == false)
    }

    @Test("mixed batch: success, conflict, and retry are partitioned")
    func mixedBatch() async throws {
        let queue = try makeQueue()
        try await queue.enqueue(PendingMutation(kind: .setRead(true), messageIDs: ["ok"]))
        try await queue.enqueue(PendingMutation(kind: .delete, messageIDs: ["gone"]))
        try await queue.enqueue(PendingMutation(kind: .setJunk(true), messageIDs: ["later"]))
        let applier = FakeApplier(outcomes: [
            .success,
            .fail(.notFound(id: "gone")),
            .fail(.rateLimited(retryAfter: 1))
        ])
        let processor = OfflineMutationProcessor(queue: queue, applier: applier)

        let result = try await processor.process()
        #expect(result.succeeded.count == 1)
        #expect(result.conflicts.count == 1)
        #expect(result.retrying.count == 1)
        // Only the retrying one remains.
        #expect(try await queue.pending().count == 1)
    }

    @Test("backoff closure is consulted with the current attempt count")
    func backoffConsulted() async throws {
        let queue = try makeQueue()
        try await queue.enqueue(PendingMutation(kind: .delete, messageIDs: ["a"]))
        let applier = FakeApplier(outcomes: [.fail(.notConnected), .success])

        final class Box: @unchecked Sendable { var attempts: [Int] = [] }
        let box = Box()
        let processor = OfflineMutationProcessor(
            queue: queue,
            applier: applier,
            backoff: { attempt in box.attempts.append(attempt); return .zero }
        )

        _ = try await processor.process() // attempt 0 seen, fails -> attempt 1
        _ = try await processor.process() // attempt 1 seen, succeeds
        #expect(box.attempts == [0, 1])
    }
}
