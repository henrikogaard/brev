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

/// Builds portable, deterministic print output (plain text or safe,
/// self-contained HTML) for one or more messages. Used by both the
/// macOS NSPrint renderer and the iOS UIKit print driver so print
/// content stays identical across platforms. Remote content is never
/// referenced — HTML bodies are reduced to escaped text.
public enum MailPrintDocument {
    public typealias PrintableMessage = (header: MessageHeader, body: MessageBody?)

    /// A deterministic plain-text rendering of the messages.
    public static func plainText(messages: [PrintableMessage]) -> String {
        messages.enumerated().map { index, message in
            let separator = index > 0 ? "\n\(String(repeating: "-", count: 72))\n\n" : ""
            return separator + plainTextBlock(message)
        }.joined()
    }

    /// A self-contained HTML rendering (escaped body, inline minimal CSS,
    /// no external resources) suitable for `UIMarkupTextPrintFormatter`.
    public static func html(messages: [PrintableMessage]) -> String {
        let style = MessageBodyStyle.resolve(
            theme: .brevPaper,
            fontFamily: .system,
            textSize: .medium,
            renderingMode: .original,
            bodyInsetPoints: 44
        )
        let bodyBlocks = messages.enumerated().map { index, message -> String in
            let rule = index > 0 ? "<hr/>" : ""
            return rule + htmlBlock(message)
        }.joined()
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"/>\
        <style>\(style.documentCSS)\
        h1{font-size:1.45em;margin:0 0 8px}\
        .meta{color:\(style.mutedTextColorCSS);font-size:.92em}\
        pre{white-space:pre-wrap;font:inherit;margin:0;background:transparent}</style>\
        </head><body>\(bodyBlocks)</body></html>
        """
    }

    // MARK: - Private plain-text helpers

    private static func plainTextBlock(_ message: PrintableMessage) -> String {
        let h = message.header
        var lines = [h.subject.isEmpty ? "(No subject)" : h.subject]
        lines.append("From: \(correspondent(h.from))")
        if !h.to.isEmpty {
            lines.append("To: \(h.to.map(correspondent).joined(separator: ", "))")
        }
        if !h.cc.isEmpty {
            lines.append("Cc: \(h.cc.map(correspondent).joined(separator: ", "))")
        }
        lines.append("Date: \(dateFormatter.string(from: h.date))")
        lines.append("")
        lines.append(bodyText(message.body))
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Private HTML helpers

    private static func htmlBlock(_ message: PrintableMessage) -> String {
        let h = message.header
        let subject = escape(h.subject.isEmpty ? "(No subject)" : h.subject)
        var meta = "From: \(escape(correspondent(h.from)))<br/>"
        if !h.to.isEmpty {
            meta += "To: \(escape(h.to.map(correspondent).joined(separator: ", ")))<br/>"
        }
        if !h.cc.isEmpty {
            meta += "Cc: \(escape(h.cc.map(correspondent).joined(separator: ", ")))<br/>"
        }
        meta += "Date: \(escape(dateFormatter.string(from: h.date)))"
        return "<h1>\(subject)</h1><div class=\"meta\">\(meta)</div><pre>\(escape(bodyText(message.body)))</pre>"
    }

    // MARK: - Shared helpers

    /// Prefers the HTML body (matching the reader) and reduces it to
    /// plain text without invoking WebKit, keeping output deterministic
    /// and remote-content-free. Falls back to `plainText` when HTML is absent.
    static func bodyText(_ body: MessageBody?) -> String {
        if let html = body?.html, !html.isEmpty { return htmlToPlainText(html) }
        if let plainText = body?.plainText, !plainText.isEmpty { return plainText }
        return ""
    }

    /// Strips `<style>` and `<script>` blocks first so their content never
    /// leaks into the output, then removes all remaining tags, then decodes
    /// common HTML entities.
    static func htmlToPlainText(_ html: String) -> String {
        var text = html
        for pattern in [
            "(?is)<style[^>]*>.*?</style>",
            "(?is)<script[^>]*>.*?</script>",
            "(?s)<!--.*?-->",
        ] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
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
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func correspondent(_ c: Correspondent) -> String {
        if let name = c.name, !name.isEmpty { return "\(name) <\(c.email)>" }
        return c.email
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
