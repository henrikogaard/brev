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
@testable import BrevMail
import Foundation
import Testing

@Suite("BackgroundMailCoordinator")
@MainActor
struct BackgroundMailCoordinatorTests {
    private static let account = BrevAccount(
        id: "bg-account",
        displayName: "Test",
        emailAddress: "test@example.org"
    )

    /// A tick source the test drives by hand plus a signal the refresh
    /// closure yields into, so assertions await real work instead of
    /// sleeping for wall-clock ticks.
    private struct DrivenTicks {
        let continuation: AsyncStream<Void>.Continuation
        let stream: AsyncStream<Void>
        let refreshContinuation: AsyncStream<Void>.Continuation
        var refreshes: AsyncStream<Void>.Iterator

        init() {
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            let (refreshes, refreshContinuation) = AsyncStream<Void>.makeStream()
            self.stream = stream
            self.continuation = continuation
            self.refreshContinuation = refreshContinuation
            self.refreshes = refreshes.makeAsyncIterator()
        }

        /// Lets one tick through and suspends until its refresh ran.
        mutating func tick() async {
            continuation.yield()
            _ = await refreshes.next()
        }
    }

    private func makeCoordinator(
        refresh: @escaping @Sendable ([any MailBackend]) async -> String?
    ) -> BackgroundMailCoordinator {
        BackgroundMailCoordinator(
            backendsProvider: { [MockBackend(account: Self.account)] },
            refresh: refresh
        )
    }

    private func makeCoordinator(
        ticks: DrivenTicks,
        refresh: @escaping @Sendable ([any MailBackend]) async -> String?
    ) -> BackgroundMailCoordinator {
        BackgroundMailCoordinator(
            backendsProvider: { [MockBackend(account: Self.account)] },
            refresh: refresh,
            tickSource: { _ in ticks.stream }
        )
    }

    @Test("ticks drive repeated refreshes and record success")
    func ticksDriveRefreshes() async {
        let counter = RefreshCounter()
        var ticks = DrivenTicks()
        let signal = ticks.refreshContinuation
        let coordinator = makeCoordinator(ticks: ticks) { _ in
            await counter.bump()
            signal.yield()
            return nil
        }
        coordinator.start(interval: 60)
        await ticks.tick()
        await ticks.tick()
        coordinator.stop()

        #expect(await counter.value == 2)
        #expect(coordinator.lastSuccessfulRefresh != nil)
        #expect(coordinator.lastFailureSummary == nil)
        #expect(!coordinator.isManualSchedule)
    }

    @Test("failure summaries propagate to status")
    func failureSummaryPropagates() async {
        let coordinator = makeCoordinator { _ in "connection lost" }
        await coordinator.refreshNow()

        #expect(coordinator.lastFailureSummary == "connection lost")
        #expect(coordinator.lastSuccessfulRefresh == nil)
    }

    @Test("stop halts further ticks")
    func stopHaltsTicks() async {
        let counter = RefreshCounter()
        var ticks = DrivenTicks()
        let signal = ticks.refreshContinuation
        let coordinator = makeCoordinator(ticks: ticks) { _ in
            await counter.bump()
            signal.yield()
            return nil
        }
        coordinator.start(interval: 60)
        await ticks.tick()
        coordinator.stop()
        // A tick yielded after stop must be dropped: the cancelled loop
        // checks Task.isCancelled before refreshing.
        ticks.continuation.yield()
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(await counter.value == 1)
        #expect(!coordinator.isActive)
    }

    @Test("manual schedule activates without ticking")
    func manualScheduleSkipsTicks() async {
        let counter = RefreshCounter()
        let tickSourceRequested = Flag()
        let coordinator = BackgroundMailCoordinator(
            backendsProvider: { [MockBackend(account: Self.account)] },
            refresh: { _ in
                await counter.bump()
                return nil
            },
            tickSource: { _ in
                tickSourceRequested.value = true
                return AsyncStream<Void>.makeStream().stream
            }
        )
        coordinator.start(interval: nil)

        #expect(coordinator.isActive)
        #expect(coordinator.isManualSchedule)
        #expect(!tickSourceRequested.value)
        #expect(await counter.value == 0)
        coordinator.stop()
    }

    @Test("restart with same interval is a no-op")
    func sameIntervalRestartIsNoOp() {
        let coordinator = makeCoordinator { _ in nil }
        coordinator.start(interval: 60)
        #expect(coordinator.isActive)
        coordinator.start(interval: 60)
        #expect(coordinator.isActive)
        coordinator.stop()
    }

    @Test("root view keeps ticks unless background mail is on")
    func ownershipPolicy() {
        #expect(BackgroundMailOwnershipPolicy.rootViewOwnsTicks(backgroundMailEnabled: false))
        #expect(!BackgroundMailOwnershipPolicy.rootViewOwnsTicks(backgroundMailEnabled: true))
    }
}

private actor RefreshCounter {
    private(set) var value = 0
    func bump() { value += 1 }
}

/// Mutable box for observing a `@Sendable` tick-source closure.
private final class Flag: @unchecked Sendable {
    var value = false
}
