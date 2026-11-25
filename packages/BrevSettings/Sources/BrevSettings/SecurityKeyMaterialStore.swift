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

public protocol SecurityKeyMaterialStore: Sendable {
    func material(for recordID: String) async throws -> Data?
    func setMaterial(_ data: Data, for recordID: String) async throws
    func deleteMaterial(for recordID: String) async throws
    /// Reads the Keychain-stored PKCS#12 passphrase for `recordID`, or `nil` if none was saved.
    func passphrase(for recordID: String) async throws -> String?
    /// Persists a PKCS#12 passphrase in Keychain keyed to `recordID` (never in UserDefaults).
    func setPassphrase(_ passphrase: String, for recordID: String) async throws
    /// Deletes any Keychain-stored PKCS#12 passphrase for `recordID`.
    func deletePassphrase(for recordID: String) async throws
}

public extension SecurityKeyMaterialStore {
    func passphrase(for _: String) async throws -> String? { nil }
    func setPassphrase(_: String, for _: String) async throws {}
    func deletePassphrase(for _: String) async throws {}
}

public enum SecurityKeyMaterialStoreError: Error, LocalizedError, Sendable {
    case keychain(status: OSStatus)

    public var errorDescription: String? {
        String(localized: "Couldn't access local key material in Keychain.", bundle: .module)
    }
}

public actor SecurityKeychainMaterialStore: SecurityKeyMaterialStore {
    private let service: String

    public init(service: String? = nil) {
        self.service = service
            ?? "\(Bundle.main.bundleIdentifier ?? "app.brev").security-key-material"
    }

    public func material(for recordID: String) async throws -> Data? {
        var query = baseQuery(recordID: recordID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SecurityKeyMaterialStoreError.keychain(status: status)
        }
        return item as? Data
    }

    public func setMaterial(_ data: Data, for recordID: String) async throws {
        let query = baseQuery(recordID: recordID)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw SecurityKeyMaterialStoreError.keychain(status: updateStatus)
        }

        var addQuery = query
        for (key, value) in attributes {
            addQuery[key] = value
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecurityKeyMaterialStoreError.keychain(status: addStatus)
        }
    }

    public func deleteMaterial(for recordID: String) async throws {
        let status = SecItemDelete(baseQuery(recordID: recordID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecurityKeyMaterialStoreError.keychain(status: status)
        }
        try await deletePassphrase(for: recordID)
    }

    public func passphrase(for recordID: String) async throws -> String? {
        var query = passphraseQuery(recordID: recordID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SecurityKeyMaterialStoreError.keychain(status: status)
        }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setPassphrase(_ passphrase: String, for recordID: String) async throws {
        let query = passphraseQuery(recordID: recordID)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(passphrase.utf8),
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw SecurityKeyMaterialStoreError.keychain(status: updateStatus)
        }

        var addQuery = query
        for (key, value) in attributes {
            addQuery[key] = value
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecurityKeyMaterialStoreError.keychain(status: addStatus)
        }
    }

    public func deletePassphrase(for recordID: String) async throws {
        let status = SecItemDelete(passphraseQuery(recordID: recordID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecurityKeyMaterialStoreError.keychain(status: status)
        }
    }

    private func baseQuery(recordID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: recordID,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }

    private func passphraseQuery(recordID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(service).passphrase",
            kSecAttrAccount as String: recordID,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}
