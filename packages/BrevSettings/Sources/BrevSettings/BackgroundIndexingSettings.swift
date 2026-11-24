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

import Foundation
import Observation

public extension Notification.Name {
    /// Posted when background recent-mail and attachment indexing settings change.
    static let brevBackgroundIndexingSettingsDidChange = Notification.Name(
        "eu.brevmail.settings.backgroundIndexing.changed"
    )
}

/// Lookback window for opt-in background recent-mail and attachment indexing.
public enum BackgroundIndexingWindow: Int, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    /// Index messages received in the last 30 days.
    case days30 = 30
    /// Index messages received in the last 90 days (default when enabled).
    case days90 = 90
    /// Index messages received in the last 365 days.
    case days365 = 365

    public var id: Int { rawValue }

    /// Lookback length in whole days.
    public var days: Int { rawValue }

    /// Localized picker title for this indexing window.
    public var displayName: String {
        switch self {
        case .days30:
            String(localized: "Last 30 days", bundle: .module)
        case .days90:
            String(localized: "Last 90 days", bundle: .module)
        case .days365:
            String(localized: "Last 365 days", bundle: .module)
        }
    }
}

/// Device-local settings for opt-in background recent-mail and attachment indexing.
///
/// Strictly off by default (`isEnabled == false`) to preserve Brev's
/// zero-unexpected-network-by-default posture. Deliberately excluded from
/// `PreferenceSyncAllowlist` so storage and bandwidth choices remain device-local.
public struct BackgroundIndexingSettings: Equatable, Sendable, Codable {
    /// Default per-attachment download cap (10 MiB) for background text indexing.
    public static let defaultMaxAttachmentBytes = 10 * 1024 * 1024

    /// Stable `UserDefaults` storage keys.
    public enum Key {
        public static let isEnabled = "mail.backgroundIndexing.enabled"
        public static let windowDays = "mail.backgroundIndexing.windowDays"
        public static let indexAttachments = "mail.backgroundIndexing.indexAttachments"
        public static let requireUnmeteredNetworkAndPower = "mail.backgroundIndexing.requireUnmeteredNetworkAndPower"
    }

    /// Master opt-in switch. Strictly off by default.
    public var isEnabled: Bool
    /// Recent lookback window indexed when `isEnabled` is `true`.
    public var windowDays: BackgroundIndexingWindow
    /// Whether eligible downloadable attachments under the size cap are text-indexed.
    public var indexAttachments: Bool
    /// Whether indexing pauses automatically on metered/constrained networks or Low Power Mode.
    public var requireUnmeteredNetworkAndPower: Bool

    /// Default configuration: strictly disabled, with conservative sub-options ready when opted in.
    public static let defaults = BackgroundIndexingSettings(
        isEnabled: false,
        windowDays: .days90,
        indexAttachments: true,
        requireUnmeteredNetworkAndPower: true
    )

    /// Creates background indexing settings.
    public init(
        isEnabled: Bool = false,
        windowDays: BackgroundIndexingWindow = .days90,
        indexAttachments: Bool = true,
        requireUnmeteredNetworkAndPower: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.windowDays = windowDays
        self.indexAttachments = indexAttachments
        self.requireUnmeteredNetworkAndPower = requireUnmeteredNetworkAndPower
    }

    /// Loads persisted background indexing settings from `defaults`.
    public static func load(from defaults: UserDefaults = .standard) -> BackgroundIndexingSettings {
        let isEnabled = defaults.bool(forKey: Key.isEnabled)
        let windowRaw = defaults.object(forKey: Key.windowDays) as? Int
        let windowDays = windowRaw.flatMap(BackgroundIndexingWindow.init(rawValue:)) ?? Self.defaults.windowDays
        let indexAttachments = defaults.object(forKey: Key.indexAttachments) as? Bool
            ?? Self.defaults.indexAttachments
        let requireUnmetered = defaults.object(forKey: Key.requireUnmeteredNetworkAndPower) as? Bool
            ?? Self.defaults.requireUnmeteredNetworkAndPower
        return BackgroundIndexingSettings(
            isEnabled: isEnabled,
            windowDays: windowDays,
            indexAttachments: indexAttachments,
            requireUnmeteredNetworkAndPower: requireUnmetered
        )
    }

