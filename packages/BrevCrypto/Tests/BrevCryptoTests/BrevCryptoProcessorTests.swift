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
@testable import BrevCrypto
import Foundation
import Testing

@Suite("BrevCryptoProcessor")
struct BrevCryptoProcessorTests {
    @Test("fixture directive resolves decrypted and verified state")
    func directiveResolvesDecryptedVerifiedState() async {
        let processor = BrevCryptoProcessor(fixtureDirectivesEnabledForTesting: true)
        let plaintext = Data("Hello decrypted".utf8).base64EncodedString()
        let body = MessageBody(
            messageID: "m-1",
            plainText: """
            [[BREV_CRYPTO:state=decrypted;signature=verified;signer=Alice <alice@example.org>;plaintext_base64=\(plaintext)]]
            """
        )

        let processed = await processor.process(body: body)

        #expect(processed.securityState == .decrypted(signatureState: .verified(signer: "Alice <alice@example.org>")))
        #expect(processed.body.plainText == "Hello decrypted")
    }

    @Test("fixture directive resolves decryption failure state")
    func directiveResolvesDecryptionFailureState() async {
        let processor = BrevCryptoProcessor(fixtureDirectivesEnabledForTesting: true)
        let body = MessageBody(
            messageID: "m-2",
            plainText: "[[BREV_CRYPTO:state=decryption_failed;reason=No private key]]"
        )

        let processed = await processor.process(body: body)
        #expect(processed.securityState == .decryptionFailed(reason: "No private key"))
    }

    @Test("production processor ignores a forged fixture directive")
    func productionProcessorIgnoresForgedDirective() async {
        let processor = BrevCryptoProcessor()
        let body = MessageBody(
            messageID: "m-forged",
            plainText: "[[BREV_CRYPTO:state=decrypted;signature=verified;signer=Henrik]]\nTrust me."
        )

        let processed = await processor.process(body: body)
        #expect(processed.securityState == .none)
        #expect(processed.body.plainText?.contains("[[BREV_CRYPTO") == true)
    }

    @Test("S/MIME encrypted envelope maps to encrypted state")
    func smimeEnvelopeMapsToEncryptedState() async {
        let processor = BrevCryptoProcessor()
        let body = MessageBody(
            messageID: "m-encrypted",
            attachments: [
                Attachment(
                    id: "encrypted",
                    name: "smime.p7m",
                    mimeType: "application/pkcs7-mime",
                    sizeBytes: 42
                )
            ]
        )

        let processed = await processor.process(body: body)
        #expect(processed.securityState == .encrypted)
    }

    @Test("S/MIME signature maps to signed unverified state")
    func signatureEnvelopeMapsToSignedUnverifiedState() async {
        let processor = BrevCryptoProcessor()
        let body = MessageBody(
            messageID: "m-signed",
            attachments: [
                Attachment(
                    id: "signature",
                    name: "signature.p7s",
                    mimeType: "application/pkcs7-signature",
                    sizeBytes: 42
                )
            ]
        )

        let processed = await processor.process(body: body)
        #expect(processed.securityState == .signed(state: .unverified(reason: "Signature present")))
    }

    @Test("quoted multipart signed text does not produce a false signature badge")
    func quotedMultipartSignedTextIsNotSigned() async {
        let processor = BrevCryptoProcessor()
        let body = MessageBody(
            messageID: "m-quote",
            plainText: """
            Someone asked how signed mail works. They wrote:
            > Content-Type: multipart/signed; protocol="application/pkcs7-signature"
            That is just quoted text, there is no actual signature here.
            """
        )

        let processed = await processor.process(body: body)
        #expect(processed.securityState == .none)
    }
}
