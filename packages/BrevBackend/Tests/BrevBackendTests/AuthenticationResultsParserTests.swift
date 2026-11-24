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

/// Unit tests for RFC 8601 `Authentication-Results` parsing, receiver provenance
/// checks, and domain-aligned sign-in trust verification for generic IMAP accounts (#5).
@Suite("RFC 8601 Authentication-Results parser and verifier")
struct AuthenticationResultsParserTests {
    private static let fastmailProvenance = IMAPSignInReceiverProvenance(incomingHost: "imap.fastmail.com")!
    private static let icloudProvenance = IMAPSignInReceiverProvenance(incomingHost: "imap.mail.me.com")!
    private static let customProvenance = IMAPSignInReceiverProvenance(incomingHost: "imap.customdomain.org")!
    private static let exampleNetProvenance = IMAPSignInReceiverProvenance(incomingHost: "imap.example.net")!

    // MARK: - Receiver provenance derivation & Codex/Devin security regressions

    @Test("derives trusted receiver boundaries for major providers and custom domains while rejecting local hosts")
    func receiverProvenanceBoundaries() {
        #expect(IMAPSignInReceiverProvenance(incomingHost: "") == nil)
        #expect(IMAPSignInReceiverProvenance(incomingHost: "localhost") == nil)
        #expect(IMAPSignInReceiverProvenance(incomingHost: "127.0.0.1") == nil)
        #expect(IMAPSignInReceiverProvenance(incomingHost: "::1") == nil)
        #expect(IMAPSignInReceiverProvenance(incomingHost: "mail.local") == nil)
        #expect(IMAPSignInReceiverProvenance(incomingHost: "bridge.internal") == nil)

        #expect(Self.fastmailProvenance.matches(authservID: "mx2.messagingengine.com"))
        #expect(Self.fastmailProvenance.matches(authservID: "mx.fastmail.com"))
        #expect(!Self.fastmailProvenance.matches(authservID: "attacker.example"))

        #expect(Self.icloudProvenance.matches(authservID: "b.mail.icloud.com"))
        #expect(Self.icloudProvenance.matches(authservID: "mx.me.com"))
        #expect(!Self.icloudProvenance.matches(authservID: "attacker.example"))

        let outlook = IMAPSignInReceiverProvenance(incomingHost: "outlook.office365.com")
        #expect(outlook?.matches(authservID: "nam11.protection.outlook.com") == true)
        #expect(outlook?.matches(authservID: "attacker.example") == false)

        #expect(Self.customProvenance.matches(authservID: "mx.customdomain.org"))
        #expect(Self.customProvenance.matches(authservID: "customdomain.org"))
        #expect(!Self.customProvenance.matches(authservID: "attacker.example"))
    }

