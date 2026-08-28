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
import Security

public struct AIProviderID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case openAICompatible
    case ollamaLocal
    case customOpenAICompatible

    var defaultDisplayName: String {
        switch self {
        case .openAICompatible:
            return "OpenAI"
        case .ollamaLocal:
            return "Ollama"
        case .customOpenAICompatible:
            return "Custom endpoint"
        }
    }
}

public enum AIProviderConfigurationValidationIssue: Equatable, Sendable {
    case displayNameRequired
    case httpEndpointRequired
    case modelIDRequired

    public var message: String {
        switch self {
        case .displayNameRequired:
            return String(localized: "Enter a provider display name.", bundle: .module)
        case .httpEndpointRequired:
            return String(localized: "Enter an http or https endpoint URL.", bundle: .module)
        case .modelIDRequired:
            return String(localized: "Enter a model ID.", bundle: .module)
        }
    }
}

public struct AIProviderConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var id: AIProviderID
    public var kind: AIProviderKind
    public var displayName: String
    public var endpointURL: URL
    public var modelID: String
    public var isEnabled: Bool
    public var isDefault: Bool
    public var assignedAccountID: String?

    public init?(
        id: AIProviderID,
        kind: AIProviderKind,
        displayName: String,
        endpointURL: URL?,
        modelID: String,
        isEnabled: Bool,
        isDefault: Bool,
        assignedAccountID: String?
    ) {
        guard let endpointURL else { return nil }
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.endpointURL = endpointURL
        self.modelID = modelID
        self.isEnabled = isEnabled
        self.isDefault = isDefault
        self.assignedAccountID = assignedAccountID
    }

    public static func ollamaLocal(modelID: String) -> AIProviderConfiguration {
        AIProviderConfiguration(
            id: AIProviderID("ollama-local"),
            kind: .ollamaLocal,
            displayName: AIProviderKind.ollamaLocal.defaultDisplayName,
            endpointURL: URL(string: "http://localhost:11434/v1"),
            modelID: modelID,
            isEnabled: false,
            isDefault: false,
            assignedAccountID: nil
        )!
    }

    public var requiresAPIKey: Bool {
        kind != .ollamaLocal
    }

    public var transparencyLabel: String {
        let host = endpointURL.host(percentEncoded: false) ?? endpointURL.host ?? endpointURL.absoluteString
        return "Sent to: \(trimmedDisplayName) (\(host))"
    }

    public var validationIssues: [AIProviderConfigurationValidationIssue] {
        var issues: [AIProviderConfigurationValidationIssue] = []
        if trimmedDisplayName.isEmpty {
            issues.append(.displayNameRequired)
        }
        if !isHTTPEndpoint {
            issues.append(.httpEndpointRequired)
        }
        if modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.modelIDRequired)
        }
        return issues
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isHTTPEndpoint: Bool {
        guard let scheme = endpointURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              endpointURL.host != nil
        else { return false }
        return true
    }
}

public struct AIProviderConfigurationStore {
    public enum Key {
        public static let providerConfigurations = "ai.providers.configurations.v1"
    }

    public enum LegacyKey {
        public static let providerEnabled = "byok.providerEnabled"
        public static let providerName = "byok.providerName"
        public static let endpointURL = "byok.endpointURL"
        public static let modelID = "byok.modelID"
    }

    public static let legacyProviderID = AIProviderID("legacy-byok-provider")

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() throws -> [AIProviderConfiguration] {
        if let data = defaults.data(forKey: Key.providerConfigurations) {
            return (try? JSONDecoder().decode([AIProviderConfiguration].self, from: data)) ?? []
        }
        return legacyConfiguration().map { [$0] } ?? []
    }

    public func save(_ configurations: [AIProviderConfiguration]) throws {
        let data = try JSONEncoder().encode(configurations)
        defaults.set(data, forKey: Key.providerConfigurations)
    }

    private func legacyConfiguration() -> AIProviderConfiguration? {
        guard defaults.object(forKey: LegacyKey.providerName) != nil
            || defaults.object(forKey: LegacyKey.endpointURL) != nil
            || defaults.object(forKey: LegacyKey.modelID) != nil
        else { return nil }

        let kind = legacyKind(defaults.string(forKey: LegacyKey.providerName))
        guard let endpointURL = URL(string: defaults.string(forKey: LegacyKey.endpointURL) ?? "") else {
            return nil
        }
        let modelID = defaults.string(forKey: LegacyKey.modelID) ?? ""
        let isEnabled = defaults.object(forKey: LegacyKey.providerEnabled) != nil
            ? defaults.bool(forKey: LegacyKey.providerEnabled)
            : false

        return AIProviderConfiguration(
            id: Self.legacyProviderID,
            kind: kind,
            displayName: kind.defaultDisplayName,
            endpointURL: endpointURL,
            modelID: modelID,
            isEnabled: isEnabled,
            isDefault: true,
            assignedAccountID: nil
        )
    }

    private func legacyKind(_ rawValue: String?) -> AIProviderKind {
        switch rawValue {
        case "ollama":
            return .ollamaLocal
        case "custom":
            return .customOpenAICompatible
        default:
            return .openAICompatible
        }
    }
}

public enum AIProviderFeatureFlags {
    /// Retained only to migrate pre-release builds that hid provider settings.
    public static let providerConfigurationVisibleKey = "ai.providers.v2.visible"

    /// Provider configuration is now a stable, user-controlled feature.
    public static func isProviderConfigurationVisible(defaults: UserDefaults = .standard) -> Bool {
        _ = defaults
        return true
    }
}

public protocol AIProviderSecretStore: Sendable {
    func apiKey(for providerID: AIProviderID) async throws -> String?
    func setAPIKey(_ apiKey: String, for providerID: AIProviderID) async throws
    func deleteAPIKey(for providerID: AIProviderID) async throws
}

public enum AIProviderSecretStoreError: Error, LocalizedError, Sendable {
    case keychain(status: OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .keychain:
            return String(localized: "Couldn't access the provider API key in Keychain.", bundle: .module)
        case .invalidData:
            return String(localized: "The provider API key stored in Keychain is unreadable.", bundle: .module)
        }
    }
}

public actor AIProviderKeychainSecretStore: AIProviderSecretStore {
    private let service: String

    public init(service: String? = nil) {
        self.service = service
            ?? "\(Bundle.main.bundleIdentifier ?? "app.brev").ai-providers"
    }

    public func apiKey(for providerID: AIProviderID) async throws -> String? {
        var query = baseQuery(providerID: providerID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw AIProviderSecretStoreError.keychain(status: status)
        }
        guard let data = item as? Data,
              let apiKey = String(data: data, encoding: .utf8)
        else {
            throw AIProviderSecretStoreError.invalidData
        }
        return apiKey
    }

    public func setAPIKey(_ apiKey: String, for providerID: AIProviderID) async throws {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAPIKey.isEmpty {
            try await deleteAPIKey(for: providerID)
            return
        }
        let data = Data(trimmedAPIKey.utf8)
        let query = baseQuery(providerID: providerID)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw AIProviderSecretStoreError.keychain(status: updateStatus)
        }
        var addQuery = query
        for (key, value) in attributes {
            addQuery[key] = value
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AIProviderSecretStoreError.keychain(status: addStatus)
        }
    }

    public func deleteAPIKey(for providerID: AIProviderID) async throws {
        let status = SecItemDelete(baseQuery(providerID: providerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AIProviderSecretStoreError.keychain(status: status)
        }
    }

    private func baseQuery(providerID: AIProviderID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID.rawValue
        ]
    }
}
