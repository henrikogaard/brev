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

/// Snapshot of the currently active registration on a remote relay or JMAP server.
///
/// Stored separately from editable Settings fields so changing the draft URL or
/// transport mode never strands the old subscription or sends its ID to the wrong server.
public struct ActivePushRelayRegistration: Codable, Equatable, Sendable {
    /// Transport mode under which this subscription was registered.
    public let mode: PushRelayMode
    /// Validated HTTPS endpoint URL where this subscription is registered.
    public let endpointURLString: String
    /// Distinct HTTPS WebPush delivery URL for JMAP subscriptions, if applicable.
    public let webPushDeliveryURLString: String?
    /// Server-assigned subscription identifier.
    public let subscriptionID: String
    /// Activation state (`.pendingVerification` for unverified JMAP subscriptions, `.active` once active).
    public var state: PushRelaySubscriptionState
    /// Timestamp when this registration was created/refreshed or verified.
    public var registeredAt: Date

    /// Normalized origin (`https://host[:port]`) used to look up the matching Keychain bearer token.
    public var endpointOrigin: String? {
        try? PushRelayEndpointValidator.originKey(from: endpointURLString)
    }

    /// Creates an active registration record.
    public init(
        mode: PushRelayMode,
        endpointURLString: String,
        webPushDeliveryURLString: String? = nil,
        subscriptionID: String,
        state: PushRelaySubscriptionState = .active,
        registeredAt: Date = Date()
    ) {
        self.mode = mode
        self.endpointURLString = endpointURLString
        self.webPushDeliveryURLString = webPushDeliveryURLString
        self.subscriptionID = subscriptionID
        self.state = state
        self.registeredAt = registeredAt
    }

    /// Returns whether this registration targets the same transport and endpoint URLs.
    public func matchesTarget(
        mode: PushRelayMode,
        endpointURLString: String,
        webPushDeliveryURLString: String?
    ) -> Bool {
        guard self.mode == mode,
              let lhsEndpoint = try? PushRelayEndpointValidator.validate(self.endpointURLString),
              let rhsEndpoint = try? PushRelayEndpointValidator.validate(endpointURLString),
              PushRelayEndpointValidator.representsSameDestination(lhsEndpoint, rhsEndpoint)
        else {
            return false
        }
        if mode == .jmapWebPush {
            guard let lhsDeliveryRaw = self.webPushDeliveryURLString,
                  let rhsDeliveryRaw = webPushDeliveryURLString,
                  let lhsDelivery = try? PushRelayEndpointValidator.validate(lhsDeliveryRaw),
                  let rhsDelivery = try? PushRelayEndpointValidator.validate(rhsDeliveryRaw)
            else {
                return false
            }
            return PushRelayEndpointValidator.representsSameDestination(lhsDelivery, rhsDelivery)
        }
        return true
    }
}

/// Device-local opt-in configuration for self-hosted closed-app push delivery (#11).
///
/// Off by default (`isEnabled == false`) and strictly device-local:
/// deliberately excluded from `.brevbackup` exports (`SettingsBackupCodec`) and
/// iCloud Key-Value preference sync (`PreferenceSyncAllowlist`) so push tokens,
/// relay endpoints, opaque account mappings, and device client IDs never leak across devices.
///
/// Optional origin-scoped bearer secrets and RFC 8291 P-256 private keys live
/// exclusively in `PushRelaySecretStore` (Keychain) and are never stored in `UserDefaults`.
public struct PushRelaySettings: Equatable, Sendable {
    /// Storage keys used in `UserDefaults`. Intentionally absent from
    /// `PreferenceSyncAllowlist.keys`.
    public enum Key {
        public static let isEnabled = "notifications.pushRelay.isEnabled.v1"
        public static let mode = "notifications.pushRelay.mode.v1"
        public static let endpointURLString = "notifications.pushRelay.endpointURL.v1"
        public static let webPushDeliveryURLString = "notifications.pushRelay.webPushDeliveryURL.v1"
        public static let enabledAccountIDs = "notifications.pushRelay.enabledAccountIDs.v1"
        public static let opaqueAccountTokens = "notifications.pushRelay.opaqueAccountTokens.v1"
        public static let deviceClientID = "notifications.pushRelay.deviceClientID.v1"
        public static let activeRegistration = "notifications.pushRelay.activeRegistration.v1"
        public static let subscriptionID = "notifications.pushRelay.subscriptionID.v1"
        public static let lastRegisteredAt = "notifications.pushRelay.lastRegisteredAt.v1"
        public static let lastRegistrationError = "notifications.pushRelay.lastRegistrationError.v1"
    }

    /// Master opt-in switch (off by default).
    public var isEnabled: Bool

    /// Selected push relay transport mode.
    public var mode: PushRelayMode

