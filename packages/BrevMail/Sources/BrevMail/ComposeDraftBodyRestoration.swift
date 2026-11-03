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
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ComposeRestoredBody {
    let attributedText: NSAttributedString
    let originalHTML: String
    let initialEditorHTML: String
    let editorFormat: ComposeBodyFormat
}

enum ComposeDraftBodyRestoration {
    @MainActor
    static func prepare(draft: Draft, format: ComposeBodyFormat) async throws -> ComposeRestoredBody {
        try Task.checkCancellation()
        let html = draft.htmlBody
        // No resource-bearing or lossy markup reaches the native HTML parser.
        guard html.utf8.count <= 1_048_576, let importable = importableHTML(from: html) else {
            throw MailBackendError.backendSpecific(message: unsupportedMessage)
        }
        let attributed: NSAttributedString
        if importable.isEmpty {
            attributed = NSAttributedString(string: "")
        } else {
            guard let imported = await MessageHTMLImporter.importAttributedHTML(importable) else {
                throw MailBackendError.backendSpecific(message: unsupportedMessage)
            }
            attributed = NSAttributedString(imported)
        }
        try Task.checkCancellation()
        let serialized = ComposeRichTextHTMLSerializer.html(from: attributed)
        if !serialized.isEmpty {
            guard let importableAgain = importableHTML(from: serialized),
                  let importedAgain = await MessageHTMLImporter.importAttributedHTML(importableAgain),
                  semantics(of: attributed).isEqual(to: semantics(of: NSAttributedString(importedAgain))) else {
                throw MailBackendError.backendSpecific(message: unsupportedMessage)
            }
        } else if !attributed.string.isEmpty {
            throw MailBackendError.backendSpecific(message: unsupportedMessage)
        }
        try Task.checkCancellation()
        let requiresRichText = serialized.range(of: #"<(strong|em|u|a)\b"#, options: .regularExpression) != nil
        guard format != .plainText || !requiresRichText else {
            throw MailBackendError.backendSpecific(message: unsupportedMessage)
        }
        return ComposeRestoredBody(
            attributedText: attributed,
            originalHTML: html,
            initialEditorHTML: serialized,
            editorFormat: format
        )
    }

    /// Reduces a stored body to text, inline formatting and `<br>`, or returns
    /// nil when it holds markup that restoration cannot carry (ADR-0093).
    static func importableHTML(from html: String) -> String? {
        let withoutDirection = html.replacingOccurrences(
            of: #"(?i)<(p|div)\s+dir="(?:ltr|rtl|auto)"\s*>"#,
            with: "<$1>",
            options: .regularExpression
        )
        guard ComposeHTMLBodyPolicy.richHTML(fromEditorHTML: withoutDirection) == withoutDirection,
              withoutDirection.range(of: #"(?i)<\s*/?\s*(img|ul|ol|li)\b"#, options: .regularExpression) == nil,
              let quoted = quoteLinesHTML(from: withoutDirection) else {
            return nil
        }
        return lineStructureHTML(from: quoted)
    }

    /// Turns flat blockquotes into `> ` lines, the form the editor holds them in.
    private static func quoteLinesHTML(from html: String) -> String? {
        var result = ""
        var remainder = Substring(html)
        while let open = remainder.range(of: "<blockquote>") {
            guard let close = remainder[open.upperBound...].range(of: "</blockquote>") else { return nil }
            let inner = remainder[open.upperBound ..< close.lowerBound]
            guard !inner.replacingOccurrences(of: "<br>", with: "").contains("<") else { return nil }
            result += remainder[..<open.lowerBound]
            if !result.isEmpty, !result.hasSuffix("<br>") { result += "<br>" }
            result += inner.components(separatedBy: "<br>")
                .map { $0.isEmpty ? "&gt;" : "&gt; \($0)" }
                .joined(separator: "<br>")
            remainder = remainder[close.upperBound...]
            if !remainder.isEmpty, !remainder.hasPrefix("<br>") { result += "<br>" }
        }
        result += remainder
        return result.contains("blockquote>") ? nil : result
    }

    /// Replaces unnested `<p>` and `<div>` with the line breaks they render as.
    private static func lineStructureHTML(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<(/?)(p|div)>") else { return nil }
        var result = ""
        var last = html.startIndex
        var openBlock: (name: Substring, start: Int)?
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let whole = Range(match.range, in: html),
                  let slash = Range(match.range(at: 1), in: html),
                  let name = Range(match.range(at: 2), in: html) else { return nil }
            result += html[last ..< whole.lowerBound]
            last = whole.upperBound
            if html[slash].isEmpty {
                guard openBlock == nil else { return nil }
                if !result.isEmpty, !result.hasSuffix("<br>") { result += "<br>" }
                openBlock = (html[name], result.utf8.count)
            } else {
                guard let block = openBlock, block.name == html[name] else { return nil }
                openBlock = nil
                if result.utf8.count == block.start || !result.hasSuffix("<br>") { result += "<br>" }
            }
        }
        guard openBlock == nil else { return nil }
        let endsInBlock = html.hasSuffix("</p>") || html.hasSuffix("</div>")
        result += html[last...]
        return endsInBlock && result.hasSuffix("<br>") ? String(result.dropLast(4)) : result
    }

    private static func semantics(of attributed: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(string: attributed.string)
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            var semantic: [NSAttributedString.Key: Any] = [:]
            #if os(macOS)
            if let font = attributes[.font] as? NSFont {
                let traits = NSFontManager.shared.traits(of: font)
                semantic[NSAttributedString.Key("bold")] = traits.contains(.boldFontMask)
                semantic[NSAttributedString.Key("italic")] = traits.contains(.italicFontMask)
            }
            #else
            if let font = attributes[.font] as? UIFont {
                let traits = font.fontDescriptor.symbolicTraits
                semantic[NSAttributedString.Key("bold")] = traits.contains(.traitBold)
                semantic[NSAttributedString.Key("italic")] = traits.contains(.traitItalic)
            }
            #endif
            semantic[.underlineStyle] = attributes[.underlineStyle]
            semantic[.paragraphStyle] = attributes[.paragraphStyle]
            if let url = attributes[.link] as? URL {
                semantic[.link] = url.absoluteString
            } else {
                semantic[.link] = attributes[.link]
            }
            result.setAttributes(semantic, range: range)
        }
        return result
    }

    static var unsupportedMessage: String {
        String(
            localized: "This draft's formatting cannot be restored safely in the current editor mode. Close this window to leave the original unchanged.",
            bundle: .module
        )
    }
}
