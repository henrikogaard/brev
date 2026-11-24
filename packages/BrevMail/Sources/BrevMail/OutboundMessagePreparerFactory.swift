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
import BrevCrypto
import BrevSettings
import Foundation
import Security

/// Builds the production S/MIME engine, backed by the local Keychain key store.
/// Returns the `BrevBackend` protocol type so the app targets can inject it into
/// `IMAPAccountConnector.standard(outboundMessagePreparer:)` without importing
/// `BrevCrypto`.
///
/// macOS uses Apple's `CMSEncoder` and iOS uses `BrevCrypto`'s pure-Swift RFC
/// 8551/5652 CMS DER encoder; both platforms resolve material strictly from the
/// local Keychain and fail closed when required certificates or identities are
/// missing.
public enum OutboundMessagePreparerFactory {
    /// Creates the standard local-Keychain S/MIME outbound preparer.
    public static func makeStandard(
        settingsProvider: @escaping @Sendable () -> SecurityKeyMaterialSettings = {
            SecurityKeyMaterialSettings.load()
        },
        materialStore: any SecurityKeyMaterialStore = SecurityKeychainMaterialStore()
    ) -> any OutboundMessagePreparing {
        SMIMEOutboundMessagePreparer(
            resolver: KeychainSMIMEResolver(
                settingsProvider: settingsProvider,
                materialStore: materialStore
            )
        )
    }

    /// Creates an outbound S/MIME preparer forced onto the cross-platform
    /// pure-Swift CMS encoder (mirrors the iOS production encoding path on macOS).
    static func makePureSwift(
        settingsProvider: @escaping @Sendable () -> SecurityKeyMaterialSettings,
        materialStore: any SecurityKeyMaterialStore
    ) -> any OutboundMessagePreparing {
        SMIMEOutboundMessagePreparer(
            resolver: KeychainSMIMEResolver(
                settingsProvider: settingsProvider,
                materialStore: materialStore
            ),
            encodingBackend: .pureSwift
        )
    }
}

/// Resolves S/MIME (CMS) key material from the local Keychain key store for the
/// outbound engine. Local-only — no directory lookups
/// (`docs/design/privacy-and-security.md`). Only `.trusted` `.smime` records
/// with the required capability are eligible (fail-closed before use).
///
/// Signing material is a PKCS#12 blob (certificate + private key); recipient
/// encryption material is either a DER certificate or a PKCS#12 from which the
/// leaf certificate is taken. A passphrase-protected PKCS#12 needs its
/// passphrase supplied via `pkcs12Passphrase`; the default empty passphrase
/// matches material stored without one, and a wrong/absent passphrase fails
/// closed (the identity resolves to nil → `missingSigningIdentity`).
struct KeychainSMIMEResolver: SMIMEIdentityResolving {
    let settingsProvider: @Sendable () -> SecurityKeyMaterialSettings
    let materialStore: any SecurityKeyMaterialStore
    let pkcs12Passphrase: @Sendable () -> String

    init(
        settingsProvider: @escaping @Sendable () -> SecurityKeyMaterialSettings,
        materialStore: any SecurityKeyMaterialStore,
        pkcs12Passphrase: @escaping @Sendable () -> String = { "" }
    ) {
        self.settingsProvider = settingsProvider
        self.materialStore = materialStore
        self.pkcs12Passphrase = pkcs12Passphrase
    }

    func signingIdentity(forSenderEmail email: String) async -> SecIdentity? {
        await signingMaterial(forSenderEmail: email)?.identity
    }

    func signingMaterial(forSenderEmail email: String) async -> SMIMESigningMaterial? {
        let records = settingsProvider().records
        guard let record = resolveRecord(in: records, capability: .signing, email: email),
              let material = try? await materialStore.material(for: record.id)
        else {
            return nil
        }
        let passphrase = await resolvedPassphrase(for: record.id)
        return Self.signingMaterial(fromPKCS12: material, passphrase: passphrase)
    }

    func encryptionCertificates(forRecipients emails: [String]) async -> [String: SecCertificate] {
        let records = settingsProvider().records
        var result: [String: SecCertificate] = [:]
        for email in emails {
            let exactTarget = normalizePreservingLocalPart(email)
            guard !exactTarget.isEmpty,
                  let record = resolveRecord(in: records, capability: .encryption, email: email),
                  let material = try? await materialStore.material(for: record.id)
            else {
                continue
            }
            let passphrase = await resolvedPassphrase(for: record.id)
            if let cert = Self.certificate(fromMaterial: material, passphrase: passphrase) {
                result[exactTarget] = cert
            }
        }
        return result
    }

