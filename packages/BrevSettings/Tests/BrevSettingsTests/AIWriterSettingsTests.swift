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
import BrevBackend
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
        #expect(settings.proactiveOnDeviceTriageEnabled == false)
        #expect(settings.isProactiveOnDeviceTriageAvailable == false)
    }

    @Test("enabling AI writer grants consent and saving round trips")
    func enablingAIWriterGrantsConsentAndSavingRoundTrips() throws {
        let defaults = try Self.makeDefaults()
        var settings = AIWriterSettings.defaults

        settings.setAvailable(true)
        settings.proactiveOnDeviceTriageEnabled = true
        settings.save(to: defaults)
        let restored = AIWriterSettings.load(from: defaults)

        #expect(restored.isEnabled)
        #expect(restored.consentGiven)
        #expect(restored.isAvailable)
        #expect(restored.proactiveOnDeviceTriageEnabled)
        #expect(restored.isProactiveOnDeviceTriageAvailable)
    }

    @Test("resetting AI writer consent clears all persisted flags")
    func resettingAIWriterConsentClearsBothPersistedFlags() throws {
        let defaults = try Self.makeDefaults()
        var settings = AIWriterSettings(
            isEnabled: true,
            consentGiven: true,
            proactiveOnDeviceTriageEnabled: true
        )

        settings.resetConsent()
        settings.save(to: defaults)
        let restored = AIWriterSettings.load(from: defaults)

        #expect(restored == .defaults)
        #expect(restored.proactiveOnDeviceTriageEnabled == false)
    }

    @Test("proactive on-device AI settings strings have Norwegian catalog translations")
    func proactiveOnDeviceNorwegianCatalogCoverage() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BrevSettings/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: Any])

        for key in [
            "Automatic on-device summaries & priority",
            "Generates short thread summaries and Urgent or Needs reply badges automatically only when an on-device AI provider is active. Never sends mail to cloud providers.",
            "Turn on AI Writer above and choose an on-device provider to enable automatic summaries.",
            "Only available when an on-device AI provider is active. Cloud and BYOK providers require an explicit click.",
            "Runs automatically only for accounts using on-device AI. Accounts with a cloud or BYOK override stay manual."
        ] {
            let entry = try #require(strings[key] as? [String: Any], "Missing BrevSettings key: \(key)")
            let nb = (entry["localizations"] as? [String: Any])?["nb"] as? [String: Any]
            let unit = nb?["stringUnit"] as? [String: Any]
            #expect((unit?["value"] as? String)?.isEmpty == false, "Missing nb translation for: \(key)")
        }
    }

    @Test("provider summary matches AIProviderResolver routing and ignores unassigned non-default on-device profiles")
    func providerSummaryRequiresDefaultOrAssignedOnDeviceRoute() throws {
        let account = BrevAccount(id: "acct-1", displayName: "Work", emailAddress: "work@example.org")
        let unassignedApple = AIProviderConfiguration.appleIntelligence(
            isEnabled: true,
            isDefault: false,
            assignedAccountID: nil
        )
        let cloudDefault = try #require(AIProviderConfiguration(
            id: AIProviderID("openai"),
            kind: .openAICompatible,
            displayName: "OpenAI",
            endpointURL: URL(string: "https://api.openai.com/v1"),
            modelID: "gpt-4o",
            isEnabled: true,
            isDefault: true,
            assignedAccountID: nil
        ))

        // Unassigned non-default Apple Intelligence alone (e.g. after deleting a cloud default) is NOT active
        let orphanSummary = AIWriterSectionProviderSummary.evaluate(
            configurations: [unassignedApple],
            assignments: AIProviderAccountAssignments(),
            accounts: [account],
            appleIntelligenceAvailability: .available
        )
        #expect(orphanSummary.hasActiveOnDeviceProvider == false)

        // Same check when no accounts are loaded yet
        let emptyAccountsOrphan = AIWriterSectionProviderSummary.evaluate(
            configurations: [unassignedApple],
            assignments: AIProviderAccountAssignments(),
            accounts: [],
            appleIntelligenceAvailability: .available
        )
        #expect(emptyAccountsOrphan.hasActiveOnDeviceProvider == false)

        // Cloud default + explicit account assignment to Apple Intelligence IS active
        var assignedToApple = AIProviderAccountAssignments()
        assignedToApple.assign(providerID: unassignedApple.id, toAccountID: account.id)
        let assignedSummary = AIWriterSectionProviderSummary.evaluate(
            configurations: [cloudDefault, unassignedApple],
            assignments: assignedToApple,
            accounts: [account],
            appleIntelligenceAvailability: .available
        )
        #expect(assignedSummary.hasActiveOnDeviceProvider == true)

        // Default Apple Intelligence overridden by cloud for every account is NOT active
        let defaultApple = AIProviderConfiguration.appleIntelligence(isEnabled: true, isDefault: true)
        var assignedToCloud = AIProviderAccountAssignments()
        assignedToCloud.assign(providerID: cloudDefault.id, toAccountID: account.id)
        let overriddenSummary = AIWriterSectionProviderSummary.evaluate(
            configurations: [defaultApple, cloudDefault],
            assignments: assignedToCloud,
            accounts: [account],
            appleIntelligenceAvailability: .available
        )
        #expect(overriddenSummary.hasActiveOnDeviceProvider == false)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "AIWriterSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
