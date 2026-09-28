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
import Foundation
import Observation

/// Periodically syncs PIM sources the user opted into background sync.
///
/// Connecting a calendar/contacts/tasks source never enables sync on its
/// own — `PIMSource.syncEnabled` is the explicit opt-in the Settings
/// toggle flips (ADR-0006). Until now that flag only kicked a single
/// immediate pass; this scheduler is the loop that keeps enabled sources
/// fresh on the same cadence the user configured for mail fetch
/// (`FetchScheduleSettings.interval`), so a remote edit lands without a
/// manual Sync Now.
///
/// The scheduler never talks to a provider itself: each tick lists the
/// sources through `sourcesProvider` and runs `syncSource` on each
/// enabled, syncable source, so connect/disconnect changes take effect
/// without restarting the loop. Session-owned like
/// `BackgroundMailCoordinator`, so the cadence survives a window closing.
@MainActor
@Observable
public final class PIMSyncScheduler {
    /// When the last pass completed without a failure.
    public private(set) var lastSuccessfulSync: Date?
    /// Provider-neutral failure summary from the last pass, if any.
    public private(set) var lastFailureSummary: String?
    /// Whether a sync pass is in flight right now.
    public private(set) var isSyncing = false
    /// Whether the cadence is currently running.
    public private(set) var isActive = false
    /// Whether the current schedule produces no ticks (manual fetch).
    public private(set) var isManualSchedule = true

    /// Source statuses a scheduled pass will sync — the same gate the
    /// browsing models use for Sync Now, so a source mid-auth or still
    /// connecting is skipped rather than failed. `.syncing` is excluded:
    /// a sync already in flight (user Sync Now or the previous tick)
    /// must not be re-entered — the sync actors are reentrant, so a
    /// second concurrent pass would double the provider requests and
    /// write the same cursor/cache concurrently.
    private static let syncableStatuses: Set<PIMSourceStatus> = [
        .ready, .permissionLimited, .failed
    ]

    /// Supplies the configured sources at each pass.
    public var sourcesProvider: @MainActor () async -> [PIMSource]
    /// Runs one sync pass for the given source and returns a failure
    /// message, or `nil` on success (and when no service is configured
    /// for the source's kind — an absent service is a session gap, not
    /// a provider failure). Settable post-init so the session can hand
    /// over a closure that captures the session itself.
    public var syncSource: @MainActor (PIMSource) async -> String? = { _ in nil }
    private let tickSource: @Sendable (TimeInterval) -> AsyncStream<Void>
    private let now: @Sendable () -> Date
    private var tickTask: Task<Void, Never>?
    private var intervalSeconds: TimeInterval?
    /// Consecutive-failure tracker that stretches the effective cadence
    /// so a stuck source is not polled at full rate forever — the same
    /// schedule the mail fetch loop uses.
    private var backoff = MailFetchBackoffSchedule()

    /// - Parameters:
    ///   - sourcesProvider: returns the configured PIM sources.
    ///   - syncSource: performs one sync pass for a source; assignable
    ///     post-init and injectable so tests can assert routing and
    ///     drive failures.
    ///   - tickSource: produces the tick stream for a given interval;
    ///     injectable so tests can drive ticks deterministically.
    ///   - now: supplies the current time for backoff gating.
    public init(
        sourcesProvider: @escaping @MainActor () async -> [PIMSource] = { [] },
        tickSource: @escaping @Sendable (TimeInterval) -> AsyncStream<Void> = {
            MailFetchScheduler.ticks(every: $0)
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sourcesProvider = sourcesProvider
        self.tickSource = tickSource
        self.now = now
    }

    /// Starts the cadence. A `nil` interval (manual fetch) activates
    /// without a tick loop — Sync Now stays available for manual passes.
    /// Calling `start` again with the same interval is a no-op; a
    /// different interval restarts the loop.
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
                    guard backoff.permitsAttempt(at: now(), base: interval)
                    else { continue }
                    backoff.recordAttempt(at: now())
                    await syncNowAll()
                }
            }
        }
    }

    /// Stops the tick loop and marks the scheduler inactive.
    public func stop() {
        tickTask?.cancel()
        tickTask = nil
        isActive = false
    }

    /// Syncs every source whose background-sync opt-in is on and whose
    /// status is syncable, recording success/failure status.
    public func syncNowAll() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let targets = await sourcesProvider().filter {
            $0.syncEnabled && Self.syncableStatuses.contains($0.status)
        }
        var failures: [String] = []
        for source in targets {
            if let failure = await syncSource(source) {
                failures.append(failure)
            }
        }
        if let failure = failures.first {
            lastFailureSummary = failure
            backoff.recordOutcome(succeeded: false)
        } else {
            lastSuccessfulSync = now()
            lastFailureSummary = nil
            backoff.recordOutcome(succeeded: true)
        }
    }
}
