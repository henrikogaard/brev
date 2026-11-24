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
import BrevDesign
import BrevThemes
import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Pure, zero-WebKit, zero-network parser that converts Brev's supported rich
/// HTML subset directly into an `NSAttributedString` for compose draft
/// restoration and sanitized paste insertion.
///
/// Supports:
/// - Inline formatting: `strong`/`b`, `em`/`i`, `u`, `s`/`del`/`strike`,
///   safe `<a href="http|https|mailto">`, inline `<code>`, `<img src="cid:…">`
/// - Block formatting: `<p>`, `<div>` (with optional `dir`), `<br>`,
///   `<h1>`–`<h3>`, `<ul>`/`<ol>`/`<li>`, flat `<blockquote>`,
///   `<pre><code>…</code></pre>`, and semantic `<table>`/`<thead>`/`<tbody>`/
///   `<tr>`/`<th>`/`<td>`.
enum ComposeRichHTMLAttributedBuilder {
    #if os(macOS)
    typealias PlatformFont = NSFont
    typealias PlatformColor = NSColor
    #else
    typealias PlatformFont = UIFont
    typealias PlatformColor = UIColor
    #endif

    /// Visual styling parameters used while building editor-ready attributed strings.
    struct Style {
        let baseFont: PlatformFont
        let monospacedFont: PlatformFont
        let textColor: PlatformColor
        let borderColor: PlatformColor
        let surfaceSecondaryColor: PlatformColor
        let maxImageWidth: CGFloat

        static func `default`(
            fontFamily: MailboxFontFamily = .system,
            textSize: MailboxTextSize = .medium,
            theme: BrevTheme = .brevMonoLight,
            maxImageWidth: CGFloat = 520
        ) -> Style {
            #if os(macOS)
            let base = ComposeEditorTypography.nsFont(family: fontFamily, textSize: textSize)
            let mono = ComposeEditorTypography.monospacedNSFont(textSize: textSize)
            let textColor = NSColor(theme.textPrimary.color)
            let borderColor = NSColor(theme.border.color)
            let secondaryColor = NSColor(theme.bgSecondary.color)
            #else
            let base = ComposeEditorTypography.uiFont(family: fontFamily, textSize: textSize)
            let mono = ComposeEditorTypography.monospacedUIFont(textSize: textSize)
            let textColor = UIColor(theme.textPrimary.color)
            let borderColor = UIColor(theme.border.color)
            let secondaryColor = UIColor(theme.bgSecondary.color)
            #endif
            return Style(
                baseFont: base,
                monospacedFont: mono,
                textColor: textColor,
                borderColor: borderColor,
                surfaceSecondaryColor: secondaryColor,
                maxImageWidth: maxImageWidth
            )
        }
    }

    private struct InlineState {
        var isBold = false
        var isItalic = false
        var isUnderline = false
        var isStrikethrough = false
        var isInlineCode = false
        var linkURL: URL?
        var headingLevel: Int?
    }

    private struct ParsedTag {
        let name: String
        let isClosing: Bool
        let isSelfClosing: Bool
        let attributes: [(name: String, value: String)]
    }

    private enum Token {
        case text(String)
        case open(ParsedTag)
        case close(String)
    }

    private final class Node {
        let tag: String?
        let attributes: [(name: String, value: String)]
        let text: String?
        var children: [Node] = []

        init(tag: String?, attributes: [(name: String, value: String)] = []) {
            self.tag = tag
            self.attributes = attributes
            text = nil
        }

        init(text: String) {
            tag = nil
            attributes = []
            self.text = text
        }

        func attributeValue(_ name: String) -> String? {
            attributes.first { $0.name == name }?.value
        }
    }

    private static let voidTags: Set<String> = ["br", "img"]

    /// Builds an `NSAttributedString` from `html`.
    ///
    /// - Parameters:
    ///   - html: Canonical or draft HTML body fragment.
    ///   - inlineAttachments: Local inline attachments keyed by normalized Content-ID.
    ///   - style: Editor typography and theme colors.
    ///   - strict: When `true` (draft restoration), fails closed (`nil`) on any
    ///     unbalanced tag, unsupported element/attribute, nested block, or unbacked `cid:`.
    static func attributedString(
        from html: String,
        inlineAttachments: [String: MIMEMessageAttachment] = [:],
        style: Style = .default(),
        strict: Bool
    ) -> NSAttributedString? {
        guard html.utf8.count <= 1_048_576 else { return nil }
        if html.isEmpty {
            return NSAttributedString(string: "")
        }

        let normalizedHTML = html
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard let tokens = tokenize(normalizedHTML, strict: strict),
              let root = buildTree(from: tokens, strict: strict) else {
            return nil
        }

        let output = NSMutableAttributedString()
        guard emitTopLevelChildren(
            root.children,
            into: output,
            inlineAttachments: inlineAttachments,
            style: style,
            strict: strict
        ) else {
            return nil
        }
        return output
    }

