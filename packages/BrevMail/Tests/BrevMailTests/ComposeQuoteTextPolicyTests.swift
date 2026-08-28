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
import Testing

@Suite("ComposeQuoteTextPolicy")
struct ComposeQuoteTextPolicyTests {
    @Test("prefers decoded plain text over base64 listing snippet")
    func prefersDecodedPlainTextOverBase64Snippet() {
        let body = MessageBody(
            messageID: "m1",
            plainText: "Your Google AI Plus plan has ended."
        )

        let quote = ComposeQuoteTextPolicy.quoteText(
            body: body,
            fallbackSnippet: "UmVuZjyDNjyDNjyDN"
        )

        #expect(quote == "Your Google AI Plus plan has ended.")
    }

    @Test("falls back to stripped HTML when plain text is missing")
    func fallsBackToStrippedHTMLWhenPlainTextMissing() {
        let body = MessageBody(
            messageID: "m1",
            html: "<p>Hello <b>world</b>&nbsp;again.</p>"
        )

        let quote = ComposeQuoteTextPolicy.quoteText(
            body: body,
            fallbackSnippet: "UmVuZ"
        )

        #expect(quote == "Hello world again.")
    }

    @Test("HTML strip inserts breaks between adjacent block and link labels")
    func htmlStripInsertsBreaksBetweenAdjacentBlockAndLinkLabels() {
        let html = """
        <div><a href="#">Porkbun</a><a href="#">Learn More:</a></div>
        <div><a href="#">How to Renew Domain Names</a><a href="#">How to Transfer a Domain to Porkbun</a></div>
        <p>Important Domain Price Update</p><p>Hello,</p>
        """

        let plain = ComposeQuoteTextPolicy.htmlToPlainText(html)

        #expect(plain.contains("Porkbun"))
        #expect(plain.contains("Learn More:"))
        #expect(!plain.contains("PorkbunLearn More:"))
        #expect(!plain.contains("NamesHow to Transfer"))
        #expect(plain.contains("Important Domain Price Update"))
        #expect(plain.contains("Hello,"))
    }

    @Test("falls back to snippet when body is unavailable")
    func fallsBackToSnippetWhenBodyUnavailable() {
        let quote = ComposeQuoteTextPolicy.quoteText(
            body: nil,
            fallbackSnippet: "  Listing preview text.  "
        )

        #expect(quote == "Listing preview text.")
    }
}
