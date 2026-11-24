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
import Security

/// Errors raised when reading or writing device-local push relay secrets.
public enum PushRelaySecretStoreError: Error, LocalizedError, Equatable, Sendable {
    case encodingFailed
    case invalidOrigin
    case keychain(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            String(localized: "Couldn't encode the push relay secret.", bundle: .module)
        case .invalidOrigin:
            String(localized: "Couldn't determine a valid HTTPS relay origin for the saved bearer token.", bundle: .module)
        case .keychain:
            String(localized: "Couldn't access the push relay secret in Keychain.", bundle: .module)
        }
    }
}

/// Device-local secret storage for origin-scoped push relay bearer tokens and
/// RFC 8291 P-256 ECDH private key material (#11).
///
/// Secrets MUST live in Keychain (`ThisDeviceOnly`), scoped per normalized
/// relay origin (`scheme://host[:port]`) so switching relay servers never
/// forwards an earlier server's credential to a new host.
public protocol PushRelaySecretStore: Sendable {
    /// Returns the stored optional bearer token scoped to `origin`, or `nil` when unset.
    func bearerToken(forOrigin origin: String) throws -> String?

    /// Saves or clears the optional bearer token scoped to `origin`.
    /// Whitespace-only or `nil` removes the credential for `origin`.
    func saveBearerToken(_ token: String?, forOrigin origin: String) throws

    /// Returns the stored RFC 8291 P-256 key material, or `nil` if not generated yet.
    func encryptionKeyMaterial() throws -> PushRelayEncryptionKeyMaterial?

    /// Returns the existing RFC 8291 P-256 key material or generates and persists a new pair.
    func loadOrCreateEncryptionKeyMaterial() throws -> PushRelayEncryptionKeyMaterial

    /// Removes all stored push relay secrets from this device.
    func clearAll() throws
}

/// Keychain-backed `PushRelaySecretStore` using `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
/// so secrets never sync via iCloud Keychain.
public final class PushRelayKeychainSecretStore: PushRelaySecretStore, @unchecked Sendable {
    private static let bearerAccountPrefix = "push-relay-bearer:"
    private static let encryptionKeyAccountKey = "push-relay-rfc8291-key"

    private let service: String

    /// Creates a Keychain store scoped to `service` (defaults to `<bundleID>.pushRelay`).
    public init(service: String? = nil) {
        self.service = service ?? "\(Bundle.main.bundleIdentifier ?? "eu.brevmail.brev").pushRelay"
    }

    public func bearerToken(forOrigin origin: String) throws -> String? {
        let normalizedOrigin = try Self.normalizeOrigin(origin)
        guard let data = try readData(account: Self.bearerAccountPrefix + normalizedOrigin) else {
            return nil
        }
        let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public func saveBearerToken(_ token: String?, forOrigin origin: String) throws {
        let normalizedOrigin = try Self.normalizeOrigin(origin)
        let accountKey = Self.bearerAccountPrefix + normalizedOrigin
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            try deleteItem(account: accountKey)
            return
        }
        try writeData(Data(trimmed.utf8), account: accountKey)
    }

    public func encryptionKeyMaterial() throws -> PushRelayEncryptionKeyMaterial? {
        guard let data = try readData(account: Self.encryptionKeyAccountKey) else { return nil }
        return try? JSONDecoder().decode(PushRelayEncryptionKeyMaterial.self, from: data)
    }

    public func loadOrCreateEncryptionKeyMaterial() throws -> PushRelayEncryptionKeyMaterial {
        if let existing = try encryptionKeyMaterial() {
            return existing
        }
        let generated = PushRelayEncryptionKeyMaterial.generate()
        guard let data = try? JSONEncoder().encode(generated) else {
            throw PushRelaySecretStoreError.encodingFailed
        }
        try writeData(data, account: Self.encryptionKeyAccountKey)
        return generated
    }

    public func clearAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PushRelaySecretStoreError.keychain(status: status)
        }
    }

    private static func normalizeOrigin(_ origin: String) throws -> String {
        guard let normalized = try? PushRelayEndpointValidator.originKey(from: origin) else {
            throw PushRelaySecretStoreError.invalidOrigin
        }
        return normalized
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func readData(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw PushRelaySecretStoreError.keychain(status: status)
        }
        return item as? Data
    }

    private func writeData(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw PushRelaySecretStoreError.keychain(status: updateStatus)
        }
        var addQuery = query
        for (key, value) in attributes {
            addQuery[key] = value
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw PushRelaySecretStoreError.keychain(status: addStatus)
        }
    }

    private func deleteItem(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PushRelaySecretStoreError.keychain(status: status)
        }
    }
}

/// Thread-safe in-memory `PushRelaySecretStore` for unit and snapshot tests.
public final class InMemoryPushRelaySecretStore: PushRelaySecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedBearersByOrigin: [String: String]
    private var storedKeyMaterial: PushRelayEncryptionKeyMaterial?

    /// Creates an in-memory secret store with optional pre-populated origin-scoped bearer tokens.
    public init(
        bearerTokensByOrigin: [String: String] = [:],
        encryptionKeyMaterial: PushRelayEncryptionKeyMaterial? = nil
    ) {
        var normalized: [String: String] = [:]
        for (origin, token) in bearerTokensByOrigin {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               let key = try? PushRelayEndpointValidator.originKey(from: origin) {
                normalized[key] = trimmed
            }
        }
        storedBearersByOrigin = normalized
        storedKeyMaterial = encryptionKeyMaterial
    }

    public func bearerToken(forOrigin origin: String) throws -> String? {
        guard let key = try? PushRelayEndpointValidator.originKey(from: origin) else {
            throw PushRelaySecretStoreError.invalidOrigin
        }
        return lock.withLock { storedBearersByOrigin[key] }
    }

    public func saveBearerToken(_ token: String?, forOrigin origin: String) throws {
        guard let key = try? PushRelayEndpointValidator.originKey(from: origin) else {
            throw PushRelaySecretStoreError.invalidOrigin
        }
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.withLock {
            if let trimmed, !trimmed.isEmpty {
                storedBearersByOrigin[key] = trimmed
            } else {
                storedBearersByOrigin.removeValue(forKey: key)
            }
        }
    }

    public func encryptionKeyMaterial() throws -> PushRelayEncryptionKeyMaterial? {
        lock.withLock { storedKeyMaterial }
    }

    public func loadOrCreateEncryptionKeyMaterial() throws -> PushRelayEncryptionKeyMaterial {
        lock.withLock {
            if let existing = storedKeyMaterial {
                return existing
            }
            let generated = PushRelayEncryptionKeyMaterial.generate()
            storedKeyMaterial = generated
            return generated
        }
    }

    public func clearAll() throws {
        lock.withLock {
            storedBearersByOrigin.removeAll()
            storedKeyMaterial = nil
        }
    }
}
