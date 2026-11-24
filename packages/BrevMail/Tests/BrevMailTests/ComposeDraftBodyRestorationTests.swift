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

@MainActor
@Suite("ComposeDraftBodyRestoration")
struct ComposeDraftBodyRestorationTests {
    @Test("nested blockquotes reopen with editable top reply and byte-for-byte preserved quote tail")
    func nestedBlockquotes() async throws {
        let quoteTail = "<blockquote>Outer<blockquote>Inner</blockquote></blockquote>"
        let html = "<strong>My reply</strong><br><br>\(quoteTail)"
        let restored = try await prepare(html, format: .richTextHTML)

        #expect(restored.attributedText.string == "My reply")
        #expect(restored.originalHTML == html)
        #expect(restored.preservedQuotedHTML == quoteTail)
        #expect(restored.quoteSeparatorHTML == "<br><br>")
        #expect(restored.preservedQuotedPlainText.contains("Outer"))
        #expect(restored.preservedQuotedPlainText.contains("Inner"))
        #expect(restored.initialEditorHTML == "<strong>My reply</strong>")
    }

    @Test("styled and Apple Mail type=cite blockquotes reopen without flattening")
    func styledAndAppleMailBlockquotes() async throws {
        let quoteTail = """
        <blockquote type="cite" style="border-left: 2px solid #ccc; margin: 0 0 0 8px">
            <div>Original <b>bold</b> line</div>
        </blockquote>
        """
        let html = "<p>Sounds good!</p>\(quoteTail)"
        let restored = try await prepare(html, format: .richTextHTML)

        #expect(restored.attributedText.string == "Sounds good!")
        #expect(restored.originalHTML == html)
        #expect(restored.preservedQuotedHTML == quoteTail)
    }

    @Test("Gmail gmail_quote with attribution and nested webmail table reopens intact")
    func gmailQuoteWithTable() async throws {
        let quoteTail = """
        <div class="gmail_quote gmail_quote_container">\
        <div dir="ltr" class="gmail_attr">On Mon, Jan 1, 2026 at 10:00 AM Alice &lt;<a href="mailto:alice@example.invalid">alice@example.invalid</a>&gt; wrote:<br></div>\
        <blockquote class="gmail_quote" style="margin:0px 0px 0px 0.8ex;border-left:1px solid rgb(204,204,204);padding-left:1ex">\
        <table cellpadding="4"><tr><td style="color:#333">Quarterly numbers</td></tr></table>\
        </blockquote></div>
        """
        let html = "<div dir=\"ltr\">Looks great, <strong>thanks</strong>!</div><br>\(quoteTail)"
        let restored = try await prepare(html, format: .richTextHTML)

        #expect(restored.attributedText.string == "Looks great, thanks!")
        #expect(restored.initialEditorHTML == "Looks great, <strong>thanks</strong>!")
        #expect(restored.originalHTML == html)
        #expect(restored.preservedQuotedHTML == quoteTail)
        #expect(restored.quoteSeparatorHTML == "<br>")
    }

    @Test("Gmail draft wrapped in outer dir=ltr container unwraps cleanly while keeping originalHTML intact")
    func gmailWrappedInOuterDirDiv() async throws {
        let quoteTail = """
        <div class="gmail_quote"><div class="gmail_attr">On Mon, Alice wrote:<br></div>\
        <blockquote class="gmail_quote" style="margin:0">Nested <em>webmail</em></blockquote></div>
        """
        let html = "<div dir=\"ltr\">Top reply<br>\(quoteTail)</div>"
        let restored = try await prepare(html, format: .richTextHTML)

        #expect(restored.attributedText.string == "Top reply")
        #expect(restored.originalHTML == html)
        #expect(restored.preservedQuotedHTML == quoteTail)
        #expect(restored.quoteSeparatorHTML == "<br>")
    }