    /// Persists background indexing settings to `defaults`.
    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: Key.isEnabled)
        defaults.set(windowDays.rawValue, forKey: Key.windowDays)
        defaults.set(indexAttachments, forKey: Key.indexAttachments)
        defaults.set(requireUnmeteredNetworkAndPower, forKey: Key.requireUnmeteredNetworkAndPower)
        if defaults === UserDefaults.standard {
            NotificationCenter.default.post(name: .brevBackgroundIndexingSettingsDidChange, object: nil)
        }
    }
}

/// Reason why background recent-mail indexing is currently paused.
public enum BackgroundIndexingPauseReason: String, Equatable, Sendable, Codable {
    /// Paused manually by the user from Settings.
    case userPaused
    /// Device currently has no network reachability.
    case offline
    /// Active network is cellular, expensive, or constrained (Low Data Mode).
    case meteredNetwork
    /// Low Power Mode / battery saver is active.
    case lowPowerMode
}

/// Runtime lifecycle state of the background recent-mail indexer.
public enum BackgroundIndexingState: Equatable, Sendable {
    /// Waiting for work or turned off.
    case idle
    /// Actively fetching and indexing recent messages in a throttled pass.
    case running(completed: Int, total: Int)
    /// Paused due to user request, network metering, offline state, or Low Power Mode.
    case paused(BackgroundIndexingPauseReason)
    /// Most recent pass finished indexing all eligible messages in the window.
    case completed
    /// Last pass stopped with an error summary.
    case failed(String)
}

/// Immutable status snapshot surfaced by Settings for background recent-mail indexing.
public struct BackgroundIndexingStatus: Equatable, Sendable {
    public var state: BackgroundIndexingState
    public var indexedMessagesCount: Int
    public var indexedAttachmentsCount: Int
    public var pendingCount: Int
    public var lastIndexedAt: Date?

    /// Default idle status before any pass has run.
    public static let idle = BackgroundIndexingStatus(
        state: .idle,
        indexedMessagesCount: 0,
        indexedAttachmentsCount: 0,
        pendingCount: 0,
        lastIndexedAt: nil
    )

    /// Creates a status snapshot.
    public init(
        state: BackgroundIndexingState = .idle,
        indexedMessagesCount: Int = 0,
        indexedAttachmentsCount: Int = 0,
        pendingCount: Int = 0,
        lastIndexedAt: Date? = nil
    ) {
        self.state = state
        self.indexedMessagesCount = indexedMessagesCount
        self.indexedAttachmentsCount = indexedAttachmentsCount
        self.pendingCount = pendingCount
        self.lastIndexedAt = lastIndexedAt
    }
}

/// Observable bridge between `BackgroundRecentIndexingCoordinator` (`BrevMail`)
/// and the `BrevSettings` UI without coupling the settings package to mail sessions.
@MainActor
@Observable
public final class BackgroundIndexingStatusModel {
    /// Current runtime indexing status.
    public var status: BackgroundIndexingStatus
    /// Triggers an immediate indexing pass when enabled.
    public var onIndexNow: (@MainActor () async -> Void)?
    /// Pauses background indexing until resumed by the user.
    public var onPause: (@MainActor () -> Void)?
    /// Resumes a user-paused indexer.
    public var onResume: (@MainActor () -> Void)?
    /// Clears persisted per-account indexing cursors and restarts if enabled.
    public var onResetIndexState: (@MainActor () async -> Void)?

