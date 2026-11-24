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

import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Typed errors thrown by `PureSwiftCMSEncoder` so outbound S/MIME always fails
/// closed without downgrading to plaintext.
public enum PureSwiftCMSError: Error, Sendable, Equatable, LocalizedError {
    /// Failed to extract the signing certificate from `SecIdentity`.
    case missingSigningCertificate(OSStatus)
    /// Failed to extract the private key from `SecIdentity`.
    case missingSigningPrivateKey(OSStatus)
    /// Signing private key is neither RSA nor ECDSA P-256/P-384/P-521 with SHA-256.
    case unsupportedSigningKeyAlgorithm
    /// `SecKeyCreateSignature` returned an error.
    case signingFailed(String)
    /// EnvelopedData requires at least one recipient certificate.
    case emptyRecipients
    /// Could not extract a public key from a recipient `SecCertificate`.
    case missingRecipientPublicKey
    /// Recipient certificate does not have a supported RSA encryption public key.
    case unsupportedEncryptionKeyAlgorithm
    /// `SecKeyCreateEncryptedData` failed while encrypting the content encryption key.
    case keyEncryptionFailed(String)
    /// `SecRandomCopyBytes` failed while generating the content encryption key or IV.
    case randomGenerationFailed(OSStatus)
    /// `CCCrypt` failed during AES-256-CBC encryption.
    case symmetricEncryptionFailed(Int32)
    /// Certificate DER could not be parsed for `IssuerAndSerialNumber`.
    case malformedCertificate

    public var errorDescription: String? {
        switch self {
        case .missingSigningCertificate, .missingSigningPrivateKey:
            String(
                localized: "The selected S/MIME signing identity is incomplete, so the message was not sent.",
                bundle: .module
            )
        case .unsupportedSigningKeyAlgorithm:
            String(
                localized: "The S/MIME signing key uses an unsupported algorithm, so the message was not sent.",
                bundle: .module
            )
        case .signingFailed:
            String(
                localized: "Signing the message failed, so it was not sent.",
                bundle: .module
            )
        case .emptyRecipients, .missingRecipientPublicKey:
            String(
                localized: "A recipient encryption certificate is missing a usable public key, so the message was not sent.",
                bundle: .module
            )
        case .unsupportedEncryptionKeyAlgorithm:
            String(
                localized: "A recipient certificate does not support RSA S/MIME encryption, so the message was not sent.",
                bundle: .module
            )
        case .keyEncryptionFailed, .randomGenerationFailed, .symmetricEncryptionFailed:
            String(
                localized: "Encrypting the message failed, so it was not sent.",
                bundle: .module
            )
        case .malformedCertificate:
            String(
                localized: "An S/MIME certificate could not be parsed, so the message was not sent.",
                bundle: .module
            )
        }
    }
}

/// Cross-platform pure-Swift RFC 5652 / RFC 8551 CMS DER encoder built solely
/// on Apple's `Security`, `CryptoKit`, and `CommonCrypto` frameworks.
///
/// Compiles on both macOS and iOS so iOS gains full outbound S/MIME signing and
/// encryption parity while macOS test suites verify interoperability directly
/// against `CMSDecoder` and OpenSSL.
public enum PureSwiftCMSEncoder: Sendable {
    private static let aes256KeyLength = kCCKeySizeAES256 // 32 bytes
    private static let aesBlockSize = kCCBlockSizeAES128 // 16 bytes

