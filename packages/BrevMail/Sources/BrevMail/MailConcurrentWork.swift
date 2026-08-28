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
    static func map<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        operation: @escaping @Sendable (Input) async -> Output
    ) async -> [Output] {
        await withTaskGroup(of: (Int, Output).self, returning: [Output].self) { group in
            for (index, input) in inputs.enumerated() {
                group.addTask {
                    let output = await operation(input)
                    return (index, output)
                }
            }

            var orderedResults = [Output?](repeating: nil, count: inputs.count)
            for await (index, output) in group {
                orderedResults[index] = output
            }
            return orderedResults.compactMap { $0 }
        }
    }
}
