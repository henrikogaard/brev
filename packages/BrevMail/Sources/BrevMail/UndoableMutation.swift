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

/// Holds the most-recent undoable mail mutation and auto-expires it after
/// `timeout` seconds.
///
/// Rules:
/// - `push(_:)` replaces pending work and clears a settled failure.
/// - `undo()` runs once; a thrown failure remains visible and retryable.
/// - `dismiss()` clears pending work; `dismissFailure()` clears only the failure.
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
    public var canRetry: Bool { failedMutation != nil && !isUndoing }

    private var failedMutation: UndoableMutation?

    private var expirationTask: Task<Void, Never>?
    private let timeout: Double

    public init(timeout: Double = 5) {
        self.timeout = timeout
    }

    /// Push a new mutation, replacing any that is already pending.
    public func push(_ mutation: UndoableMutation) {
        expirationTask?.cancel()
        current = mutation
        if !isUndoing {
            failedMutation = nil
            errorMessage = nil
        }
        let timeoutNS = UInt64(timeout * 1_000_000_000)
        expirationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNS)
            guard !Task.isCancelled else { return }
            if self?.current?.id == mutation.id { self?.current = nil }
        }
    }

    /// Runs the pending reversal once; the task returns whether that specific reversal succeeded.
    @discardableResult
    public func undo() -> Task<Bool, Never>? {
        guard !isUndoing, let mutation = current else { return nil }
        expirationTask?.cancel()
        expirationTask = nil
        current = nil
        return execute(mutation)
    }

    /// Retries the exact failed reversal with its originally captured mailbox context.
    @discardableResult
    public func retry() -> Task<Bool, Never>? {
        guard !isUndoing, let mutation = failedMutation else { return nil }
        return execute(mutation)
    }

    private func execute(_ mutation: UndoableMutation) -> Task<Bool, Never> {
        isUndoing = true
        errorMessage = nil
        failedMutation = nil
        return Task { [weak self] in
            defer { self?.isUndoing = false }
            do {
                try await mutation.undoAction()
                return true
            } catch {
                self?.failedMutation = mutation
                self?.errorMessage = error.localizedDescription
                return false
            }
        }
    }

    /// Dismiss the toast without executing the action.
    public func dismiss() {
        expirationTask?.cancel()
        expirationTask = nil
        current = nil
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