    /// Builds a semantic table `NSAttributedString` ready for direct insertion
    /// into the compose editor.
    static func makeTableAttributedString(
        headers: [String],
        rows: [[String]],
        tableID: String = UUID().uuidString,
        style: Style = .default()
    ) -> NSAttributedString {
        let columnCount = max(headers.count, rows.map(\.count).max() ?? 0)
        guard columnCount > 0 else { return NSAttributedString(string: "") }

        let allRows: [(isHeader: Bool, cells: [String])] = {
            var list: [(isHeader: Bool, cells: [String])] = []
            if !headers.isEmpty {
                list.append((isHeader: true, cells: padded(headers, to: columnCount)))
            }
            for row in rows {
                list.append((isHeader: false, cells: padded(row, to: columnCount)))
            }
            return list
        }()

        let output = NSMutableAttributedString()
        #if os(macOS)
        let textTable = NSTextTable()
        textTable.numberOfColumns = columnCount
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        #endif

        for (rowIndex, row) in allRows.enumerated() {
            for (colIndex, cellText) in row.cells.enumerated() {
                let isLastCell = rowIndex == allRows.count - 1 && colIndex == row.cells.count - 1
                let metadata = ComposeTableCellMetadata(
                    tableID: tableID,
                    row: rowIndex,
                    column: colIndex,
                    isHeader: row.isHeader
                )
                let paragraphStyle = makeTableCellParagraphStyle(
                    row: rowIndex,
                    column: colIndex,
                    columnCount: columnCount,
                    isHeader: row.isHeader,
                    style: style
                )
                #if os(macOS)
                attachMacTableBlock(
                    to: paragraphStyle,
                    table: textTable,
                    row: rowIndex,
                    column: colIndex,
                    columnCount: columnCount,
                    isHeader: row.isHeader,
                    style: style
                )
                #endif

                let font = resolvedFont(
                    for: InlineState(isBold: row.isHeader),
                    style: style
                )
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: style.textColor,
                    .paragraphStyle: paragraphStyle,
                    ComposeRichTextAttribute.tableCell: metadata
                ]
                if row.isHeader {
                    attrs[.font] = font
                }
                let text = isLastCell ? cellText : (cellText + "\n")
                if text.isEmpty {
                    output.append(NSAttributedString(string: "\n", attributes: attrs))
                } else {
                    output.append(NSAttributedString(string: text, attributes: attrs))
                }
            }
        }
        return output
    }

    // MARK: - Tokenizer

    private static func tokenize(_ html: String, strict: Bool) -> [Token]? {
        var tokens: [Token] = []
        var cursor = html.startIndex
        let end = html.endIndex

        while cursor < end {
            guard let lt = html[cursor ..< end].firstIndex(of: "<") else {
                tokens.append(.text(String(html[cursor ..< end])))
                break
            }
            if cursor < lt {
                tokens.append(.text(String(html[cursor ..< lt])))
            }

            let remaining = html[lt ..< end]
            if remaining.hasPrefix("<!--") || remaining.hasPrefix("<!") || remaining.hasPrefix("<?") {
                return nil
            }

            let afterLT = html.index(after: lt)
            guard afterLT < end else { return nil }
            let nextChar = html[afterLT]
            guard nextChar == "/" || (nextChar.isASCII && nextChar.isLetter) else {
                if strict { return nil }
                tokens.append(.text("<"))
                cursor = afterLT
                continue
            }

            guard let gt = findTagClose(in: html, from: lt, limit: end) else {
                return nil
            }
            let nextIndex = html.index(after: gt)
            guard let parsed = parseTag(html[lt ..< nextIndex], strict: strict) else {
                return nil
            }
            if parsed.isClosing {
                tokens.append(.close(parsed.name))
            } else {
                tokens.append(.open(parsed))
            }
            cursor = nextIndex
        }
        return tokens
    }

    private static func findTagClose(
        in html: String,
        from start: String.Index,
        limit: String.Index
    ) -> String.Index? {
        var idx = html.index(after: start)
        var quote: Character?
        while idx < limit {
            let ch = html[idx]
            if let activeQuote = quote {
                if ch == activeQuote { quote = nil }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == ">" {
                return idx
            }
            idx = html.index(after: idx)
        }
        return nil
    }

    private static func parseTag(_ raw: Substring, strict: Bool) -> ParsedTag? {
        guard raw.count >= 3, raw.first == "<", raw.last == ">" else { return nil }
        var inner = raw.dropFirst().dropLast()
        var idx = inner.startIndex
        while idx < inner.endIndex, inner[idx].isWhitespace {
            idx = inner.index(after: idx)
        }
        guard idx < inner.endIndex else { return nil }

        let isClosing: Bool
        if inner[idx] == "/" {
            isClosing = true
            idx = inner.index(after: idx)
            while idx < inner.endIndex, inner[idx].isWhitespace {
                idx = inner.index(after: idx)
            }
        } else {
            isClosing = false
        }

        let nameStart = idx
        while idx < inner.endIndex,
              let ascii = inner[idx].asciiValue,
              (ascii >= 65 && ascii <= 90)
              || (ascii >= 97 && ascii <= 122)
              || (ascii >= 48 && ascii <= 57) {
            idx = inner.index(after: idx)
        }
        guard nameStart < idx else { return nil }
        let rawName = String(inner[nameStart ..< idx])
        let name = rawName.lowercased()
        if strict, rawName != name {
            // Preserve PR #350 invariant: noncanonical casing like `</BLOCKQUOTE>`
            // triggers quote-preservation rather than flat import.
            return nil
        }

        inner = inner[idx...]
        var trimmedTail = inner
        while let last = trimmedTail.last, last.isWhitespace {
            trimmedTail = trimmedTail.dropLast()
        }
        let explicitSelfClosing: Bool
        if !isClosing, trimmedTail.last == "/" {
            explicitSelfClosing = true
            trimmedTail = trimmedTail.dropLast()
        } else {
            explicitSelfClosing = false
        }

        if isClosing {
            guard trimmedTail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return ParsedTag(name: name, isClosing: true, isSelfClosing: false, attributes: [])
        }

        guard let attributes = parseAttributes(trimmedTail, strict: strict) else {
            return nil
        }
        let isSelfClosing = explicitSelfClosing || voidTags.contains(name)
        return ParsedTag(
            name: name,
            isClosing: false,
            isSelfClosing: isSelfClosing,
            attributes: attributes
        )
    }

    private static func parseAttributes(
        _ slice: Substring,
        strict: Bool
    ) -> [(name: String, value: String)]? {
        var attributes: [(name: String, value: String)] = []
        var idx = slice.startIndex
        let end = slice.endIndex

        while idx < end {
            while idx < end, slice[idx].isWhitespace {
                idx = slice.index(after: idx)
            }
            guard idx < end else { break }

            let nameStart = idx
            while idx < end,
                  let ascii = slice[idx].asciiValue,
                  (ascii >= 65 && ascii <= 90)
                  || (ascii >= 97 && ascii <= 122)
                  || (ascii >= 48 && ascii <= 57)
                  || ascii == 45 {
                idx = slice.index(after: idx)
            }
            guard nameStart < idx else { return nil }
            let attrName = String(slice[nameStart ..< idx]).lowercased()

            while idx < end, slice[idx].isWhitespace {
                idx = slice.index(after: idx)
            }
            guard idx < end, slice[idx] == "=" else {
                if strict { return nil }
                continue
            }
            idx = slice.index(after: idx)
            while idx < end, slice[idx].isWhitespace {
                idx = slice.index(after: idx)
            }
            guard idx < end else { return nil }

            let value: String
            if slice[idx] == "\"" || slice[idx] == "'" {
                let quote = slice[idx]
                idx = slice.index(after: idx)
                let valStart = idx
                while idx < end, slice[idx] != quote {
                    idx = slice.index(after: idx)
                }
                guard idx < end else { return nil }
                value = String(slice[valStart ..< idx])
                idx = slice.index(after: idx)
            } else {
                let valStart = idx
                while idx < end, !slice[idx].isWhitespace {
                    idx = slice.index(after: idx)
                }
                value = String(slice[valStart ..< idx])
            }
            attributes.append((name: attrName, value: value))
        }
        return attributes
    }

    // MARK: - Strict Tree Builder

    private static func buildTree(from tokens: [Token], strict: Bool) -> Node? {
        let root = Node(tag: nil)
        var stack: [Node] = [root]

        for token in tokens {
            switch token {
            case .text(let value):
                stack.last?.children.append(Node(text: value))
            case .open(let tag):
                if strict, !isAllowedTag(tag) {
                    return nil
                }
                let node = Node(tag: tag.name, attributes: tag.attributes)
                stack.last?.children.append(node)
                if !tag.isSelfClosing {
                    stack.append(node)
                }
            case .close(let name):
                guard let top = stack.last, top.tag == name, stack.count > 1 else {
                    return nil
                }
                stack.removeLast()
            }
        }
        guard stack.count == 1 else { return nil }
        return root
    }

    private static func isAllowedTag(_ tag: ParsedTag) -> Bool {
        switch tag.name {
        case "p", "div":
            return tag.attributes.allSatisfy { attr in
                attr.name == "dir" && ["ltr", "rtl", "auto"].contains(attr.value.lowercased())
            }
        case "a":
            guard tag.attributes.allSatisfy({ $0.name == "href" }) else { return false }
            if let href = tag.attributes.first?.value {
                return ComposeHTMLPasteSanitizer.sanitizedSafeHref(href) != nil
            }
            return true
        case "img":
            guard tag.attributes.allSatisfy({ $0.name == "src" || $0.name == "alt" }),
                  let src = tag.attributes.first(where: { $0.name == "src" })?.value else {
                return false
            }
            return ComposeHTMLPasteSanitizer.decodeHTMLEntities(src)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .hasPrefix("cid:")
        case "br", "strong", "b", "em", "i", "u", "s", "del", "strike",
             "code", "pre", "h1", "h2", "h3", "ul", "ol", "li",
             "blockquote", "table", "thead", "tbody", "tr", "th", "td":
            return tag.attributes.isEmpty
        default:
            return false
        }
    }

    // MARK: - Emission

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func emitTopLevelChildren(
        _ nodes: [Node],
        into output: NSMutableAttributedString,
        inlineAttachments: [String: MIMEMessageAttachment],
        style: Style,
        strict: Bool
    ) -> Bool {
        var didEmitAny = false
        var lastEndedWithNewline = false

        func ensureLineBreakBeforeBlock() {
            guard didEmitAny, !lastEndedWithNewline else { return }
            appendPlain("\n", to: output, style: style)
            lastEndedWithNewline = true
        }

        for (index, node) in nodes.enumerated() {
            let hasMore = index < nodes.count - 1
            let nextIsBreak = hasMore && nodes[index + 1].tag == "br"
            let needsBlockTrailingNewline = hasMore && !nextIsBreak
            if let text = node.text {
                if text.isEmpty { continue }
                let decoded = ComposeHTMLPasteSanitizer.decodeHTMLEntities(text)
                if decoded.isEmpty { continue }
                appendInlineText(decoded, state: InlineState(), to: output, style: style)
                didEmitAny = true
                lastEndedWithNewline = decoded.hasSuffix("\n")
                continue
            }

            guard let tag = node.tag else { return false }
            switch tag {
            case "br":
                appendPlain("\n", to: output, style: style)
                didEmitAny = true
                lastEndedWithNewline = true

            case "p", "div":
                ensureLineBreakBeforeBlock()
                let beforeLength = output.length
                if node.children.count == 1, node.children[0].tag == "br" {
                    // Empty block divider such as `<div><br></div>`.
                    if needsBlockTrailingNewline {
                        appendPlain("\n", to: output, style: style)
                        lastEndedWithNewline = true
                    } else {
                        lastEndedWithNewline = false
                    }
                    didEmitAny = true
                    continue
                }
                guard emitInlineChildren(
                    node.children,
                    state: InlineState(),
                    into: output,
                    inlineAttachments: inlineAttachments,
                    style: style,
                    strict: strict
                ) else {
                    return false
                }
                didEmitAny = true
                let producedContent = output.length > beforeLength
                if needsBlockTrailingNewline {
                    if !producedContent || !output.string.hasSuffix("\n") {
                        appendPlain("\n", to: output, style: style)
                    }
                    lastEndedWithNewline = true
                } else {
                    lastEndedWithNewline = producedContent && output.string.hasSuffix("\n")
                }

            case "h1", "h2", "h3":
                ensureLineBreakBeforeBlock()
                let level = tag == "h1" ? 1 : (tag == "h2" ? 2 : 3)
                var headingState = InlineState()
                headingState.headingLevel = level
                headingState.isBold = true
                let start = output.length
                guard emitInlineChildren(
                    node.children,
                    state: headingState,
                    into: output,
                    inlineAttachments: inlineAttachments,
                    style: style,
                    strict: strict
                ) else {
                    return false
                }
                if output.length == start {
                    // Empty heading needs a carrier character if followed by more blocks.
                    if needsBlockTrailingNewline {
                        appendInlineText("\n", state: headingState, to: output, style: style)
                        lastEndedWithNewline = true
                    } else {
                        lastEndedWithNewline = false
                    }
                } else {
                    if needsBlockTrailingNewline {
                        appendInlineText("\n", state: headingState, to: output, style: style)
                        lastEndedWithNewline = true
                    } else {
                        lastEndedWithNewline = false
                    }
                }
                didEmitAny = true

            case "ul", "ol":
                ensureLineBreakBeforeBlock()
                let marker: NSTextList.MarkerFormat = tag == "ol" ? .decimal : .disc
                guard emitList(
                    node,
                    marker: marker,
                    hasTrailingSibling: needsBlockTrailingNewline,
                    into: output,
                    inlineAttachments: inlineAttachments,
                    style: style,
                    strict: strict
                ) else {
                    return false
                }
                didEmitAny = true
                lastEndedWithNewline = needsBlockTrailingNewline

            case "blockquote":
                ensureLineBreakBeforeBlock()
                guard emitFlatBlockquote(
                    node,
                    hasTrailingSibling: needsBlockTrailingNewline,
                    into: output,
                    style: style
                ) else {
                    return false
                }
                didEmitAny = true
                lastEndedWithNewline = needsBlockTrailingNewline

            case "pre":
                ensureLineBreakBeforeBlock()
                guard emitCodeBlock(
                    node,
                    hasTrailingSibling: needsBlockTrailingNewline,
                    into: output,
                    style: style,
                    strict: strict
                ) else {
                    return false
                }
                didEmitAny = true
                lastEndedWithNewline = needsBlockTrailingNewline

            case "table":
                ensureLineBreakBeforeBlock()
                guard emitTable(
                    node,
                    hasTrailingSibling: needsBlockTrailingNewline,
                    into: output,
                    inlineAttachments: inlineAttachments,
                    style: style,
                    strict: strict
                ) else {
                    return false
                }
                didEmitAny = true
                lastEndedWithNewline = needsBlockTrailingNewline

            case "strong", "b", "em", "i", "u", "s", "del", "strike", "code", "a", "img":
                let beforeLength = output.length
                guard emitInlineNode(
                    node,
                    state: InlineState(),
                    into: output,
                    inlineAttachments: inlineAttachments,
                    style: style,
                    strict: strict
                ) else {
                    return false
                }
                if output.length > beforeLength {
                    didEmitAny = true
                    lastEndedWithNewline = output.string.hasSuffix("\n")
                }

            default:
                return false
            }
        }
        return true
    }

    private static func emitInlineChildren(
        _ nodes: [Node],
        state: InlineState,
        into output: NSMutableAttributedString,
        inlineAttachments: [String: MIMEMessageAttachment],
        style: Style,
        strict: Bool
    ) -> Bool {
        for child in nodes {
            guard emitInlineNode(
                child,
                state: state,
                into: output,
                inlineAttachments: inlineAttachments,
                style: style,
                strict: strict
            ) else {
                return false
            }
        }
        return true
    }

    private static func emitInlineNode(
        _ node: Node,
        state: InlineState,
        into output: NSMutableAttributedString,
        inlineAttachments: [String: MIMEMessageAttachment],
        style: Style,
        strict: Bool
    ) -> Bool {
        if let text = node.text {
            let decoded = ComposeHTMLPasteSanitizer.decodeHTMLEntities(text)
            if !decoded.isEmpty {
                appendInlineText(decoded, state: state, to: output, style: style)
            }
            return true
        }
        guard let tag = node.tag else { return false }
        switch tag {
        case "br":
            if state.headingLevel != nil && strict {
                return false
            }
            appendInlineText("\n", state: state, to: output, style: style)
            return true

        case "strong", "b":
            var next = state
            next.isBold = true
            return emitInlineChildren(
                node.children,
                state: next,
                into: output,
                inlineAttachments: inlineAttachments,
                style: style,
                strict: strict
            )

        case "em", "i":
            var next = state
            next.isItalic = true
            return emitInlineChildren(
                node.children,
                state: next,
                into: output,
                inlineAttachments: inlineAttachments,
                style: style,
                strict: strict
            )

        case "u":
            var next = state
            next.isUnderline = true
            return emitInlineChildren(
                node.children,
                state: next,
                into: output,
                inlineAttachments: inlineAttachments,
                style: style,
                strict: strict
            )

        case "s", "del", "strike":
            var next = state
            next.isStrikethrough = true
            return emitInlineChildren(
                node.children,
                state: next,
                into: output,
                inlineAttachments: inlineAttachments,
                style: style,
                strict: strict
            )

        case "code":
            var next = state
            next.isInlineCode = true
            return emitInlineChildren(
                node.children,
                state: next,
                into: output,
                inlineAttachments: inlineAttachments,
                style: style,
                strict: strict
            )

        case "a":
            var next = state
            if let href = node.attributeValue("href"),
               let safeHref = ComposeHTMLPasteSanitizer.sanitizedSafeHref(href),
               let url = URL(string: safeHref) {
                next.linkURL = url
            } else if strict, node.attributeValue("href") != nil {
                return false
            }
            return emitInlineChildren(
                node.children,
                state: next,
                into: output,
                inlineAttachments: inlineAttachments,
                style: style,
                strict: strict
            )

        case "img":
            return emitInlineImage(
                node,
                into: output,
                inlineAttachments: inlineAttachments,
                style: style
            )

        default:
            return false
        }
    }

    private static func emitInlineImage(
        _ node: Node,
        into output: NSMutableAttributedString,
        inlineAttachments: [String: MIMEMessageAttachment],
        style: Style
    ) -> Bool {
        guard let rawSrc = node.attributeValue("src") else { return false }
        let decodedSrc = ComposeHTMLPasteSanitizer.decodeHTMLEntities(rawSrc)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard decodedSrc.lowercased().hasPrefix("cid:") else { return false }
        let rawCID = String(decodedSrc.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCID = ComposeInlineImageData.normalizedContentID(rawCID)
        guard !normalizedCID.isEmpty,
              let payload = inlineAttachments[normalizedCID],
              payload.isInline,
              !payload.data.isEmpty else {
            return false
        }

        let attachment = NSTextAttachment()
        #if os(macOS)
        if let image = NSImage(data: payload.data) {
            attachment.image = image
            let size = image.size
            if size.width > style.maxImageWidth, size.width > 0 {
                let scale = style.maxImageWidth / size.width
                attachment.bounds = CGRect(
                    x: 0,
                    y: 0,
                    width: style.maxImageWidth,
                    height: size.height * scale
                )
            }
        } else {
            attachment.contents = payload.data
            attachment.fileType = payload.mimeType
        }
        #else
        if let image = UIImage(data: payload.data) {
            attachment.image = image
            let size = image.size
            if size.width > style.maxImageWidth, size.width > 0 {
                let scale = style.maxImageWidth / size.width
                attachment.bounds = CGRect(
                    x: 0,
                    y: 0,
                    width: style.maxImageWidth,
                    height: size.height * scale
                )
            }
        } else {
            attachment.contents = payload.data
            attachment.fileType = payload.mimeType
        }
        #endif

        let attachmentString = NSMutableAttributedString(attachment: attachment)
        let range = NSRange(location: 0, length: attachmentString.length)
        attachmentString.addAttribute(
            ComposeInlineImageAttribute.contentID,
            value: rawCID,
            range: range
        )
        if let rawAlt = node.attributeValue("alt") {
            let decodedAlt = ComposeHTMLPasteSanitizer.decodeHTMLEntities(rawAlt)
            if !decodedAlt.isEmpty {
                attachmentString.addAttribute(
                    ComposeInlineImageAttribute.alt,
                    value: decodedAlt,
                    range: range
                )
            }
        }
        output.append(attachmentString)
        return true
    }

    private static func emitList(
        _ listNode: Node,
        marker: NSTextList.MarkerFormat,
        hasTrailingSibling: Bool,
        into output: NSMutableAttributedString,
        inlineAttachments: [String: MIMEMessageAttachment],
        style: Style,
        strict: Bool
    ) -> Bool {
        guard !listNode.children.isEmpty else { return false }
        var listItems: [Node] = []
        for child in listNode.children {
            if child.tag == "li" {
                listItems.append(child)
            } else if let text = child.text, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !strict {
                continue
            } else {
                // Loose text or non-<li> children inside <ul>/<ol> fail closed.
                return false
            }
        }
        guard !listItems.isEmpty else { return false }

        let listStyle = NSMutableParagraphStyle()
        listStyle.textLists = [NSTextList(markerFormat: marker, options: 0)]
        listStyle.headIndent = 24
        listStyle.firstLineHeadIndent = 8

        for (index, item) in listItems.enumerated() {
            let start = output.length
            // Disallow <br> or block children inside <li> in strict mode.
            for itemChild in item.children {
                if itemChild.tag == "br" && strict { return false }
                guard emitInlineNode(
                    itemChild,
                    state: InlineState(),
                    into: output,
                    inlineAttachments: inlineAttachments,
                    style: style,
                    strict: strict
                ) else {
                    return false
                }
            }
            let needsNewline = index < listItems.count - 1 || hasTrailingSibling || output.length == start
            if needsNewline {
                appendPlain("\n", to: output, style: style)
            }
            let range = NSRange(location: start, length: output.length - start)
            if range.length > 0 {
                output.addAttribute(.paragraphStyle, value: listStyle.copy(), range: range)
            }
        }
        return true
    }

    private static func emitFlatBlockquote(
        _ quoteNode: Node,
        hasTrailingSibling: Bool,
        into output: NSMutableAttributedString,
        style: Style
    ) -> Bool {
        // Flat blockquotes contain only plain text and <br>; richer blockquotes
        // are preserved byte-for-byte via ComposeDraftQuoteSplitter instead.
        var lines = [""]
        for child in quoteNode.children {
            if let text = child.text {
                lines[lines.count - 1] += ComposeHTMLPasteSanitizer.decodeHTMLEntities(text)
            } else if child.tag == "br" {
                lines.append("")
            } else {
                return false
            }
        }
        let prefixed = lines.map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n")
        appendPlain(hasTrailingSibling ? prefixed + "\n" : prefixed, to: output, style: style)
        return true
    }

    private static func emitCodeBlock(
        _ preNode: Node,
        hasTrailingSibling: Bool,
        into output: NSMutableAttributedString,
        style: Style,
        strict: Bool
    ) -> Bool {
        // Accept `<pre><code>...</code></pre>` or bare `<pre>text</pre>`.
        let codeNodes: [Node]
        if preNode.children.count == 1, preNode.children[0].tag == "code" {
            codeNodes = preNode.children[0].children
        } else {
            codeNodes = preNode.children
        }

        var rawCode = ""
        for child in codeNodes {
            if let text = child.text {
                rawCode += ComposeHTMLPasteSanitizer.decodeHTMLEntities(text)
            } else if child.tag == "br", !strict {
                rawCode += "\n"
            } else {
                return false
            }
        }

        let blockID = UUID().uuidString
        let paraStyle = makeCodeBlockParagraphStyle()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: style.monospacedFont,
            .foregroundColor: style.textColor,
            .paragraphStyle: paraStyle,
            ComposeRichTextAttribute.codeBlockID: blockID
        ]

        let lines = rawCode.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for (index, line) in lines.enumerated() {
            let isLast = index == lines.count - 1
            let suffix = (!isLast || hasTrailingSibling || (isLast && line.isEmpty && lines.count == 1)) ? "\n" : ""
            output.append(NSAttributedString(string: line + suffix, attributes: attrs))
        }
        return true
    }

    private static func emitTable(
        _ tableNode: Node,
        hasTrailingSibling: Bool,
        into output: NSMutableAttributedString,
        inlineAttachments: [String: MIMEMessageAttachment],
        style: Style,
        strict: Bool
    ) -> Bool {
        var parsedRows: [(isHeaderRow: Bool, cells: [(isHeader: Bool, node: Node)])] = []

        func collectRows(from container: Node, inHead: Bool) -> Bool {
            for child in container.children {
                if let text = child.text {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        continue
                    }
                    return false
                }
                guard let tag = child.tag else { return false }
                switch tag {
                case "thead":
                    guard collectRows(from: child, inHead: true) else { return false }
                case "tbody":
                    guard collectRows(from: child, inHead: false) else { return false }
                case "tr":
                    var cells: [(isHeader: Bool, node: Node)] = []
                    for cellChild in child.children {
                        if let text = cellChild.text {
                            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                continue
                            }
                            return false
                        }
                        guard cellChild.tag == "th" || cellChild.tag == "td" else {
                            return false
                        }
                        cells.append((isHeader: inHead || cellChild.tag == "th", node: cellChild))
                    }
                    guard !cells.isEmpty else { return false }
                    parsedRows.append((isHeaderRow: inHead, cells: cells))
                default:
                    return false
                }
            }
            return true
        }

        guard collectRows(from: tableNode, inHead: false), !parsedRows.isEmpty else {
            return false
        }
        let columnCount = parsedRows.map(\.cells.count).max() ?? 0
        guard columnCount > 0 else { return false }
        if strict, !parsedRows.allSatisfy({ $0.cells.count == columnCount }) {
            return false
        }

        let tableID = UUID().uuidString
        #if os(macOS)
        let textTable = NSTextTable()
        textTable.numberOfColumns = columnCount
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        #endif

        for (rowIndex, row) in parsedRows.enumerated() {
            for (colIndex, cell) in row.cells.enumerated() {
                let isLastCell = rowIndex == parsedRows.count - 1 && colIndex == row.cells.count - 1
                let metadata = ComposeTableCellMetadata(
                    tableID: tableID,
                    row: rowIndex,
                    column: colIndex,
                    isHeader: cell.isHeader
                )
                let paragraphStyle = makeTableCellParagraphStyle(
                    row: rowIndex,
                    column: colIndex,
                    columnCount: columnCount,
                    isHeader: cell.isHeader,
                    style: style
                )
                #if os(macOS)
                attachMacTableBlock(
                    to: paragraphStyle,
                    table: textTable,
                    row: rowIndex,
                    column: colIndex,
                    columnCount: columnCount,
                    isHeader: cell.isHeader,
                    style: style
                )
                #endif

                let start = output.length
                var cellState = InlineState()
                if cell.isHeader {
                    cellState.isBold = true
                }
                for cellChild in cell.node.children {
                    if cellChild.tag == "br" && strict {
                        return false
                    }
                    guard emitInlineNode(
                        cellChild,
                        state: cellState,
                        into: output,
                        inlineAttachments: inlineAttachments,
                        style: style,
                        strict: strict
                    ) else {
                        return false
                    }
                }
                let isEmptyCell = output.length == start
                let needsNewline = !isLastCell || hasTrailingSibling || isEmptyCell
                if needsNewline {
                    appendInlineText("\n", state: cellState, to: output, style: style)
                }
                let range = NSRange(location: start, length: output.length - start)
                if range.length > 0 {
                    output.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
                    output.addAttribute(ComposeRichTextAttribute.tableCell, value: metadata, range: range)
                }
            }
        }
        return true
    }

    // MARK: - Styling Helpers

    private static func appendPlain(
        _ string: String,
        to output: NSMutableAttributedString,
        style: Style
    ) {
        output.append(NSAttributedString(string: string, attributes: [
            .font: style.baseFont,
            .foregroundColor: style.textColor
        ]))
    }

    private static func appendInlineText(
        _ string: String,
        state: InlineState,
        to output: NSMutableAttributedString,
        style: Style
    ) {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: resolvedFont(for: state, style: style),
            .foregroundColor: style.textColor
        ]
        if state.isUnderline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if state.isStrikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if state.isInlineCode {
            attributes[ComposeRichTextAttribute.inlineCode] = true
            attributes[.backgroundColor] = style.surfaceSecondaryColor
        }
        if let linkURL = state.linkURL {
            attributes[.link] = linkURL
        }
        if let headingLevel = state.headingLevel {
            attributes[ComposeRichTextAttribute.headingLevel] = headingLevel
            let headingStyle = NSMutableParagraphStyle()
            headingStyle.paragraphSpacingBefore = headingLevel == 1 ? 8 : 6
            headingStyle.paragraphSpacing = 4
            attributes[.paragraphStyle] = headingStyle
        }
        output.append(NSAttributedString(string: string, attributes: attributes))
    }

    private static func resolvedFont(for state: InlineState, style: Style) -> PlatformFont {
        #if os(macOS)
        var candidate: NSFont
        if state.isInlineCode {
            candidate = style.monospacedFont
        } else if let level = state.headingLevel {
            let scaledSize = style.baseFont.pointSize * ComposeEditorTypography.headingScale(for: level)
            candidate = NSFont(descriptor: style.baseFont.fontDescriptor, size: scaledSize) ?? style.baseFont
        } else {
            candidate = style.baseFont
        }
        var emphasis: NSFontDescriptor.SymbolicTraits = []
        if state.isBold || state.headingLevel != nil { emphasis.insert(.bold) }
        if state.isItalic { emphasis.insert(.italic) }
        if !emphasis.isEmpty {
            return ComposeEditorTypography.font(candidate, emphasis: emphasis) ?? candidate
        }
        return candidate
        #else
        var candidate: UIFont
        if state.isInlineCode {
            candidate = style.monospacedFont
        } else if let level = state.headingLevel {
            let scaledSize = style.baseFont.pointSize * ComposeEditorTypography.headingScale(for: level)
            candidate = style.baseFont.withSize(scaledSize)
        } else {
            candidate = style.baseFont
        }
        var traits = candidate.fontDescriptor.symbolicTraits
        if state.isBold || state.headingLevel != nil { traits.insert(.traitBold) }
        if state.isItalic { traits.insert(.traitItalic) }
        if let descriptor = candidate.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: candidate.pointSize)
        }
        return candidate
        #endif
    }

    static func makeCodeBlockParagraphStyle() -> NSMutableParagraphStyle {
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.headIndent = 12
        paraStyle.firstLineHeadIndent = 12
        paraStyle.paragraphSpacing = 2
        return paraStyle
    }

    private static func makeTableCellParagraphStyle(
        row _: Int,
        column _: Int,
        columnCount _: Int,
        isHeader _: Bool,
        style _: Style
    ) -> NSMutableParagraphStyle {
        let paraStyle = NSMutableParagraphStyle()
        #if os(iOS)
        paraStyle.headIndent = 10
        paraStyle.firstLineHeadIndent = 10
        paraStyle.paragraphSpacing = 4
        #endif
        return paraStyle
    }

    #if os(macOS)
    private static func attachMacTableBlock(
        to paragraphStyle: NSMutableParagraphStyle,
        table: NSTextTable,
        row: Int,
        column: Int,
        columnCount: Int,
        isHeader: Bool,
        style: Style
    ) {
        let block = NSTextTableBlock(
            table: table,
            startingRow: row,
            rowSpan: 1,
            startingColumn: column,
            columnSpan: 1
        )
        let widthPercent = 100.0 / CGFloat(max(columnCount, 1))
        block.setContentWidth(widthPercent, type: .percentageValueType)
        block.setWidth(0.5, type: .absoluteValueType, for: .border)
        block.setWidth(6, type: .absoluteValueType, for: .padding)
        block.setBorderColor(style.borderColor)
        if isHeader {
            block.backgroundColor = style.surfaceSecondaryColor
        }
        paragraphStyle.textBlocks = [block]
    }
    #endif

    private static func padded(_ cells: [String], to count: Int) -> [String] {
        if cells.count >= count {
            return Array(cells.prefix(count))
        }
        return cells + Array(repeating: "", count: count - cells.count)
    }
}
