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

@Suite("MailFetchBackoffSchedule")
struct MailFetchBackoffScheduleTests {
    private static let epoch = Date(timeIntervalSince1970: 1_000_000)

    @Test("first attempt is always permitted")
    func firstAttemptIsPermitted() {
        let schedule = MailFetchBackoffSchedule()
        #expect(schedule.permitsAttempt(at: Self.epoch, base: 60))
        #expect(schedule.effectiveInterval(base: 60) == 60)
    }

    @Test("first failure keeps the base interval")
    func firstFailureKeepsBaseInterval() {
        var schedule = MailFetchBackoffSchedule()
        schedule.recordAttempt(at: Self.epoch)
        schedule.recordOutcome(succeeded: false)
        #expect(schedule.consecutiveFailures == 1)
        #expect(schedule.effectiveInterval(base: 60) == 60)
        // The gate only engages once extraDelay grows; at the base
        // cadence every tick runs so a slightly-early tick is kept.
        #expect(schedule.permitsAttempt(at: Self.epoch + 59, base: 60))
        #expect(schedule.permitsAttempt(at: Self.epoch + 60, base: 60))
    }

    @Test("consecutive failures stretch the effective interval")
    func consecutiveFailuresStretchInterval() {
        var schedule = MailFetchBackoffSchedule()
        schedule.recordAttempt(at: Self.epoch)
        schedule.recordOutcome(succeeded: false)
        schedule.recordAttempt(at: Self.epoch + 60)
        schedule.recordOutcome(succeeded: false)
        // Second consecutive failure adds the initial 30 s delay, so the
        // next attempt needs 60 + 30 s since the last attempt.
        #expect(schedule.consecutiveFailures == 2)
        #expect(schedule.effectiveInterval(base: 60) == 90)
        #expect(!schedule.permitsAttempt(at: Self.epoch + 60 + 89, base: 60))
        #expect(schedule.permitsAttempt(at: Self.epoch + 60 + 90, base: 60))
    }

    @Test("added delay doubles per consecutive failure")
    func addedDelayDoubles() {
        var schedule = MailFetchBackoffSchedule()
        var now = Self.epoch
        schedule.recordAttempt(at: now)
        for expectedExtra in [0, 30, 60, 120] as [TimeInterval] {
            schedule.recordOutcome(succeeded: false)
            #expect(schedule.extraDelay == expectedExtra)
            now += schedule.effectiveInterval(base: 60)
            schedule.recordAttempt(at: now)
        }
    }

    @Test("success resets the schedule")
    func successResetsSchedule() {
        var schedule = MailFetchBackoffSchedule()
        schedule.recordAttempt(at: Self.epoch)
        schedule.recordOutcome(succeeded: false)
        schedule.recordAttempt(at: Self.epoch + 60)
        schedule.recordOutcome(succeeded: false)
        #expect(schedule.extraDelay == 30)
        schedule.recordOutcome(succeeded: true)
        #expect(schedule.consecutiveFailures == 0)
        #expect(schedule.extraDelay == 0)
        #expect(schedule.permitsAttempt(at: Self.epoch + 120, base: 60))
    }
}
