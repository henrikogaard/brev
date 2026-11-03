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

import AppKit
import BrevBackend
@testable import BrevMail
import Foundation
import Testing

/// ADR-0093: which saved bodies reopen, and what the editor receives.
@MainActor
@Suite("Compose draft reopening")
struct ComposeDraftReopeningTests {
    private static let quoteText = "Thanks!\n\nOn Jan 1, Ada <ada@example.org> wrote:\n> first\n> second"

    @Test("Brev's plain reply body reopens with quote lines", arguments: [ComposeBodyFormat.plainText, .richTextHTML])
    func plainReplyBody(format: ComposeBodyFormat) async throws {
        let html = ComposeHTMLBodyPolicy.html(fromEditorText: Self.quoteText)
        let body = try await prepare(html, inReplyTo: "<reply@example.org>", format: format)
        #expect(body.attributedText.string == Self.quoteText)
        #expect(body.originalHTML == html)
    }

    @Test("Brev's rich reply body reopens with quote lines")
    func richReplyBody() async throws {
        let html = ComposeRichTextHTMLSerializer.html(from: NSAttributedString(string: Self.quoteText))
        let body = try await prepare(html, inReplyTo: "<reply@example.org>", format: .richTextHTML)
        #expect(body.attributedText.string == Self.quoteText)
        #expect(body.originalHTML == html)
        #expect(body.initialEditorHTML == html)
    }

    @Test("a forward with emphasis above its quote keeps both")
    func forwardKeepsEmphasis() async throws {
        let html = "<strong>Note</strong><br>---------- Forwarded message ---------<br><blockquote>first</blockquote>"
        let body = try await prepare(html, forwarded: "<forward@example.org>", format: .richTextHTML)
        #expect(body.attributedText.string == "Note\n---------- Forwarded message ---------\n> first")
        #expect(ComposeRichTextHTMLSerializer.html(from: body.attributedText).contains("<strong>Note</strong>"))
    }

    @Test("p and div reopen as line structure", arguments: [
        ("<div dir=\"ltr\">One</div><div>Two</div>", "One\nTwo"),
        ("<div>One</div><div><br></div><div>Two</div>", "One\n\nTwo"),
        ("<p>One</p><p>Two</p>", "One\nTwo"),
        ("Lead<div>One</div>", "Lead\nOne"),
        ("<div><strong>One</strong> two</div>", "One two")
    ])
    func lineStructure(html: String, expected: String) async throws {
        let body = try await prepare(html, format: .richTextHTML)
        #expect(body.attributedText.string == expected)
        #expect(body.originalHTML == html)
    }

    @Test("markup outside the accepted subset stays refused", arguments: [
        "<blockquote style=\"color:red\">first</blockquote>",
        "<blockquote><blockquote>first</blockquote></blockquote>",
        "<blockquote><strong>first</strong></blockquote>",
        "<blockquote>first",
        "<div class=\"gmail_quote\">first</div>",
        "<div dir=\"ltr\" style=\"color:red\">first</div>",
        "<div><div>first</div></div>",
        "<p>One<div>Two</div></p>",
        "<ul><li>first</li></ul>",
        "<img src=\"cid:one\">"
    ])
    func refused(html: String) async {
        await #expect(throws: (any Error).self) {
            _ = try await prepare(html, format: .richTextHTML)
        }
    }

    private func prepare(
        _ html: String,
        inReplyTo: String? = nil,
        forwarded: String? = nil,
        format: ComposeBodyFormat
    ) async throws -> ComposeRestoredBody {
        try await ComposeDraftBodyRestoration.prepare(
            draft: Draft(id: "draft", inReplyToMessageID: inReplyTo, forwardedMessageID: forwarded, htmlBody: html),
            format: format
        )
    }
}
