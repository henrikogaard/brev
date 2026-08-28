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

/// Shared opt-in state for AI-assisted mailbox actions.
///
/// This is intentionally separate from `AIWriterSettings`: compose
/// assistance and mailbox mutations have different consent boundaries.
public struct MailboxActionAgentSettings: Equatable, Sendable {
    public enum Key {
        public static let isEnabled = "ai.mailboxActionAgent.enabled"
        public static let consentGiven = "ai.mailboxActionAgent.consentGiven"
    }

    public var isEnabled: Bool
    public var consentGiven: Bool

    public var isAvailable: Bool {
        isEnabled && consentGiven
    }

    public static let defaults = MailboxActionAgentSettings(
        isEnabled: false,
        consentGiven: false
    )

    public init(isEnabled: Bool, consentGiven: Bool) {
        self.isEnabled = isEnabled
        self.consentGiven = consentGiven
    }

    public static func load(from defaults: UserDefaults = .standard) -> MailboxActionAgentSettings {
        MailboxActionAgentSettings(
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

public struct MailboxActionAgentDisclosure: Equatable, Sendable {
    public let displayName: String
    public let transparencyLabel: String
    public let consentMessage: String

    public static let defaultProvider = MailboxActionAgentDisclosure(
        displayName: String(localized: "Provider-hosted mailbox assistant", bundle: .module),
        transparencyLabel: String(localized: "Sent to: Provider-hosted AI", bundle: .module),
        consentMessage: [
            String(
                localized: "Mailbox Assistant sends your typed request to the configured account AI endpoint to plan mailbox actions.",
                bundle: .module
            ),
            String(
                localized: "It does not receive message bodies, attachments, matched message IDs, or mailbox indexes.",
                bundle: .module
            ),
            String(
                localized: "Brev computes counts locally and requires your exact confirmation before any mutation runs.",
                bundle: .module
            )
        ].joined(separator: " ")
    )
    public static let unsupportedAccountMessage = [
        String(
            localized: "Mailbox Assistant requires an account backend with an available AI provider.",
            bundle: .module
        ),
        String(
            localized: "It stays hidden until mailbox-action AI is explicitly enabled for a supported account.",
            bundle: .module
        )
    ].joined(separator: " ")
}
