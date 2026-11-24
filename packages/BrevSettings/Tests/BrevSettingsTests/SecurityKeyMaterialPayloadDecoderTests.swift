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

@testable import BrevSettings
import Foundation
@preconcurrency import Security
import Testing

@Suite("SecurityKeyMaterialPayloadDecoder")
struct SecurityKeyMaterialPayloadDecoderTests {
    @Test("stores unencoded certificate text as UTF-8")
    func storesUnencodedCertificateTextAsUTF8() throws {
        let payload = "certificate text"

        let data = try SecurityKeyMaterialPayloadDecoder.materialData(
            from: payload,
            family: .smime
        )

        #expect(data == Data(payload.utf8))
    }

    @Test("decodes pasted base64 PKCS12 material for S/MIME records")
    func decodesBase64PKCS12Material() throws {
        let raw = Data([0x30, 0x82, 0x01, 0x0A, 0x02, 0x01])
        let pasted = raw.base64EncodedString()

        let data = try SecurityKeyMaterialPayloadDecoder.materialData(
            from: pasted,
            family: .smime
        )

        #expect(data == raw)
    }

    @Test("decodes PEM-armored PKCS12 material for S/MIME records")
    func decodesPEMArmoredPKCS12Material() throws {
        let raw = Data([0x30, 0x82, 0x02, 0x0B, 0x02, 0x01])
        let pasted = """
        -----BEGIN PKCS12-----
        \(raw.base64EncodedString())
        -----END PKCS12-----
        """

        let data = try SecurityKeyMaterialPayloadDecoder.materialData(
            from: pasted,
            family: .smime
        )

        #expect(data == raw)
    }

