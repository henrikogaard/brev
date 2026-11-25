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

@testable import BrevBackend
@testable import BrevCrypto
import Foundation
@preconcurrency import Security
import Testing

@Suite("ASN1DER & X509CertificateParser")
struct ASN1DERTests {
    @Test("encodes short and long definite DER lengths")
    func encodesLengths() {
        #expect(ASN1DER.length(0) == Data([0x00]))
        #expect(ASN1DER.length(127) == Data([0x7F]))
        #expect(ASN1DER.length(128) == Data([0x81, 0x80]))
        #expect(ASN1DER.length(255) == Data([0x81, 0xFF]))
        #expect(ASN1DER.length(256) == Data([0x82, 0x01, 0x00]))
        #expect(ASN1DER.length(65536) == Data([0x83, 0x01, 0x00, 0x00]))
    }

    @Test("encodes non-negative DER integers with minimal signed bytes")
    func encodesIntegers() {
        #expect(ASN1DER.integer(0) == Data([0x02, 0x01, 0x00]))
        #expect(ASN1DER.integer(1) == Data([0x02, 0x01, 0x01]))
        #expect(ASN1DER.integer(127) == Data([0x02, 0x01, 0x7F]))
        #expect(ASN1DER.integer(128) == Data([0x02, 0x02, 0x00, 0x80]))
        #expect(ASN1DER.integer(256) == Data([0x02, 0x02, 0x01, 0x00]))
    }

