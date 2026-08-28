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

@Suite("MailPrintDocument")
struct MailPrintDocumentTests {
    // MARK: - Factory

    private func header(subject: String) -> MessageHeader {
        MessageHeader(
            id: "m-test",
            threadID: "t-test",
            folderID: "inbox",
            from: Correspondent(name: "Alice Example", email: "alice@example.org"),
            to: [Correspondent(email: "bob@example.org")],
            subject: subject,
            snippet: "",
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - Tests

    @Test("plain-text entry includes subject, from, date, and body")
    func plainTextEntry() {
        let h = header(subject: "Quarterly update")
        let body = MessageBody(messageID: "m-test", plainText: "Numbers look good.")
        let text = MailPrintDocument.plainText(messages: [(h, body)])
        #expect(text.contains("Quarterly update"))
        #expect(text.contains("From:"))
        #expect(text.contains("Date:"))
        #expect(text.contains("Numbers look good."))
    }

    @Test("empty subject renders a placeholder")
    func emptySubjectPlaceholder() {
        let text = MailPrintDocument.plainText(messages: [(header(subject: ""), nil as MessageBody?)])
        #expect(text.contains("(No subject)"))
    }

    @Test("html body is reduced to plain text without style/script leakage")
    func htmlReducedToText() {
        let html = "<style>.x{color:red}</style><p>Hello &amp; welcome</p><script>alert(1)</script>"
        let body = MessageBody(messageID: "m-test", html: html)
        let text = MailPrintDocument.plainText(messages: [(header(subject: "S"), body)])
        #expect(text.contains("Hello & welcome"))
        #expect(!text.contains("color:red"))
        #expect(!text.contains("alert(1)"))
    }

    @Test("multiple messages are separated by a divider in order")
    func threadOrderAndDivider() {
        let text = MailPrintDocument.plainText(messages: [
            (header(subject: "First"), nil as MessageBody?),
            (header(subject: "Second"), nil as MessageBody?),
        ])
        #expect(text.range(of: "First")!.lowerBound < text.range(of: "Second")!.lowerBound)
        #expect(text.contains(String(repeating: "-", count: 72)))
    }

    @Test("html output escapes the body and is self-contained (no remote refs)")
    func htmlOutputEscaped() {
        let body = MessageBody(messageID: "m-test", plainText: "a < b & c")
        let html = MailPrintDocument.html(messages: [(header(subject: "T & U"), body)])
        #expect(html.contains("a &lt; b &amp; c"))
        #expect(html.contains("T &amp; U"))
        #expect(!html.contains("http://"))
        #expect(!html.contains("https://"))
    }
}
