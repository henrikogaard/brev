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
@testable import BrevBackend
@testable import BrevCrypto
import Foundation
import Security
import Testing

private let smimeEmail = "smime-test@brev.example"

private struct StubSMIMEResolver: SMIMEIdentityResolving {
    let identity: SecIdentity
    let certificate: SecCertificate
    func signingIdentity(forSenderEmail email: String) async -> SecIdentity? {
        OutboundAddressNormalizer.normalize(email) == smimeEmail ? identity : nil
    }

    func encryptionCertificates(forRecipients emails: [String]) async -> [String: SecCertificate] {
        var out: [String: SecCertificate] = [:]
        for e in emails where OutboundAddressNormalizer.normalize(e) == smimeEmail {
            out[smimeEmail] = certificate
        }
        return out
    }
}

private func loadFixture() throws -> (SecIdentity, SecCertificate) {
    let b64 = "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"
    let data = try #require(Data(base64Encoded: b64))
    var items: CFArray?
    try #require(SecPKCS12Import(data as CFData, [kSecImportExportPassphrase as String: "brevtest"] as CFDictionary, &items) ==
        errSecSuccess)
    let dict = try #require((items as? [[String: Any]])?.first)
    let identity = try #require(dict[kSecImportItemIdentity as String] as! SecIdentity?)
    var certOpt: SecCertificate?
    try #require(SecIdentityCopyCertificate(identity, &certOpt) == errSecSuccess)
    return try (identity, #require(certOpt))
}

private let message = Data("""
From: Test <smime-test@brev.example>\r
To: Test <smime-test@brev.example>\r
Subject: S/MIME\r
MIME-Version: 1.0\r
Content-Type: text/plain; charset=utf-8\r
\r
Hello over S/MIME.\r
""".utf8)

private func request(_ mode: OutboundMessageSecurityMode) -> OutboundMessageSecurityRequest {
    OutboundMessageSecurityRequest(senderEmail: smimeEmail, to: [smimeEmail], mode: mode)
}

@Suite("SMIMEOutboundMessagePreparer")
struct SMIMEOutboundMessagePreparerTests {
    @Test("signs into multipart/signed and the CMS signature verifies")
    func signRoundTrips() async throws {
        let (identity, cert) = try loadFixture()
        let engine = SMIMEOutboundMessagePreparer(resolver: StubSMIMEResolver(identity: identity, certificate: cert))
        let out = try await engine.prepare(mimeData: message, request: request(.sign))
        let text = String(decoding: out, as: UTF8.self)
        #expect(text.contains("multipart/signed"))
        #expect(text.contains("application/pkcs7-signature"))
        #expect(text.contains("smime.p7s"))
        #expect(text.contains("Subject: S/MIME")) // headers preserved

        // Extract the base64 p7s and CMS-verify it against the signed content entity.
        let split = MIMEEntitySplit.make(from: message)
        let sigBase64 = extractBase64Part(text, afterMarker: "filename=\"smime.p7s\"")
        let signature = try #require(Data(base64Encoded: sigBase64, options: .ignoreUnknownCharacters))
        try verifyDetached(signature: signature, content: split.contentEntity)
    }

    @Test("encrypts into application/pkcs7-mime enveloped-data")
    func encryptStructure() async throws {
        let (identity, cert) = try loadFixture()
        let engine = SMIMEOutboundMessagePreparer(resolver: StubSMIMEResolver(identity: identity, certificate: cert))
        let out = try await engine.prepare(mimeData: message, request: request(.encrypt))
        let text = String(decoding: out, as: UTF8.self)
        #expect(text.contains("application/pkcs7-mime"))
        #expect(text.contains("smime-type=enveloped-data"))
        #expect(text.contains("smime.p7m"))
        #expect(text.contains("Subject: S/MIME"))
    }

    @Test("mode .none passes the plaintext through")
    func noneMode() async throws {
        let (identity, cert) = try loadFixture()
        let engine = SMIMEOutboundMessagePreparer(resolver: StubSMIMEResolver(identity: identity, certificate: cert))
        let out = try await engine.prepare(mimeData: message, request: request(.none))
        #expect(out == message)
    }

    // MARK: helpers

    private func extractBase64Part(_ text: String, afterMarker marker: String) -> String {
        guard let markerRange = text.range(of: marker),
              let blankRange = text.range(of: "\r\n\r\n", range: markerRange.upperBound ..< text.endIndex)
        else { return "" }
        let rest = text[blankRange.upperBound...]
        // up to the next boundary line
        if let boundary = rest.range(of: "\r\n--") {
            return String(rest[..<boundary.lowerBound])
        }
        return String(rest)
    }

    private func verifyDetached(signature: Data, content: Data) throws {
        var decoderOpt: CMSDecoder?
        try #require(CMSDecoderCreate(&decoderOpt) == errSecSuccess)
        let decoder = try #require(decoderOpt)
        signature.withUnsafeBytes { _ = CMSDecoderUpdateMessage(decoder, $0.baseAddress!, signature.count) }
        CMSDecoderSetDetachedContent(decoder, content as CFData)
        try #require(CMSDecoderFinalizeMessage(decoder) == errSecSuccess)
        var signerStatus: CMSSignerStatus = .unsigned
        var certVerify: OSStatus = 0
        var trust: SecTrust?
        CMSDecoderCopySignerStatus(decoder, 0, SecPolicyCreateBasicX509(), false, &signerStatus, &trust, &certVerify)
        #expect(signerStatus == .valid)
    }
}
#endif
