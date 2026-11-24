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
    case keychain(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            String(localized: "Couldn't encode the push relay secret.", bundle: .module)
        case .keychain:
            String(localized: "Couldn't access the push relay secret in Keychain.", bundle: .module)
        }
    }
}

/// Device-local secret storage for the optional push relay bearer token and
/// RFC 8291 P-256 ECDH private key material (#11).
///
/// Secrets MUST live in Keychain (`ThisDeviceOnly`) and never in `UserDefaults`,
/// logs, backups, or iCloud sync.
public protocol PushRelaySecretStore: Sendable {
    /// Returns the stored optional bearer token, or `nil` when unset.
    func bearerToken() throws -> String?

    /// Saves or clears the optional bearer token. Whitespace-only or `nil` clears it.
    func saveBearerToken(_ token: String?) throws

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
    private static let bearerAccountKey = "push-relay-bearer-token"
    private static let encryptionKeyAccountKey = "push-relay-rfc8291-key"

    private let service: String

    /// Creates a Keychain store scoped to `service` (defaults to `<bundleID>.pushRelay`).
    public init(service: String? = nil) {
        self.service = service ?? "\(Bundle.main.bundleIdentifier ?? "eu.brevmail.brev").pushRelay"
    }

    public func bearerToken() throws -> String? {
        guard let data = try readData(account: Self.bearerAccountKey) else { return nil }
        let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public func saveBearerToken(_ token: String?) throws {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            try deleteItem(account: Self.bearerAccountKey)
            return
        }
        try writeData(Data(trimmed.utf8), account: Self.bearerAccountKey)
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
        try deleteItem(account: Self.bearerAccountKey)
        try deleteItem(account: Self.encryptionKeyAccountKey)
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
    private var storedBearer: String?
    private var storedKeyMaterial: PushRelayEncryptionKeyMaterial?

    /// Creates an in-memory secret store with optional pre-populated values.
    public init(
        bearerToken: String? = nil,
        encryptionKeyMaterial: PushRelayEncryptionKeyMaterial? = nil
    ) {
        let trimmed = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        storedBearer = trimmed?.isEmpty == false ? trimmed : nil
        storedKeyMaterial = encryptionKeyMaterial
    }

    public func bearerToken() throws -> String? {
        lock.withLock { storedBearer }
    }

    public func saveBearerToken(_ token: String?) throws {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.withLock {
            storedBearer = trimmed?.isEmpty == false ? trimmed : nil
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
            storedBearer = nil
            storedKeyMaterial = nil
        }
    }
}