    /// Validated HTTPS push relay or JMAP API endpoint URL string.
    /// Invalid or credential-bearing URLs are never persisted.
    public var endpointURLString: String

    /// Validated HTTPS WebPush delivery receiver URL for `.jmapWebPush` mode.
    /// Must be distinct from `endpointURLString`; invalid or credential-bearing URLs are never persisted.
    public var webPushDeliveryURLString: String

    /// Explicit per-account opt-ins keyed by stable local `BrevAccount.ID`.
    public var enabledAccountIDs: Set<String>

    /// Device-local mapping `realAccountID -> "acct-<UUID>"` so raw account IDs
    /// (such as `imap-smtp:<email>`) are never disclosed to push relays.
    public var opaqueAccountTokens: [String: String]

    /// Opaque per-device client identifier generated locally on this device.
    public var deviceClientID: String

    /// Currently active remote registration tracked separately from editable draft URLs.
    public var activeRegistration: ActivePushRelayRegistration?

    /// Last registration/unregistration error message shown in Settings, if any.
    public var lastRegistrationError: String?

    /// Convenience accessor for the active registration's subscription ID, if any.
    public var subscriptionID: String? {
        activeRegistration?.subscriptionID
    }

    /// Convenience accessor for the active registration's timestamp, if any.
    public var lastRegisteredAt: Date? {
        activeRegistration?.registeredAt
    }

    /// Default configuration: strictly off, zero accounts opted in, empty endpoints.
    public static let defaults = PushRelaySettings(
        isEnabled: false,
        mode: .userHostedRelay,
        endpointURLString: "",
        webPushDeliveryURLString: "",
        enabledAccountIDs: [],
        opaqueAccountTokens: [:],
        deviceClientID: "",
        activeRegistration: nil,
        lastRegistrationError: nil
    )

    /// Creates device-local closed-app push relay settings.
    public init(
        isEnabled: Bool = false,
        mode: PushRelayMode = .userHostedRelay,
        endpointURLString: String = "",
        webPushDeliveryURLString: String = "",
        enabledAccountIDs: Set<String> = [],
        opaqueAccountTokens: [String: String] = [:],
        deviceClientID: String = "",
        activeRegistration: ActivePushRelayRegistration? = nil,
        lastRegistrationError: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.endpointURLString = Self.sanitizedPersistedURLString(endpointURLString)
        self.webPushDeliveryURLString = Self.sanitizedPersistedURLString(webPushDeliveryURLString)
        self.enabledAccountIDs = Set(
            enabledAccountIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        self.opaqueAccountTokens = opaqueAccountTokens.reduce(into: [:]) { result, entry in
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !value.isEmpty {
                result[key] = value
            }
        }
        self.deviceClientID = deviceClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.activeRegistration = activeRegistration
        let trimmedError = lastRegistrationError?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastRegistrationError = trimmedError?.isEmpty == false ? trimmedError : nil
    }

    /// Returns whether push wakes are enabled both globally and for `accountID`.
    public func isAccountEnabled(_ accountID: String) -> Bool {
        isEnabled && mode != .disabled && enabledAccountIDs.contains(accountID)
    }

    /// Toggles per-account opt-in without altering the master switch.
    /// Ensures an opaque device-local relay token exists when enabling an account.
    public mutating func setAccount(_ accountID: String, enabled: Bool) {
        let trimmed = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if enabled {
            enabledAccountIDs.insert(trimmed)
            _ = opaqueToken(forAccountID: trimmed)
        } else {
            enabledAccountIDs.remove(trimmed)
        }
    }

    /// Returns the opaque device-local relay token (`acct-<uuid>`) for `accountID`,
    /// generating and storing one if absent. Never contains the account's email address.
    @discardableResult
    public mutating func opaqueToken(forAccountID accountID: String) -> String {
        let trimmed = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = opaqueAccountTokens[trimmed], !existing.isEmpty {
            return existing
        }
        let generated = "acct-\(UUID().uuidString.lowercased())"
        opaqueAccountTokens[trimmed] = generated
        return generated
    }

    /// Returns sorted opaque tokens for every opted-in account, generating missing mappings.
    public mutating func opaqueTokensForEnabledAccounts() -> [String] {
        enabledAccountIDs.sorted().map { opaqueToken(forAccountID: $0) }.sorted()
    }

    /// Reverse-maps an incoming opaque relay token to the corresponding local `BrevAccount.ID`,
    /// returning `nil` if the token is unknown or the mapped account is not opted in.
    public func resolveAccountID(forOpaqueToken opaqueToken: String) -> String? {
        let trimmed = opaqueToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for (realAccountID, token) in opaqueAccountTokens where token == trimmed {
            guard enabledAccountIDs.contains(realAccountID) else { return nil }
            return realAccountID
        }
        return nil
    }

    /// Validates `endpointURLString` using strict HTTPS rules.
    public func validatedEndpointURL() throws -> URL {
        try PushRelayEndpointValidator.validate(endpointURLString)
    }

    /// Validates `webPushDeliveryURLString` using strict HTTPS rules.
    public func validatedWebPushDeliveryURL() throws -> URL {
        try PushRelayEndpointValidator.validate(webPushDeliveryURLString)
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
        let webPushDeliveryURLString = defaults.string(forKey: Key.webPushDeliveryURLString) ?? ""
        let rawIDs = defaults.stringArray(forKey: Key.enabledAccountIDs) ?? []
        let opaqueTokens: [String: String] = if let data = defaults.data(forKey: Key.opaqueAccountTokens),
                                                let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            decoded
        } else {
            [:]
        }
        let deviceClientID = defaults.string(forKey: Key.deviceClientID) ?? ""
        let activeRegistration: ActivePushRelayRegistration? = if let data = defaults.data(forKey: Key.activeRegistration),
                                                                  let decoded = try? JSONDecoder().decode(
                                                                      ActivePushRelayRegistration.self,
                                                                      from: data
                                                                  ) {
            decoded
        } else {
            nil
        }
        let lastRegistrationError = defaults.string(forKey: Key.lastRegistrationError)

        return PushRelaySettings(
            isEnabled: isEnabled,
            mode: mode,
            endpointURLString: endpointURLString,
            webPushDeliveryURLString: webPushDeliveryURLString,
            enabledAccountIDs: Set(rawIDs),
            opaqueAccountTokens: opaqueTokens,
            deviceClientID: deviceClientID,
            activeRegistration: activeRegistration,
            lastRegistrationError: lastRegistrationError
        )
    }

