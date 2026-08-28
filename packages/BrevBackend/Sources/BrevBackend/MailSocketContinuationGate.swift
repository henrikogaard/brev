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

final class MailSocketContinuationGate<Success>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Success, Error>?

    init(_ continuation: CheckedContinuation<Success, Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume(returning value: Success) -> Bool {
        guard let continuation = takeContinuation() else { return false }
        continuation.resume(returning: value)
        return true
    }

    @discardableResult
    func resume(throwing error: any Error) -> Bool {
        guard let continuation = takeContinuation() else { return false }
        continuation.resume(throwing: error)
        return true
    }

    private func takeContinuation() -> CheckedContinuation<Success, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let value = continuation
        continuation = nil
        return value
    }
}
