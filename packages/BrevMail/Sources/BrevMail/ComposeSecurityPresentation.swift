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
}
