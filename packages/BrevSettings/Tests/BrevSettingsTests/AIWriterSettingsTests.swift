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

import BrevAI
@testable import BrevSettings
import Foundation
import Testing

@Suite("AIWriterSettings")
struct AIWriterSettingsTests {
    @Test("defaults keep AI writer disabled without consent")
    func defaultsKeepAIWriterDisabledWithoutConsent() throws {
        let defaults = try Self.makeDefaults()

        let settings = AIWriterSettings.load(from: defaults)

        #expect(settings.isEnabled == false)
        #expect(settings.consentGiven == false)
        #expect(settings.isAvailable == false)
    }

    @Test("enabling AI writer grants consent and saving round trips")
    func enablingAIWriterGrantsConsentAndSavingRoundTrips() throws {
        let defaults = try Self.makeDefaults()
        var settings = AIWriterSettings.defaults

        settings.setAvailable(true)
        settings.save(to: defaults)
        let restored = AIWriterSettings.load(from: defaults)

        #expect(restored.isEnabled)
        #expect(restored.consentGiven)
        #expect(restored.isAvailable)
    }

    @Test("resetting AI writer consent clears both persisted flags")
    func resettingAIWriterConsentClearsBothPersistedFlags() throws {
        let defaults = try Self.makeDefaults()
        var settings = AIWriterSettings(isEnabled: true, consentGiven: true)

        settings.resetConsent()
        settings.save(to: defaults)
        let restored = AIWriterSettings.load(from: defaults)

        #expect(restored == .defaults)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "AIWriterSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
