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

/// Drains local schedule edits before account teardown without waiting on SMTP.
actor ScheduledEditingLifetime {
    private var generation = UUID()
    private var active = true
    private var localWork = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func currentGeneration() -> UUID { generation }
    func isCurrent(_ expected: UUID) -> Bool { active && generation == expected }

    func activate(_ expected: UUID) throws {
        guard generation == expected else { throw ScheduledSendEditingError.sessionChanged }
        active = true
    }

    func close() async {
        active = false
        generation = UUID()
        guard localWork > 0 else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func perform<Value: Sendable>(generation expected: UUID? = nil,
                                  _ operation: @Sendable () async throws -> Value) async throws -> Value {
        guard active, expected == nil || expected == generation else { throw ScheduledSendEditingError.sessionChanged }
        localWork += 1
        defer {
            localWork -= 1
            if localWork == 0 {
                let ready = waiters
                waiters.removeAll()
                ready.forEach { $0.resume() }
            }
        }
        return try await operation()
    }
}
