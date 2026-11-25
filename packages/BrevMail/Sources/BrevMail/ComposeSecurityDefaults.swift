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

    /// Returns `.disabled` when the active mail backend does not advertise
    /// `BackendExtendedCapabilities.outboundSMIME` (for example native Gmail
    /// while it rejects protected drafts), preventing global S/MIME defaults
    /// from blocking sends on unsupported backends.
    public func gated(
        by extendedCapabilities: BackendExtendedCapabilities
    ) -> ComposeSecurityDefaultState {
        extendedCapabilities.contains(.outboundSMIME) ? self : .disabled
    }
}

public enum ComposeSecurityDefaults {
    public static func resolve(
        encryptionSettings: EncryptionSettings,
        trustedSigningIdentityCount: Int,
        trustedEncryptionIdentityCount: Int,
        supportsOutboundSMIME: Bool = true
    ) -> ComposeSecurityDefaultState {
        let featureEnabled = encryptionSettings.smimeEnabled && supportsOutboundSMIME
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

/// Pure state-transition rules for S/MIME controls when switching the active
/// `From:` sender account inside compose.
public enum ComposeSecuritySenderSwitchPolicy {
    /// Returns whether the compose Security menu should be shown.
    ///
    /// Shown whenever S/MIME is globally enabled AND either the selected
    /// backend supports outbound S/MIME OR the draft already has signing or
    /// encryption active (so the user can see and explicitly change it).
    public static func isSecurityMenuVisible(
        defaults: ComposeSecurityDefaultState,
        backendSupportsOutboundSMIME: Bool,
        currentMode: OutboundMessageSecurityMode
    ) -> Bool {
        defaults.isFeatureEnabled && (backendSupportsOutboundSMIME || currentMode != .none)
    }

    /// Resolves the draft's security mode after switching the `From:` sender.
    ///
    /// **Fail-closed security invariant:** Switching an already-signed or
    /// already-encrypted draft to a backend without `.outboundSMIME` NEVER
    /// silently downgrades `currentMode` to `.none` (plaintext). The active
    /// security mode stays selected so send validation blocks plaintext
    /// delivery until the user explicitly switches back or turns off S/MIME.
    public static func modeAfterSenderSwitch(
        currentMode: OutboundMessageSecurityMode,
        hasExplicitUserSelection: Bool,
        defaults: ComposeSecurityDefaultState,
        newBackendSupportsOutboundSMIME: Bool
    ) -> OutboundMessageSecurityMode {
        guard currentMode == .none else {
            return currentMode
        }
        guard !hasExplicitUserSelection, newBackendSupportsOutboundSMIME else {
            return .none
        }
        return OutboundMessageSecurityMode(
            signing: defaults.shouldSignByDefault,
            encrypting: defaults.shouldEncryptByDefault
        )
    }
}
