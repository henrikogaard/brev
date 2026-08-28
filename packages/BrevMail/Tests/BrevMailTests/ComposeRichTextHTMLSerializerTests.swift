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

#if os(macOS)
import AppKit
@testable import BrevMail
import Foundation
import Testing

@Suite("ComposeRichTextHTMLSerializer")
struct ComposeRichTextHTMLSerializerTests {
    @Test("bold/italic/underline still serialize")
    func basics() {
        let s = NSMutableAttributedString(string: "bolditalicunderline")
        s.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 12), range: NSRange(location: 0, length: 4))
        #expect(ComposeRichTextHTMLSerializer.html(from: s).contains("<strong>bold</strong>"))

        let italicFont = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 12), toHaveTrait: .italicFontMask)
        s.addAttribute(.font, value: italicFont, range: NSRange(location: 4, length: 6))
        #expect(ComposeRichTextHTMLSerializer.html(from: s).contains("<em>italic</em>"))

        s.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 10, length: 9))
        #expect(ComposeRichTextHTMLSerializer.html(from: s).contains("<u>underline</u>"))
    }

    @Test("bold run serializes to strong")
    func boldSerializes() {
        let s = NSMutableAttributedString(string: "Hello")
        s.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14), range: NSRange(location: 0, length: 5))
        let html = ComposeRichTextHTMLSerializer.html(from: s)
        #expect(html.contains("<strong>Hello</strong>"))
        #expect(ComposeRichTextHTMLSerializer.isBold([.font: NSFont.boldSystemFont(ofSize: 14)]))
        #expect(!ComposeRichTextHTMLSerializer.isBold([.font: NSFont.systemFont(ofSize: 14)]))
    }

    @Test("link serializes to a href")
    func link() {
        let s = NSMutableAttributedString(string: "site")
        s.addAttribute(.link, value: URL(string: "https://x.test")!, range: NSRange(location: 0, length: 4))
        #expect(ComposeRichTextHTMLSerializer.html(from: s).contains("<a href=\"https://x.test\">site</a>"))
    }

    @Test("bulleted list serializes to ul/li")
    func bulleted() {
        let html = ComposeRichTextHTMLSerializer.html(from: Self.list(marker: .disc, items: ["one", "two"]))
        #expect(html.contains("<ul>"))
        #expect(html.contains("<li>one</li>"))
        #expect(html.contains("<li>two</li>"))
        #expect(html.contains("</ul>"))
        #expect(html.contains("<ul><li>one</li><li>two</li></ul>"))
    }

    @Test("numbered list serializes to ol/li")
    func numbered() {
        let html = ComposeRichTextHTMLSerializer.html(from: Self.list(marker: .decimal, items: ["a"]))
        #expect(html.contains("<ol>"))
        #expect(html.contains("<li>a</li>"))
    }

    @Test("single word does not duplicate")
    func noDuplication() {
        let s = NSAttributedString(string: "Hello")
        #expect(ComposeRichTextHTMLSerializer.html(from: s) == "Hello")
    }

    @Test("multi-paragraph text round-trips with br separators")
    func multiParagraphLineBreaks() {
        let s = NSAttributedString(string: "Line 1\nLine 2\n\nLine 4")
        #expect(ComposeRichTextHTMLSerializer.html(from: s) == "Line 1<br>Line 2<br><br>Line 4")
    }

    @Test("list followed by paragraph does not duplicate trailing paragraph")
    func listFollowedByParagraph() {
        let listPart = Self.list(marker: .disc, items: ["item"])
        let out = NSMutableAttributedString(attributedString: listPart)
        out.append(NSAttributedString(string: "after"))
        let html = ComposeRichTextHTMLSerializer.html(from: out)
        #expect(html.contains("<ul><li>item</li></ul>"))
        #expect(html.hasSuffix("after"))
    }

    @Test("tagged image attachment serializes to img cid")
    func image() {
        let att = NSTextAttachment(); att.image = NSImage(size: .init(width: 1, height: 1))
        let s = NSMutableAttributedString(attributedString: NSAttributedString(attachment: att))
        s.addAttribute(ComposeInlineImageAttribute.contentID, value: "c@brev",
                       range: NSRange(location: 0, length: s.length))
        #expect(ComposeRichTextHTMLSerializer.html(from: s).contains("<img src=\"cid:c@brev\">"))
    }

    private static func list(marker: NSTextList.MarkerFormat, items: [String]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let style = NSMutableParagraphStyle()
        style.textLists = [NSTextList(markerFormat: marker, options: 0)]
        for item in items {
            let para = NSMutableAttributedString(string: item + "\n")
            para.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: para.length))
            out.append(para)
        }
        return out
    }
}
#endif
