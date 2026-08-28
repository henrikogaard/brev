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

/// Errors raised while persisting OAuth tokens in the system Keychain.
public enum KeychainTokenStoreError: Error, LocalizedError, Sendable, Equatable {
    case encodingFailed
    case keychain(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return String(localized: "Couldn't encode the saved sign-in token.", bundle: .module)
        case .keychain:
            return String(localized: "Couldn't save the sign-in token in Keychain.", bundle: .module)
        }
    }
}

/// `TokenStore` backed by the system Keychain (kSecClassGenericPassword).
/// One Keychain item per account id; the service name is the supplied
/// `service` (defaults to `\(Bundle.main.bundleIdentifier).tokens`).
///
/// Tokens are JSON-encoded and written with
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so they survive
/// reboots but never sync to iCloud Keychain.
public actor KeychainTokenStore: TokenStore {
    private let service: String

    public init(service: String? = nil) {
        self.service = service
            ?? "\(Bundle.main.bundleIdentifier ?? "app.brev").tokens"
    }

    public func token(for accountID: String) -> Token? {
        var query = baseQuery(accountID: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Token.self, from: data)
    }

    public func setToken(_ token: Token, for accountID: String) throws {
        guard let data = try? JSONEncoder().encode(token) else {
            throw KeychainTokenStoreError.encodingFailed
        }
        let query = baseQuery(accountID: accountID)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainTokenStoreError.keychain(status: updateStatus)
        }
        var addQuery = query
        for (key, value) in attributes {
            addQuery[key] = value
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainTokenStoreError.keychain(status: addStatus)
        }
    }

    public func clearToken(for accountID: String) {
        try? clearTokenChecked(for: accountID)
    }

    /// Removes a token and reports any Keychain failure to the caller.
    public func clearTokenChecked(for accountID: String) throws {
        let query = baseQuery(accountID: accountID)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.keychain(status: status)
        }
    }

    private func baseQuery(accountID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID
        ]
    }
}
