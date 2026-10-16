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
@testable import BrevGmail
import Foundation
import Testing

/// Synthetic fixtures for the ADR-0088 Gmail trust rule. Header values are
/// fabricated — no real sign-in codes, addresses, or provider data.
@Suite("Gmail sign-in trust assessor")
struct GmailSignInTrustAssessorTests {
    private func ar(_ value: String) -> GmailMessageHeader {
        GmailMessageHeader(name: "Authentication-Results", value: value)
    }

    private func from(_ value: String) -> GmailMessageHeader {
        GmailMessageHeader(name: "From", value: value)
    }

    @Test("E1: genuine aligned message passes")
    func alignedPass() {
        let assessment = GmailSignInTrustAssessor.assess(headers: [
            ar(
                "mx.google.com; dkim=pass header.i=@bank.example; spf=pass smtp.mailfrom=bank.example; dmarc=pass header.from=bank.example"
            ),
            from("Bank <alerts@bank.example>")
        ])
        #expect(assessment == .pass(fromDomain: "bank.example"))
    }

    @Test("E2: a lower forged mx.google.com header fails closed")
    func lowerForgedGoogleHeader() {
        let assessment = GmailSignInTrustAssessor.assess(headers: [
            ar("mx.google.com; dmarc=pass header.from=bank.example"),
            ar("mx.google.com; dmarc=pass header.from=forged.example"),
            from("Bank <alerts@bank.example>")
        ])
        #expect(assessment == .unavailable(.conflictingTrustedHeaders))
    }

    @Test("E3: a forged lower header with a different authserv-id is decided by the top header")
    func lowerForgedOtherAuthservID() {
        let assessment = GmailSignInTrustAssessor.assess(headers: [
            ar("mx.google.com; dmarc=pass header.from=bank.example"),
            ar("attacker.example; dmarc=pass header.from=evil.example"),
            from("Bank <alerts@bank.example>")
        ])
        #expect(assessment == .pass(fromDomain: "bank.example"))
    }

    @Test("folded genuine header parses like its unfolded form")
    func foldedGenuinePass() {
        let assessment = GmailSignInTrustAssessor.assess(headers: [
            ar(
                "mx.google.com;\r\n       dkim=pass header.i=@bank.example;\r\n       spf=pass smtp.mailfrom=bank.example;\r\n       dmarc=pass (p=REJECT sp=REJECT dis=NONE) header.from=bank.example"
            ),
            from("Bank <alerts@bank.example>")
        ])
        #expect(assessment == .pass(fromDomain: "bank.example"))
    }

    @Test("folded header with a lower forged mx.google.com copy fails closed")
    func foldedLowerForged() {
        let assessment = GmailSignInTrustAssessor.assess(headers: [
            ar("mx.google.com;\r\n       dmarc=pass header.from=bank.example"),
            ar("mx.google.com;\r\n       dmarc=pass header.from=forged.example"),
            from("Bank <alerts@bank.example>")
        ])
        #expect(assessment == .unavailable(.conflictingTrustedHeaders))
    }

    @Test("E4: dmarc=fail and dmarc=none both fail")
    func dmarcFailAndNone() {
        for result in ["fail", "none"] {
            let assessment = GmailSignInTrustAssessor.assess(headers: [
                ar("mx.google.com; dmarc=\(result) header.from=bank.example"),
                from("alerts@bank.example")
            ])
            #expect(assessment == .unavailable(.dmarcNotPass))
        }
    }

    @Test("topmost Authentication-Results from a different receiver is not trusted")
    func topmostNotGoogle() {
        let assessment = GmailSignInTrustAssessor.assess(headers: [
            ar("attacker.example; dmarc=pass header.from=bank.example"),
            ar("mx.google.com; dmarc=pass header.from=bank.example"),
            from("alerts@bank.example")
        ])
        #expect(assessment == .unavailable(.noTrustedHeader))
    }

    @Test("no Authentication-Results header is not trusted")
    func noAuthenticationResults() {
        let assessment = GmailSignInTrustAssessor.assess(headers: [
            from("alerts@bank.example")
        ])
        #expect(assessment == .unavailable(.noTrustedHeader))
    }

