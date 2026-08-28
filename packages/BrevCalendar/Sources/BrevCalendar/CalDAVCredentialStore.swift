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

/// Persists CalDAV write-target credentials. Credentials never touch
/// `UserDefaults`; only the Keychain account identifier is stored in
/// settings (`CalDAVSettings.credentialAccount`).
public protocol CalDAVCredentialStore: Sendable {
    /// Returns the stored credential for `account`, or `nil` if none.
    func credential(for account: String) async throws -> CalDAVCredential?
    /// Stores `credential` under `account`, replacing any existing value.
    func setCredential(_ credential: CalDAVCredential, for account: String) async throws
    /// Removes any credential stored under `account`.
    func deleteCredential(for account: String) async throws
}

public enum CalDAVCredentialStoreError: Error, LocalizedError, Sendable {
    case keychain(status: OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .keychain:
            return String(localized: "Couldn't access the CalDAV credential in Keychain.", bundle: .module)
        case .invalidData:
            return String(localized: "The CalDAV credential stored in Keychain is unreadable.", bundle: .module)
        }
    }
}

private enum StoredCalDAVCredentialKind: String, Codable {
    case bearer
    case basic
}

/// Keychain-backed `CalDAVCredentialStore`.
///
/// Credentials are serialized as JSON so both Bearer tokens and (local
/// only) Basic username/password pairs round-trip under one generic
/// password item per account.
public actor CalDAVKeychainCredentialStore: CalDAVCredentialStore {
    private let service: String

    public init(service: String? = nil) {
        self.service = service
            ?? "\(Bundle.main.bundleIdentifier ?? "app.brev").caldav-credentials"
    }

    public func credential(for account: String) async throws -> CalDAVCredential? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw CalDAVCredentialStoreError.keychain(status: status)
        }
        guard let data = item as? Data,
              let stored = try? JSONDecoder().decode(StoredCredential.self, from: data)
        else {
            throw CalDAVCredentialStoreError.invalidData
        }
        return stored.credential
    }

    public func setCredential(_ credential: CalDAVCredential, for account: String) async throws {
        let data = try JSONEncoder().encode(StoredCredential(credential))
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw CalDAVCredentialStoreError.keychain(status: updateStatus)
        }
        var addQuery = query
        for (key, value) in attributes {
            addQuery[key] = value
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CalDAVCredentialStoreError.keychain(status: addStatus)
        }
    }

    public func deleteCredential(for account: String) async throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CalDAVCredentialStoreError.keychain(status: status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// Codable wrapper so `CalDAVCredential` can be persisted as one blob.
    private struct StoredCredential: Codable {
        let kind: StoredCalDAVCredentialKind
        let token: String?
        let username: String?
        let password: String?

        init(_ credential: CalDAVCredential) {
            switch credential {
            case .bearer(let token):
                kind = .bearer
                self.token = token
                username = nil
                password = nil
            case .basic(let username, let password):
                kind = .basic
                token = nil
                self.username = username
                self.password = password
            }
        }

        var credential: CalDAVCredential {
            switch kind {
            case .bearer:
                return .bearer(token: token ?? "")
            case .basic:
                return .basic(username: username ?? "", password: password ?? "")
            }
        }
    }
}