    /// Creates a status model for Settings views or deterministic previews/snapshots.
    public init(
        status: BackgroundIndexingStatus = .idle,
        onIndexNow: (@MainActor () async -> Void)? = nil,
        onPause: (@MainActor () -> Void)? = nil,
        onResume: (@MainActor () -> Void)? = nil,
        onResetIndexState: (@MainActor () async -> Void)? = nil
    ) {
        self.status = status
        self.onIndexNow = onIndexNow
        self.onPause = onPause
        self.onResume = onResume
        self.onResetIndexState = onResetIndexState
    }
}

/// Persisted per-account indexing ledger so background passes do not re-fetch
/// messages or attachments that were already indexed on this device.
public struct BackgroundIndexingAccountProgress: Codable, Equatable, Sendable {
    public var indexedBodyMessageIDs: Set<String>
    public var indexedAttachmentMessageIDs: Set<String>
    public var lastIndexedAt: Date?

    /// Empty progress state for an account that has not been indexed yet.
    public static let empty = BackgroundIndexingAccountProgress(
        indexedBodyMessageIDs: [],
        indexedAttachmentMessageIDs: [],
        lastIndexedAt: nil
    )

    /// Creates a persisted per-account progress record.
    public init(
        indexedBodyMessageIDs: Set<String> = [],
        indexedAttachmentMessageIDs: Set<String> = [],
        lastIndexedAt: Date? = nil
    ) {
        self.indexedBodyMessageIDs = indexedBodyMessageIDs
        self.indexedAttachmentMessageIDs = indexedAttachmentMessageIDs
        self.lastIndexedAt = lastIndexedAt
    }
}

/// Device-local `UserDefaults` persistence for per-account background indexing cursors.
///
/// Excluded from settings backups and iCloud sync because local cache contents
/// are strictly device-specific.
public struct BackgroundIndexingProgressStore: @unchecked Sendable {
    private static let keyPrefix = "mail.backgroundIndexing.progress.v1."
    private static let trackedAccountsKey = "mail.backgroundIndexing.trackedAccounts.v1"

    private let defaults: UserDefaults

    /// Shared store backed by `UserDefaults.standard`.
    public static let shared = BackgroundIndexingProgressStore(defaults: .standard)

    /// Creates a progress store backed by `defaults`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Loads persisted progress for `accountID`, or `.empty` when none is stored.
    public func load(accountID: String) -> BackgroundIndexingAccountProgress {
        guard let data = defaults.data(forKey: Self.key(for: accountID)),
              let decoded = try? JSONDecoder().decode(BackgroundIndexingAccountProgress.self, from: data)
        else {
            return .empty
        }
        return decoded
    }

    /// Persists progress for `accountID`.
    public func save(_ progress: BackgroundIndexingAccountProgress, accountID: String) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        defaults.set(data, forKey: Self.key(for: accountID))
        var tracked = Set(defaults.stringArray(forKey: Self.trackedAccountsKey) ?? [])
        if tracked.insert(accountID).inserted {
            defaults.set(Array(tracked).sorted(), forKey: Self.trackedAccountsKey)
        }
    }

    /// Clears persisted progress for one account (used on account removal or reset).
    public func clear(accountID: String) {
        defaults.removeObject(forKey: Self.key(for: accountID))
        var tracked = Set(defaults.stringArray(forKey: Self.trackedAccountsKey) ?? [])
        if tracked.remove(accountID) != nil {
            defaults.set(Array(tracked).sorted(), forKey: Self.trackedAccountsKey)
        }
    }

    /// Clears persisted progress across all tracked accounts and any supplied `accountIDs`.
    public func clearAll(accountIDs: [String] = []) {
        let tracked = Set(defaults.stringArray(forKey: Self.trackedAccountsKey) ?? []).union(accountIDs)
        for accountID in tracked {
            defaults.removeObject(forKey: Self.key(for: accountID))
        }
        defaults.removeObject(forKey: Self.trackedAccountsKey)
    }

    /// Returns the most recent indexing timestamp recorded across all tracked accounts.
    public func latestIndexedAt(accountIDs: [String] = []) -> Date? {
        let tracked = Set(defaults.stringArray(forKey: Self.trackedAccountsKey) ?? []).union(accountIDs)
        return tracked.compactMap { load(accountID: $0).lastIndexedAt }.max()
    }

    private static func key(for accountID: String) -> String {
        keyPrefix + accountID
    }
}

