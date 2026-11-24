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
        /// Enclosing opening wrapper tags (such as `<div dir="rtl">`) unwrapped to
        /// reach the quote boundary; re-applied around edited HTML on save/send.
        let outerWrapperOpenHTML: String
        /// Enclosing closing wrapper tags matching `outerWrapperOpenHTML`.
        let outerWrapperCloseHTML: String
        /// Inherited text direction (`"rtl"`, `"ltr"`, or `"auto"`) from an unwrapped
        /// direction-bearing container, used to preserve directionality in previews.
        let inheritedDirection: String?

        init(
            editablePrefixHTML: String,
            quoteSeparatorHTML: String,
            preservedQuotedHTML: String,
            outerWrapperOpenHTML: String = "",
            outerWrapperCloseHTML: String = "",
            inheritedDirection: String? = nil
        ) {
            self.editablePrefixHTML = editablePrefixHTML
            self.quoteSeparatorHTML = quoteSeparatorHTML
            self.preservedQuotedHTML = preservedQuotedHTML
            self.outerWrapperOpenHTML = outerWrapperOpenHTML
            self.outerWrapperCloseHTML = outerWrapperCloseHTML
            self.inheritedDirection = inheritedDirection
        }
    }

    private struct TagToken {
        let name: String
        let isClosing: Bool
        let isSelfClosing: Bool
        let range: Range<String.Index>
        let rawTag: Substring
    }

    private struct WrapperContext {
        var openHTML = ""
        var closeHTML = ""
        var inheritedDirection: String?
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

    /// HTML5 elements whose closing tags are optional when implicitly closed by
    /// a following sibling or enclosing parent close tag inside quoted HTML.
    private static let html5OptionalCloseElements: Set<String> = [
        "p", "li", "dt", "dd", "td", "th", "tr", "thead", "tbody", "tfoot", "colgroup", "option"
    ]

    /// Block-level and enclosing optional-close opening tags that implicitly close
    /// an open `<p>` per HTML5 (including `<li>`, `<dt>`, `<dd>`, and table cells/rows
    /// so nested optional tags such as `<ul><li><p>One<li><p>Two</ul>` unwind cleanly).
    private static let pClosingBlockElements: Set<String> = [
        "address", "article", "aside", "blockquote", "dd", "details", "div", "dl",
        "dt", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3",
        "h4", "h5", "h6", "header", "hgroup", "hr", "li", "main", "menu", "nav", "ol",
        "p", "pre", "section", "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul"
    ]

    /// Attempts to split `html` at the first balanced complex/explicit quoted-thread boundary.
    static func split(_ html: String) -> SplitResult? {
        guard !html.isEmpty else { return nil }
        return split(
            in: html,
            sliceRange: html.startIndex ..< html.endIndex,
            allowUnwrapDepth: 2,
            wrapper: WrapperContext()
        )
    }

    private static func split(
        in html: String,
        sliceRange: Range<String.Index>,
        allowUnwrapDepth: Int,
        wrapper: WrapperContext
    ) -> SplitResult? {
        guard let nodes = parseTopLevelNodes(in: html, sliceRange: sliceRange) else {
            return nil
        }
        // Prefer a complex/styled/nested blockquote or explicit webmail quote
        // container so user-typed flat `<blockquote>...</blockquote>` lines above a
        // preserved thread remain editable on reopen. Fall back to a plain blockquote
        // only when it is immediately preceded by an explicit prelude or standalone
        // attribution block (e.g. a styled `<div style="...">On Mon, Ada wrote:</div>`).
        let quoteNodeIndex = nodes.firstIndex(where: { isComplexOrExplicitQuoteContainer($0, in: html) })
            ?? fallbackAttributedBlockquoteIndex(in: nodes, html: html)
        guard let quoteNodeIndex else {
            if allowUnwrapDepth > 0, let unwrapped = singlePlainWrapper(in: nodes, html: html) {
                var nextWrapper = wrapper
                nextWrapper.openHTML += String(unwrapped.open.rawTag)
                nextWrapper.closeHTML = String(unwrapped.close.rawTag) + nextWrapper.closeHTML
                if let dir = unwrapped.direction {
                    nextWrapper.inheritedDirection = dir
                }
                return split(
                    in: html,
                    sliceRange: unwrapped.innerRange,
                    allowUnwrapDepth: allowUnwrapDepth - 1,
                    wrapper: nextWrapper
                )
            }
            return nil
        }

        let quoteNode = nodes[quoteNodeIndex]
        let isBlockquoteBoundary = isBlockquoteElement(quoteNode)
        let isOutlookBoundary = isOutlookQuoteElement(quoteNode)

        var startNodeIndex = quoteNodeIndex
        var textSplitIndex: String.Index?

        // Pull explicit quote-prelude elements and immediate standalone attribution
        // headers into the preserved quote tail so they never dangle in the editor.
        var scanIndex = quoteNodeIndex - 1
        while scanIndex >= 0 {
            let candidate = nodes[scanIndex]
            if isInsignificantSeparator(candidate, in: html) {
                scanIndex -= 1
                continue
            }
            if isExplicitQuotePrelude(candidate, isOutlookBoundary: isOutlookBoundary) {
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
                if isStandaloneAttributionElement(candidate, in: html) {
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
                    preservedQuotedHTML: preserved,
                    outerWrapperOpenHTML: wrapper.openHTML,
                    outerWrapperCloseHTML: wrapper.closeHTML,
                    inheritedDirection: wrapper.inheritedDirection
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
            preservedQuotedHTML: preservedQuotedHTML,
            outerWrapperOpenHTML: wrapper.openHTML,
            outerWrapperCloseHTML: wrapper.closeHTML,
            inheritedDirection: wrapper.inheritedDirection
        )
    }

    // MARK: - Balanced HTML Scanner

    /// Parses top-level nodes inside `sliceRange` while strictly verifying tag
    /// balance (with HTML5 optional closing tags permitted strictly inside an
    /// open quote container). Returns `nil` on malformed or unbalanced markup.
    private static func parseTopLevelNodes(
        in html: String,
        sliceRange: Range<String.Index>
    ) -> [TopLevelNode]? {
        var nodes: [TopLevelNode] = []
        var stack: [TagToken] = []
        var quoteContainerDepth = 0
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

        func popStackElement() -> TagToken? {
            guard let popped = stack.popLast() else { return nil }
            if isQuoteContainerOpeningTag(popped) {
                quoteContainerDepth = max(0, quoteContainerDepth - 1)
            }
            return popped
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
            guard firstAfterLT == "/" || (firstAfterLT.isASCII && firstAfterLT.isLetter) else {
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

            // Raw-text elements (<style>, <script>): scan linearly to matching close tag.
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
                // Inside quoted HTML, implicitly close optional HTML5 elements
                // (e.g. <td>, <tr>, <tbody>, <li>, <p>) before matching an ancestor.
                if quoteContainerDepth > 0 {
                    while let top = stack.last,
                          top.name != token.name,
                          canImplicitlyClose(openTag: top.name, onClosingTag: token.name) {
                        _ = popStackElement()
                    }
                }
                guard let open = popStackElement(), open.name == token.name else {
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
                if quoteContainerDepth > 0 {
                    while let top = stack.last,
                          canImplicitlyClose(openTag: top.name, onOpeningTag: token.name) {
                        _ = popStackElement()
                    }
                }
                if stack.isEmpty {
                    nodes.append(.voidTag(token))
                }
            } else {
                if quoteContainerDepth > 0 {
                    while let top = stack.last,
                          canImplicitlyClose(openTag: top.name, onOpeningTag: token.name) {
                        _ = popStackElement()
                    }
                }
                stack.append(token)
                if isQuoteContainerOpeningTag(token) {
                    quoteContainerDepth += 1
                }
            }
            cursor = nextIndex
        }

        guard stack.isEmpty else {
            return nil
        }
        flushText(upTo: sliceRange.upperBound)
        return nodes
    }

    /// HTML5 optional-close rules when a new opening tag arrives inside quoted HTML.
    private static func canImplicitlyClose(openTag: String, onOpeningTag nextTag: String) -> Bool {
        switch openTag {
        case "p":
            return pClosingBlockElements.contains(nextTag)
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
        case "colgroup":
            return nextTag == "thead" || nextTag == "tbody" || nextTag == "tfoot"
                || nextTag == "tr" || nextTag == "caption" || nextTag == "colgroup"
        case "option":
            return nextTag == "option" || nextTag == "optgroup"
        default:
            return false
        }
    }

    /// HTML5 optional-close rules when an ancestor closing tag arrives inside quoted HTML.
    private static func canImplicitlyClose(openTag: String, onClosingTag closingTag: String) -> Bool {
        guard html5OptionalCloseElements.contains(openTag) else { return false }
        switch openTag {
        case "td", "th":
            return closingTag == "tr" || closingTag == "thead" || closingTag == "tbody"
                || closingTag == "tfoot" || closingTag == "table"
        case "tr":
            return closingTag == "thead" || closingTag == "tbody" || closingTag == "tfoot"
                || closingTag == "table"
        case "thead", "tbody", "tfoot", "colgroup":
            return closingTag == "table"
        case "li":
            return closingTag == "ul" || closingTag == "ol" || closingTag == "menu"
        case "dt", "dd":
            return closingTag == "dl"
        case "option":
            return closingTag == "select" || closingTag == "optgroup" || closingTag == "datalist"
        case "p":
            // Per HTML5, </p> may be omitted when the parent element closes
            // (except for <a>, which does not implicitly close <p>).
            return closingTag != "a"
        default:
            return false
        }
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

    /// Scans strictly linearly (O(n)) for a matching `</style>` or `</script>`
    /// end tag inside a raw-text element without calling `findTagCloseIndex`
    /// on non-matching `<` characters.
    private static func findRawTextCloseTag(
        named name: String,
        in html: String,
        from start: String.Index,
        limit: String.Index
    ) -> TagToken? {
        let nameBytes = Array(name.utf8)
        var cursor = start
        while cursor < limit {
            guard let lt = html[cursor ..< limit].firstIndex(of: "<") else {
                return nil
            }
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
            while idx < limit, isASCIIWhitespace(html[idx]) {
                idx = html.index(after: idx)
            }
            if idx < limit, html[idx] == ">" {
                let next = html.index(after: idx)
                let tokenRange = lt ..< next
                return TagToken(
                    name: name,
                    isClosing: true,
                    isSelfClosing: false,
                    range: tokenRange,
                    rawTag: html[tokenRange]
                )
            }
            cursor = idx > lt ? idx : html.index(after: lt)
        }
        return nil
    }

    private static func isASCIIWhitespace(_ ch: Character) -> Bool {
        ch == " " || ch == "\t" || ch == "\n" || ch == "\r" || ch == "\u{0C}"
    }

    // MARK: - Quote & Attribution Recognition

    /// True for opening tags that can establish a quote container scope
    /// (used to scope HTML5 optional closing tag handling).
    private static func isQuoteContainerOpeningTag(_ open: TagToken) -> Bool {
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

    /// True when `node` is an explicit webmail quote container (`.gmail_quote`,
    /// `#divRplyFwdMsg`, etc.) OR a `<blockquote>` that cannot be imported flat
    /// into Brev's editor (has attributes, noncanonical tag casing, nested quotes,
    /// or rich inner markup).
    private static func isComplexOrExplicitQuoteContainer(_ node: TopLevelNode, in html: String) -> Bool {
        guard case .element(let open, let close, _, let innerRange) = node else { return false }
        if open.name == "blockquote" {
            return !isFlatImportableBlockquote(open: open, close: close, innerHTML: html[innerRange])
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

    /// Fallback boundary for a canonical plain `<blockquote>...</blockquote>` that
    /// is immediately preceded by an explicit quote prelude or standalone attribution
    /// element (for example, a styled `<div style="...">On Mon, Ada wrote:</div>`
    /// that prevented flat import). Explicit provider-marked preludes rank ahead of
    /// inferred plain-text attributions.
    private static func fallbackAttributedBlockquoteIndex(
        in nodes: [TopLevelNode],
        html: String
    ) -> Int? {
        var firstInferredAttributionIndex: Int?
        for index in nodes.indices {
            guard isBlockquoteElement(nodes[index]) else { continue }
            var scan = index - 1
            while scan >= 0, isInsignificantSeparator(nodes[scan], in: html) {
                scan -= 1
            }
            guard scan >= 0 else { continue }
            let preceding = nodes[scan]
            if isExplicitQuotePrelude(preceding, isOutlookBoundary: false) {
                return index
            }
            if firstInferredAttributionIndex == nil,
               isStandaloneAttributionElement(preceding, in: html) {
                firstInferredAttributionIndex = index
            }
        }
        return firstInferredAttributionIndex
    }

    /// Matches the exact flat `<blockquote>...</blockquote>` form that
    /// `ComposeDraftBodyRestoration.quoteLinesHTML` imports into editable `> ` lines.
    private static func isFlatImportableBlockquote(
        open: TagToken,
        close: TagToken,
        innerHTML: Substring
    ) -> Bool {
        guard open.rawTag == "<blockquote>", close.rawTag == "</blockquote>" else { return false }
        return !innerHTML.replacingOccurrences(of: "<br>", with: "").contains("<")
    }

    private static func isBlockquoteElement(_ node: TopLevelNode) -> Bool {
        guard case .element(let open, _, _, _) = node else { return false }
        return open.name == "blockquote"
    }

    private static func isOutlookQuoteElement(_ node: TopLevelNode) -> Bool {
        guard case .element(let open, _, _, _) = node, open.name == "div" else { return false }
        let id = attribute("id", in: open.rawTag)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return id.map { quoteContainerIDs.contains($0) } ?? false
    }

    private static func isExplicitQuotePrelude(
        _ node: TopLevelNode,
        isOutlookBoundary: Bool
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

    /// True only when the ENTIRE `<div>`/`<p>` block is a standalone attribution
    /// header (never when the block starts with ordinary reply text before `<br>`).
    private static func isStandaloneAttributionElement(_ node: TopLevelNode, in html: String) -> Bool {
        guard case .element(let open, _, let range, _) = node,
              open.name == "div" || open.name == "p" else {
            return false
        }
        let plain = ComposeQuoteTextPolicy.htmlToPlainText(String(html[range]))
        return looksLikeStandaloneAttributionHeader(plain)
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
        guard looksLikeStandaloneAttributionHeader(decoded) else { return nil }
        var start = lineStart
        while start < trimmedEnd, text[start] == " " || text[start] == "\t" {
            start = text.index(after: start)
        }
        return start
    }

    private static func looksLikeStandaloneAttributionHeader(_ plainText: String) -> Bool {
        let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 300 else { return false }
        let lines = trimmed
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !lines.contains(where: \.isEmpty) else { return false }

        if lines.count == 1 {
            return matchesAttributionLine(lines[0].lowercased())
        }
        // Only treat a 2-line block as one wrapped attribution header when line 1
        // itself starts like a date/attribution lead-in (not an ordinary reply sentence)
        // and does not end with sentence-terminating punctuation.
        if lines.count == 2 {
            let first = lines[0].lowercased()
            let leadIns = ["on ", "den ", "am ", "le ", "el ", "il ", "at "]
            let endsSentence = first.hasSuffix(".") || first.hasSuffix("!") || first.hasSuffix("?")
            guard !endsSentence, leadIns.contains(where: { first.hasPrefix($0) }) else {
                return false
            }
            return matchesAttributionLine("\(first) \(lines[1].lowercased())")
        }
        return false
    }

    private static func matchesAttributionLine(_ normalized: String) -> Bool {
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
        if suffixes.contains(where: { hasWordBoundedSuffix(normalized, suffix: $0) }) {
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

    private static func hasWordBoundedSuffix(_ text: String, suffix: String) -> Bool {
        guard text.hasSuffix(suffix) else { return false }
        let prefixEnd = text.index(text.endIndex, offsetBy: -suffix.count)
        guard prefixEnd > text.startIndex else { return true }
        let charBefore = text[text.index(before: prefixEnd)]
        return !charBefore.isLetter && !charBefore.isNumber
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

    private struct UnwrappedContainer {
        let open: TagToken
        let close: TagToken
        let innerRange: Range<String.Index>
        let direction: String?
    }

    /// Returns the single enclosing plain/direction-only wrapper (`<div>`,
    /// `<div dir="ltr|rtl|auto">`, `<body>`, `<body dir="...">`, or `<html>`).
    private static func singlePlainWrapper(
        in nodes: [TopLevelNode],
        html: String
    ) -> UnwrappedContainer? {
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
              case .element(let open, let close, _, let innerRange) = significant[0],
              open.name == "div" || open.name == "body" || open.name == "html",
              isPlainOrDirectionOnlyTag(open) else {
            return nil
        }
        let dir = attribute("dir", in: open.rawTag)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return UnwrappedContainer(open: open, close: close, innerRange: innerRange, direction: dir)
    }

    private static func isPlainOrDirectionOnlyTag(_ token: TagToken) -> Bool {
        let stripped = String(token.rawTag)
            .replacingOccurrences(
                of: #"(?i)^<\s*(?:div|p|body|html)(?:\s+dir\s*=\s*["'](?:ltr|rtl|auto)["'])?\s*>$"#,
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
