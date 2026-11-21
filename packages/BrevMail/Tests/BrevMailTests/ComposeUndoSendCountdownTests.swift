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

@Suite("Compose undo-send countdown")
struct ComposeUndoSendCountdownTests {
    @Test("cancellation during the final interval suppresses send")
    @MainActor
    func finalIntervalCancellationSuppressesSend() async {
        let taskBox = CountdownTaskBox()
        var sleepCount = 0
        var completionCount = 0
        var sendCount = 0
        let task = Task { @MainActor in
            try await ComposeUndoSendCountdown.run(
                delaySeconds: 3,
                sleeper: { _ in
                    sleepCount += 1
                    if sleepCount == 3 {
                        taskBox.task?.cancel()
                    }
                    try Task.checkCancellation()
                },
                onProgress: { _, _ in },
                onCountdownComplete: { completionCount += 1 },
                send: { sendCount += 1 }
            )
        }
        taskBox.task = task

        do {
            try await task.value
            Issue.record("Expected cancellation before send")
        } catch is CancellationError {}
        catch {
            Issue.record("Unexpected error awaiting countdown: \(error)")
        }

        #expect(sleepCount == 3)
        #expect(completionCount == 0)
        #expect(sendCount == 0)
    }

    @Test("expiry sends once after the ring spans the configured delay")
    @MainActor
    func expirySendsOnceAfterConfiguredProgress() async throws {
        let delaySeconds = 4
        var sleepDurations: [UInt64] = []
        var remainingValues: [Int] = []
        var progressPercentages: [Int] = []
        var completionCount = 0
        var sendCount = 0

        try await ComposeUndoSendCountdown.run(
            delaySeconds: delaySeconds,
            sleeper: { sleepDurations.append($0) },
            onProgress: { remaining, progress in
                remainingValues.append(remaining)
                progressPercentages.append(Int((progress * 100).rounded()))
            },
            onCountdownComplete: { completionCount += 1 },
            send: { sendCount += 1 }
        )

        #expect(sleepDurations == Array(repeating: 1_000_000_000, count: delaySeconds))
        #expect(remainingValues == [4, 3, 2, 1, 0])
        #expect(progressPercentages == [0, 25, 50, 75, 100])
        #expect(completionCount == 1)
        #expect(sendCount == 1)
    }

    @Test("zero delay sends once without sleeping")
    @MainActor
    func zeroDelaySendsOnceWithoutSleeping() async throws {
        var sleepCount = 0
        var progressCount = 0
        var completionCount = 0
        var sendCount = 0

        try await ComposeUndoSendCountdown.run(
            delaySeconds: 0,
            sleeper: { _ in sleepCount += 1 },
            onProgress: { _, _ in progressCount += 1 },
            onCountdownComplete: { completionCount += 1 },
            send: { sendCount += 1 }
        )

        #expect(sleepCount == 0)
        #expect(progressCount == 0)
        #expect(completionCount == 0)
        #expect(sendCount == 1)
    }

    @Test("ring progress clamps to the configured monotonic duration")
    func ringProgressClampsAtStartMidpointAndEnd() {
        let start = 100.0

        #expect(ComposeUndoSendProgress.fraction(startedAt: start, now: start - 1, duration: 4) == 0)
        #expect(ComposeUndoSendProgress.fraction(startedAt: start, now: start, duration: 4) == 0)
        #expect(ComposeUndoSendProgress.fraction(startedAt: start, now: start + 2, duration: 4) == 0.5)
        #expect(ComposeUndoSendProgress.fraction(startedAt: start, now: start + 4, duration: 4) == 1)
        #expect(ComposeUndoSendProgress.fraction(startedAt: start, now: start + 5, duration: 4) == 1)
        #expect(ComposeUndoSendProgress.fraction(startedAt: start, now: start, duration: 1) == 0)
        #expect(ComposeUndoSendProgress.fraction(startedAt: start, now: start + 0.5, duration: 1) == 0.5)
        #expect(ComposeUndoSendProgress.fraction(startedAt: start, now: start + 1, duration: 1) == 1)
    }
}

@MainActor
private final class CountdownTaskBox {
    var task: Task<Void, Error>?
}
