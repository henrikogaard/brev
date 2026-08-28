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

@Suite("MailtoURL")
struct MailtoURLTests {
    @Test("path addresses are comma-separated and percent-decoded")
    func pathAddresses() throws {
        let mailto = try #require(MailtoURL(url: URL(string: "mailto:a@example.org,b%40example.org")!))
        #expect(mailto.to == ["a@example.org", "b@example.org"])
        #expect(mailto.cc.isEmpty)
        #expect(mailto.bcc.isEmpty)
        #expect(mailto.subject == nil)
        #expect(mailto.body == nil)
    }

    @Test("query headers to/cc/bcc/subject/body are extracted and percent-decoded")
    func queryHeaders() throws {
        let raw = "mailto:a@example.org?to=b@example.org,c@example.org&cc=d@example.org&bcc=e@example.org&subject=Hello%20World&body=Line%201%0D%0ALine%202"
        let mailto = try #require(MailtoURL(url: URL(string: raw)!))
        #expect(mailto.to == ["a@example.org", "b@example.org", "c@example.org"])
        #expect(mailto.cc == ["d@example.org"])
        #expect(mailto.bcc == ["e@example.org"])
        #expect(mailto.subject == "Hello World")
        #expect(mailto.body == "Line 1\r\nLine 2")
    }

    @Test("plus is a literal character, not a space (RFC 6068)")
    func plusIsLiteral() throws {
        let mailto = try #require(MailtoURL(url: URL(string: "mailto:?subject=a+b&to=user+tag@example.org")!))
        #expect(mailto.subject == "a+b")
        #expect(mailto.to == ["user+tag@example.org"])
    }

    @Test("header names are case-insensitive and unknown headers are ignored")
    func headerNames() throws {
        let mailto = try #require(MailtoURL(url: URL(string: "mailto:?Subject=Hi&CC=x@example.org&x-foo=bar")!))
        #expect(mailto.subject == "Hi")
        #expect(mailto.cc == ["x@example.org"])
    }

    @Test("empty mailto yields no recipients")
    func emptyMailto() throws {
        let mailto = try #require(MailtoURL(url: URL(string: "mailto:")!))
        #expect(mailto.to.isEmpty)
        #expect(mailto.isEmpty)
    }

    @Test("whitespace around addresses is trimmed and empty entries dropped")
    func trimming() throws {
        let mailto = try #require(MailtoURL(url: URL(string: "mailto:a@example.org,%20,%20b@example.org,")!))
        #expect(mailto.to == ["a@example.org", "b@example.org"])
    }

    @Test("scheme is matched case-insensitively and other schemes are rejected")
    func scheme() {
        #expect(MailtoURL(url: URL(string: "MAILTO:a@example.org")!)?.to == ["a@example.org"])
        #expect(MailtoURL(url: URL(string: "https://example.org")!) == nil)
        #expect(MailtoURL(url: URL(string: "brev://compose")!) == nil)
    }

    @Test("ComposePrefill maps all mailto fields including bcc")
    func composePrefill() throws {
        let raw = "mailto:a@example.org?cc=c@example.org&bcc=b@example.org&subject=S&body=B"
        let prefill = try #require(ComposePrefill(mailtoURL: URL(string: raw)!))
        #expect(prefill.to == ["a@example.org"])
        #expect(prefill.cc == ["c@example.org"])
        #expect(prefill.bcc == ["b@example.org"])
        #expect(prefill.subject == "S")
        #expect(prefill.bodyText == "B")
    }
}
