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
        #expect(draft.redactedKeyPresentation == "Saved in Keychain")
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
