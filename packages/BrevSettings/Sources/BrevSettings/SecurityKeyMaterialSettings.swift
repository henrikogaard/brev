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

public enum SecurityKeyMaterialFamily: String, Codable, CaseIterable, Sendable {
    case smime
}

public enum SecurityKeyMaterialTrustState: String, Codable, CaseIterable, Sendable {
    case trusted
    case untrusted
    case revoked
    case expired
}

public enum SecuritySMIMEExportFormat: String, Codable, CaseIterable, Sendable {
    case pem
    case der
    case pkcs12
}

/// Provider-neutral local catalog metadata for imported key and certificate
/// material. This model persists *descriptors* only; private key bytes stay in
/// Keychain-backed storage in the crypto pipeline.
public struct SecurityKeyMaterialSettings: Equatable, Codable, Sendable {
    public enum Key {
        public static let storage = "security.keyMaterial.settings"
    }

    public var records: [Record]
    public var importExport: ImportExportPreferences

    public static let defaults = SecurityKeyMaterialSettings(
        records: [],
        importExport: .defaults
    )

    public init(
        records: [Record],
        importExport: ImportExportPreferences
    ) {
        self.records = records
        self.importExport = importExport
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyRecords = try container.decodeIfPresent([LegacyRecord].self, forKey: .records) ?? []
        records = legacyRecords.compactMap(\.currentRecord)
        importExport = try container.decodeIfPresent(
            ImportExportPreferences.self,
            forKey: .importExport
        ) ?? .defaults
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(records, forKey: .records)
        try container.encode(importExport, forKey: .importExport)
    }

    public static func load(from defaults: UserDefaults = .standard) -> SecurityKeyMaterialSettings {
        guard let data = defaults.data(forKey: Key.storage),
              let settings = try? JSONDecoder().decode(SecurityKeyMaterialSettings.self, from: data)
        else {
            return .defaults
        }
        return settings
    }

    /// Identifiers for material recorded by a retired security family. The
    /// caller uses these to delete the corresponding Keychain payloads before
    /// the sanitized S/MIME-only catalog is persisted.
    public static func retiredRecordIDs(from defaults: UserDefaults = .standard) -> [String] {
        guard let data = defaults.data(forKey: Key.storage),
              let catalog = try? JSONDecoder().decode(LegacyCatalog.self, from: data)
        else {
            return []
        }
        return catalog.records.filter { $0.family != SecurityKeyMaterialFamily.smime.rawValue }.map(\.id)
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Key.storage)
    }

    public mutating func upsert(_ record: Record) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
            return
        }
        records.append(record)
    }

    @discardableResult
    public mutating func removeRecord(id: String) -> Bool {
        let originalCount = records.count
        records.removeAll { $0.id == id }
        return records.count != originalCount
    }

    @discardableResult
    public mutating func removeAllRecords(in family: SecurityKeyMaterialFamily? = nil) -> Int {
        let removedCount: Int
        if let family {
            removedCount = records.filter { $0.family == family }.count
            records.removeAll { $0.family == family }
        } else {
            removedCount = records.count
            records.removeAll()
        }
        return removedCount
    }

    public var trustedSigningRecordCount: Int {
        trustedRecordCount(needsSigning: true)
    }

    public var trustedEncryptionRecordCount: Int {
        trustedRecordCount(needsEncryption: true)
    }

    private func trustedRecordCount(
        needsSigning: Bool = false,
        needsEncryption: Bool = false
    ) -> Int {
        records.filter { record in
            guard record.trust == .trusted else { return false }
            if needsSigning, !record.canSign {
                return false
            }
            if needsEncryption, !record.canEncrypt {
                return false
            }
            return true
        }.count
    }

    public struct Record: Equatable, Codable, Sendable, Identifiable {
        public let id: String
        public var family: SecurityKeyMaterialFamily
        public var label: String
        public var emailAddress: String?
        public var fingerprint: String
        public var algorithm: String
        public var canSign: Bool
        public var canEncrypt: Bool
        public var hasPrivateMaterial: Bool
        public var trust: SecurityKeyMaterialTrustState
        public var importedAt: Date
        public var expiresAt: Date?

        public init(
            id: String,
            family: SecurityKeyMaterialFamily,
            label: String,
            emailAddress: String? = nil,
            fingerprint: String,
            algorithm: String,
            canSign: Bool,
            canEncrypt: Bool,
            hasPrivateMaterial: Bool,
            trust: SecurityKeyMaterialTrustState,
            importedAt: Date,
            expiresAt: Date? = nil
        ) {
            self.id = id
            self.family = family
            self.label = label
            self.emailAddress = emailAddress
            self.fingerprint = fingerprint
            self.algorithm = algorithm
            self.canSign = canSign
            self.canEncrypt = canEncrypt
            self.hasPrivateMaterial = hasPrivateMaterial
            self.trust = trust
            self.importedAt = importedAt
            self.expiresAt = expiresAt
        }
    }

    public struct ImportExportPreferences: Equatable, Codable, Sendable {
        public var smimeExportFormat: SecuritySMIMEExportFormat
        public var includePrivateMaterialInExport: Bool
        public var allowReplacingExistingMaterialOnImport: Bool

        public static let defaults = ImportExportPreferences(
            smimeExportFormat: .pkcs12,
            includePrivateMaterialInExport: false,
            allowReplacingExistingMaterialOnImport: false
        )

        public init(
            smimeExportFormat: SecuritySMIMEExportFormat,
            includePrivateMaterialInExport: Bool,
            allowReplacingExistingMaterialOnImport: Bool
        ) {
            self.smimeExportFormat = smimeExportFormat
            self.includePrivateMaterialInExport = includePrivateMaterialInExport
            self.allowReplacingExistingMaterialOnImport = allowReplacingExistingMaterialOnImport
        }
    }

    private enum CodingKeys: String, CodingKey {
        case records
        case importExport
    }

    private struct LegacyCatalog: Decodable {
        let records: [LegacyRecord]
    }

    private struct LegacyRecord: Decodable {
        let id: String
        let family: String
        let label: String
        let emailAddress: String?
        let fingerprint: String
        let algorithm: String
        let canSign: Bool
        let canEncrypt: Bool
        let hasPrivateMaterial: Bool
        let trust: SecurityKeyMaterialTrustState
        let importedAt: Date
        let expiresAt: Date?

        var currentRecord: Record? {
            guard family == SecurityKeyMaterialFamily.smime.rawValue else { return nil }
            return Record(
                id: id,
                family: .smime,
                label: label,
                emailAddress: emailAddress,
                fingerprint: fingerprint,
                algorithm: algorithm,
                canSign: canSign,
                canEncrypt: canEncrypt,
                hasPrivateMaterial: hasPrivateMaterial,
                trust: trust,
                importedAt: importedAt,
                expiresAt: expiresAt
            )
        }
    }
}

