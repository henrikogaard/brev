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

@Suite("Configured AI provider runtime")
struct AIProviderBackendResolverTests {
    @Test("a configured default provider is built for an IMAP account")
    func configuredDefaultProviderIsBuiltForAnIMAPAccount() async throws {
        let defaults = try Self.makeDefaults()
        let configuration = try #require(AIProviderConfiguration(
            id: AIProviderID("private-gateway"),
            kind: .customOpenAICompatible,
            displayName: "Private Gateway",
            endpointURL: URL(string: "https://ai.example.test/v1"),
            modelID: "mail-model",
            isEnabled: true,
            isDefault: true,
            assignedAccountID: nil
        ))
        try AIProviderConfigurationStore(defaults: defaults).save([configuration])
        let secrets = InMemorySecretStore()
        try await secrets.setAPIKey("test-key", for: configuration.id)

        let resolver = AIProviderBackendResolver(defaults: defaults, secretStore: secrets)
        let backends = await resolver.backends(
            forAccountIDs: ["imap-account"],
            builtInBackends: [:]
        )

        let backend = try #require(backends["imap-account"])
        #expect(backend.displayName == "Private Gateway")
        #expect(backend.transparencyLabel == "Sent to: Private Gateway (ai.example.test)")
    }

    @Test("an account assignment wins over the configured default")
    func accountAssignmentWinsOverConfiguredDefault() async throws {
        let defaults = try Self.makeDefaults()
        let defaultProvider = try Self.provider(
            id: "default-provider",
            name: "Default AI",
            isDefault: true
        )
        let assignedProvider = try Self.provider(
            id: "work-provider",
            name: "Work AI",
            isDefault: false
        )
        try AIProviderConfigurationStore(defaults: defaults).save([defaultProvider, assignedProvider])
        var assignments = AIProviderAccountAssignments()
        assignments.assign(providerID: assignedProvider.id, toAccountID: "work-account")
        try AIProviderAccountAssignmentStore(defaults: defaults).save(assignments)
        let secrets = InMemorySecretStore()
        try await secrets.setAPIKey("default-key", for: defaultProvider.id)
        try await secrets.setAPIKey("work-key", for: assignedProvider.id)

        let resolver = AIProviderBackendResolver(defaults: defaults, secretStore: secrets)
        let backends = await resolver.backends(
            forAccountIDs: ["personal-account", "work-account"],
            builtInBackends: [:]
        )

        #expect(backends["personal-account"]?.displayName == "Default AI")
        #expect(backends["work-account"]?.displayName == "Work AI")
    }

    @Test("a missing selected key does not silently fall back to another provider")
    func missingSelectedKeyDoesNotFallBackToAnotherProvider() async throws {
        let defaults = try Self.makeDefaults()
        let defaultProvider = try Self.provider(
            id: "default-provider",
            name: "Default AI",
            isDefault: true
        )
        let assignedProvider = try Self.provider(
            id: "work-provider",
            name: "Work AI",
            isDefault: false
        )
        try AIProviderConfigurationStore(defaults: defaults).save([defaultProvider, assignedProvider])
        var assignments = AIProviderAccountAssignments()
        assignments.assign(providerID: assignedProvider.id, toAccountID: "work-account")
        try AIProviderAccountAssignmentStore(defaults: defaults).save(assignments)
        let secrets = InMemorySecretStore()
        try await secrets.setAPIKey("default-key", for: defaultProvider.id)

        let resolver = AIProviderBackendResolver(defaults: defaults, secretStore: secrets)
        let backends = await resolver.backends(
            forAccountIDs: ["work-account"],
            builtInBackends: [:]
        )

        #expect(backends["work-account"] == nil)
    }

    private static func provider(
        id: String,
        name: String,
        isDefault: Bool
    ) throws -> AIProviderConfiguration {
        try #require(AIProviderConfiguration(
            id: AIProviderID(id),
            kind: .customOpenAICompatible,
            displayName: name,
            endpointURL: URL(string: "https://\(id).example.test/v1"),
            modelID: "mail-model",
            isEnabled: true,
            isDefault: isDefault,
            assignedAccountID: nil
        ))
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "AIProviderBackendResolverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private actor InMemorySecretStore: AIProviderSecretStore {
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
}