    @Test("missing dmarc= result is unavailable")
    func missingDMARC() {
        let assessment = GmailSignInTrustAssessor.assess(headers: [
            ar("mx.google.com; dkim=pass header.i=@bank.example; spf=pass smtp.mailfrom=bank.example"),
            from("alerts@bank.example")
        ])
        #expect(assessment == .unavailable(.missingDMARC))
    }

    @Test("duplicate dmarc= results fail closed")
    func duplicateDMARC() {
        let assessment = GmailSignInTrustAssessor.assess(headers: [
            ar("mx.google.com; dmarc=pass header.from=bank.example; dmarc=pass header.from=bank.example"),
            from("alerts@bank.example")
        ])
        #expect(assessment == .unavailable(.duplicateDMARC))
    }

    @Test("header.from mismatch rejects exact-domain check")
    func headerFromMismatch() {
        let assessment = GmailSignInTrustAssessor.assess(headers: [
            ar("mx.google.com; dmarc=pass header.from=bank.example"),
            from("alerts@other.example")
        ])
        #expect(assessment == .unavailable(.fromMismatch))
    }

    @Test("subdomain vs parent is not relaxed")
    func subdomainNotRelaxed() {
        let assessment = GmailSignInTrustAssessor.assess(headers: [
            ar("mx.google.com; dmarc=pass header.from=mail.bank.example"),
            from("alerts@bank.example")
        ])
        #expect(assessment == .unavailable(.fromMismatch))
    }

    @Test("two From headers are malformed")
    func twoFromHeaders() {
        let assessment = GmailSignInTrustAssessor.assess(headers: [
            ar("mx.google.com; dmarc=pass header.from=bank.example"),
            from("alerts@bank.example"),
            from("alerts@bank.example")
        ])
        #expect(assessment == .unavailable(.malformedFrom))
    }

    @Test("a From header with two addresses is malformed")
    func twoFromAddresses() {
        let assessment = GmailSignInTrustAssessor.assess(headers: [
            ar("mx.google.com; dmarc=pass header.from=bank.example"),
            from("a@bank.example, b@bank.example")
        ])
        #expect(assessment == .unavailable(.malformedFrom))
    }

    @Test("header name and domain matching is case-insensitive")
    func caseInsensitive() {
        let assessment = GmailSignInTrustAssessor.assess(headers: [
            GmailMessageHeader(
                name: "authentication-results",
                value: "MX.Google.Com; DMARC=pass Header.From=BANK.example"
            ),
            GmailMessageHeader(name: "fRoM", value: "Alerts <alerts@bank.EXAMPLE>")
        ])
        #expect(assessment == .pass(fromDomain: "bank.example"))
    }

    @Test("an unparseable topmost header is malformed")
    func malformedTopmost() {
        for value in ["", "   ", "; dmarc=pass header.from=bank.example", "mx.google.com"] {
            let assessment = GmailSignInTrustAssessor.assess(headers: [
                ar(value),
                from("alerts@bank.example")
            ])
            #expect(assessment == .unavailable(.malformedHeader), "expected malformedHeader for \(value)")
        }
    }

    @Test("a dmarc result without header.from is malformed")
    func dmarcWithoutHeaderFrom() {
        let assessment = GmailSignInTrustAssessor.assess(headers: [
            ar("mx.google.com; dmarc=pass"),
            from("alerts@bank.example")
        ])
        #expect(assessment == .unavailable(.malformedHeader))
    }

    @Test("no header values survive description, reflection, or Codable")
    func noHeaderValueLeaks() {
        let canary = "dmarc=pass header.from=sender.invalid"
        let assessment = GmailSignInTrustAssessor.assess(headers: [
            ar("mx.google.com; \(canary)"),
            from("From Display <a@sender.invalid>")
        ])
        let pass = GmailSignInTrustAssessor.assess(headers: [
            ar("mx.google.com; \(canary)"),
            from("a@sender.invalid")
        ])
        for value in [assessment, pass] {
            #expect(!(value is any Codable))
            #expect(!String(describing: value).contains("dmarc=pass"))
            #expect(!String(reflecting: value).contains("From Display"))
            let mirror = Mirror(reflecting: value)
            #expect(!mirror.children.contains { String(describing: $0.value).contains("From Display") })
        }
    }
}