    /// Produces a DER-encoded CMS `ContentInfo(id-signedData, SignedData)`
    /// containing a detached SHA-256 signature, the signer's certificate, and
    /// any supporting intermediate CA certificates.
    ///
    /// - Parameters:
    ///   - content: Canonical MIME entity bytes to sign (detached; not embedded in `encapContentInfo`).
    ///   - identity: Local Keychain `SecIdentity` providing the signer's certificate and private key.
    ///   - intermediateCertificates: Optional intermediate CA certificates from the signer's chain.
    ///   - signingTime: UTC timestamp recorded in the `signingTime` signed attribute.
    public static func detachedSignature(
        of content: Data,
        identity: SecIdentity,
        intermediateCertificates: [SecCertificate] = [],
        signingTime: Date = Date()
    ) throws -> Data {
        var certOpt: SecCertificate?
        let certStatus = SecIdentityCopyCertificate(identity, &certOpt)
        guard certStatus == errSecSuccess, let certificate = certOpt else {
            throw PureSwiftCMSError.missingSigningCertificate(certStatus)
        }

        var keyOpt: SecKey?
        let keyStatus = SecIdentityCopyPrivateKey(identity, &keyOpt)
        guard keyStatus == errSecSuccess, let privateKey = keyOpt else {
            throw PureSwiftCMSError.missingSigningPrivateKey(keyStatus)
        }

        let signingSpec = try resolveSigningSpec(for: privateKey)
        let certDER = SecCertificateCopyData(certificate) as Data
        let issuerAndSerial = try X509CertificateParser.extractIssuerAndSerialNumber(from: certDER)

        let digest = Data(SHA256.hash(data: content))

        // Build RFC 5652 signed attributes: contentType, signingTime, messageDigest.
        let contentTypeAttr = ASN1DER.sequence([
            ASN1DER.objectIdentifier(CMSObjectIdentifier.contentType),
            ASN1DER.set([ASN1DER.objectIdentifier(CMSObjectIdentifier.data)])
        ])
        let signingTimeAttr = ASN1DER.sequence([
            ASN1DER.objectIdentifier(CMSObjectIdentifier.signingTime),
            ASN1DER.set([ASN1DER.cmsTime(signingTime)])
        ])
        let messageDigestAttr = ASN1DER.sequence([
            ASN1DER.objectIdentifier(CMSObjectIdentifier.messageDigest),
            ASN1DER.set([ASN1DER.octetString(digest)])
        ])

        // RFC 5652 §5.4: SignedAttributes MUST be DER-encoded with EXPLICIT SET OF tag (0x31)
        // when computing the signature, then encoded as [0] IMPLICIT (0xA0) inside SignerInfo.
        let sortedAttrs = ASN1DER.sortedSetElements([contentTypeAttr, signingTimeAttr, messageDigestAttr])
        let sortedAttrsBody = ASN1DER.concat(sortedAttrs)
        let signedAttrsForDigest = ASN1DER.tlv(tag: ASN1DER.setTag, content: sortedAttrsBody)

        var signError: Unmanaged<CFError>?
        guard let signatureCF = SecKeyCreateSignature(
            privateKey,
            signingSpec.secAlgorithm,
            signedAttrsForDigest as CFData,
            &signError
        ) else {
            let description = signError?.takeRetainedValue().localizedDescription ?? "Unknown SecKey signature error"
            throw PureSwiftCMSError.signingFailed(description)
        }
        let signatureBytes = signatureCF as Data

        // RFC 5754 §2: SHA-256 AlgorithmIdentifier parameters SHOULD be omitted.
        let sha256AlgID = ASN1DER.algorithmIdentifier(oid: CMSObjectIdentifier.sha256)
        let signedAttrsImplicit = ASN1DER.contextSpecific(
            tagNumber: 0,
            constructed: true,
            content: sortedAttrsBody
        )
        let signerInfo = ASN1DER.sequence([
            ASN1DER.integer(1),
            issuerAndSerial.derEncoded,
            sha256AlgID,
            signedAttrsImplicit,
            signingSpec.algorithmIdentifierDER,
            ASN1DER.octetString(signatureBytes)
        ])

        // Detached SignedData omits eContent inside EncapsulatedContentInfo.
        let encapContentInfo = ASN1DER.sequence([
            ASN1DER.objectIdentifier(CMSObjectIdentifier.data)
        ])
        // Deduplicate leaf + intermediate CA certificates and DER-sort the
        // [0] IMPLICIT CertificateSet per RFC 5652 §5.1.
        var seenCertificates: Set<Data> = [certDER]
        var certificateSetDERs: [Data] = [certDER]
        for supportingCert in intermediateCertificates {
            let supportingDER = SecCertificateCopyData(supportingCert) as Data
            if seenCertificates.insert(supportingDER).inserted {
                certificateSetDERs.append(supportingDER)
            }
        }
        let sortedCertificatesBody = ASN1DER.concat(ASN1DER.sortedSetElements(certificateSetDERs))
        let certificatesImplicit = ASN1DER.contextSpecific(
            tagNumber: 0,
            constructed: true,
            content: sortedCertificatesBody
        )
        let signedData = ASN1DER.sequence([
            ASN1DER.integer(1),
            ASN1DER.set([sha256AlgID]),
            encapContentInfo,
            certificatesImplicit,
            ASN1DER.set([signerInfo])
        ])

        return ASN1DER.sequence([
            ASN1DER.objectIdentifier(CMSObjectIdentifier.signedData),
            ASN1DER.contextSpecific(tagNumber: 0, constructed: true, content: signedData)
        ])
    }

