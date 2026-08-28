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
    /// Human-readable description shown in the "Undo" toast (e.g. "Archive").
    public let description: String

    /// Async closure that reverses the mutation. Must be safe to call
    /// concurrently with other mutations (the `UndoQueue` fires it on
    /// the `@MainActor` task that owns the queue).
    let undoAction: @Sendable () async -> Void

    public init(description: String, undoAction: @escaping @Sendable () async -> Void) {
        self.description = description
        self.undoAction = undoAction
    }
}

// MARK: - UndoQueue

/// Holds the most-recent undoable mail mutation and auto-expires it after
/// `timeout` seconds.
///
/// Rules:
/// - `push(_:)` replaces any pending mutation and restarts the timer.
/// - `undo()` cancels the timer, fires the action, and clears the queue.
/// - `dismiss()` cancels the timer and clears without executing the action.
///
/// The queue is owned by `BrevMailRootView` and injected into the
/// environment via `\.undoQueue` so descendant views can both push
/// mutations and read `current` to drive the toast.
@Observable
@MainActor
public final class UndoQueue {
    /// The pending mutation, or `nil` when the queue is empty.
    public private(set) var current: UndoableMutation?

    private var expirationTask: Task<Void, Never>?
    private let timeout: Double

    public init(timeout: Double = 5) {
        self.timeout = timeout
    }

    /// Push a new mutation, replacing any that is already pending.
    public func push(_ mutation: UndoableMutation) {
        expirationTask?.cancel()
        current = mutation
        let timeoutNS = UInt64(timeout * 1_000_000_000)
        expirationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNS)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.current = nil }
        }
    }

    /// Execute the pending undo action immediately and clear the queue.
    public func undo() {
        expirationTask?.cancel()
        expirationTask = nil
        guard let mutation = current else { return }
        current = nil
        Task { await mutation.undoAction() }
    }

    /// Dismiss the toast without executing the action.
    public func dismiss() {
        expirationTask?.cancel()
        expirationTask = nil
        current = nil
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
