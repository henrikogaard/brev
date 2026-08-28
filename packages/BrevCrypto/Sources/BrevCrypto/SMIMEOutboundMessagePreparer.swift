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

// S/MIME outbound preparation uses the macOS-only CMSEncoder. iOS has no public
// CMS encoder, so S/MIME *send* is a macOS capability. iOS fails closed through
// the shared preparer seam if stale state requests message security.
#if os(macOS)
import BrevBackend
import Foundation
import Security

// MARK: - Identity resolution

/// Supplies the S/MIME signing identity and recipient certificates from the
/// local Keychain key store (ADR-0021). Local-only — no directory lookups.
public protocol SMIMEIdentityResolving: Sendable {
    /// The sender's signing identity (certificate + private key), or nil.
    func signingIdentity(forSenderEmail email: String) async -> SecIdentity?
    /// Recipient encryption certificates, keyed by normalized email; recipients
    /// without a certificate are absent.
    func encryptionCertificates(forRecipients emails: [String]) async -> [String: SecCertificate]
}

// MARK: - Engine

/// `OutboundMessagePreparing` backed by Apple's CMS (S/MIME) APIs, producing
/// RFC 5751 `multipart/signed` (detached `application/pkcs7-signature`) and
/// `application/pkcs7-mime` enveloped-data. Fails closed via the shared
/// `OutboundMessageSecurityPolicy` before any crypto runs (ADR-0021 #4).
public struct SMIMEOutboundMessagePreparer: OutboundMessagePreparing {
    private let resolver: any SMIMEIdentityResolving
    private let micalg: String
    private let boundaryProvider: @Sendable () -> String

    public init(
        resolver: any SMIMEIdentityResolving,
        micalg: String = "sha-256",
        boundaryProvider: @escaping @Sendable () -> String = { "brev-smime-\(UUID().uuidString)" }
    ) {
        self.resolver = resolver
        self.micalg = micalg
        self.boundaryProvider = boundaryProvider
    }

    public func prepare(
        mimeData: Data,
        request: OutboundMessageSecurityRequest
    ) async throws -> Data {
        guard request.mode != .none else { return mimeData }

        let signingIdentity = request.mode.requiresSigning
            ? await resolver.signingIdentity(forSenderEmail: request.senderEmail)
            : nil
        let recipients = orderedRecipients(for: request)
        let recipientCerts = request.mode.requiresEncryption
            ? await resolver.encryptionCertificates(forRecipients: recipients)
            : [:]

        let availability = OutboundSecurityAvailability(
            hasTrustedSigningIdentity: signingIdentity != nil,
            trustedEncryptionRecipients: Set(recipientCerts.keys)
        )
        let plan = try OutboundMessageSecurityPolicy.prepare(request: request, availability: availability)

        let split = MIMEEntitySplit.make(from: mimeData)
        var entity = split.contentEntity
        var transformed = false

        if plan.requiresSigning {
            guard let signingIdentity else {
                throw OutboundMessageSecurityError.missingSigningIdentity(senderEmail: request.senderEmail)
            }
            entity = try signedEntity(contentEntity: split.contentEntity, identity: signingIdentity)
            transformed = true
        }
        if plan.requiresEncryption {
            let certs = try plan.encryptionRecipients.map { recipient -> SecCertificate in
                guard let cert = recipientCerts[recipient] else {
                    throw OutboundMessageSecurityError.missingEncryptionRecipients([recipient])
                }
                return cert
            }
            entity = try encryptedEntity(plaintext: entity, certificates: certs)
            transformed = true
        }

        guard transformed else { return mimeData }
        return MIMESecurityAssembler.message(topHeaderLines: split.topHeaderLines, entity: entity)
    }

    // MARK: Crypto + MIME

    private func signedEntity(contentEntity: Data, identity: SecIdentity) throws -> Data {
        let signature = try CMS.detachedSignature(of: contentEntity, identity: identity)
        let boundary = boundaryProvider()
        let signaturePart =
            "Content-Type: application/pkcs7-signature; name=\"smime.p7s\"\r\n"
                + "Content-Transfer-Encoding: base64\r\n"
                + "Content-Disposition: attachment; filename=\"smime.p7s\"\r\n\r\n"
                + base64Wrapped(signature)

        var out = "Content-Type: multipart/signed; protocol=\"application/pkcs7-signature\"; "
            + "micalg=\"\(micalg)\"; boundary=\"\(boundary)\"\r\n\r\n"
        out += "--\(boundary)\r\n"
        out += String(decoding: contentEntity, as: UTF8.self)
        out += "\r\n--\(boundary)\r\n"
        out += signaturePart
        out += "\r\n--\(boundary)--\r\n"
        return Data(out.utf8)
    }

    private func encryptedEntity(plaintext: Data, certificates: [SecCertificate]) throws -> Data {
        let enveloped = try CMS.envelopedData(of: plaintext, certificates: certificates)
        let out = "Content-Type: application/pkcs7-mime; smime-type=enveloped-data; name=\"smime.p7m\"\r\n"
            + "Content-Transfer-Encoding: base64\r\n"
            + "Content-Disposition: attachment; filename=\"smime.p7m\"\r\n\r\n"
            + base64Wrapped(enveloped)
        return Data(out.utf8)
    }

    private func base64Wrapped(_ data: Data) -> String {
        data.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
    }

    private func orderedRecipients(for request: OutboundMessageSecurityRequest) -> [String] {
        var seen = Set<String>()
        return ([request.senderEmail] + request.to + request.cc + request.bcc)
            .map(OutboundAddressNormalizer.normalize)
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}

// MARK: - CMS wrapper

/// Thin wrappers over CMSEncoder for detached signing and enveloped encryption.
enum CMS {
    enum CMSError: Error { case encoderUnavailable, operationFailed(OSStatus) }

    static func detachedSignature(of content: Data, identity: SecIdentity) throws -> Data {
        var encoderOpt: CMSEncoder?
        try check(CMSEncoderCreate(&encoderOpt))
        guard let encoder = encoderOpt else { throw CMSError.encoderUnavailable }
        try check(CMSEncoderAddSigners(encoder, identity))
        try check(CMSEncoderSetHasDetachedContent(encoder, true))
        try content.withUnsafeBytes { buffer in
            try check(CMSEncoderUpdateContent(encoder, buffer.baseAddress!, content.count))
        }
        var signedOpt: CFData?
        try check(CMSEncoderCopyEncodedContent(encoder, &signedOpt))
        guard let signed = signedOpt as Data? else { throw CMSError.operationFailed(errSecParam) }
        return signed
    }

    static func envelopedData(of content: Data, certificates: [SecCertificate]) throws -> Data {
        var encoderOpt: CMSEncoder?
        try check(CMSEncoderCreate(&encoderOpt))
        guard let encoder = encoderOpt else { throw CMSError.encoderUnavailable }
        try check(CMSEncoderAddRecipients(encoder, certificates as CFArray))
        try content.withUnsafeBytes { buffer in
            try check(CMSEncoderUpdateContent(encoder, buffer.baseAddress!, content.count))
        }
        var envelopedOpt: CFData?
        try check(CMSEncoderCopyEncodedContent(encoder, &envelopedOpt))
        guard let enveloped = envelopedOpt as Data? else { throw CMSError.operationFailed(errSecParam) }
        return enveloped
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw CMSError.operationFailed(status) }
    }
}
#endif
