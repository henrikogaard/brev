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

import BrevCalendar
@testable import BrevMail
import Foundation
import Testing

@Suite("PIMSyncScheduler")
@MainActor
struct PIMSyncSchedulerTests {
    /// A tick source the test drives by hand plus a signal the sync
    /// closure yields into, so assertions await real work instead of
    /// sleeping for wall-clock ticks.
    private struct DrivenTicks {
        let continuation: AsyncStream<Void>.Continuation
        let stream: AsyncStream<Void>
        let syncContinuation: AsyncStream<Void>.Continuation
        var syncs: AsyncStream<Void>.Iterator

        init() {
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            let (syncs, syncContinuation) = AsyncStream<Void>.makeStream()
            self.stream = stream
            self.continuation = continuation
            self.syncContinuation = syncContinuation
            self.syncs = syncs.makeAsyncIterator()
        }

        /// Lets one tick through and suspends until its sync pass ran.
        mutating func tick() async {
            continuation.yield()
            _ = await syncs.next()
        }
    }

    private func makeSource(
        id: String,
        kind: PIMSourceKind = .calendar,
        syncEnabled: Bool = true,
        status: PIMSourceStatus = .ready
    ) -> PIMSource {
        PIMSource(
            id: id,
            kind: kind,
            provider: .calDAV,
            displayName: id,
            syncEnabled: syncEnabled,
            status: status
        )
    }

    private func makeScheduler(
        ticks: DrivenTicks,
        sources: [PIMSource],
        syncSource: @escaping @MainActor (PIMSource) async -> String?
    ) -> PIMSyncScheduler {
        let scheduler = PIMSyncScheduler(
            sourcesProvider: { sources },
            tickSource: { _ in ticks.stream }
        )
        scheduler.syncSource = syncSource
        return scheduler
    }

    @Test("tick syncs every sync-enabled source, skipping disabled and unsyncable")
    func tickSyncsEnabledSources() async {
        let counter = SyncCounter()
        var ticks = DrivenTicks()
        let signal = ticks.syncContinuation
        let scheduler = makeScheduler(
            ticks: ticks,
            sources: [
                makeSource(id: "cal-on"),
                makeSource(id: "cal-off", syncEnabled: false),
                makeSource(id: "cal-connecting", status: .connecting)
            ]
        ) { source in
            await counter.bump(source.id)
            signal.yield()
            return nil
        }
        scheduler.start(interval: 60)
        await ticks.tick()
        scheduler.stop()

        #expect(await counter.ids == ["cal-on"])
        #expect(scheduler.lastSuccessfulSync != nil)
        #expect(scheduler.lastFailureSummary == nil)
    }

    @Test("sources are re-read every pass so enable/disable lands without restart")
    func sourcesReReadEachPass() async {
        var currentSources = [makeSource(id: "first")]
        let counter = SyncCounter()
        var ticks = DrivenTicks()
        let signal = ticks.syncContinuation
        let scheduler = PIMSyncScheduler(
            sourcesProvider: { currentSources },
            tickSource: { _ in ticks.stream }
        )
        scheduler.syncSource = { source in
            await counter.bump(source.id)
            signal.yield()
            return nil
        }
        scheduler.start(interval: 60)
        await ticks.tick()
        currentSources = [
            makeSource(id: "first", syncEnabled: false),
            makeSource(id: "second", kind: .tasks)
        ]
        await ticks.tick()
        scheduler.stop()

        #expect(await counter.ids == ["first", "second"])
    }

    @Test("failure summary propagates; success clears it")
    func failureSummaryPropagates() async {
        var failing = true
        let scheduler = PIMSyncScheduler(
            sourcesProvider: { [makeSource(id: "a")] }
        )
        scheduler.syncSource = { _ in failing ? "server unreachable" : nil }
        await scheduler.syncNowAll()
        #expect(scheduler.lastFailureSummary == "server unreachable")
        #expect(scheduler.lastSuccessfulSync == nil)

        failing = false
        await scheduler.syncNowAll()
        #expect(scheduler.lastFailureSummary == nil)
        #expect(scheduler.lastSuccessfulSync != nil)
    }

    @Test("manual schedule activates without ticking")
    func manualScheduleSkipsTicks() async {
        let counter = SyncCounter()
        let tickSourceRequested = Flag()
        let scheduler = PIMSyncScheduler(
            sourcesProvider: { [makeSource(id: "a")] },
            tickSource: { _ in
                tickSourceRequested.value = true
                return AsyncStream<Void>.makeStream().stream
            }
        )
        scheduler.syncSource = { source in
            await counter.bump(source.id)
            return nil
        }
        scheduler.start(interval: nil)

        #expect(scheduler.isActive)
        #expect(scheduler.isManualSchedule)
        #expect(!tickSourceRequested.value)
        scheduler.stop()
    }

    @Test("stop halts further ticks")
    func stopHaltsTicks() async {
        let counter = SyncCounter()
        var ticks = DrivenTicks()
        let signal = ticks.syncContinuation
        let scheduler = makeScheduler(
            ticks: ticks,
            sources: [makeSource(id: "a")]
        ) { source in
            await counter.bump(source.id)
            signal.yield()
            return nil
        }
        scheduler.start(interval: 60)
        await ticks.tick()
        scheduler.stop()
        ticks.continuation.yield()
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(await counter.ids == ["a"])
        #expect(!scheduler.isActive)
    }

    @Test("restart with same interval is a no-op")
    func sameIntervalRestartIsNoOp() {
        let scheduler = PIMSyncScheduler()
        scheduler.start(interval: 60)
        #expect(scheduler.isActive)
        scheduler.start(interval: 60)
        #expect(scheduler.isActive)
        scheduler.stop()
    }
}

private actor SyncCounter {
    private(set) var ids: [String] = []
    func bump(_ id: String) { ids.append(id) }
}

/// Mutable box for observing a `@Sendable` tick-source closure.
private final class Flag: @unchecked Sendable {
    var value = false
}
