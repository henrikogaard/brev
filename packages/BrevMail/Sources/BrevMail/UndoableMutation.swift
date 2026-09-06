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
import Observation
import SwiftUI

/// Immutable ownership and invocation order for one forward mail operation.
public struct UndoMutationLease: Sendable {
    fileprivate let id: UUID
    fileprivate let scope: UUID
    fileprivate let order: UInt64
    let selection: MailUndoSelectionRestorer?
}

// MARK: - UndoableMutation

/// A description and a reversing action for a mail mutation.
///
/// Call sites capture all state they need inside `undoAction`; the
/// `UndoQueue` treats the closure as opaque.
public struct UndoableMutation: @unchecked Sendable {
    let id = UUID()
    /// Human-readable description shown in the "Undo" toast (e.g. "Archive").
    public let description: String

    /// Reverses the captured mutation. The owning queue serializes reversals
    /// and retains thrown failures for an explicit retry.
    let undoAction: @Sendable () async throws -> Void

    /// Creates an undo action with the original mailbox context captured by its caller.
    public init(description: String, undoAction: @escaping @Sendable () async throws -> Void) {
        self.description = description
        self.undoAction = undoAction
    }
}

// MARK: - UndoQueue

/// Holds the latest mail reversal. Its toast expires after `timeout` seconds;
/// the native Undo command remains available until another action supersedes it.
///
/// Rules:
/// - `push(_:)` replaces pending work and clears a settled failure.
/// - `undo()` runs once; a thrown failure remains visible and retryable.
/// - `dismiss()` hides the toast; `dismissFailure()` clears only the failure.
///
/// The queue is owned by `BrevMailRootView` and injected into the
/// environment via `\.undoQueue` so descendant views can both push
/// mutations and read `current` to drive the toast.
@Observable
@MainActor
public final class UndoQueue {
    /// The pending mutation, or `nil` when the queue is empty.
    public private(set) var current: UndoableMutation?
    /// Most recent undo failure, shown to the user instead of discarded.
    public private(set) var errorMessage: String?
    /// Whether a reversal is currently running.
    public private(set) var isUndoing = false
    /// The latest failure is retryable until dismissed or another reversal is chosen.
    public var canRetry: Bool { failedMutation != nil && !isUndoing && !isMutationInFlight }

    /// Whether a mail action is available for the native Undo command.
    public var canUndo: Bool { latest != nil && !isUndoing && !isMutationInFlight }
    /// Whether an in-flight forward mutation prevents a reversal.
    public var isMutationInFlight: Bool { !mutationTokens.isEmpty }

    private var latest: UndoableMutation?
    private var mutationTokens: Set<UUID> = []
    private var scopeID = UUID()
    private var nextOrder: UInt64 = 0
    private var latestOrder: UInt64 = 0
    private var activeUndoID: UUID?
    private var activeTask: Task<Bool, Never>?

    /// Suspends Undo while an independently owned forward mutation runs.
    /// Pass navigation to restore its selected message after a confirmed inverse move.
    public func beginMutation(navigation: MailNavigationState? = nil) -> UndoMutationLease {
        nextOrder &+= 1
        let lease = UndoMutationLease(id: UUID(), scope: scopeID, order: nextOrder,
                                      selection: navigation.flatMap { MailUndoSelectionRestorer(navigation: $0) })
        mutationTokens.insert(lease.id)
        expirationTask?.cancel()
        return lease
    }

    /// Releases only the matching forward operation's suspension.
    public func endMutation(_ lease: UndoMutationLease) {
        guard lease.scope == scopeID else { return }
        guard mutationTokens.remove(lease.id) != nil else { return }
        if !isMutationInFlight, !isUndoing, let current { startExpiration(for: current) }
    }

    private var failedMutation: UndoableMutation?

    private var expirationTask: Task<Void, Never>?
    private let timeout: Double

    public init(timeout: Double = 5) {
        self.timeout = timeout
    }

