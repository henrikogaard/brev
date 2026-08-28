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

@Suite("MailFetchScheduler")
struct MailFetchSchedulerTests {
    @Test("manual mode produces no ticks")
    func manualModeProducesNoTicks() async {
        var tickCount = 0
        for await _ in MailFetchScheduler.ticks(every: nil) {
            tickCount += 1
        }
        #expect(tickCount == 0)
    }

    @Test("zero-second interval produces no ticks")
    func zeroIntervalProducesNoTicks() async {
        var tickCount = 0
        for await _ in MailFetchScheduler.ticks(every: 0) {
            tickCount += 1
        }
        #expect(tickCount == 0)
    }

    @Test("negative interval produces no ticks")
    func negativeIntervalProducesNoTicks() async {
        var tickCount = 0
        for await _ in MailFetchScheduler.ticks(every: -1) {
            tickCount += 1
        }
        #expect(tickCount == 0)
    }

    @Test("scheduler is cancelled when the consuming task is cancelled")
    func schedulerIsCancelledWhenTaskIsCancelled() async {
        // Use a very short interval (0.01 s) so the stream produces at
        // least one tick before we cancel.
        let stream = MailFetchScheduler.ticks(every: 0.01)
        var tickCount = 0
        let consumer = Task {
            for await _ in stream {
                tickCount += 1
                if tickCount >= 2 { break }
            }
        }
        await consumer.value
        // We should have exited after collecting 2 ticks.
        #expect(tickCount == 2)
    }
}

@Suite("MailFetchBackoff")
struct MailFetchBackoffTests {
    @Test("initial delay is 30 seconds")
    func initialDelayIs30Seconds() {
        #expect(MailFetchBackoff.initial == 30)
    }

    @Test("backoff doubles on each call")
    func backoffDoubles() {
        #expect(MailFetchBackoff.next(previous: 30) == 60)
        #expect(MailFetchBackoff.next(previous: 60) == 120)
        #expect(MailFetchBackoff.next(previous: 120) == 240)
    }

    @Test("backoff is capped at the default maximum of 900 seconds")
    func backoffIsCappedAtMax() {
        #expect(MailFetchBackoff.next(previous: 600) == 900)
        #expect(MailFetchBackoff.next(previous: 900) == 900)
        #expect(MailFetchBackoff.next(previous: 10000) == 900)
    }

    @Test("custom max cap is respected")
    func customMaxCapIsRespected() {
        #expect(MailFetchBackoff.next(previous: 30, max: 45) == 45)
    }
}
