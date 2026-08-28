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

import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Serializes an `NSAttributedString` (rich compose body) into HTML constrained to the
/// ADR-0038 allowlist: `a, blockquote, br, div, em, img (cid: only), li, ol, p, strong, u, ul`.
///
/// Shared by macOS and iOS native compose editors.
enum ComposeRichTextHTMLSerializer {
    /// Converts an attributed string to HTML.
    ///
    /// Paragraphs separated by `\n` are processed individually. Consecutive paragraphs that
    /// share the same `NSTextList` marker are grouped into `<ul>` or `<ol>` blocks. All other
    /// paragraphs keep their run-level formatting (bold, italic, underline, link, image).
    static func html(from attributedString: NSAttributedString) -> String {
        guard attributedString.length > 0 else { return "" }

        var paragraphRanges: [NSRange] = []
        let nsString = attributedString.string as NSString
        var searchStart = 0
        while searchStart < attributedString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: searchStart, length: 0))
            paragraphRanges.append(lineRange)
            let nextStart = lineRange.upperBound
            if nextStart <= searchStart {
                break
            }
            searchStart = nextStart
        }

        struct Paragraph {
            let range: NSRange
            let textList: NSTextList?
        }
        let paragraphs: [Paragraph] = paragraphRanges.map { range in
            guard range.length > 0 else { return Paragraph(range: range, textList: nil) }
            var textList: NSTextList?
            if let style = attributedString.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
                as? NSParagraphStyle,
                let first = style.textLists.first {
                textList = first
            }
            return Paragraph(range: range, textList: textList)
        }

        var result = ""
        var index = 0
        var lastWasNonList = false
        while index < paragraphs.count {
            let para = paragraphs[index]

            if let list = para.textList {
                let tag = listTag(for: list.markerFormat)
                result += "<\(tag)>"
                var groupIndex = index
                while groupIndex < paragraphs.count,
                      let groupList = paragraphs[groupIndex].textList,
                      groupList.markerFormat == list.markerFormat {
                    let innerHTML = runHTML(for: paragraphs[groupIndex].range, in: attributedString)
                    result += "<li>\(innerHTML)</li>"
                    groupIndex += 1
                }
                result += "</\(tag)>"
                index = groupIndex
                lastWasNonList = false
            } else {
                if lastWasNonList {
                    result += "<br>"
                }
                let innerHTML = runHTML(for: para.range, in: attributedString)
                result += innerHTML
                index += 1
                lastWasNonList = true
            }
        }

        return result
    }

    /// Generates inline HTML for all attribute runs within a paragraph range.
    private static func runHTML(for range: NSRange, in attributedString: NSAttributedString) -> String {
        guard range.length > 0 else { return "" }

        let nsString = attributedString.string as NSString
        var effectiveRange = range
        let lastCharRange = NSRange(location: effectiveRange.upperBound - 1, length: 1)
        if nsString.substring(with: lastCharRange) == "\n" {
            effectiveRange = NSRange(location: effectiveRange.location, length: effectiveRange.length - 1)
        }
        guard effectiveRange.length > 0 else { return "" }

        var html = ""
        attributedString.enumerateAttributes(in: effectiveRange) { attributes, runRange, _ in
            html += wrapping(for: runRange, in: attributedString, attributes: attributes)
        }
        return html
    }

    /// Produces the HTML fragment for a single attribute run.
    private static func wrapping(
        for range: NSRange,
        in attributedString: NSAttributedString,
        attributes: [NSAttributedString.Key: Any]
    ) -> String {
        if let contentID = attributes[ComposeInlineImageAttribute.contentID] as? String {
            return "<img src=\"cid:\(escapedAttribute(contentID))\">"
        }

        let rawText = attributedString.attributedSubstring(from: range).string
        let textHTML = ComposeHTMLBodyPolicy.html(fromEditorText: rawText)
        guard !textHTML.isEmpty else { return "" }

        var wrapped = textHTML

        if let link = attributes[.link] {
            let href: String
            if let url = link as? URL {
                href = url.absoluteString
            } else if let url = link as? NSURL, let s = url.absoluteString {
                href = s
            } else {
                href = String(describing: link)
            }
            wrapped = "<a href=\"\(escapedAttribute(href))\">\(wrapped)</a>"
        }
        if attributes[.underlineStyle] != nil {
            wrapped = "<u>\(wrapped)</u>"
        }
        if isItalic(attributes) {
            wrapped = "<em>\(wrapped)</em>"
        }
        if isBold(attributes) {
            wrapped = "<strong>\(wrapped)</strong>"
        }
        return wrapped
    }

    /// Whether the run's font carries a bold trait (AppKit or UIKit).
    static func isBold(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        #if os(macOS)
        guard let font = attributes[.font] as? NSFont else { return false }
        return NSFontManager.shared.traits(of: font).contains(.boldFontMask)
        #else
        guard let font = attributes[.font] as? UIFont else { return false }
        return font.fontDescriptor.symbolicTraits.contains(.traitBold)
        #endif
    }

    /// Whether the run's font carries an italic trait (AppKit or UIKit).
    static func isItalic(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        #if os(macOS)
        guard let font = attributes[.font] as? NSFont else { return false }
        return NSFontManager.shared.traits(of: font).contains(.italicFontMask)
        #else
        guard let font = attributes[.font] as? UIFont else { return false }
        return font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        #endif
    }

    private static func listTag(for markerFormat: NSTextList.MarkerFormat) -> String {
        markerFormat == .decimal ? "ol" : "ul"
    }

    private static func escapedAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
