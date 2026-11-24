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
    /// Preserved byte-for-byte quoted HTML tail when a draft contains nested,
    /// styled, or webmail quoted thread markup that the native rich-text editor
    /// should keep intact below the editable reply region.
    let preservedQuotedHTML: String?
    /// Separator HTML (such as `<br><br>` or `<div><br></div>`) that appeared
    /// between the editable prefix and `preservedQuotedHTML` in `originalHTML`.
    let quoteSeparatorHTML: String
    /// Plain-text fallback extracted from `preservedQuotedHTML`.
    let preservedQuotedPlainText: String
    /// Enclosing opening wrapper tags (such as `<div dir="rtl">`) unwrapped during
    /// quote splitting and re-applied on edited save/send.
    let outerWrapperOpenHTML: String
    /// Enclosing closing wrapper tags matching `outerWrapperOpenHTML`.
    let outerWrapperCloseHTML: String
    /// Inherited text direction (`"rtl"`, `"ltr"`, or `"auto"`) from an unwrapped
    /// direction-bearing container, used to preserve directionality in previews.
    let inheritedDirection: String?

    init(
        attributedText: NSAttributedString,
        originalHTML: String,
        initialEditorHTML: String,
        editorFormat: ComposeBodyFormat,
        preservedQuotedHTML: String? = nil,
        quoteSeparatorHTML: String = "",
        preservedQuotedPlainText: String = "",
        outerWrapperOpenHTML: String = "",
        outerWrapperCloseHTML: String = "",
        inheritedDirection: String? = nil
    ) {
        self.attributedText = attributedText
        self.originalHTML = originalHTML
        self.initialEditorHTML = initialEditorHTML
        self.editorFormat = editorFormat
        self.preservedQuotedHTML = preservedQuotedHTML
        self.quoteSeparatorHTML = quoteSeparatorHTML
        self.preservedQuotedPlainText = preservedQuotedPlainText
        self.outerWrapperOpenHTML = outerWrapperOpenHTML
        self.outerWrapperCloseHTML = outerWrapperCloseHTML
        self.inheritedDirection = inheritedDirection
    }

    /// Produces the persisted HTML body for the current editor state.
    ///
    /// - Returns `originalHTML` byte-for-byte when the editable region is untouched.
    /// - Reassembles `editedTopHTML` with `preservedQuotedHTML` intact when edited.
    /// - Returns `nil` when there is no preserved tail and the user edited the body.
    func htmlBodyForSave(
        currentBodyText: String,
        currentBodyHTML: String?,
        editedTopHTML: String
    ) -> String? {
        let isUnedited = currentBodyText == attributedText.string
            && (editorFormat == .plainText || currentBodyHTML == initialEditorHTML)
        if isUnedited {
            return originalHTML
        }
        guard let preservedQuotedHTML else { return nil }
        return Self.reassembledHTML(
            editedTopHTML: editedTopHTML,
            separatorHTML: quoteSeparatorHTML,
            preservedQuotedHTML: preservedQuotedHTML,
            outerWrapperOpenHTML: outerWrapperOpenHTML,
            outerWrapperCloseHTML: outerWrapperCloseHTML
        )
    }

    /// Reassembles serialized top reply HTML with a byte-for-byte preserved quote tail,
    /// preserving any enclosing direction-bearing wrapper tags.
    static func reassembledHTML(
        editedTopHTML: String,
        separatorHTML: String,
        preservedQuotedHTML: String,
        outerWrapperOpenHTML: String = "",
        outerWrapperCloseHTML: String = ""
    ) -> String {
        let inner: String
        if editedTopHTML.isEmpty {
            inner = preservedQuotedHTML
        } else {
            let joiner: String
            if !separatorHTML.isEmpty {
                joiner = separatorHTML
            } else if editedTopHTML.hasSuffix("<br>") {
                joiner = "<br>"
            } else {
                joiner = "<br><br>"
            }
            inner = editedTopHTML + joiner + preservedQuotedHTML
        }
        return outerWrapperOpenHTML + inner + outerWrapperCloseHTML
    }

    /// Combines edited top plain text with extracted quoted plain text without
    /// modifying the preserved HTML tail.
    func combinedPlainText(editedTopPlainText: String) -> String {
        guard !preservedQuotedPlainText.isEmpty else {
            return editedTopPlainText
        }
        let trimmedTop = editedTopPlainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTop.isEmpty else {
            return preservedQuotedPlainText
        }
        return "\(editedTopPlainText)\n\n\(preservedQuotedPlainText)"
    }
}

