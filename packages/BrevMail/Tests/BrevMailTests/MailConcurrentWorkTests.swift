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

@testable import BrevMail
import Foundation
import Testing

struct MailConcurrentWorkTests {
    @Test("a healthy source publishes before another source finishes")
    @MainActor
    func healthySourcePublishesImmediately() async {
        let barrier = MailConcurrentStartBarrier(expectedCount: 2)
        var received: [Int] = []
        await MailConcurrentWork.forEachResult([0, 1]) { value in
            if value == 1 { await barrier.arrive(1) }
            return value
        } receive: { _, value in
            received.append(value)
            if value == 0 { await barrier.arrive(2) }
        }
        #expect(received == [0, 1])
        #expect(await barrier.arrivalCountAtRelease == 2)
    }

    @Test("runs independent mailbox work concurrently while preserving source order")
    func runsIndependentMailboxWorkConcurrentlyWhilePreservingSourceOrder() async throws {
        let barrier = MailConcurrentStartBarrier(expectedCount: 3)
        let results = await MailConcurrentWork.map([1, 2, 3]) { value in
            await barrier.arrive(value)
            return value * 10
        }

        #expect(results == [10, 20, 30])
        #expect(await barrier.arrivalCountAtRelease == 3)
    }
}

/// Holds each operation until every input has entered the concurrent map.
/// A serial implementation releases after the safety timeout with an arrival
/// count of one, making the assertion fail without measuring runner wall time.
private actor MailConcurrentStartBarrier {
    private let expectedCount: Int
    private var arrivals: Set<Int> = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false
    private var safetyReleaseTask: Task<Void, Never>?
    private(set) var arrivalCountAtRelease = 0

    init(expectedCount: Int) {
        self.expectedCount = expectedCount
    }

    func arrive(_ value: Int) async {
        guard !isReleased else { return }
        arrivals.insert(value)
        if arrivals.count == expectedCount {
            release()
            return
        }

        if safetyReleaseTask == nil {
            safetyReleaseTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self?.release()
            }
        }

        await withCheckedContinuation { continuation in
            if isReleased {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }

    private func release() {
        guard !isReleased else { return }
        isReleased = true
        arrivalCountAtRelease = arrivals.count
        safetyReleaseTask?.cancel()
        safetyReleaseTask = nil
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }
}
