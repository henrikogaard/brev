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

/// Deterministic, linear-time HTML sanitizer for rich-compose paste handling.
///
/// Preserves semantic formatting (`strong`, `em`, `u`, `s`, `h1`–`h3`, safe
/// `http`/`https`/`mailto` links, `ul`/`ol`/`li`, `blockquote`, semantic
/// `table`/`thead`/`tbody`/`tr`/`th`/`td`, inline `code`, and `<pre><code>`
/// blocks) while stripping active content (`script`, `style`, `iframe`,
/// `object`, `embed`, `form`, `meta`, `on*` event handlers), remote tracking
/// pixels and external `<img>` URLs, dangerous URL schemes (`javascript:`,
/// `vbscript:`, `data:`, `file:`), and inline color/background/CSS overrides
/// so pasted content adapts cleanly to Brev's light and dark themes.
enum ComposeHTMLPasteSanitizer {
    /// Maximum accepted HTML input size (1 MiB) before failing closed.
    static let maxInputBytes = 1_048_576

    private static let dropSubtreeTags: Set<String> = [
        "applet", "audio", "base", "button", "canvas", "embed", "form",
        "head", "iframe", "input", "link", "math", "meta", "noscript",
        "object", "option", "script", "select", "source", "style", "svg",
        "template", "textarea", "title", "video"
    ]

