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
import Foundation

struct AIProviderSettingsDraft: Equatable, Sendable {
    var id: AIProviderID
    var kind: AIProviderKind
    var displayName: String
    var endpointURLString: String
    var modelID: String
    var isEnabled: Bool
    var isDefault: Bool
    var assignedAccountID: String?
    var pendingAPIKey: String
    var hasSavedAPIKey: Bool

    init(
        id: AIProviderID,
        kind: AIProviderKind,
        displayName: String,
        endpointURLString: String,
        modelID: String,
        isEnabled: Bool,
        isDefault: Bool,
        assignedAccountID: String?,
        pendingAPIKey: String = "",
        hasSavedAPIKey: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.endpointURLString = endpointURLString
        self.modelID = modelID
        self.isEnabled = isEnabled
        self.isDefault = isDefault
        self.assignedAccountID = assignedAccountID
        self.pendingAPIKey = pendingAPIKey
        self.hasSavedAPIKey = hasSavedAPIKey
    }

    init(
        configuration: AIProviderConfiguration,
        hasSavedAPIKey: Bool,
        pendingAPIKey: String = ""
    ) {
        self.init(
            id: configuration.id,
            kind: configuration.kind,
            displayName: configuration.displayName,
            endpointURLString: configuration.endpointURL.absoluteString,
            modelID: configuration.modelID,
            isEnabled: configuration.isEnabled,
            isDefault: configuration.isDefault,
            assignedAccountID: configuration.assignedAccountID,
            pendingAPIKey: pendingAPIKey,
            hasSavedAPIKey: hasSavedAPIKey
        )
    }

    static func new(kind: AIProviderKind) -> AIProviderSettingsDraft {
        AIProviderSettingsDraft(
            id: AIProviderID("provider-\(UUID().uuidString)"),
            kind: kind,
            displayName: kind.settingsDisplayName,
            endpointURLString: kind.defaultEndpointString,
            modelID: kind.defaultModelID,
            isEnabled: false,
            isDefault: true,
            assignedAccountID: nil
        )
    }

    var requiresAPIKey: Bool {
        kind != .ollamaLocal
    }

    var validationIssues: [AIProviderConfigurationValidationIssue] {
        var issues: [AIProviderConfigurationValidationIssue] = []
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.displayNameRequired)
        }
        if !hasValidHTTPEndpoint {
            issues.append(.httpEndpointRequired)
        }
        if modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.modelIDRequired)
        }
        return issues
    }

    var configuration: AIProviderConfiguration? {
        guard validationIssues.isEmpty else { return nil }
        return AIProviderConfiguration(
            id: id,
            kind: kind,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            endpointURL: URL(string: endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
            modelID: modelID.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: isEnabled,
            isDefault: isDefault,
            assignedAccountID: assignedAccountID
        )
    }

    var transparencyPreview: String {
        let providerName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? kind.settingsDisplayName
            : displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointHost = URL(
            string: endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        )?.host(percentEncoded: false) ?? String(localized: "endpoint not set", bundle: .module)
        return String(localized: "Sent to: \(providerName) (\(endpointHost))", bundle: .module)
    }

    var apiKeyStatusText: String {
        if !requiresAPIKey {
            return String(localized: "No API key required for local providers.", bundle: .module)
        }
        if !pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "New key will be saved in Keychain.", bundle: .module)
        }
        if hasSavedAPIKey {
            return String(localized: "Saved in Keychain.", bundle: .module)
        }
        return String(localized: "API key required for hosted providers.", bundle: .module)
    }

    var redactedKeyPresentation: String {
        guard requiresAPIKey else { return "Not required" }
        if hasSavedAPIKey {
            return String(localized: "Saved in Keychain", bundle: .module)
        }
        return String(localized: "Not saved", bundle: .module)
    }

    var platformCaveatMessage: String? {
        kind.platformCaveatMessage
    }

    var transportWarning: String? {
        guard let endpoint = URL(
            string: endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        ), endpoint.scheme?.lowercased() == "http",
        let host = endpoint.host?.lowercased(),
        !["localhost", "127.0.0.1", "::1"].contains(host)
        else { return nil }
        return String(
            localized: "This plaintext endpoint can expose message content and your API key on its network. Use HTTPS unless you trust that local network.",
            bundle: .module
        )
    }

    mutating func applyPreset(_ newKind: AIProviderKind) {
        kind = newKind
        displayName = newKind.settingsDisplayName
        endpointURLString = newKind.defaultEndpointString
        modelID = newKind.defaultModelID
        pendingAPIKey = ""
        if newKind == .ollamaLocal {
            hasSavedAPIKey = false
        }
    }

    private var hasValidHTTPEndpoint: Bool {
        guard let url = URL(string: endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil
        else { return false }
        return true
    }
}

enum AIProviderSettingsPersistence {
    static func loadDraft(
        providerID: AIProviderID? = nil,
        settingsStore: SettingsPersistenceStore,
        secretStore: any AIProviderSecretStore
    ) async -> AIProviderSettingsDraft {
        let configurations = (try? settingsStore.aiProviderConfigurations()) ?? []
        guard let configuration = configurations.first(where: { $0.id == providerID })
            ?? configurations.first
        else {
            return .new(kind: .openAICompatible)
        }
        let savedKey = await configuration.requiresAPIKey
            ? (try? secretStore.apiKey(for: configuration.id)) ?? nil
            : nil
        return AIProviderSettingsDraft(
            configuration: configuration,
            hasSavedAPIKey: savedKey?.isEmpty == false
        )
    }

