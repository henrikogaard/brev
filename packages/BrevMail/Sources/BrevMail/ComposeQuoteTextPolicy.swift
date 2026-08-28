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

    /// Strips style/script/comments/tags and decodes common entities.
    ///
    /// Block-level tags and `<br>` become newlines; other tags become spaces so
    /// adjacent labels like `</a><a>` do not concatenate into one word.
    static func htmlToPlainText(_ html: String) -> String {
        var text = html
        for pattern in [
            "(?is)<style[^>]*>.*?</style>",
            "(?is)<script[^>]*>.*?</script>",
            "(?s)<!--.*?-->",
        ] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        // Soft breaks and horizontal rules become hard line breaks.
        text = text.replacingOccurrences(
            of: #"(?i)<br\s*/?>"#,
            with: "\n",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?i)<hr\b[^>]*>"#,
            with: "\n",
            options: .regularExpression
        )

        // Block boundaries become newlines before tags are removed.
        text = text.replacingOccurrences(
            of: #"(?i)</?(?:address|article|aside|blockquote|div|dl|dt|dd|fieldset|figcaption|figure|footer|form|h[1-6]|header|li|main|nav|ol|p|pre|section|table|tbody|td|tfoot|th|thead|tr|ul)\b[^>]*>"#,
            with: "\n",
            options: .regularExpression
        )

        // Remaining tags (inline links, spans, formatting) become spaces.
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

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

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
