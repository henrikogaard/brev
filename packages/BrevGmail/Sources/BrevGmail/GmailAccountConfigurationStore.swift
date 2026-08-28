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

import BrevBackend
import Foundation

/// Persists non-secret Google account metadata used to restore native Gmail
/// API sessions. Tokens remain in the injected `TokenStore`.
public protocol GmailAccountConfigurationStore: Sendable {
    /// Returns metadata for one account, if it was provisioned.
    func configuration(for accountID: String) async -> GoogleOAuthAccountConfiguration?
    /// Persists metadata for one account.
    func setConfiguration(_ configuration: GoogleOAuthAccountConfiguration) async throws
    /// Removes metadata for one account.
    func clearConfiguration(for accountID: String) async
}

/// Deterministic account configuration store for tests and previews.
public actor InMemoryGmailAccountConfigurationStore: GmailAccountConfigurationStore {
    private var configurations: [String: GoogleOAuthAccountConfiguration]

    /// Creates an empty store or seeds it with existing configurations.
    public init(configurations: [GoogleOAuthAccountConfiguration] = []) {
        self.configurations = Dictionary(uniqueKeysWithValues: configurations.map { ($0.accountID, $0) })
    }

    /// Returns metadata for one account.
    public func configuration(for accountID: String) -> GoogleOAuthAccountConfiguration? {
        configurations[accountID]
    }

    /// Persists metadata keyed by its stable account identity.
    public func setConfiguration(_ configuration: GoogleOAuthAccountConfiguration) throws {
        guard !configuration.accountID.isEmpty,
              !configuration.email.isEmpty
        else { throw GmailAccountConfigurationStoreError.invalidConfiguration }
        configurations[configuration.accountID] = configuration
    }

    /// Removes metadata for one account.
    public func clearConfiguration(for accountID: String) {
        configurations[accountID] = nil
    }
}

/// UserDefaults-backed account configuration store. Only non-secret metadata
/// is encoded here; access and refresh tokens are never written to UserDefaults.
public actor UserDefaultsGmailAccountConfigurationStore: GmailAccountConfigurationStore {
    private let defaults: UserDefaults
    private let key: String

    /// Creates a store using the supplied defaults suite and storage key.
    public init(
        defaults: UserDefaults = .standard,
        key: String = "Brev.gmailOAuthAccountConfigurations.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    /// Returns metadata for one account.
    public func configuration(for accountID: String) -> GoogleOAuthAccountConfiguration? {
        configurations()[accountID]
    }

    /// Encodes and persists one non-secret configuration.
    public func setConfiguration(_ configuration: GoogleOAuthAccountConfiguration) throws {
        guard !configuration.accountID.isEmpty,
              !configuration.email.isEmpty
        else { throw GmailAccountConfigurationStoreError.invalidConfiguration }
        var values = configurations()
        values[configuration.accountID] = configuration
        try persist(values)
    }

    /// Removes one configuration while preserving other accounts.
    public func clearConfiguration(for accountID: String) {
        var values = configurations()
        values[accountID] = nil
        try? persist(values)
    }

    private func configurations() -> [String: GoogleOAuthAccountConfiguration] {
        guard let data = defaults.data(forKey: key),
              let values = try? JSONDecoder().decode(
                  [String: GoogleOAuthAccountConfiguration].self,
                  from: data
              )
        else { return [:] }
        return values
    }

    private func persist(_ values: [String: GoogleOAuthAccountConfiguration]) throws {
        let data = try JSONEncoder().encode(values)
        defaults.set(data, forKey: key)
    }
}

/// Errors raised while validating non-secret Gmail account metadata.
public enum GmailAccountConfigurationStoreError: Error, Sendable, Equatable, LocalizedError {
    /// The account metadata did not contain a stable account id or email.
    case invalidConfiguration

    /// Safe user-facing error text.
    public var errorDescription: String? {
        "The Gmail account configuration is invalid."
    }
}