    @discardableResult
    static func save(
        _ draft: AIProviderSettingsDraft,
        settingsStore: SettingsPersistenceStore,
        secretStore: any AIProviderSecretStore
    ) async throws -> AIProviderConfiguration {
        guard let configuration = draft.configuration else {
            throw AIProviderSettingsError.validation(draft.validationIssues)
        }

        var configurations = try settingsStore.aiProviderConfigurations()
        let previousConfiguration = configurations.first { $0.id == configuration.id }
        configurations.removeAll { $0.id == configuration.id }
        configurations.append(configuration)
        if configuration.isDefault {
            configurations = configurations.map { existing in
                var updated = existing
                updated.isDefault = existing.id == configuration.id
                return updated
            }
        }
        try settingsStore.saveAIProviderConfigurations(configurations)
        try saveAssignment(
            for: configuration,
            previousConfiguration: previousConfiguration,
            settingsStore: settingsStore
        )

        if configuration.requiresAPIKey {
            let apiKey = draft.pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !apiKey.isEmpty {
                try await secretStore.setAPIKey(apiKey, for: configuration.id)
            }
        } else {
            try await secretStore.deleteAPIKey(for: configuration.id)
        }
        return configuration
    }

    private static func saveAssignment(
        for configuration: AIProviderConfiguration,
        previousConfiguration: AIProviderConfiguration?,
        settingsStore: SettingsPersistenceStore
    ) throws {
        var assignments = try settingsStore.aiProviderAssignments()
        if let previousAccountID = previousConfiguration?.assignedAccountID,
           previousAccountID != configuration.assignedAccountID,
           assignments.providerID(forAccountID: previousAccountID) == configuration.id {
            assignments.removeAccount(previousAccountID)
        }
        if let accountID = configuration.assignedAccountID {
            assignments.assign(providerID: configuration.id, toAccountID: accountID)
        }
        try settingsStore.saveAIProviderAssignments(assignments)
    }

    static func disable(
        providerID: AIProviderID,
        settingsStore: SettingsPersistenceStore
    ) throws {
        let configurations = try settingsStore.aiProviderConfigurations().map { existing in
            var updated = existing
            if existing.id == providerID {
                updated.isEnabled = false
            }
            return updated
        }
        try settingsStore.saveAIProviderConfigurations(configurations)
    }

    static func delete(
        providerID: AIProviderID,
        settingsStore: SettingsPersistenceStore,
        secretStore: any AIProviderSecretStore
    ) async throws {
        let configurations = try settingsStore.aiProviderConfigurations()
            .filter { $0.id != providerID }
        try settingsStore.saveAIProviderConfigurations(configurations)
        try settingsStore.removeAIProviderAssignments(providerID: providerID)
        try await secretStore.deleteAPIKey(for: providerID)
    }
}

enum AIProviderSettingsError: Error, LocalizedError, Sendable {
    case validation([AIProviderConfigurationValidationIssue])

    var errorDescription: String? {
        switch self {
        case .validation(let issues):
            return issues.map(\.message).joined(separator: " ")
        }
    }
}

extension AIProviderKind {
    var settingsDisplayName: String {
        switch self {
        case .openAICompatible:
            return String(localized: "OpenAI", bundle: .module)
        case .ollamaLocal:
            return String(localized: "Ollama", bundle: .module)
        case .customOpenAICompatible:
            return String(localized: "Custom endpoint", bundle: .module)
        }
    }

    var settingsTitle: String {
        switch self {
        case .openAICompatible:
            return String(localized: "OpenAI-compatible", bundle: .module)
        case .ollamaLocal:
            return String(localized: "Ollama/local", bundle: .module)
        case .customOpenAICompatible:
            return String(localized: "Custom endpoint", bundle: .module)
        }
    }

    var settingsSubtitle: String {
        switch self {
        case .openAICompatible:
            return String(localized: "Hosted provider with a compatible chat-completions API.", bundle: .module)
        case .ollamaLocal:
            return String(localized: "Local OpenAI-compatible endpoint; no API key by default.", bundle: .module)
        case .customOpenAICompatible:
            return String(localized: "Self-hosted or OpenAI-compatible endpoint.", bundle: .module)
        }
    }

    var platformCaveatMessage: String? {
        switch self {
        case .ollamaLocal:
            return String(
                localized: "On macOS, localhost is this Mac. On iOS devices and Simulator, localhost may not be your Mac-hosted Ollama server.",
                bundle: .module
            )
        case .openAICompatible, .customOpenAICompatible:
            return nil
        }
    }

    var defaultEndpointString: String {
        switch self {
        case .openAICompatible:
            return "https://api.openai.com/v1"
        case .ollamaLocal:
            return "http://localhost:11434/v1"
        case .customOpenAICompatible:
            return ""
        }
    }

    var defaultModelID: String {
        switch self {
        case .openAICompatible:
            return "gpt-4.1-mini"
        case .ollamaLocal:
            return ""
        case .customOpenAICompatible:
            return ""
        }
    }
}
