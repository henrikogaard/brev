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
}
