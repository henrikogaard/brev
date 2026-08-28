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

/// User preferences for message signing and encryption.
///
/// These settings are intentionally inert until `#13`
/// (PGP/MIME and S/MIME rendering pipeline) and its ADR land.
/// The model is persisted so that a future implementation can read
/// whatever the user has already configured.
///
/// **No encryption or decryption ever happens based solely on these
/// settings.** The library, trust model, and key-storage ADR must
/// ship first. Views gate encryption UI on a capability flag, not
/// on these values directly.
public struct EncryptionSettings: Equatable, Sendable {
    public enum Key {
        public static let smimeEnabled = "encryption.smimeEnabled"
        public static let preferSign = "encryption.preferSign"
        public static let preferEncrypt = "encryption.preferEncrypt"
    }

    /// Whether the user has opted into S/MIME certificate handling.
    public var smimeEnabled: Bool
    /// Prefer signing outgoing messages when a local private key is available.
    public var preferSign: Bool
    /// Prefer encrypting outgoing messages when recipient keys are trusted.
    public var preferEncrypt: Bool

    public static let defaults = EncryptionSettings(
        smimeEnabled: false,
        preferSign: false,
        preferEncrypt: false
    )

    public init(
        smimeEnabled: Bool,
        preferSign: Bool,
        preferEncrypt: Bool
    ) {
        self.smimeEnabled = smimeEnabled
        self.preferSign = preferSign
        self.preferEncrypt = preferEncrypt
    }

    public static func load(from defaults: UserDefaults = .standard) -> EncryptionSettings {
        EncryptionSettings(
            smimeEnabled: defaults.object(forKey: Key.smimeEnabled) != nil
                ? defaults.bool(forKey: Key.smimeEnabled) : Self.defaults.smimeEnabled,
            preferSign: defaults.object(forKey: Key.preferSign) != nil
                ? defaults.bool(forKey: Key.preferSign) : Self.defaults.preferSign,
            preferEncrypt: defaults.object(forKey: Key.preferEncrypt) != nil
                ? defaults.bool(forKey: Key.preferEncrypt) : Self.defaults.preferEncrypt
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(smimeEnabled, forKey: Key.smimeEnabled)
        defaults.set(preferSign, forKey: Key.preferSign)
        defaults.set(preferEncrypt, forKey: Key.preferEncrypt)
    }
}
