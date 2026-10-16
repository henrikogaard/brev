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

/// Operation identity for the Drive attachment flows (#14).
///
/// Every awaited phase carries the token it started with. A superseded,
/// cancelled, or terminated flow can never publish state, start the next
/// provider call, or report success: `isCurrent` fails for stale tokens,
/// for a cancelled enclosing task, and permanently after `finish()`.
@MainActor
final class GoogleDriveOperationLifetime {
    private(set) var isTerminal = false
    private var generation = 0
    private var task: Task<Void, Never>?

    /// Whether the token still owns the flow and the task is alive.
    func isCurrent(_ token: Int) -> Bool {
        !isTerminal && token == generation && !Task.isCancelled
    }

    /// Starts a new operation, superseding any in-flight one. A finished
    /// flow refuses to restart — the caller constructs a fresh flow.
    func start(_ body: @escaping (Int) async -> Void) {
        guard let token = nextToken() else { return }
        task = Task { await body(token) }
    }

    /// Claims a token for an awaited phase driven by the caller.
    func nextToken() -> Int? {
        guard !isTerminal else { return nil }
        generation &+= 1
        task?.cancel()
        task = nil
        return generation
    }

    /// Abandons in-flight work; later phases of it cannot publish.
    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
    }

    /// Cancels and permanently closes the flow.
    func finish() {
        cancel()
        isTerminal = true
    }
}
