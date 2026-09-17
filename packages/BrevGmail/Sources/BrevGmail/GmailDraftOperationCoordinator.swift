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
import Foundation

/// Owns per-draft work and prevents retired provider replies from writing local staging.
actor GmailDraftOperationCoordinator {
    struct Lease: Sendable {
        let id: UUID
        let generation: UUID
    }

    private var isActive = false
    private var generation = UUID()
    private var operations: [UUID: Set<String>] = [:]
    private var stagingWrites = 0
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    func connectionGeneration() -> UUID { generation }

    func activate(generation expected: UUID) throws {
        guard generation == expected else { throw MailBackendError.notConnected }
        isActive = true
    }

    /// Drains local writes before purge without waiting for a stalled provider request.
    func deactivate() async {
        isActive = false
        generation = UUID()
        operations.removeAll()
        guard stagingWrites > 0 else { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }

    func withOperation<Value: Sendable>(identifiers: [String],
                                        operation: @Sendable (Lease) async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        guard isActive else { throw MailBackendError.notConnected }
        let keys = Set(identifiers.filter { !$0.isEmpty })
        guard operations.values.allSatisfy({ $0.isDisjoint(with: keys) }) else { throw GmailDraftOperationError.busy }
        let lease = Lease(id: UUID(), generation: generation)
        operations[lease.id] = keys
        defer { operations[lease.id] = nil }
        return try await operation(lease)
    }

    func check(_ lease: Lease) throws {
        try Task.checkCancellation()
        guard isActive, lease.generation == generation, operations[lease.id] != nil else {
            throw MailBackendError.notConnected
        }
    }

    func withStaging<Value: Sendable>(_ lease: Lease,
                                      operation: @Sendable () async throws -> Value) async throws -> Value {
        try check(lease)
        stagingWrites += 1
        defer {
            stagingWrites -= 1
            if stagingWrites == 0 {
                let waiters = drainWaiters
                drainWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        }
        return try await operation()
    }
}

enum GmailDraftOperationError: Error, LocalizedError {
    case busy

    var errorDescription: String? {
        String(localized: "This draft is already being updated. Try again when that operation finishes.", bundle: .module)
    }
}
