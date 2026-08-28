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

@Suite("AI provider account routing")
struct AIProviderAccountRoutingTests {
    @Test("accounts with backend AI support resolve to provider-hosted backend when AI is enabled")
    func accountsWithAIBackendSupportResolveToBuiltInProviderWhenEnabled() {
        let resolver = AIProviderResolver(
            settings: AIWriterSettings(isEnabled: true, consentGiven: true),
            assignments: AIProviderAccountAssignments(),
            providerConfigurations: []
        )

        let resolution = resolver.resolve(
            accountID: "account-with-ai-capability",
            accountBackendIdentifier: "provider-xyz",
            backendSupportsAIWriter: true
        )

        #expect(resolution.source == .builtInProvider)
        #expect(resolution.providerID == AIProviderResolver.defaultProviderID)
        #expect(resolution.transparencyLabel == AIWriterDisclosure.defaultProvider.transparencyLabel)
        #expect(resolution.disabledReason == nil)
    }

    @Test("non-capable accounts default to backend unsupported with no provider")
    func nonCapableAccountsDefaultToBackendUnsupportedWithoutConfiguredProvider() {
        let resolver = AIProviderResolver(
            settings: AIWriterSettings(isEnabled: true, consentGiven: true),
            assignments: AIProviderAccountAssignments(),
            providerConfigurations: []
        )

        let resolution = resolver.resolve(
            accountID: "non-capable-account",
            accountBackendIdentifier: "imap",
            backendSupportsAIWriter: false
        )

        #expect(resolution.source == .none)
        #expect(resolution.disabledReason == .backendUnsupported)
        #expect(resolution.transparencyLabel == nil)
    }

    @Test("global default BYOK provider resolves when no account override exists")
    func globalDefaultBYOKProviderResolvesWhenNoAccountOverrideExists() throws {
        let configuration = try Self.provider(
            id: "custom-default",
            displayName: "Private Gateway",
            isEnabled: true,
            isDefault: true
        )
        let resolver = AIProviderResolver(
            settings: AIWriterSettings(isEnabled: true, consentGiven: true),
            assignments: AIProviderAccountAssignments(),
            providerConfigurations: [configuration]
        )

        let resolution = resolver.resolve(
            accountID: "imap-account",
            accountBackendIdentifier: "imap",
            backendSupportsAIWriter: false
        )

        #expect(resolution.source == .configuredProvider)
        #expect(resolution.providerID == configuration.id)
        #expect(resolution.transparencyLabel == configuration.transparencyLabel)
    }

    @Test("legacy built-in provider alias resolves as built-in")
    func legacyBuiltInProviderAliasStillMapsToBuiltInProvider() {
        var assignments = AIProviderAccountAssignments()
        assignments.assign(providerID: AIProviderID("euria"), toAccountID: "legacy-account")
        let resolver = AIProviderResolver(
            settings: AIWriterSettings(isEnabled: true, consentGiven: true),
            assignments: assignments,
            providerConfigurations: []
        )

        let resolution = resolver.resolve(
            accountID: "legacy-account",
            accountBackendIdentifier: "imap",
            backendSupportsAIWriter: false
        )

        #expect(resolution.source == .builtInProvider)
        #expect(resolution.providerID == AIProviderResolver.defaultProviderID)
    }

    @Test("account-specific provider assignments override global defaults")
    func accountSpecificProviderAssignmentsOverrideGlobalDefaults() throws {
        let assigned = try Self.provider(
            id: "assigned-provider",
            displayName: "Assigned",
            isEnabled: true,
            isDefault: false
        )
        let defaultProvider = try Self.provider(
            id: "default-provider",
            displayName: "Default",
            isEnabled: true,
            isDefault: true
        )
        var assignments = AIProviderAccountAssignments()
        assignments.assign(providerID: assigned.id, toAccountID: "account-1")
        let resolver = AIProviderResolver(
            settings: AIWriterSettings(isEnabled: true, consentGiven: true),
            assignments: assignments,
            providerConfigurations: [defaultProvider, assigned]
        )

        let resolution = resolver.resolve(
            accountID: "account-1",
            accountBackendIdentifier: "imap",
            backendSupportsAIWriter: false
        )

        #expect(resolution.source == .configuredProvider)
        #expect(resolution.providerID == assigned.id)
        #expect(resolution.transparencyLabel == assigned.transparencyLabel)
    }

    @Test("missing or disabled assigned providers do not silently fall back")
    func missingOrDisabledAssignedProvidersDoNotSilentlyFallBack() throws {
        let disabled = try Self.provider(
            id: "disabled-provider",
            displayName: "Disabled",
            isEnabled: false,
            isDefault: false
        )
        let defaultProvider = try Self.provider(
            id: "default-provider",
            displayName: "Default",
            isEnabled: true,
            isDefault: true
        )
        var assignments = AIProviderAccountAssignments()
        assignments.assign(providerID: disabled.id, toAccountID: "disabled-account")
        assignments.assign(providerID: AIProviderID("missing-provider"), toAccountID: "missing-account")
        let resolver = AIProviderResolver(
            settings: AIWriterSettings(isEnabled: true, consentGiven: true),
            assignments: assignments,
            providerConfigurations: [defaultProvider, disabled]
        )

        let disabledResolution = resolver.resolve(
            accountID: "disabled-account",
            accountBackendIdentifier: "imap",
            backendSupportsAIWriter: false
        )
        let missingResolution = resolver.resolve(
            accountID: "missing-account",
            accountBackendIdentifier: "imap",
            backendSupportsAIWriter: false
        )

        #expect(disabledResolution.source == .none)
        #expect(disabledResolution.disabledReason == .assignedProviderDisabled)
        #expect(missingResolution.source == .none)
        #expect(missingResolution.disabledReason == .assignedProviderUnavailable)
    }

    @Test("assignment cleanup removes deleted accounts and providers")
    func assignmentCleanupRemovesDeletedAccountsAndProviders() {
        var assignments = AIProviderAccountAssignments()
        let providerID = AIProviderID("provider")
        assignments.assign(providerID: providerID, toAccountID: "account-a")
        assignments.assign(providerID: providerID, toAccountID: "account-b")

        assignments.removeAccount("account-a")
        assignments.removeProvider(providerID)

        #expect(assignments.providerID(forAccountID: "account-a") == nil)
        #expect(assignments.providerID(forAccountID: "account-b") == nil)
    }

    @Test("assignment store persists and prunes account preferences")
    func assignmentStorePersistsAndPrunesAccountPreferences() throws {
        let defaults = try Self.makeDefaults()
        let store = AIProviderAccountAssignmentStore(defaults: defaults)
        var assignments = AIProviderAccountAssignments()
        assignments.assign(providerID: AIProviderID("provider"), toAccountID: "account-a")

        try store.save(assignments)
        try store.removeAccount("account-a")

        #expect(try store.load().providerID(forAccountID: "account-a") == nil)
    }

    private static func provider(
        id: String,
        displayName: String,
        isEnabled: Bool,
        isDefault: Bool
    ) throws -> AIProviderConfiguration {
        try #require(AIProviderConfiguration(
            id: AIProviderID(id),
            kind: .customOpenAICompatible,
            displayName: displayName,
            endpointURL: URL(string: "https://\(id).example.test/v1"),
            modelID: "mail-model",
            isEnabled: isEnabled,
            isDefault: isDefault,
            assignedAccountID: nil
        ))
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "AIProviderAccountRoutingTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
