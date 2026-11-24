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

/// Serializes an `NSAttributedString` (rich compose body) into clean semantic HTML
/// covering Brev's rich-compose allowlist:
/// `a` (http/https/mailto), `blockquote`, `br`, `code`, `div`, `em`, `h1`–`h3`,
/// `img` (`cid:` only), `li`, `ol`, `p`, `pre`, `s`, `strong`,
/// `table`/`thead`/`tbody`/`tr`/`th`/`td`, `u`, `ul`.
///
/// Shared by macOS and iOS native compose editors.
enum ComposeRichTextHTMLSerializer {
    private struct Paragraph {
        let range: NSRange
        let textList: NSTextList?
        let codeBlockID: String?
        let headingLevel: Int?
        let tableCell: ComposeTableCellMetadata?

        var isBlockElement: Bool {
            textList != nil || codeBlockID != nil || headingLevel != nil || tableCell != nil
        }
    }

    /// Converts an attributed string to semantic HTML.
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

        let paragraphs: [Paragraph] = paragraphRanges.map { range in
            classifyParagraph(range, in: attributedString)
        }

        var result = ""
        var index = 0
        var lastWasPlain = false
        while index < paragraphs.count {
            let para = paragraphs[index]

            if let cell = para.tableCell {
                var groupEnd = index + 1
                while groupEnd < paragraphs.count,
                      paragraphs[groupEnd].tableCell?.tableID == cell.tableID {
                    groupEnd += 1
                }
                result += serializeTable(
                    paragraphs: Array(paragraphs[index ..< groupEnd]),
                    in: attributedString
                )
                index = groupEnd
                lastWasPlain = false
            } else if let blockID = para.codeBlockID {
                var groupEnd = index + 1
                while groupEnd < paragraphs.count,
                      paragraphs[groupEnd].codeBlockID == blockID {
                    groupEnd += 1
                }
                result += serializeCodeBlock(
                    paragraphs: Array(paragraphs[index ..< groupEnd]),
                    in: attributedString
                )
                index = groupEnd
                lastWasPlain = false
            } else if let level = para.headingLevel, (1 ... 3).contains(level) {
                let innerHTML = runHTML(
                    for: para.range,
                    in: attributedString,
                    suppressBaseBold: true
                )
                result += "<h\(level)>\(innerHTML)</h\(level)>"
                index += 1
                lastWasPlain = false
            } else if let list = para.textList {
                let tag = listTag(for: list.markerFormat)
                result += "<\(tag)>"
                var groupIndex = index
                while groupIndex < paragraphs.count,
                      let groupList = paragraphs[groupIndex].textList,
                      paragraphs[groupIndex].tableCell == nil,
                      paragraphs[groupIndex].codeBlockID == nil,
                      paragraphs[groupIndex].headingLevel == nil,
                      groupList.markerFormat == list.markerFormat {
                    let innerHTML = runHTML(for: paragraphs[groupIndex].range, in: attributedString)
                    result += "<li>\(innerHTML)</li>"
                    groupIndex += 1
                }
                result += "</\(tag)>"
                index = groupIndex
                lastWasPlain = false
            } else {
                if lastWasPlain {
                    result += "<br>"
                }
                let innerHTML = runHTML(for: para.range, in: attributedString)
                result += innerHTML
                // Preserve an explicit empty line sitting directly before a block
                // element (e.g. `Intro\n\n<h1>Title</h1>`) across round-trips.
                if innerHTML.isEmpty,
                   lastWasPlain,
                   index + 1 < paragraphs.count,
                   paragraphs[index + 1].isBlockElement {
                    result += "<br>"
                }
                index += 1
                lastWasPlain = true
            }
        }

