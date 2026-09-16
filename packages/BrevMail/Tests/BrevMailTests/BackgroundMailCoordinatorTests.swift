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

    private func makeCoordinator(
        refresh: @escaping @Sendable ([any MailBackend]) async -> String?
    ) -> BackgroundMailCoordinator {
        BackgroundMailCoordinator(
            backendsProvider: { [MockBackend(account: Self.account)] },
            refresh: refresh
        )
    }

    @Test("ticks drive repeated refreshes and record success")
    func ticksDriveRefreshes() async throws {
        let counter = RefreshCounter()
        let coordinator = makeCoordinator { _ in
            await counter.bump()
            return nil
        }
        coordinator.start(interval: 0.05)
        try await Task.sleep(for: .milliseconds(230))
        coordinator.stop()

        #expect(await counter.value >= 2)
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
    func stopHaltsTicks() async throws {
        let counter = RefreshCounter()
        let coordinator = makeCoordinator { _ in
            await counter.bump()
            return nil
        }
        coordinator.start(interval: 0.05)
        try await Task.sleep(for: .milliseconds(120))
        coordinator.stop()
        let settled = await counter.value
        try await Task.sleep(for: .milliseconds(150))

        #expect(settled >= 1)
        #expect(await counter.value == settled)
        #expect(!coordinator.isActive)
    }

    @Test("manual schedule activates without ticking")
    func manualScheduleSkipsTicks() async throws {
        let counter = RefreshCounter()
        let coordinator = makeCoordinator { _ in
            await counter.bump()
            return nil
        }
        coordinator.start(interval: nil)
        try await Task.sleep(for: .milliseconds(120))

        #expect(coordinator.isActive)
        #expect(coordinator.isManualSchedule)
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
