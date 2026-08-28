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

@Suite("AI provider configuration")
struct AIProviderConfigurationTests {
    @Test("provider metadata validates independently of SwiftUI views")
    func providerMetadataValidatesIndependentlyOfViews() throws {
        let configuration = try #require(AIProviderConfiguration(
            id: AIProviderID("openai-primary"),
            kind: .openAICompatible,
            displayName: "OpenAI",
            endpointURL: URL(string: "https://api.openai.com/v1"),
            modelID: "gpt-4.1-mini",
            isEnabled: true,
            isDefault: true,
            assignedAccountID: "account-1"
        ))

        #expect(configuration.validationIssues.isEmpty)
        #expect(configuration.transparencyLabel == "Sent to: OpenAI (api.openai.com)")
        #expect(configuration.requiresAPIKey)
        #expect(configuration.assignedAccountID == "account-1")
    }

    @Test("validation reports actionable non-secret errors")
    func validationReportsActionableNonSecretErrors() throws {
        let configuration = try #require(AIProviderConfiguration(
            id: AIProviderID("bad-provider"),
            kind: .customOpenAICompatible,
            displayName: " \n\t ",
            endpointURL: URL(string: "file:///tmp/provider"),
            modelID: " ",
            isEnabled: true,
            isDefault: false,
            assignedAccountID: nil
        ))

        #expect(configuration.validationIssues == [
            .displayNameRequired,
            .httpEndpointRequired,
            .modelIDRequired
        ])
        #expect(configuration.validationIssues.allSatisfy { !$0.message.contains("sk-") })
    }

    @Test("Ollama local preset is disabled and keyless by default")
    func ollamaLocalPresetIsDisabledAndKeylessByDefault() throws {
        let configuration = AIProviderConfiguration.ollamaLocal(modelID: "llama3.1")

        #expect(configuration.kind == .ollamaLocal)
        #expect(configuration.endpointURL.absoluteString == "http://localhost:11434/v1")
        #expect(configuration.displayName == "Ollama")
        #expect(configuration.modelID == "llama3.1")
        #expect(configuration.isEnabled == false)
        #expect(configuration.requiresAPIKey == false)
        #expect(configuration.transparencyLabel == "Sent to: Ollama (localhost)")
    }

    @Test("settings persistence stores metadata but never API keys")
    func settingsPersistenceStoresMetadataButNeverAPIKeys() throws {
        let defaults = try Self.makeDefaults()
        let secret = "sk-test-never-store-me"
        let configuration = try #require(AIProviderConfiguration(
            id: AIProviderID("custom-provider"),
            kind: .customOpenAICompatible,
            displayName: "Private Gateway",
            endpointURL: URL(string: "https://ai.example.test/v1"),
            modelID: "mail-model",
            isEnabled: true,
            isDefault: false,
            assignedAccountID: "account-1"
        ))
        let store = AIProviderConfigurationStore(defaults: defaults)

        try store.save([configuration])
        let restored = try store.load()

        #expect(restored == [configuration])
        #expect(defaults.dictionaryRepresentation().description.contains(secret) == false)
        #expect(defaults.dictionaryRepresentation().description.contains("apiKey") == false)
    }

    @Test("legacy BYOK skeleton migrates to provider metadata")
    func legacyBYOKSkeletonMigratesToProviderMetadata() throws {
        let defaults = try Self.makeDefaults()
        defaults.set(true, forKey: AIProviderConfigurationStore.LegacyKey.providerEnabled)
        defaults.set("ollama", forKey: AIProviderConfigurationStore.LegacyKey.providerName)
        defaults.set("http://localhost:11434/v1", forKey: AIProviderConfigurationStore.LegacyKey.endpointURL)
        defaults.set("llama3", forKey: AIProviderConfigurationStore.LegacyKey.modelID)

        let restored = try AIProviderConfigurationStore(defaults: defaults).load()

        #expect(restored.count == 1)
        #expect(restored.first?.id == AIProviderConfigurationStore.legacyProviderID)
        #expect(restored.first?.kind == .ollamaLocal)
        #expect(restored.first?.displayName == "Ollama")
        #expect(restored.first?.modelID == "llama3")
        #expect(restored.first?.isEnabled == true)
    }

    @Test("API keys round-trip through the Keychain-backed secret store")
    func apiKeysRoundTripThroughKeychainBackedSecretStore() async throws {
        let service = "app.brev.tests.ai-provider.\(UUID().uuidString)"
        let store = AIProviderKeychainSecretStore(service: service)
        let providerID = AIProviderID("keychain-provider")

        try await store.setAPIKey("sk-test-secret", for: providerID)
        let restored = try await store.apiKey(for: providerID)
        try await store.deleteAPIKey(for: providerID)
        let deleted = try await store.apiKey(for: providerID)

        #expect(restored == "sk-test-secret")
        #expect(deleted == nil)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "AIProviderConfigurationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
