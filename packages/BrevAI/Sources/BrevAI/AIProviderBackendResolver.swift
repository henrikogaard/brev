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

import Foundation

/// Resolves the user's local provider preferences into account-scoped AI backends.
///
/// Constructing a backend is local-only. The backend contacts its configured
/// endpoint only after an explicit AI action invokes `AIBackend`.
public actor AIProviderBackendResolver {
    private let configurationStore: AIProviderConfigurationStore
    private let assignmentStore: AIProviderAccountAssignmentStore
    private let secretStore: any AIProviderSecretStore

    /// Creates a resolver backed by device-local provider metadata and Keychain secrets.
    public init(
        defaults: UserDefaults = .standard,
        secretStore: any AIProviderSecretStore = AIProviderKeychainSecretStore()
    ) {
        configurationStore = AIProviderConfigurationStore(defaults: defaults)
        assignmentStore = AIProviderAccountAssignmentStore(defaults: defaults)
        self.secretStore = secretStore
    }

    /// Resolves one backend per account without making a network request.
    ///
    /// An explicit account assignment wins over the default. A selected provider
    /// with a missing Keychain key produces no backend instead of silently
    /// falling back to another provider. A built-in account backend remains the
    /// default for that account unless the user has assigned a configured provider.
    public func backends(
        forAccountIDs accountIDs: [String],
        builtInBackends: [String: any AIBackend]
    ) async -> [String: any AIBackend] {
        let configurations = (try? configurationStore.load()) ?? []
        let assignments = (try? assignmentStore.load()) ?? AIProviderAccountAssignments()
        let providerResolver = AIProviderResolver(
            settings: AIWriterSettings(isEnabled: true, consentGiven: true),
            assignments: assignments,
            providerConfigurations: configurations
        )

        var resolvedBackends: [String: any AIBackend] = [:]
        for accountID in accountIDs {
            let builtInBackend = builtInBackends[accountID]
            let resolution = providerResolver.resolve(
                accountID: accountID,
                accountBackendIdentifier: "",
                backendSupportsAIWriter: builtInBackend != nil
            )

            switch resolution.source {
            case .builtInProvider:
                if let builtInBackend {
                    resolvedBackends[accountID] = builtInBackend
                }
            case .configuredProvider:
                guard let providerID = resolution.providerID,
                      let configuration = configurations.first(where: { $0.id == providerID }),
                      let backend = await configuredBackend(for: configuration)
                else { continue }
                resolvedBackends[accountID] = backend
            case .none:
                continue
            }
        }
        return resolvedBackends
    }

    private func configuredBackend(
        for configuration: AIProviderConfiguration
    ) async -> (any AIBackend)? {
        guard configuration.isEnabled,
              configuration.validationIssues.isEmpty
        else { return nil }

        let apiKey: String?
        if configuration.requiresAPIKey {
            guard let storedKey = try? await secretStore.apiKey(for: configuration.id),
                  !storedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            apiKey = storedKey
        } else {
            apiKey = nil
        }

        return OpenAICompatibleBackend(
            providerName: configuration.displayName,
            transparencyLabel: configuration.transparencyLabel,
            baseURL: configuration.endpointURL,
            apiKey: apiKey,
            modelID: configuration.modelID
        )
    }
}
