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

/// User-visible import/sync phase while older mail or indexing continues.
enum ImportProgressPhase: String, Equatable, Sendable, CaseIterable {
    case connecting
    case backfillContinuing
    case indexCatchingUp
    case recoverableFailure
}

enum ImportProgressBannerStyle: Equatable, Sendable {
    case info
    case warning
    case error
}

/// Non-blocking mailbox import/sync banner content derived from backend health.
struct ImportProgressBannerPresentation: Equatable, Sendable {
    let phase: ImportProgressPhase
    let title: String
    let message: String?
    let style: ImportProgressBannerStyle
    let showsDeterminateProgress: Bool
    let progressCompleted: Int?
    let progressTotal: Int?
    let progressFraction: Double?
    let showsRetryAction: Bool
    let accessibilityLabel: String
}

/// Maps `AccountSyncHealth` and folder-level sync ticks into mailbox chrome copy.
enum ImportProgressPresentation {
    static func resolve(
        health: AccountSyncHealth?,
        folderSyncProgress: MailSyncProgress?
    ) -> ImportProgressBannerPresentation? {
        guard let health else { return nil }

        if health.state == .authenticationRequired {
            return ImportProgressBannerPresentation(
                phase: .recoverableFailure,
                title: "Sign-in required",
                message: health.lastErrorDescription ?? "Reconnect this account to keep syncing mail.",
                style: .warning,
                showsDeterminateProgress: false,
                progressCompleted: nil,
                progressTotal: nil,
                progressFraction: nil,
                showsRetryAction: false,
                accessibilityLabel: "Sign-in required to continue syncing mail."
            )
        }

        if health.canRetryWithoutUserAction {
            if isCancellationNoise(health.lastErrorDescription) {
                // Superseded refresh/task cancel — not actionable sync failure.
            } else {
                return recoverableFailurePresentation(for: health)
            }
        }

        if let folderSyncProgress, folderSyncProgress.total > 0 {
            return backfillPresentation(
                health: health,
                completed: folderSyncProgress.completed,
                total: folderSyncProgress.total
            )
        }

        if isIndexing(health) {
            return indexCatchingUpPresentation(for: health)
        }

        if health.state == .offline, health.lastSuccessfulSyncAt == nil {
            return ImportProgressBannerPresentation(
                phase: .connecting,
                title: "Connecting",
                message: "Setting up your mailbox. Cached mail will appear as soon as the first page is ready.",
                style: .info,
                showsDeterminateProgress: false,
                progressCompleted: nil,
                progressTotal: nil,
                progressFraction: nil,
                showsRetryAction: false,
                accessibilityLabel: "Connecting to your mail account."
            )
        }

        if hasReadableCache(health), isBackgroundImportContinuing(health) {
            // Inbox is already usable — don't park a permanent "you can read
            // mail" tip over the mailbox chrome. Determinate download/index
            // banners and failures still surface via the branches above.
            return nil
        }

        if health.state == .healthy, case .ready = health.indexStatus {
            return nil
        }

        return nil
    }

    static func shouldPollFrequently(health: AccountSyncHealth?) -> Bool {
        guard let health else { return false }
        if health.canRetryWithoutUserAction { return true }
        if health.state == .authenticationRequired { return true }
        if isIndexing(health) { return true }
        if isBackgroundImportContinuing(health) { return true }
        if health.state == .offline, health.lastSuccessfulSyncAt == nil { return true }
        return false
    }

    /// Returns the next health poll delay, or `nil` when the account is idle
    /// and fully healthy. A healthy mailbox has no banner transition to watch,
    /// so keeping a 2-second timer alive only burns main-actor work.
    static func pollingIntervalNanoseconds(health: AccountSyncHealth?) -> UInt64? {
        guard let health else { return nil }
        if health.state == .healthy,
           !health.canRetryWithoutUserAction,
           health.lastErrorDescription == nil,
           case .ready = health.indexStatus {
            return nil
        }
        return shouldPollFrequently(health: health)
            ? 500_000_000
            : 10_000_000_000
    }

