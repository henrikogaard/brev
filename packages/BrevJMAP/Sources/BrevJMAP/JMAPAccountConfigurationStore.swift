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

/// Persists non-secret JMAP account configuration metadata used to restore sessions.
///
/// Bearer / API tokens remain strictly in `TokenStore` (Keychain) and are never
/// stored in this store, in `.brevbackup`, or in iCloud preference sync.
public protocol JMAPAccountConfigurationStore: Sendable {
    /// Returns saved metadata for `accountID`, or `nil` when absent.
    func configuration(for accountID: String) async -> JMAPAccountConfiguration?
    /// Persists non-secret metadata for one JMAP account.
    func setConfiguration(_ configuration: JMAPAccountConfiguration) async throws
    /// Removes saved metadata for `accountID`.
    func clearConfiguration(for accountID: String) async
}

/// Deterministic in-memory JMAP account configuration store for tests and previews.
public actor InMemoryJMAPAccountConfigurationStore: JMAPAccountConfigurationStore {
    private var configurations: [String: JMAPAccountConfiguration]

    /// Creates an in-memory store optionally seeded with configurations.
    public init(configurations: [JMAPAccountConfiguration] = []) {
        self.configurations = Dictionary(uniqueKeysWithValues: configurations.map { ($0.accountID, $0) })
    }

    /// Returns metadata for `accountID`.
    public func configuration(for accountID: String) -> JMAPAccountConfiguration? {
        configurations[accountID]
    }

    /// Validates and stores non-secret JMAP metadata.
    public func setConfiguration(_ configuration: JMAPAccountConfiguration) throws {
        guard !configuration.accountID.isEmpty,
              !configuration.emailAddress.isEmpty
        else {
            throw JMAPError.invalidConfiguration
        }
        _ = try JMAPURLValidator.validateHTTPSURL(configuration.sessionURL)
        configurations[configuration.accountID] = configuration
    }

    /// Removes metadata for `accountID`.
    public func clearConfiguration(for accountID: String) {
        configurations[accountID] = nil
    }
}

/// UserDefaults-backed non-secret JMAP account metadata store.
///
/// Strictly stores only account identifiers, email/display name, and validated
/// HTTPS session URLs. Secrets are never written here.
public actor UserDefaultsJMAPAccountConfigurationStore: JMAPAccountConfigurationStore {
    private let defaults: UserDefaults
    private let key: String

    /// Creates a store backed by `defaults` and `key`.
    public init(
        defaults: UserDefaults = .standard,
        key: String = "Brev.jmapAccountConfigurations.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    /// Returns metadata for `accountID`.
    public func configuration(for accountID: String) -> JMAPAccountConfiguration? {
        configurations()[accountID]
    }

    /// Validates and persists non-secret metadata for one JMAP account.
    public func setConfiguration(_ configuration: JMAPAccountConfiguration) throws {
        guard !configuration.accountID.isEmpty,
              !configuration.emailAddress.isEmpty
        else {
            throw JMAPError.invalidConfiguration
        }
        _ = try JMAPURLValidator.validateHTTPSURL(configuration.sessionURL)
        var values = configurations()
        values[configuration.accountID] = configuration
        let data = try JSONEncoder().encode(values)
        defaults.set(data, forKey: key)
    }

    /// Removes metadata for `accountID` while preserving other JMAP accounts.
    public func clearConfiguration(for accountID: String) {
        var values = configurations()
        values[accountID] = nil
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: key)
        }
    }

    private func configurations() -> [String: JMAPAccountConfiguration] {
        guard let data = defaults.data(forKey: key),
              let values = try? JSONDecoder().decode(
                  [String: JMAPAccountConfiguration].self,
                  from: data
              )
        else {
            return [:]
        }
        return values
    }
}
