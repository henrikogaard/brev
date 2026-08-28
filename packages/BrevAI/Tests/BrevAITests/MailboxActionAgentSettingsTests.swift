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

@Suite("MailboxActionAgentSettings")
struct MailboxActionAgentSettingsTests {
    @Test("defaults keep mailbox actions hidden without consent")
    func defaultsKeepMailboxActionsHiddenWithoutConsent() throws {
        let defaults = try Self.makeDefaults()

        let settings = MailboxActionAgentSettings.load(from: defaults)

        #expect(settings.isEnabled == false)
        #expect(settings.consentGiven == false)
        #expect(settings.isAvailable == false)
    }

    @Test("availability persists through mailbox-action-specific storage keys")
    func availabilityPersistsThroughMailboxActionSpecificStorageKeys() throws {
        let defaults = try Self.makeDefaults()
        var settings = MailboxActionAgentSettings.defaults

        settings.setAvailable(true)
        settings.save(to: defaults)
        let restored = MailboxActionAgentSettings.load(from: defaults)

        #expect(defaults.bool(forKey: MailboxActionAgentSettings.Key.isEnabled))
        #expect(defaults.bool(forKey: MailboxActionAgentSettings.Key.consentGiven))
        #expect(restored.isAvailable)
    }

    @Test("reset consent clears mailbox-action availability")
    func resetConsentClearsMailboxActionAvailability() throws {
        let defaults = try Self.makeDefaults()
        var settings = MailboxActionAgentSettings(isEnabled: true, consentGiven: true)

        settings.resetConsent()
        settings.save(to: defaults)
        let restored = MailboxActionAgentSettings.load(from: defaults)

        #expect(restored == .defaults)
    }

    @Test("disclosure copy separates mailbox actions from compose writing")
    func disclosureCopySeparatesMailboxActionsFromComposeWriting() {
        #expect(MailboxActionAgentDisclosure.defaultProvider.displayName == "Provider-hosted mailbox assistant")
        #expect(MailboxActionAgentDisclosure.defaultProvider.transparencyLabel == "Sent to: Provider-hosted AI")
        #expect(MailboxActionAgentDisclosure.defaultProvider.consentMessage.contains("configured account AI endpoint"))
        #expect(MailboxActionAgentDisclosure.defaultProvider.consentMessage.contains("does not receive message bodies"))
        #expect(MailboxActionAgentDisclosure.unsupportedAccountMessage.contains("available AI provider"))
    }

    @available(*, deprecated, message: "Exercises deprecated compatibility alias")
    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "MailboxActionAgentSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
