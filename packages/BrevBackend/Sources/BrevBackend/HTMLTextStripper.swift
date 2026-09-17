// MIT License — Copyright (c) 2026 Brev Contributors

import Foundation

/// Pure-string HTML markup stripping shared by snippet normalization and the
/// attachment text extractor. Never invokes a document importer, so it can be
/// applied to untrusted bytes without any chance of a remote subresource load.
enum HTMLTextStripper {
    /// Removes style/script content, comments, tags, and a final tag cut in
    /// half by a byte-limited read, leaving the text content behind.
    static func stripMarkup(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"(?is)<(style|script)\b[^>]*>.*?</\1\s*>"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?is)<(style|script)\b[^>]*>.*\z"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?s)<!--.*?-->"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(
                of: #"(?s)<[^>]*\z"#,
                with: " ",
                options: .regularExpression
            )
    }

    /// Replaces the common named entities plus numeric character references.
    static func unescapingEntities(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
        result = replaceNumericEntities(in: result, pattern: #"&#x([0-9A-Fa-f]{1,6});"#, radix: 16)
        result = replaceNumericEntities(in: result, pattern: #"&#([0-9]{1,7});"#, radix: 10)
        return result
    }

    /// Decodes untrusted HTML bytes (UTF-8, then the declared `<meta>` charset,
    /// then Latin-1) and returns the visible text: markup, style and script
    /// content removed, entities unescaped, whitespace collapsed.
    static func visibleText(from data: Data) -> String {
        let decoded = decodeHTML(data)
        let stripped = stripMarkup(decoded)
        let unescaped = unescapingEntities(stripped)
        return unescaped
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTML(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        // Latin-1 decoding is lossless, so it can carry a declared charset.
        let latin1 = String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
        if let declared = declaredCharset(in: latin1),
           let decoded = String(data: data, encoding: declared) {
            return decoded
        }
        return latin1
    }

    private static func declaredCharset(in text: String) -> String.Encoding? {
        let headEnd = text.range(of: "</head>", options: .caseInsensitive)?.lowerBound
            ?? text.index(text.startIndex, offsetBy: min(text.count, 8192), limitedBy: text.endIndex)
            ?? text.endIndex
        let head = String(text[text.startIndex ..< headEnd])
        guard let regex = try? NSRegularExpression(
            pattern: #"charset\s*=\s*"?([A-Za-z0-9._-]+)"#,
            options: .caseInsensitive
        ),
            let match = regex.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)),
            let nameRange = Range(match.range(at: 1), in: head) else { return nil }
        switch head[nameRange].lowercased() {
        case "utf-8", "utf8": return .utf8
        case "iso-8859-1", "latin1", "latin-1": return .isoLatin1
        case "windows-1252", "cp1252": return .windowsCP1252
        case "us-ascii", "ascii": return .ascii
        case "utf-16", "utf-16le": return .utf16LittleEndian
        case "utf-16be": return .utf16BigEndian
        default: return nil
        }
    }

    private static func replaceNumericEntities(in text: String, pattern: String, radix: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = ""
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text),
                  let valueRange = Range(match.range(at: 1), in: text),
                  let scalarValue = UInt32(text[valueRange], radix: radix),
                  let scalar = Unicode.Scalar(scalarValue) else { continue }
            result += text[cursor ..< range.lowerBound]
            result.unicodeScalars.append(scalar)
            cursor = range.upperBound
        }
        guard cursor > text.startIndex else { return text }
        result += text[cursor...]
        return result
    }
}
