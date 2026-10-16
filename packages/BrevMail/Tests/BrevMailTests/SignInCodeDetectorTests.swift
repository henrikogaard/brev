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

@testable import BrevMail
import Foundation
import Testing

@Suite("SignInCodeDetector")
struct SignInCodeDetectorTests {
    @Test("Recognizes explicit English and Norwegian code context", arguments: [
        "Your verification code is: 012345",
        "Your sign-in code: 012345",
        "One-time code\n012345",
        "Use 012345 to sign in.",
        "Din engangskode er 012345",
        "Kode for innlogging: 012345",
        "Bruk 012345 for å logge inn.",
    ])
    func codeContext(_ text: String) {
        #expect(SignInCodeDetector.detect(in: text) == .code("012345"))
    }

    @Test("Keeps code spelling and leading zeros", arguments: ["0123", "01234567", "aB12Cd"])
    func codeSpelling(_ code: String) {
        #expect(SignInCodeDetector.detect(in: "Verification code: \(code)") == .code(code))
    }

    @Test("Rejects ambiguous codes and ordinary numbers", arguments: [
        "123456", "Your code is 123456", "Verification code: 123", "Verification code: 123456789",
        "Verification code: ABCDEF", "Verification code: å12345", "Verification code: １２３４５６",
        "Verification code: K12345", "Verification code: 123456@example.test",
        "Verification code: 123456.example.test", "Verification code: 1234%",
        "Sign in. Order number: 123456", "Logg inn. Ordrenummer: 123456",
        "Verification code: order 123456", "Verification code: 1234.50 USD",
        "Verification code: $1234", "Logg inn. Pris: 1234 kr",
        "Verification code: +4712345678", "Verification code: 1234-5678",
        "Sign in. Phone: 12345678", "Logg inn. Telefon: 12345678",
        "Verification code: 2026-10-15", "Verification code: 15/10/2026",
        "Verification code: 20261015", "Logg inn. Dato: 15.10.2026",
        "Verification code: 123456 or 654321", "Verification code: 123456\nOne-time code: 654321",
        "Verification code: 123456\nVerification code: 123456",
        "Verification code: 123456\nSign in: https://login.example.test/session",
        "Verification code: 123456\nOrder number: 654321",
        "Verification code: 123456\u{202E}",
    ])
    func rejectsCodeAmbiguity(_ text: String) {
        #expect(SignInCodeDetector.detect(in: text) == nil)
    }

    @Test("Returns the exact HTTPS destination and actual host", arguments: [
        "Sign in: ", "Logg inn: ", "Verify your account: ", "Bekreft innlogging: ",
    ])
    func exactLink(_ prefix: String) {
        let destination = "https://login.example.test/session?token=A%2Fb%2Bc&next=%2Fhome#finish"
        #expect(SignInCodeDetector.detect(in: prefix + destination) == .link(
            destination: destination, host: "login.example.test"
        ))
    }

    @Test("Checks every displayed domain, not just the target appearing in the label")
    func displayedDomain() {
        #expect(SignInCodeDetector.detect(in: "Sign in to login.example.test: https://login.example.test/session") == .link(
            destination: "https://login.example.test/session", host: "login.example.test"
        ))
        #expect(SignInCodeDetector
            .detect(in: "Sign in to good.example.test and login.example.test: https://login.example.test/session") == nil)
    }

    @Test("Rejects unsafe, misleading, unsupported or ambiguous links", arguments: [
        "Sign in: http://login.example.test/session", "Sign in: javascript:alert(1)",
        "Sign in: /session", "Sign in: //login.example.test/session",
        "Sign in: https://user:pass@login.example.test/session",
        "Sign in: https://good.example.test@login.example.test/session",
        "Sign in: https://login.example.test:8443/session",
        "Sign in: https://login.example.test\\@evil.example.test/session",
        "Sign in: https://login.example.test/%ZZ", "Sign in: https://login.example.test/session.",
        "Sign in: https://login.example.test/session%0Aevil", "Sign in: https://login.example.test/%5Cevil",
        "Sign in: https://login.example.test/session https://other.example.test/session",
        "Sign in: https://login.example.test/session\nhttp://other.example.test/session",
        "Sign in: https://login.example.test/track?url=https%3A%2F%2Fgood.example.test",
        "Sign in: https://login.example.test/unsubscribe", "Meld av: https://login.example.test/session",
        "Sign in to good.example.test: https://evil.example.test/session",
        "Sign in to example.test: https://evil.example.test/session",
        "[Sign in to good.example.test](https://evil.example.test/session)",
        "<a href=\"https://evil.example.test/session\">Sign in to good.example.test</a>",
        "Sign in: https://xn--exmple-cua.test/session", "Sign in: https://exämple.test/session",
        "Sign in: https://127.0.0.1/session", "Sign in: https://localhost/session",
        "Sign in: https://login.example.test/session\u{200B}",
        "https://login.example.test/session",
    ])
    func rejectsLinks(_ text: String) {
        #expect(SignInCodeDetector.detect(in: text) == nil)
    }

    @Test("Has no serializable candidate or diagnostic payload")
    func ephemeralCandidate() throws {
        let candidate = try #require(SignInCodeDetector.detect(in: "Verification code: 012345"))
        let erased: Any = candidate
        #expect(!(erased is any Encodable))
        #expect(!(erased is any Decodable))
        #expect(!String(describing: candidate).contains("012345"))
        #expect(!String(reflecting: candidate).contains("012345"))
        #expect(Mirror(reflecting: candidate).children.isEmpty)
    }

    @Test("Bounds untrusted input and retains no prior result")
    func boundedStatelessDetection() {
        #expect(SignInCodeDetector.detect(in: String(repeating: "a", count: 65537)) == nil)
        #expect(SignInCodeDetector.detect(in: "Verification code: 012345") == .code("012345"))
        #expect(SignInCodeDetector.detect(in: "") == nil)
    }
}