    /// Produces a DER-encoded CMS `ContentInfo(id-envelopedData, EnvelopedData)`
    /// encrypting `content` with AES-256-CBC and wrapping the random content
    /// encryption key for each recipient certificate via RSA PKCS#1 v1.5.
    ///
    /// - Parameters:
    ///   - content: Plaintext MIME entity bytes (or signed `multipart/signed` entity).
    ///   - certificates: Recipient X.509 certificates (must be non-empty; every certificate must have an RSA public key).
    public static func envelopedData(
        of content: Data,
        certificates: [SecCertificate]
    ) throws -> Data {
        guard !certificates.isEmpty else {
            throw PureSwiftCMSError.emptyRecipients
        }

        var cek = try randomBytes(count: aes256KeyLength)
        defer { cek.resetBytes(in: 0 ..< cek.count) }
        let iv = try randomBytes(count: aesBlockSize)

        let recipientInfos = try certificates.map { certificate -> Data in
            try buildKeyTransRecipientInfo(for: certificate, cek: cek)
        }

        let ciphertext = try encryptAES256CBC(plaintext: content, key: cek, iv: iv)

        let contentEncryptionAlgID = ASN1DER.algorithmIdentifier(
            oid: CMSObjectIdentifier.aes256CBC,
            parameters: ASN1DER.octetString(iv)
        )
        // RFC 5652 §6.1: encryptedContent is [0] IMPLICIT OCTET STRING OPTIONAL (primitive tag 0x80).
        let encryptedContentImplicit = ASN1DER.contextSpecific(
            tagNumber: 0,
            constructed: false,
            content: ciphertext
        )
        let encryptedContentInfo = ASN1DER.sequence([
            ASN1DER.objectIdentifier(CMSObjectIdentifier.data),
            contentEncryptionAlgID,
            encryptedContentImplicit
        ])

        let envelopedData = ASN1DER.sequence([
            ASN1DER.integer(0),
            ASN1DER.set(recipientInfos),
            encryptedContentInfo
        ])

        return ASN1DER.sequence([
            ASN1DER.objectIdentifier(CMSObjectIdentifier.envelopedData),
            ASN1DER.contextSpecific(tagNumber: 0, constructed: true, content: envelopedData)
        ])
    }

    // MARK: - Helpers

    private struct SigningSpec {
        let secAlgorithm: SecKeyAlgorithm
        let algorithmIdentifierDER: Data
    }

    private static func resolveSigningSpec(for privateKey: SecKey) throws -> SigningSpec {
        let attributes = SecKeyCopyAttributes(privateKey) as? [String: Any]
        let keyType = attributes?[kSecAttrKeyType as String] as? String

        if keyType == (kSecAttrKeyTypeRSA as String) {
            let algorithm = SecKeyAlgorithm.rsaSignatureMessagePKCS1v15SHA256
            guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
                throw PureSwiftCMSError.unsupportedSigningKeyAlgorithm
            }
            return SigningSpec(
                secAlgorithm: algorithm,
                algorithmIdentifierDER: ASN1DER.algorithmIdentifier(
                    oid: CMSObjectIdentifier.sha256WithRSAEncryption,
                    parameters: ASN1DER.null()
                )
            )
        }

