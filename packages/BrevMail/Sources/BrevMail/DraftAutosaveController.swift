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
import Observation

/// Periodic draft autosave controller.
///
/// Drives a 30-second repeating timer that persists the current draft state
/// through the compose view's save path. View code owns one instance per open
/// compose window and calls `markChanged()` whenever the user edits draft fields.
@Observable
@MainActor
final class DraftAutosaveController {
    /// The time the draft was last successfully persisted.
    private(set) var lastSavedAt: Date?

    /// `true` when the draft has been edited since the last save.
    private(set) var hasPendingChanges = false

    private var timerTask: Task<Void, Never>?
    private static let intervalNanoseconds: UInt64 = 30_000_000_000

    /// Called by the view whenever a draft field changes.
    func markChanged() {
        hasPendingChanges = true
    }

    /// Start the periodic 30-second autosave loop. Call once from
    /// a `.task` modifier on the compose view; SwiftUI cancels that task when
    /// the view disappears, and the view also calls `stop()` during teardown.
    /// Cancellation stops the timer promptly but cannot interrupt an already
    /// awaited save closure; the closure must keep its own response guards.
    func start(saveDraft: @escaping @MainActor () async -> Void) {
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: Self.intervalNanoseconds)
                } catch {
                    return
                }
                guard !Task.isCancelled, hasPendingChanges else { continue }
                await saveDraft()
                hasPendingChanges = false
                lastSavedAt = Date()
            }
        }
    }

    /// Stop the timer. Safe to call multiple times.
    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }
}