public enum SecurityKeyMaterialDestructiveAction: String, Sendable, CaseIterable {
    case removeSelectedItem
    case removeAllSMIME
    case removeAllMaterial
}

public struct SecurityKeyMaterialConfirmation: Equatable, Sendable {
    public let title: String
    public let message: String
    public let confirmButtonTitle: String
    public let typedPhrase: String?

    public var requiresTypedConfirmation: Bool {
        typedPhrase != nil
    }

    public func isSatisfied(by candidate: String?) -> Bool {
        guard let typedPhrase else { return true }
        return candidate?.trimmingCharacters(in: .whitespacesAndNewlines) == typedPhrase
    }
}

public enum SecurityKeyMaterialConfirmationPolicy {
    public static let bulkDeletePhrase = "DELETE"

    public static func confirmation(
        for action: SecurityKeyMaterialDestructiveAction,
        subjectLabel: String? = nil
    ) -> SecurityKeyMaterialConfirmation {
        switch action {
        case .removeSelectedItem:
            let label = subjectLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
            let display = (label?.isEmpty == false) ? label! : String(localized: "this item", bundle: .module)
            return SecurityKeyMaterialConfirmation(
                title: String(localized: "Remove key material?", bundle: .module),
                message: String(localized: "This removes \(display) from local key storage on this device.", bundle: .module),
                confirmButtonTitle: String(localized: "Remove", bundle: .module),
                typedPhrase: nil
            )
        case .removeAllSMIME:
            return SecurityKeyMaterialConfirmation(
                title: String(localized: "Remove all S/MIME certificates?", bundle: .module),
                message: String(
                    localized: "Type DELETE to confirm removing all local S/MIME certificates and keys from this device.",
                    bundle: .module
                ),
                confirmButtonTitle: String(localized: "Remove All", bundle: .module),
                typedPhrase: bulkDeletePhrase
            )
        case .removeAllMaterial:
            return SecurityKeyMaterialConfirmation(
                title: String(localized: "Remove all key and certificate material?", bundle: .module),
                message: String(
                    localized: "Type DELETE to confirm removing all local signing and encryption material from this device.",
                    bundle: .module
                ),
                confirmButtonTitle: String(localized: "Remove Everything", bundle: .module),
                typedPhrase: bulkDeletePhrase
            )
        }
    }
}
