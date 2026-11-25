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
            "Install a compatible local inference helper (such as llama-cli) to run automatic summaries with a downloaded model.",
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

    @Test("provider summary gates downloaded-model proactive triage on local inference runtime readiness")
    func providerSummaryGatesDownloadedModelOnInferenceRuntimeReadiness() {
        let account = BrevAccount(id: "acct-1", displayName: "Work", emailAddress: "work@example.org")
        let secondAccount = BrevAccount(id: "acct-2", displayName: "Personal", emailAddress: "me@example.org")
        let downloadedDefault = AIProviderConfiguration.onDeviceDownloadedModel(
            modelID: LocalModelCatalog.defaultModelID,
            isEnabled: true,
            isDefault: true
        )
        let enabledSettings = AIWriterSettings(
            isEnabled: true,
            consentGiven: true,
            proactiveOnDeviceTriageEnabled: false
        )

        // Installed local inference helper makes the downloaded-model route usable for proactive triage.
        let readySummary = AIWriterSectionProviderSummary.evaluate(
            configurations: [downloadedDefault],
            assignments: AIProviderAccountAssignments(),
            accounts: [account],
            appleIntelligenceAvailability: .appleIntelligenceNotEnabled,
            isLocalInferenceRuntimeInstalled: true
        )
        #expect(readySummary.hasActiveOnDeviceProvider == true)
        #expect(readySummary.hasDownloadedModelMissingRuntime == false)
        #expect(readySummary.proactiveStatusNote(for: enabledSettings) == nil)

        // Missing local inference helper disables proactive triage and surfaces the localized prerequisite note.
        let missingRuntimeSummary = AIWriterSectionProviderSummary.evaluate(
            configurations: [downloadedDefault],
            assignments: AIProviderAccountAssignments(),
            accounts: [account],
            appleIntelligenceAvailability: .appleIntelligenceNotEnabled,
            isLocalInferenceRuntimeInstalled: false
        )
        #expect(missingRuntimeSummary.hasActiveOnDeviceProvider == false)
        #expect(missingRuntimeSummary.hasDownloadedModelMissingRuntime == true)
        let expectedNote = String(
            localized: "Install a compatible local inference helper (such as llama-cli) to run automatic summaries with a downloaded model.",
            bundle: PrivacySection.resourceBundle
        )
        #expect(missingRuntimeSummary.proactiveStatusNote(for: enabledSettings) == expectedNote)

        // When another account has a usable Apple Intelligence override, proactive triage stays enabled.
        let appleOverride = AIProviderConfiguration.appleIntelligence(isEnabled: true, isDefault: false)
        var assignments = AIProviderAccountAssignments()
        assignments.assign(providerID: appleOverride.id, toAccountID: secondAccount.id)
        let mixedSummary = AIWriterSectionProviderSummary.evaluate(
            configurations: [downloadedDefault, appleOverride],
            assignments: assignments,
            accounts: [account, secondAccount],
            appleIntelligenceAvailability: .available,
            isLocalInferenceRuntimeInstalled: false
        )
        #expect(mixedSummary.hasActiveOnDeviceProvider == true)
        #expect(mixedSummary.hasDownloadedModelMissingRuntime == false)

        // Unassigned non-default downloaded model does not trigger the missing-runtime note.
        let orphanDownloaded = AIProviderConfiguration.onDeviceDownloadedModel(
            modelID: LocalModelCatalog.defaultModelID,
            isEnabled: true,
            isDefault: false
        )
        let orphanSummary = AIWriterSectionProviderSummary.evaluate(
            configurations: [orphanDownloaded],
            assignments: AIProviderAccountAssignments(),
            accounts: [account],
            appleIntelligenceAvailability: .appleIntelligenceNotEnabled,
            isLocalInferenceRuntimeInstalled: false
        )
        #expect(orphanSummary.hasActiveOnDeviceProvider == false)
        #expect(orphanSummary.hasDownloadedModelMissingRuntime == false)
    }

    @Test("already-enabled proactive triage stays visible and opt-outable when downloaded-model helper is missing")
    func missingHelperAllowsOptOutWhileBlockingOptIn() {
        let account = BrevAccount(id: "acct-1", displayName: "Work", emailAddress: "work@example.org")
        let downloadedDefault = AIProviderConfiguration.onDeviceDownloadedModel(
            modelID: LocalModelCatalog.defaultModelID,
            isEnabled: true,
            isDefault: true
        )
        let summary = AIWriterSectionProviderSummary.evaluate(
            configurations: [downloadedDefault],
            assignments: AIProviderAccountAssignments(),
            accounts: [account],
            appleIntelligenceAvailability: .appleIntelligenceNotEnabled,
            isLocalInferenceRuntimeInstalled: false
        )

        // Previously enabled preference remains visible as ON and interactive so the user can opt out.
        var pausedEnabled = AIWriterSettings(
            isEnabled: true,
            consentGiven: true,
            proactiveOnDeviceTriageEnabled: true
        )
        #expect(summary.proactiveTriageSwitchValue(for: pausedEnabled) == true)
        #expect(summary.isProactiveTriageSwitchInteractive(for: pausedEnabled) == true)
        #expect(summary.proactiveStatusNote(for: pausedEnabled) != nil)

        // Opting OUT succeeds and persists false; afterward, opting back IN is blocked while helper is absent.
        #expect(summary.applyProactiveTriageToggle(false, to: &pausedEnabled) == true)
        #expect(pausedEnabled.proactiveOnDeviceTriageEnabled == false)
        #expect(summary.proactiveTriageSwitchValue(for: pausedEnabled) == false)
        #expect(summary.isProactiveTriageSwitchInteractive(for: pausedEnabled) == false)

        #expect(summary.applyProactiveTriageToggle(true, to: &pausedEnabled) == false)
        #expect(pausedEnabled.proactiveOnDeviceTriageEnabled == false)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "AIWriterSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
