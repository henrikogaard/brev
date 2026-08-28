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

import Foundation

// MARK: - Application seam

/// Applies a single `PendingMutation` against a concrete backend.
///
/// This narrow seam lets the processor stay independent of `MailBackend`'s
/// full object graph (it deals in IDs, not `Folder`/`Draft` instances) and
/// makes retry/conflict policy unit-testable with a fake applier.
public protocol MutationApplying: Sendable {
    /// Performs the mutation. Throws `MailBackendError` to signal failure;
    /// the processor classifies the error into retry vs. conflict.
    func apply(_ mutation: PendingMutation) async throws
}

// MARK: - Result

/// Summary of one `process()` pass over the queue.
public struct MutationProcessingResult: Sendable, Equatable {
    /// Mutations applied successfully and removed from the queue.
    public var succeeded: [PendingMutation]
    /// Mutations that hit a surfaced, recoverable conflict and were
    /// removed from the queue.
    public var conflicts: [MutationConflict]
    /// Mutations that failed transiently and remain queued for a later
    /// pass (their `attempt` count was incremented).
    public var retrying: [PendingMutation]

    public init(
        succeeded: [PendingMutation] = [],
        conflicts: [MutationConflict] = [],
        retrying: [PendingMutation] = []
    ) {
        self.succeeded = succeeded
        self.conflicts = conflicts
        self.retrying = retrying
    }
}

// MARK: - Processor

/// Drains an `OfflineMutationQueue`, applying retry-with-backoff,
/// conflict detection, and permanent-failure handling (ADR-0022).
///
/// Each `process()` call attempts every pending mutation once. Transient
/// failures bump `attempt` and stay queued until `maxAttempts`, after
/// which they convert to a `retriesExhausted` conflict. Callers re-invoke
/// `process()` when connectivity returns; the optional `backoff` closure
/// supplies an inter-attempt delay (defaults to none, which keeps tests
/// deterministic).
public actor OfflineMutationProcessor {
    private let queue: OfflineMutationQueue
    private let applier: MutationApplying
    private let maxAttempts: Int
    private let backoff: @Sendable (Int) -> Duration
    private let sleeper: @Sendable (Duration) async -> Void

    public init(
        queue: OfflineMutationQueue,
        applier: MutationApplying,
        maxAttempts: Int = 5,
        backoff: @escaping @Sendable (Int) -> Duration = { _ in .zero },
        sleeper: @escaping @Sendable (Duration) async -> Void = { _ in }
    ) {
        self.queue = queue
        self.applier = applier
        self.maxAttempts = max(1, maxAttempts)
        self.backoff = backoff
        self.sleeper = sleeper
    }

    /// Cancels (removes) the queued mutation with `id` without applying
    /// it. Returns `true` if a mutation was removed.
    @discardableResult
    public func cancel(id: UUID) async throws -> Bool {
        let before = try await queue.pending()
        guard before.contains(where: { $0.id == id }) else { return false }
        try await queue.remove(id: id)
        return true
    }

    /// Attempts every pending mutation once, in insertion order.
    ///
    /// - Parameter processSends: When `false`, `.send(draft:)` mutations are
    ///   skipped and remain in the queue (e.g. for manual retry from the
    ///   Outbox UI). Defaults to `true`.
    public func process(processSends: Bool = true) async throws -> MutationProcessingResult {
        var result = MutationProcessingResult()
        let items = try await queue.pending()

        for var mutation in items {
            if !processSends {
                switch mutation.kind {
                case .send(draft:), .sendStagedDraft: continue
                default: break
                }
            }
            let delay = backoff(mutation.attempt)
            if delay != .zero { await sleeper(delay) }

            do {
                try await applier.apply(mutation)
                try await queue.remove(id: mutation.id)
                result.succeeded.append(mutation)
            } catch let error as MailBackendError {
                if let conflict = permanentConflict(for: mutation, error: error) {
                    try await queue.remove(id: mutation.id)
                    result.conflicts.append(conflict)
                    continue
                }
                // Transient: bump attempt; exhaust into a conflict if needed.
                mutation.attempt += 1
                if mutation.attempt >= maxAttempts {
                    try await queue.remove(id: mutation.id)
                    result.conflicts.append(MutationConflict(
                        mutation: mutation,
                        reason: .retriesExhausted,
                        message: "Gave up after \(mutation.attempt) attempts: "
                            + error.userFacingMessage
                    ))
                } else {
                    try await queue.update(mutation)
                    result.retrying.append(mutation)
                }
            } catch {
                // Non-backend error: treat as transient.
                mutation.attempt += 1
                if mutation.attempt >= maxAttempts {
                    try await queue.remove(id: mutation.id)
                    result.conflicts.append(MutationConflict(
                        mutation: mutation,
                        reason: .retriesExhausted,
                        message: "Gave up after \(mutation.attempt) attempts."
                    ))
                } else {
                    try await queue.update(mutation)
                    result.retrying.append(mutation)
                }
            }
        }
        return result
    }

    /// Classifies a backend error as an immediately-permanent conflict,
    /// or `nil` if it should be retried.
    private func permanentConflict(
        for mutation: PendingMutation,
        error: MailBackendError
    ) -> MutationConflict? {
        switch error {
        case .notFound(let id):
            return MutationConflict(
                mutation: mutation,
                reason: .targetMissing,
                message: "The item no longer exists on the server (\(id))."
            )
        case .permissionDenied(let message):
            return MutationConflict(
                mutation: mutation,
                reason: .rejectedByServer,
                message: message
            )
        case .quotaExceeded:
            return MutationConflict(
                mutation: mutation,
                reason: .rejectedByServer,
                message: "The server rejected the change: quota exceeded."
            )
        case .notSupported:
            return MutationConflict(
                mutation: mutation,
                reason: .rejectedByServer,
                message: "This backend does not support the requested change."
            )
        case .notConnected, .authenticationRequired, .rateLimited, .network,
             .credentialStoreUnavailable, .backendSpecific:
            // Transient — worth retrying when connectivity/auth/Keychain recovers.
            return nil
        }
    }
}

private extension MailBackendError {
    /// A short, user-safe description for conflict messages.
    var userFacingMessage: String {
        switch self {
        case .notConnected: return "not connected"
        case .authenticationRequired: return "authentication required"
        case .notSupported: return "not supported"
        case .notFound(let id): return "not found (\(id))"
        case .permissionDenied(let message): return message
        case .quotaExceeded: return "quota exceeded"
        case .rateLimited: return "rate limited"
        case .network(let underlying): return underlying
        case .credentialStoreUnavailable: return "credential store unavailable"
        case .backendSpecific(let message): return message
        }
    }
}
