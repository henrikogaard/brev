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

public struct AIProviderAccountAssignments: Codable, Equatable, Sendable {
    private var providerIDsByAccountID: [String: AIProviderID]

    public init(providerIDsByAccountID: [String: AIProviderID] = [:]) {
        self.providerIDsByAccountID = providerIDsByAccountID
    }

    public func providerID(forAccountID accountID: String) -> AIProviderID? {
        providerIDsByAccountID[accountID]
    }

    public mutating func assign(providerID: AIProviderID, toAccountID accountID: String) {
        providerIDsByAccountID[accountID] = providerID
    }

    public mutating func removeAccount(_ accountID: String) {
        providerIDsByAccountID[accountID] = nil
    }

    public mutating func removeProvider(_ providerID: AIProviderID) {
        providerIDsByAccountID = providerIDsByAccountID.filter { $0.value != providerID }
    }
}

public struct AIProviderAccountAssignmentStore {
    public enum Key {
        public static let accountAssignments = "ai.providers.accountAssignments.v1"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() throws -> AIProviderAccountAssignments {
        guard let data = defaults.data(forKey: Key.accountAssignments) else {
            return AIProviderAccountAssignments()
        }
        return (try? JSONDecoder().decode(AIProviderAccountAssignments.self, from: data))
            ?? AIProviderAccountAssignments()
    }

    public func save(_ assignments: AIProviderAccountAssignments) throws {
        let data = try JSONEncoder().encode(assignments)
        defaults.set(data, forKey: Key.accountAssignments)
    }

    public func removeAccount(_ accountID: String) throws {
        var assignments = try load()
        assignments.removeAccount(accountID)
        try save(assignments)
    }

    public func removeProvider(_ providerID: AIProviderID) throws {
        var assignments = try load()
        assignments.removeProvider(providerID)
        try save(assignments)
    }
}

public enum AIProviderResolutionSource: Equatable, Sendable {
    case none
    case configuredProvider
    /// Built-in backend-provided AI when the active backend advertises AI support.
    case builtInProvider
}

public enum AIProviderResolutionDisabledReason: Equatable, Sendable {
    case aiWriterDisabled
    case backendUnsupported
    case noProviderConfigured
    case assignedProviderUnavailable
    case assignedProviderDisabled
}

public struct AIProviderResolution: Equatable, Sendable {
    public let source: AIProviderResolutionSource
    public let providerID: AIProviderID?
    public let displayName: String?
    public let transparencyLabel: String?
    public let disabledReason: AIProviderResolutionDisabledReason?

    public static func builtInProvider(
        _ disclosure: AIWriterDisclosure = .defaultProvider
    ) -> AIProviderResolution {
        AIProviderResolution(
            source: .builtInProvider,
            providerID: AIProviderResolver.defaultProviderID,
            displayName: disclosure.displayName,
            transparencyLabel: disclosure.transparencyLabel,
            disabledReason: nil
        )
    }

    public static func configuredProvider(
        _ configuration: AIProviderConfiguration
    ) -> AIProviderResolution {
        AIProviderResolution(
            source: .configuredProvider,
            providerID: configuration.id,
            displayName: configuration.displayName,
            transparencyLabel: configuration.transparencyLabel,
            disabledReason: nil
        )
    }

    public static func disabled(
        _ reason: AIProviderResolutionDisabledReason
    ) -> AIProviderResolution {
        AIProviderResolution(
            source: .none,
            providerID: nil,
            displayName: nil,
            transparencyLabel: nil,
            disabledReason: reason
        )
    }
}

public struct AIProviderResolver: Sendable {
    public static let defaultProviderID = AIProviderID("provider-hosted")
    private static let legacyBuiltInProviderID = AIProviderID("euria")
    private let settings: AIWriterSettings
    private let assignments: AIProviderAccountAssignments
    private let providerConfigurations: [AIProviderConfiguration]

    public init(
        settings: AIWriterSettings,
        assignments: AIProviderAccountAssignments,
        providerConfigurations: [AIProviderConfiguration]
    ) {
        self.settings = settings
        self.assignments = assignments
        self.providerConfigurations = providerConfigurations
    }

    public func resolve(
        accountID: String,
        accountBackendIdentifier: String,
        backendSupportsAIWriter: Bool
    ) -> AIProviderResolution {
        _ = accountBackendIdentifier

        guard settings.isAvailable else {
            return .disabled(.aiWriterDisabled)
        }

        if let assignedProviderID = assignments.providerID(forAccountID: accountID) {
            return resolveAssignedProvider(assignedProviderID)
        }

        if backendSupportsAIWriter {
            return .builtInProvider()
        }

        if let defaultProvider = providerConfigurations.first(where: isUsableDefaultProvider) {
            return .configuredProvider(defaultProvider)
        }

        if !backendSupportsAIWriter {
            return .disabled(.backendUnsupported)
        }

        return .disabled(.noProviderConfigured)
    }

    private func resolveAssignedProvider(_ providerID: AIProviderID) -> AIProviderResolution {
        if providerID == Self.legacyBuiltInProviderID {
            return .builtInProvider()
        }

        guard let configuration = providerConfigurations.first(where: { $0.id == providerID }) else {
            return .disabled(.assignedProviderUnavailable)
        }
        guard isUsableProvider(configuration) else {
            return .disabled(.assignedProviderDisabled)
        }
        return .configuredProvider(configuration)
    }

    private func isUsableDefaultProvider(_ configuration: AIProviderConfiguration) -> Bool {
        configuration.isDefault && isUsableProvider(configuration)
    }

    private func isUsableProvider(_ configuration: AIProviderConfiguration) -> Bool {
        configuration.isEnabled && configuration.validationIssues.isEmpty
    }
}
