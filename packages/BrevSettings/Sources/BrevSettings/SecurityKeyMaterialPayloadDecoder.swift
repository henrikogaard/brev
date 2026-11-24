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
    /// The stored material cannot be represented in the user's selected S/MIME export format.
    case unsupportedExportFormat

    public var errorDescription: String? {
        switch self {
        case .privateMaterialExportDisabled:
            String(
                localized: "Private material export is disabled. Enable “Allow private material in exports” to export this item.",
                bundle: .module
            )
        case .unsupportedExportFormat:
            String(
                localized: "This item can't be exported in the selected format. Choose a matching S/MIME export format.",
                bundle: .module
            )
        }
    }
}

/// Result of importing a PKCS#12 bundle without polluting the user's default macOS Keychain.
///
/// Hold `lifetimeToken` for as long as `identity` is used for signing so the
/// temporary macOS keychain backing the private key stays alive and is deleted
/// automatically on deallocation.
public struct IsolatedPKCS12ImportResult: @unchecked Sendable {
    /// The unlocked signing identity (leaf certificate + private key).
    public let identity: SecIdentity
    /// Supporting intermediate CA certificates returned in `kSecImportItemCertChain` (leaf excluded).
    public let intermediateCertificates: [SecCertificate]
    /// RAII lifetime guard keeping an isolated temporary macOS `SecKeychain` alive until deallocated.
    public let lifetimeToken: (any Sendable)?
}

#if os(macOS)
/// Owns an ephemeral file-based `SecKeychain` in a unique temp directory so
/// `SecPKCS12Import` never writes keys or certificates into the user's default
/// login Keychain. Deleted automatically on `deinit`.
private final class EphemeralMacOSKeychainLease: @unchecked Sendable {
    let keychain: SecKeychain
    private let directoryURL: URL

