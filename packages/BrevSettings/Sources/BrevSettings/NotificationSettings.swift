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

public extension Notification.Name {
    static let brevNotificationSettingsDidChange = Notification.Name(
        "eu.brevmail.settings.notifications.changed"
    )
}

public enum NotificationBadgePolicy: String, CaseIterable, Sendable {
    case allUnread
    case inboxUnread
    case selectedSources
    case off

    var title: String {
        switch self {
        case .allUnread: return String(localized: "All unread", bundle: .module)
        case .inboxUnread: return String(localized: "Inbox unread", bundle: .module)
        case .selectedSources: return String(localized: "Selected accounts", bundle: .module)
        case .off: return String(localized: "Off", bundle: .module)
        }
    }

    var subtitle: String {
        switch self {
        case .allUnread:
            return String(localized: "Count unread mail across every visible folder.", bundle: .module)
        case .inboxUnread:
            return String(localized: "Count unread mail in Inbox folders only.", bundle: .module)
        case .selectedSources:
            return String(localized: "Count unread mail only for accounts enabled below.", bundle: .module)
        case .off:
            return String(localized: "Do not show unread badges.", bundle: .module)
        }
    }
}

public struct NotificationSettings: Equatable, Sendable {
    public struct AccountOverride: Codable, Equatable, Sendable, Identifiable {
        public var id: String { accountID }

        public var accountID: String
        public var notificationsEnabled: Bool
        public var badgeEnabled: Bool
        public var soundEnabled: Bool
    }

    public enum Key {
        // Keep the existing storage key so users' notification preference
        // survives the remote-push retirement (ADR-0037).
        static let notificationsEnabled = "notifications.pushEnabled"
        static let badgeEnabled = "notifications.badgeEnabled"
        static let badgePolicy = "notifications.badgePolicy"
        static let soundEnabled = "notifications.soundEnabled"
        static let showPreviews = "notifications.showPreviews"
        static let accountOverrides = "notifications.accountOverrides"
        static let quietHoursEnabled = "notifications.quietHoursEnabled"
        static let quietHoursStart = "notifications.quietHoursStart"
        static let quietHoursEnd = "notifications.quietHoursEnd"
    }

    public var notificationsEnabled: Bool
    public var badgeEnabled: Bool
    public var badgePolicy: NotificationBadgePolicy
    public var soundEnabled: Bool
    public var showPreviews: Bool
    public var accountOverrides: [String: AccountOverride]
    public var quietHoursEnabled: Bool
    public var quietHoursStart: Int
    public var quietHoursEnd: Int

    public static let defaults = NotificationSettings(
        notificationsEnabled: false,
        badgeEnabled: true,
        badgePolicy: .inboxUnread,
        soundEnabled: true,
        showPreviews: true,
        accountOverrides: [:],
        quietHoursEnabled: false,
        quietHoursStart: 22,
        quietHoursEnd: 7
    )

    public var quietHoursStartLabel: String {
        formatHour(quietHoursStart)
    }

    public var quietHoursEndLabel: String {
        formatHour(quietHoursEnd)
    }

    public static func load(from defaults: UserDefaults = .standard) -> NotificationSettings {
        NotificationSettings(
            notificationsEnabled: bool(
                for: Key.notificationsEnabled,
                defaultValue: Self.defaults.notificationsEnabled,
                defaults: defaults
            ),
            badgeEnabled: bool(
                for: Key.badgeEnabled,
                defaultValue: Self.defaults.badgeEnabled,
                defaults: defaults
            ),
            badgePolicy: enumValue(
                NotificationBadgePolicy.self,
                for: Key.badgePolicy,
                defaultValue: Self.defaults.badgePolicy,
                defaults: defaults
            ),
            soundEnabled: bool(
                for: Key.soundEnabled,
                defaultValue: Self.defaults.soundEnabled,
                defaults: defaults
            ),
            showPreviews: bool(
                for: Key.showPreviews,
                defaultValue: Self.defaults.showPreviews,
                defaults: defaults
            ),
            accountOverrides: accountOverrides(from: defaults),
            quietHoursEnabled: bool(
                for: Key.quietHoursEnabled,
                defaultValue: Self.defaults.quietHoursEnabled,
                defaults: defaults
            ),
            quietHoursStart: defaults.object(forKey: Key.quietHoursStart) != nil
                ? defaults.integer(forKey: Key.quietHoursStart) : Self.defaults.quietHoursStart,
            quietHoursEnd: defaults.object(forKey: Key.quietHoursEnd) != nil
                ? defaults.integer(forKey: Key.quietHoursEnd) : Self.defaults.quietHoursEnd
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled)
        defaults.set(badgeEnabled, forKey: Key.badgeEnabled)
        defaults.set(badgePolicy.rawValue, forKey: Key.badgePolicy)
        defaults.set(soundEnabled, forKey: Key.soundEnabled)
        defaults.set(showPreviews, forKey: Key.showPreviews)
        if let data = try? JSONEncoder().encode(accountOverrides) {
            defaults.set(data, forKey: Key.accountOverrides)
        }
        defaults.set(quietHoursEnabled, forKey: Key.quietHoursEnabled)
        defaults.set(quietHoursStart, forKey: Key.quietHoursStart)
        defaults.set(quietHoursEnd, forKey: Key.quietHoursEnd)
    }

    public mutating func setAccountOverride(
        accountID: String,
        notificationsEnabled: Bool,
        badgeEnabled: Bool,
        soundEnabled: Bool
    ) {
        accountOverrides[accountID] = AccountOverride(
            accountID: accountID,
            notificationsEnabled: notificationsEnabled,
            badgeEnabled: badgeEnabled,
            soundEnabled: soundEnabled
        )
    }

    public mutating func removeAccountOverride(accountID: String) {
        accountOverrides.removeValue(forKey: accountID)
    }

    public func accountOverride(for accountID: String) -> AccountOverride {
        accountOverrides[accountID] ?? AccountOverride(
            accountID: accountID,
            notificationsEnabled: true,
            badgeEnabled: true,
            soundEnabled: true
        )
    }

    private static func bool(
        for key: String,
        defaultValue: Bool,
        defaults: UserDefaults
    ) -> Bool {
        guard let value = defaults.object(forKey: key) as? Bool else { return defaultValue }
        return value
    }

    private static func enumValue<Value>(
        _ type: Value.Type,
        for key: String,
        defaultValue: Value,
        defaults: UserDefaults
    ) -> Value where Value: RawRepresentable, Value.RawValue == String {
        guard let rawValue = defaults.string(forKey: key),
              let value = Value(rawValue: rawValue) else {
            return defaultValue
        }
        return value
    }

    private static func accountOverrides(from defaults: UserDefaults) -> [String: AccountOverride] {
        guard let data = defaults.data(forKey: Key.accountOverrides),
              let overrides = try? JSONDecoder().decode([String: AccountOverride].self, from: data) else {
            return Self.defaults.accountOverrides
        }
        return overrides
    }

    private func formatHour(_ hour: Int) -> String {
        Self.hourLabel(hour)
    }

    /// On-the-hour label for a 0...23 value, for the quiet-hours pickers.
    public static func hourLabel(_ hour: Int) -> String {
        let clamped = hour % 24
        if clamped == 0 { return String(localized: "12:00 AM", bundle: .module) }
        if clamped == 12 { return String(localized: "12:00 PM", bundle: .module) }
        if clamped < 12 { return String(localized: "\(clamped):00 AM", bundle: .module) }
        return String(localized: "\(clamped - 12):00 PM", bundle: .module)
    }
}