    @Test("encodes standard CMS and digest OIDs accurately")
    func encodesOIDs() {
        // id-data: 1.2.840.113549.1.7.1
        #expect(
            ASN1DER.objectIdentifier(CMSObjectIdentifier.data)
                == Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x01])
        )
        // id-sha256: 2.16.840.1.101.3.4.2.1
        #expect(
            ASN1DER.objectIdentifier(CMSObjectIdentifier.sha256)
                == Data([0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01])
        )
        // id-aes256-CBC: 2.16.840.1.101.3.4.1.42
        #expect(
            ASN1DER.objectIdentifier(CMSObjectIdentifier.aes256CBC)
                == Data([0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x01, 0x2A])
        )
    }

    @Test("sorts DER SET elements in ascending unsigned byte order")
    func sortsSetElements() {
        let a = ASN1DER.integer(10) // 02 01 0A
        let b = ASN1DER.integer(2) // 02 01 02
        let c = ASN1DER.null() // 05 00
        let encoded = ASN1DER.set([c, a, b])
        #expect(encoded == Data([0x31, 0x08]) + b + a + c)
    }

    @Test("encodes UTCTime through 2049 and GeneralizedTime from 2050")
    func encodesTimePerRFC5652() {
        let utcDate = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z
        let utc = ASN1DER.cmsTime(utcDate)
        #expect(utc.first == 0x17)
        #expect(String(decoding: utc.dropFirst(2), as: UTF8.self) == "231114221320Z")

        let futureDate = Date(timeIntervalSince1970: 2_524_608_000) // 2050-01-01T00:00:00Z
        let gen = ASN1DER.cmsTime(futureDate)
        #expect(gen.first == 0x18)
        #expect(String(decoding: gen.dropFirst(2), as: UTF8.self) == "20500101000000Z")
    }

    @Test("extracts IssuerAndSerialNumber from a v1 certificate without explicit version field")
    func extractsIssuerAndSerialFromV1Certificate() throws {
        let serialDER = ASN1DER.integer(42)
        let sigAlgDER = ASN1DER.algorithmIdentifier(oid: CMSObjectIdentifier.sha256WithRSAEncryption, parameters: ASN1DER.null())
        let issuerDER = ASN1DER.sequence([
            ASN1DER.set([
                ASN1DER.sequence([
                    ASN1DER.objectIdentifier([2, 5, 4, 3]),
                    ASN1DER.tlv(tag: 0x0C, content: Data("Test CA".utf8))
                ])
            ])
        ])
        let tbs = ASN1DER.sequence([serialDER, sigAlgDER, issuerDER])
        let certDER = ASN1DER.sequence([tbs, sigAlgDER, ASN1DER.tlv(tag: 0x03, content: Data([0x00]))])

        let parsed = try X509CertificateParser.extractIssuerAndSerialNumber(from: certDER)
        #expect(parsed.issuerDER == issuerDER)
        #expect(parsed.serialNumberDER == serialDER)
        #expect(parsed.derEncoded == ASN1DER.sequence([issuerDER, serialDER]))
    }

    @Test("rejects malformed or truncated certificate DER")
    func rejectsMalformedCertificate() {
        #expect(throws: PureSwiftCMSError.malformedCertificate) {
            _ = try X509CertificateParser.extractIssuerAndSerialNumber(from: Data([0x30, 0x05, 0x01, 0x02]))
        }
        #expect(throws: PureSwiftCMSError.malformedCertificate) {
            _ = try X509CertificateParser.extractIssuerAndSerialNumber(from: Data())
        }
    }

    @Test("every PureSwiftCMSError provides a localized non-empty description")
    func errorsProvideLocalizedDescriptions() {
        let cases: [PureSwiftCMSError] = [
            .missingSigningCertificate(errSecItemNotFound),
            .missingSigningPrivateKey(errSecItemNotFound),
            .unsupportedSigningKeyAlgorithm,
            .signingFailed("test"),
            .emptyRecipients,
            .missingRecipientPublicKey,
            .unsupportedEncryptionKeyAlgorithm,
            .keyEncryptionFailed("test"),
            .randomGenerationFailed(errSecParam),
            .symmetricEncryptionFailed(-1),
            .malformedCertificate
        ]
        for error in cases {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}

#if os(macOS)
@Suite("PureSwiftCMSEncoder interoperability", .serialized)
struct PureSwiftCMSEncoderTests {
    private struct EphemeralIdentity {
        let identity: SecIdentity
        let certificate: SecCertificate
        let certPEMURL: URL
        let keyPEMURL: URL
        let directoryURL: URL

        func cleanup() {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    private enum KeyKind {
        case rsa
        case ecdsaP256
    }

    private func generateIdentity(email: String, kind: KeyKind) throws -> EphemeralIdentity {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-cms-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let keyURL = dir.appendingPathComponent("key.pem")
        let certURL = dir.appendingPathComponent("cert.pem")
        let p12URL = dir.appendingPathComponent("id.p12")

        switch kind {
        case .rsa:
            try runOpenSSL([
                "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-keyout", keyURL.path,
                "-out", certURL.path,
                "-days", "7",
                "-subj", "/CN=Brev Test/emailAddress=\(email)"
            ])
        case .ecdsaP256:
            let paramURL = dir.appendingPathComponent("ecparam.pem")
            try runOpenSSL(["ecparam", "-name", "prime256v1", "-out", paramURL.path])
            try runOpenSSL([
                "req", "-x509", "-newkey", "ec:\(paramURL.path)", "-nodes",
                "-keyout", keyURL.path,
                "-out", certURL.path,
                "-days", "7",
                "-subj", "/CN=Brev EC Test/emailAddress=\(email)"
            ])
        }

        try runOpenSSL([
            "pkcs12", "-export",
            "-inkey", keyURL.path,
            "-in", certURL.path,
            "-out", p12URL.path,
            "-passout", "pass:brevtest"
        ])

        let p12Data = try Data(contentsOf: p12URL)
        var itemsOpt: CFArray?
        let status = SecPKCS12Import(
            p12Data as CFData,
            [kSecImportExportPassphrase as String: "brevtest"] as CFDictionary,
            &itemsOpt
        )
        try #require(status == errSecSuccess)
        let items = try #require(itemsOpt as? [[String: Any]])
        let first = try #require(items.first)
        let identity = try #require(first[kSecImportItemIdentity as String] as! SecIdentity?)
        var certOpt: SecCertificate?
        try #require(SecIdentityCopyCertificate(identity, &certOpt) == errSecSuccess)
        return try EphemeralIdentity(
            identity: identity,
            certificate: #require(certOpt),
            certPEMURL: certURL,
            keyPEMURL: keyURL,
            directoryURL: dir
        )
    }

    @discardableResult
    private func runOpenSSL(_ arguments: [String], stdin: Data? = nil) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        if let stdin {
            let inPipe = Pipe()
            process.standardInput = inPipe
            try process.run()
            inPipe.fileHandleForWriting.write(stdin)
            inPipe.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }
        let stdout = outPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errText = String(decoding: stderr, as: UTF8.self)
            Issue.record("openssl \(arguments.joined(separator: " ")) failed: \(errText)")
            throw NSError(domain: "OpenSSLTest", code: Int(process.terminationStatus))
        }
        return stdout
    }

    private func verifyWithCMSDecoder(signature: Data, content: Data) throws -> CMSSignerStatus {
        var decoderOpt: CMSDecoder?
        try #require(CMSDecoderCreate(&decoderOpt) == errSecSuccess)
        let decoder = try #require(decoderOpt)
        signature.withUnsafeBytes { buffer in
            if let base = buffer.baseAddress {
                _ = CMSDecoderUpdateMessage(decoder, base, buffer.count)
            }
        }
        CMSDecoderSetDetachedContent(decoder, content as CFData)
        try #require(CMSDecoderFinalizeMessage(decoder) == errSecSuccess)
        var status: CMSSignerStatus = .unsigned
        var certVerify: OSStatus = 0
        var trust: SecTrust?
        CMSDecoderCopySignerStatus(decoder, 0, SecPolicyCreateBasicX509(), false, &status, &trust, &certVerify)
        return status
    }

    private func decryptWithOpenSSL(envelopedDER: Data, recipient: EphemeralIdentity) throws -> Data {
        try runOpenSSL(
            [
                "cms", "-decrypt", "-inform", "DER",
                "-recip", recipient.certPEMURL.path,
                "-inkey", recipient.keyPEMURL.path
            ],
            stdin: envelopedDER
        )
    }

    @Test("RSA detached SignedData verifies in Apple CMSDecoder and OpenSSL")
    func rsaDetachedSignatureVerifies() throws {
        let alice = try generateIdentity(email: "alice@brev.example", kind: .rsa)
        defer { alice.cleanup() }

        let content = Data("Content-Type: text/plain; charset=utf-8\r\n\r\nHello from iOS S/MIME!\r\n".utf8)
        let der = try PureSwiftCMSEncoder.detachedSignature(of: content, identity: alice.identity)

        let status = try verifyWithCMSDecoder(signature: der, content: content)
        #expect(status == .valid)

        // Verify with OpenSSL CMS as independent cross-check.
        let contentFile = alice.directoryURL.appendingPathComponent("content.bin")
        try content.write(to: contentFile)
        _ = try runOpenSSL(
            [
                "cms", "-verify", "-inform", "DER",
                "-content", contentFile.path,
                "-noverify",
                "-out", "/dev/null"
            ],
            stdin: der
        )
    }

    @Test("ECDSA P-256 detached SignedData verifies in Apple CMSDecoder and OpenSSL")
    func ecdsaDetachedSignatureVerifies() throws {
        let bob = try generateIdentity(email: "bob@brev.example", kind: .ecdsaP256)
        defer { bob.cleanup() }

        let content = Data("Content-Type: text/plain; charset=utf-8\r\n\r\nSigned with P-256.\r\n".utf8)
        let der = try PureSwiftCMSEncoder.detachedSignature(of: content, identity: bob.identity)

        let status = try verifyWithCMSDecoder(signature: der, content: content)
        #expect(status == .valid)

        let contentFile = bob.directoryURL.appendingPathComponent("content.bin")
        try content.write(to: contentFile)
        _ = try runOpenSSL(
            [
                "cms", "-verify", "-inform", "DER",
                "-content", contentFile.path,
                "-noverify",
                "-out", "/dev/null"
            ],
            stdin: der
        )
    }

    @Test("tampered content fails CMSDecoder signature verification")
    func tamperedContentFailsVerification() throws {
        let alice = try generateIdentity(email: "alice@brev.example", kind: .rsa)
        defer { alice.cleanup() }

        let content = Data("Original body".utf8)
        let der = try PureSwiftCMSEncoder.detachedSignature(of: content, identity: alice.identity)
        let tampered = Data("Tampered body".utf8)

        let status = try verifyWithCMSDecoder(signature: der, content: tampered)
        #expect(status != .valid)
    }

    @Test("EnvelopedData decrypts for a single RSA recipient via OpenSSL")
    func singleRecipientEnvelopedDataRoundTrips() throws {
        let alice = try generateIdentity(email: "alice@brev.example", kind: .rsa)
        defer { alice.cleanup() }

        let plaintext = Data("Content-Type: text/plain; charset=utf-8\r\n\r\nConfidential message.\r\n".utf8)
        let enveloped = try PureSwiftCMSEncoder.envelopedData(of: plaintext, certificates: [alice.certificate])
        let decrypted = try decryptWithOpenSSL(envelopedDER: enveloped, recipient: alice)
        #expect(decrypted == plaintext)
    }

    @Test("EnvelopedData decrypts for multiple RSA recipients independently")
    func multiRecipientEnvelopedDataRoundTrips() throws {
        let alice = try generateIdentity(email: "alice@brev.example", kind: .rsa)
        let bob = try generateIdentity(email: "bob@brev.example", kind: .rsa)
        defer {
            alice.cleanup()
            bob.cleanup()
        }

        let plaintext = Data(repeating: 0xAB, count: 4096) + Data("Multi-recipient payload".utf8)
        let enveloped = try PureSwiftCMSEncoder.envelopedData(
            of: plaintext,
            certificates: [alice.certificate, bob.certificate]
        )

        #expect(try decryptWithOpenSSL(envelopedDER: enveloped, recipient: alice) == plaintext)
        #expect(try decryptWithOpenSSL(envelopedDER: enveloped, recipient: bob) == plaintext)
    }

    @Test("EnvelopedData handles empty plaintext cleanly")
    func emptyPlaintextEnvelopedDataRoundTrips() throws {
        let alice = try generateIdentity(email: "alice@brev.example", kind: .rsa)
        defer { alice.cleanup() }

        let enveloped = try PureSwiftCMSEncoder.envelopedData(of: Data(), certificates: [alice.certificate])
        let decrypted = try decryptWithOpenSSL(envelopedDER: enveloped, recipient: alice)
        #expect(decrypted == Data())
    }

    @Test("EnvelopedData fails closed for empty recipients and non-RSA encryption keys")
    func envelopedDataFailsClosed() throws {
        let ec = try generateIdentity(email: "ec@brev.example", kind: .ecdsaP256)
        defer { ec.cleanup() }

        #expect(throws: PureSwiftCMSError.emptyRecipients) {
            _ = try PureSwiftCMSEncoder.envelopedData(of: Data("hi".utf8), certificates: [])
        }
        #expect(throws: PureSwiftCMSError.unsupportedEncryptionKeyAlgorithm) {
            _ = try PureSwiftCMSEncoder.envelopedData(of: Data("hi".utf8), certificates: [ec.certificate])
        }
    }

    @Test("SMIMEOutboundMessagePreparer pureSwift signAndEncrypt round-trips end-to-end")
    func preparerPureSwiftSignAndEncryptRoundTrips() async throws {
        let alice = try generateIdentity(email: "alice@brev.example", kind: .rsa)
        let bob = try generateIdentity(email: "bob@brev.example", kind: .rsa)
        defer {
            alice.cleanup()
            bob.cleanup()
        }

        struct MultiResolver: SMIMEIdentityResolving {
            let signing: SecIdentity
            let certs: [String: SecCertificate]
            func signingIdentity(forSenderEmail email: String) async -> SecIdentity? {
                OutboundAddressNormalizer.normalize(email) == "alice@brev.example" ? signing : nil
            }

            func encryptionCertificates(forRecipients emails: [String]) async -> [String: SecCertificate] {
                var out: [String: SecCertificate] = [:]
                for email in emails {
                    let normalized = OutboundAddressNormalizer.normalize(email)
                    if let cert = certs[normalized] {
                        out[normalized] = cert
                    }
                }
                return out
            }
        }

        let resolver = MultiResolver(
            signing: alice.identity,
            certs: [
                "alice@brev.example": alice.certificate,
                "bob@brev.example": bob.certificate
            ]
        )
        let preparer = SMIMEOutboundMessagePreparer(
            resolver: resolver,
            encodingBackend: .pureSwift
        )
        let rawMessage = Data("""
        From: Alice <alice@brev.example>\r
        To: Bob <bob@brev.example>\r
        Subject: Secret Signed\r
        MIME-Version: 1.0\r
        Content-Type: text/plain; charset=utf-8\r
        \r
        Sign then encrypt from pure Swift.\r
        """.utf8)
        let request = OutboundMessageSecurityRequest(
            senderEmail: "alice@brev.example",
            to: ["bob@brev.example"],
            mode: .signAndEncrypt
        )

        let prepared = try await preparer.prepare(mimeData: rawMessage, request: request)
        let text = String(decoding: prepared, as: UTF8.self)
        #expect(text.contains("Subject: Secret Signed"))
        #expect(text.contains("Content-Type: application/pkcs7-mime; smime-type=enveloped-data"))
        #expect(!text.contains("Sign then encrypt from pure Swift."))

        // Extract base64 smime.p7m body and decrypt for Bob.
        let bodyRange = try #require(text.range(of: "\r\n\r\n"))
        let p7mBase64 = String(text[bodyRange.upperBound...])
        let p7mDER = try #require(Data(base64Encoded: p7mBase64, options: .ignoreUnknownCharacters))
        let decryptedSignedMIME = try decryptWithOpenSSL(envelopedDER: p7mDER, recipient: bob)
        let decryptedText = String(decoding: decryptedSignedMIME, as: UTF8.self)
        #expect(decryptedText.contains("multipart/signed"))
        #expect(decryptedText.contains("Sign then encrypt from pure Swift."))

        // Extract BOTH the delivered signed first MIME part AND the detached smime.p7s
        // from the decrypted multipart/signed payload, and verify against the delivered part.
        let boundaryPrefix = "boundary=\""
        let boundaryStart = try #require(decryptedText.range(of: boundaryPrefix))
        let boundaryEnd = try #require(
            decryptedText.range(of: "\"", range: boundaryStart.upperBound ..< decryptedText.endIndex)
        )
        let boundary = String(decryptedText[boundaryStart.upperBound ..< boundaryEnd.lowerBound])
        let firstPartMarker = Data("--\(boundary)\r\n".utf8)
        let nextPartDelimiter = Data("\r\n--\(boundary)\r\n".utf8)
        let firstMarkerRange = try #require(decryptedSignedMIME.range(of: firstPartMarker))
        let nextPartRange = try #require(
            decryptedSignedMIME.range(
                of: nextPartDelimiter,
                in: firstMarkerRange.upperBound ..< decryptedSignedMIME.endIndex
            )
        )
        let deliveredFirstPart = Data(decryptedSignedMIME[firstMarkerRange.upperBound ..< nextPartRange.lowerBound])
        let originalSplit = MIMEEntitySplit.make(from: rawMessage)
        #expect(deliveredFirstPart == originalSplit.contentEntity)

        let markerRange = try #require(decryptedText.range(of: "filename=\"smime.p7s\""))
        let blankRange = try #require(
            decryptedText.range(of: "\r\n\r\n", range: markerRange.upperBound ..< decryptedText.endIndex)
        )
        let rest = decryptedText[blankRange.upperBound...]
        let sigEnd = try #require(rest.range(of: "\r\n--"))
        let p7sDER = try #require(
            Data(base64Encoded: String(rest[..<sigEnd.lowerBound]), options: .ignoreUnknownCharacters)
        )
        let status = try verifyWithCMSDecoder(signature: p7sDER, content: deliveredFirstPart)
        #expect(status == .valid)
    }

    @Test("detached SignedData embeds intermediate CA certificates so OpenSSL verifies against Root CA alone")
    func detachedSignatureEmbedsIntermediateCertificates() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-cms-chain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let rootKey = dir.appendingPathComponent("root.key")
        let rootCert = dir.appendingPathComponent("root.pem")
        let rootExt = dir.appendingPathComponent("root.ext")
        try "basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n"
            .write(to: rootExt, atomically: true, encoding: .utf8)

        try runOpenSSL([
            "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", rootKey.path,
            "-out", rootCert.path,
            "-days", "7",
            "-subj", "/CN=Brev Test Root CA",
            "-extensions", "v3_ca",
            "-config", "/System/Library/OpenSSL/openssl.cnf"
        ])

        let interKey = dir.appendingPathComponent("inter.key")
        let interCSR = dir.appendingPathComponent("inter.csr")
        let interCert = dir.appendingPathComponent("inter.pem")
        let interExt = dir.appendingPathComponent("inter.ext")
        try "basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n"
            .write(to: interExt, atomically: true, encoding: .utf8)

        try runOpenSSL([
            "req", "-new", "-newkey", "rsa:2048", "-nodes",
            "-keyout", interKey.path,
            "-out", interCSR.path,
            "-subj", "/CN=Brev Test Intermediate CA"
        ])
        try runOpenSSL([
            "x509", "-req", "-in", interCSR.path,
            "-CA", rootCert.path, "-CAkey", rootKey.path, "-CAcreateserial",
            "-out", interCert.path, "-days", "7",
            "-extfile", interExt.path
        ])

        let leafKey = dir.appendingPathComponent("leaf.key")
        let leafCSR = dir.appendingPathComponent("leaf.csr")
        let leafCert = dir.appendingPathComponent("leaf.pem")
        let leafExt = dir.appendingPathComponent("leaf.ext")
        try "basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=emailProtection\n"
            .write(to: leafExt, atomically: true, encoding: .utf8)

        try runOpenSSL([
            "req", "-new", "-newkey", "rsa:2048", "-nodes",
            "-keyout", leafKey.path,
            "-out", leafCSR.path,
            "-subj", "/CN=Leaf Signer/emailAddress=leaf@brev.example"
        ])
        try runOpenSSL([
            "x509", "-req", "-in", leafCSR.path,
            "-CA", interCert.path, "-CAkey", interKey.path, "-CAcreateserial",
            "-out", leafCert.path, "-days", "7",
            "-extfile", leafExt.path
        ])

        let p12URL = dir.appendingPathComponent("leaf-chain.p12")
        try runOpenSSL([
            "pkcs12", "-export",
            "-inkey", leafKey.path,
            "-in", leafCert.path,
            "-certfile", interCert.path,
            "-out", p12URL.path,
            "-passout", "pass:brevtest"
        ])

        let p12Data = try Data(contentsOf: p12URL)
        var itemsOpt: CFArray?
        try #require(
            SecPKCS12Import(
                p12Data as CFData,
                [kSecImportExportPassphrase as String: "brevtest"] as CFDictionary,
                &itemsOpt
            ) == errSecSuccess
        )
        let first = try #require((itemsOpt as? [[String: Any]])?.first)
        let identity = try #require(first[kSecImportItemIdentity as String] as! SecIdentity?)
        var leafSecCertOpt: SecCertificate?
        try #require(SecIdentityCopyCertificate(identity, &leafSecCertOpt) == errSecSuccess)
        let leafDER = try SecCertificateCopyData(#require(leafSecCertOpt)) as Data
        let chain = (first[kSecImportItemCertChain as String] as? [SecCertificate]) ?? []
        let intermediates = chain.filter { (SecCertificateCopyData($0) as Data) != leafDER }
        #expect(!intermediates.isEmpty)

        let content = Data("Content-Type: text/plain; charset=utf-8\r\n\r\nVerified via Root CA only.\r\n".utf8)
        let signatureDER = try PureSwiftCMSEncoder.detachedSignature(
            of: content,
            identity: identity,
            intermediateCertificates: intermediates
        )

        let contentFile = dir.appendingPathComponent("content.bin")
        try content.write(to: contentFile)
        // Verify with ONLY root.pem as trust anchor — proving the intermediate was embedded in SignedData.certificates.
        _ = try runOpenSSL(
            [
                "cms", "-verify", "-inform", "DER",
                "-content", contentFile.path,
                "-CAfile", rootCert.path,
                "-purpose", "any",
                "-out", "/dev/null"
            ],
            stdin: signatureDER
        )
    }

    @Test("separate To/Cc and Bcc encrypted envelopes prevent leaking Bcc certificate metadata")
    func separateBccEnvelopePreventsMetadataLeak() throws {
        let alice = try generateIdentity(email: "alice@brev.example", kind: .rsa)
        let bob = try generateIdentity(email: "bob@brev.example", kind: .rsa)
        let hidden = try generateIdentity(email: "hidden@brev.example", kind: .rsa)
        defer {
            alice.cleanup()
            bob.cleanup()
            hidden.cleanup()
        }

        let hiddenIssuerSerial = try X509CertificateParser.extractIssuerAndSerialNumber(
            from: SecCertificateCopyData(hidden.certificate) as Data
        )
        let plaintext = Data("Content-Type: text/plain; charset=utf-8\r\n\r\nPrivate Bcc test.\r\n".utf8)

        let visibleEnvelope = try PureSwiftCMSEncoder.envelopedData(
            of: plaintext,
            certificates: [alice.certificate, bob.certificate]
        )
        let bccEnvelope = try PureSwiftCMSEncoder.envelopedData(
            of: plaintext,
            certificates: [alice.certificate, hidden.certificate]
        )

        // Visible envelope decrypts for Alice & Bob, and does NOT contain Hidden's certificate serial.
        #expect(try decryptWithOpenSSL(envelopedDER: visibleEnvelope, recipient: alice) == plaintext)
        #expect(try decryptWithOpenSSL(envelopedDER: visibleEnvelope, recipient: bob) == plaintext)
        #expect(visibleEnvelope.range(of: hiddenIssuerSerial.serialNumberDER) == nil)

        // Separate Bcc envelope decrypts for Alice & Hidden.
        #expect(try decryptWithOpenSSL(envelopedDER: bccEnvelope, recipient: alice) == plaintext)
        #expect(try decryptWithOpenSSL(envelopedDER: bccEnvelope, recipient: hidden) == plaintext)
    }

    @Test("SMIMEOutboundMessagePreparer pureSwift fails closed on missing identity or recipient certificate")
    func preparerPureSwiftFailsClosedOnMissingMaterial() async throws {
        let alice = try generateIdentity(email: "alice@brev.example", kind: .rsa)
        defer { alice.cleanup() }

        struct PartialResolver: SMIMEIdentityResolving {
            let signing: SecIdentity?
            let certs: [String: SecCertificate]
            func signingIdentity(forSenderEmail _: String) async -> SecIdentity? { signing }
            func encryptionCertificates(forRecipients emails: [String]) async -> [String: SecCertificate] {
                var out: [String: SecCertificate] = [:]
                for email in emails {
                    let key = OutboundAddressNormalizer.normalize(email)
                    if let cert = certs[key] { out[key] = cert }
                }
                return out
            }
        }

        let rawMessage = Data("Subject: Test\r\n\r\nBody".utf8)

        let noSigning = SMIMEOutboundMessagePreparer(
            resolver: PartialResolver(signing: nil, certs: [:]),
            encodingBackend: .pureSwift
        )
        await #expect(throws: OutboundMessageSecurityError.missingSigningIdentity(senderEmail: "alice@brev.example")) {
            _ = try await noSigning.prepare(
                mimeData: rawMessage,
                request: OutboundMessageSecurityRequest(
                    senderEmail: "alice@brev.example",
                    to: ["bob@brev.example"],
                    mode: .sign
                )
            )
        }

        let missingRecipient = SMIMEOutboundMessagePreparer(
            resolver: PartialResolver(signing: alice.identity, certs: ["alice@brev.example": alice.certificate]),
            encodingBackend: .pureSwift
        )
        await #expect(throws: OutboundMessageSecurityError.missingEncryptionRecipients(["bob@brev.example"])) {
            _ = try await missingRecipient.prepare(
                mimeData: rawMessage,
                request: OutboundMessageSecurityRequest(
                    senderEmail: "alice@brev.example",
                    to: ["bob@brev.example"],
                    mode: .signAndEncrypt
                )
            )
        }

        let ec = try generateIdentity(email: "ec@brev.example", kind: .ecdsaP256)
        defer { ec.cleanup() }
        let unsupportedKey = SMIMEOutboundMessagePreparer(
            resolver: PartialResolver(
                signing: alice.identity,
                certs: [
                    "alice@brev.example": alice.certificate,
                    "ec@brev.example": ec.certificate
                ]
            ),
            encodingBackend: .pureSwift
        )
        await #expect(throws: PureSwiftCMSError.unsupportedEncryptionKeyAlgorithm) {
            _ = try await unsupportedKey.prepare(
                mimeData: rawMessage,
                request: OutboundMessageSecurityRequest(
                    senderEmail: "alice@brev.example",
                    to: ["ec@brev.example"],
                    mode: .encrypt
                )
            )
        }
    }
}
#endif
