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

@testable import BrevSettings
import Foundation
import Testing

@Suite("SecurityKeyMaterialPayloadDecoder")
struct SecurityKeyMaterialPayloadDecoderTests {
    @Test("stores unencoded certificate text as UTF-8")
    func storesUnencodedCertificateTextAsUTF8() throws {
        let payload = "certificate text"

        let data = try SecurityKeyMaterialPayloadDecoder.materialData(
            from: payload,
            family: .smime
        )

        #expect(data == Data(payload.utf8))
    }

    @Test("decodes pasted base64 PKCS12 material for S/MIME records")
    func decodesBase64PKCS12Material() throws {
        let raw = Data([0x30, 0x82, 0x01, 0x0A, 0x02, 0x01])
        let pasted = raw.base64EncodedString()

        let data = try SecurityKeyMaterialPayloadDecoder.materialData(
            from: pasted,
            family: .smime
        )

        #expect(data == raw)
    }

    @Test("decodes PEM-armored PKCS12 material for S/MIME records")
    func decodesPEMArmoredPKCS12Material() throws {
        let raw = Data([0x30, 0x82, 0x02, 0x0B, 0x02, 0x01])
        let pasted = """
        -----BEGIN PKCS12-----
        \(raw.base64EncodedString())
        -----END PKCS12-----
        """

        let data = try SecurityKeyMaterialPayloadDecoder.materialData(
            from: pasted,
            family: .smime
        )

        #expect(data == raw)
    }
}
