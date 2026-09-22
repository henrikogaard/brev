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

enum MessageBodyLoadTimeoutRace {
    static func load(
        messageID: String,
        sourceID: MailSourceID?,
        backend: any MailBackend,
        timeoutNanoseconds: UInt64,
        timeoutError: @escaping @Sendable () -> any Error
    ) async throws -> MessageBody {
        let interval = MailUIPerformanceDiagnostics.beginInterval("Message Body Backend Fetch")
        defer { MailUIPerformanceDiagnostics.endInterval(interval) }
        do {
            let body = try await race(
                timeoutNanoseconds: timeoutNanoseconds,
                timeoutError: timeoutError
            ) {
                if let sourceID {
                    return try await backend.body(for: messageID, sourceID: sourceID)
                }
                return try await backend.body(for: messageID)
            }
            MailUIPerformanceDiagnostics.logBodyFetchFinished(
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
            return body
        } catch {
            MailUIPerformanceDiagnostics.logBodyFetchFailed(
                error: error,
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
            throw error
        }
    }

    /// Races `operation` against a timeout. Whichever finishes first wins;
    /// the loser task is cancelled. Used by the conversation reader to bound
    /// the whole permit-wait + backend-load span, so a stalled permit queue
    /// cannot pin a card at "Loading message…" forever (#51).
    static func race<T>(
        timeoutNanoseconds: UInt64,
        timeoutError: @escaping @Sendable () -> any Error,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let state = FirstMessageBodyLoadResult<T>()
            let bodyTask = Task.detached(priority: .userInitiated) {
                do {
                    let value = try await operation()
                    state.resume(.success(value), continuation: continuation)
                } catch {
                    state.resume(.failure(error), continuation: continuation)
                }
            }
            let timeoutTask = Task.detached {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    state.resume(.failure(timeoutError()), continuation: continuation)
                } catch {
                    // The timeout task is cancelled when the operation wins.
                }
            }

            state.setOnComplete {
                bodyTask.cancel()
                timeoutTask.cancel()
            }
        }
    }
}

private final class FirstMessageBodyLoadResult<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var didComplete = false
    private var onComplete: (@Sendable () -> Void)?

    func setOnComplete(_ action: @escaping @Sendable () -> Void) {
        lock.lock()
        if didComplete {
            lock.unlock()
            action()
            return
        }
        onComplete = action
        lock.unlock()
    }

    func resume(
        _ result: Result<T, any Error>,
        continuation: CheckedContinuation<T, any Error>
    ) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        let onComplete = onComplete
        lock.unlock()

        onComplete?()
        continuation.resume(with: result)
    }
}