enum ComposeDraftBodyRestoration {
    @MainActor
    static func prepare(draft: Draft, format: ComposeBodyFormat) async throws -> ComposeRestoredBody {
        try Task.checkCancellation()
        let html = draft.htmlBody
        // No resource-bearing or lossy markup reaches the native HTML parser.
        guard html.utf8.count <= 1_048_576 else {
            throw MailBackendError.backendSpecific(message: unsupportedMessage)
        }

        let importable: ImportableBody
        let preservedQuotedHTML: String?
        let quoteSeparatorHTML: String
        let outerWrapperOpenHTML: String
        let outerWrapperCloseHTML: String
        let inheritedDirection: String?
        if let flat = importableBody(from: html) {
            importable = flat
            preservedQuotedHTML = nil
            quoteSeparatorHTML = ""
            outerWrapperOpenHTML = ""
            outerWrapperCloseHTML = ""
            inheritedDirection = nil
        } else if let matched = ComposeDraftQuoteSplitter.candidateSplits(html).lazy.compactMap({ split
                -> (ImportableBody, ComposeDraftQuoteSplitter.SplitResult)? in
            let trimmedPrefix = split.editablePrefixHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedPrefix.isEmpty {
                return (ImportableBody(html: "", listLines: [:]), split)
            }
            guard let prefixImportable = importableBody(from: split.editablePrefixHTML) else {
                return nil
            }
            return (prefixImportable, split)
        }).first {
            importable = matched.0
            preservedQuotedHTML = matched.1.preservedQuotedHTML
            quoteSeparatorHTML = matched.1.quoteSeparatorHTML
            outerWrapperOpenHTML = matched.1.outerWrapperOpenHTML
            outerWrapperCloseHTML = matched.1.outerWrapperCloseHTML
            inheritedDirection = matched.1.inheritedDirection
        } else {
            throw MailBackendError.backendSpecific(message: unsupportedMessage)
        }

        let attributed: NSAttributedString
        if importable.html.isEmpty {
            attributed = NSAttributedString(string: "")
        } else {
            guard let imported = await attributedText(for: importable) else {
                throw MailBackendError.backendSpecific(message: unsupportedMessage)
            }
            attributed = imported
        }
        try Task.checkCancellation()
        let serialized = ComposeRichTextHTMLSerializer.html(from: attributed)
        if !serialized.isEmpty {
            guard let importableAgain = importableBody(from: serialized),
                  let importedAgain = await attributedText(for: importableAgain),
                  semantics(of: attributed).isEqual(to: semantics(of: importedAgain)) else {
                throw MailBackendError.backendSpecific(message: unsupportedMessage)
            }
        } else if !attributed.string.isEmpty {
            throw MailBackendError.backendSpecific(message: unsupportedMessage)
        }
        try Task.checkCancellation()
        let requiresRichText = serialized.range(of: #"<(strong|em|u|a|ul|ol)\b"#, options: .regularExpression) != nil
            || preservedQuotedHTML != nil
        guard format != .plainText || !requiresRichText else {
            throw MailBackendError.backendSpecific(message: unsupportedMessage)
        }
        let preservedQuotedPlainText = preservedQuotedHTML.map(ComposeQuoteTextPolicy.htmlToPlainText) ?? ""
        return ComposeRestoredBody(
            attributedText: attributed,
            originalHTML: html,
            initialEditorHTML: serialized,
            editorFormat: format,
            preservedQuotedHTML: preservedQuotedHTML,
            quoteSeparatorHTML: quoteSeparatorHTML,
            preservedQuotedPlainText: preservedQuotedPlainText,
            outerWrapperOpenHTML: outerWrapperOpenHTML,
            outerWrapperCloseHTML: outerWrapperCloseHTML,
            inheritedDirection: inheritedDirection
        )
    }

    /// A stored body reduced to text, inline formatting and `<br>`, plus the
    /// lines that Brev's own list commands marked as list items.
    struct ImportableBody {
        let html: String
        /// Zero-based line index to the list marker that line carries.
        let listLines: [Int: NSTextList.MarkerFormat]
    }

    /// Reduces a stored body to an `ImportableBody`, or returns nil when it
    /// holds markup that restoration cannot carry (ADR-0093).
    static func importableBody(from html: String) -> ImportableBody? {
        let withoutDirection = html.replacingOccurrences(
            of: #"(?i)<(p|div)\s+dir="(?:ltr|rtl|auto)"\s*>"#,
            with: "<$1>",
            options: .regularExpression
        )
        guard ComposeHTMLBodyPolicy.richHTML(fromEditorHTML: withoutDirection) == withoutDirection,
              withoutDirection.range(of: #"(?i)<\s*/?\s*img\b"#, options: .regularExpression) == nil,
              let quoted = quoteLinesHTML(from: withoutDirection),
              let lines = lineStructureHTML(from: quoted),
              let listed = listLinesHTML(from: lines),
              listed.html.range(of: #"(?i)<\s*/?\s*(ul|ol|li)\b"#, options: .regularExpression) == nil else {
            return nil
        }
        return listed
    }

    /// Imports the reduced HTML and gives list lines the editor's list style.
    @MainActor
    private static func attributedText(for body: ImportableBody) async -> NSAttributedString? {
        guard let imported = await MessageHTMLImporter.importAttributedHTML(body.html) else { return nil }
        let text = NSMutableAttributedString(imported)
        guard !body.listLines.isEmpty else { return text }
        let string = text.string as NSString
        var lineIndex = 0
        var location = 0
        while location < string.length {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            if let marker = body.listLines[lineIndex] {
                let existing = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
                    as? NSParagraphStyle
                let style = existing.flatMap { $0.mutableCopy() as? NSMutableParagraphStyle }
                    ?? NSMutableParagraphStyle()
                // The same style the editor's list commands apply.
                style.textLists = [NSTextList(markerFormat: marker, options: 0)]
                style.headIndent = 24
                style.firstLineHeadIndent = 8
                text.addAttribute(.paragraphStyle, value: style, range: range)
            }
            lineIndex += 1
            location = range.upperBound
        }
        return lineIndex > (body.listLines.keys.max() ?? -1) ? text : nil
    }

    /// Turns the flat `<ul>`/`<ol>` blocks the serializer writes into lines,
    /// recording which lines are list items. Anything nested or attributed
    /// stays as markup, which the caller then refuses.
    private static func listLinesHTML(from html: String) -> ImportableBody? {
        guard let regex = try? NSRegularExpression(pattern: "<(ul|ol)>(.*?)</\\1>") else { return nil }
        var result = ""
        var listLines: [Int: NSTextList.MarkerFormat] = [:]
        var last = html.startIndex
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let whole = Range(match.range, in: html),
                  let tag = Range(match.range(at: 1), in: html),
                  let inner = Range(match.range(at: 2), in: html) else { return nil }
            let body = html[inner]
            guard body.hasPrefix("<li>"), body.hasSuffix("</li>") else { return nil }
            let items = body.dropFirst(4).dropLast(5).components(separatedBy: "</li><li>")
            let blockTags = #"(?i)<\s*/?\s*(ul|ol|li|br|p|div|blockquote)\b"#
            guard items.allSatisfy({ $0.range(of: blockTags, options: .regularExpression) == nil }) else {
                return nil
            }
            result += html[last ..< whole.lowerBound]
            if !result.isEmpty, !result.hasSuffix("<br>") { result += "<br>" }
            let firstLine = result.components(separatedBy: "<br>").count - 1
            let marker: NSTextList.MarkerFormat = html[tag] == "ol" ? .decimal : .disc
            for offset in items.indices {
                listLines[firstLine + offset] = marker
            }
            result += items.joined(separator: "<br>")
            last = whole.upperBound
            if last < html.endIndex, !html[last...].hasPrefix("<br>") { result += "<br>" }
        }
        result += html[last...]
        return ImportableBody(html: result, listLines: listLines)
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
            // List objects compare by identity; compare their marker instead.
            if let style = attributes[.paragraphStyle] as? NSParagraphStyle,
               let plain = style.mutableCopy() as? NSMutableParagraphStyle {
                semantic[NSAttributedString.Key("list")] = style.textLists.first?.markerFormat.rawValue
                plain.textLists = []
                semantic[.paragraphStyle] = plain
            } else {
                semantic[.paragraphStyle] = attributes[.paragraphStyle]
            }
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
