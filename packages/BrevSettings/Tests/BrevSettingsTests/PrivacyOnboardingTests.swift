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

    @Test("external per-account AI override blocks granting global AI consent under on-device prompt")
    func externalAccountOverrideBlocksGlobalAIConsent() throws {
        let (defaults, suite) = try makeDefaults("external-override-block")
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsPersistenceStore(defaults: defaults)
        let cloud = try #require(AIProviderConfiguration(
            id: AIProviderID("cloud-openai"),
            kind: .openAICompatible,
            displayName: "OpenAI",
            endpointURL: URL(string: "https://api.openai.com/v1"),
            modelID: "gpt-4.1-mini",
            isEnabled: true,
            isDefault: false,
            assignedAccountID: "acct-work"
        ))
        try store.saveAIProviderConfigurations([cloud])
        var assignments = AIProviderAccountAssignments()
        assignments.assign(providerID: cloud.id, toAccountID: "acct-work")
        try store.saveAIProviderAssignments(assignments)
        AIWriterSettings(isEnabled: false, consentGiven: false, proactiveOnDeviceTriageEnabled: false).save(to: defaults)

        #expect(PrivacyOnboardingChoices.blocksOnDeviceAIOptInDueToExternalAccountRoutes(in: store))

        let initial = PrivacyOnboardingChoices.load(from: store, appleIntelligenceAvailability: .available)
        var draft = initial
        draft.onDeviceAIEnabled = true
        draft.proactiveOnDeviceTriageEnabled = true

        let result = draft.apply(
            to: store,
            relativeTo: initial,
            appleIntelligenceAvailability: .available
        )

        #expect(!result.aiConfigurationChanged)
        #expect(!store.aiWriterSettings().isEnabled)
        #expect(!store.aiWriterSettings().consentGiven)
        #expect(!store.aiWriterSettings().proactiveOnDeviceTriageEnabled)
        #expect(try store.aiProviderConfigurations() == [cloud])
    }

    @Test("opting out of Apple Intelligence restores previously displaced default AI provider")
    func optingOutRestoresDisplacedDefaultProvider() throws {
        let (defaults, suite) = try makeDefaults("restore-displaced-default")
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsPersistenceStore(defaults: defaults)
        let ollama = try #require(AIProviderConfiguration(
            id: AIProviderID("local-ollama"),
            kind: .ollamaLocal,
            displayName: "Ollama",
            endpointURL: URL(string: "http://localhost:11434/v1"),
            modelID: "llama3.2",
            isEnabled: true,
            isDefault: true,
            assignedAccountID: nil
        ))
        try store.saveAIProviderConfigurations([ollama])
        AIWriterSettings(isEnabled: true, consentGiven: true, proactiveOnDeviceTriageEnabled: false).save(to: defaults)

        let beforeEnable = PrivacyOnboardingChoices.load(from: store, appleIntelligenceAvailability: .available)
        #expect(!beforeEnable.onDeviceAIEnabled)

        var enableDraft = beforeEnable
        enableDraft.onDeviceAIEnabled = true
        enableDraft.apply(to: store, relativeTo: beforeEnable, appleIntelligenceAvailability: .available)

        let configsAfterEnable = try store.aiProviderConfigurations()
        #expect(configsAfterEnable.first { $0.kind == .appleIntelligence }?.isDefault == true)
        #expect(configsAfterEnable.first { $0.id == ollama.id }?.isDefault == false)

        let beforeDisable = PrivacyOnboardingChoices.load(from: store, appleIntelligenceAvailability: .available)
        #expect(beforeDisable.onDeviceAIEnabled)

        var disableDraft = beforeDisable
        disableDraft.onDeviceAIEnabled = false
        disableDraft.apply(to: store, relativeTo: beforeDisable, appleIntelligenceAvailability: .available)

        let configsAfterDisable = try store.aiProviderConfigurations()
        #expect(configsAfterDisable.first { $0.kind == .appleIntelligence }?.isEnabled == false)
        #expect(configsAfterDisable.first { $0.kind == .appleIntelligence }?.isDefault == false)
        #expect(configsAfterDisable.first { $0.id == ollama.id }?.isDefault == true)
        #expect(store.aiWriterSettings().isAvailable)
    }

    @Test("opting out does not overwrite a newer explicit default chosen outside the walkthrough")
    func optingOutRespectsNewerExplicitDefault() throws {
        let (defaults, suite) = try makeDefaults("newer-explicit-default")
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsPersistenceStore(defaults: defaults)
        let ollama = try #require(AIProviderConfiguration(
            id: AIProviderID("local-ollama"),
            kind: .ollamaLocal,
            displayName: "Ollama",
            endpointURL: URL(string: "http://localhost:11434/v1"),
            modelID: "llama3.2",
            isEnabled: true,
            isDefault: true,
            assignedAccountID: nil
        ))
        let custom = try #require(AIProviderConfiguration(
            id: AIProviderID("custom-ai"),
            kind: .customOpenAICompatible,
            displayName: "Custom",
            endpointURL: URL(string: "https://llm.example.test/v1"),
            modelID: "model-x",
            isEnabled: true,
            isDefault: false,
            assignedAccountID: nil
        ))
        try store.saveAIProviderConfigurations([ollama, custom])
        AIWriterSettings(isEnabled: true, consentGiven: true, proactiveOnDeviceTriageEnabled: false).save(to: defaults)

        let beforeEnable = PrivacyOnboardingChoices.load(from: store, appleIntelligenceAvailability: .available)
        var enableDraft = beforeEnable
        enableDraft.onDeviceAIEnabled = true
        enableDraft.apply(to: store, relativeTo: beforeEnable, appleIntelligenceAvailability: .available)

        // User later switches default in AI Settings to `custom`, while assigning Apple Intelligence to one account.
        var updatedConfigs = try store.aiProviderConfigurations().map { config in
            var copy = config
            copy.isDefault = (config.id == custom.id)
            return copy
        }
        try store.saveAIProviderConfigurations(updatedConfigs)
        var assignments = AIProviderAccountAssignments()
        assignments.assign(providerID: AppleIntelligenceAIBackend.providerID, toAccountID: "acct-personal")
        try store.saveAIProviderAssignments(assignments)

        let beforeDisable = PrivacyOnboardingChoices.load(from: store, appleIntelligenceAvailability: .available)
        #expect(beforeDisable.onDeviceAIEnabled)

        var disableDraft = beforeDisable
        disableDraft.onDeviceAIEnabled = false
        disableDraft.apply(to: store, relativeTo: beforeDisable, appleIntelligenceAvailability: .available)

        updatedConfigs = try store.aiProviderConfigurations()
        #expect(updatedConfigs.first { $0.id == custom.id }?.isDefault == true)
        #expect(updatedConfigs.first { $0.id == ollama.id }?.isDefault == false)
        #expect(updatedConfigs.first { $0.kind == .appleIntelligence }?.isEnabled == false)
    }

    @Test("account-assigned non-default Apple Intelligence loads as enabled and disables without touching other routes")
    func accountAssignedAppleIntelligenceLoadsAndDisablesCleanly() throws {
        let (defaults, suite) = try makeDefaults("account-assigned-apple-ai")
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsPersistenceStore(defaults: defaults)
        let ollama = try #require(AIProviderConfiguration(
            id: AIProviderID("local-ollama"),
            kind: .ollamaLocal,
            displayName: "Ollama",
            endpointURL: URL(string: "http://localhost:11434/v1"),
            modelID: "llama3.2",
            isEnabled: true,
            isDefault: true,
            assignedAccountID: nil
        ))
        let apple = AIProviderConfiguration.appleIntelligence(
            isEnabled: true,
            isDefault: false,
            assignedAccountID: "acct-personal"
        )
        try store.saveAIProviderConfigurations([ollama, apple])
        var assignments = AIProviderAccountAssignments()
        assignments.assign(providerID: apple.id, toAccountID: "acct-personal")
        try store.saveAIProviderAssignments(assignments)
        AIWriterSettings(isEnabled: true, consentGiven: true, proactiveOnDeviceTriageEnabled: true).save(to: defaults)

        let loaded = PrivacyOnboardingChoices.load(from: store, appleIntelligenceAvailability: .available)
        #expect(loaded.onDeviceAIEnabled)
        #expect(loaded.proactiveOnDeviceTriageEnabled)

        var disableDraft = loaded
        disableDraft.onDeviceAIEnabled = false
        let result = disableDraft.apply(to: store, relativeTo: loaded, appleIntelligenceAvailability: .available)

        #expect(result.aiConfigurationChanged)
        let configs = try store.aiProviderConfigurations()
        #expect(configs.first { $0.kind == .appleIntelligence }?.isEnabled == false)
        #expect(configs.first { $0.id == ollama.id }?.isDefault == true)
        #expect(configs.first { $0.id == ollama.id }?.isEnabled == true)
        #expect(store.aiWriterSettings().isAvailable)
        #expect(!store.aiWriterSettings().proactiveOnDeviceTriageEnabled)
    }

    @Test("trusted-sender toggle respects rich HTML renderer gate and accurate tracking-pixel copy")
    func trustedSenderRespectsRichHTMLAndTrackingPixelState() throws {
        let (defaults, suite) = try makeDefaults("trusted-sender-gates")
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsPersistenceStore(defaults: defaults)
        var mailbox = MailboxViewSettings.defaults
        mailbox.useRichRenderer = false
        mailbox.allowRemoteContentForTrustedSenders = false
        mailbox.save(to: defaults)

        let initial = PrivacyOnboardingChoices.load(from: store, appleIntelligenceAvailability: .available)
        var draft = initial
        draft.allowRemoteContentForTrustedSenders = true
        draft.apply(to: store, relativeTo: initial, appleIntelligenceAvailability: .available)

        // With rich HTML rendering off, trusted-sender remote images stays untouched and rich HTML stays off.
        #expect(!store.mailboxViewSettings().useRichRenderer)
        #expect(!store.mailboxViewSettings().allowRemoteContentForTrustedSenders)

        let plainTextSubtitle = PrivacyOnboardingCopy.trustedSendersSubtitle(
            useRichRenderer: false,
            stripTrackingPixels: true
        )
        #expect(plainTextSubtitle.contains("rich HTML reader"))

        let strippedSubtitle = PrivacyOnboardingCopy.trustedSendersSubtitle(
            useRichRenderer: true,
            stripTrackingPixels: true
        )
        #expect(strippedSubtitle.contains("tracking-pixel removal stays on"))

        let unstrippedSubtitle = PrivacyOnboardingCopy.trustedSendersSubtitle(
            useRichRenderer: true,
            stripTrackingPixels: false
        )
        #expect(!unstrippedSubtitle.contains("tracking-pixel removal stays on"))
        #expect(unstrippedSubtitle.contains("Tracking-pixel removal is currently off"))
    }

    @Test("presentation policy blocks onboarding during active sign-in/restore and after failed restore of saved accounts")
    func presentationPolicySignInAndRestoreFailureGuards() {
        // Transient restore failure when saved accounts exist in AccountStore is NOT a fresh install.
        #expect(!PrivacyOnboardingPresentationPolicy.didStartWithoutAccounts(
            storedAccountBackendIdentifiers: ["imap"],
            visibleBackendIdentifiers: [],
            demoBackendIdentifier: "demo",
            accountRestoreErrorCount: 0,
            canRetrySessionRestore: true
        ))
        #expect(!PrivacyOnboardingPresentationPolicy.didStartWithoutAccounts(
            storedAccountBackendIdentifiers: [],
            visibleBackendIdentifiers: [],
            demoBackendIdentifier: "demo",
            accountRestoreErrorCount: 1,
            canRetrySessionRestore: false
        ))
        // Demo-only records or zero saved accounts with zero restore errors IS a fresh install.
        #expect(PrivacyOnboardingPresentationPolicy.didStartWithoutAccounts(
            storedAccountBackendIdentifiers: ["demo"],
            visibleBackendIdentifiers: [],
            demoBackendIdentifier: "demo",
            accountRestoreErrorCount: 0,
            canRetrySessionRestore: false
        ))
        #expect(PrivacyOnboardingPresentationPolicy.didStartWithoutAccounts(
            storedAccountBackendIdentifiers: [],
            visibleBackendIdentifiers: [],
            demoBackendIdentifier: "demo",
            accountRestoreErrorCount: 0,
            canRetrySessionRestore: false
        ))

        // In-flight sign-in must defer onboarding until `finishSignIn` settles `pendingInitialMailboxSelectionAccountID`.
        #expect(!PrivacyOnboardingPresentationPolicy.shouldPresentAfterFirstAccountSetup(
            hasCompletedOnboarding: false,
            isSuppressedByEnvironment: false,
            isDemoSession: false,
            didStartWithoutAccounts: true,
            hasVisibleRealAccount: true,
            isSigningIn: true,
            isRestoringSession: false,
            hasPendingInitialMailboxSelection: false,
            hasOtherModalPresented: false,
            hasExistingCustomizedSettings: false
        ))
        #expect(!PrivacyOnboardingPresentationPolicy.shouldPresentAfterFirstAccountSetup(
            hasCompletedOnboarding: false,
            isSuppressedByEnvironment: false,
            isDemoSession: false,
            didStartWithoutAccounts: true,
            hasVisibleRealAccount: true,
            isSigningIn: false,
            isRestoringSession: true,
            hasPendingInitialMailboxSelection: false,
            hasOtherModalPresented: false,
            hasExistingCustomizedSettings: false
        ))
    }
}