    private func resolvedPassphrase(for recordID: String) async -> String {
        if let stored = try? await materialStore.passphrase(for: recordID), !stored.isEmpty {
            return stored
        }
        return pkcs12Passphrase()
    }

    private enum Capability { case signing, encryption }

    /// Resolves an eligible trusted S/MIME record for `email`: prefers an exact
    /// local-part-case-preserving match (`normalizedSMTPRecipientKey`), and falls
    /// back to case-insensitive local-part matching ONLY when all matching
    /// records belong to a single unambiguous address variant (rejecting
    /// ambiguous case-variant collisions rather than encrypting for the wrong key).
    private func resolveRecord(
        in records: [SecurityKeyMaterialSettings.Record],
        capability: Capability,
        email: String
    ) -> SecurityKeyMaterialSettings.Record? {
        let exactTarget = normalizePreservingLocalPart(email)
        guard !exactTarget.isEmpty else { return nil }
        let eligible = records.filter { hasEligibility($0, capability: capability) }
        if let exactMatch = eligible.first(where: {
            normalizePreservingLocalPart($0.emailAddress ?? "") == exactTarget
        }) {
            return exactMatch
        }
        let foldedTarget = exactTarget.lowercased()
        let foldedMatches = eligible.filter {
            normalizePreservingLocalPart($0.emailAddress ?? "").lowercased() == foldedTarget
        }
        let distinctVariants = Set(foldedMatches.map { normalizePreservingLocalPart($0.emailAddress ?? "") })
        guard distinctVariants.count == 1 else {
            return nil
        }
        return foldedMatches.first
    }

    private func hasEligibility(
        _ record: SecurityKeyMaterialSettings.Record,
        capability: Capability
    ) -> Bool {
        guard record.family == .smime, record.trust == .trusted else { return false }
        switch capability {
        case .signing:
            return record.canSign && record.hasPrivateMaterial
        case .encryption:
            return record.canEncrypt
        }
    }

    private func normalizePreservingLocalPart(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let address: String
        if let start = trimmed.lastIndex(of: "<"),
           let end = trimmed[start...].firstIndex(of: ">") {
            address = String(trimmed[trimmed.index(after: start) ..< end])
        } else {
            address = trimmed
        }
        return SentMessageLedger.normalizedSMTPRecipientKey(address)
    }

    /// Imports a PKCS#12 blob in isolation (via an ephemeral macOS keychain so
    /// the user's default login Keychain is never polluted) and returns its
    /// first identity alongside any intermediate CA certificates from
    /// `kSecImportItemCertChain`, or nil if the blob can't be decoded (e.g.
    /// wrong passphrase) — never throwing, so the caller fails closed.
    private static func signingMaterial(
        fromPKCS12 data: Data,
        passphrase: String
    ) -> SMIMESigningMaterial? {
        guard let imported = SecurityKeyMaterialPayloadDecoder.importPKCS12(data, passphrase: passphrase) else {
            return nil
        }
        return SMIMESigningMaterial(
            identity: imported.identity,
            intermediateCertificates: imported.intermediateCertificates,
            lifetimeToken: imported.lifetimeToken
        )
    }

    /// Builds a pure in-memory recipient certificate from stored material: a
    /// DER certificate if possible, otherwise the leaf certificate of a PKCS#12
    /// identity imported in isolation (never writing to the default Keychain).
    private static func certificate(fromMaterial data: Data, passphrase: String) -> SecCertificate? {
        if let cert = SecCertificateCreateWithData(nil, data as CFData) {
            return cert
        }
        guard let imported = SecurityKeyMaterialPayloadDecoder.importPKCS12(data, passphrase: passphrase) else {
            return nil
        }
        var certOpt: SecCertificate?
        guard SecIdentityCopyCertificate(imported.identity, &certOpt) == errSecSuccess,
              let cert = certOpt
        else { return nil }
        let der = SecCertificateCopyData(cert) as Data
        return SecCertificateCreateWithData(nil, der as CFData)
    }
}
