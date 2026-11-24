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

@Suite("AI provider settings")
struct AIProviderSettingsTests {
    @Test("cancelling Add provider restores an existing selection")
    func cancellingAddProviderRestoresExistingSelection() {
        let first = AIProviderID("first")
        let second = AIProviderID("second")

        #expect(
            AIProviderEditorPresentation.selectionAfterCancellingAdd(
                selectedProviderID: nil,
                configuredProviderIDs: [first, second]
            ) == first
        )
    }

    @Test("draft validation exposes actionable fields and transparency preview")
    func draftValidationExposesActionableFieldsAndTransparencyPreview() {
        var draft = AIProviderSettingsDraft.new(kind: .customOpenAICompatible)
        draft.displayName = "Private Gateway"
        draft.endpointURLString = "https://ai.example.test/v1"
        draft.modelID = "mail-model"

        #expect(draft.validationIssues.isEmpty)
        #expect(draft.transparencyPreview == "Sent to: Private Gateway (ai.example.test)")
        #expect(draft.apiKeyStatusText == "API key required for hosted providers.")

        draft.displayName = " "
        draft.endpointURLString = "file:///tmp/model"
        draft.modelID = ""

        #expect(draft.validationIssues == [
            .displayNameRequired,
            .httpEndpointRequired,
            .modelIDRequired
        ])
    }

    @Test("saved API keys are represented without exposing the raw key")
    func savedAPIKeysAreRepresentedWithoutExposingRawKey() throws {
        let rawKey = "sk-test-never-render"
        let configuration = try #require(AIProviderConfiguration(
            id: AIProviderID("hosted-provider"),
            kind: .openAICompatible,
            displayName: "OpenAI",
            endpointURL: URL(string: "https://api.openai.com/v1"),
            modelID: "gpt-4.1-mini",
            isEnabled: true,
            isDefault: true,
            assignedAccountID: nil
        ))
        let draft = AIProviderSettingsDraft(
            configuration: configuration,
            hasSavedAPIKey: true
        )

        #expect(draft.apiKeyStatusText == "Saved in Keychain.")
        #expect(draft.redactedKeyPresentation == String(localized: "savedInKeychain.badge", bundle: .module))
        #expect(draft.apiKeyStatusText.contains(rawKey) == false)
        #expect(draft.redactedKeyPresentation.contains(rawKey) == false)
    }

    @Test("saving provider writes metadata to defaults and keys to secret store only")
    func savingProviderWritesMetadataToDefaultsAndKeysToSecretStoreOnly() async throws {
        let defaults = try Self.makeDefaults()
        let store = SettingsPersistenceStore(defaults: defaults)
        let secrets = InMemoryProviderSecretStore()
        var draft = AIProviderSettingsDraft.new(kind: .customOpenAICompatible)
        draft.displayName = "Private Gateway"
        draft.endpointURLString = "https://ai.example.test/v1"
        draft.modelID = "mail-model"
        draft.pendingAPIKey = "sk-test-secret"

        let saved = try await AIProviderSettingsPersistence.save(
            draft,
            settingsStore: store,
            secretStore: secrets
        )

        #expect(saved.displayName == "Private Gateway")
        #expect(try store.aiProviderConfigurations() == [saved])
        #expect(await secrets.apiKeyValue(for: draft.id) == "sk-test-secret")
        #expect(defaults.dictionaryRepresentation().description.contains("sk-test-secret") == false)
    }

    @Test("saving an account assignment persists the provider route locally")
    func savingAccountAssignmentPersistsProviderRouteLocally() async throws {
        let defaults = try Self.makeDefaults()
        let store = SettingsPersistenceStore(defaults: defaults)
        let secrets = InMemoryProviderSecretStore()
        var draft = AIProviderSettingsDraft.new(kind: .customOpenAICompatible)
        draft.displayName = "Work AI"
        draft.endpointURLString = "https://ai.example.test/v1"
        draft.modelID = "mail-model"
        draft.assignedAccountID = "work-account"
        draft.pendingAPIKey = "sk-test-secret"

        let saved = try await AIProviderSettingsPersistence.save(
            draft,
            settingsStore: store,
            secretStore: secrets
        )

        #expect(
            try store.aiProviderAssignments().providerID(forAccountID: "work-account") == saved.id
        )
    }

    @Test("deleting provider removes metadata and deletes the Keychain secret")
    func deletingProviderRemovesMetadataAndDeletesKeychainSecret() async throws {
        let defaults = try Self.makeDefaults()
        let store = SettingsPersistenceStore(defaults: defaults)
        let secrets = InMemoryProviderSecretStore()
        var draft = AIProviderSettingsDraft.new(kind: .openAICompatible)
        draft.displayName = "OpenAI"
        draft.endpointURLString = "https://api.openai.com/v1"
        draft.modelID = "gpt-4.1-mini"
        draft.pendingAPIKey = "sk-test-secret"
        _ = try await AIProviderSettingsPersistence.save(
            draft,
            settingsStore: store,
            secretStore: secrets
        )

        try await AIProviderSettingsPersistence.delete(
            providerID: draft.id,
            settingsStore: store,
            secretStore: secrets
        )

        #expect(try store.aiProviderConfigurations().isEmpty)
        #expect(await secrets.apiKeyValue(for: draft.id) == nil)
    }

    @Test("deleting provider prunes account assignments")
    func deletingProviderPrunesAccountAssignments() async throws {
        let defaults = try Self.makeDefaults()
        let store = SettingsPersistenceStore(defaults: defaults)
        let secrets = InMemoryProviderSecretStore()
        var draft = AIProviderSettingsDraft.new(kind: .customOpenAICompatible)
        draft.displayName = "Private Gateway"
        draft.endpointURLString = "https://ai.example.test/v1"
        draft.modelID = "mail-model"
        _ = try await AIProviderSettingsPersistence.save(
            draft,
            settingsStore: store,
            secretStore: secrets
        )
        var assignments = AIProviderAccountAssignments()
        assignments.assign(providerID: draft.id, toAccountID: "account-1")
        let assignmentStore = AIProviderAccountAssignmentStore(defaults: defaults)
        try assignmentStore.save(assignments)

        try await AIProviderSettingsPersistence.delete(
            providerID: draft.id,
            settingsStore: store,
            secretStore: secrets
        )

        #expect(try assignmentStore.load().providerID(forAccountID: "account-1") == nil)
    }

    @Test("Ollama preset has local defaults and requires no API key")
    func ollamaPresetHasLocalDefaultsAndRequiresNoAPIKey() {
        let draft = AIProviderSettingsDraft.new(kind: .ollamaLocal)

        #expect(draft.displayName == "Ollama")
        #expect(draft.endpointURLString == "http://localhost:11434/v1")
        #expect(draft.requiresAPIKey == false)
        #expect(draft.apiKeyStatusText == "No API key required for local providers.")
        #expect(draft.transparencyPreview == "Sent to: Ollama (localhost)")
    }

    @Test("saving Ollama preset stores no key and clears stale secrets")
    func savingOllamaPresetStoresNoKeyAndClearsStaleSecrets() async throws {
        let defaults = try Self.makeDefaults()
        let store = SettingsPersistenceStore(defaults: defaults)
        let secrets = InMemoryProviderSecretStore()
        var draft = AIProviderSettingsDraft.new(kind: .ollamaLocal)
        draft.modelID = "llama3.1"
        draft.isEnabled = true
        try await secrets.setAPIKey("stale-hosted-key", for: draft.id)

        let saved = try await AIProviderSettingsPersistence.save(
            draft,
            settingsStore: store,
            secretStore: secrets
        )

        #expect(saved.kind == .ollamaLocal)
        #expect(saved.endpointURL.absoluteString == "http://localhost:11434/v1")
        #expect(saved.requiresAPIKey == false)
        #expect(await secrets.apiKeyValue(for: draft.id) == nil)
    }

    @Test("Ollama caveat explains localhost platform behavior")
    func ollamaCaveatExplainsLocalhostPlatformBehavior() {
        let draft = AIProviderSettingsDraft.new(kind: .ollamaLocal)

        #expect(draft.platformCaveatMessage?.contains("macOS") == true)
        #expect(draft.platformCaveatMessage?.contains("iOS") == true)
        #expect(draft.platformCaveatMessage?.contains("localhost") == true)
    }

    @Test("plaintext remote endpoints show a credential and content warning")
    func plaintextRemoteEndpointsShowCredentialAndContentWarning() {
        var draft = AIProviderSettingsDraft.new(kind: .customOpenAICompatible)
        draft.endpointURLString = "http://ai.example.test/v1"

        #expect(draft.transportWarning?.contains("API key") == true)
        #expect(draft.transportWarning?.contains("message content") == true)

        draft.endpointURLString = "http://localhost:11434/v1"

        #expect(draft.transportWarning == nil)
    }

    @Test("Apple Intelligence draft requires no API key or URL, reports On this Mac, and preserves AI off-by-default")
    func appleIntelligenceDraftRequiresNoKeyAndPreservesDefaultOff() async throws {
        let defaults = try Self.makeDefaults()
        let store = SettingsPersistenceStore(defaults: defaults)
        let secrets = InMemoryProviderSecretStore()

        let draft = AIProviderSettingsDraft.new(kind: .appleIntelligence)
        #expect(draft.requiresAPIKey == false)
        #expect(draft.validationIssues.isEmpty)
        #expect(draft.transparencyPreview == OnDeviceAIPlatformLabel.transparencyLabel)
        #expect(draft.apiKeyStatusText.contains("no API key"))

        var enabledDraft = draft
        enabledDraft.isEnabled = true
        let saved = try await AIProviderSettingsPersistence.save(
            enabledDraft,
            settingsStore: store,
            secretStore: secrets
        )

        #expect(saved.kind == .appleIntelligence)
        #expect(saved.id == AppleIntelligenceAIBackend.providerID)
        #expect(saved.transparencyLabel == OnDeviceAIPlatformLabel.transparencyLabel)
        #expect(await secrets.apiKeyValue(for: saved.id) == nil)
        #expect(store.aiWriterSettings() == AIWriterSettings.defaults)
    }

    @Test("preset switching preserves hosted and Apple Intelligence profile identities")
    func presetSwitchingPreservesProfileIdentity() async throws {
        let defaults = try Self.makeDefaults()
        let store = SettingsPersistenceStore(defaults: defaults)
        let secrets = InMemoryProviderSecretStore()

        var hosted = AIProviderSettingsDraft.new(kind: .openAICompatible)
        hosted.displayName = "Work OpenAI"
        hosted.pendingAPIKey = "sk-test-secret"
        hosted.isEnabled = true
        hosted.assignedAccountID = "acct-work"
        let savedHosted = try await AIProviderSettingsPersistence.save(hosted, settingsStore: store, secretStore: secrets)

        var editedHosted = AIProviderSettingsDraft(configuration: savedHosted, hasSavedAPIKey: true)
        editedHosted.applyPreset(.appleIntelligence)
        #expect(editedHosted.kind == .openAICompatible)
        #expect(editedHosted.id == savedHosted.id)

        var onDevice = AIProviderSettingsDraft.new(kind: .appleIntelligence)
        onDevice.isEnabled = true
        onDevice.isDefault = false
        onDevice.assignedAccountID = "acct-personal"
        let savedOnDevice = try await AIProviderSettingsPersistence.save(onDevice, settingsStore: store, secretStore: secrets)

        var editedOnDevice = AIProviderSettingsDraft(configuration: savedOnDevice, hasSavedAPIKey: false)
        editedOnDevice.displayName = "Custom On-Device Name"
        editedOnDevice.applyPreset(.openAICompatible)
        #expect(editedOnDevice.kind == .appleIntelligence)
        #expect(editedOnDevice.id == AppleIntelligenceAIBackend.providerID)
        #expect(editedOnDevice.displayName == "Custom On-Device Name")
        // Restoring the Apple Intelligence profile's own preset resets its default display name.
        editedOnDevice.applyPreset(.appleIntelligence)
        #expect(editedOnDevice.kind == .appleIntelligence)
        #expect(editedOnDevice.displayName == AIProviderKind.appleIntelligence.settingsDisplayName)
        #expect(await secrets.apiKeyValue(for: savedHosted.id) == "sk-test-secret")
    }

    @Test("Downloaded local model draft requires no API key or URL, reports On this Mac, and preserves AI off-by-default")
    func downloadedLocalModelDraftRequiresNoKeyAndPreservesDefaultOff() async throws {
        let defaults = try Self.makeDefaults()
        let store = SettingsPersistenceStore(defaults: defaults)
        let secrets = InMemoryProviderSecretStore()

        let draft = AIProviderSettingsDraft.new(kind: .onDeviceDownloadedModel)
        #expect(draft.id == LocalDownloadedModelAIBackend.providerID)
        #expect(draft.requiresAPIKey == false)
        #expect(draft.validationIssues.isEmpty)
        #expect(draft.modelID == LocalModelCatalog.defaultModelID)
        #expect(draft.transparencyPreview == OnDeviceAIPlatformLabel.transparencyLabel)
        #expect(draft.apiKeyStatusText.contains("no API key"))

        var enabledDraft = draft
        enabledDraft.isEnabled = true
        let saved = try await AIProviderSettingsPersistence.save(
            enabledDraft,
            settingsStore: store,
            secretStore: secrets
        )

        #expect(saved.kind == .onDeviceDownloadedModel)
        #expect(saved.id == LocalDownloadedModelAIBackend.providerID)
        #expect(saved.transparencyLabel == OnDeviceAIPlatformLabel.transparencyLabel)
        #expect(await secrets.apiKeyValue(for: saved.id) == nil)
        #expect(store.aiWriterSettings() == AIWriterSettings.defaults)

        var edited = AIProviderSettingsDraft(configuration: saved, hasSavedAPIKey: false)
        edited.displayName = "Custom Local Name"
        edited.applyPreset(.appleIntelligence)
        #expect(edited.kind == .onDeviceDownloadedModel)
        #expect(edited.displayName == "Custom Local Name")
        edited.applyPreset(.onDeviceDownloadedModel)
        #expect(edited.displayName == AIProviderKind.onDeviceDownloadedModel.settingsDisplayName)
    }

    @Test("Editor validation blocks enabling an uninstalled local model and allows installed or disabled drafts")
    func editorValidationBlocksUninstalledLocalModel() {
        var enabledDraft = AIProviderSettingsDraft.new(kind: .onDeviceDownloadedModel)
        enabledDraft.isEnabled = true

        // Blocked when weights are not yet downloaded.
        let missingWeightsReason = AIProviderEditorValidation.blockingReason(
            for: enabledDraft,
            appleIntelligenceAvailability: .available,
            isLocalModelPlatformSupported: true,
            installedLocalModelIDs: []
        )
        #expect(missingWeightsReason != nil)
        #expect(missingWeightsReason?.contains("Local Models") == true)

        // Blocked on unsupported platforms (e.g. iOS).
        let unsupportedPlatformReason = AIProviderEditorValidation.blockingReason(
            for: enabledDraft,
            appleIntelligenceAvailability: .available,
            isLocalModelPlatformSupported: false,
            installedLocalModelIDs: [enabledDraft.modelID]
        )
        #expect(unsupportedPlatformReason == DefaultLocalModelInferenceRuntime.platformUnsupportedMessage)

        // Allowed once installed on a supported platform.
        #expect(
            AIProviderEditorValidation.blockingReason(
                for: enabledDraft,
                appleIntelligenceAvailability: .available,
                isLocalModelPlatformSupported: true,
                installedLocalModelIDs: [enabledDraft.modelID]
            ) == nil
        )

        // Saving a disabled draft remains allowed even if weights were deleted.
        var disabledDraft = enabledDraft
        disabledDraft.isEnabled = false
        #expect(
            AIProviderEditorValidation.blockingReason(
                for: disabledDraft,
                appleIntelligenceAvailability: .available,
                isLocalModelPlatformSupported: true,
                installedLocalModelIDs: []
            ) == nil
        )
    }

    @Test("Local model row action policy gates Download and Use model on platform support while keeping Delete enabled")
    func localModelRowActionPolicyGatesUnsupportedPlatforms() {
        let installedState = LocalModelDownloadState.installed(
            installedAt: Date(timeIntervalSince1970: 1_760_000_000),
            fileSizeBytes: 1024
        )

        let unsupportedNotDownloaded = LocalModelRowActionPolicy(
            state: .notDownloaded,
            isPlatformSupported: false,
            isActive: false
        )
        #expect(!unsupportedNotDownloaded.canDownload)
        #expect(!unsupportedNotDownloaded.canUseModel)
        #expect(!unsupportedNotDownloaded.canDelete)

        let unsupportedInstalled = LocalModelRowActionPolicy(
            state: installedState,
            isPlatformSupported: false,
            isActive: false
        )
        #expect(!unsupportedInstalled.canDownload)
        #expect(!unsupportedInstalled.canUseModel)
        #expect(unsupportedInstalled.canDelete)

        let supportedInstalled = LocalModelRowActionPolicy(
            state: installedState,
            isPlatformSupported: true,
            isActive: false
        )
        #expect(!supportedInstalled.canDownload)
        #expect(supportedInstalled.canUseModel)
        #expect(supportedInstalled.canDelete)
    }

    @Test("External provider refresh performs field-level three-way rebase across demoted defaults and replaced local models")
    func externalRefreshThreeWayRebasePreservesEditsAndPullsUntouchedChanges() throws {
        // (a) Hosted default demoted by "Use model" while its displayName is being edited.
        let hostedBefore = try #require(AIProviderConfiguration(
            id: AIProviderID("hosted-1"),
            kind: .openAICompatible,
            displayName: "OpenAI",
            endpointURL: URL(string: "https://api.openai.com/v1"),
            modelID: "gpt-4.1-mini",
            isEnabled: true,
            isDefault: true,
            assignedAccountID: nil
        ))
        var hostedAfter = hostedBefore
        hostedAfter.isDefault = false

        let localModel = AIProviderConfiguration.onDeviceDownloadedModel(isEnabled: true, isDefault: true)
        let updatedList = [hostedAfter, localModel]

        let hostedBaseline = AIProviderSettingsDraft(configuration: hostedBefore, hasSavedAPIKey: true)
        var hostedEdited = hostedBaseline
        hostedEdited.displayName = "Unsaved Work Name"
        hostedEdited.pendingAPIKey = "sk-unsaved-key"

        let demotedOutcome = AIProviderEditorPresentation.stateAfterExternalRefresh(
            isEditingProvider: true,
            selectedProviderID: hostedBefore.id,
            currentDraft: hostedEdited,
            baselineDraft: hostedBaseline,
            updatedConfigurations: updatedList
        )
        #expect(demotedOutcome.selectedProviderID == hostedBefore.id)
        #expect(demotedOutcome.shouldReloadDraft == false)
        #expect(demotedOutcome.shouldExitEditing == false)
        let rebasedHosted = try #require(demotedOutcome.rebasedDraft)
        #expect(rebasedHosted.displayName == "Unsaved Work Name")
        #expect(rebasedHosted.pendingAPIKey == "sk-unsaved-key")
        #expect(rebasedHosted.isDefault == false)
        #expect(demotedOutcome.updatedBaselineDraft?.isDefault == false)
        #expect(demotedOutcome.updatedBaselineDraft?.displayName == "OpenAI")

        // (b) Installed local model replaced while its provider is open for editing.
        let localBefore = AIProviderConfiguration.onDeviceDownloadedModel(
            modelID: "qwen2.5-3b-instruct-q4km",
            isEnabled: true,
            isDefault: true
        )
        let localAfter = AIProviderConfiguration.onDeviceDownloadedModel(
            modelID: "llama-3.2-3b-instruct-q4km",
            isEnabled: true,
            isDefault: true
        )
        let localBaseline = AIProviderSettingsDraft(configuration: localBefore, hasSavedAPIKey: false)
        var localEdited = localBaseline
        localEdited.displayName = "Offline Mac Model"

        let replacedOutcome = AIProviderEditorPresentation.stateAfterExternalRefresh(
            isEditingProvider: true,
            selectedProviderID: localBefore.id,
            currentDraft: localEdited,
            baselineDraft: localBaseline,
            updatedConfigurations: [hostedAfter, localAfter]
        )
        let rebasedLocal = try #require(replacedOutcome.rebasedDraft)
        #expect(rebasedLocal.displayName == "Offline Mac Model")
        #expect(rebasedLocal.modelID == "llama-3.2-3b-instruct-q4km")
        #expect(replacedOutcome.updatedBaselineDraft?.modelID == "llama-3.2-3b-instruct-q4km")

        // Adding a brand-new unsaved provider: keep selection nil and do not clobber draft.
        let newDraft = AIProviderSettingsDraft.new(kind: .customOpenAICompatible)
        let addOutcome = AIProviderEditorPresentation.stateAfterExternalRefresh(
            isEditingProvider: true,
            selectedProviderID: nil,
            currentDraft: newDraft,
            baselineDraft: newDraft,
            updatedConfigurations: updatedList
        )
        #expect(addOutcome == .init(
            selectedProviderID: nil,
            rebasedDraft: nil,
            updatedBaselineDraft: nil,
            shouldReloadDraft: false,
            shouldExitEditing: false
        ))

        // Edited provider deleted externally: fall back cleanly to the remaining default provider.
        let deletedOutcome = AIProviderEditorPresentation.stateAfterExternalRefresh(
            isEditingProvider: true,
            selectedProviderID: AIProviderID("removed-id"),
            currentDraft: hostedEdited,
            baselineDraft: hostedBaseline,
            updatedConfigurations: [localModel]
        )
        #expect(deletedOutcome == .init(
            selectedProviderID: localModel.id,
            rebasedDraft: nil,
            updatedBaselineDraft: nil,
            shouldReloadDraft: true,
            shouldExitEditing: false
        ))
    }

    @Test("Completing a local model download unblocks saving an open draft without clobbering edits")
    func downloadCompletionUnblocksOpenDraftWithoutClobberingEdits() async throws {
        var openDraft = AIProviderSettingsDraft.new(kind: .onDeviceDownloadedModel)
        openDraft.displayName = "My Offline Model"
        openDraft.isEnabled = true

        // Before download finishes, saving is blocked.
        var installedIDs: Set<String> = []
        #expect(
            AIProviderEditorValidation.blockingReason(
                for: openDraft,
                appleIntelligenceAvailability: .available,
                isLocalModelPlatformSupported: true,
                installedLocalModelIDs: installedIDs
            ) != nil
        )

        // Simulate installedModelsRevision refresh after download completes (draft untouched).
        installedIDs.insert(openDraft.modelID)
        #expect(
            AIProviderEditorValidation.blockingReason(
                for: openDraft,
                appleIntelligenceAvailability: .available,
                isLocalModelPlatformSupported: true,
                installedLocalModelIDs: installedIDs
            ) == nil
        )
        #expect(openDraft.displayName == "My Offline Model")
        #expect(openDraft.isEnabled == true)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "AIProviderSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private actor InMemoryProviderSecretStore: AIProviderSecretStore {
    private var keys: [AIProviderID: String] = [:]

    func apiKey(for providerID: AIProviderID) async throws -> String? {
        keys[providerID]
    }

    func setAPIKey(_ apiKey: String, for providerID: AIProviderID) async throws {
        keys[providerID] = apiKey
    }

    func deleteAPIKey(for providerID: AIProviderID) async throws {
        keys[providerID] = nil
    }

    func apiKeyValue(for providerID: AIProviderID) -> String? {
        keys[providerID]
    }
}
