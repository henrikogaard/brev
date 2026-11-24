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
import BrevAvatars
@testable import BrevSettings
import Foundation
import Testing

@Suite("Privacy onboarding choices and policy")
struct PrivacyOnboardingTests {
    private func makeDefaults(_ name: String) throws -> (defaults: UserDefaults, suite: String) {
        let suite = "PrivacyOnboardingTests-\(name)-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, suite)
    }

    @Test("fresh install keeps every opt-in choice off and onboarding incomplete")
    func freshInstallAllOffDefaults() throws {
        let (defaults, suite) = try makeDefaults("defaults")
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsPersistenceStore(defaults: defaults)
        let onboarding = store.privacyOnboardingSettings()
        let choices = PrivacyOnboardingChoices.load(
            from: store,
            appleIntelligenceAvailability: .available
        )

        #expect(onboarding == .defaults)
        #expect(!onboarding.hasCompletedOnboarding)
        #expect(choices == .allOff)
        #expect(!PrivacyOnboardingChoices.hasExistingCustomizedSettings(in: store))
    }

    @Test("Keep defaults leaves every opt-in setting off and marks onboarding completed")
    func keepDefaultsLeavesAllOptInsOff() throws {
        let (defaults, suite) = try makeDefaults("keep-defaults")
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsPersistenceStore(defaults: defaults)
        PrivacyOnboardingChoices.keepPrivacyDefaults(in: store)

        #expect(store.privacyOnboardingSettings().hasCompletedOnboarding)
        #expect(store.avatarPrivacySettings() == .initialsOnly)
        #expect(!store.mailboxViewSettings().allowRemoteContent)
        #expect(!store.mailboxViewSettings().allowRemoteContentForTrustedSenders)
        #expect(store.mailboxViewSettings().stripTrackingPixels)
        #expect(!store.preferenceSyncSettings().isICloudSyncEnabled)
        #expect(!store.notificationSettings().backgroundMailEnabled)
        #expect(!store.backgroundIndexingSettings().isEnabled)
        #expect(!store.aiWriterSettings().isEnabled)
        #expect(!store.aiWriterSettings().consentGiven)
        #expect(!store.aiWriterSettings().proactiveOnDeviceTriageEnabled)
        #expect((try? store.aiProviderConfigurations())?.isEmpty ?? true)
    }