    private static func recoverableFailurePresentation(
        for health: AccountSyncHealth
    ) -> ImportProgressBannerPresentation {
        let title: String
        switch health.state {
        case .offline:
            title = "Sync paused"
        case .providerError:
            title = "Sync interrupted"
        case .degraded:
            title = "Sync needs attention"
        default:
            title = "Sync interrupted"
        }
        let message = health.lastErrorDescription
            ?? "Cached mail stays available. Retry when you're back online."
        return ImportProgressBannerPresentation(
            phase: .recoverableFailure,
            title: title,
            message: message,
            style: .warning,
            showsDeterminateProgress: false,
            progressCompleted: nil,
            progressTotal: nil,
            progressFraction: nil,
            showsRetryAction: true,
            accessibilityLabel: "\(title). \(message)"
        )
    }

    private static func backfillPresentation(
        health: AccountSyncHealth,
        completed: Int,
        total: Int
    ) -> ImportProgressBannerPresentation {
        let clampedTotal = max(total, 1)
        let message = hasReadableCache(health)
            ? "You can read available messages while Brev downloads the rest."
            : "Downloading folders into local storage."
        return ImportProgressBannerPresentation(
            phase: .backfillContinuing,
            title: "Downloading mail",
            message: message,
            style: .info,
            showsDeterminateProgress: true,
            progressCompleted: completed,
            progressTotal: total,
            progressFraction: Double(completed) / Double(clampedTotal),
            showsRetryAction: false,
            accessibilityLabel: "Downloading mail. \(completed) of \(total) folders complete."
        )
    }

    private static func indexCatchingUpPresentation(
        for health: AccountSyncHealth
    ) -> ImportProgressBannerPresentation {
        let fraction = indexProgressFraction(for: health)
        let detail = indexProgressDetail(for: health)
        let message = hasReadableCache(health)
            ? "You can read available messages while Brev finishes indexing."
            : detail
        return ImportProgressBannerPresentation(
            phase: .indexCatchingUp,
            title: "Indexing mail",
            message: message,
            style: .info,
            showsDeterminateProgress: fraction != nil,
            progressCompleted: health.searchIndexProgress?.completedFolderCount,
            progressTotal: health.searchIndexProgress?.totalFolderCount,
            progressFraction: fraction,
            showsRetryAction: false,
            accessibilityLabel: "Indexing mail. \(detail)"
        )
    }

    private static func hasReadableCache(_ health: AccountSyncHealth) -> Bool {
        if health.lastSuccessfulSyncAt != nil { return true }
        if let metrics = health.localSearchIndexMetrics, metrics.indexedHeaderCount > 0 {
            return true
        }
        if case .ready = health.indexStatus { return true }
        if case .rebuilding = health.indexStatus { return true }
        return health.cacheSizeBytes > 0
    }

    /// Task cancellation surfaces as `Swift.CancellationError` localized text; it is not a sync outage.
    private static func isCancellationNoise(_ description: String?) -> Bool {
        guard let description else { return false }
        return description.lowercased().contains("cancellationerror")
    }

    private static func isIndexing(_ health: AccountSyncHealth) -> Bool {
        if health.state == .indexing { return true }
        if case .rebuilding = health.indexStatus { return true }
        return false
    }

    private static func isBackgroundImportContinuing(_ health: AccountSyncHealth) -> Bool {
        if isIndexing(health) { return true }
        if let snapshot = health.backgroundRefreshSnapshot, snapshot.deferredFolderCount > 0 {
            return true
        }
        if case .notBuilt = health.indexStatus, health.lastSuccessfulSyncAt != nil {
            return true
        }
        return false
    }

    private static func indexProgressFraction(for health: AccountSyncHealth) -> Double? {
        if let progress = health.searchIndexProgress, progress.totalFolderCount > 0 {
            return Double(progress.completedFolderCount) / Double(progress.totalFolderCount)
        }
        if case .rebuilding(let progress) = health.indexStatus, let progress {
            return min(max(progress, 0), 1)
        }
        return nil
    }

    private static func indexProgressDetail(for health: AccountSyncHealth) -> String {
        if let progress = health.searchIndexProgress, progress.totalFolderCount > 0 {
            return "\(progress.completedFolderCount) of \(progress.totalFolderCount) folders indexed."
        }
        if case .rebuilding(let progress) = health.indexStatus, let progress {
            let percent = Int((min(max(progress, 0), 1) * 100).rounded())
            return "Indexing is \(percent) percent complete."
        }
        return "Building the local search index."
    }
}
