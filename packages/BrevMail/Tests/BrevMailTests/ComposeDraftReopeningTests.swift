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
#if os(macOS)
import AppKit
#else
import UIKit
#endif
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
        "<ul><li>first<ul><li>nested</li></ul></li></ul>",
        "<ul><li>first</li>loose</ul>",
        "<ul class=\"x\"><li>first</li></ul>",
        "<li>first</li>",
        "<ul><li>first</li>",
        "<blockquote><ul><li>first</li></ul></blockquote>",
        "<ul><li><div>first</div></li></ul>",
        "<img src=\"cid:one\">"
    ])
    func refused(html: String) async {
        await #expect(throws: (any Error).self) {
            _ = try await prepare(html, format: .richTextHTML)
        }
    }

    @Test("lists the editor made reopen as the same list lines", arguments: [
        ["Intro", "• one", "• two", "Outro"],
        ["1. one", "1. two", "• three"],
        ["• only"]
    ])
    func editorLists(lines: [String]) async throws {
        let authored = Self.listBody(lines)
        let html = ComposeRichTextHTMLSerializer.html(from: authored)
        let body = try await prepare(html, format: .richTextHTML)
        #expect(body.attributedText.string == authored.string)
        #expect(Self.markers(body.attributedText) == Self.markers(authored))
        #expect(body.initialEditorHTML == html)
        #expect(body.originalHTML == html)
    }

    @Test("emphasis and links inside list items survive reopening")
    func listItemFormatting() async throws {
        let html = "<ul><li><strong>Bold</strong> item</li><li><a href=\"https://example.invalid/\">Link</a></li></ul>"
        let body = try await prepare(html, format: .richTextHTML)
        #expect(body.attributedText.string == "Bold item\nLink")
        let editorHTML = body.initialEditorHTML
        #expect(editorHTML.hasPrefix("<ul><li><strong>Bold</strong> item</li><li>"))
        #expect(editorHTML.contains("<a href=\"https://example.invalid/\">Link</a>"))
        #expect(body.originalHTML == html)
    }

    @Test("a list cannot reopen in the plain-text editor")
    func listNeedsRichText() async {
        await #expect(throws: (any Error).self) {
            _ = try await prepare("<ul><li>first</li></ul>", format: .plainText)
        }
    }

    /// Builds lines the way the editor's list commands do: "• " marks a
    /// bulleted line, "1. " a numbered one.
    private static func listBody(_ lines: [String]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            var text = line
            var format: NSTextList.MarkerFormat?
            if line.hasPrefix("• ") { format = .disc; text = String(line.dropFirst(2)) }
            if line.hasPrefix("1. ") { format = .decimal; text = String(line.dropFirst(3)) }
            let style = NSMutableParagraphStyle()
            if let format {
                style.textLists = [NSTextList(markerFormat: format, options: 0)]
                style.headIndent = 24
                style.firstLineHeadIndent = 8
            }
            let suffix = index < lines.count - 1 ? "\n" : ""
            result.append(NSAttributedString(string: text + suffix, attributes: [.paragraphStyle: style]))
        }
        return result
    }

    private static func markers(_ text: NSAttributedString) -> [String] {
        let string = text.string as NSString
        var result: [String] = []
        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length),
            options: .byParagraphs
        ) { _, range, _, _ in
            let location = min(range.location, max(text.length - 1, 0))
            let style = text.length == 0 ? nil
                : text.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            result.append(style?.textLists.first?.markerFormat.rawValue ?? "-")
        }
        return result
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