    @Test("Outlook divRplyFwdMsg and trailing quoted siblings reopen intact")
    func outlookDivRplyFwdMsg() async throws {
        let quoteTail = """
        <div id="appendonsend"></div>\
        <hr style="display:inline-block;width:98%" tabindex="-1">\
        <div id="divRplyFwdMsg" dir="ltr"><font face="Calibri"><b>From:</b> Alice<br><b>Sent:</b> Monday</font></div>\
        <div class="BodyFragment"><p style="margin:0">Original Outlook message</p></div>
        """
        let html = "<div dir=\"ltr\">Got it.</div>\(quoteTail)"
        let restored = try await prepare(html, format: .richTextHTML)

        #expect(restored.attributedText.string == "Got it.")
        #expect(restored.originalHTML == html)
        #expect(restored.preservedQuotedHTML == quoteTail)
    }

    @Test("attribution header immediately preceding a complex blockquote stays with the preserved quote")
    func attributionHeaderPulledIntoPreservedQuote() async throws {
        let quoteTail = """
        <div>On Jan 1, 2026, at 10:00, Ada &lt;<a href="mailto:ada@example.invalid">ada@example.invalid</a>&gt; wrote:</div>\
        <blockquote type="cite" style="border-left:2px solid #999"><div>Original reply</div></blockquote>
        """
        let html = "<div>Sure thing!</div><div><br></div>\(quoteTail)"
        let restored = try await prepare(html, format: .richTextHTML)

        #expect(restored.attributedText.string == "Sure thing!")
        #expect(restored.originalHTML == html)
        #expect(restored.preservedQuotedHTML == quoteTail)
        #expect(restored.quoteSeparatorHTML == "<div><br></div>")
    }

    @Test("plain-text attribution line before nested blockquote stays with the preserved quote")
    func plainAttributionLineBeforeNestedBlockquote() async throws {
        let quoteTail = "On Jan 1, Ada &lt;ada@example.invalid&gt; wrote:<br><blockquote>Outer<blockquote>Inner</blockquote></blockquote>"
        let html = "Thanks!<br><br>\(quoteTail)"
        let restored = try await prepare(html, format: .richTextHTML)

        #expect(restored.attributedText.string == "Thanks!")
        #expect(restored.originalHTML == html)
        #expect(restored.preservedQuotedHTML == quoteTail)
        #expect(restored.quoteSeparatorHTML == "<br><br>")
    }

    @Test("draft with only a preserved quote opens with an empty editable top area")
    func quoteOnlyDraftOpensEmptyEditableTop() async throws {
        let html = "<blockquote>Outer<blockquote>Inner</blockquote></blockquote>"
        let restored = try await prepare(html, format: .richTextHTML)

        #expect(restored.attributedText.string == "")
        #expect(restored.initialEditorHTML == "")
        #expect(restored.originalHTML == html)
        #expect(restored.preservedQuotedHTML == html)
    }

    @Test("reassembly keeps originalHTML byte-for-byte on no-edit and preserves quote tail byte-for-byte on edit")
    func reassemblyBehavior() async throws {
        let quoteTail = "<blockquote type=\"cite\" style=\"border-left:2px solid #ccc\">Outer<blockquote>Inner</blockquote></blockquote>"
        let html = "<strong>Hi</strong><br><br>\(quoteTail)"
        let restored = try await prepare(html, format: .richTextHTML)

        let unedited = restored.htmlBodyForSave(
            currentBodyText: restored.attributedText.string,
            currentBodyHTML: restored.initialEditorHTML,
            editedTopHTML: restored.initialEditorHTML
        )
        #expect(unedited == html)

        let edited = restored.htmlBodyForSave(
            currentBodyText: "Hi updated",
            currentBodyHTML: "<strong>Hi</strong> updated",
            editedTopHTML: "<strong>Hi</strong> updated"
        )
        #expect(edited == "<strong>Hi</strong> updated<br><br>\(quoteTail)")

        let combinedPlain = restored.combinedPlainText(editedTopPlainText: "Hi updated")
        #expect(combinedPlain.hasPrefix("Hi updated\n\n"))
        #expect(combinedPlain.contains("Outer"))
        #expect(combinedPlain.contains("Inner"))
    }

