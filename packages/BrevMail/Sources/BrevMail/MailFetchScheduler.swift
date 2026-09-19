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
import BrevSettings
import Foundation

/// Produces periodic tick events for the automatic mail-fetch scheduler.
///
/// Use `ticks(every:)` inside a `.task(id: interval)` modifier so the
/// stream is automatically cancelled and restarted whenever the interval
/// changes. When `interval` is `nil` (manual-only mode) no ticks are
/// produced.
///
/// The scheduler does not enforce rate-limiting itself; the caller is
/// responsible for gating actual refresh work behind `canStartRefresh()`
/// before acting on a tick.
public enum MailFetchScheduler {
    /// Refreshes each supplied source's Inbox through its source-scoped backend.
    ///
    /// Used by Unified Inbox foreground and manual refreshes, where there is no
    /// single concrete selected folder to pass to `MailBackend.refresh`.
    /// Successful sources are retained when another source fails.
    ///
    /// - Parameters:
    ///   - backends: The currently connected account backends.
    ///   - sourceSections: The enabled mailbox sources visible in Unified Inbox.
    /// - Returns: The first provider error message, or `nil` when all targets succeed.
    static func performVisibleInboxRefresh(
        backends: [any MailBackend],
        sourceSections: [MailSourceSection]
    ) async -> String? {
        let backendsByAccountID = backends.reduce(into: [BrevAccount.ID: any MailBackend]()) {
            $0[$1.account.id] = $1
        }
        let failures: [String?] = await MailConcurrentWork.map(sourceSections) { section in
            guard let backend = backendsByAccountID[section.account.id] else {
                return MailBackendError.notConnected.localizedDescription
            }

            let inbox: Folder
            if let cachedInbox = section.folders.first(where: { $0.role == .inbox }) {
                inbox = cachedInbox
            } else {
                do {
                    let refreshedFolders = try await backend.folders(in: section.id)
                    guard let recoveredInbox = refreshedFolders.first(where: { $0.role == .inbox }) else {
                        return section.loadError?.message
                            ?? MailBackendError.notFound(id: "Inbox").localizedDescription
                    }
                    inbox = recoveredInbox
                } catch {
                    return error.localizedDescription
                }
            }
            do {
                try await backend.refresh(folder: inbox, in: section.id)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        return failures.compactMap { $0 }.first
    }

    /// Performs a one-shot background mailbox refresh for all supplied backends.
    ///
    /// Uses a backend's mailbox-wide background refresh service when available,
    /// so richer backends can warm multiple first-page caches. Backends without
    /// that service fall back to locating and refreshing the inbox folder.
    /// Returns the first failure's provider-neutral message (the same
    /// `localizedDescription` the visible refresh path surfaces), or `nil`
    /// when every backend succeeded — an iOS `BGAppRefreshTask` caller may
    /// ignore the result and call `task.setTaskCompleted(success:)`.
    ///
    /// - Parameter backends: The currently connected backends. May be empty.
    /// - Returns: The first provider error message, or `nil` when all targets succeed.
    @discardableResult
    public static func performBackgroundRefresh(backends: [any MailBackend]) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            for backend in backends {
                // A background window is also the only chance a suspended app
                // gets to flush "send later" drafts that came due meanwhile.
                if let scheduledSends = backend.extensionService(ScheduledSendManaging.self) {
                    group.addTask {
                        await scheduledSends.deliverDueScheduledSends()
                        return nil
                    }
                }
                group.addTask {
                    do {
                        let mailbox = try await backend.currentMailbox()
                        let sourceID = backend.sourceID(for: mailbox)
                        if let backgroundRefresher = backend.extensionService(MailboxBackgroundRefreshing.self) {
                            try await backgroundRefresher.refreshMailbox(for: sourceID)
                            return nil
                        }

                        let folders = try await backend.folders()
                        guard let inbox = folders.first(where: { $0.role == .inbox }) else { return nil }
                        try await backend.refresh(folder: inbox)
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                }
            }
            for await failure in group {
                if let failure { return failure }
            }
            return nil
        }
    }

    /// Returns an `AsyncStream` that yields `Void` at the given interval.
    ///
    /// The first tick is delayed by `interval` seconds (i.e. no
    /// immediate fire on subscription), matching Apple Mail behaviour.
    /// If `intervalSeconds` is `nil` the stream completes immediately
    /// with no ticks.
    public static func ticks(every intervalSeconds: TimeInterval?) -> AsyncStream<Void> {
        guard let intervalSeconds, intervalSeconds > 0 else {
            return AsyncStream { $0.finish() }
        }
        return AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
                    guard !Task.isCancelled else { break }
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Computes the backoff delay (in seconds) for a refresh failure.
///
/// Uses a simple doubling strategy capped at `maxDelay`.
enum MailFetchBackoff {
    /// Returns the next backoff interval given the previous one.
    static func next(previous: TimeInterval, max maxDelay: TimeInterval = 900) -> TimeInterval {
        min(previous * 2, maxDelay)
    }

    /// Initial backoff delay after the first consecutive failure.
    static let initial: TimeInterval = 30
}

/// Tracks consecutive scheduled-refresh failures and stretches the
/// effective fetch cadence so a persistently failing account (for
/// example one stuck in `reauthenticationRequired`) is not polled at
/// full rate forever.
///
/// The first failure keeps the base interval — only *consecutive*
/// failures add delay. The added delay doubles per failure via
/// `MailFetchBackoff` (30 s up to the 900 s cap). Any success resets
/// the schedule.
struct MailFetchBackoffSchedule {
    /// Consecutive recorded failures. Resets on success.
    private(set) var consecutiveFailures = 0
    /// Extra delay currently added on top of the base interval.
    private(set) var extraDelay: TimeInterval = 0
    /// When the most recent scheduled attempt started.
    private var lastAttemptAt: Date?

    /// The effective cadence for the next attempt: the base interval
    /// plus any failure-grown delay.
    func effectiveInterval(base: TimeInterval) -> TimeInterval {
        base + extraDelay
    }

    /// Whether a scheduled attempt may run at `now`. The gate only
    /// engages once consecutive failures have grown `extraDelay`; at the
    /// base cadence every tick runs so a slightly-early tick is never
    /// dropped. Once grown, attempts wait for `effectiveInterval(base:)`
    /// to elapse since the last one.
    func permitsAttempt(at now: Date, base: TimeInterval) -> Bool {
        guard extraDelay > 0, let lastAttemptAt else { return true }
        return now.timeIntervalSince(lastAttemptAt) >= effectiveInterval(base: base)
    }

    /// Records that a scheduled attempt started at `now`.
    mutating func recordAttempt(at now: Date) {
        lastAttemptAt = now
    }

    /// Records an attempt's outcome. The first consecutive failure keeps
    /// the base interval; each further failure doubles the added delay
    /// via `MailFetchBackoff`. Success resets the schedule.
    mutating func recordOutcome(succeeded: Bool) {
        if succeeded {
            consecutiveFailures = 0
            extraDelay = 0
        } else {
            consecutiveFailures += 1
            if consecutiveFailures > 1 {
                extraDelay = extraDelay == 0
                    ? MailFetchBackoff.initial
                    : MailFetchBackoff.next(previous: extraDelay)
            }
        }
    }
}
