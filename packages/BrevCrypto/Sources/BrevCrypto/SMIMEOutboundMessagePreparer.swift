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
import Foundation
import Security

// MARK: - Identity resolution

/// A local signing identity together with any supporting intermediate CA
/// certificates extracted from its PKCS#12 chain.
public struct SMIMESigningMaterial: @unchecked Sendable {
    /// The signer's leaf identity (certificate + private key).
    public let identity: SecIdentity
    /// Supporting intermediate CA certificates to embed in CMS `SignedData.certificates`.
    public let intermediateCertificates: [SecCertificate]

    /// Creates signing material with optional supporting intermediate certificates.
    public init(identity: SecIdentity, intermediateCertificates: [SecCertificate] = []) {
        self.identity = identity
        self.intermediateCertificates = intermediateCertificates
    }
}

/// Supplies the S/MIME signing identity and recipient certificates from the
/// local Keychain key store (`docs/design/privacy-and-security.md`).
/// Local-only — no directory or network lookups.
public protocol SMIMEIdentityResolving: Sendable {
    /// The sender's signing identity (certificate + private key), or nil.
    func signingIdentity(forSenderEmail email: String) async -> SecIdentity?
    /// The sender's signing identity and any supporting intermediate CA certificates, or nil.
    func signingMaterial(forSenderEmail email: String) async -> SMIMESigningMaterial?
    /// Recipient encryption certificates, keyed by normalized email; recipients
    /// without a certificate are absent.
    func encryptionCertificates(forRecipients emails: [String]) async -> [String: SecCertificate]
}

public extension SMIMEIdentityResolving {
    func signingMaterial(forSenderEmail email: String) async -> SMIMESigningMaterial? {
        guard let identity = await signingIdentity(forSenderEmail: email) else { return nil }
        return SMIMESigningMaterial(identity: identity)
    }
}

// MARK: - CMS encoding backend

/// Selects the CMS encoding implementation backing `SMIMEOutboundMessagePreparer`.
public enum SMIMECMSEncodingBackend: Sendable {
    /// Uses Apple's `CMSEncoder` on macOS and `PureSwiftCMSEncoder` on iOS.
    case platformDefault
    /// Always uses the cross-platform pure-Swift RFC 8551 / RFC 5652 CMS encoder.
    case pureSwift
}

// MARK: - Engine

/// Cross-platform `OutboundMessagePreparing` producing RFC 8551 / RFC 5751
/// `multipart/signed` (detached `application/pkcs7-signature`) and
/// `application/pkcs7-mime` enveloped-data on both macOS and iOS.
///
/// Fails closed via the shared `OutboundMessageSecurityPolicy` before any
/// crypto runs, and never downgrades a protected send to plaintext.
public struct SMIMEOutboundMessagePreparer: OutboundMessagePreparing {
    private let resolver: any SMIMEIdentityResolving
    private let micalg: String
    private let encodingBackend: SMIMECMSEncodingBackend
    private let boundaryProvider: @Sendable () -> String

    /// Creates an outbound S/MIME preparer backed by a local identity resolver.
    ///
    /// - Parameters:
    ///   - resolver: Local Keychain identity/certificate resolver.
    ///   - micalg: `multipart/signed` hash algorithm token (defaults to `"sha-256"`).
    ///   - encodingBackend: CMS encoder backend (`.platformDefault` uses `CMSEncoder` on macOS and `PureSwiftCMSEncoder` on iOS).
    ///   - boundaryProvider: MIME multipart boundary generator.
    public init(
        resolver: any SMIMEIdentityResolving,
        micalg: String = "sha-256",
        encodingBackend: SMIMECMSEncodingBackend = .platformDefault,
        boundaryProvider: @escaping @Sendable () -> String = { "brev-smime-\(UUID().uuidString)" }
    ) {
        self.resolver = resolver
        self.micalg = micalg
        self.encodingBackend = encodingBackend
        self.boundaryProvider = boundaryProvider
    }

