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

/// Device-local consent only, never provider eligibility or permission to read mail.
/// Deliberately excluded from settings backups and preference sync (ADR-0088).
public struct SignInCodeSettings: Equatable, Sendable {
    /// Independent opt-ins bound to a stable account ID on this device.
    public struct AccountOverride: Codable, Equatable, Sendable, Identifiable {
        /// The stable account ID, not a display name or list position.
        public let accountID: String
        /// Whether the user consented to sign-in code presentation.
        public let codesEnabled: Bool
        /// Whether the user consented to sign-in link presentation.
        public let linksEnabled: Bool
        /// Stable identity for this account's consent record.
        public var id: String { accountID }
    }

    enum Key {
        static let accountOverrides = "signInCode.accountOverrides.v1"
    }

    /// No account inherits consent from a global enable switch.
    public static let defaults = SignInCodeSettings()
    /// Initial post-use behavior never modifies the source message.
    public static let leavesMessageUnchanged = true
    /// Fixed initial panel timeout in seconds; no panel is wired yet.
    public static let panelTimeout: TimeInterval = 60
    /// Explicit account records only; missing accounts have both opt-ins off.
    public private(set) var accountOverrides: [String: AccountOverride] = [:]

    /// Creates settings with no account consent.
    public init() {}

    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var decodedCache: [Data: SignInCodeSettings] = [:]
    private static let maxCacheEntries = 16
    #if DEBUG
    private nonisolated(unsafe) static var jsonDecodeCountForTestingStorage = 0
    static var jsonDecodeCountForTesting: Int {
        cacheLock.withLock { jsonDecodeCountForTestingStorage }
    }
    #endif

    /// Loads from the supplied local defaults, rejecting malformed records as a whole.
    public static func load(from defaults: UserDefaults) -> SignInCodeSettings {
        guard let data = defaults.data(forKey: Key.accountOverrides) else {
            return Self.defaults
        }
        if let cached = cacheLock.withLock({ decodedCache[data] }) {
            return cached
        }
        #if DEBUG
        cacheLock.withLock { jsonDecodeCountForTestingStorage += 1 }
        #endif
        let decoded: SignInCodeSettings
        if let records = try? JSONDecoder().decode([String: AccountOverride].self, from: data),
           records.allSatisfy({ key, record in
               validAccountID(key) && key == record.accountID
           }) {
            var settings = Self.defaults
            settings.accountOverrides = records
            decoded = settings
        } else {
            decoded = Self.defaults
        }
        cacheLock.withLock {
            if decodedCache.count >= maxCacheEntries {
                decodedCache.removeAll(keepingCapacity: true)
            }
            decodedCache[data] = decoded
        }
        return decoded
    }

    /// Persists only consent flags and account IDs to the supplied local defaults.
    public func save(to defaults: UserDefaults) {
        if !accountOverrides.isEmpty,
           let data = try? JSONEncoder().encode(accountOverrides) {
            defaults.set(data, forKey: Key.accountOverrides)
            Self.cacheLock.withLock {
                if Self.decodedCache.count >= Self.maxCacheEntries {
                    Self.decodedCache.removeAll(keepingCapacity: true)
                }
                Self.decodedCache[data] = self
            }
        } else {
            defaults.removeObject(forKey: Key.accountOverrides)
        }
        if defaults === UserDefaults.standard {
            NotificationCenter.default.post(name: .brevNotificationSettingsDidChange, object: nil)
        }
    }

    /// Returns explicit account consent, or both opt-ins off when absent.
    public func accountOverride(for accountID: String) -> AccountOverride {
        accountOverrides[accountID] ?? AccountOverride(
            accountID: accountID, codesEnabled: false, linksEnabled: false
        )
    }

    /// Changes independent opt-ins for a stable account ID; call save to persist.
    public mutating func setAccountOverride(accountID: String, codesEnabled: Bool, linksEnabled: Bool) {
        guard Self.validAccountID(accountID) else { return }
        accountOverrides[accountID] = AccountOverride(
            accountID: accountID, codesEnabled: codesEnabled, linksEnabled: linksEnabled
        )
    }

    /// Removes the account record and persists the remaining consent to local defaults.
    /// No account lifecycle caller is connected yet.
    public mutating func removeAccountOverride(accountID: String, from defaults: UserDefaults) {
        accountOverrides.removeValue(forKey: accountID)
        save(to: defaults)
    }

    private static func validAccountID(_ accountID: String) -> Bool {
        !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
