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

/// Runs independent mailbox work concurrently while keeping the caller's input order.
enum MailConcurrentWork {
    @MainActor
    static func forEachResult<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        operation: @escaping @Sendable (Input) async -> Output,
        receive: (Int, Output) async -> Void
    ) async {
        await withTaskGroup(of: (Int, Output).self) { group in
            var next = 0
            func enqueue(_ index: Int) {
                group.addTask { await (index, operation(inputs[index])) }
            }
            while next < min(4, inputs.count) {
                enqueue(next); next += 1
            }
            while let (index, result) = await group.next() {
                guard !Task.isCancelled else { group.cancelAll(); return }
                await receive(index, result)
                if next < inputs.count { enqueue(next); next += 1 }
            }
        }
    }

    static func map<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        operation: @escaping @Sendable (Input) async -> Output
    ) async -> [Output] {
        await withTaskGroup(of: (Int, Output).self, returning: [Output].self) { group in
            var next = 0
            func enqueue(_ index: Int) {
                group.addTask { await (index, operation(inputs[index])) }
            }
            while next < min(4, inputs.count) {
                enqueue(next); next += 1
            }
            var orderedResults = [Output?](repeating: nil, count: inputs.count)
            for await (index, output) in group {
                guard !Task.isCancelled else { group.cancelAll(); return [] }
                orderedResults[index] = output
                if next < inputs.count { enqueue(next); next += 1 }
            }
            return orderedResults.compactMap { $0 }
        }
    }
}
