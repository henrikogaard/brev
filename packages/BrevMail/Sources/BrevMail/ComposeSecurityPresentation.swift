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

import BrevDesign
import Foundation
import SwiftUI

enum ComposeSecurityPresentation {
    static func menuHelpText(
        isSigningEnabled: Bool,
        isEncryptionEnabled: Bool
    ) -> String {
        if isSigningEnabled, isEncryptionEnabled {
            return "Signing and encryption enabled"
        }
        if isSigningEnabled {
            return "Signing enabled"
        }
        if isEncryptionEnabled {
            return "Encryption enabled"
        }
        return "Security options"
    }

    static func missingKeyWarning(
        isSigningEnabled: Bool,
        hasTrustedSigningIdentity: Bool,
        isEncryptionEnabled: Bool,
        hasTrustedEncryptionIdentity: Bool
    ) -> String? {
        if isSigningEnabled, !hasTrustedSigningIdentity {
            return "Signing is enabled, but no trusted local signing identity is available."
        }
        if isEncryptionEnabled, !hasTrustedEncryptionIdentity {
            return "Encryption is enabled, but no trusted local encryption identity is available."
        }
        return nil
    }

    /// Returns a blocking error message when signing or encryption is active
    /// on a draft whose selected sender backend does not support outbound
    /// S/MIME (never silently downgrading to plaintext).
    static func unsupportedBackendWarning(
        isSigningEnabled: Bool,
        isEncryptionEnabled: Bool,
        supportsOutboundSMIME: Bool
    ) -> String? {
        guard isSigningEnabled || isEncryptionEnabled, !supportsOutboundSMIME else {
            return nil
        }
        return String(
            localized: "This account doesn't support S/MIME signing or encryption. Switch to a supported account or turn off message security before sending.",
            bundle: .module
        )
    }
}

/// Inline warning banner rendered in Compose whenever S/MIME signing or
/// encryption remains active after switching to a sender backend that does not
/// advertise `.outboundSMIME`.
struct ComposeSecurityWarningBanner: View {
    let isSigningEnabled: Bool
    let isEncryptionEnabled: Bool
    let supportsOutboundSMIME: Bool

    var body: some View {
        if let message = ComposeSecurityPresentation.unsupportedBackendWarning(
            isSigningEnabled: isSigningEnabled,
            isEncryptionEnabled: isEncryptionEnabled,
            supportsOutboundSMIME: supportsOutboundSMIME
        ) {
            VStack(spacing: 0) {
                BrevDivider()
                BrevInlineStatus(
                    message: message,
                    tone: .warning,
                    lineLimit: 3
                )
            }
        }
    }
}
