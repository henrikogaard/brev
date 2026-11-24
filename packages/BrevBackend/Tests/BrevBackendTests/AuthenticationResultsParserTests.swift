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

/// Unit tests for RFC 8601 `Authentication-Results` parsing and domain-aligned
/// sign-in trust verification for generic IMAP accounts (#5).
@Suite("RFC 8601 Authentication-Results parser and verifier")
struct AuthenticationResultsParserTests {
    // MARK: - Valid passing headers

    @Test("passes with dmarc=pass and aligned dkim=pass (Fastmail-style folded header with comments)")
    func foldedFastmailHeaderPasses() {
        let rawHeaders = """
        Delivered-To: user@fastmail.example\r
        Authentication-Results: mx2.messagingengine.com (Fastmail);\r
            dkim=pass (2048-bit rsa key; sha256) header.d=bank.example header.i=@bank.example header.b="AbCd;Ef12==";\r
            dmarc=pass (p=reject, d=none) policy.published-domain-policy=reject header.from=bank.example;\r
            spf=fail (sender IP not permitted) smtp.mailfrom=bounce@relay.thirdparty.example\r
        From: "Bank, Inc." <alerts@bank.example>\r
        Subject: Your verification code\r
        \r
        Your code is 123456
        """
        let assessment = AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: rawHeaders)
        #expect(assessment == .pass(fromDomain: "bank.example"))
    }

    @Test("passes with dmarc=pass and aligned spf=pass when dkim is absent or failing")
    func alignedSPFPassesWithoutDKIM() {
        let rawHeaders = """
        Authentication-Results: b.mail.icloud.com;\r
            dkim=fail (body hash did not verify) header.d=bank.example;\r
            spf=pass (b.mail.icloud.com: domain of bounce@mail.bank.example designates 192.0.2.1) smtp.mailfrom="bounce@mail.bank.example";\r
            dmarc=pass (p=REJECT sp=REJECT dis=NONE) header.from=bank.example\r
        From: Security <no-reply@bank.example>\r
        \r
        Body
        """
        let assessment = AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: rawHeaders)
        #expect(assessment == .pass(fromDomain: "bank.example"))
    }

    @Test("passes with relaxed subdomain alignment for dkim header.d and parent/sibling domains")
    func relaxedSubdomainAlignment() {
        // From subdomain, DKIM signed by organizational parent domain
        let childFrom = """
        Authentication-Results: mx.proton.example 1;
            dkim=pass header.d=bank.example;
            dmarc=pass header.from=auth.bank.example
        From: Bank Auth <codes@auth.bank.example>
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: childFrom) == .pass(fromDomain: "auth.bank.example"))

        // Sibling subdomains under same organizational domain (e.g. accounts.google.com + bounces.google.com)
        let siblingSPF = """
        Authentication-Results: b.mail.icloud.com;
            spf=pass smtp.mailfrom=3abc@gaia.bounces.bank.example;
            dmarc=pass header.from=accounts.bank.example
        From: Bank Accounts <no-reply@accounts.bank.example>
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: siblingSPF)
                == .pass(fromDomain: "accounts.bank.example")
        )

        // Multi-label public suffix: subdomains of bank.co.uk align with bank.co.uk
        let multiLabelTLD = """
        Authentication-Results: mx.example.net;
            dkim=pass header.d=mail.bank.co.uk;
            dmarc=pass header.from=alerts.bank.co.uk
        From: Bank UK <no-reply@alerts.bank.co.uk>
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: multiLabelTLD)
                == .pass(fromDomain: "alerts.bank.co.uk")
        )
    }

    @Test("passes with dkim header.i fallback when header.d is omitted")
    func dkimHeaderIFallback() {
        let rawHeaders = """
        Authentication-Results: mx.custom.example;
            dkim=pass header.i=@bank.example;
            dmarc=pass header.from=bank.example
        From: alerts@bank.example
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: rawHeaders) == .pass(fromDomain: "bank.example"))
    }

    @Test("passes when one of multiple dkim signatures is aligned and passes")
    func multipleDKIMSignaturesOneAligned() {
        let rawHeaders = """
        Authentication-Results: mx.fastmail.example;
            dkim=pass header.d=sendgrid.net;
            dkim=fail header.d=oldkey.bank.example;
            dkim=pass header.d=bank.example;
            dmarc=pass header.from=bank.example
        From: Bank <no-reply@bank.example>
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: rawHeaders) == .pass(fromDomain: "bank.example"))
    }

    @Test("passes with spf smtp.helo fallback when smtp.mailfrom is omitted")
    func spfHeloFallback() {
        let rawHeaders = """
        Authentication-Results: mx.custom.example;
            spf=pass smtp.helo=mail.bank.example;
            dmarc=pass header.from=bank.example
        From: Bank <no-reply@bank.example>
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: rawHeaders) == .pass(fromDomain: "bank.example"))
    }

    @Test("handles nested comments, quoted strings, method versions, CFWS around equals, and case insensitivity")
    func rfc8601SyntaxVariants() {
        let rawHeaders = """
        authentication-results: MX.Example.Net (outer (nested; dmarc=fail) comment) 1;
            DKIM/1 = PASS (comment with "quotes" and ; semicolons) header.d = "BANK.EXAMPLE" reason="all; good";
            DMARC = Pass header.from = "Bank.Example"
        fRoM: "alerts@evil.example" (Bank Team) <no-reply@BANK.example>
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: rawHeaders) == .pass(fromDomain: "bank.example"))
    }

    @Test("ignores attacker-injected lower Authentication-Results with different authserv-id when top passes")
    func lowerDifferentAuthservIgnoredWhenTopPasses() {
        let rawHeaders = """
        Authentication-Results: mx.fastmail.example; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example
        Authentication-Results: attacker.example; dmarc=pass header.from=evil.example; dkim=pass header.d=evil.example
        From: alerts@bank.example
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: rawHeaders) == .pass(fromDomain: "bank.example"))
    }

    // MARK: - Spoofing, smuggling, and failure edge cases

    @Test("attacker-injected lower Authentication-Results cannot override a failing top-most header")
    func injectedLowerHeaderCannotOverrideFailingTop() {
        let rawHeaders = """
        Authentication-Results: mx.fastmail.example; dmarc=fail header.from=bank.example; dkim=fail; spf=fail
        Authentication-Results: attacker.example; dmarc=pass header.from=bank.example; dkim=pass header.d=bank.example; spf=pass smtp.mailfrom=bank.example
        From: alerts@bank.example
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: rawHeaders) == .unavailable(.dmarcNotPass))
    }

    @Test("attacker-injected lower Authentication-Results cannot supply missing dmarc or dkim/spf")
    func injectedLowerHeaderCannotSupplyMissingPass() {
        let missingDMARCInTop = """
        Authentication-Results: mx.fastmail.example; spf=pass smtp.mailfrom=bank.example
        Authentication-Results: attacker.example; dmarc=pass header.from=bank.example; dkim=pass header.d=bank.example
        From: alerts@bank.example
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: missingDMARCInTop) == .unavailable(.missingDMARC))

        let missingMechanismInTop = """
        Authentication-Results: mx.fastmail.example; dmarc=pass header.from=bank.example
        Authentication-Results: attacker.example; dkim=pass header.d=bank.example; spf=pass smtp.mailfrom=bank.example
        From: alerts@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: missingMechanismInTop)
                == .unavailable(.missingAlignedMechanism)
        )
    }

    @Test("conflicting lower Authentication-Results with the same authserv-id fails closed")
    func conflictingSameAuthservIDFailsClosed() {
        let rawHeaders = """
        Authentication-Results: mx.fastmail.example; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example
        Authentication-Results: mx.fastmail.example; dmarc=pass header.from=forged.example
        From: alerts@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: rawHeaders)
                == .unavailable(.conflictingTrustedHeaders)
        )
    }

    @Test("rejects dmarc=pass when both dkim and spf fail or are unaligned")
    func dmarcPassWithoutAlignedDKIMOrSPFRejected() {
        let bothFail = """
        Authentication-Results: mx.example.net;
            dkim=fail header.d=bank.example;
            spf=fail smtp.mailfrom=bank.example;
            dmarc=pass header.from=bank.example
        From: alerts@bank.example
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: bothFail) == .unavailable(.missingAlignedMechanism))

        let bothUnaligned = """
        Authentication-Results: mx.example.net;
            dkim=pass header.d=thirdparty.example;
            spf=pass smtp.mailfrom=bounce@other.example;
            dmarc=pass header.from=bank.example
        From: alerts@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: bothUnaligned)
                == .unavailable(.missingAlignedMechanism)
        )

        // Multi-label public suffix attack: evil.co.uk must NEVER align with bank.co.uk
        let publicSuffixAttack = """
        Authentication-Results: mx.example.net;
            dkim=pass header.d=evil.co.uk;
            spf=pass smtp.mailfrom=bounce@evil.co.uk;
            dmarc=pass header.from=bank.co.uk
        From: alerts@bank.co.uk
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: publicSuffixAttack)
                == .unavailable(.missingAlignedMechanism)
        )
    }

    @Test("rejects dmarc=fail, dmarc=none, dmarc=temperror, dmarc=permerror", arguments: [
        "fail", "none", "temperror", "permerror", "bestguesspass"
    ])
    func nonPassDMARCRejected(_ result: String) {
        let rawHeaders = """
        Authentication-Results: mx.example.net; dkim=pass header.d=bank.example; dmarc=\(result) header.from=bank.example
        From: alerts@bank.example
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: rawHeaders) == .unavailable(.dmarcNotPass))
    }

    @Test("rejects comment or quoted-string smuggling of dmarc=pass")
    func commentAndQuoteSmugglingRejected() {
        let commentSmuggled = """
        Authentication-Results: mx.example.net; dkim=pass (fake; dmarc=pass header.from=bank.example) header.d=bank.example
        From: alerts@bank.example
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: commentSmuggled) == .unavailable(.missingDMARC))

        let quoteSmuggled = """
        Authentication-Results: mx.example.net; dkim=pass reason="; dmarc=pass header.from=bank.example" header.d=bank.example
        From: alerts@bank.example
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: quoteSmuggled) == .unavailable(.missingDMARC))
    }

    @Test("rejects header injection in message body after blank line")
    func bodyHeaderInjectionIgnored() {
        let rawMessage = """
        From: alerts@bank.example\r
        Subject: Spoofed\r
        \r
        Authentication-Results: mx.example.net; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example\r
        Your code is 999999
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: rawMessage) == .unavailable(.noTrustedHeader))
    }

    @Test("rejects misaligned header.from, missing From, multiple From headers, and multiple From addresses")
    func fromHeaderValidation() {
        let mismatched = """
        Authentication-Results: mx.example.net; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example
        From: alerts@other.example
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: mismatched) == .unavailable(.fromMismatch))

        let subdomainMismatch = """
        Authentication-Results: mx.example.net; dkim=pass header.d=mail.bank.example; dmarc=pass header.from=mail.bank.example
        From: alerts@bank.example
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: subdomainMismatch) == .unavailable(.fromMismatch))

        let missingFrom = """
        Authentication-Results: mx.example.net; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example
        Subject: No From
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: missingFrom) == .unavailable(.malformedFrom))

        let twoFromHeaders = """
        Authentication-Results: mx.example.net; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example
        From: alerts@bank.example
        From: alerts@bank.example
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: twoFromHeaders) == .unavailable(.malformedFrom))

        let multipleAddresses = """
        Authentication-Results: mx.example.net; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example
        From: a@bank.example, b@bank.example
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: multipleAddresses) == .unavailable(.malformedFrom))

        let twoAngleAddrs = """
        Authentication-Results: mx.example.net; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example
        From: <a@bank.example> <b@bank.example>
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: twoAngleAddrs) == .unavailable(.malformedFrom))
    }

    @Test("rejects missing, duplicate, and malformed Authentication-Results headers")
    func malformedAndDuplicateHeaders() {
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: "From: alerts@bank.example\r\n")
                == .unavailable(.noTrustedHeader)
        )

        let duplicateDMARC = """
        Authentication-Results: mx.example.net; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example; dmarc=fail header.from=bank.example
        From: alerts@bank.example
        """
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: duplicateDMARC) == .unavailable(.duplicateDMARC))

        for badValue in [
            "",
            "mx.example.net",
            "; dmarc=pass header.from=bank.example",
            "mx.example.net (unclosed comment; dmarc=pass header.from=bank.example",
            "mx.example.net; dkim=pass header.d=\"unclosed; dmarc=pass header.from=bank.example",
            "mx.example.net; dkim=pass header.d=bank.example; dmarc=pass",
            "mx.example.net; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example header.from=other.example"
        ] {
            let raw = "Authentication-Results: \(badValue)\r\nFrom: alerts@bank.example\r\n"
            #expect(
                AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: raw) == .unavailable(.malformedHeader),
                "Expected malformedHeader for \(badValue)"
            )
        }
    }

    @Test("no-result Authentication-Results: mx.example.net; none fails cleanly")
    func noResultHeader() {
        let raw = "Authentication-Results: mx.example.net; none\r\nFrom: alerts@bank.example\r\n"
        #expect(AuthenticationResultsSignInTrustAssessor.assess(rawHeaders: raw) == .unavailable(.missingDMARC))
    }
}