    @Test("attribute values containing > and raw style blocks inside quotes scan accurately")
    func scannerHandlesQuotedAnglesAndStyleInsideQuote() async throws {
        let quoteTail = """
        <blockquote data-label="a > b" style="border-left:2px solid #ccc">\
        <style>.q > .p { color: #555; }</style>\
        <div>Safe quoted text</div>\
        </blockquote>
        """
        let html = "Reply<br>\(quoteTail)"
        let restored = try await prepare(html, format: .richTextHTML)

        #expect(restored.attributedText.string == "Reply")
        #expect(restored.preservedQuotedHTML == quoteTail)
    }

    @Test("plain-text mode refuses drafts with preserved rich quoted HTML", arguments: [
        "<blockquote><blockquote>Nested</blockquote></blockquote>",
        "<blockquote type=\"cite\">Quoted</blockquote>",
        "<div dir=\"ltr\">Hi</div><div class=\"gmail_quote\">Quoted</div>",
        "<div id=\"divRplyFwdMsg\">From: Alice</div>"
    ])
    func plainTextRefusesPreservedQuotes(html: String) async {
        await #expect(throws: (any Error).self) {
            _ = try await prepare(html, format: .plainText)
        }
    }

    @Test("malformed or unbalanced quotes and unsupported editable prefixes fail closed", arguments: [
        "<blockquote>unclosed",
        "<blockquote>Outer<blockquote>Inner</blockquote>",
        "stray</blockquote>",
        "<div class=\"gmail_quote\">unclosed",
        "<div id=\"divRplyFwdMsg\">unclosed",
        "<blockquote type=\"cite\"><div>mismatched</blockquote>",
        "<table><tr><td>Editable table</td></tr></table><blockquote type=\"cite\">Quoted</blockquote>",
        "<script>alert(1)</script>Top<blockquote type=\"cite\">Quoted</blockquote>",
        "<img src=\"https://example.invalid/pixel.png\">Top<blockquote type=\"cite\">Quoted</blockquote>",
        "<div style=\"color:red\">Styled top<blockquote type=\"cite\">Quoted</blockquote></div>",
        "<!-- unclosed comment --><blockquote type=\"cite\">Quoted"
    ])
    func malformedAndUnsupportedPrefixesFailClosed(html: String) async {
        await #expect(throws: (any Error).self) {
            _ = try await prepare(html, format: .richTextHTML)
        }
    }

    @Test("preview HTML strips active scripts and unsafe embeds without mutating stored quote")
    func previewSanitizesActiveContentOnly() {
        let rawQuote = """
        <blockquote type="cite" onclick="evil()">\
        <script>alert(1)</script>\
        <iframe src="https://evil.invalid"></iframe>\
        <a href="javascript:alert(1)">Bad</a>\
        <p>Safe quote</p>\
        </blockquote>
        """
        let preview = ComposeHTMLPreviewSource.html(
            richHTML: "<strong>Reply</strong>",
            plainBody: "Reply",
            preservedQuotedHTML: rawQuote,
            quoteSeparatorHTML: "<br><br>"
        )
        #expect(preview.contains("<strong>Reply</strong>"))
        #expect(preview.contains("Safe quote"))
        #expect(!preview.lowercased().contains("<script"))
        #expect(!preview.lowercased().contains("<iframe"))
        #expect(!preview.lowercased().contains("onclick"))
        #expect(!preview.lowercased().contains("javascript:"))
        // Original stored quote remains untouched.
        #expect(rawQuote.contains("<script>"))
    }

    private func prepare(
        _ html: String,
        format: ComposeBodyFormat
    ) async throws -> ComposeRestoredBody {
        try await ComposeDraftBodyRestoration.prepare(
            draft: Draft(id: "draft", inReplyToMessageID: "<reply@example.invalid>", htmlBody: html),
            format: format
        )
    }
}
