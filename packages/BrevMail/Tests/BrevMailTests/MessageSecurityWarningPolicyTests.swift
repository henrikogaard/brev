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
@testable import BrevMail
import Foundation
import Testing

@Suite("MessageSecurityWarningPolicy")
struct MessageSecurityWarningPolicyTests {
    @Test("display-name domain mismatch creates a sender warning")
    func displayNameDomainMismatchCreatesSenderWarning() {
        let analysis = MessageSecurityWarningPolicy.analyze(
            header: Self.header(
                from: Correspondent(
                    name: "Apple Support <security@apple.com>",
                    email: "notice@accounts.example"
                )
            ),
            bodyHTML: nil,
            replyTo: []
        )

        #expect(analysis.warnings.map(\.kind) == [
            .displayNameDomainMismatch(displayedDomain: "apple.com", senderDomain: "accounts.example")
        ])
        #expect(analysis
            .summary == "Sender or link details look unusual. Check the highlighted details before trusting this message.")
    }

    @Test("reply-to domain mismatch creates a reply warning")
    func replyToDomainMismatchCreatesReplyWarning() {
        let analysis = MessageSecurityWarningPolicy.analyze(
            header: Self.header(
                from: Correspondent(name: "Example Billing", email: "billing@example.com")
            ),
            bodyHTML: nil,
            replyTo: [Correspondent(name: "Billing", email: "billing@payments.example.net")]
        )

        #expect(analysis.warnings.map(\.kind) == [
            .replyToDomainMismatch(senderDomain: "example.com", replyToDomain: "payments.example.net")
        ])
    }

    @Test("deceptive link text creates a link warning")
    func deceptiveLinkTextCreatesLinkWarning() throws {
        let url = try #require(URL(string: "https://login.example.test/session"))
        let analysis = MessageSecurityWarningPolicy.analyze(
            header: Self.header(),
            bodyHTML: #"<a href="https://login.example.test/session">https://bank.example.com/security</a>"#,
            replyTo: []
        )

        #expect(analysis.linkWarnings == [
            MessageSecurityLinkWarning(
                url: url,
                displayedHost: "bank.example.com",
                destinationHost: "login.example.test",
                reason: .deceptiveText
            )
        ])
        #expect(analysis.warnings.map(\.kind) == [
            .deceptiveLink(displayedDomain: "bank.example.com", destinationDomain: "login.example.test")
        ])
    }

    // Regression: a `>` inside an earlier attribute of the <a> tag used to end
    // the tag scan before `href`, so the link was never extracted and the
    // deceptive-link warning was silently suppressed.
    @Test("a > inside an earlier <a> attribute does not suppress the deceptive-link warning")
    func quotedAngleBracketDoesNotSuppressDeceptiveLinkWarning() throws {
        let url = try #require(URL(string: "https://login.example.test/session"))
        let analysis = MessageSecurityWarningPolicy.analyze(
            header: Self.header(),
            bodyHTML: #"<a title="go here ->" href="https://login.example.test/session">https://bank.example.com/security</a>"#,
            replyTo: []
        )

        #expect(analysis.linkWarnings == [
            MessageSecurityLinkWarning(
                url: url,
                displayedHost: "bank.example.com",
                destinationHost: "login.example.test",
                reason: .deceptiveText
            )
        ])
    }

    @Test("a hidden matching URL in the label does not suppress a visible-domain mismatch")
    func hiddenMatchingURLDoesNotSuppressVisibleMismatch() {
        // The label shows the bank domain but also embeds a hidden URL matching
        // the (evil) destination — which previously suppressed the warning.
        let analysis = MessageSecurityWarningPolicy.analyze(
            header: Self.header(),
            bodyHTML: #"<a href="https://evil.test/x">Sign in at bank.example.com https://evil.test/x</a>"#,
            replyTo: []
        )

        #expect(analysis.linkWarnings.map(\.displayedHost) == ["bank.example.com"])
        #expect(analysis.linkWarnings.first?.destinationHost == "evil.test")
    }

    // Regression: a version/price/build-number token in the anchor text (e.g.
    // "v2.3.1", "$19.99") is a dotted number, not a domain. It must not be
    // treated as a displayed host, or a legitimate link raises a false
    // deceptive-link warning.
    @Test("a numeric version/price token in anchor text does not raise a false warning")
    func numericTokenInLabelDoesNotFalseWarn() {
        let analysis = MessageSecurityWarningPolicy.analyze(
            header: Self.header(),
            bodyHTML: #"<a href="https://shop.example.com/p">Get v2.3.1 for $19.99 at shop.example.com</a>"#,
            replyTo: []
        )
        #expect(analysis.linkWarnings.isEmpty)
    }

    @Test("punycode link hosts create an internationalized-domain warning")
    func punycodeLinkHostsCreateInternationalizedDomainWarning() throws {
        let url = try #require(URL(string: "https://xn--pple-43d.example/login"))
        let analysis = MessageSecurityWarningPolicy.analyze(
            header: Self.header(),
            bodyHTML: #"<a href="https://xn--pple-43d.example/login">Review account</a>"#,
            replyTo: []
        )

        #expect(analysis.linkWarnings == [
            MessageSecurityLinkWarning(
                url: url,
                displayedHost: nil,
                destinationHost: "xn--pple-43d.example",
                reason: .internationalizedDomain
            )
        ])
        #expect(analysis.warnings.map(\.kind) == [
            .internationalizedLink(destinationDomain: "xn--pple-43d.example")
        ])
    }

    @Test("unicode link hosts create an internationalized-domain warning")
    func unicodeLinkHostsCreateInternationalizedDomainWarning() throws {
        let url = try #require(URL(string: "https://äpple.example/login"))
        let analysis = MessageSecurityWarningPolicy.analyze(
            header: Self.header(),
            bodyHTML: #"<a href="https://äpple.example/login">Review account</a>"#,
            replyTo: []
        )

        #expect(analysis.linkWarnings == [
            MessageSecurityLinkWarning(
                url: url,
                displayedHost: nil,
                destinationHost: "xn--pple-koa.example",
                reason: .internationalizedDomain
            )
        ])
        #expect(analysis.warnings.map(\.kind) == [
            .internationalizedLink(destinationDomain: "xn--pple-koa.example")
        ])
    }

    @Test("matching sender and ordinary links produce no warnings")
    func matchingSenderAndOrdinaryLinksProduceNoWarnings() {
        let analysis = MessageSecurityWarningPolicy.analyze(
            header: Self.header(
                from: Correspondent(name: "Example Updates", email: "updates@example.com")
            ),
            bodyHTML: #"<a href="https://example.com/read">https://example.com/read</a>"#,
            replyTo: [Correspondent(name: "Example Support", email: "support@mail.example.com")]
        )

        #expect(analysis == .empty)
    }

    private static func header(
        from: Correspondent = Correspondent(name: "Example", email: "hello@example.com")
    ) -> MessageHeader {
        MessageHeader(
            id: "message-1",
            threadID: "thread-1",
            folderID: "inbox",
            from: from,
            subject: "Account update",
            snippet: "Please review",
            date: Date(timeIntervalSince1970: 1_779_960_600)
        )
    }
}
