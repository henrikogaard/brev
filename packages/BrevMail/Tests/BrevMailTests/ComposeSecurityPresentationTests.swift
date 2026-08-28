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

@testable import BrevMail
import Testing

@Suite("ComposeSecurityPresentation")
struct ComposeSecurityPresentationTests {
    @Test("menu help text reflects selected security controls")
    func menuHelpTextReflectsSelections() {
        #expect(ComposeSecurityPresentation.menuHelpText(
            isSigningEnabled: false,
            isEncryptionEnabled: false
        ) == "Security options")
        #expect(ComposeSecurityPresentation.menuHelpText(
            isSigningEnabled: true,
            isEncryptionEnabled: false
        ) == "Signing enabled")
        #expect(ComposeSecurityPresentation.menuHelpText(
            isSigningEnabled: false,
            isEncryptionEnabled: true
        ) == "Encryption enabled")
        #expect(ComposeSecurityPresentation.menuHelpText(
            isSigningEnabled: true,
            isEncryptionEnabled: true
        ) == "Signing and encryption enabled")
    }

    @Test("missing key warning prefers signing warning first")
    func missingKeyWarningPrefersSigningWarningFirst() {
        #expect(ComposeSecurityPresentation.missingKeyWarning(
            isSigningEnabled: true,
            hasTrustedSigningIdentity: false,
            isEncryptionEnabled: true,
            hasTrustedEncryptionIdentity: false
        ) == "Signing is enabled, but no trusted local signing identity is available.")
    }

    @Test("missing key warning reports encryption warning when signing is satisfied")
    func missingKeyWarningReportsEncryptionWarning() {
        #expect(ComposeSecurityPresentation.missingKeyWarning(
            isSigningEnabled: true,
            hasTrustedSigningIdentity: true,
            isEncryptionEnabled: true,
            hasTrustedEncryptionIdentity: false
        ) == "Encryption is enabled, but no trusted local encryption identity is available.")
    }

    @Test("missing key warning is nil when required identities exist")
    func missingKeyWarningIsNilWhenIdentitiesExist() {
        #expect(ComposeSecurityPresentation.missingKeyWarning(
            isSigningEnabled: true,
            hasTrustedSigningIdentity: true,
            isEncryptionEnabled: true,
            hasTrustedEncryptionIdentity: true
        ) == nil)
    }
}
