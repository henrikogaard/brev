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
import Foundation

/// Resolves human-readable quote text for reply/forward compose.
///
/// Listing snippets come from raw `BODY.PEEK[TEXT]` and are often still
/// base64/quoted-printable. Prefer a fully decoded `MessageBody` instead.
enum ComposeQuoteTextPolicy {
    /// Prefer decoded plain text, then stripped HTML, then the listing snippet.
    static func quoteText(
        body: MessageBody?,
        fallbackSnippet: String
    ) -> String {
        if let plainText = normalized(body?.plainText), !plainText.isEmpty {
            return plainText
        }
        if let html = body?.html, !html.isEmpty {
            let stripped = htmlToPlainText(html)
            if !stripped.isEmpty {
                return stripped
            }
        }
        return fallbackSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let blockElements: Set<String> = [
        "address", "article", "aside", "blockquote", "br", "div", "dl", "dt", "dd",
        "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3",
        "h4", "h5", "h6", "header", "hr", "li", "main", "nav", "ol", "p", "pre",
        "section", "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul"
    ]

    /// Strips style/script/comments/tags (respecting quoted attribute values
    /// containing `>`) and decodes common entities.
    ///
    /// Block-level tags and `<br>` become newlines; other tags become spaces so
    /// adjacent labels like `</a><a>` do not concatenate into one word.
    static func htmlToPlainText(_ html: String) -> String {
        var text = scanAndReplaceTags(in: html)

        for (entity, replacement) in [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " "),
        ] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { line in
                line
                    .split(whereSeparator: { $0.isWhitespace })
                    .joined(separator: " ")
            }

        var collapsed: [String] = []
        for line in lines {
            if line.isEmpty {
                if collapsed.last?.isEmpty == false {
                    collapsed.append("")
                }
            } else {
                collapsed.append(line)
            }
        }
        while collapsed.last?.isEmpty == true {
            collapsed.removeLast()
        }
        return collapsed.joined(separator: "\n")
    }

    private static func scanAndReplaceTags(in html: String) -> String {
        var output = ""
        output.reserveCapacity(html.count)
        var cursor = html.startIndex
        let end = html.endIndex

        while cursor < end {
            guard let lt = html[cursor ..< end].firstIndex(of: "<") else {
                output.append(contentsOf: html[cursor ..< end])
                break
            }
            if cursor < lt {
                output.append(contentsOf: html[cursor ..< lt])
            }
            let remaining = html[lt ..< end]

            if remaining.hasPrefix("<!--") {
                let afterOpen = html.index(lt, offsetBy: 4)
                output.append(" ")
                if let closeRange = html[afterOpen ..< end].range(of: "-->") {
                    cursor = closeRange.upperBound
                } else {
                    break
                }
                continue
            }

            if remaining.hasPrefix("<!") || remaining.hasPrefix("<?") {
                output.append(" ")
                if let gt = findTagClose(in: html, from: lt, limit: end) {
                    cursor = html.index(after: gt)
                } else {
                    break
                }
                continue
            }

            let afterLT = html.index(after: lt)
            guard afterLT < end else {
                output.append("<")
                break
            }
            let nextChar = html[afterLT]
            guard nextChar == "/" || (nextChar.isASCII && nextChar.isLetter) else {
                output.append("<")
                cursor = afterLT
                continue
            }

            guard let gt = findTagClose(in: html, from: lt, limit: end) else {
                output.append(contentsOf: html[lt ..< end])
                break
            }
            let nextIndex = html.index(after: gt)
            let (tagName, isClosing) = parseTagName(in: html[lt ..< nextIndex])

            if !isClosing, tagName == "style" || tagName == "script" {
                output.append(" ")
                if let closeEnd = findRawTextCloseEnd(named: tagName, in: html, from: nextIndex, limit: end) {
                    cursor = closeEnd
                } else {
                    break
                }
                continue
            }

            if blockElements.contains(tagName) {
                output.append("\n")
            } else {
                output.append(" ")
            }
            cursor = nextIndex
        }
        return output
    }

    private static func findTagClose(
        in html: String,
        from lt: String.Index,
        limit: String.Index
    ) -> String.Index? {
        var idx = html.index(after: lt)
        var quote: Character?
        while idx < limit {
            let ch = html[idx]
            if let activeQuote = quote {
                if ch == activeQuote {
                    quote = nil
                }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == ">" {
                return idx
            }
            idx = html.index(after: idx)
        }
        return nil
    }

    private static func parseTagName(in rawTag: Substring) -> (name: String, isClosing: Bool) {
        let inner = rawTag.dropFirst().dropLast()
        var idx = inner.startIndex
        while idx < inner.endIndex, inner[idx].isWhitespace {
            idx = inner.index(after: idx)
        }
        var isClosing = false
        if idx < inner.endIndex, inner[idx] == "/" {
            isClosing = true
            idx = inner.index(after: idx)
            while idx < inner.endIndex, inner[idx].isWhitespace {
                idx = inner.index(after: idx)
            }
        }
        let nameStart = idx
        while idx < inner.endIndex,
              let ascii = inner[idx].asciiValue,
              (ascii >= 65 && ascii <= 90)
              || (ascii >= 97 && ascii <= 122)
              || (ascii >= 48 && ascii <= 57) {
            idx = inner.index(after: idx)
        }
        return (String(inner[nameStart ..< idx]).lowercased(), isClosing)
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
            while idx < limit, html[idx] == " " || html[idx] == "\t" || html[idx] == "\n" || html[idx] == "\r" {
                idx = html.index(after: idx)
            }
            if idx < limit, html[idx] == ">" {
                return html.index(after: idx)
            }
            cursor = idx > lt ? idx : html.index(after: lt)
        }
        return nil
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
