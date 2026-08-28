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

/// Shared opt-in state for AI Writer.
///
/// Both compose and settings use this model and its storage keys so
/// enabling, disabling, and resetting consent cannot drift between
/// surfaces.
public struct AIWriterSettings: Equatable, Sendable {
    public enum Key {
        public static let isEnabled = "ai.enabled"
        public static let consentGiven = "ai.consentGiven"
    }

    public var isEnabled: Bool
    public var consentGiven: Bool

    public var isAvailable: Bool {
        isEnabled && consentGiven
    }

    public static let defaults = AIWriterSettings(
        isEnabled: false,
        consentGiven: false
    )

    public init(isEnabled: Bool, consentGiven: Bool) {
        self.isEnabled = isEnabled
        self.consentGiven = consentGiven
    }

    public static func load(from defaults: UserDefaults = .standard) -> AIWriterSettings {
        AIWriterSettings(
            isEnabled: bool(
                for: Key.isEnabled,
                defaultValue: Self.defaults.isEnabled,
                defaults: defaults
            ),
            consentGiven: bool(
                for: Key.consentGiven,
                defaultValue: Self.defaults.consentGiven,
                defaults: defaults
            )
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: Key.isEnabled)
        defaults.set(consentGiven, forKey: Key.consentGiven)
    }

    public mutating func setAvailable(_ isAvailable: Bool) {
        isEnabled = isAvailable
        if isAvailable {
            consentGiven = true
        }
    }

    public mutating func resetConsent() {
        isEnabled = false
        consentGiven = false
    }

    private static func bool(
        for key: String,
        defaultValue: Bool,
        defaults: UserDefaults
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }
}

public struct AIWriterDisclosure: Equatable, Sendable {
    public let displayName: String
    public let transparencyLabel: String
    public let consentMessage: String

    public static let defaultProvider = AIWriterDisclosure(
        displayName: String(localized: "Provider-hosted AI assistant", bundle: .module),
        transparencyLabel: String(localized: "Sent to: Provider-hosted AI", bundle: .module),
        consentMessage: [
            String(localized: "AI Writer sends your text to the configured account AI endpoint.", bundle: .module),
            String(
                localized: "Your AI request is processed by the account provider and is not used for model training by default.",
                bundle: .module
            ),
            String(
                localized: "Only the content generated from your request is shared with the provider endpoint.",
                bundle: .module
            )
        ].joined(separator: " ")
    )
    public static let unsupportedAccountMessage = [
        String(localized: "AI Writer v1 requires an account backend with server-side AI support.", bundle: .module),
        String(
            localized: "BYOK/local providers are planned for v2, so this account stays disabled until a provider is configured.",
            bundle: .module
        )
    ].joined(separator: " ")
}
