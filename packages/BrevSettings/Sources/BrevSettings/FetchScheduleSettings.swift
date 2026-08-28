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

/// User preferences for automatic mail-fetch scheduling.
///
/// Defaults to manual-only mode so new installs do not poll unexpectedly.
public struct FetchScheduleSettings: Equatable, Sendable {
    /// `UserDefaults` key constants shared between `BrevSettings` and
    /// `BrevMail` so both packages write and read from the same store.
    public enum Key {
        public static let interval = "fetch.interval"
    }

    /// How often Brev polls the backend for new messages.
    public var interval: FetchInterval

    /// Sensible out-of-the-box default: manual-only mode, so a new
    /// install never polls until the user asks for it.
    public static let defaults = FetchScheduleSettings(interval: .manual)

    public init(interval: FetchInterval) {
        self.interval = interval
    }

    /// Loads settings from the given `UserDefaults`, falling back to
    /// `defaults` for any missing or invalid value.
    public static func load(from defaults: UserDefaults = .standard) -> FetchScheduleSettings {
        FetchScheduleSettings(
            interval: enumValue(
                FetchInterval.self,
                for: Key.interval,
                default: Self.defaults.interval,
                defaults: defaults
            )
        )
    }

    /// Persists the current settings to `defaults`.
    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(interval.rawValue, forKey: Key.interval)
    }

    private static func enumValue<T>(
        _ type: T.Type,
        for key: String,
        default defaultValue: T,
        defaults: UserDefaults
    ) -> T where T: RawRepresentable, T.RawValue == String {
        guard let raw = defaults.string(forKey: key), let value = T(rawValue: raw) else {
            return defaultValue
        }
        return value
    }
}

/// Polling cadence advertised to the user in Settings → Accounts.
public enum FetchInterval: String, CaseIterable, Sendable, Identifiable {
    case manual
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour

    public var id: String { rawValue }

    /// Display title for the Settings picker.
    public var title: String {
        switch self {
        case .manual: return String(localized: "Manually", bundle: .module)
        case .fiveMinutes: return String(localized: "Every 5 minutes", bundle: .module)
        case .fifteenMinutes: return String(localized: "Every 15 minutes", bundle: .module)
        case .thirtyMinutes: return String(localized: "Every 30 minutes", bundle: .module)
        case .oneHour: return String(localized: "Every hour", bundle: .module)
        }
    }

    /// One-line description shown beneath the picker selection.
    public var subtitle: String {
        switch self {
        case .manual: return String(localized: "Only check when you pull to refresh.", bundle: .module)
        case .fiveMinutes: return String(localized: "Frequent checks. Higher battery usage.", bundle: .module)
        case .fifteenMinutes: return String(localized: "Balanced frequency and battery usage.", bundle: .module)
        case .thirtyMinutes: return String(localized: "Moderate frequency. Lower battery usage.", bundle: .module)
        case .oneHour: return String(localized: "Infrequent checks. Minimal battery impact.", bundle: .module)
        }
    }

    /// Wall-clock polling interval in seconds.
    /// Returns `nil` for `.manual` (no automatic polling).
    public var intervalSeconds: TimeInterval? {
        switch self {
        case .manual: return nil
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .thirtyMinutes: return 1800
        case .oneHour: return 3600
        }
    }
}
