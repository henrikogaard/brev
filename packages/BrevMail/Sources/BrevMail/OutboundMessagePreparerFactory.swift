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
#if os(macOS)
import Security
#endif

/// Builds the production S/MIME engine, backed by the local Keychain key store.
/// Returns the `BrevBackend` protocol type so the app targets can inject it into
/// `IMAPAccountConnector.standard(outboundMessagePreparer:)` without importing
/// `BrevCrypto`.
///
/// macOS uses Apple's CMS encoder. iOS has no public CMS encoder, so its empty
/// composite fails closed if stale state ever requests message security.
public enum OutboundMessagePreparerFactory {
    public static func makeStandard(
        settingsProvider: @escaping @Sendable () -> SecurityKeyMaterialSettings = {
            SecurityKeyMaterialSettings.load()
        },
        materialStore: any SecurityKeyMaterialStore = SecurityKeychainMaterialStore()
    ) -> any OutboundMessagePreparing {
        #if os(macOS)
        return SMIMEOutboundMessagePreparer(
            resolver: KeychainSMIMEResolver(
                settingsProvider: settingsProvider,
                materialStore: materialStore
            )
        )
        #else
        return CompositeOutboundMessagePreparer([])
        #endif
    }
}

#if os(macOS)
/// Resolves S/MIME (CMS) key material from the local Keychain key store for the
/// outbound engine. Local-only — no directory lookups (ADR-0021 #1). Only
/// `.trusted` `.smime` records with the required capability are eligible
/// (fail-closed before use).
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
        let target = normalize(email)
        let record = settingsProvider().records.first { record in
            isEligible(record, capability: .signing, target: target)
        }
        guard let record, let material = try? await materialStore.material(for: record.id) else {
            return nil
        }
        return Self.identity(fromPKCS12: material, passphrase: pkcs12Passphrase())
    }

    func encryptionCertificates(forRecipients emails: [String]) async -> [String: SecCertificate] {
        let records = settingsProvider().records
        var result: [String: SecCertificate] = [:]
        for email in emails {
            let target = normalize(email)
            let record = records.first { record in
                isEligible(record, capability: .encryption, target: target)
            }
            guard let record, let material = try? await materialStore.material(for: record.id) else {
                continue
            }
            if let cert = Self.certificate(fromMaterial: material, passphrase: pkcs12Passphrase()) {
                result[target] = cert
            }
        }
        return result
    }

    private enum Capability { case signing, encryption }

    /// Broken out of the `first(where:)` predicates because the combined boolean
    /// expression exceeded the Swift type-checker's time budget inline.
    private func isEligible(
        _ record: SecurityKeyMaterialSettings.Record,
        capability: Capability,
        target: String
    ) -> Bool {
        guard record.family == .smime, record.trust == .trusted else { return false }
        switch capability {
        case .signing where !(record.canSign && record.hasPrivateMaterial): return false
        case .encryption where !record.canEncrypt: return false
        default: break
        }
        return normalize(record.emailAddress ?? "") == target
    }

    private func normalize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let address: String
        if let start = trimmed.lastIndex(of: "<"),
           let end = trimmed[start...].firstIndex(of: ">") {
            address = String(trimmed[trimmed.index(after: start) ..< end])
        } else {
            address = trimmed
        }
        return address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Imports a PKCS#12 blob and returns its first identity, or nil if the blob
    /// can't be decoded (e.g. wrong passphrase) — never throwing, so the caller
    /// fails closed rather than crashing.
    private static func identity(fromPKCS12 data: Data, passphrase: String) -> SecIdentity? {
        let options = [kSecImportExportPassphrase as String: passphrase] as CFDictionary
        var itemsOpt: CFArray?
        let status = SecPKCS12Import(data as CFData, options, &itemsOpt)
        guard status == errSecSuccess, let items = itemsOpt as? [[String: Any]] else { return nil }
        for item in items {
            guard let value = item[kSecImportItemIdentity as String] else { continue }
            return (value as! SecIdentity) // key presence guarantees the type
        }
        return nil
    }

    /// Builds a recipient certificate from stored material: a DER certificate if
    /// possible, otherwise the leaf certificate of a PKCS#12 identity.
    private static func certificate(fromMaterial data: Data, passphrase: String) -> SecCertificate? {
        if let cert = SecCertificateCreateWithData(nil, data as CFData) {
            return cert
        }
        guard let identity = identity(fromPKCS12: data, passphrase: passphrase) else { return nil }
        var certOpt: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certOpt) == errSecSuccess else { return nil }
        return certOpt
    }
}
#endif