/// Pure formatting and control-availability policy for the Background indexing Settings UI.
enum BackgroundIndexingStatusPresentation {
    /// Human-readable status line for the Settings info callout.
    static func summary(
        settings: BackgroundIndexingSettings,
        status: BackgroundIndexingStatus,
        now: Date = Date()
    ) -> String {
        guard settings.isEnabled else {
            return String(
                localized: "Off. Brev does not download message bodies or attachments in the background.",
                bundle: .module
            )
        }
        switch status.state {
        case .idle:
            if let last = status.lastIndexedAt {
                let formatted = formatTimestamp(last, relativeTo: now)
                return String(
                    localized: "Idle. Last indexed \(formatted).",
                    bundle: .module
                )
            }
            return String(
                localized: "Idle. Ready to index recent mail from the last \(settings.windowDays.days) days.",
                bundle: .module
            )
        case .running(let completed, let total):
            if total > 0 {
                return String(
                    localized: "Indexing \(completed) of \(total) recent messages…",
                    bundle: .module
                )
            }
            return String(localized: "Indexing recent messages…", bundle: .module)
        case .paused(let reason):
            switch reason {
            case .userPaused:
                return String(localized: "Paused. Resume to continue background indexing.", bundle: .module)
            case .offline:
                return String(localized: "Paused while offline. Resumes automatically when reconnected.", bundle: .module)
            case .meteredNetwork:
                return String(
                    localized: "Paused on cellular or Low Data Mode. Resumes automatically on Wi-Fi.",
                    bundle: .module
                )
            case .lowPowerMode:
                return String(
                    localized: "Paused in Low Power Mode. Resumes automatically when battery saver turns off.",
                    bundle: .module
                )
            }
        case .completed:
            let countPart = String(
                localized: "Indexed \(status.indexedMessagesCount) messages and \(status.indexedAttachmentsCount) attachments.",
                bundle: .module
            )
            if let last = status.lastIndexedAt {
                let formatted = formatTimestamp(last, relativeTo: now)
                return String(localized: "\(countPart) Last indexed \(formatted).", bundle: .module)
            }
            return countPart
        case .failed(let message):
            return String(localized: "Background indexing stopped: \(message)", bundle: .module)
        }
    }

    /// Semantic tone for the status callout.
    static func tone(
        settings: BackgroundIndexingSettings,
        status: BackgroundIndexingStatus
    ) -> SettingsCalloutTone {
        guard settings.isEnabled else { return .info }
        switch status.state {
        case .completed:
            return .success
        case .paused, .failed:
            return .warning
        case .idle, .running:
            return .info
        }
    }

    /// SF Symbol name reflecting the current state.
    static func symbolName(
        settings: BackgroundIndexingSettings,
        status: BackgroundIndexingStatus
    ) -> String {
        guard settings.isEnabled else { return "pause.circle" }
        switch status.state {
        case .idle:
            return "clock"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .paused(let reason):
            switch reason {
            case .lowPowerMode: return "battery.25percent"
            case .meteredNetwork, .offline: return "wifi.slash"
            case .userPaused: return "pause.circle"
            }
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    /// Whether the status is currently running a pass.
    static func isRunning(_ state: BackgroundIndexingState) -> Bool {
        if case .running = state { return true }
        return false
    }

    /// Whether the status is manually paused by the user.
    static func isUserPaused(_ state: BackgroundIndexingState) -> Bool {
        state == .paused(.userPaused)
    }

    private static func formatTimestamp(_ date: Date, relativeTo now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
