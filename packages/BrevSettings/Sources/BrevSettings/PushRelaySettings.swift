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

public extension Notification.Name {
    /// Posted when device-local closed-app push relay settings change (#11).
    static let brevPushRelaySettingsDidChange = Notification.Name(
        "eu.brevmail.settings.pushRelay.changed"
    )
}

/// Device-local opt-in configuration for self-hosted closed-app push delivery (#11).
///
/// Off by default (`isEnabled == false`) and strictly device-local:
/// deliberately excluded from `.brevbackup` exports (`SettingsBackupCodec`) and
/// iCloud Key-Value preference sync (`PreferenceSyncAllowlist`) so push tokens,
/// relay endpoints, and device client IDs never leak across devices.
///
/// Optional bearer secrets and RFC 8291 P-256 private keys live exclusively in
/// `PushRelaySecretStore` (Keychain) and are never stored in `UserDefaults`.
public struct PushRelaySettings: Equatable, Sendable {
    /// Storage keys used in `UserDefaults`. Intentionally absent from
    /// `PreferenceSyncAllowlist.keys`.
    public enum Key {
        public static let isEnabled = "notifications.pushRelay.isEnabled.v1"
        public static let mode = "notifications.pushRelay.mode.v1"
        public static let endpointURLString = "notifications.pushRelay.endpointURL.v1"
        public static let enabledAccountIDs = "notifications.pushRelay.enabledAccountIDs.v1"
        public static let deviceClientID = "notifications.pushRelay.deviceClientID.v1"
        public static let subscriptionID = "notifications.pushRelay.subscriptionID.v1"
        public static let lastRegisteredAt = "notifications.pushRelay.lastRegisteredAt.v1"
        public static let lastRegistrationError = "notifications.pushRelay.lastRegistrationError.v1"
    }

    /// Master opt-in switch (off by default).
    public var isEnabled: Bool

    /// Selected push relay transport mode.
    public var mode: PushRelayMode

    /// User-configured HTTPS push relay or JMAP endpoint URL string.
    public var endpointURLString: String

    /// Explicit per-account opt-ins keyed by stable `BrevAccount.ID`.
    public var enabledAccountIDs: Set<String>

    /// Opaque per-device client identifier generated locally on this device.
    public var deviceClientID: String

    /// Subscription identifier returned by the relay on the last successful registration.
    public var subscriptionID: String?

    /// Timestamp of the last successful relay registration, if any.
    public var lastRegisteredAt: Date?

    /// Last registration/unregistration error message shown in Settings, if any.
    public var lastRegistrationError: String?

    /// Default configuration: strictly off, zero accounts opted in, empty endpoint.
    public static let defaults = PushRelaySettings(
        isEnabled: false,
        mode: .userHostedRelay,
        endpointURLString: "",
        enabledAccountIDs: [],
        deviceClientID: "",
        subscriptionID: nil,
        lastRegisteredAt: nil,
        lastRegistrationError: nil
    )

