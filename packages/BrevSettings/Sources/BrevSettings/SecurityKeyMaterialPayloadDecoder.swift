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

/// Validation errors surfaced when importing S/MIME key material.
public enum SecurityKeyMaterialImportError: Error, LocalizedError, Sendable, Equatable {
    /// The PKCS#12 archive could not be unlocked with the supplied passphrase or contained no identity.
    case invalidPKCS12OrPassphrase

    public var errorDescription: String? {
        switch self {
        case .invalidPKCS12OrPassphrase:
            String(
                localized: "Couldn't unlock the PKCS#12 signing identity. Check the certificate data and passphrase.",
                bundle: .module
            )
        }
    }
}

/// Errors surfaced when exporting stored S/MIME key material.
public enum SecurityKeyMaterialExportError: Error, LocalizedError, Sendable, Equatable {
    /// Exporting private key material requires explicit opt-in in import/export preferences.
    case privateMaterialExportDisabled

    public var errorDescription: String? {
        switch self {
        case .privateMaterialExportDisabled:
            String(
                localized: "Private material export is disabled. Enable “Allow private material in exports” to export this item.",
                bundle: .module
            )
        }
    }
}

public enum SecurityKeyMaterialPayloadDecoder {
    public static func materialData(
        from payload: String,
        family: SecurityKeyMaterialFamily
    ) throws -> Data {
        switch family {
        case .smime:
            return decodedSMIMEMaterial(from: payload) ?? Data(payload.utf8)
        }
    }

    /// Verifies that `data` is a readable PKCS#12 archive containing an identity
    /// unlockable with `passphrase`. Fails closed on corrupt data or wrong passphrases.
    public static func validatePKCS12SigningIdentity(_ data: Data, passphrase: String) throws {
        let options = [kSecImportExportPassphrase as String: passphrase] as CFDictionary
        var itemsOpt: CFArray?
        let status = SecPKCS12Import(data as CFData, options, &itemsOpt)
        guard status == errSecSuccess,
              let items = itemsOpt as? [[String: Any]],
              items.contains(where: { $0[kSecImportItemIdentity as String] != nil })
        else {
            throw SecurityKeyMaterialImportError.invalidPKCS12OrPassphrase
        }
    }

    /// Formats stored key material for text export while enforcing the
    /// private-material export opt-in guard.
    ///
    /// - Binary DER X.509 certificates are PEM-wrapped (`-----BEGIN CERTIFICATE-----`).
    /// - Binary PKCS#12 archives and other binary payloads are base64-encoded (64-char lines).
    /// - Already PEM-armored UTF-8 text is returned unchanged.
    public static func formattedExportPayload(
        from data: Data,
        record: SecurityKeyMaterialSettings.Record,
        preferences: SecurityKeyMaterialSettings.ImportExportPreferences
    ) throws -> String {
        if record.hasPrivateMaterial, !preferences.includePrivateMaterialInExport {
            throw SecurityKeyMaterialExportError.privateMaterialExportDisabled
        }

        if let text = String(data: data, encoding: .utf8),
           text.contains("-----BEGIN ") {
            return text
        }

        let base64Lines = data.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        if SecCertificateCreateWithData(nil, data as CFData) != nil {
            return "-----BEGIN CERTIFICATE-----\n\(base64Lines)\n-----END CERTIFICATE-----"
        }

        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        return base64Lines
    }

    private static func decodedSMIMEMaterial(from payload: String) -> Data? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let direct = Data(base64Encoded: base64Normalized(trimmed)) {
            return direct
        }

        let body = trimmed
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("-----") }
            .joined()

        return Data(base64Encoded: base64Normalized(body))
    }

    private static func base64Normalized(_ value: String) -> String {
        value.filter { !$0.isWhitespace }
    }
}
