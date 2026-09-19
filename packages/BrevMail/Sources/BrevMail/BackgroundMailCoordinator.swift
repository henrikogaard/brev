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
import Observation

/// Owns the periodic fetch tick loop when background mail is enabled
/// (ADR-0075). Session-owned so the cadence survives the last window
/// closing; with the setting off the root view keeps owning the loop and
/// this coordinator is never started.
///
/// The coordinator never talks to a provider itself: each tick (or a
/// `refreshNow()` call from the status item) runs the injected refresh
/// closure over the backends the provider returns at that moment, so
/// sign-in/out changes take effect without restarting the loop.
@MainActor
@Observable
public final class BackgroundMailCoordinator {
    /// When the last refresh completed without a failure.
    public private(set) var lastSuccessfulRefresh: Date?
    /// Provider-neutral failure summary from the last refresh, if any.
    public private(set) var lastFailureSummary: String?
    /// Whether a refresh is in flight right now.
    public private(set) var isRefreshing = false
    /// Latest unread count, pushed in by the root view's badge computation.
    public var unreadCount = 0
    /// Whether the background cadence is currently running.
    public var isActive = false
    /// Whether the current schedule produces no ticks (manual mode — the
    /// coordinator is active but only server pushes/IDLE deliver mail).
    public private(set) var isManualSchedule = true

    /// Supplies the currently connected backends at each refresh.
    public var backendsProvider: @MainActor () -> [any MailBackend]
    private let refresh: @Sendable ([any MailBackend]) async -> String?
    private let tickSource: @Sendable (TimeInterval) -> AsyncStream<Void>
    private let now: @Sendable () -> Date
    private var tickTask: Task<Void, Never>?
    private var intervalSeconds: TimeInterval?
    /// Consecutive-failure tracker that stretches the effective cadence
    /// so a stuck account is not polled at full rate forever.
    private var backoff = MailFetchBackoffSchedule()

    /// - Parameters:
    ///   - backendsProvider: returns the currently connected backends.
    ///   - refresh: performs one refresh over the given backends and returns
    ///     a failure summary, or `nil` on success. Defaults to
    ///     `MailFetchScheduler.performBackgroundRefresh`.
    ///   - tickSource: produces the tick stream for a given interval;
    ///     injectable so tests can drive ticks deterministically.
    ///   - now: supplies the current time for backoff gating; injectable
    ///     so tests can advance the clock deterministically.
    public init(
        backendsProvider: @escaping @MainActor () -> [any MailBackend] = { [] },
        refresh: (@Sendable ([any MailBackend]) async -> String?)? = nil,
        tickSource: @escaping @Sendable (TimeInterval) -> AsyncStream<Void> = {
            MailFetchScheduler.ticks(every: $0)
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.backendsProvider = backendsProvider
        self.refresh = refresh ?? { backends in
            await MailFetchScheduler.performBackgroundRefresh(backends: backends)
        }
        self.tickSource = tickSource
        self.now = now
    }

    /// Starts the cadence. A `nil` interval (manual schedule) activates
    /// background presence without a tick loop — IDLE/push still deliver.
    /// Calling `start` again with the same interval is a no-op; a different
    /// interval restarts the loop.
    public func start(interval: TimeInterval?) {
        guard !(isActive && intervalSeconds == interval) else { return }
        tickTask?.cancel()
        intervalSeconds = interval
        isManualSchedule = interval == nil
        isActive = true
        if let interval {
            tickTask = Task { @MainActor [weak self, tickSource] in
                for await _ in tickSource(interval) {
                    guard let self, !Task.isCancelled else { break }
                    // Consecutive failures stretch the effective interval;
                    // ticks inside the backoff window are skipped.
                    guard backoff.permitsAttempt(at: now(), base: interval) else { continue }
                    backoff.recordAttempt(at: now())
                    await refreshNow()
                }
            }
        }
    }

    /// Stops the tick loop and marks background presence inactive.
    public func stop() {
        tickTask?.cancel()
        tickTask = nil
        isActive = false
    }

    /// Runs one refresh immediately, recording success/failure status.
    public func refreshNow() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if let failure = await refresh(backendsProvider()) {
            lastFailureSummary = failure
            backoff.recordOutcome(succeeded: false)
        } else {
            lastSuccessfulRefresh = Date()
            lastFailureSummary = nil
            backoff.recordOutcome(succeeded: true)
        }
    }
}

/// Decides who owns the periodic fetch tick loop so the off path is
/// byte-for-byte today's behavior (ADR-0075 consequence 1).
public enum BackgroundMailOwnershipPolicy {
    /// The root view keeps owning ticks unless background mail is enabled.
    public static func rootViewOwnsTicks(backgroundMailEnabled: Bool) -> Bool {
        !backgroundMailEnabled
    }
}
