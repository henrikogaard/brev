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
        var value = html.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("<br>") {
            value = String(value.dropLast(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
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

    static func decodeHTMLEntities(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&amp;", with: "&")
        result = replaceNumericEntities(in: result, pattern: #"&#x([0-9A-Fa-f]{1,6});"#, radix: 16)
        result = replaceNumericEntities(in: result, pattern: #"&#([0-9]{1,7});"#, radix: 10)
        return result
    }

    private static func replaceNumericEntities(in text: String, pattern: String, radix: Int) -> String {
        guard text.contains("&#"), let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        var output = ""
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text),
                  let digits = Range(match.range(at: 1), in: text),
                  let value = UInt32(text[digits], radix: radix),
                  let scalar = Unicode.Scalar(value) else {
                continue
            }
            output += text[cursor ..< whole.lowerBound]
            output.unicodeScalars.append(scalar)
            cursor = whole.upperBound
        }
        guard cursor > text.startIndex else { return text }
        output += text[cursor...]
        return output
    }
}