    /// Persists device-local push relay settings to `defaults`.
    ///
    /// Never writes bearer secrets, private encryption keys, or invalid/credential-bearing URLs
    /// to `UserDefaults`.
    public func save(to defaults: UserDefaults = .standard) {
        var copy = self
        if copy.isEnabled, copy.deviceClientID.isEmpty {
            _ = copy.ensureDeviceClientID()
        }
        // Defense in depth: only valid https:// URLs with zero embedded credentials are ever persisted.
        let safeEndpoint = Self.sanitizedPersistedURLString(copy.endpointURLString)
        let safeDelivery = Self.sanitizedPersistedURLString(copy.webPushDeliveryURLString)

        defaults.set(copy.isEnabled, forKey: Key.isEnabled)
        defaults.set(copy.mode.rawValue, forKey: Key.mode)
        defaults.set(safeEndpoint, forKey: Key.endpointURLString)
        defaults.set(safeDelivery, forKey: Key.webPushDeliveryURLString)
        defaults.set(Array(copy.enabledAccountIDs).sorted(), forKey: Key.enabledAccountIDs)
        if !copy.opaqueAccountTokens.isEmpty,
           let tokenData = try? JSONEncoder().encode(copy.opaqueAccountTokens) {
            defaults.set(tokenData, forKey: Key.opaqueAccountTokens)
        } else {
            defaults.removeObject(forKey: Key.opaqueAccountTokens)
        }
        if copy.deviceClientID.isEmpty {
            defaults.removeObject(forKey: Key.deviceClientID)
        } else {
            defaults.set(copy.deviceClientID, forKey: Key.deviceClientID)
        }
        if let active = copy.activeRegistration,
           let activeData = try? JSONEncoder().encode(active) {
            defaults.set(activeData, forKey: Key.activeRegistration)
        } else {
            defaults.removeObject(forKey: Key.activeRegistration)
        }
        // Clean legacy flat keys if present.
        defaults.removeObject(forKey: Key.subscriptionID)
        defaults.removeObject(forKey: Key.lastRegisteredAt)

        if let lastRegistrationError = copy.lastRegistrationError {
            defaults.set(lastRegistrationError, forKey: Key.lastRegistrationError)
        } else {
            defaults.removeObject(forKey: Key.lastRegistrationError)
        }
        if defaults === UserDefaults.standard {
            NotificationCenter.default.post(name: .brevPushRelaySettingsDidChange, object: nil)
        }
    }

    /// Removes a deleted account from the device-local push opt-in set and opaque token table.
    public static func removeAccount(_ accountID: String, from defaults: UserDefaults = .standard) {
        let trimmed = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var settings = load(from: defaults)
        let removedOptIn = settings.enabledAccountIDs.remove(trimmed) != nil
        let removedToken = settings.opaqueAccountTokens.removeValue(forKey: trimmed) != nil
        guard removedOptIn || removedToken else { return }
        settings.save(to: defaults)
    }

    /// Strips any URL that fails strict HTTPS + zero-credential validation.
    private static func sanitizedPersistedURLString(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let validated = try? PushRelayEndpointValidator.validate(trimmed) else {
            return ""
        }
        return validated.absoluteString
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