    private static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img",
        "input", "keygen", "link", "meta", "param", "source", "track", "wbr"
    ]

    private static let html5OptionalCloseTags: Set<String> = [
        "p", "li", "dt", "dd", "td", "th", "tr", "thead", "tbody", "tfoot", "colgroup", "option"
    ]

    private static let pClosingBlockTags: Set<String> = [
        "address", "article", "aside", "blockquote", "dd", "details", "div", "dl",
        "dt", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3",
        "h4", "h5", "h6", "header", "hgroup", "hr", "li", "main", "menu", "nav", "ol",
        "p", "pre", "section", "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul"
    ]

    private enum Token {
        case text(String)
        case openTag(name: String, rawTag: Substring, isSelfClosing: Bool)
        case closeTag(name: String)
    }

    private final class Node {
        let tag: String?
        let text: String?
        let rawTag: Substring?
        var children: [Node] = []

        init(tag: String?, rawTag: Substring? = nil) {
            self.tag = tag
            text = nil
            self.rawTag = rawTag
        }

        init(text: String) {
            tag = nil
            self.text = text
            rawTag = nil
        }
    }

    /// Sanitizes arbitrary pasted HTML into clean, balanced semantic HTML in
    /// Brev's supported rich-compose subset.
    ///
    /// - Parameters:
    ///   - rawHTML: The raw HTML payload from the pasteboard.
    ///   - allowedCIDs: Optional normalized `cid:` identifiers that may survive
    ///     as `<img src="cid:…">`. Defaults to empty so external paste strips all
    ///     `<img>` tags (including remote URLs and foreign `cid:` references).
    /// - Returns: Clean canonical HTML, or `nil` when `rawHTML` exceeds
    ///   `maxInputBytes`.
    static func sanitize(
        _ rawHTML: String,
        allowedCIDs: Set<String> = []
    ) -> String? {
        guard rawHTML.utf8.count <= maxInputBytes else { return nil }
        let normalizedInput = rawHTML
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let normalizedAllowedCIDs = Set(allowedCIDs.map(ComposeInlineImageData.normalizedContentID))

        let tokens = tokenize(normalizedInput)
        let root = buildTree(from: tokens)
        let rendered = renderChildren(
            of: root,
            inPre: false,
            inTableCell: false,
            inListItem: false,
            inBlockquote: false,
            allowedCIDs: normalizedAllowedCIDs
        )
        return cleanupOutput(rendered)
    }

    /// Validates whether `href` uses a safe link scheme (`http`, `https`, or `mailto`)
    /// with no embedded control characters.
    static func sanitizedSafeHref(_ rawHref: String) -> String? {
        let decoded = decodeHTMLEntities(rawHref)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decoded.isEmpty else { return nil }
        guard !decoded.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            return nil
        }
        let lowercased = decoded.lowercased()
        guard lowercased.hasPrefix("https://")
            || lowercased.hasPrefix("http://")
            || lowercased.hasPrefix("mailto:") else {
            return nil
        }
        guard URL(string: decoded) != nil else { return nil }
        return decoded
    }

    // MARK: - Tokenizer (Linear O(n))

    private static func tokenize(_ html: String) -> [Token] {
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
            if remaining.hasPrefix("<!--") {
                let afterOpen = html.index(lt, offsetBy: 4)
                if let closeRange = html[afterOpen ..< end].range(of: "-->") {
                    cursor = closeRange.upperBound
                } else {
                    break
                }
                continue
            }

            if remaining.hasPrefix("<!") || remaining.hasPrefix("<?") {
                if let gt = findTagClose(in: html, from: lt, limit: end) {
                    cursor = html.index(after: gt)
                } else {
                    break
                }
                continue
            }

            let afterLT = html.index(after: lt)
            guard afterLT < end else {
                tokens.append(.text("<"))
                break
            }
            let firstAfterLT = html[afterLT]
            guard firstAfterLT == "/" || (firstAfterLT.isASCII && firstAfterLT.isLetter) else {
                tokens.append(.text("<"))
                cursor = afterLT
                continue
            }

            guard let gt = findTagClose(in: html, from: lt, limit: end) else {
                break
            }
            let nextIndex = html.index(after: gt)
            let rawTag = html[lt ..< nextIndex]

            if let parsed = parseTag(rawTag) {
                if !parsed.isClosing, !parsed.isSelfClosing,
                   parsed.name == "script" || parsed.name == "style" {
                    if let closeEnd = findRawTextCloseEnd(
                        named: parsed.name,
                        in: html,
                        from: nextIndex,
                        limit: end
                    ) {
                        cursor = closeEnd
                    } else {
                        break
                    }
                    continue
                }
                if parsed.isClosing {
                    tokens.append(.closeTag(name: parsed.name))
                } else {
                    tokens.append(.openTag(
                        name: parsed.name,
                        rawTag: rawTag,
                        isSelfClosing: parsed.isSelfClosing
                    ))
                }
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

    private static func parseTag(_ raw: Substring) -> (name: String, isClosing: Bool, isSelfClosing: Bool)? {
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
        let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSelfClosing = !isClosing && (trimmed.hasSuffix("/") || voidTags.contains(name))
        return (name, isClosing, isSelfClosing)
    }

    private static func findRawTextCloseEnd(
        named name: String,
        in html: String,
        from start: String.Index,
        limit: String.Index
    ) -> String.Index? {
        let nameBytes = Array(name.utf8)
        var cursor = start
        while cursor < limit {
            guard let lt = html[cursor ..< limit].firstIndex(of: "<") else { return nil }
            var idx = html.index(after: lt)
            guard idx < limit, html[idx] == "/" else {
                cursor = idx
                continue
            }
            idx = html.index(after: idx)
            var matched = true
            for expectedByte in nameBytes {
                guard idx < limit, let ascii = html[idx].asciiValue else {
                    matched = false
                    break
                }
                let lower = (ascii >= 65 && ascii <= 90) ? ascii + 32 : ascii
                if lower != expectedByte {
                    matched = false
                    break
                }
                idx = html.index(after: idx)
            }
            guard matched else {
                cursor = html.index(after: lt)
                continue
            }
            while idx < limit, html[idx].isWhitespace {
                idx = html.index(after: idx)
            }
            if idx < limit, html[idx] == ">" {
                return html.index(after: idx)
            }
            cursor = idx > lt ? idx : html.index(after: lt)
        }
        return nil
    }

    // MARK: - Tree Construction

    private static func buildTree(from tokens: [Token]) -> Node {
        let root = Node(tag: nil)
        var stack: [Node] = [root]
        var dropDepth = 0
        var droppedTagStack: [String] = []

        for token in tokens {
            if dropDepth > 0 {
                switch token {
                case .openTag(let name, _, let isSelfClosing):
                    if !isSelfClosing, dropSubtreeTags.contains(name) {
                        dropDepth += 1
                        droppedTagStack.append(name)
                    }
                case .closeTag(let name):
                    if let last = droppedTagStack.last, last == name {
                        droppedTagStack.removeLast()
                        dropDepth -= 1
                    }
                case .text:
                    break
                }
                continue
            }

            switch token {
            case .text(let value):
                stack.last?.children.append(Node(text: value))

            case .openTag(let name, let rawTag, let isSelfClosing):
                if dropSubtreeTags.contains(name) {
                    if !isSelfClosing {
                        dropDepth = 1
                        droppedTagStack = [name]
                    }
                    continue
                }
                while stack.count > 1,
                      let topTag = stack.last?.tag,
                      canImplicitlyClose(openTag: topTag, onOpeningTag: name) {
                    stack.removeLast()
                }
                let node = Node(tag: name, rawTag: rawTag)
                stack.last?.children.append(node)
                if !isSelfClosing {
                    stack.append(node)
                }

            case .closeTag(let name):
                if dropSubtreeTags.contains(name) { continue }
                while stack.count > 1,
                      let topTag = stack.last?.tag,
                      topTag != name,
                      canImplicitlyClose(openTag: topTag, onClosingTag: name) {
                    stack.removeLast()
                }
                if let matchIndex = stack.lastIndex(where: { $0.tag == name }), matchIndex > 0 {
                    stack.removeSubrange(matchIndex ..< stack.count)
                }
            }
        }
        return root
    }

    private static func canImplicitlyClose(openTag: String, onOpeningTag nextTag: String) -> Bool {
        switch openTag {
        case "p":
            return pClosingBlockTags.contains(nextTag)
        case "li":
            return nextTag == "li"
        case "dt", "dd":
            return nextTag == "dt" || nextTag == "dd"
        case "td", "th":
            return nextTag == "td" || nextTag == "th" || nextTag == "tr"
                || nextTag == "thead" || nextTag == "tbody" || nextTag == "tfoot"
        case "tr":
            return nextTag == "tr" || nextTag == "thead" || nextTag == "tbody" || nextTag == "tfoot"
        case "thead", "tbody", "tfoot":
            return nextTag == "thead" || nextTag == "tbody" || nextTag == "tfoot"
        default:
            return false
        }
    }

    private static func canImplicitlyClose(openTag: String, onClosingTag closingTag: String) -> Bool {
        guard html5OptionalCloseTags.contains(openTag) else { return false }
        switch openTag {
        case "td", "th":
            return closingTag == "tr" || closingTag == "thead" || closingTag == "tbody"
                || closingTag == "tfoot" || closingTag == "table"
        case "tr":
            return closingTag == "thead" || closingTag == "tbody" || closingTag == "tfoot"
                || closingTag == "table"
        case "thead", "tbody", "tfoot":
            return closingTag == "table"
        case "li":
            return closingTag == "ul" || closingTag == "ol" || closingTag == "menu"
        case "dt", "dd":
            return closingTag == "dl"
        case "p":
            return closingTag != "a"
        default:
            return false
        }
    }

    // MARK: - Canonical Semantic Serialization

    private static func renderChildren(
        of parent: Node,
        inPre: Bool,
        inTableCell: Bool,
        inListItem: Bool,
        inBlockquote: Bool,
        allowedCIDs: Set<String>
    ) -> String {
        var result = ""
        for child in parent.children {
            result += render(
                node: child,
                inPre: inPre,
                inTableCell: inTableCell,
                inListItem: inListItem,
                inBlockquote: inBlockquote,
                allowedCIDs: allowedCIDs
            )
        }
        return result
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func render(
        node: Node,
        inPre: Bool,
        inTableCell: Bool,
        inListItem: Bool,
        inBlockquote: Bool,
        allowedCIDs: Set<String>
    ) -> String {
        if let text = node.text {
            let decoded = decodeHTMLEntities(text)
            if inPre {
                return escapeHTML(decoded)
            }
            // Collapse inter-tag source newlines/tabs outside <pre> to single spaces
            // while keeping meaningful text spaces intact.
            let collapsed = decoded.replacingOccurrences(
                of: #"[\t\n]+"#,
                with: " ",
                options: .regularExpression
            )
            if collapsed.trimmingCharacters(in: .whitespaces).isEmpty {
                return collapsed.isEmpty ? "" : " "
            }
            return escapeHTML(collapsed)
        }

        guard let tag = node.tag else { return "" }

        if inPre {
            if tag == "br" {
                return "\n"
            }
            return renderChildren(
                of: node,
                inPre: true,
                inTableCell: inTableCell,
                inListItem: inListItem,
                inBlockquote: inBlockquote,
                allowedCIDs: allowedCIDs
            )
        }

        switch tag {
        case "br":
            return "<br>"

        case "strong", "b":
            let inner = renderChildren(
                of: node,
                inPre: false,
                inTableCell: inTableCell,
                inListItem: inListItem,
                inBlockquote: inBlockquote,
                allowedCIDs: allowedCIDs
            )
            return inner.isEmpty ? "" : "<strong>\(inner)</strong>"

        case "em", "i":
            let inner = renderChildren(
                of: node,
                inPre: false,
                inTableCell: inTableCell,
                inListItem: inListItem,
                inBlockquote: inBlockquote,
                allowedCIDs: allowedCIDs
            )
            return inner.isEmpty ? "" : "<em>\(inner)</em>"

        case "u", "ins":
            let inner = renderChildren(
                of: node,
                inPre: false,
                inTableCell: inTableCell,
                inListItem: inListItem,
                inBlockquote: inBlockquote,
                allowedCIDs: allowedCIDs
            )
            return inner.isEmpty ? "" : "<u>\(inner)</u>"

        case "s", "del", "strike":
            let inner = renderChildren(
                of: node,
                inPre: false,
                inTableCell: inTableCell,
                inListItem: inListItem,
                inBlockquote: inBlockquote,
                allowedCIDs: allowedCIDs
            )
            return inner.isEmpty ? "" : "<s>\(inner)</s>"

        case "code":
            let inner = renderChildren(
                of: node,
                inPre: false,
                inTableCell: inTableCell,
                inListItem: inListItem,
                inBlockquote: inBlockquote,
                allowedCIDs: allowedCIDs
            )
            return inner.isEmpty ? "" : "<code>\(inner)</code>"

        case "a":
            let inner = renderChildren(
                of: node,
                inPre: false,
                inTableCell: inTableCell,
                inListItem: inListItem,
                inBlockquote: inBlockquote,
                allowedCIDs: allowedCIDs
            )
            guard !inner.isEmpty else { return "" }
            if let rawTag = node.rawTag,
               let href = attribute("href", in: rawTag),
               let safeHref = sanitizedSafeHref(href) {
                return "<a href=\"\(escapeHTML(safeHref))\">\(inner)</a>"
            }
            return inner

        case "img":
            guard let rawTag = node.rawTag,
                  let rawSrc = attribute("src", in: rawTag) else {
                return ""
            }
            let decodedSrc = decodeHTMLEntities(rawSrc).trimmingCharacters(in: .whitespacesAndNewlines)
            guard decodedSrc.lowercased().hasPrefix("cid:") else {
                return ""
            }
            let cid = String(decodedSrc.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedCID = ComposeInlineImageData.normalizedContentID(cid)
            guard !normalizedCID.isEmpty, allowedCIDs.contains(normalizedCID) else {
                return ""
            }
            let altAttr: String
            if let rawAlt = attribute("alt", in: rawTag) {
                let decodedAlt = decodeHTMLEntities(rawAlt).trimmingCharacters(in: .whitespacesAndNewlines)
                altAttr = decodedAlt.isEmpty ? "" : " alt=\"\(escapeHTML(decodedAlt))\""
            } else {
                altAttr = ""
            }
            return "<img src=\"cid:\(escapeHTML(cid))\"\(altAttr)>"

        case "h1", "h2", "h3", "h4", "h5", "h6":
            let inner = renderChildren(
                of: node,
                inPre: false,
                inTableCell: inTableCell,
                inListItem: inListItem,
                inBlockquote: inBlockquote,
                allowedCIDs: allowedCIDs
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !inner.isEmpty else { return "" }
            if inTableCell || inListItem || inBlockquote {
                return "<strong>\(inner)</strong>"
            }
            let normalizedTag = (tag == "h1" || tag == "h2" || tag == "h3") ? tag : "h3"
            return "<\(normalizedTag)>\(inner)</\(normalizedTag)>"

        case "pre":
            let codeText = extractPreText(from: node)
            let trimmedNewlines = trimSingleLeadingAndTrailingNewline(codeText)
            if inTableCell || inListItem || inBlockquote {
                let escaped = escapeHTML(trimmedNewlines).replacingOccurrences(of: "\n", with: "<br>")
                return escaped.isEmpty ? "" : "<code>\(escaped)</code>"
            }
            return "<pre><code>\(escapeHTML(trimmedNewlines))</code></pre>"

        case "blockquote":
            if inTableCell || inListItem {
                return renderChildren(
                    of: node,
                    inPre: false,
                    inTableCell: inTableCell,
                    inListItem: inListItem,
                    inBlockquote: inBlockquote,
                    allowedCIDs: allowedCIDs
                )
            }
            let quotePlain = extractBlockquoteLines(from: node)
            guard !quotePlain.isEmpty else { return "" }
            return "<blockquote>\(quotePlain)</blockquote>"

        case "ul", "ol":
            if inTableCell {
                let items = collectListItemHTML(
                    from: node,
                    inTableCell: true,
                    allowedCIDs: allowedCIDs
                )
                return items.joined(separator: "<br>")
            }
            let items = collectListItemHTML(
                from: node,
                inTableCell: false,
                allowedCIDs: allowedCIDs
            )
            guard !items.isEmpty else { return "" }
            let listItemsHTML = items.map { "<li>\($0)</li>" }.joined()
            return "<\(tag)>\(listItemsHTML)</\(tag)>"

        case "table":
            if inTableCell || inListItem {
                return flattenTableText(node, allowedCIDs: allowedCIDs)
            }
            return renderTable(node, allowedCIDs: allowedCIDs)

        case "p", "div", "section", "article", "header", "footer", "main", "aside":
            let inner = renderChildren(
                of: node,
                inPre: false,
                inTableCell: inTableCell,
                inListItem: inListItem,
                inBlockquote: inBlockquote,
                allowedCIDs: allowedCIDs
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if inner.isEmpty {
                return ""
            }
            if inTableCell || inListItem {
                return inner + "<br>"
            }
            if containsTopLevelBlock(inner) {
                return inner
            }
            return "<p>\(inner)</p>"

        case "span", "font":
            let inner = renderChildren(
                of: node,
                inPre: false,
                inTableCell: inTableCell,
                inListItem: inListItem,
                inBlockquote: inBlockquote,
                allowedCIDs: allowedCIDs
            )
            guard !inner.isEmpty else { return "" }
            guard let rawTag = node.rawTag,
                  let style = attribute("style", in: rawTag) else {
                return inner
            }
            return applySafeSemanticStyle(style, to: inner)

        default:
            return renderChildren(
                of: node,
                inPre: false,
                inTableCell: inTableCell,
                inListItem: inListItem,
                inBlockquote: inBlockquote,
                allowedCIDs: allowedCIDs
            )
        }
    }

    private static func extractPreText(from node: Node) -> String {
        if let text = node.text {
            return decodeHTMLEntities(text)
        }
        guard let tag = node.tag else { return "" }
        if tag == "br" {
            return "\n"
        }
        var out = ""
        for child in node.children {
            out += extractPreText(from: child)
        }
        if tag == "p" || tag == "div" || tag == "li" {
            if !out.hasSuffix("\n") {
                out += "\n"
            }
        }
        return out
    }

    private static func trimSingleLeadingAndTrailingNewline(_ text: String) -> String {
        var value = text
        if value.hasPrefix("\n") {
            value.removeFirst()
        }
        if value.hasSuffix("\n") {
            value.removeLast()
        }
        return value
    }

    private static func extractBlockquoteLines(from node: Node) -> String {
        var lines: [String] = []
        var current = ""

        func flushLine() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lines.append(escapeHTML(trimmed))
            }
            current = ""
        }

        func walk(_ currentNode: Node) {
            if let text = currentNode.text {
                let decoded = decodeHTMLEntities(text)
                    .replacingOccurrences(of: #"[\t\n]+"#, with: " ", options: .regularExpression)
                current += decoded
                return
            }
            guard let tag = currentNode.tag else { return }
            if tag == "br" {
                flushLine()
                return
            }
            let isBlock = pClosingBlockTags.contains(tag)
            if isBlock {
                flushLine()
            }
            for child in currentNode.children {
                walk(child)
            }
            if isBlock {
                flushLine()
            }
        }

        for child in node.children {
            walk(child)
        }
        flushLine()
        return lines.joined(separator: "<br>")
    }

    private static func collectListItemHTML(
        from listNode: Node,
        inTableCell: Bool,
        allowedCIDs: Set<String>
    ) -> [String] {
        var items: [String] = []
        for child in listNode.children {
            if child.tag == "li" {
                var ownParts = ""
                var nestedItems: [String] = []
                for liChild in child.children {
                    if liChild.tag == "ul" || liChild.tag == "ol" {
                        nestedItems.append(contentsOf: collectListItemHTML(
                            from: liChild,
                            inTableCell: inTableCell,
                            allowedCIDs: allowedCIDs
                        ))
                    } else {
                        ownParts += render(
                            node: liChild,
                            inPre: false,
                            inTableCell: inTableCell,
                            inListItem: true,
                            inBlockquote: false,
                            allowedCIDs: allowedCIDs
                        )
                    }
                }
                let cleanedOwn = stripTrailingBreaks(ownParts)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanedOwn.isEmpty {
                    items.append(cleanedOwn)
                }
                items.append(contentsOf: nestedItems)
            } else if child.tag == "ul" || child.tag == "ol" {
                items.append(contentsOf: collectListItemHTML(
                    from: child,
                    inTableCell: inTableCell,
                    allowedCIDs: allowedCIDs
                ))
            }
        }
        return items
    }

    private static func renderTable(_ tableNode: Node, allowedCIDs: Set<String>) -> String {
        var headerRows: [[(isHeader: Bool, html: String)]] = []
        var bodyRows: [[(isHeader: Bool, html: String)]] = []

        func collectRows(from container: Node, inHead: Bool) {
            for child in container.children {
                guard let tag = child.tag else { continue }
                switch tag {
                case "thead":
                    collectRows(from: child, inHead: true)
                case "tbody", "tfoot":
                    collectRows(from: child, inHead: false)
                case "tr":
                    var cells: [(isHeader: Bool, html: String)] = []
                    for cellNode in child.children {
                        guard cellNode.tag == "th" || cellNode.tag == "td" else { continue }
                        let isHeader = inHead || cellNode.tag == "th"
                        let rawCell = renderChildren(
                            of: cellNode,
                            inPre: false,
                            inTableCell: true,
                            inListItem: false,
                            inBlockquote: false,
                            allowedCIDs: allowedCIDs
                        )
                        let cleaned = stripTrailingBreaks(rawCell)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        cells.append((isHeader: isHeader, html: cleaned))
                    }
                    guard !cells.isEmpty else { continue }
                    if inHead || (bodyRows.isEmpty && cells.allSatisfy(\.isHeader)) {
                        headerRows.append(cells.map { (isHeader: true, html: $0.html) })
                    } else {
                        bodyRows.append(cells)
                    }
                default:
                    break
                }
            }
        }

        collectRows(from: tableNode, inHead: false)
        guard !headerRows.isEmpty || !bodyRows.isEmpty else { return "" }

        var out = "<table>"
        if !headerRows.isEmpty {
            out += "<thead>"
            for row in headerRows {
                out += "<tr>"
                for cell in row {
                    out += "<th>\(cell.html)</th>"
                }
                out += "</tr>"
            }
            out += "</thead>"
        }
        if !bodyRows.isEmpty {
            out += "<tbody>"
            for row in bodyRows {
                out += "<tr>"
                for cell in row {
                    let tag = cell.isHeader ? "th" : "td"
                    out += "<\(tag)>\(cell.html)</\(tag)>"
                }
                out += "</tr>"
            }
            out += "</tbody>"
        }
        out += "</table>"
        return out
    }

    private static func flattenTableText(_ tableNode: Node, allowedCIDs: Set<String>) -> String {
        var rowStrings: [String] = []
        func walk(_ node: Node) {
            if node.tag == "tr" {
                let cells = node.children.compactMap { child -> String? in
                    guard child.tag == "th" || child.tag == "td" else { return nil }
                    let rendered = stripTrailingBreaks(renderChildren(
                        of: child,
                        inPre: false,
                        inTableCell: true,
                        inListItem: false,
                        inBlockquote: false,
                        allowedCIDs: allowedCIDs
                    )).trimmingCharacters(in: .whitespacesAndNewlines)
                    return rendered.isEmpty ? nil : rendered
                }
                if !cells.isEmpty {
                    rowStrings.append(cells.joined(separator: " | "))
                }
                return
            }
            for child in node.children {
                walk(child)
            }
        }
        walk(tableNode)
        return rowStrings.joined(separator: "<br>")
    }

    /// Extracts strictly semantic inline traits (`font-weight`, `font-style`,
    /// `text-decoration`) from a pasted `style` attribute while discarding all
    /// colors, backgrounds, sizes, fonts, and layout CSS.
    private static func applySafeSemanticStyle(_ style: String, to inner: String) -> String {
        var wrapped = inner
        let declarations = style.split(separator: ";")
        var isBold = false
        var isItalic = false
        var isUnderline = false
        var isStrike = false

        for decl in declarations {
            let parts = decl.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let property = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch property {
            case "font-weight":
                if value == "bold" || value == "bolder" {
                    isBold = true
                } else if let weight = Int(value), weight >= 600 {
                    isBold = true
                }
            case "font-style":
                if value == "italic" || value == "oblique" {
                    isItalic = true
                }
            case "text-decoration", "text-decoration-line":
                if value.contains("underline") {
                    isUnderline = true
                }
                if value.contains("line-through") {
                    isStrike = true
                }
            default:
                break
            }
        }

        if isStrike { wrapped = "<s>\(wrapped)</s>" }
        if isUnderline { wrapped = "<u>\(wrapped)</u>" }
        if isItalic { wrapped = "<em>\(wrapped)</em>" }
        if isBold { wrapped = "<strong>\(wrapped)</strong>" }
        return wrapped
    }

    private static func containsTopLevelBlock(_ html: String) -> Bool {
        html.range(
            of: #"<(?:p|ul|ol|blockquote|pre|table|h[1-3])\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func stripTrailingBreaks(_ html: String) -> String {
        var start = html.startIndex
        var end = html.endIndex
        while start < end, html[start].isWhitespace {
            start = html.index(after: start)
        }
        while start < end {
            while start < end, html[html.index(before: end)].isWhitespace {
                end = html.index(before: end)
            }
            if html[start ..< end].hasSuffix("<br>") {
                end = html.index(end, offsetBy: -4)
            } else {
                break
            }
        }
        return String(html[start ..< end])
    }

    private static func cleanupOutput(_ html: String) -> String {
        var value = html.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip whitespace-only gaps directly between block boundaries without touching <pre>.
        if !value.contains("<pre>") {
            value = value.replacingOccurrences(
                of: #"(</(?:p|h[1-3]|ul|ol|blockquote|table)>)\s+(<(?:p|h[1-3]|ul|ol|blockquote|table|pre)\b)"#,
                with: "$1$2",
                options: .regularExpression
            )
        }
        return value
    }

    // MARK: - Attribute & Entity Helpers

    private static func attribute(_ name: String, in rawTag: Substring) -> String? {
        let tag = String(rawTag)
        let pattern = #"(?i)(?:\s|^)"# + NSRegularExpression.escapedPattern(for: name)
            + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s/>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else {
            return nil
        }
        for group in 1 ..< match.numberOfRanges {
            let range = match.range(at: group)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: tag) else {
                continue
            }
            return String(tag[swiftRange])
        }
        return nil
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// Single-pass O(n) HTML5 entity decoder covering named entities (Latin-1,
    /// Scandinavian/European diacritics, punctuation, currency, arrows, Greek,
    /// and math symbols) plus decimal (`&#…;`) and hexadecimal (`&#x…;`) numeric
    /// references. Never re-scans decoded output, so `&amp;#60;` decodes to
    /// literal `&#60;` rather than `<`.
    static func decodeHTMLEntities(_ value: String) -> String {
        guard value.contains("&") else { return value }
        var output = ""
        output.reserveCapacity(value.count)
        var cursor = value.startIndex
        let end = value.endIndex

        while cursor < end {
            guard let amp = value[cursor ..< end].firstIndex(of: "&") else {
                output.append(contentsOf: value[cursor ..< end])
                break
            }
            if cursor < amp {
                output.append(contentsOf: value[cursor ..< amp])
            }
            let afterAmp = value.index(after: amp)
            guard afterAmp < end else {
                output.append("&")
                break
            }
            // Scan at most 32 characters ahead for the terminating `;`.
            var scan = afterAmp
            var steps = 0
            var semicolon: String.Index?
            while scan < end, steps < 32 {
                let ch = value[scan]
                if ch == ";" {
                    semicolon = scan
                    break
                }
                if ch == "&" || ch.isWhitespace || ch == "<" {
                    break
                }
                scan = value.index(after: scan)
                steps += 1
            }
            if let semi = semicolon,
               let decoded = decodeSingleEntity(value[afterAmp ..< semi]) {
                output.append(decoded)
                cursor = value.index(after: semi)
            } else {
                output.append("&")
                cursor = afterAmp
            }
        }
        return output
    }

    private static func decodeSingleEntity(_ token: Substring) -> String? {
        guard !token.isEmpty else { return nil }
        if token.first == "#" {
            let digits = token.dropFirst()
            guard !digits.isEmpty else { return nil }
            let scalarValue: UInt32?
            if digits.first == "x" || digits.first == "X" {
                let hex = digits.dropFirst()
                guard !hex.isEmpty, hex.count <= 6 else { return nil }
                scalarValue = UInt32(hex, radix: 16)
            } else {
                guard digits.count <= 7 else { return nil }
                scalarValue = UInt32(digits, radix: 10)
            }
            guard let code = scalarValue, code > 0, let scalar = Unicode.Scalar(code) else {
                return nil
            }
            return String(scalar)
        }
        return namedEntities[String(token)]
    }

    private static let namedEntities: [String: String] = [
        // Core XML/HTML
        "amp": "&", "AMP": "&", "lt": "<", "LT": "<", "gt": ">", "GT": ">",
        "quot": "\"", "QUOT": "\"", "apos": "'", "nbsp": " ", "NonBreakingSpace": " ",
        // Latin-1 symbols & punctuation
        "iexcl": "\u{00A1}", "cent": "\u{00A2}", "pound": "\u{00A3}", "curren": "\u{00A4}",
        "yen": "\u{00A5}", "brvbar": "\u{00A6}", "sect": "\u{00A7}", "uml": "\u{00A8}",
        "copy": "\u{00A9}", "COPY": "\u{00A9}", "ordf": "\u{00AA}", "laquo": "\u{00AB}",
        "not": "\u{00AC}", "shy": "\u{00AD}", "reg": "\u{00AE}", "REG": "\u{00AE}",
        "macr": "\u{00AF}", "deg": "\u{00B0}", "plusmn": "\u{00B1}", "sup2": "\u{00B2}",
        "sup3": "\u{00B3}", "acute": "\u{00B4}", "micro": "\u{00B5}", "para": "\u{00B6}",
        "middot": "\u{00B7}", "cedil": "\u{00B8}", "sup1": "\u{00B9}", "ordm": "\u{00BA}",
        "raquo": "\u{00BB}", "frac14": "\u{00BC}", "frac12": "\u{00BD}", "frac34": "\u{00BE}",
        "iquest": "\u{00BF}", "times": "\u{00D7}", "divide": "\u{00F7}",
        // Latin-1 uppercase & lowercase letters (including Scandinavian Å/Ø/Æ)
        "Agrave": "\u{00C0}", "Aacute": "\u{00C1}", "Acirc": "\u{00C2}", "Atilde": "\u{00C3}",
        "Auml": "\u{00C4}", "Aring": "\u{00C5}", "AElig": "\u{00C6}", "Ccedil": "\u{00C7}",
        "Egrave": "\u{00C8}", "Eacute": "\u{00C9}", "Ecirc": "\u{00CA}", "Euml": "\u{00CB}",
        "Igrave": "\u{00CC}", "Iacute": "\u{00CD}", "Icirc": "\u{00CE}", "Iuml": "\u{00CF}",
        "ETH": "\u{00D0}", "Ntilde": "\u{00D1}", "Ograve": "\u{00D2}", "Oacute": "\u{00D3}",
        "Ocirc": "\u{00D4}", "Otilde": "\u{00D5}", "Ouml": "\u{00D6}", "Oslash": "\u{00D8}",
        "Ugrave": "\u{00D9}", "Uacute": "\u{00DA}", "Ucirc": "\u{00DB}", "Uuml": "\u{00DC}",
        "Yacute": "\u{00DD}", "THORN": "\u{00DE}", "szlig": "\u{00DF}",
        "agrave": "\u{00E0}", "aacute": "\u{00E1}", "acirc": "\u{00E2}", "atilde": "\u{00E3}",
        "auml": "\u{00E4}", "aring": "\u{00E5}", "aelig": "\u{00E6}", "ccedil": "\u{00E7}",
        "egrave": "\u{00E8}", "eacute": "\u{00E9}", "ecirc": "\u{00EA}", "euml": "\u{00EB}",
        "igrave": "\u{00EC}", "iacute": "\u{00ED}", "icirc": "\u{00EE}", "iuml": "\u{00EF}",
        "eth": "\u{00F0}", "ntilde": "\u{00F1}", "ograve": "\u{00F2}", "oacute": "\u{00F3}",
        "ocirc": "\u{00F4}", "otilde": "\u{00F5}", "ouml": "\u{00F6}", "oslash": "\u{00F8}",
        "ugrave": "\u{00F9}", "uacute": "\u{00FA}", "ucirc": "\u{00FB}", "uuml": "\u{00FC}",
        "yacute": "\u{00FD}", "thorn": "\u{00FE}", "yuml": "\u{00FF}",
        // Latin Extended-A & typographic punctuation
        "OElig": "\u{0152}", "oelig": "\u{0153}", "Scaron": "\u{0160}", "scaron": "\u{0161}",
        "Yuml": "\u{0178}", "fnof": "\u{0192}", "circ": "\u{02C6}", "tilde": "\u{02DC}",
        "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}", "zwnj": "\u{200C}",
        "zwj": "\u{200D}", "lrm": "\u{200E}", "rlm": "\u{200F}",
        "ndash": "\u{2013}", "mdash": "\u{2014}", "lsquo": "\u{2018}", "rsquo": "\u{2019}",
        "sbquo": "\u{201A}", "ldquo": "\u{201C}", "rdquo": "\u{201D}", "bdquo": "\u{201E}",
        "dagger": "\u{2020}", "Dagger": "\u{2021}", "bull": "\u{2022}", "hellip": "\u{2026}",
        "permil": "\u{2030}", "prime": "\u{2032}", "Prime": "\u{2033}", "lsaquo": "\u{2039}",
        "rsaquo": "\u{203A}", "oline": "\u{203E}", "frasl": "\u{2044}",
        "euro": "\u{20AC}", "trade": "\u{2122}", "TRADE": "\u{2122}",
        // Arrows
        "larr": "\u{2190}", "uarr": "\u{2191}", "rarr": "\u{2192}", "darr": "\u{2193}",
        "harr": "\u{2194}", "crarr": "\u{21B5}", "lArr": "\u{21D0}", "uArr": "\u{21D1}",
        "rArr": "\u{21D2}", "dArr": "\u{21D3}", "hArr": "\u{21D4}",
        // Common Greek letters
        "Alpha": "\u{0391}", "Beta": "\u{0392}", "Gamma": "\u{0393}", "Delta": "\u{0394}",
        "Epsilon": "\u{0395}", "Zeta": "\u{0396}", "Eta": "\u{0397}", "Theta": "\u{0398}",
        "Iota": "\u{0399}", "Kappa": "\u{039A}", "Lambda": "\u{039B}", "Mu": "\u{039C}",
        "Nu": "\u{039D}", "Xi": "\u{039E}", "Omicron": "\u{039F}", "Pi": "\u{03A0}",
        "Rho": "\u{03A1}", "Sigma": "\u{03A3}", "Tau": "\u{03A4}", "Upsilon": "\u{03A5}",
        "Phi": "\u{03A6}", "Chi": "\u{03A7}", "Psi": "\u{03A8}", "Omega": "\u{03A9}",
        "alpha": "\u{03B1}", "beta": "\u{03B2}", "gamma": "\u{03B3}", "delta": "\u{03B4}",
        "epsilon": "\u{03B5}", "zeta": "\u{03B6}", "eta": "\u{03B7}", "theta": "\u{03B8}",
        "iota": "\u{03B9}", "kappa": "\u{03BA}", "lambda": "\u{03BB}", "mu": "\u{03BC}",
        "nu": "\u{03BD}", "xi": "\u{03BE}", "omicron": "\u{03BF}", "pi": "\u{03C0}",
        "rho": "\u{03C1}", "sigmaf": "\u{03C2}", "sigma": "\u{03C3}", "tau": "\u{03C4}",
        "upsilon": "\u{03C5}", "phi": "\u{03C6}", "chi": "\u{03C7}", "psi": "\u{03C8}",
        "omega": "\u{03C9}",
        // Common mathematical & misc symbols
        "forall": "\u{2200}", "part": "\u{2202}", "exist": "\u{2203}", "empty": "\u{2205}",
        "nabla": "\u{2207}", "isin": "\u{2208}", "notin": "\u{2209}", "ni": "\u{220B}",
        "prod": "\u{220F}", "sum": "\u{2211}", "minus": "\u{2212}", "lowast": "\u{2217}",
        "radic": "\u{221A}", "prop": "\u{221D}", "infin": "\u{221E}", "ang": "\u{2220}",
        "and": "\u{2227}", "or": "\u{2228}", "cap": "\u{2229}", "cup": "\u{222A}",
        "int": "\u{222B}", "there4": "\u{2234}", "sim": "\u{223C}", "cong": "\u{2245}",
        "asymp": "\u{2248}", "ne": "\u{2260}", "equiv": "\u{2261}", "le": "\u{2264}",
        "ge": "\u{2265}", "sub": "\u{2282}", "sup": "\u{2283}", "nsub": "\u{2284}",
        "sube": "\u{2286}", "supe": "\u{2287}", "oplus": "\u{2295}", "otimes": "\u{2297}",
        "perp": "\u{22A5}", "sdot": "\u{22C5}", "loz": "\u{25CA}", "spades": "\u{2660}",
        "clubs": "\u{2663}", "hearts": "\u{2665}", "diams": "\u{2666}", "check": "\u{2713}",
        "cross": "\u{2717}", "star": "\u{2606}"
    ]
}
