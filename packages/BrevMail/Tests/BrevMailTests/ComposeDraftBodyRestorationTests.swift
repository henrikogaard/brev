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

    @Test("enclosing RTL direction wrapper is preserved on edited reassembly and in quote previews")
    func rtlWrapperPreservedOnEditAndPreview() async throws {
        let hebrewQuote = "<blockquote type=\"cite\">עברית</blockquote>"
        let hebrewHTML = "<div dir=\"rtl\">Reply<br>\(hebrewQuote)</div>"
        let hebrewRestored = try await prepare(hebrewHTML, format: .richTextHTML)

        #expect(hebrewRestored.attributedText.string == "Reply")
        #expect(hebrewRestored.preservedQuotedHTML == hebrewQuote)
        #expect(hebrewRestored.inheritedDirection == "rtl")
        #expect(hebrewRestored.outerWrapperOpenHTML == "<div dir=\"rtl\">")
        #expect(hebrewRestored.outerWrapperCloseHTML == "</div>")

        let hebrewEdited = hebrewRestored.htmlBodyForSave(
            currentBodyText: "Updated reply",
            currentBodyHTML: "Updated reply",
            editedTopHTML: "Updated reply"
        )
        #expect(hebrewEdited == "<div dir=\"rtl\">Updated reply<br>\(hebrewQuote)</div>")

        let arabicQuote = "<div class=\"gmail_quote\">الاجتماع Friday?</div>"
        let arabicHTML = "<div dir=\"rtl\">Reply<br>\(arabicQuote)</div>"
        let arabicRestored = try await prepare(arabicHTML, format: .richTextHTML)

        #expect(arabicRestored.inheritedDirection == "rtl")
        let arabicEdited = arabicRestored.htmlBodyForSave(
            currentBodyText: "Reply updated",
            currentBodyHTML: "Reply updated",
            editedTopHTML: "Reply updated"
        )
        #expect(arabicEdited == "<div dir=\"rtl\">Reply updated<br>\(arabicQuote)</div>")

        let sectionPreview = ComposeHTMLPreviewSource.sanitizedQuotePreviewHTML(
            arabicQuote,
            inheritedDirection: arabicRestored.inheritedDirection
        )
        #expect(sectionPreview == "<div dir=\"rtl\">\(arabicQuote)</div>")

        let fullPreview = ComposeHTMLPreviewSource.html(
            richHTML: "Reply updated",
            plainBody: "Reply updated",
            preservedQuotedHTML: arabicRestored.preservedQuotedHTML,
            quoteSeparatorHTML: arabicRestored.quoteSeparatorHTML,
            outerWrapperOpenHTML: arabicRestored.outerWrapperOpenHTML,
            outerWrapperCloseHTML: arabicRestored.outerWrapperCloseHTML
        )
        #expect(fullPreview == "<div dir=\"rtl\">Reply updated<br>\(arabicQuote)</div>")
    }

    @Test("raw style block with 8000+ repeated < characters scans linearly without stalling")
    func linearScanOnRepeatedAngleBracketsInStyle() async throws {
        let repeatedAngles = String(repeating: "<", count: 8500)
        let quoteTail = "<blockquote type=\"cite\"><style>/* \(repeatedAngles) */</style><div>Fast quote</div></blockquote>"
        let html = "Reply<br>\(quoteTail)"

        let start = ContinuousClock.now
        let restored = try await prepare(html, format: .richTextHTML)
        let elapsed = ContinuousClock.now - start

        #expect(restored.attributedText.string == "Reply")
        #expect(restored.preservedQuotedHTML == quoteTail)
        #expect(elapsed < .seconds(2))
    }

    @Test("typing a > quote line above a preserved Gmail thread keeps both lines editable after save and reopen")
    func inlineGreaterThanQuoteLineStaysEditableAfterReopen() async throws {
        let gmailTail = """
        <div class="gmail_quote"><div dir="ltr" class="gmail_attr">On Mon, Alice wrote:<br></div>\
        <blockquote class="gmail_quote" style="margin:0;border-left:1px solid #ccc">Original thread</blockquote></div>
        """
        let initialHTML = "<div dir=\"ltr\">Draft start</div><br>\(gmailTail)"
        let firstOpen = try await prepare(initialHTML, format: .richTextHTML)

        let authoredReply = NSAttributedString(string: "> Friday works\nLet's book a room.")
        let serializedTop = ComposeRichTextHTMLSerializer.html(from: authoredReply)
        #expect(serializedTop.contains("<blockquote>Friday works</blockquote>"))

        let savedHTML = try #require(firstOpen.htmlBodyForSave(
            currentBodyText: authoredReply.string,
            currentBodyHTML: serializedTop,
            editedTopHTML: serializedTop
        ))
        #expect(savedHTML.hasSuffix("<br>\(gmailTail)"))

        let reopened = try await prepare(savedHTML, format: .richTextHTML)
        #expect(reopened.attributedText.string == "> Friday works\nLet's book a room.")
        #expect(reopened.preservedQuotedHTML == gmailTail)
    }

    @Test("reply text sharing a div with trailing attribution before a blockquote stays editable")
    func replyAndAttributionInSameDivDoesNotLockReplyText() async throws {
        let quoteTail = "<blockquote type=\"cite\">Original note</blockquote>"
        let html = "<div>Thanks, Friday works.<br>On Monday, Ada wrote:</div>\(quoteTail)"
        let restored = try await prepare(html, format: .richTextHTML)

        #expect(restored.attributedText.string.contains("Thanks, Friday works."))
        #expect(restored.preservedQuotedHTML == quoteTail)
        #expect(restored.preservedQuotedHTML?.contains("Thanks, Friday works.") == false)

        // A genuine 2-line wrapped standalone attribution without reply text still stays with the quote.
        let wrappedQuoteTail = "<div>On Mon, Jan 1, 2026 at 10:00 AM<br>Ada wrote:</div>\(quoteTail)"
        let wrappedHTML = "<div>Sounds good!</div>\(wrappedQuoteTail)"
        let wrappedRestored = try await prepare(wrappedHTML, format: .richTextHTML)
        #expect(wrappedRestored.attributedText.string == "Sounds good!")
        #expect(wrappedRestored.preservedQuotedHTML == wrappedQuoteTail)
    }

    @Test("compact HTML5 quoted tables and lists omitting optional closing tags reopen cleanly")
    func html5OptionalClosingTagsInsidePreservedQuotes() async throws {
        let compactTableQuote = """
        <div class="gmail_quote"><blockquote class="gmail_quote">\
        <table><thead><tr><th>Item<th>Qty<tbody><tr><td>Apples<td>3<tr><td>Oranges<td>5</table>\
        <ul><li>First item<li>Second item</ul>\
        <p>Paragraph one<p>Paragraph two\
        </blockquote></div>
        """
        let html = "<div dir=\"ltr\">Looks good!</div><br>\(compactTableQuote)"
        let restored = try await prepare(html, format: .richTextHTML)

        #expect(restored.attributedText.string == "Looks good!")
        #expect(restored.originalHTML == html)
        #expect(restored.preservedQuotedHTML == compactTableQuote)
        #expect(restored.preservedQuotedPlainText.contains("Apples"))
        #expect(restored.preservedQuotedPlainText.contains("Oranges"))
    }

    @Test("quoted plain text extraction respects > inside attribute values without leaking attribute markup")
    func quotedPlainTextIgnoresAngleBracketInsideAttributeValue() async throws {
        let quoteTail = "<blockquote data-label=\"a > b\" title='x > y'>Original reply</blockquote>"
        let html = "Top<br>\(quoteTail)"
        let restored = try await prepare(html, format: .richTextHTML)

        #expect(restored.preservedQuotedPlainText == "Original reply")
        #expect(!restored.preservedQuotedPlainText.contains("b\""))
        #expect(!restored.preservedQuotedPlainText.contains("y'"))
    }

    @Test("styled attribution before plain blockquote and uppercase </BLOCKQUOTE> reopen cleanly")
    func styledAttributionBeforePlainBlockquoteAndNoncanonicalCase() async throws {
        let attributedQuoteTail = "<div style=\"color:gray\">On Monday, Ada wrote:</div><blockquote>Original note</blockquote>"
        let attributedHTML = "Reply<br>\(attributedQuoteTail)"
        let attributedRestored = try await prepare(attributedHTML, format: .richTextHTML)

        #expect(attributedRestored.attributedText.string == "Reply")
        #expect(attributedRestored.originalHTML == attributedHTML)
        #expect(attributedRestored.preservedQuotedHTML == attributedQuoteTail)
        #expect(attributedRestored.quoteSeparatorHTML == "<br>")

        let uppercaseCloseHTML = "Reply<br><blockquote>Original</BLOCKQUOTE>"
        let uppercaseRestored = try await prepare(uppercaseCloseHTML, format: .richTextHTML)

        #expect(uppercaseRestored.attributedText.string == "Reply")
        #expect(uppercaseRestored.originalHTML == uppercaseCloseHTML)
        #expect(uppercaseRestored.preservedQuotedHTML == "<blockquote>Original</BLOCKQUOTE>")
    }

    @Test("nested optional HTML5 closing tags like <li><p>One<li><p>Two</ul> inside preserved quotes reopen cleanly")
    func nestedOptionalClosingTagsInsidePreservedQuotes() async throws {
        let nestedListQuote = "<blockquote type=\"cite\"><ul><li><p>One<li><p>Two</ul><table><tr><td><p>A<td><p>B</table></blockquote>"
        let html = "Looks good<br>\(nestedListQuote)"
        let restored = try await prepare(html, format: .richTextHTML)

        #expect(restored.attributedText.string == "Looks good")
        #expect(restored.originalHTML == html)
        #expect(restored.preservedQuotedHTML == nestedListQuote)
        #expect(restored.preservedQuotedPlainText.contains("One"))
        #expect(restored.preservedQuotedPlainText.contains("Two"))
    }

    @Test("dir=auto outer wrapper resolves quote-only preview direction from full document while saving dir=auto verbatim")
    func dirAutoResolvesQuotePreviewDirectionFromLeadingReply() async throws {
        let quoteTail = "<blockquote type=\"cite\">שלום</blockquote>"
        let html = "<div dir=\"auto\">Thanks<br>\(quoteTail)</div>"
        let restored = try await prepare(html, format: .richTextHTML)

        #expect(restored.attributedText.string == "Thanks")
        #expect(restored.inheritedDirection == "auto")
        #expect(restored.outerWrapperOpenHTML == "<div dir=\"auto\">")
        #expect(restored.outerWrapperCloseHTML == "</div>")

        let quotePreview = ComposeHTMLPreviewSource.sanitizedQuotePreviewHTML(
            quoteTail,
            inheritedDirection: restored.inheritedDirection,
            leadingContextText: restored.attributedText.string
        )
        #expect(quotePreview == "<div dir=\"ltr\">\(quoteTail)</div>")

        // When leading text is empty, dir="auto" falls through to the Hebrew quote -> "rtl".
        let quoteOnlyPreview = ComposeHTMLPreviewSource.sanitizedQuotePreviewHTML(
            quoteTail,
            inheritedDirection: "auto",
            leadingContextText: ""
        )
        #expect(quoteOnlyPreview == "<div dir=\"rtl\">\(quoteTail)</div>")

        // Saved HTML preserves dir="auto" verbatim.
        let edited = restored.htmlBodyForSave(
            currentBodyText: "Thanks updated",
            currentBodyHTML: "Thanks updated",
            editedTopHTML: "Thanks updated"
        )
        #expect(edited == "<div dir=\"auto\">Thanks updated<br>\(quoteTail)</div>")
    }

    @Test("attribution matching enforces word boundary and ranks provider-marked preludes ahead of inferred attributions")
    func attributionWordBoundaryAndProviderPreludePrecedence() async throws {
        let providerQuoteTail = "<div class=\"gmail_attr\">On Monday, Ada wrote:</div><blockquote>Original note</blockquote>"
        let html = "<div>I rewrote:</div><blockquote>Proposal A</blockquote><div>Does that work?</div>\(providerQuoteTail)"
        let restored = try await prepare(html, format: .richTextHTML)

        #expect(restored.attributedText.string.contains("I rewrote:"))
        #expect(restored.attributedText.string.contains("> Proposal A"))
        #expect(restored.attributedText.string.contains("Does that work?"))
        #expect(restored.preservedQuotedHTML == providerQuoteTail)
        #expect(restored.originalHTML == html)

        // Even when an earlier flat quote is preceded by an inferred attribution,
        // a later provider-marked prelude still wins as the preserved boundary.
        let inferredBeforeProviderHTML = "<div>On Sunday, Bob wrote:</div><blockquote>Inline excerpt</blockquote><div>Thoughts?</div>\(providerQuoteTail)"
        let ranked = try await prepare(inferredBeforeProviderHTML, format: .richTextHTML)

        #expect(ranked.attributedText.string.contains("Thoughts?"))
        #expect(ranked.preservedQuotedHTML == providerQuoteTail)

        // When a later provider-marked prelude leaves an earlier styled attribution
        // in the editable prefix, fall back to the earlier styled-attribution split
        // so both quotes stay byte-for-byte intact and the reply reopens editable.
        let styledThenProviderTail =
            "<div style=\"color:gray\">On Monday, Ada wrote:</div><blockquote>First note</blockquote>"
                + "<div class=\"gmail_attr\">On Sunday, Bob wrote:</div><blockquote>Older note</blockquote>"
        let styledThenProviderHTML = "Reply<br>\(styledThenProviderTail)"
        let fallbackRestored = try await prepare(styledThenProviderHTML, format: .richTextHTML)

        #expect(fallbackRestored.attributedText.string == "Reply")
        #expect(fallbackRestored.originalHTML == styledThenProviderHTML)
        #expect(fallbackRestored.preservedQuotedHTML == styledThenProviderTail)
        #expect(fallbackRestored.quoteSeparatorHTML == "<br>")

        // An intervening quote preceded by a standalone plain-text attribution node
        // is still part of the pure quote chain and falls back cleanly.
        let plainTextAttributedChainTail =
            "<div style=\"color:gray\">On Monday, Ada wrote:</div><blockquote>First note</blockquote>"
                + "On Tuesday, Bea wrote:<br><blockquote>Middle note</blockquote>"
                + "<div class=\"gmail_attr\">On Sunday, Bob wrote:</div><blockquote>Older note</blockquote>"
        let plainTextAttributedChainHTML = "Reply<br>\(plainTextAttributedChainTail)"
        let chainRestored = try await prepare(plainTextAttributedChainHTML, format: .richTextHTML)

        #expect(chainRestored.attributedText.string == "Reply")
        #expect(chainRestored.originalHTML == plainTextAttributedChainHTML)
        #expect(chainRestored.preservedQuotedHTML == plainTextAttributedChainTail)
        #expect(chainRestored.quoteSeparatorHTML == "<br>")

        // A text node containing reply text before an attribution line is not a
        // standalone attribution and must fail closed instead of locking the reply.
        let replyBeforePlainAttributionHTML =
            "<div style=\"color:gray\">On Monday, Ada wrote:</div><blockquote>First note</blockquote>"
                + "Thoughts?\nOn Tuesday, Bea wrote:<br><blockquote>Middle note</blockquote>"
                + "<div class=\"gmail_attr\">On Sunday, Bob wrote:</div><blockquote>Older note</blockquote>"
        await #expect(throws: (any Error).self) {
            _ = try await prepare(replyBeforePlainAttributionHTML, format: .richTextHTML)
        }

        // However, if standalone styled reply content sits between the earlier inline
        // quote and the later `.gmail_attr` boundary, fail closed rather than locking
        // the user's reply paragraph into read-only quoted history.
        let styledReplyBetweenQuotesHTML =
            "<div style=\"color:gray\">On Sunday, Bob wrote:</div><blockquote>inline excerpt</blockquote>"
                + "<div style=\"color:blue\">Thoughts?</div>"
                + "<div class=\"gmail_attr\">On Monday, Ada wrote:</div><blockquote>quoted thread</blockquote>"
        await #expect(throws: (any Error).self) {
            _ = try await prepare(styledReplyBetweenQuotesHTML, format: .richTextHTML)
        }
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
