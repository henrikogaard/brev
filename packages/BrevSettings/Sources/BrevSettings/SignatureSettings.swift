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

public struct SignatureSettings: Codable, Equatable, Sendable {
    public enum MoveDirection: Sendable, Hashable {
        case up
        case down
    }

    public struct Signature: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var body: String
        public var isEnabled: Bool
    }

    private struct LegacySignature: Codable, Equatable, Sendable {
        var body: String
        var isEnabled: Bool
    }

    private struct LegacyAccountSignature: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var body: String
        var isEnabled: Bool
    }

    private struct LegacySignatureSettings: Codable, Equatable, Sendable {
        var defaultSignature: LegacySignature
        var accountSignatures: [LegacyAccountSignature]
    }

    struct AccountDefaultSignature: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var signatureID: String?
    }

    public static let storageKey = "signature.settings"

    public var signatures: [Signature]
    public var defaultSignatureIDsByAccountID: [String: String]
    public var accountIDsWithNoDefaultSignature: Set<String>

    public static let defaults = SignatureSettings(
        signatures: [],
        defaultSignatureIDsByAccountID: [:],
        accountIDsWithNoDefaultSignature: []
    )

    public static func load(from defaults: UserDefaults = .standard) -> SignatureSettings {
        guard let data = defaults.data(forKey: storageKey) else {
            return .defaults
        }

        if let legacy = try? JSONDecoder().decode(LegacySignatureSettings.self, from: data) {
            return Self.migrated(from: legacy)
        }

        if let settings = try? JSONDecoder().decode(SignatureSettings.self, from: data) {
            return settings
        }

        return .defaults
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    public func signatures(forAccountID _: String) -> [Signature] {
        guard !signatures.isEmpty else { return [] }
        return signatures.filter(\.isEnabled)
    }

    public func defaultSignatureID(forAccountID accountID: String) -> String? {
        if accountIDsWithNoDefaultSignature.contains(accountID) {
            return nil
        }

        if let storedID = defaultSignatureIDsByAccountID[accountID],
           signatures.contains(where: { $0.id == storedID && $0.isEnabled }) {
            return storedID
        }

        return signatures.first { $0.isEnabled }?.id
    }

    public func signature(forAccountID accountID: String) -> Signature? {
        guard let signatureID = defaultSignatureID(forAccountID: accountID) else {
            return nil
        }
        return signatures.first { $0.id == signatureID && $0.isEnabled }
    }

    public mutating func addSignature(
        name: String,
        body: String,
        isEnabled: Bool
    ) -> Signature {
        let signature = Signature(
            id: UUID().uuidString,
            name: name,
            body: body,
            isEnabled: isEnabled && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        signatures.append(signature)
        return signature
    }

    public mutating func updateSignature(
        id: String,
        name: String,
        body: String,
        isEnabled: Bool
    ) {
        let hasBody = !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard let index = signatures.firstIndex(where: { $0.id == id }) else {
            return
        }

        signatures[index] = Signature(
            id: id,
            name: name,
            body: body,
            isEnabled: isEnabled && hasBody
        )
    }

    public mutating func setSignatureEnabled(_ isEnabled: Bool, id: String) {
        guard let index = signatures.firstIndex(where: { $0.id == id }) else { return }
        let hasBody = !signatures[index].body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        signatures[index].isEnabled = isEnabled && hasBody
    }

    public mutating func removeSignature(id: String) {
        signatures.removeAll { $0.id == id }
        defaultSignatureIDsByAccountID = defaultSignatureIDsByAccountID.filter { $0.value != id }
    }

    public func canMoveSignature(id: String, direction: MoveDirection) -> Bool {
        guard let index = signatures.firstIndex(where: { $0.id == id }) else {
            return false
        }
        switch direction {
        case .up:
            return index > signatures.startIndex
        case .down:
            return index < signatures.index(before: signatures.endIndex)
        }
    }

    public mutating func moveSignature(id: String, direction: MoveDirection) {
        guard let index = signatures.firstIndex(where: { $0.id == id }) else {
            return
        }

        let destination: Array<Signature>.Index
        switch direction {
        case .up:
            guard index > signatures.startIndex else { return }
            destination = signatures.index(before: index)
        case .down:
            guard index < signatures.index(before: signatures.endIndex) else { return }
            destination = signatures.index(after: index)
        }

        signatures.swapAt(index, destination)
    }

    public mutating func setDefaultSignature(
        signatureID: String?,
        forAccountID accountID: String
    ) {
        guard let signatureID else {
            defaultSignatureIDsByAccountID[accountID] = nil
            accountIDsWithNoDefaultSignature.insert(accountID)
            return
        }

        guard signatures.contains(where: { $0.id == signatureID && $0.isEnabled }) else {
            return
        }

        accountIDsWithNoDefaultSignature.remove(accountID)
        defaultSignatureIDsByAccountID[accountID] = signatureID
    }

    private static func migrated(from legacy: LegacySignatureSettings) -> SignatureSettings {
        var migratedSignatures: [Signature] = []
        var defaultSignatureIDsByAccountID: [String: String] = [:]

        if legacy.defaultSignature.isEnabled,
           !legacy.defaultSignature.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            migratedSignatures.append(Signature(
                id: "legacy-default-signature",
                name: String(localized: "Default signature", bundle: .module),
                body: legacy.defaultSignature.body,
                isEnabled: true
            ))
        }

        for (index, legacySignature) in legacy.accountSignatures.enumerated() {
            guard !legacySignature.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            let signatureID = "legacy-account-signature-\(index)"
            migratedSignatures.append(Signature(
                id: signatureID,
                name: String(localized: "Account signature", bundle: .module),
                body: legacySignature.body,
                isEnabled: legacySignature.isEnabled
            ))

            if legacySignature.isEnabled {
                defaultSignatureIDsByAccountID[legacySignature.id] = signatureID
            }
        }

        return SignatureSettings(
            signatures: migratedSignatures,
            defaultSignatureIDsByAccountID: defaultSignatureIDsByAccountID,
            accountIDsWithNoDefaultSignature: []
        )
    }

    private enum CodingKeys: String, CodingKey {
        case signatures
        case defaultSignatureIDsByAccountID
        case accountIDsWithNoDefaultSignature
    }

    public init(
        signatures: [Signature],
        defaultSignatureIDsByAccountID: [String: String],
        accountIDsWithNoDefaultSignature: Set<String> = []
    ) {
        self.signatures = signatures
        self.defaultSignatureIDsByAccountID = defaultSignatureIDsByAccountID
        self.accountIDsWithNoDefaultSignature = accountIDsWithNoDefaultSignature
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        signatures = try container.decode([Signature].self, forKey: .signatures)
        defaultSignatureIDsByAccountID = try container.decodeIfPresent(
            [String: String].self,
            forKey: .defaultSignatureIDsByAccountID
        ) ?? [:]
        accountIDsWithNoDefaultSignature = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .accountIDsWithNoDefaultSignature
        ) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(signatures, forKey: .signatures)
        try container.encode(defaultSignatureIDsByAccountID, forKey: .defaultSignatureIDsByAccountID)
        try container.encode(accountIDsWithNoDefaultSignature, forKey: .accountIDsWithNoDefaultSignature)
    }
}
