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
            let body = try await withCheckedThrowingContinuation { continuation in
                let state = FirstMessageBodyLoadResult()
                let bodyTask = Task.detached(priority: .userInitiated) {
                    do {
                        let body: MessageBody
                        if let sourceID {
                            body = try await backend.body(for: messageID, sourceID: sourceID)
                        } else {
                            body = try await backend.body(for: messageID)
                        }
                        state.resume(.success(body), continuation: continuation)
                    } catch {
                        state.resume(.failure(error), continuation: continuation)
                    }
                }
                let timeoutTask = Task.detached {
                    do {
                        try await Task.sleep(nanoseconds: timeoutNanoseconds)
                        state.resume(.failure(timeoutError()), continuation: continuation)
                    } catch {
                        // The timeout task is cancelled when the body load wins.
                    }
                }

                state.setOnComplete {
                    bodyTask.cancel()
                    timeoutTask.cancel()
                }
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
}

private final class FirstMessageBodyLoadResult: @unchecked Sendable {
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
        _ result: Result<MessageBody, any Error>,
        continuation: CheckedContinuation<MessageBody, any Error>
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
