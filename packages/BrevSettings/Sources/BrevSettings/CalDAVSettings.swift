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

/// User configuration for the optional CalDAV write target.
///
/// Brev is not a calendar client: this models *only* a single collection
/// into which accepted invites are PUT. There is no calendar browsing or
/// sync. The whole feature is hidden unless `featureFlagEnabled` is set,
/// and inert unless the user additionally turns `isEnabled` on.
///
/// Credentials are never stored here — they live in the Keychain, keyed
/// by `credentialAccount`. This struct only persists non-secret metadata.
public struct CalDAVSettings: Equatable, Sendable {
    public enum Key {
        public static let featureFlagEnabled = "caldav.featureFlagEnabled"
        public static let isEnabled = "caldav.isEnabled"
        public static let serverURL = "caldav.serverURL"
        public static let calendarName = "caldav.calendarName"
        public static let collectionPath = "caldav.collectionPath"
        public static let credentialAccount = "caldav.credentialAccount"
        public static let useLocalBasicAuth = "caldav.useLocalBasicAuth"
    }

    /// Master gate: when `false`, the CalDAV settings UI is not shown at
    /// all. Off by default — the feature is opt-in per ADR-0028.
    public var featureFlagEnabled: Bool
    /// Whether the user has turned the configured target on.
    public var isEnabled: Bool
    /// Base server URL, e.g. `https://caldav.example.com`.
    public var serverURL: String
    /// Human-readable calendar name shown in the UI.
    public var calendarName: String
    /// Path of the writable calendar collection on the server, e.g.
    /// `/calendars/user/personal/`. Combined with `serverURL` to form the
    /// collection URL events are PUT into.
    public var collectionPath: String
    /// Keychain account identifier under which this target's credential is
    /// stored. Empty until the user saves a credential.
    public var credentialAccount: String
    /// Use HTTP Basic instead of OAuth2 Bearer. Only honoured for
    /// localhost servers by `CalDAVEventWriter`; off by default.
    public var useLocalBasicAuth: Bool

    public init(
        featureFlagEnabled: Bool,
        isEnabled: Bool,
        serverURL: String,
        calendarName: String,
        collectionPath: String,
        credentialAccount: String,
        useLocalBasicAuth: Bool
    ) {
        self.featureFlagEnabled = featureFlagEnabled
        self.isEnabled = isEnabled
        self.serverURL = serverURL
        self.calendarName = calendarName
        self.collectionPath = collectionPath
        self.credentialAccount = credentialAccount
        self.useLocalBasicAuth = useLocalBasicAuth
    }

    public static let defaults = CalDAVSettings(
        featureFlagEnabled: false,
        isEnabled: false,
        serverURL: "",
        calendarName: "Calendar",
        collectionPath: "",
        credentialAccount: "",
        useLocalBasicAuth: false
    )

    /// Whether the CalDAV write target is fully configured and active.
    ///
    /// Callers use this to decide between the CalDAV PUT path and the
    /// local iMIP fallback when a user accepts an invite.
    public var isWriteTargetActive: Bool {
        featureFlagEnabled
            && isEnabled
            && !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !collectionPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The fully-resolved collection URL events are written to, or `nil`
    /// if the configured server/path don't form a valid URL.
    public var collectionURL: URL? {
        let trimmedServer = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedServer.isEmpty, var base = URL(string: trimmedServer) else { return nil }
        let path = collectionPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return base }
        for segment in path.split(separator: "/") {
            base.appendPathComponent(String(segment))
        }
        // Preserve trailing slash convention for CalDAV collections.
        if path.hasSuffix("/"), !base.absoluteString.hasSuffix("/") {
            base = URL(string: base.absoluteString + "/") ?? base
        }
        return base
    }

    public static func load(from defaults: UserDefaults = .standard) -> CalDAVSettings {
        func bool(_ key: String, default fallback: Bool) -> Bool {
            defaults.object(forKey: key) != nil ? defaults.bool(forKey: key) : fallback
        }
        return CalDAVSettings(
            featureFlagEnabled: bool(Key.featureFlagEnabled, default: Self.defaults.featureFlagEnabled),
            isEnabled: bool(Key.isEnabled, default: Self.defaults.isEnabled),
            serverURL: defaults.string(forKey: Key.serverURL) ?? Self.defaults.serverURL,
            calendarName: defaults.string(forKey: Key.calendarName) ?? Self.defaults.calendarName,
            collectionPath: defaults.string(forKey: Key.collectionPath) ?? Self.defaults.collectionPath,
            credentialAccount: defaults.string(forKey: Key.credentialAccount) ?? Self.defaults.credentialAccount,
            useLocalBasicAuth: bool(Key.useLocalBasicAuth, default: Self.defaults.useLocalBasicAuth)
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(featureFlagEnabled, forKey: Key.featureFlagEnabled)
        defaults.set(isEnabled, forKey: Key.isEnabled)
        defaults.set(serverURL, forKey: Key.serverURL)
        defaults.set(calendarName, forKey: Key.calendarName)
        defaults.set(collectionPath, forKey: Key.collectionPath)
        defaults.set(credentialAccount, forKey: Key.credentialAccount)
        defaults.set(useLocalBasicAuth, forKey: Key.useLocalBasicAuth)
    }
}