        return result
    }

    // MARK: - Block Classification & Serialization

    private static func classifyParagraph(
        _ range: NSRange,
        in attributedString: NSAttributedString
    ) -> Paragraph {
        guard range.length > 0 else {
            return Paragraph(range: range, textList: nil, codeBlockID: nil, headingLevel: nil, tableCell: nil)
        }
        let attrs = attributedString.attributes(at: range.location, effectiveRange: nil)

        if let explicitCell = attrs[ComposeRichTextAttribute.tableCell] as? ComposeTableCellMetadata {
            return Paragraph(
                range: range,
                textList: nil,
                codeBlockID: nil,
                headingLevel: nil,
                tableCell: explicitCell
            )
        }

        #if os(macOS)
        if let style = attrs[.paragraphStyle] as? NSParagraphStyle,
           let block = style.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first {
            let tableID = "nstexttable-\(ObjectIdentifier(block.table).hashValue)"
            let fallbackCell = ComposeTableCellMetadata(
                tableID: tableID,
                row: block.startingRow,
                column: block.startingColumn,
                isHeader: block.startingRow == 0 && isBold(attrs)
            )
            return Paragraph(
                range: range,
                textList: nil,
                codeBlockID: nil,
                headingLevel: nil,
                tableCell: fallbackCell
            )
        }
        #endif

        if let codeBlockID = attrs[ComposeRichTextAttribute.codeBlockID] as? String {
            return Paragraph(
                range: range,
                textList: nil,
                codeBlockID: codeBlockID,
                headingLevel: nil,
                tableCell: nil
            )
        }

        if let headingLevel = attrs[ComposeRichTextAttribute.headingLevel] as? Int,
           (1 ... 3).contains(headingLevel) {
            return Paragraph(
                range: range,
                textList: nil,
                codeBlockID: nil,
                headingLevel: headingLevel,
                tableCell: nil
            )
        }

        var textList: NSTextList?
        if let style = attrs[.paragraphStyle] as? NSParagraphStyle,
           let first = style.textLists.first {
            textList = first
        }
        return Paragraph(
            range: range,
            textList: textList,
            codeBlockID: nil,
            headingLevel: nil,
            tableCell: nil
        )
    }

    private static func serializeCodeBlock(
        paragraphs: [Paragraph],
        in attributedString: NSAttributedString
    ) -> String {
        let nsString = attributedString.string as NSString
        let lines: [String] = paragraphs.map { para in
            var effective = para.range
            if effective.length > 0 {
                let lastChar = nsString.substring(with: NSRange(location: effective.upperBound - 1, length: 1))
                if lastChar == "\n" {
                    effective = NSRange(location: effective.location, length: effective.length - 1)
                }
            }
            guard effective.length > 0 else { return "" }
            return escapedHTMLText(nsString.substring(with: effective))
        }
        return "<pre><code>\(lines.joined(separator: "\n"))</code></pre>"
    }

    private static func serializeTable(
        paragraphs: [Paragraph],
        in attributedString: NSAttributedString
    ) -> String {
        struct CellEntry {
            let row: Int
            let column: Int
            let isHeader: Bool
            let html: String
        }

        var rowsByIndex: [Int: [CellEntry]] = [:]
        for para in paragraphs {
            guard let meta = para.tableCell else { continue }
            let cellHTML = runHTML(
                for: para.range,
                in: attributedString,
                suppressBaseBold: meta.isHeader
            )
            let entry = CellEntry(
                row: meta.row,
                column: meta.column,
                isHeader: meta.isHeader,
                html: cellHTML
            )
            rowsByIndex[meta.row, default: []].append(entry)
        }

        let sortedRowKeys = rowsByIndex.keys.sorted()
        let orderedRows: [[CellEntry]] = sortedRowKeys.map { key in
            (rowsByIndex[key] ?? []).sorted { $0.column < $1.column }
        }
        let maxCols = orderedRows.map(\.count).max() ?? 0
        guard maxCols > 0 else { return "" }

        var headerRows: [[CellEntry]] = []
        var bodyRows: [[CellEntry]] = []
        var stillInHeader = true
        for row in orderedRows {
            if stillInHeader, !row.isEmpty, row.allSatisfy(\.isHeader) {
                headerRows.append(row)
            } else {
                stillInHeader = false
                bodyRows.append(row)
            }
        }

        var out = "<table>"
        if !headerRows.isEmpty {
            out += "<thead>"
            for row in headerRows {
                out += "<tr>"
                for col in 0 ..< maxCols {
                    let content = col < row.count ? row[col].html : ""
                    out += "<th>\(content)</th>"
                }
                out += "</tr>"
            }
            out += "</thead>"
        }
        if !bodyRows.isEmpty {
            out += "<tbody>"
            for row in bodyRows {
                out += "<tr>"
                for col in 0 ..< maxCols {
                    if col < row.count {
                        let tag = row[col].isHeader ? "th" : "td"
                        out += "<\(tag)>\(row[col].html)</\(tag)>"
                    } else {
                        out += "<td></td>"
                    }
                }
                out += "</tr>"
            }
            out += "</tbody>"
        }
        out += "</table>"
        return out
    }

    // MARK: - Inline Runs

    /// Generates inline HTML for all attribute runs within a paragraph range.
    private static func runHTML(
        for range: NSRange,
        in attributedString: NSAttributedString,
        suppressBaseBold: Bool = false
    ) -> String {
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
            html += wrapping(
                for: runRange,
                in: attributedString,
                attributes: attributes,
                suppressBaseBold: suppressBaseBold
            )
        }
        return html
    }

    /// Produces the HTML fragment for a single attribute run.
    private static func wrapping(
        for range: NSRange,
        in attributedString: NSAttributedString,
        attributes: [NSAttributedString.Key: Any],
        suppressBaseBold: Bool
    ) -> String {
        if let contentID = attributes[ComposeInlineImageAttribute.contentID] as? String {
            let altSuffix: String
            if let alt = attributes[ComposeInlineImageAttribute.alt] as? String, !alt.isEmpty {
                altSuffix = " alt=\"\(escapedAttribute(alt))\""
            } else {
                altSuffix = ""
            }
            return "<img src=\"cid:\(escapedAttribute(contentID))\"\(altSuffix)>"
        }

        let rawText = attributedString.attributedSubstring(from: range).string
        let isInlineCode = (attributes[ComposeRichTextAttribute.inlineCode] as? Bool) == true
        let textHTML = isInlineCode
            ? escapedHTMLText(rawText)
            : ComposeHTMLBodyPolicy.html(fromEditorText: rawText)
        guard !textHTML.isEmpty else { return "" }

        var wrapped = textHTML

        if isInlineCode {
            wrapped = "<code>\(wrapped)</code>"
        }

        if let link = attributes[.link] {
            let href: String
            if let url = link as? URL {
                href = url.absoluteString
            } else if let url = link as? NSURL, let s = url.absoluteString {
                href = s
            } else {
                href = String(describing: link)
            }
            if let safeHref = ComposeHTMLPasteSanitizer.sanitizedSafeHref(href) {
                wrapped = "<a href=\"\(escapedAttribute(safeHref))\">\(wrapped)</a>"
            }
        }
        if isStrikethrough(attributes) {
            wrapped = "<s>\(wrapped)</s>"
        }
        if isUnderlined(attributes) {
            wrapped = "<u>\(wrapped)</u>"
        }
        if isItalic(attributes) {
            wrapped = "<em>\(wrapped)</em>"
        }
        if !suppressBaseBold, isBold(attributes) {
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

    /// Whether the run carries a non-zero underline style.
    static func isUnderlined(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        guard let raw = attributes[.underlineStyle] else { return false }
        if let intValue = raw as? Int { return intValue != 0 }
        if let number = raw as? NSNumber { return number.intValue != 0 }
        return true
    }

    /// Whether the run carries a non-zero strikethrough style.
    static func isStrikethrough(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        guard let raw = attributes[.strikethroughStyle] else { return false }
        if let intValue = raw as? Int { return intValue != 0 }
        if let number = raw as? NSNumber { return number.intValue != 0 }
        return true
    }

    private static func listTag(for markerFormat: NSTextList.MarkerFormat) -> String {
        markerFormat == .decimal ? "ol" : "ul"
    }

    private static func escapedHTMLText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func escapedAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
