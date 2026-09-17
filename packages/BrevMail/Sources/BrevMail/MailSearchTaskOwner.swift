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

/// Owns one cancellable search worker across SwiftUI triggers and explicit retries.
@MainActor
final class MailSearchTaskOwner {
    private var task: Task<Void, Never>?
    private var generation: UUID?

    func run(_ operation: @escaping @MainActor @Sendable () async -> Void) async {
        guard !Task.isCancelled else { return }
        task?.cancel()
        let id = UUID()
        let current = Task { await operation() }
        generation = id
        task = current
        await withTaskCancellationHandler {
            await current.value
        } onCancel: {
            current.cancel()
        }
        if generation == id {
            task = nil
            generation = nil
        }
    }

    func cancel() { task?.cancel() }
}
