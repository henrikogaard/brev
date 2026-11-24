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
@testable import BrevMail
import BrevSettings
import Testing

@Suite("ComposeSecurityDefaults")
struct ComposeSecurityDefaultsTests {
    @Test("feature stays disabled and safe by default")
    func featureStaysDisabledAndSafeByDefault() {
        let state = ComposeSecurityDefaults.resolve(
            encryptionSettings: .defaults,
            trustedSigningIdentityCount: 5,
            trustedEncryptionIdentityCount: 5
        )

        #expect(state == .disabled)
    }

    @Test("signing and encryption defaults require trusted local material")
    func defaultsRequireTrustedLocalMaterial() {
        let settings = EncryptionSettings(
            smimeEnabled: true,
            preferSign: true,
            preferEncrypt: true
        )

        let state = ComposeSecurityDefaults.resolve(
            encryptionSettings: settings,
            trustedSigningIdentityCount: 0,
            trustedEncryptionIdentityCount: 1
        )

        #expect(state.isFeatureEnabled)
        #expect(state.shouldSignByDefault == false)
        #expect(state.shouldEncryptByDefault)
    }

    @Test("encryption defaults stay off when preference is disabled")
    func encryptionDefaultsStayOffWhenPreferenceIsDisabled() {
        let settings = EncryptionSettings(
            smimeEnabled: true,
            preferSign: false,
            preferEncrypt: false
        )

        let state = ComposeSecurityDefaults.resolve(
            encryptionSettings: settings,
            trustedSigningIdentityCount: 1,
            trustedEncryptionIdentityCount: 2
        )

        #expect(state.isFeatureEnabled)
        #expect(state.shouldSignByDefault == false)
        #expect(state.shouldEncryptByDefault == false)
    }

    @Test(
        "backends without outboundSMIME capability (such as native Gmail) start with .none even when global S/MIME defaults are enabled"
    )
    func unsupportedBackendDisablesDefaultsAndStartsWithNoneMode() {
        let settings = EncryptionSettings(
            smimeEnabled: true,
            preferSign: true,
            preferEncrypt: true
        )
        let enabledDefaults = ComposeSecurityDefaults.resolve(
            encryptionSettings: settings,
            trustedSigningIdentityCount: 2,
            trustedEncryptionIdentityCount: 2
        )
        #expect(enabledDefaults.shouldSignByDefault)
        #expect(enabledDefaults.shouldEncryptByDefault)

        // Native Gmail backend omits `.outboundSMIME` from extendedCapabilities.
        let gmailCapabilities: BackendExtendedCapabilities = [.rawMessageSource, .cachedMessageHeaders]
        let gatedForGmail = enabledDefaults.gated(by: gmailCapabilities)
        #expect(gatedForGmail == .disabled)
        #expect(
            OutboundMessageSecurityMode(
                signing: gatedForGmail.shouldSignByDefault,
                encrypting: gatedForGmail.shouldEncryptByDefault
            ) == .none
        )

        // IMAP/SMTP with an outbound preparer advertises `.outboundSMIME`.
        let imapCapabilities: BackendExtendedCapabilities = [.outboundSMIME]
        let gatedForIMAP = enabledDefaults.gated(by: imapCapabilities)
        #expect(gatedForIMAP == enabledDefaults)

        // Resolving with supportsOutboundSMIME: false directly also yields .disabled.
        let directUnsupported = ComposeSecurityDefaults.resolve(
            encryptionSettings: settings,
            trustedSigningIdentityCount: 2,
            trustedEncryptionIdentityCount: 2,
            supportsOutboundSMIME: false
        )
        #expect(directUnsupported == .disabled)
    }
}
