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

#if os(macOS)
@testable import BrevMail
import BrevSettings
import Foundation
@preconcurrency import Security
import Testing

/// In-memory `SecurityKeyMaterialStore` so the resolver's record-filtering and
/// PKCS#12 import path can be exercised without touching the system Keychain.
private actor FakeMaterialStore: SecurityKeyMaterialStore {
    private var storage: [String: Data]
    init(_ storage: [String: Data]) { self.storage = storage }
    func material(for recordID: String) async throws -> Data? { storage[recordID] }
    func setMaterial(_ data: Data, for recordID: String) async throws { storage[recordID] = data }
    func deleteMaterial(for recordID: String) async throws { storage[recordID] = nil }
}

private let smimeEmail = "smime-test@brev.example"
private let smimePassphrase = "brevtest"

// Same passphrase-protected ("brevtest") PKCS#12 fixture used by the BrevCrypto
// S/MIME engine tests — a self-signed identity for smime-test@brev.example.
private let p12Base64 = "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"

private func signingRecord(id: String = "sign-1") -> SecurityKeyMaterialSettings.Record {
    SecurityKeyMaterialSettings.Record(
        id: id,
        family: .smime,
        label: "S/MIME test",
        emailAddress: smimeEmail,
        fingerprint: "FP",
        algorithm: "rsa",
        canSign: true,
        canEncrypt: true,
        hasPrivateMaterial: true,
        trust: .trusted,
        importedAt: Date(timeIntervalSince1970: 0)
    )
}

private func settings(_ records: [SecurityKeyMaterialSettings.Record]) -> SecurityKeyMaterialSettings {
    SecurityKeyMaterialSettings(records: records, importExport: .defaults)
}

@Suite("KeychainSMIMEResolver", .serialized)
struct KeychainSMIMEResolverTests {
    @Test("resolves a signing identity from a trusted S/MIME PKCS#12 record")
    func resolvesSigningIdentity() async throws {
        let record = signingRecord()
        let resolver = KeychainSMIMEResolver(
            settingsProvider: { settings([record]) },
            materialStore: FakeMaterialStore([record.id: try! #require(Data(base64Encoded: p12Base64))]),
            pkcs12Passphrase: { smimePassphrase }
        )
        let identity = await resolver.signingIdentity(forSenderEmail: "Test <\(smimeEmail)>")
        #expect(identity != nil)
    }

    @Test("returns nil signing identity when the sender does not match")
    func noSigningIdentityForOtherSender() async throws {
        let record = signingRecord()
        let resolver = try KeychainSMIMEResolver(
            settingsProvider: { settings([record]) },
            materialStore: FakeMaterialStore([record.id: #require(Data(base64Encoded: p12Base64))]),
            pkcs12Passphrase: { smimePassphrase }
        )
        let identity = await resolver.signingIdentity(forSenderEmail: "someone-else@brev.example")
        #expect(identity == nil)
    }

    @Test("fails closed (nil identity) when the PKCS#12 passphrase is wrong")
    func wrongPassphraseFailsClosed() async throws {
        let record = signingRecord()
        let resolver = try KeychainSMIMEResolver(
            settingsProvider: { settings([record]) },
            materialStore: FakeMaterialStore([record.id: #require(Data(base64Encoded: p12Base64))]),
            pkcs12Passphrase: { "not-the-passphrase" }
        )
        let identity = await resolver.signingIdentity(forSenderEmail: smimeEmail)
        #expect(identity == nil)
    }

    @Test("extracts a recipient certificate from a PKCS#12 record (leaf cert fallback)")
    func resolvesEncryptionCertificate() async throws {
        let record = signingRecord(id: "enc-1")
        let resolver = try KeychainSMIMEResolver(
            settingsProvider: { settings([record]) },
            materialStore: FakeMaterialStore([record.id: #require(Data(base64Encoded: p12Base64))]),
            pkcs12Passphrase: { smimePassphrase }
        )
        let certs = await resolver.encryptionCertificates(forRecipients: [smimeEmail])
        #expect(certs[smimeEmail] != nil)
    }

    @Test("returns no certificate for an untrusted record")
    func untrustedRecordIgnored() async throws {
        var mutableRecord = signingRecord()
        mutableRecord.trust = .untrusted
        let record = mutableRecord
        let resolver = try KeychainSMIMEResolver(
            settingsProvider: { settings([record]) },
            materialStore: FakeMaterialStore([record.id: #require(Data(base64Encoded: p12Base64))]),
            pkcs12Passphrase: { smimePassphrase }
        )
        let certs = await resolver.encryptionCertificates(forRecipients: [smimeEmail])
        #expect(certs.isEmpty)
    }
}
#endif
