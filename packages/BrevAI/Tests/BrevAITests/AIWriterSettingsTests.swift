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

@testable import BrevAI
import Foundation
import Testing

@Suite("AIWriterSettings")
struct AIWriterSettingsTests {
    @Test("defaults keep AI Writer disabled without consent")
    func defaultsKeepAIWriterDisabledWithoutConsent() throws {
        let defaults = try Self.makeDefaults()

        let settings = AIWriterSettings.load(from: defaults)

        #expect(settings.isEnabled == false)
        #expect(settings.consentGiven == false)
        #expect(settings.isAvailable == false)
    }

    @Test("availability persists through the shared storage keys")
    func availabilityPersistsThroughSharedStorageKeys() throws {
        let defaults = try Self.makeDefaults()
        var settings = AIWriterSettings.defaults

        settings.setAvailable(true)
        settings.save(to: defaults)
        let restored = AIWriterSettings.load(from: defaults)

        #expect(defaults.bool(forKey: AIWriterSettings.Key.isEnabled))
        #expect(defaults.bool(forKey: AIWriterSettings.Key.consentGiven))
        #expect(restored.isAvailable)
    }

    @Test("reset consent clears enabled and consent flags")
    func resetConsentClearsEnabledAndConsentFlags() throws {
        let defaults = try Self.makeDefaults()
        var settings = AIWriterSettings(isEnabled: true, consentGiven: true)

        settings.resetConsent()
        settings.save(to: defaults)
        let restored = AIWriterSettings.load(from: defaults)

        #expect(restored == .defaults)
    }

    @Test("privacy copy uses provider-hosted defaults")
    func privacyCopyMatchesV1ProviderHostedDisclosure() {
        #expect(AIWriterDisclosure.defaultProvider.displayName == "Provider-hosted AI assistant")
        #expect(AIWriterDisclosure.defaultProvider.transparencyLabel == "Sent to: Provider-hosted AI")
        #expect(AIWriterDisclosure.defaultProvider.consentMessage.contains("not used for model training"))
        #expect(AIWriterDisclosure.unsupportedAccountMessage.contains("BYOK/local providers are planned for v2"))
    }

    @available(*, deprecated, message: "Exercises deprecated compatibility alias")
    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "AIWriterSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