    init?() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-p12-ephemeral-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        var randomBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes) == errSecSuccess else {
            try? FileManager.default.removeItem(at: dir)
            return nil
        }
        let password = randomBytes.map { String(format: "%02x", $0) }.joined()
        let path = dir.appendingPathComponent("ephemeral.keychain-db").path

        var created: SecKeychain?
        let status = password.withCString { cStr in
            SecKeychainCreate(path, UInt32(strlen(cStr)), cStr, false, nil, &created)
        }
        guard status == errSecSuccess, let keychain = created else {
            try? FileManager.default.removeItem(at: dir)
            return nil
        }
        self.keychain = keychain
        directoryURL = dir
    }

    deinit {
        _ = SecKeychainDelete(keychain)
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
#endif

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

    /// Imports a PKCS#12 archive in isolation (using an ephemeral temporary
    /// `SecKeychain` on macOS so nothing is ever added to the user's default
    /// login Keychain) and returns its identity, supporting intermediate CA
    /// certificates, and lifetime guard.
    public static func importPKCS12(
        _ data: Data,
        passphrase: String
    ) -> IsolatedPKCS12ImportResult? {
        #if os(macOS)
        guard let lease = EphemeralMacOSKeychainLease() else { return nil }
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: passphrase,
            kSecImportExportKeychain as String: lease.keychain
        ]
        let lifetimeToken: (any Sendable)? = lease
        #else
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: passphrase
        ]
        let lifetimeToken: (any Sendable)? = nil
        #endif

        var itemsOpt: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &itemsOpt)
        guard status == errSecSuccess, let items = itemsOpt as? [[String: Any]] else {
            return nil
        }

        for item in items {
            guard let value = item[kSecImportItemIdentity as String] else { continue }
            let identity = (value as! SecIdentity)
            var leafCertOpt: SecCertificate?
            let leafDER: Data? = if SecIdentityCopyCertificate(identity, &leafCertOpt) == errSecSuccess,
                                    let leafCert = leafCertOpt {
                SecCertificateCopyData(leafCert) as Data
            } else {
                nil
            }
            let rawChain = (item[kSecImportItemCertChain as String] as? [SecCertificate]) ?? []
            // Re-materialize supporting certs as pure in-memory DER SecCertificates.
            let intermediates: [SecCertificate] = rawChain.compactMap { cert in
                let certDER = SecCertificateCopyData(cert) as Data
                if let leafDER, certDER == leafDER { return nil }
                return SecCertificateCreateWithData(nil, certDER as CFData)
            }
            return IsolatedPKCS12ImportResult(
                identity: identity,
                intermediateCertificates: intermediates,
                lifetimeToken: lifetimeToken
            )
        }
        return nil
    }

    /// Verifies that `data` is a readable PKCS#12 archive containing an identity
    /// unlockable with `passphrase`, without polluting the default macOS Keychain.
    public static func validatePKCS12SigningIdentity(_ data: Data, passphrase: String) throws {
        guard importPKCS12(data, passphrase: passphrase) != nil else {
            throw SecurityKeyMaterialImportError.invalidPKCS12OrPassphrase
        }
    }

    /// Inspects the actual stored bytes to detect private key material (PKCS#12
    /// PFX ASN.1 archives, PKCS#8 PrivateKeyInfo, or PEM private key blocks) so
    /// export protection never relies solely on user-supplied record metadata.
    public static func containsPrivateMaterial(in data: Data) -> Bool {
        if let text = String(data: data, encoding: .utf8) {
            let upper = text.uppercased()
            if upper.contains("PRIVATE KEY") || upper.contains("-----BEGIN PKCS12-----") {
                return true
            }
        }
        return isPKCS12Archive(data) || isPKCS8PrivateKey(data)
    }

    /// Formats stored key material for text export while enforcing the
    /// private-material export opt-in guard (checked against BOTH metadata and
    /// actual bytes) and honoring `preferences.smimeExportFormat`.
    public static func formattedExportPayload(
        from data: Data,
        record: SecurityKeyMaterialSettings.Record,
        preferences: SecurityKeyMaterialSettings.ImportExportPreferences
    ) throws -> String {
        let hasPrivateBytes = containsPrivateMaterial(in: data)
        if record.hasPrivateMaterial || hasPrivateBytes, !preferences.includePrivateMaterialInExport {
            throw SecurityKeyMaterialExportError.privateMaterialExportDisabled
        }

        let isPKCS12 = isPKCS12Archive(data)
        let certDER = x509CertificateDER(from: data)

        switch preferences.smimeExportFormat {
        case .pem:
            if let certDER {
                let base64 = certDER.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
                return "-----BEGIN CERTIFICATE-----\n\(base64)\n-----END CERTIFICATE-----"
            }
            if !isPKCS12, let text = String(data: data, encoding: .utf8), text.contains("-----BEGIN ") {
                return text
            }
            throw SecurityKeyMaterialExportError.unsupportedExportFormat

        case .der:
            if let certDER {
                return certDER.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
            }
            throw SecurityKeyMaterialExportError.unsupportedExportFormat

        case .pkcs12:
            if isPKCS12 {
                return data.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
            }
            if let text = String(data: data, encoding: .utf8),
               text.uppercased().contains("-----BEGIN PKCS12-----") {
                return text
            }
            throw SecurityKeyMaterialExportError.unsupportedExportFormat
        }
    }

    // MARK: - Inspection helpers

    /// Returns raw X.509 DER bytes when `data` is either a DER X.509 certificate
    /// or a PEM-armored `CERTIFICATE` block.
    private static func x509CertificateDER(from data: Data) -> Data? {
        if SecCertificateCreateWithData(nil, data as CFData) != nil {
            return data
        }
        guard let text = String(data: data, encoding: .utf8),
              text.contains("-----BEGIN CERTIFICATE-----"),
              let decoded = decodedSMIMEMaterial(from: text),
              SecCertificateCreateWithData(nil, decoded as CFData) != nil
        else {
            return nil
        }
        return decoded
    }

    /// Detects a DER-encoded PKCS#12 `PFX` structure:
    /// `SEQUENCE { INTEGER 3, SEQUENCE { OID id-data (1.2.840.113549.1.7.1), ... }, ... }`.
    private static func isPKCS12Archive(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var root = 0
        guard let outer = readDERElement(in: bytes, cursor: &root, limit: bytes.count),
              outer.tag == 0x30
        else { return false }

        var seqCursor = outer.valueStart
        guard let version = readDERElement(in: bytes, cursor: &seqCursor, limit: outer.valueEnd),
              version.tag == 0x02,
              version.valueEnd - version.valueStart == 1,
              bytes[version.valueStart] == 0x03
        else { return false }

        guard let authSafe = readDERElement(in: bytes, cursor: &seqCursor, limit: outer.valueEnd),
              authSafe.tag == 0x30
        else { return false }

        var contentCursor = authSafe.valueStart
        guard let contentType = readDERElement(in: bytes, cursor: &contentCursor, limit: authSafe.valueEnd),
              contentType.tag == 0x06
        else { return false }

        // OID 1.2.840.113549.1.7.1 (id-data)
        let idDataOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x01]
        return Array(bytes[contentType.valueStart ..< contentType.valueEnd]) == idDataOID
    }

    /// Detects a DER-encoded PKCS#8 `PrivateKeyInfo` (`SEQUENCE { INTEGER 0, SEQUENCE { OID }, OCTET STRING }`).
    private static func isPKCS8PrivateKey(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var root = 0
        guard let outer = readDERElement(in: bytes, cursor: &root, limit: bytes.count),
              outer.tag == 0x30
        else { return false }

        var seqCursor = outer.valueStart
        guard let version = readDERElement(in: bytes, cursor: &seqCursor, limit: outer.valueEnd),
              version.tag == 0x02,
              version.valueEnd - version.valueStart == 1,
              bytes[version.valueStart] == 0x00,
              let alg = readDERElement(in: bytes, cursor: &seqCursor, limit: outer.valueEnd),
              alg.tag == 0x30,
              let keyOctets = readDERElement(in: bytes, cursor: &seqCursor, limit: outer.valueEnd),
              keyOctets.tag == 0x04
        else { return false }
        return true
    }

    private struct DERHeader {
        let tag: UInt8
        let valueStart: Int
        let valueEnd: Int
    }

    private static func readDERElement(
        in bytes: [UInt8],
        cursor: inout Int,
        limit: Int
    ) -> DERHeader? {
        guard cursor < limit else { return nil }
        let tag = bytes[cursor]
        cursor += 1
        guard cursor < limit else { return nil }
        let firstLen = bytes[cursor]
        cursor += 1

        let contentLength: Int
        if firstLen < 0x80 {
            contentLength = Int(firstLen)
        } else {
            let octets = Int(firstLen & 0x7F)
            if octets == 0 {
                // BER indefinite length (common in OpenSSL PKCS#12 PFX) — treat remainder up to limit as content.
                let start = cursor
                cursor = limit
                return DERHeader(tag: tag, valueStart: start, valueEnd: limit)
            }
            guard octets <= 4, cursor + octets <= limit else { return nil }
            var value = 0
            for idx in 0 ..< octets {
                value = (value << 8) | Int(bytes[cursor + idx])
            }
            cursor += octets
            contentLength = value
        }

        let start = cursor
        guard contentLength >= 0, start <= limit - contentLength else { return nil }
        let end = start + contentLength
        cursor = end
        return DERHeader(tag: tag, valueStart: start, valueEnd: end)
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
