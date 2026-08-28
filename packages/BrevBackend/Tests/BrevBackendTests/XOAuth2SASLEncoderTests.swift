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
import Foundation
import Testing

@Suite("XOAuth2SASLEncoder")
struct XOAuth2SASLEncoderTests {
    // RFC 7628 §3.1 example: the raw string before base64 is
    // "user=someuser@example.com\x01auth=Bearer vF9dft4qmTc2Nvb3RlckBhamFsYXBhaS5jb20\x01\x01"
    // base64 = "dXNlcj1zb21ldXNlckBleGFtcGxlLmNvbQFhdXRoPUJlYXJlciB2RjlkZnQ0cW1UYzJOdmIzUmxja0JoYW1Gc1lYQmhhaS5jb20BAQ=="

    @Test("produces correct base64 output for RFC 7628 example values")
    func rfc7628ExampleOutput() {
        let email = "someuser@example.com"
        let token = "vF9dft4qmTc2Nvb3RlckBhamFsYXBhaS5jb20" // gitleaks:allow, RFC 7628 vector

        let sasl = XOAuth2SASLEncoder.encode(email: email, accessToken: token)

        // Verify by decoding and checking the raw string.
        let decoded = String(
            data: Data(base64Encoded: sasl, options: .ignoreUnknownCharacters)!,
            encoding: .utf8
        )!
        #expect(decoded == "user=\(email)\u{01}auth=Bearer \(token)\u{01}\u{01}")
    }

    @Test("encoded string is non-empty for valid inputs")
    func encodedStringIsNonEmpty() {
        let result = XOAuth2SASLEncoder.encode(email: "user@gmail.com", accessToken: "token123")
        #expect(!result.isEmpty)
    }

    @Test("output is valid base64")
    func outputIsValidBase64() {
        let result = XOAuth2SASLEncoder.encode(email: "user@gmail.com", accessToken: "mytoken")
        #expect(Data(base64Encoded: result) != nil)
    }

    @Test("output contains the email and token when decoded")
    func decodedOutputContainsEmailAndToken() {
        let email = "henrik@gmail.com"
        let token = "ya29.test-token-value"
        let encoded = XOAuth2SASLEncoder.encode(email: email, accessToken: token)
        guard let data = Data(base64Encoded: encoded),
              let decoded = String(data: data, encoding: .utf8)
        else {
            Issue.record("Could not decode base64 output")
            return
        }
        #expect(decoded.contains(email))
        #expect(decoded.contains(token))
        #expect(decoded.contains("auth=Bearer"))
    }

    @Test("output starts with 'user=' when decoded")
    func decodedOutputStartsWithUserPrefix() {
        let encoded = XOAuth2SASLEncoder.encode(email: "a@b.com", accessToken: "tok")
        let decoded = String(
            data: Data(base64Encoded: encoded)!,
            encoding: .utf8
        )!
        #expect(decoded.hasPrefix("user="))
    }

    @Test("output ends with two SOH characters when decoded")
    func decodedOutputEndsWithDoubleSOH() {
        let encoded = XOAuth2SASLEncoder.encode(email: "a@b.com", accessToken: "tok")
        let decoded = String(
            data: Data(base64Encoded: encoded)!,
            encoding: .utf8
        )!
        #expect(decoded.hasSuffix("\u{01}\u{01}"))
    }

    @Test("two different emails produce different output")
    func differentEmailsProduceDifferentOutput() {
        let first = XOAuth2SASLEncoder.encode(email: "alice@gmail.com", accessToken: "token")
        let second = XOAuth2SASLEncoder.encode(email: "bob@gmail.com", accessToken: "token")
        #expect(first != second)
    }

    @Test("two different tokens produce different output")
    func differentTokensProduceDifferentOutput() {
        let first = XOAuth2SASLEncoder.encode(email: "user@gmail.com", accessToken: "token-a")
        let second = XOAuth2SASLEncoder.encode(email: "user@gmail.com", accessToken: "token-b")
        #expect(first != second)
    }
}