    @Test("validates PKCS#12 signing identity passphrases and rejects wrong passphrases")
    func validatesPKCS12Passphrases() throws {
        // Same self-signed test PKCS#12 fixture ("brevtest") used across Brev S/MIME tests.
        let p12Base64 = "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"
        let p12Data = try SecurityKeyMaterialPayloadDecoder.materialData(from: p12Base64, family: .smime)

        try SecurityKeyMaterialPayloadDecoder.validatePKCS12SigningIdentity(p12Data, passphrase: "brevtest")

        #expect(throws: SecurityKeyMaterialImportError.invalidPKCS12OrPassphrase) {
            try SecurityKeyMaterialPayloadDecoder.validatePKCS12SigningIdentity(p12Data, passphrase: "wrong")
        }
        #expect(throws: SecurityKeyMaterialImportError.invalidPKCS12OrPassphrase) {
            try SecurityKeyMaterialPayloadDecoder.validatePKCS12SigningIdentity(p12Data, passphrase: "")
        }
    }

    @Test("exports binary DER X.509 certificates honoring PEM vs DER format and inspects actual bytes for private material")
    func exportsBinaryDERAndGuardsPrivatePKCS12() throws {
        let p12Base64 = "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"
        let p12Data = try SecurityKeyMaterialPayloadDecoder.materialData(from: p12Base64, family: .smime)

        // Extract leaf X.509 DER certificate via isolated import (never touches default Keychain).
        let imported = try #require(SecurityKeyMaterialPayloadDecoder.importPKCS12(p12Data, passphrase: "brevtest"))
        var certOpt: SecCertificate?
        try #require(SecIdentityCopyCertificate(imported.identity, &certOpt) == errSecSuccess)
        let derCert = try SecCertificateCopyData(#require(certOpt)) as Data

        let publicCertRecord = SecurityKeyMaterialSettings.Record(
            id: "pub-cert",
            family: .smime,
            label: "Public Cert",
            emailAddress: "smime-test@brev.example",
            fingerprint: "FP1",
            algorithm: "RSA",
            canSign: false,
            canEncrypt: true,
            hasPrivateMaterial: false,
            trust: .trusted,
            importedAt: Date(timeIntervalSince1970: 0)
        )

        // PEM format outputs -----BEGIN CERTIFICATE----- armor and round-trips cleanly.
        let pemPrefs = SecurityKeyMaterialSettings.ImportExportPreferences(
            smimeExportFormat: .pem,
            includePrivateMaterialInExport: false,
            allowReplacingExistingMaterialOnImport: false
        )
        let exportedPEM = try SecurityKeyMaterialPayloadDecoder.formattedExportPayload(
            from: derCert,
            record: publicCertRecord,
            preferences: pemPrefs
        )
        #expect(exportedPEM.hasPrefix("-----BEGIN CERTIFICATE-----\n"))
        #expect(exportedPEM.hasSuffix("\n-----END CERTIFICATE-----"))
        #expect(try SecurityKeyMaterialPayloadDecoder.materialData(from: exportedPEM, family: .smime) == derCert)

        // DER format outputs raw base64-encoded DER (NO PEM armor) and round-trips cleanly.
        let derPrefs = SecurityKeyMaterialSettings.ImportExportPreferences(
            smimeExportFormat: .der,
            includePrivateMaterialInExport: false,
            allowReplacingExistingMaterialOnImport: false
        )
        let exportedDER = try SecurityKeyMaterialPayloadDecoder.formattedExportPayload(
            from: derCert,
            record: publicCertRecord,
            preferences: derPrefs
        )
        #expect(!exportedDER.contains("-----BEGIN"))
        #expect(try SecurityKeyMaterialPayloadDecoder.materialData(from: exportedDER, family: .smime) == derCert)

        // Exporting a public X.509 certificate as PKCS#12 fails cleanly instead of returning PEM.
        #expect(throws: SecurityKeyMaterialExportError.unsupportedExportFormat) {
            _ = try SecurityKeyMaterialPayloadDecoder.formattedExportPayload(
                from: derCert,
                record: publicCertRecord,
                preferences: .defaults
            )
        }

        // Unlabeled PKCS#12 (record.hasPrivateMaterial == false) is STILL blocked by byte inspection!
        let unlabeledPrivateRecord = SecurityKeyMaterialSettings.Record(
            id: "unlabeled-p12",
            family: .smime,
            label: "Unlabeled P12",
            emailAddress: "smime-test@brev.example",
            fingerprint: "FP-UNLABELED",
            algorithm: "RSA",
            canSign: true,
            canEncrypt: true,
            hasPrivateMaterial: false,
            trust: .trusted,
            importedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(SecurityKeyMaterialPayloadDecoder.containsPrivateMaterial(in: p12Data))
        #expect(throws: SecurityKeyMaterialExportError.privateMaterialExportDisabled) {
            _ = try SecurityKeyMaterialPayloadDecoder.formattedExportPayload(
                from: p12Data,
                record: unlabeledPrivateRecord,
                preferences: .defaults
            )
        }

        let exportAllowedPrefs = SecurityKeyMaterialSettings.ImportExportPreferences(
            smimeExportFormat: .pkcs12,
            includePrivateMaterialInExport: true,
            allowReplacingExistingMaterialOnImport: false
        )
        let exportedP12 = try SecurityKeyMaterialPayloadDecoder.formattedExportPayload(
            from: p12Data,
            record: unlabeledPrivateRecord,
            preferences: exportAllowedPrefs
        )
        #expect(!exportedP12.contains("-----BEGIN"))
        #expect(try SecurityKeyMaterialPayloadDecoder.materialData(from: exportedP12, family: .smime) == p12Data)

        // Exporting a PKCS#12 archive as PEM rejects unsupported conversion cleanly.
        let pemAllowedPrefs = SecurityKeyMaterialSettings.ImportExportPreferences(
            smimeExportFormat: .pem,
            includePrivateMaterialInExport: true,
            allowReplacingExistingMaterialOnImport: false
        )
        #expect(throws: SecurityKeyMaterialExportError.unsupportedExportFormat) {
            _ = try SecurityKeyMaterialPayloadDecoder.formattedExportPayload(
                from: p12Data,
                record: unlabeledPrivateRecord,
                preferences: pemAllowedPrefs
            )
        }
    }

    #if os(macOS)
    @Test("isolated PKCS#12 validation does not pollute the default macOS login Keychain")
    func isolatedPKCS12ValidationDoesNotPolluteDefaultKeychain() throws {
        let uniqueCN = "Brev-Isolated-Test-\(UUID().uuidString)"
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-p12-iso-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let keyURL = dir.appendingPathComponent("key.pem")
        let certURL = dir.appendingPathComponent("cert.pem")
        let p12URL = dir.appendingPathComponent("id.p12")

        func runOpenSSL(_ args: [String]) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            p.arguments = args
            try p.run()
            p.waitUntilExit()
            try #require(p.terminationStatus == 0)
        }

        try runOpenSSL([
            "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", keyURL.path, "-out", certURL.path,
            "-days", "1", "-subj", "/CN=\(uniqueCN)"
        ])
        try runOpenSSL([
            "pkcs12", "-export", "-inkey", keyURL.path, "-in", certURL.path,
            "-out", p12URL.path, "-passout", "pass:brevtest"
        ])

        let p12Data = try Data(contentsOf: p12URL)
        try SecurityKeyMaterialPayloadDecoder.validatePKCS12SigningIdentity(p12Data, passphrase: "brevtest")

        // Verify the unique certificate does NOT exist in the default login Keychain.
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecMatchSubjectContains as String: uniqueCN,
            kSecReturnRef as String: true
        ]
        var found: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        #expect(status == errSecItemNotFound)
    }
    #endif
}
