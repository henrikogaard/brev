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

/// Splits a stored draft HTML body into an editable top prefix and a
/// byte-for-byte preserved quoted HTML tail using a linear balanced-tag scanner.
///
/// Returns `nil` when the HTML contains malformed/unbalanced tags or no
/// recognized quoted thread boundary so callers can fail closed.
enum ComposeDraftQuoteSplitter {
    struct SplitResult: Equatable {
        let editablePrefixHTML: String
        let quoteSeparatorHTML: String
        let preservedQuotedHTML: String
    }

    private struct TagToken {
        let name: String
        let isClosing: Bool
        let isSelfClosing: Bool
        let range: Range<String.Index>
        let rawTag: Substring
    }

    private enum TopLevelNode {
        case text(Range<String.Index>)
        case comment(Range<String.Index>)
        case declaration(Range<String.Index>)
        case voidTag(TagToken)
        case element(open: TagToken, close: TagToken, range: Range<String.Index>, innerRange: Range<String.Index>)

        var range: Range<String.Index> {
            switch self {
            case .text(let range), .comment(let range), .declaration(let range):
                return range
            case .voidTag(let token):
                return token.range
            case .element(_, _, let range, _):
                return range
            }
        }
    }

    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img",
        "input", "keygen", "link", "meta", "param", "source", "track", "wbr"
    ]

    private static let quoteContainerClasses: Set<String> = [
        "gmail_quote",
        "gmail_quote_container",
        "yahoo_quoted",
        "protonmail_quote",
        "outlookmessageheader"
    ]

    private static let quoteContainerIDs: Set<String> = [
        "divrplyfwdmsg",
        "mail-editor-reference-message-container"
    ]

    private static let quotePreludeClasses: Set<String> = [
        "gmail_attr",
        "moz-cite-prefix",
        "appleoriginalcontents",
        "quote_header"
    ]

    private static let quotePreludeIDs: Set<String> = [
        "appendonsend"
    ]

    /// Attempts to split `html` at the first balanced quoted-thread boundary.
    static func split(_ html: String) -> SplitResult? {
        guard !html.isEmpty else { return nil }
        return split(in: html, sliceRange: html.startIndex ..< html.endIndex, allowUnwrapDepth: 2)
    }

    private static func split(
        in html: String,
        sliceRange: Range<String.Index>,
        allowUnwrapDepth: Int
    ) -> SplitResult? {
        guard let nodes = parseTopLevelNodes(in: html, sliceRange: sliceRange) else {
            return nil
        }
        guard let quoteNodeIndex = nodes.firstIndex(where: { isQuoteContainer($0, in: html) }) else {
            if allowUnwrapDepth > 0, let innerRange = singlePlainWrapperInnerRange(in: nodes, html: html) {
                return split(in: html, sliceRange: innerRange, allowUnwrapDepth: allowUnwrapDepth - 1)
            }
            return nil
        }

        let quoteNode = nodes[quoteNodeIndex]
        let isBlockquoteBoundary = isBlockquoteElement(quoteNode)
        let isOutlookBoundary = isOutlookQuoteElement(quoteNode, in: html)

        var startNodeIndex = quoteNodeIndex
        var textSplitIndex: String.Index?

        // Pull explicit quote-prelude elements and immediate attribution headers
        // into the preserved quote tail so they never dangle in the editable box.
        var scanIndex = quoteNodeIndex - 1
        while scanIndex >= 0 {
            let candidate = nodes[scanIndex]
            if isInsignificantSeparator(candidate, in: html) {
                scanIndex -= 1
                continue
            }
            if isExplicitQuotePrelude(candidate, isOutlookBoundary: isOutlookBoundary, in: html) {
                startNodeIndex = scanIndex
                scanIndex -= 1
                continue
            }
            if isBlockquoteBoundary {
                if case .text(let textRange) = candidate,
                   let attributionStart = trailingAttributionStart(in: html[textRange]) {
                    textSplitIndex = attributionStart
                    startNodeIndex = scanIndex
                    break
                }
                if isAttributionElement(candidate, in: html) {
                    startNodeIndex = scanIndex
                }
            }
            break
        }

        let quoteStart: String.Index
        let prefixEndNodeLimit: Int
        if let textSplitIndex {
            quoteStart = textSplitIndex
            let candidateRange = nodes[startNodeIndex].range
            if textSplitIndex == candidateRange.lowerBound {
                prefixEndNodeLimit = startNodeIndex
            } else {
                // Prefix ends mid-text node right before the attribution line.
                let prefixRaw = String(html[sliceRange.lowerBound ..< textSplitIndex])
                let (prefixTrimmed, trailingWhitespace) = splittingTrailingNewlinesAndWhitespace(prefixRaw)
                let preserved = String(html[quoteStart ..< sliceRange.upperBound])
                return SplitResult(
                    editablePrefixHTML: prefixTrimmed,
                    quoteSeparatorHTML: trailingWhitespace,
                    preservedQuotedHTML: preserved
                )
            }
        } else {
            quoteStart = nodes[startNodeIndex].range.lowerBound
            prefixEndNodeLimit = startNodeIndex
        }

        // Separate trailing `<br>`, whitespace, and empty `<div><br></div>`
        // dividers between the editable prefix and the quote boundary.
        var separatorStartNodeIndex = prefixEndNodeLimit
        while separatorStartNodeIndex > 0,
              isQuoteGapNode(nodes[separatorStartNodeIndex - 1], in: html) {
            separatorStartNodeIndex -= 1
        }

        let separatorStart: String.Index = if separatorStartNodeIndex < prefixEndNodeLimit {
            nodes[separatorStartNodeIndex].range.lowerBound
        } else {
            quoteStart
        }

        let editablePrefixHTML = String(html[sliceRange.lowerBound ..< separatorStart])
        let quoteSeparatorHTML = String(html[separatorStart ..< quoteStart])
        let preservedQuotedHTML = String(html[quoteStart ..< sliceRange.upperBound])

        guard !preservedQuotedHTML.isEmpty else { return nil }
        return SplitResult(
            editablePrefixHTML: editablePrefixHTML,
            quoteSeparatorHTML: quoteSeparatorHTML,
            preservedQuotedHTML: preservedQuotedHTML
        )
    }

    // MARK: - Balanced HTML Scanner

    /// Parses top-level nodes inside `sliceRange` while strictly verifying that
    /// every non-void tag, comment, and raw-text block is properly closed and
    /// nested. Returns `nil` on any malformed or unbalanced markup.
    private static func parseTopLevelNodes(
        in html: String,
        sliceRange: Range<String.Index>
    ) -> [TopLevelNode]? {
        var nodes: [TopLevelNode] = []
        var stack: [TagToken] = []
        var cursor = sliceRange.lowerBound
        var textStart: String.Index?

        func flushText(upTo index: String.Index) {
            guard stack.isEmpty, let start = textStart, start < index else {
                textStart = nil
                return
            }
            nodes.append(.text(start ..< index))
            textStart = nil
        }

        while cursor < sliceRange.upperBound {
            if html[cursor] != "<" {
                if stack.isEmpty, textStart == nil {
                    textStart = cursor
                }
                cursor = html.index(after: cursor)
                continue
            }

            let remaining = html[cursor ..< sliceRange.upperBound]

            // HTML comment: <!-- ... -->
            if remaining.hasPrefix("<!--") {
                flushText(upTo: cursor)
                let afterOpen = html.index(cursor, offsetBy: 4)
                guard let closeRange = html[afterOpen ..< sliceRange.upperBound].range(of: "-->") else {
                    return nil
                }
                if stack.isEmpty {
                    nodes.append(.comment(cursor ..< closeRange.upperBound))
                }
                cursor = closeRange.upperBound
                continue
            }

            // Doctype or processing instruction: <!...> / <?...>
            if remaining.hasPrefix("<!") || remaining.hasPrefix("<?") {
                flushText(upTo: cursor)
                guard let tagEnd = findTagCloseIndex(in: html, from: cursor, limit: sliceRange.upperBound) else {
                    return nil
                }
                let nextIndex = html.index(after: tagEnd)
                if stack.isEmpty {
                    nodes.append(.declaration(cursor ..< nextIndex))
                }
                cursor = nextIndex
                continue
            }

            // Standard HTML tag: <tag ...> or </tag>
            let afterLT = html.index(after: cursor)
            guard afterLT < sliceRange.upperBound else {
                return nil
            }
            let firstAfterLT = html[afterLT]
            guard firstAfterLT == "/" || firstAfterLT.isASCII && firstAfterLT.isLetter else {
                // Lone `<` followed by non-tag character (e.g. `1 < 2`): treat as text.
                if stack.isEmpty, textStart == nil {
                    textStart = cursor
                }
                cursor = afterLT
                continue
            }

            flushText(upTo: cursor)
            guard let tagEnd = findTagCloseIndex(in: html, from: cursor, limit: sliceRange.upperBound) else {
                return nil
            }
            let nextIndex = html.index(after: tagEnd)
            let tokenRange = cursor ..< nextIndex
            guard let token = parseTagToken(html[tokenRange], range: tokenRange) else {
                return nil
            }

            // Raw-text elements (<style>, <script>): scan directly to matching close tag.
            if !token.isClosing, !token.isSelfClosing, token.name == "style" || token.name == "script" {
                guard let closeToken = findRawTextCloseTag(
                    named: token.name,
                    in: html,
                    from: nextIndex,
                    limit: sliceRange.upperBound
                ) else {
                    return nil
                }
                if stack.isEmpty {
                    nodes.append(.element(
                        open: token,
                        close: closeToken,
                        range: token.range.lowerBound ..< closeToken.range.upperBound,
                        innerRange: token.range.upperBound ..< closeToken.range.lowerBound
                    ))
                }
                cursor = closeToken.range.upperBound
                continue
            }

            if token.isClosing {
                guard let open = stack.popLast(), open.name == token.name else {
                    return nil
                }
                if stack.isEmpty {
                    nodes.append(.element(
                        open: open,
                        close: token,
                        range: open.range.lowerBound ..< token.range.upperBound,
                        innerRange: open.range.upperBound ..< token.range.lowerBound
                    ))
                }
            } else if token.isSelfClosing {
                if stack.isEmpty {
                    nodes.append(.voidTag(token))
                }
            } else {
                stack.append(token)
            }
            cursor = nextIndex
        }

        guard stack.isEmpty else {
            return nil
        }
        flushText(upTo: sliceRange.upperBound)
        return nodes
    }

    /// Finds the closing `>` of a tag starting at `start`, respecting `"..."` and `'...'` attributes.
    private static func findTagCloseIndex(
        in html: String,
        from start: String.Index,
        limit: String.Index
    ) -> String.Index? {
        var index = html.index(after: start)
        var quoteChar: Character?
        while index < limit {
            let ch = html[index]
            if let activeQuote = quoteChar {
                if ch == activeQuote {
                    quoteChar = nil
                }
            } else if ch == "\"" || ch == "'" {
                quoteChar = ch
            } else if ch == ">" {
                return index
            }
            index = html.index(after: index)
        }
        return nil
    }

    private static func parseTagToken(_ raw: Substring, range: Range<String.Index>) -> TagToken? {
        guard raw.count >= 3, raw.first == "<", raw.last == ">" else { return nil }
        let inner = raw.dropFirst().dropLast()
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
              || (ascii >= 48 && ascii <= 57)
              || ascii == 45
              || ascii == 58 {
            idx = inner.index(after: idx)
        }
        guard nameStart < idx else { return nil }
        let name = String(inner[nameStart ..< idx]).lowercased()

        let trimmedInner = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitSelfClosing = !isClosing && trimmedInner.hasSuffix("/")
        let isSelfClosing = !isClosing && (explicitSelfClosing || voidElements.contains(name))

        return TagToken(
            name: name,
            isClosing: isClosing,
            isSelfClosing: isSelfClosing,
            range: range,
            rawTag: raw
        )
    }

    private static func findRawTextCloseTag(
        named name: String,
        in html: String,
        from start: String.Index,
        limit: String.Index
    ) -> TagToken? {
        var search = start
        while search < limit {
            guard let lt = html[search ..< limit].firstIndex(of: "<") else {
                return nil
            }
            if let gt = findTagCloseIndex(in: html, from: lt, limit: limit) {
                let next = html.index(after: gt)
                let tokenRange = lt ..< next
                if let token = parseTagToken(html[tokenRange], range: tokenRange),
                   token.isClosing,
                   token.name == name {
                    return token
                }
            }
            search = html.index(after: lt)
        }
        return nil
    }

    // MARK: - Quote & Attribution Recognition

    private static func isQuoteContainer(_ node: TopLevelNode, in _: String) -> Bool {
        guard case .element(let open, _, _, _) = node else { return false }
        if open.name == "blockquote" {
            return true
        }
        guard open.name == "div" else { return false }
        if let id = attribute("id", in: open.rawTag)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           quoteContainerIDs.contains(id) {
            return true
        }
        if let classValue = attribute("class", in: open.rawTag) {
            let classes = classValue.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if classes.contains(where: { quoteContainerClasses.contains($0) }) {
                return true
            }
        }
        return false
    }

    private static func isBlockquoteElement(_ node: TopLevelNode) -> Bool {
        guard case .element(let open, _, _, _) = node else { return false }
        return open.name == "blockquote"
    }

    private static func isOutlookQuoteElement(_ node: TopLevelNode, in _: String) -> Bool {
        guard case .element(let open, _, _, _) = node, open.name == "div" else { return false }
        let id = attribute("id", in: open.rawTag)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return id.map { quoteContainerIDs.contains($0) } ?? false
    }

    private static func isExplicitQuotePrelude(
        _ node: TopLevelNode,
        isOutlookBoundary: Bool,
        in _: String
    ) -> Bool {
        switch node {
        case .voidTag(let token):
            return isOutlookBoundary && token.name == "hr"
        case .element(let open, _, _, _):
            guard open.name == "div" || open.name == "p" else { return false }
            if let id = attribute("id", in: open.rawTag)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               quotePreludeIDs.contains(id) {
                return true
            }
            if let classValue = attribute("class", in: open.rawTag) {
                let classes = classValue.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
                if classes.contains(where: { quotePreludeClasses.contains($0) }) {
                    return true
                }
            }
            return false
        default:
            return false
        }
    }

    private static func isAttributionElement(_ node: TopLevelNode, in html: String) -> Bool {
        guard case .element(let open, _, let range, _) = node,
              open.name == "div" || open.name == "p" else {
            return false
        }
        let plain = ComposeQuoteTextPolicy.htmlToPlainText(String(html[range]))
        return looksLikeAttributionHeader(plain)
    }

    private static func trailingAttributionStart(in text: Substring) -> String.Index? {
        let trimmedEnd = text.lastIndex(where: { !$0.isWhitespace })
        guard let trimmedEnd else { return nil }
        let upToEnd = text[...trimmedEnd]
        let lineStart: String.Index
        if let lastNewline = upToEnd.lastIndex(of: "\n") {
            lineStart = text.index(after: lastNewline)
        } else {
            lineStart = text.startIndex
        }
        let candidateLine = String(upToEnd[lineStart...])
        let decoded = ComposeQuoteTextPolicy.htmlToPlainText(candidateLine)
        guard looksLikeAttributionHeader(decoded) else { return nil }
        // Advance past any leading spaces on that attribution line only if it's after a newline.
        var start = lineStart
        while start < trimmedEnd, text[start] == " " || text[start] == "\t" {
            start = text.index(after: start)
        }
        return start
    }

    private static func looksLikeAttributionHeader(_ plainText: String) -> Bool {
        let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 300 else { return false }
        let lines = trimmed.components(separatedBy: "\n")
        // Reject multi-paragraph blocks that include real reply copy above an attribution line.
        guard lines.count <= 2, !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return false
        }
        let normalized = lines.joined(separator: " ").lowercased()
        let suffixes = [
            "wrote:",
            "wrote :",
            "skrev:",
            "skrev :",
            "schrieb:",
            "schrieb :",
            "écrit :",
            "écrit:",
            "escribió:",
            "ha scritto:",
            "begin forwarded message:",
            "videresendt melding:"
        ]
        if suffixes.contains(where: { normalized.hasSuffix($0) }) {
            return true
        }
        let markers = [
            "forwarded message",
            "original message",
            "videresendt melding",
            "opprinnelig melding"
        ]
        if markers.contains(where: { normalized.contains($0) }),
           normalized.hasPrefix("-") || normalized.hasPrefix("—") || normalized.hasPrefix("begin ") {
            return true
        }
        return false
    }

    private static func isInsignificantSeparator(_ node: TopLevelNode, in html: String) -> Bool {
        switch node {
        case .text(let range):
            return html[range].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .voidTag(let token):
            return token.name == "br"
        default:
            return false
        }
    }

    private static func isQuoteGapNode(_ node: TopLevelNode, in html: String) -> Bool {
        if isInsignificantSeparator(node, in: html) {
            return true
        }
        guard case .element(let open, _, _, let innerRange) = node,
              open.name == "div" || open.name == "p",
              isPlainOrDirectionOnlyTag(open) else {
            return false
        }
        let inner = html[innerRange].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return inner.isEmpty || inner == "<br>" || inner == "<br/>" || inner == "<br />" || inner == "&nbsp;"
    }

    /// Returns the inner range when the slice consists solely of one plain/direction-only
    /// container (`<div>`, `<div dir="ltr|rtl|auto">`, `<body>`, or `<html>`).
    private static func singlePlainWrapperInnerRange(
        in nodes: [TopLevelNode],
        html: String
    ) -> Range<String.Index>? {
        let significant = nodes.filter { node in
            switch node {
            case .text(let range):
                return !html[range].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .comment, .declaration:
                return false
            default:
                return true
            }
        }
        guard significant.count == 1,
              case .element(let open, _, _, let innerRange) = significant[0],
              open.name == "div" || open.name == "body" || open.name == "html",
              isPlainOrDirectionOnlyTag(open) else {
            return nil
        }
        return innerRange
    }

    private static func isPlainOrDirectionOnlyTag(_ token: TagToken) -> Bool {
        let stripped = String(token.rawTag)
            .replacingOccurrences(
                of: #"(?i)^<\s*(?:div|p|body|html)(?:\s+dir\s*=\s*"(?:ltr|rtl|auto)")?\s*>$"#,
                with: "",
                options: .regularExpression
            )
        return stripped.isEmpty
    }

    private static func splittingTrailingNewlinesAndWhitespace(_ value: String) -> (String, String) {
        var idx = value.endIndex
        while idx > value.startIndex {
            let prev = value.index(before: idx)
            if value[prev].isWhitespace {
                idx = prev
            } else {
                break
            }
        }
        return (String(value[..<idx]), String(value[idx...]))
    }

    /// Extracts an attribute value from a single opening HTML tag, respecting
    /// double-quoted, single-quoted, and unquoted forms.
    private static func attribute(_ name: String, in rawTag: Substring) -> String? {
        guard rawTag.count >= 2 else { return nil }
        let content = rawTag.dropFirst().dropLast()
        var idx = content.startIndex
        // Skip tag name.
        while idx < content.endIndex, content[idx].isWhitespace {
            idx = content.index(after: idx)
        }
        while idx < content.endIndex, !content[idx].isWhitespace, content[idx] != "/" {
            idx = content.index(after: idx)
        }

        let target = name.lowercased()
        while idx < content.endIndex {
            while idx < content.endIndex, content[idx].isWhitespace || content[idx] == "/" {
                idx = content.index(after: idx)
            }
            guard idx < content.endIndex else { break }
            let attrStart = idx
            while idx < content.endIndex,
                  !content[idx].isWhitespace,
                  content[idx] != "=",
                  content[idx] != "/" {
                idx = content.index(after: idx)
            }
            let attrName = String(content[attrStart ..< idx]).lowercased()
            while idx < content.endIndex, content[idx].isWhitespace {
                idx = content.index(after: idx)
            }
            var attrValue: String?
            if idx < content.endIndex, content[idx] == "=" {
                idx = content.index(after: idx)
                while idx < content.endIndex, content[idx].isWhitespace {
                    idx = content.index(after: idx)
                }
                if idx < content.endIndex {
                    let ch = content[idx]
                    if ch == "\"" || ch == "'" {
                        idx = content.index(after: idx)
                        let valStart = idx
                        while idx < content.endIndex, content[idx] != ch {
                            idx = content.index(after: idx)
                        }
                        attrValue = String(content[valStart ..< idx])
                        if idx < content.endIndex {
                            idx = content.index(after: idx)
                        }
                    } else {
                        let valStart = idx
                        while idx < content.endIndex, !content[idx].isWhitespace {
                            idx = content.index(after: idx)
                        }
                        attrValue = String(content[valStart ..< idx])
                    }
                }
            }
            if attrName == target {
                return attrValue
            }
        }
        return nil
    }
}