    /// Push a new mutation, replacing any that is already pending.
    public func push(_ mutation: UndoableMutation, lease: UndoMutationLease? = nil) {
        guard acceptRegistration(lease) else { return }
        expirationTask?.cancel()
        current = mutation
        latest = mutation
        if !isUndoing {
            failedMutation = nil
            errorMessage = nil
        }
        if !isMutationInFlight, !isUndoing { startExpiration(for: mutation) }
    }

    private func acceptRegistration(_ lease: UndoMutationLease?) -> Bool {
        if let lease {
            guard lease.scope == scopeID, lease.order >= latestOrder else { return false }
            latestOrder = lease.order
        } else {
            nextOrder &+= 1
            latestOrder = nextOrder
        }
        return true
    }

    /// A newer irreversible/unmapped action supersedes older Undo without releasing operation leases.
    public func discardPendingUndo(lease: UndoMutationLease? = nil) {
        guard acceptRegistration(lease) else { return }
        latest = nil
        dismiss()
        dismissFailure()
    }

    private func startExpiration(for mutation: UndoableMutation) {
        expirationTask?.cancel()
        let timeoutNS = UInt64(max(0, timeout) * 1_000_000_000)
        expirationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNS)
            guard !Task.isCancelled else { return }
            if self?.current?.id == mutation.id { self?.current = nil }
        }
    }

    /// Runs the pending reversal once; the task returns whether that specific reversal succeeded.
    @discardableResult
    public func undo() -> Task<Bool, Never>? {
        guard canUndo, let mutation = latest else { return nil }
        expirationTask?.cancel()
        expirationTask = nil
        current = nil
        latest = nil
        return execute(mutation)
    }

    /// Retries the exact failed reversal with its originally captured mailbox context.
    @discardableResult
    public func retry() -> Task<Bool, Never>? {
        guard canRetry, let mutation = failedMutation else { return nil }
        return execute(mutation)
    }

    private func execute(_ mutation: UndoableMutation) -> Task<Bool, Never> {
        let operationID = UUID()
        activeUndoID = operationID
        isUndoing = true
        errorMessage = nil
        failedMutation = nil
        let task = Task { [weak self] in
            defer {
                if self?.activeUndoID == operationID {
                    self?.activeUndoID = nil
                    self?.activeTask = nil
                    self?.isUndoing = false
                    if let self, !self.isMutationInFlight, let current = self.current { self.startExpiration(for: current) }
                }
            }
            do {
                try Task.checkCancellation()
                try await mutation.undoAction()
                return self?.activeUndoID == operationID
            } catch {
                guard self?.activeUndoID == operationID else { return false }
                self?.failedMutation = mutation
                self?.errorMessage = error.localizedDescription
                return false
            }
        }
        activeTask = task
        return task
    }

    /// Dismiss the toast without executing the action.
    public func dismiss() {
        expirationTask?.cancel()
        expirationTask = nil
        current = nil
    }

    /// Discards account-bound actions and invalidates late callbacks from a retired session.
    public func discardAll() {
        activeTask?.cancel()
        activeTask = nil
        activeUndoID = nil
        mutationTokens.removeAll()
        scopeID = UUID()
        nextOrder = 0
        latestOrder = 0
        latest = nil
        dismiss()
        dismissFailure()
        isUndoing = false
    }

    /// Dismisses failed reversal feedback without consuming a newer pending action.
    public func dismissFailure() {
        failedMutation = nil
        errorMessage = nil
    }
}

// MARK: - Environment key

private struct UndoQueueKey: EnvironmentKey {
    static let defaultValue: UndoQueue? = nil
}

public extension EnvironmentValues {
    /// The nearest `UndoQueue` in the environment. Set by
    /// `BrevMailRootView` so both the root and all descendants share one
    /// queue instance.
    var undoQueue: UndoQueue? {
        get { self[UndoQueueKey.self] }
        set { self[UndoQueueKey.self] = newValue }
    }
}