    @Test("Save choices applies only chosen opt-ins and preserves privacy invariants")
    func saveChoicesAppliesOnlySelectedOptIns() throws {
        let (defaults, suite) = try makeDefaults("save-selected")
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsPersistenceStore(defaults: defaults)
        let initial = PrivacyOnboardingChoices.load(
            from: store,
            appleIntelligenceAvailability: .available
        )
        var draft = initial
        draft.useDomainAvatars = true
        draft.allowRemoteContentForTrustedSenders = true
        draft.backgroundIndexingEnabled = true
        draft.onDeviceAIEnabled = true
        draft.proactiveOnDeviceTriageEnabled = true

        let result = draft.apply(
            to: store,
            relativeTo: initial,
            appleIntelligenceAvailability: .available
        )

        #expect(store.privacyOnboardingSettings().hasCompletedOnboarding)
        #expect(result.aiConfigurationChanged)
        #expect(result.updatedAvatarPreferences == AvatarPreferences(
            useContacts: false,
            useGravatar: false,
            useBIMI: true,
            useFavicon: true
        ))

        let avatars = store.avatarPrivacySettings()
        #expect(avatars.useBIMI)
        #expect(avatars.useFavicon)
        #expect(!avatars.useGravatar)
        #expect(!avatars.useContacts)

        let mailbox = store.mailboxViewSettings()
        #expect(mailbox.allowRemoteContentForTrustedSenders)
        #expect(!mailbox.allowRemoteContent)
        #expect(mailbox.stripTrackingPixels)

        // Unselected options remain strictly off.
        #expect(!store.preferenceSyncSettings().isICloudSyncEnabled)
        #expect(!store.notificationSettings().backgroundMailEnabled)

        // Background indexing enabled with conservative Wi-Fi/power-friendly defaults intact.
        let indexing = store.backgroundIndexingSettings()
        #expect(indexing.isEnabled)
        #expect(indexing.requireUnmeteredNetworkAndPower)
        #expect(indexing.indexAttachments)

        // On-device Apple Intelligence enabled cleanly with zero cloud/BYOK providers.
        let aiWriter = store.aiWriterSettings()
        #expect(aiWriter.isEnabled)
        #expect(aiWriter.consentGiven)
        #expect(aiWriter.proactiveOnDeviceTriageEnabled)
        let configs = try store.aiProviderConfigurations()
        #expect(configs.count == 1)
        #expect(configs.first?.kind == .appleIntelligence)
        #expect(configs.first?.isEnabled == true)
        #expect(configs.first?.isDefault == true)
    }

    @Test("reopening from Settings reflects current values, preserves untouched granular settings, and Cancel discards edits")
    func reopenFromSettingsPreservesUntouchedAndCancelDiscards() throws {
        let (defaults, suite) = try makeDefaults("reopen-settings")
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsPersistenceStore(defaults: defaults)
        // User previously enabled only BIMI (not favicon), plus iCloud sync and a custom BYOK AI provider.
        AvatarPrivacySettings(useContacts: true, useGravatar: false, useBIMI: true, useFavicon: false).save(to: defaults)
        PreferenceSyncSettings(isICloudSyncEnabled: true).save(to: defaults)
        let byok = try #require(AIProviderConfiguration(
            id: AIProviderID("custom-byok"),
            kind: .ollamaLocal,
            displayName: "Ollama",
            endpointURL: URL(string: "http://localhost:11434/v1"),
            modelID: "llama3.2",
            isEnabled: true,
            isDefault: true,
            assignedAccountID: nil
        ))
        try store.saveAIProviderConfigurations([byok])
        AIWriterSettings(isEnabled: true, consentGiven: true, proactiveOnDeviceTriageEnabled: false).save(to: defaults)

        let loaded = PrivacyOnboardingChoices.load(
            from: store,
            appleIntelligenceAvailability: .available
        )
        #expect(loaded.useDomainAvatars)
        #expect(!loaded.useGravatar)
        #expect(loaded.iCloudPreferenceSyncEnabled)
        #expect(!loaded.onDeviceAIEnabled)

        // Simulate Cancel: mutate draft locally and drop it without calling apply.
        var cancelledDraft = loaded
        cancelledDraft.useGravatar = true
        cancelledDraft.iCloudPreferenceSyncEnabled = false
        cancelledDraft.allowRemoteContentForTrustedSenders = true
        #expect(store.preferenceSyncSettings().isICloudSyncEnabled)
        #expect(!store.avatarPrivacySettings().useGravatar)
        #expect(!store.mailboxViewSettings().allowRemoteContentForTrustedSenders)

        // Now save only a single explicit change (trusted-sender remote images).
        var editedDraft = loaded
        editedDraft.allowRemoteContentForTrustedSenders = true
        let result = editedDraft.apply(
            to: store,
            relativeTo: loaded,
            appleIntelligenceAvailability: .available
        )

        #expect(result.updatedAvatarPreferences == nil)
        #expect(!result.aiConfigurationChanged)
        #expect(store.mailboxViewSettings().allowRemoteContentForTrustedSenders)
        // Granular avatar choices (useContacts=true, useBIMI=true, useFavicon=false) stay intact.
        #expect(store.avatarPrivacySettings() == AvatarPrivacySettings(
            useContacts: true,
            useGravatar: false,
            useBIMI: true,
            useFavicon: false
        ))
        // Untouched BYOK AI configuration stays intact.
        #expect(try store.aiProviderConfigurations() == [byok])
    }

    @Test("unavailable on-device AI cannot be enabled via onboarding")
    func unavailableOnDeviceAIIsBlocked() throws {
        let (defaults, suite) = try makeDefaults("unavailable-ai")
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsPersistenceStore(defaults: defaults)
        let initial = PrivacyOnboardingChoices.load(
            from: store,
            appleIntelligenceAvailability: .deviceNotEligible
        )
        var draft = initial
        draft.onDeviceAIEnabled = true
        draft.proactiveOnDeviceTriageEnabled = true

        let result = draft.apply(
            to: store,
            relativeTo: initial,
            appleIntelligenceAvailability: .deviceNotEligible
        )

        #expect(!result.aiConfigurationChanged)
        #expect(!store.aiWriterSettings().isEnabled)
        #expect(!store.aiWriterSettings().proactiveOnDeviceTriageEnabled)
        #expect((try? store.aiProviderConfigurations())?.isEmpty ?? true)
    }

    @Test("disabling on-device AI during Settings review disables Apple Intelligence and proactive triage")
    func disablingOnDeviceAIClearsProactiveTriage() throws {
        let (defaults, suite) = try makeDefaults("disable-ai")
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsPersistenceStore(defaults: defaults)
        let first = PrivacyOnboardingChoices.allOff
        var enableDraft = first
        enableDraft.onDeviceAIEnabled = true
        enableDraft.proactiveOnDeviceTriageEnabled = true
        enableDraft.apply(to: store, relativeTo: first, appleIntelligenceAvailability: .available)

        let loaded = PrivacyOnboardingChoices.load(from: store, appleIntelligenceAvailability: .available)
        #expect(loaded.onDeviceAIEnabled)
        #expect(loaded.proactiveOnDeviceTriageEnabled)

        var disableDraft = loaded
        disableDraft.onDeviceAIEnabled = false
        let result = disableDraft.apply(to: store, relativeTo: loaded, appleIntelligenceAvailability: .available)

        #expect(result.aiConfigurationChanged)
        #expect(!store.aiWriterSettings().isEnabled)
        #expect(!store.aiWriterSettings().proactiveOnDeviceTriageEnabled)
        let appleConfig = try store.aiProviderConfigurations().first { $0.kind == .appleIntelligence }
        #expect(appleConfig?.isEnabled == false)
    }

    @Test("completion flag stays device-local: excluded from iCloud sync allowlist and portable backups")
    func completionFlagIsDeviceLocalOnly() throws {
        #expect(!PreferenceSyncAllowlist.keys.contains(PrivacyOnboardingSettings.Key.hasCompletedOnboarding))
        #expect(!SettingsBackupPayload.knownKeys.contains("privacyOnboarding"))
        #expect(!SettingsBackupPayload.knownKeys.contains(PrivacyOnboardingSettings.Key.hasCompletedOnboarding))

        let (sourceDefaults, sourceSuite) = try makeDefaults("backup-src")
        let (destDefaults, destSuite) = try makeDefaults("backup-dst")
        defer {
            sourceDefaults.removePersistentDomain(forName: sourceSuite)
            destDefaults.removePersistentDomain(forName: destSuite)
        }

        let sourceStore = SettingsPersistenceStore(defaults: sourceDefaults)
        let destStore = SettingsPersistenceStore(defaults: destDefaults)
        PrivacyOnboardingSettings(hasCompletedOnboarding: true).save(to: sourceDefaults)

        let payload = SettingsBackupCodec.export(from: sourceStore)
        SettingsBackupCodec.apply(payload, to: destStore, mode: .replace)

        #expect(!destStore.privacyOnboardingSettings().hasCompletedOnboarding)
    }

    @Test("presentation policy suppresses demo, mock, test, completed, and existing-user sessions")
    func presentationPolicySuppressionRules() throws {
        let (defaults, suite) = try makeDefaults("policy")
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(PrivacyOnboardingPresentationPolicy.isSuppressedByEnvironment(
            environment: ["BREV_USE_MOCK": "1"],
            arguments: [],
            defaults: defaults,
            isDeveloperBuild: true
        ))
        #expect(PrivacyOnboardingPresentationPolicy.isSuppressedByEnvironment(
            environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"],
            arguments: [],
            defaults: defaults,
            isDeveloperBuild: false
        ))
        #expect(PrivacyOnboardingPresentationPolicy.isSuppressedByEnvironment(
            environment: ["RECORD_SNAPSHOTS": "YES"],
            arguments: [],
            defaults: defaults,
            isDeveloperBuild: false
        ))
        #expect(PrivacyOnboardingPresentationPolicy.isSuppressedByEnvironment(
            environment: [:],
            arguments: ["-UITesting"],
            defaults: defaults,
            isDeveloperBuild: false
        ))
        #expect(!PrivacyOnboardingPresentationPolicy.isSuppressedByEnvironment(
            environment: [:],
            arguments: [],
            defaults: defaults,
            isDeveloperBuild: false
        ))

        // Happy path: brand-new user just added their first real account.
        #expect(PrivacyOnboardingPresentationPolicy.shouldPresentAfterFirstAccountSetup(
            hasCompletedOnboarding: false,
            isSuppressedByEnvironment: false,
            isDemoSession: false,
            didStartWithoutAccounts: true,
            hasVisibleRealAccount: true,
            hasPendingInitialMailboxSelection: false,
            hasOtherModalPresented: false,
            hasExistingCustomizedSettings: false
        ))

        // Suppressed when already completed.
        #expect(!PrivacyOnboardingPresentationPolicy.shouldPresentAfterFirstAccountSetup(
            hasCompletedOnboarding: true,
            isSuppressedByEnvironment: false,
            isDemoSession: false,
            didStartWithoutAccounts: true,
            hasVisibleRealAccount: true,
            hasPendingInitialMailboxSelection: false,
            hasOtherModalPresented: false,
            hasExistingCustomizedSettings: false
        ))

        // Suppressed in demo session.
        #expect(!PrivacyOnboardingPresentationPolicy.shouldPresentAfterFirstAccountSetup(
            hasCompletedOnboarding: false,
            isSuppressedByEnvironment: false,
            isDemoSession: true,
            didStartWithoutAccounts: true,
            hasVisibleRealAccount: false,
            hasPendingInitialMailboxSelection: false,
            hasOtherModalPresented: false,
            hasExistingCustomizedSettings: false
        ))

        // Suppressed for existing users who already had accounts restored on launch.
        #expect(!PrivacyOnboardingPresentationPolicy.shouldPresentAfterFirstAccountSetup(
            hasCompletedOnboarding: false,
            isSuppressedByEnvironment: false,
            isDemoSession: false,
            didStartWithoutAccounts: false,
            hasVisibleRealAccount: true,
            hasPendingInitialMailboxSelection: false,
            hasOtherModalPresented: false,
            hasExistingCustomizedSettings: false
        ))

        // Suppressed while InitialMailboxSelectionSheet or another modal is pending.
        #expect(!PrivacyOnboardingPresentationPolicy.shouldPresentAfterFirstAccountSetup(
            hasCompletedOnboarding: false,
            isSuppressedByEnvironment: false,
            isDemoSession: false,
            didStartWithoutAccounts: true,
            hasVisibleRealAccount: true,
            hasPendingInitialMailboxSelection: true,
            hasOtherModalPresented: false,
            hasExistingCustomizedSettings: false
        ))
        #expect(!PrivacyOnboardingPresentationPolicy.shouldPresentAfterFirstAccountSetup(
            hasCompletedOnboarding: false,
            isSuppressedByEnvironment: false,
            isDemoSession: false,
            didStartWithoutAccounts: true,
            hasVisibleRealAccount: true,
            hasPendingInitialMailboxSelection: false,
            hasOtherModalPresented: true,
            hasExistingCustomizedSettings: false
        ))

        // Suppressed when existing user already customized privacy/convenience settings.
        #expect(!PrivacyOnboardingPresentationPolicy.shouldPresentAfterFirstAccountSetup(
            hasCompletedOnboarding: false,
            isSuppressedByEnvironment: false,
            isDemoSession: false,
            didStartWithoutAccounts: true,
            hasVisibleRealAccount: true,
            hasPendingInitialMailboxSelection: false,
            hasOtherModalPresented: false,
            hasExistingCustomizedSettings: true
        ))
    }

    @Test("Settings Search indexes the Review Privacy & Convenience Choices entry")
    func settingsSearchFindsPrivacyWalkthrough() {
        let results = SettingsSearchResult.results(
            for: "Convenience Choices",
            sections: SettingsSection.allCases
        )
        #expect(results.contains {
            $0.section == .privacy && $0.title == "Review Privacy & Convenience Choices…"
        })
    }
}
