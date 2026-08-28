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

import BrevSettings
import Foundation

public struct ComposeSecurityDefaultState: Equatable, Sendable {
    public let isFeatureEnabled: Bool
    public let shouldSignByDefault: Bool
    public let shouldEncryptByDefault: Bool

    public static let disabled = ComposeSecurityDefaultState(
        isFeatureEnabled: false,
        shouldSignByDefault: false,
        shouldEncryptByDefault: false
    )

    public init(
        isFeatureEnabled: Bool,
        shouldSignByDefault: Bool,
        shouldEncryptByDefault: Bool
    ) {
        self.isFeatureEnabled = isFeatureEnabled
        self.shouldSignByDefault = shouldSignByDefault
        self.shouldEncryptByDefault = shouldEncryptByDefault
    }
}

public enum ComposeSecurityDefaults {
    public static func resolve(
        encryptionSettings: EncryptionSettings,
        trustedSigningIdentityCount: Int,
        trustedEncryptionIdentityCount: Int
    ) -> ComposeSecurityDefaultState {
        let featureEnabled = encryptionSettings.smimeEnabled
        guard featureEnabled else {
            return .disabled
        }

        let hasTrustedSigningIdentity = trustedSigningIdentityCount > 0
        let hasTrustedEncryptionIdentity = trustedEncryptionIdentityCount > 0
        let shouldSign = encryptionSettings.preferSign && hasTrustedSigningIdentity
        let shouldEncrypt = encryptionSettings.preferEncrypt && hasTrustedEncryptionIdentity

        return ComposeSecurityDefaultState(
            isFeatureEnabled: true,
            shouldSignByDefault: shouldSign,
            shouldEncryptByDefault: shouldEncrypt
        )
    }
}