    /// Creates device-local closed-app push relay settings.
    public init(
        isEnabled: Bool = false,
        mode: PushRelayMode = .userHostedRelay,
        endpointURLString: String = "",
        enabledAccountIDs: Set<String> = [],
        deviceClientID: String = "",
        subscriptionID: String? = nil,
        lastRegisteredAt: Date? = nil,
        lastRegistrationError: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.endpointURLString = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        self.enabledAccountIDs = Set(
            enabledAccountIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        self.deviceClientID = deviceClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubID = subscriptionID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.subscriptionID = trimmedSubID?.isEmpty == false ? trimmedSubID : nil
        self.lastRegisteredAt = lastRegisteredAt
        let trimmedError = lastRegistrationError?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastRegistrationError = trimmedError?.isEmpty == false ? trimmedError : nil
    }

    /// Returns whether push wakes are enabled both globally and for `accountID`.
    public func isAccountEnabled(_ accountID: String) -> Bool {
        isEnabled && mode != .disabled && enabledAccountIDs.contains(accountID)
    }

    /// Toggles per-account opt-in without altering the master switch.
    public mutating func setAccount(_ accountID: String, enabled: Bool) {
        let trimmed = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if enabled {
            enabledAccountIDs.insert(trimmed)
        } else {
            enabledAccountIDs.remove(trimmed)
        }
    }

    /// Validates `endpointURLString` using strict HTTPS rules.
    public func validatedEndpointURL() throws -> URL {
        try PushRelayEndpointValidator.validate(endpointURLString)
    }

    /// Returns a non-empty opaque per-device client ID, generating one if needed.
    public mutating func ensureDeviceClientID() -> String {
        if deviceClientID.isEmpty {
            deviceClientID = "brev-dev-\(UUID().uuidString.lowercased())"
        }
        return deviceClientID
    }

    /// Loads device-local push relay settings from `defaults`.
    public static func load(from defaults: UserDefaults = .standard) -> PushRelaySettings {
        let isEnabled = defaults.bool(forKey: Key.isEnabled)
        let mode: PushRelayMode
        if let rawMode = defaults.string(forKey: Key.mode),
           let parsed = PushRelayMode(rawValue: rawMode) {
            mode = parsed
        } else {
            mode = Self.defaults.mode
        }
        let endpointURLString = defaults.string(forKey: Key.endpointURLString) ?? ""
        let rawIDs = defaults.stringArray(forKey: Key.enabledAccountIDs) ?? []
        let deviceClientID = defaults.string(forKey: Key.deviceClientID) ?? ""
        let subscriptionID = defaults.string(forKey: Key.subscriptionID)
        let lastRegisteredAt: Date? = if defaults.object(forKey: Key.lastRegisteredAt) != nil {
            Date(timeIntervalSince1970: defaults.double(forKey: Key.lastRegisteredAt))
        } else {
            nil
        }
        let lastRegistrationError = defaults.string(forKey: Key.lastRegistrationError)

        return PushRelaySettings(
            isEnabled: isEnabled,
            mode: mode,
            endpointURLString: endpointURLString,
            enabledAccountIDs: Set(rawIDs),
            deviceClientID: deviceClientID,
            subscriptionID: subscriptionID,
            lastRegisteredAt: lastRegisteredAt,
            lastRegistrationError: lastRegistrationError
        )
    }

    /// Persists device-local push relay settings to `defaults`.
    /// Never writes bearer secrets or private encryption keys to `UserDefaults`.
    public func save(to defaults: UserDefaults = .standard) {
        var copy = self
        if copy.isEnabled, copy.deviceClientID.isEmpty {
            _ = copy.ensureDeviceClientID()
        }
        defaults.set(copy.isEnabled, forKey: Key.isEnabled)
        defaults.set(copy.mode.rawValue, forKey: Key.mode)
        defaults.set(copy.endpointURLString, forKey: Key.endpointURLString)
        defaults.set(Array(copy.enabledAccountIDs).sorted(), forKey: Key.enabledAccountIDs)
        if copy.deviceClientID.isEmpty {
            defaults.removeObject(forKey: Key.deviceClientID)
        } else {
            defaults.set(copy.deviceClientID, forKey: Key.deviceClientID)
        }
        if let subscriptionID = copy.subscriptionID {
            defaults.set(subscriptionID, forKey: Key.subscriptionID)
        } else {
            defaults.removeObject(forKey: Key.subscriptionID)
        }
        if let lastRegisteredAt = copy.lastRegisteredAt {
            defaults.set(lastRegisteredAt.timeIntervalSince1970, forKey: Key.lastRegisteredAt)
        } else {
            defaults.removeObject(forKey: Key.lastRegisteredAt)
        }
        if let lastRegistrationError = copy.lastRegistrationError {
            defaults.set(lastRegistrationError, forKey: Key.lastRegistrationError)
        } else {
            defaults.removeObject(forKey: Key.lastRegistrationError)
        }
        if defaults === UserDefaults.standard {
            NotificationCenter.default.post(name: .brevPushRelaySettingsDidChange, object: nil)
        }
    }

    /// Removes a deleted account from the device-local push opt-in set.
    public static func removeAccount(_ accountID: String, from defaults: UserDefaults = .standard) {
        let trimmed = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var settings = load(from: defaults)
        guard settings.enabledAccountIDs.remove(trimmed) != nil else { return }
        settings.save(to: defaults)
    }
}

public extension PushRelayMode {
    /// Localized user-facing title shown in Settings → Notifications.
    var settingsTitle: String {
        switch self {
        case .disabled:
            String(localized: "Disabled", bundle: .module)
        case .userHostedRelay:
            String(localized: "User-hosted HTTPS relay", bundle: .module)
        case .jmapWebPush:
            String(localized: "JMAP WebPush (RFC 8620)", bundle: .module)
        }
    }

    /// Localized explanation for the selected relay mode.
    var settingsSubtitle: String {
        switch self {
        case .disabled:
            String(localized: "Closed-app push wakes are off.", bundle: .module)
        case .userHostedRelay:
            String(
                localized: "Register this device with your own HTTPS push relay to receive opaque wake signals.",
                bundle: .module
            )
        case .jmapWebPush:
            String(
                localized: "Register an RFC 8620 PushSubscription with RFC 8291 P-256 encryption keys on your JMAP server.",
                bundle: .module
            )
        }
    }

    /// Modes selectable while closed-app push is enabled.
    static var configurableModes: [PushRelayMode] {
        [.userHostedRelay, .jmapWebPush]
    }
}
