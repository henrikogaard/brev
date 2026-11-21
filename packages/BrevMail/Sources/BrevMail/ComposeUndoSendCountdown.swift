/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions: The above copyright
 notice and this permission notice shall be included in all copies or
 substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

import Foundation

enum ComposeUndoSendCountdown {
    typealias Sleeper = @MainActor (UInt64) async throws -> Void

    @MainActor
    static func run(
        delaySeconds: Int,
        sleeper: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) },
        onProgress: @escaping @MainActor (_ remainingSeconds: Int, _ progress: Double) -> Void,
        onCountdownComplete: @escaping @MainActor () -> Void,
        send: @escaping @MainActor () async -> Void
    ) async throws {
        guard delaySeconds > 0 else {
            try Task.checkCancellation()
            await send()
            return
        }

        for (elapsed, remaining) in ComposeUndoSendPolicy.countdownValues(for: delaySeconds).enumerated() {
            try Task.checkCancellation()
            onProgress(remaining, Double(elapsed) / Double(delaySeconds))
            try await sleeper(1_000_000_000)
        }

        try Task.checkCancellation()
        onProgress(0, 1)
        try Task.checkCancellation()
        onCountdownComplete()
        try Task.checkCancellation()
        await send()
    }
}
