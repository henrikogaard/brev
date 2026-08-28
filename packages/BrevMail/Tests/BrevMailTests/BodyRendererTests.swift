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
@testable import BrevMail
import Foundation
import Testing

@Suite("BodyRenderer")
struct BodyRendererTests {
    @Test("default renderer surfaces encrypted state from crypto processor")
    func defaultRendererSurfacesEncryptedState() async {
        let renderer = BodyRenderer()
        let body = MessageBody(
            messageID: "m-1",
            attachments: [
                Attachment(
                    id: "encrypted",
                    name: "smime.p7m",
                    mimeType: "application/pkcs7-mime",
                    sizeBytes: 42
                )
            ]
        )

        let rendered = await renderer.render(body)
        #expect(rendered.securityState == .encrypted)
    }

    @Test("fixture directive surfaces decrypted signature state")
    func fixtureDirectiveSurfacesDecryptedState() async {
        let renderer = BodyRenderer(
            cryptoProcessor: BrevCryptoProcessor(fixtureDirectivesEnabledForTesting: true)
        )
        let plaintext = Data("hello".utf8).base64EncodedString()
        let body = MessageBody(
            messageID: "m-2",
            plainText: """
            [[BREV_CRYPTO:state=decrypted;signature=verified;signer=Alice;plaintext_base64=\(plaintext)]]
            """
        )

        let rendered = await renderer.render(body)
        #expect(rendered.securityState == .decrypted(signatureState: .verified(signer: "Alice")))
        #expect(rendered.plainText == "hello")
    }
}