    public func prepare(
        mimeData: Data,
        request: OutboundMessageSecurityRequest
    ) async throws -> Data {
        guard request.mode != .none else { return mimeData }

        let signingMaterial = request.mode.requiresSigning
            ? await resolver.signingMaterial(forSenderEmail: request.senderEmail)
            : nil
        let recipients = orderedRecipients(for: request)
        let recipientCerts = request.mode.requiresEncryption
            ? await resolver.encryptionCertificates(forRecipients: recipients)
            : [:]

        let availability = OutboundSecurityAvailability(
            hasTrustedSigningIdentity: signingMaterial != nil,
            trustedEncryptionRecipients: Set(recipientCerts.keys)
        )
        let plan = try OutboundMessageSecurityPolicy.prepare(request: request, availability: availability)

        let split = MIMEEntitySplit.make(from: mimeData)
        var entity = split.contentEntity
        var transformed = false

        if plan.requiresSigning {
            guard let signingMaterial else {
                throw OutboundMessageSecurityError.missingSigningIdentity(senderEmail: request.senderEmail)
            }
            entity = try signedEntity(contentEntity: split.contentEntity, material: signingMaterial)
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

    private func signedEntity(contentEntity: Data, material: SMIMESigningMaterial) throws -> Data {
        let signature = try encodeDetachedSignature(
            of: contentEntity,
            identity: material.identity,
            intermediateCertificates: material.intermediateCertificates
        )
        let boundary = boundaryProvider()
        let signaturePart =
            "Content-Type: application/pkcs7-signature; name=\"smime.p7s\"\r\n"
                + "Content-Transfer-Encoding: base64\r\n"
                + "Content-Disposition: attachment; filename=\"smime.p7s\"\r\n\r\n"
                + base64Wrapped(signature)

        var out = Data()
        let header = "Content-Type: multipart/signed; protocol=\"application/pkcs7-signature\"; "
            + "micalg=\"\(micalg)\"; boundary=\"\(boundary)\"\r\n\r\n"
            + "--\(boundary)\r\n"
        out.append(Data(header.utf8))
        out.append(contentEntity)
        out.append(Data("\r\n--\(boundary)\r\n".utf8))
        out.append(Data(signaturePart.utf8))
        out.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return out
    }

    private func encryptedEntity(plaintext: Data, certificates: [SecCertificate]) throws -> Data {
        let enveloped = try encodeEnvelopedData(of: plaintext, certificates: certificates)
        let out = "Content-Type: application/pkcs7-mime; smime-type=enveloped-data; name=\"smime.p7m\"\r\n"
            + "Content-Transfer-Encoding: base64\r\n"
            + "Content-Disposition: attachment; filename=\"smime.p7m\"\r\n\r\n"
            + base64Wrapped(enveloped)
        return Data(out.utf8)
    }

    private func encodeDetachedSignature(
        of content: Data,
        identity: SecIdentity,
        intermediateCertificates: [SecCertificate]
    ) throws -> Data {
        switch encodingBackend {
        case .pureSwift:
            return try PureSwiftCMSEncoder.detachedSignature(
                of: content,
                identity: identity,
                intermediateCertificates: intermediateCertificates
            )
        case .platformDefault:
            #if os(macOS)
            return try CMS.detachedSignature(
                of: content,
                identity: identity,
                intermediateCertificates: intermediateCertificates
            )
            #else
            return try PureSwiftCMSEncoder.detachedSignature(
                of: content,
                identity: identity,
                intermediateCertificates: intermediateCertificates
            )
            #endif
        }
    }

    private func encodeEnvelopedData(of content: Data, certificates: [SecCertificate]) throws -> Data {
        switch encodingBackend {
        case .pureSwift:
            return try PureSwiftCMSEncoder.envelopedData(of: content, certificates: certificates)
        case .platformDefault:
            #if os(macOS)
            return try CMS.envelopedData(of: content, certificates: certificates)
            #else
            return try PureSwiftCMSEncoder.envelopedData(of: content, certificates: certificates)
            #endif
        }
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

#if os(macOS)

// MARK: - macOS CMSEncoder wrapper

/// Thin wrappers over macOS's `CMSEncoder` for detached signing and enveloped encryption.
enum CMS {
    enum CMSError: Error { case encoderUnavailable, operationFailed(OSStatus) }

    static func detachedSignature(
        of content: Data,
        identity: SecIdentity,
        intermediateCertificates: [SecCertificate] = []
    ) throws -> Data {
        var encoderOpt: CMSEncoder?
        try check(CMSEncoderCreate(&encoderOpt))
        guard let encoder = encoderOpt else { throw CMSError.encoderUnavailable }
        try check(CMSEncoderAddSigners(encoder, identity))
        if !intermediateCertificates.isEmpty {
            try check(CMSEncoderAddSupportingCerts(encoder, intermediateCertificates as CFArray))
        }
        try check(CMSEncoderSetHasDetachedContent(encoder, true))
        try content.withUnsafeBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                try check(CMSEncoderUpdateContent(encoder, baseAddress, content.count))
            }
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
            if let baseAddress = buffer.baseAddress {
                try check(CMSEncoderUpdateContent(encoder, baseAddress, content.count))
            }
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