        if keyType == (kSecAttrKeyTypeECSECPrimeRandom as String) {
            let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
            guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
                throw PureSwiftCMSError.unsupportedSigningKeyAlgorithm
            }
            // RFC 5754 §3.3: ecdsa-with-SHA256 parameters MUST be omitted.
            return SigningSpec(
                secAlgorithm: algorithm,
                algorithmIdentifierDER: ASN1DER.algorithmIdentifier(
                    oid: CMSObjectIdentifier.ecdsaWithSHA256,
                    parameters: nil
                )
            )
        }

        throw PureSwiftCMSError.unsupportedSigningKeyAlgorithm
    }

    private static func buildKeyTransRecipientInfo(
        for certificate: SecCertificate,
        cek: Data
    ) throws -> Data {
        let certDER = SecCertificateCopyData(certificate) as Data
        let issuerAndSerial = try X509CertificateParser.extractIssuerAndSerialNumber(from: certDER)

        guard let publicKey = SecCertificateCopyKey(certificate) else {
            throw PureSwiftCMSError.missingRecipientPublicKey
        }
        let attributes = SecKeyCopyAttributes(publicKey) as? [String: Any]
        let keyType = attributes?[kSecAttrKeyType as String] as? String
        guard keyType == (kSecAttrKeyTypeRSA as String),
              SecKeyIsAlgorithmSupported(publicKey, .encrypt, .rsaEncryptionPKCS1)
        else {
            throw PureSwiftCMSError.unsupportedEncryptionKeyAlgorithm
        }

        var encryptError: Unmanaged<CFError>?
        guard let encryptedKeyCF = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionPKCS1,
            cek as CFData,
            &encryptError
        ) else {
            let description = encryptError?.takeRetainedValue().localizedDescription ?? "Unknown SecKey encryption error"
            throw PureSwiftCMSError.keyEncryptionFailed(description)
        }

        let keyEncryptionAlgID = ASN1DER.algorithmIdentifier(
            oid: CMSObjectIdentifier.rsaEncryption,
            parameters: ASN1DER.null()
        )
        return ASN1DER.sequence([
            ASN1DER.integer(0),
            issuerAndSerial.derEncoded,
            keyEncryptionAlgID,
            ASN1DER.octetString(encryptedKeyCF as Data)
        ])
    }

    private static func randomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }
        guard status == errSecSuccess else {
            throw PureSwiftCMSError.randomGenerationFailed(status)
        }
        return data
    }

    private static func encryptAES256CBC(
        plaintext: Data,
        key: Data,
        iv: Data
    ) throws -> Data {
        let bufferCapacity = plaintext.count + aesBlockSize
        var output = Data(count: bufferCapacity)
        var bytesEncrypted = 0
        var emptyInputByte: UInt8 = 0

        let status: CCCryptorStatus = key.withUnsafeBytes { keyBuffer in
            iv.withUnsafeBytes { ivBuffer in
                plaintext.withUnsafeBytes { inBuffer in
                    withUnsafeBytes(of: &emptyInputByte) { emptyBuffer in
                        output.withUnsafeMutableBytes { outBuffer in
                            let inPtr = inBuffer.baseAddress ?? emptyBuffer.baseAddress
                            return CCCrypt(
                                CCOperation(kCCEncrypt),
                                CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                keyBuffer.baseAddress,
                                key.count,
                                ivBuffer.baseAddress,
                                inPtr,
                                plaintext.count,
                                outBuffer.baseAddress,
                                bufferCapacity,
                                &bytesEncrypted
                            )
                        }
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw PureSwiftCMSError.symmetricEncryptionFailed(status)
        }
        output.count = bytesEncrypted
        return output
    }
}