    @Test("rejects attacker-forged Authentication-Results against Fastmail and custom IMAP hosts")
    func rejectsForgedForeignAuthservID() {
        let forged = """
        Authentication-Results: attacker.example; dmarc=pass header.from=bank.example; dkim=pass header.d=bank.example\r
        From: alerts@bank.example\r
        \r
        Your code is 482913
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: forged,
                receiverProvenance: Self.fastmailProvenance
            ) == .unavailable(.noTrustedHeader)
        )
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: forged,
                receiverProvenance: Self.customProvenance
            ) == .unavailable(.noTrustedHeader)
        )
    }

    @Test("rejects Authentication-Results placed below an external Received hop while allowing internal receiving hops")
    func receivedHopBoundaryCheck() {
        let belowExternalHop = """
        Received: from mail.sender.example by external.relay.net with ESMTPS id abc; Tue, 24 Nov 2026 14:00:00 +0000\r
        Authentication-Results: mx2.messagingengine.com; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example\r
        From: alerts@bank.example\r
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: belowExternalHop,
                receiverProvenance: Self.fastmailProvenance
            ) == .unavailable(.noTrustedHeader)
        )

        let belowInternalHop = """
        Received: from mx2.messagingengine.com by mailstore1.fastmail.com with LMTP; Tue, 24 Nov 2026 14:00:00 +0000\r
        Authentication-Results: mx2.messagingengine.com; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example\r
        From: alerts@bank.example\r
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: belowInternalHop,
                receiverProvenance: Self.fastmailProvenance
            ) == .pass(fromDomain: "bank.example")
        )
    }

    @Test("supports RFC 8601 quoted-string authserv-id tokens while rejecting malformed or untrusted quoted hosts")
    func quotedAuthservID() {
        let quotedValid = """
        Authentication-Results: "mx2.messagingengine.com" 1;
            dkim=pass header.d=bank.example;
            dmarc=pass header.from=bank.example
        From: alerts@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: quotedValid,
                receiverProvenance: Self.fastmailProvenance
            ) == .pass(fromDomain: "bank.example")
        )

        let quotedForeign = """
        Authentication-Results: "attacker.example";
            dkim=pass header.d=bank.example;
            dmarc=pass header.from=bank.example
        From: alerts@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: quotedForeign,
                receiverProvenance: Self.fastmailProvenance
            ) == .unavailable(.noTrustedHeader)
        )

        let quotedMalformed = """
        Authentication-Results: "bad host";
            dkim=pass header.d=bank.example;
            dmarc=pass header.from=bank.example
        From: alerts@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: quotedMalformed,
                receiverProvenance: Self.fastmailProvenance
            ) == .unavailable(.malformedHeader)
        )
    }

    // MARK: - Valid passing headers

    @Test("passes with dmarc=pass and aligned dkim=pass (Fastmail-style folded header with comments)")
    func foldedFastmailHeaderPasses() {
        let rawHeaders = """
        Delivered-To: user@fastmail.com\r
        Authentication-Results: mx2.messagingengine.com (Fastmail);\r
            dkim=pass (2048-bit rsa key; sha256) header.d=bank.example header.i=@bank.example header.b="AbCd;Ef12==";\r
            dmarc=pass (p=reject, d=none) policy.published-domain-policy=reject header.from=bank.example;\r
            spf=fail (sender IP not permitted) smtp.mailfrom=bounce@relay.thirdparty.example\r
        From: "Bank, Inc." <alerts@bank.example>\r
        Subject: Your verification code\r
        \r
        Your code is 123456
        """
        let assessment = AuthenticationResultsSignInTrustAssessor.assess(
            rawHeaders: rawHeaders,
            receiverProvenance: Self.fastmailProvenance
        )
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
        let assessment = AuthenticationResultsSignInTrustAssessor.assess(
            rawHeaders: rawHeaders,
            receiverProvenance: Self.icloudProvenance
        )
        #expect(assessment == .pass(fromDomain: "bank.example"))
    }

    @Test("passes with relaxed subdomain alignment for dkim header.d and parent/sibling domains")
    func relaxedSubdomainAlignment() {
        let childFrom = """
        Authentication-Results: mx.customdomain.org 1;
            dkim=pass header.d=bank.example;
            dmarc=pass header.from=auth.bank.example
        From: Bank Auth <codes@auth.bank.example>
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: childFrom,
                receiverProvenance: Self.customProvenance
            ) == .pass(fromDomain: "auth.bank.example")
        )

        let siblingSPF = """
        Authentication-Results: b.mail.icloud.com;
            spf=pass smtp.mailfrom=3abc@gaia.bounces.bank.example;
            dmarc=pass header.from=accounts.bank.example
        From: Bank Accounts <no-reply@accounts.bank.example>
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: siblingSPF,
                receiverProvenance: Self.icloudProvenance
            ) == .pass(fromDomain: "accounts.bank.example")
        )

        let multiLabelTLD = """
        Authentication-Results: mx.example.net;
            dkim=pass header.d=mail.bank.co.uk;
            dmarc=pass header.from=alerts.bank.co.uk
        From: Bank UK <no-reply@alerts.bank.co.uk>
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: multiLabelTLD,
                receiverProvenance: Self.exampleNetProvenance
            ) == .pass(fromDomain: "alerts.bank.co.uk")
        )
    }

    @Test("passes with dkim header.i fallback when header.d is omitted")
    func dkimHeaderIFallback() {
        let rawHeaders = """
        Authentication-Results: mx.customdomain.org;
            dkim=pass header.i=@bank.example;
            dmarc=pass header.from=bank.example
        From: alerts@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: rawHeaders,
                receiverProvenance: Self.customProvenance
            ) == .pass(fromDomain: "bank.example")
        )
    }

    @Test("passes when one of multiple dkim signatures is aligned and passes")
    func multipleDKIMSignaturesOneAligned() {
        let rawHeaders = """
        Authentication-Results: mx.fastmail.com;
            dkim=pass header.d=sendgrid.net;
            dkim=fail header.d=oldkey.bank.example;
            dkim=pass header.d=bank.example;
            dmarc=pass header.from=bank.example
        From: Bank <no-reply@bank.example>
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: rawHeaders,
                receiverProvenance: Self.fastmailProvenance
            ) == .pass(fromDomain: "bank.example")
        )
    }

    @Test("passes with spf smtp.helo fallback when smtp.mailfrom is omitted")
    func spfHeloFallback() {
        let rawHeaders = """
        Authentication-Results: mx.customdomain.org;
            spf=pass smtp.helo=mail.bank.example;
            dmarc=pass header.from=bank.example
        From: Bank <no-reply@bank.example>
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: rawHeaders,
                receiverProvenance: Self.customProvenance
            ) == .pass(fromDomain: "bank.example")
        )
    }

    @Test("handles nested comments, quoted strings, method versions, CFWS around equals, and case insensitivity")
    func rfc8601SyntaxVariants() {
        let rawHeaders = """
        authentication-results: MX.Example.Net (outer (nested; dmarc=fail) comment) 1;
            DKIM/1 = PASS (comment with "quotes" and ; semicolons) header.d = "BANK.EXAMPLE" reason="all; good";
            DMARC = Pass header.from = "Bank.Example"
        fRoM: "alerts@evil.example" (Bank Team) <no-reply@BANK.example>
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: rawHeaders,
                receiverProvenance: Self.exampleNetProvenance
            ) == .pass(fromDomain: "bank.example")
        )
    }

    @Test("ignores attacker-injected lower Authentication-Results with different authserv-id when top passes")
    func lowerDifferentAuthservIgnoredWhenTopPasses() {
        let rawHeaders = """
        Authentication-Results: mx.fastmail.com; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example
        Authentication-Results: attacker.example; dmarc=pass header.from=evil.example; dkim=pass header.d=evil.example
        From: alerts@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: rawHeaders,
                receiverProvenance: Self.fastmailProvenance
            ) == .pass(fromDomain: "bank.example")
        )
    }

    // MARK: - Spoofing, smuggling, and failure edge cases

    @Test("attacker-injected lower Authentication-Results cannot override a failing top-most header")
    func injectedLowerHeaderCannotOverrideFailingTop() {
        let rawHeaders = """
        Authentication-Results: mx.fastmail.com; dmarc=fail header.from=bank.example; dkim=fail; spf=fail
        Authentication-Results: attacker.example; dmarc=pass header.from=bank.example; dkim=pass header.d=bank.example; spf=pass smtp.mailfrom=bank.example
        From: alerts@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: rawHeaders,
                receiverProvenance: Self.fastmailProvenance
            ) == .unavailable(.dmarcNotPass)
        )
    }

    @Test("attacker-injected lower Authentication-Results cannot supply missing dmarc or dkim/spf")
    func injectedLowerHeaderCannotSupplyMissingPass() {
        let missingDMARCInTop = """
        Authentication-Results: mx.fastmail.com; spf=pass smtp.mailfrom=bank.example
        Authentication-Results: attacker.example; dmarc=pass header.from=bank.example; dkim=pass header.d=bank.example
        From: alerts@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: missingDMARCInTop,
                receiverProvenance: Self.fastmailProvenance
            ) == .unavailable(.missingDMARC)
        )

        let missingMechanismInTop = """
        Authentication-Results: mx.fastmail.com; dmarc=pass header.from=bank.example
        Authentication-Results: attacker.example; dkim=pass header.d=bank.example; spf=pass smtp.mailfrom=bank.example
        From: alerts@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: missingMechanismInTop,
                receiverProvenance: Self.fastmailProvenance
            ) == .unavailable(.missingAlignedMechanism)
        )
    }

    @Test("conflicting lower Authentication-Results with the same trust boundary fails closed")
    func conflictingSameAuthservIDFailsClosed() {
        let rawHeaders = """
        Authentication-Results: mx2.messagingengine.com; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example
        Authentication-Results: mx1.fastmail.com; dmarc=pass header.from=forged.example
        From: alerts@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: rawHeaders,
                receiverProvenance: Self.fastmailProvenance
            ) == .unavailable(.conflictingTrustedHeaders)
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
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: bothFail,
                receiverProvenance: Self.exampleNetProvenance
            ) == .unavailable(.missingAlignedMechanism)
        )

        let bothUnaligned = """
        Authentication-Results: mx.example.net;
            dkim=pass header.d=thirdparty.example;
            spf=pass smtp.mailfrom=bounce@other.example;
            dmarc=pass header.from=bank.example
        From: alerts@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: bothUnaligned,
                receiverProvenance: Self.exampleNetProvenance
            ) == .unavailable(.missingAlignedMechanism)
        )

        let publicSuffixAttack = """
        Authentication-Results: mx.example.net;
            dkim=pass header.d=evil.co.uk;
            spf=pass smtp.mailfrom=bounce@evil.co.uk;
            dmarc=pass header.from=bank.co.uk
        From: alerts@bank.co.uk
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: publicSuffixAttack,
                receiverProvenance: Self.exampleNetProvenance
            ) == .unavailable(.missingAlignedMechanism)
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
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: rawHeaders,
                receiverProvenance: Self.exampleNetProvenance
            ) == .unavailable(.dmarcNotPass)
        )
    }

    @Test("rejects comment or quoted-string smuggling of dmarc=pass")
    func commentAndQuoteSmugglingRejected() {
        let commentSmuggled = """
        Authentication-Results: mx.example.net; dkim=pass (fake; dmarc=pass header.from=bank.example) header.d=bank.example
        From: alerts@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: commentSmuggled,
                receiverProvenance: Self.exampleNetProvenance
            ) == .unavailable(.missingDMARC)
        )

        let quoteSmuggled = """
        Authentication-Results: mx.example.net; dkim=pass reason="; dmarc=pass header.from=bank.example" header.d=bank.example
        From: alerts@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: quoteSmuggled,
                receiverProvenance: Self.exampleNetProvenance
            ) == .unavailable(.missingDMARC)
        )
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
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: rawMessage,
                receiverProvenance: Self.exampleNetProvenance
            ) == .unavailable(.noTrustedHeader)
        )
    }

    @Test("rejects misaligned header.from, missing From, multiple From headers, and multiple From addresses")
    func fromHeaderValidation() {
        let mismatched = """
        Authentication-Results: mx.example.net; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example
        From: alerts@other.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: mismatched,
                receiverProvenance: Self.exampleNetProvenance
            ) == .unavailable(.fromMismatch)
        )

        let subdomainMismatch = """
        Authentication-Results: mx.example.net; dkim=pass header.d=mail.bank.example; dmarc=pass header.from=mail.bank.example
        From: alerts@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: subdomainMismatch,
                receiverProvenance: Self.exampleNetProvenance
            ) == .unavailable(.fromMismatch)
        )

        let missingFrom = """
        Authentication-Results: mx.example.net; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example
        Subject: No From
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: missingFrom,
                receiverProvenance: Self.exampleNetProvenance
            ) == .unavailable(.malformedFrom)
        )

        let twoFromHeaders = """
        Authentication-Results: mx.example.net; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example
        From: alerts@bank.example
        From: alerts@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: twoFromHeaders,
                receiverProvenance: Self.exampleNetProvenance
            ) == .unavailable(.malformedFrom)
        )

        let multipleAddresses = """
        Authentication-Results: mx.example.net; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example
        From: a@bank.example, b@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: multipleAddresses,
                receiverProvenance: Self.exampleNetProvenance
            ) == .unavailable(.malformedFrom)
        )

        let twoAngleAddrs = """
        Authentication-Results: mx.example.net; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example
        From: <a@bank.example> <b@bank.example>
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: twoAngleAddrs,
                receiverProvenance: Self.exampleNetProvenance
            ) == .unavailable(.malformedFrom)
        )
    }

    @Test("rejects missing, duplicate, and malformed Authentication-Results headers")
    func malformedAndDuplicateHeaders() {
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: "From: alerts@bank.example\r\n",
                receiverProvenance: Self.exampleNetProvenance
            ) == .unavailable(.noTrustedHeader)
        )

        let duplicateDMARC = """
        Authentication-Results: mx.example.net; dkim=pass header.d=bank.example; dmarc=pass header.from=bank.example; dmarc=fail header.from=bank.example
        From: alerts@bank.example
        """
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: duplicateDMARC,
                receiverProvenance: Self.exampleNetProvenance
            ) == .unavailable(.duplicateDMARC)
        )

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
                AuthenticationResultsSignInTrustAssessor.assess(
                    rawHeaders: raw,
                    receiverProvenance: Self.exampleNetProvenance
                ) == .unavailable(.malformedHeader),
                "Expected malformedHeader for \(badValue)"
            )
        }
    }

    @Test("no-result Authentication-Results: mx.example.net; none fails cleanly")
    func noResultHeader() {
        let raw = "Authentication-Results: mx.example.net; none\r\nFrom: alerts@bank.example\r\n"
        #expect(
            AuthenticationResultsSignInTrustAssessor.assess(
                rawHeaders: raw,
                receiverProvenance: Self.exampleNetProvenance
            ) == .unavailable(.missingDMARC)
        )
    }
}
