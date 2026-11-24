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
    static func prepare(
        draft: Draft,
        attachments: [MIMEMessageAttachment] = [],
        format: ComposeBodyFormat
    ) async throws -> ComposeRestoredBody {
        try Task.checkCancellation()
        let html = draft.htmlBody
        // No resource-bearing or lossy markup reaches the native HTML parser.
        guard html.utf8.count <= 1_048_576 else {
            throw MailBackendError.backendSpecific(message: unsupportedMessage)
        }

        let inlineMap = inlineAttachmentLookup(from: attachments)
        let attributed: NSAttributedString
        let preservedQuotedHTML: String?
        let quoteSeparatorHTML: String
        let outerWrapperOpenHTML: String
        let outerWrapperCloseHTML: String
        let inheritedDirection: String?

        if let flat = importEditableHTML(html, inlineAttachments: inlineMap) {
            attributed = flat
            preservedQuotedHTML = nil
            quoteSeparatorHTML = ""
            outerWrapperOpenHTML = ""
            outerWrapperCloseHTML = ""
            inheritedDirection = nil
        } else if let result = ComposeDraftQuoteSplitter.firstSplit(
            in: html,
            matchPrefix: { prefix -> NSAttributedString? in
                let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedPrefix.isEmpty {
                    return NSAttributedString(string: "")
                }
                return importEditableHTML(prefix, inlineAttachments: inlineMap)
            }
        ) {
            attributed = result.matched
            preservedQuotedHTML = result.split.preservedQuotedHTML
            quoteSeparatorHTML = result.split.quoteSeparatorHTML
            outerWrapperOpenHTML = result.split.outerWrapperOpenHTML
            outerWrapperCloseHTML = result.split.outerWrapperCloseHTML
            inheritedDirection = result.split.inheritedDirection
        } else {
            throw MailBackendError.backendSpecific(message: unsupportedMessage)
        }

        try Task.checkCancellation()
        let serialized = ComposeRichTextHTMLSerializer.html(from: attributed)
        if !serialized.isEmpty {
            guard let importedAgain = importEditableHTML(serialized, inlineAttachments: inlineMap),
                  semantics(of: attributed).isEqual(to: semantics(of: importedAgain)) else {
                throw MailBackendError.backendSpecific(message: unsupportedMessage)
            }
        } else if !attributed.string.isEmpty {
            throw MailBackendError.backendSpecific(message: unsupportedMessage)
        }
        try Task.checkCancellation()
        let requiresRichText = serialized.range(
            of: #"<(strong|em|u|s|a|ul|ol|h[1-3]|code|pre|table|img)\b"#,
            options: .regularExpression
        ) != nil || preservedQuotedHTML != nil
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

    /// Parses an editable HTML body strictly into an `NSAttributedString`, failing
    /// closed (`nil`) on any unsupported tag, attribute, nesting, or unbacked `cid:`.
    private static func importEditableHTML(
        _ html: String,
        inlineAttachments: [String: MIMEMessageAttachment]
    ) -> NSAttributedString? {
        if html.isEmpty {
            return NSAttributedString(string: "")
        }
        return ComposeRichHTMLAttributedBuilder.attributedString(
            from: html,
            inlineAttachments: inlineAttachments,
            style: .default(),
            strict: true
        )
    }

    private static func inlineAttachmentLookup(
        from attachments: [MIMEMessageAttachment]
    ) -> [String: MIMEMessageAttachment] {
        var lookup: [String: MIMEMessageAttachment] = [:]
        for attachment in attachments where attachment.isInline {
            guard let rawCID = attachment.contentID else { continue }
            let normalized = ComposeInlineImageData.normalizedContentID(rawCID)
            guard !normalized.isEmpty, lookup[normalized] == nil else { continue }
            lookup[normalized] = attachment
        }
        return lookup
    }

    private static func semantics(of attributed: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(string: attributed.string)
        var codeBlockOrder: [String: Int] = [:]
        var tableOrder: [String: Int] = [:]
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            var semantic: [NSAttributedString.Key: Any] = [:]
            let isHeading = attributes[ComposeRichTextAttribute.headingLevel] != nil
            let isHeaderCell = (attributes[ComposeRichTextAttribute.tableCell] as? ComposeTableCellMetadata)?
                .isHeader == true
            #if os(macOS)
            if let font = attributes[.font] as? NSFont {
                let traits = NSFontManager.shared.traits(of: font)
                semantic[NSAttributedString.Key("bold")] = (isHeading || isHeaderCell)
                    ? false
                    : traits.contains(.boldFontMask)
                semantic[NSAttributedString.Key("italic")] = traits.contains(.italicFontMask)
            }
            #else
            if let font = attributes[.font] as? UIFont {
                let traits = font.fontDescriptor.symbolicTraits
                semantic[NSAttributedString.Key("bold")] = (isHeading || isHeaderCell)
                    ? false
                    : traits.contains(.traitBold)
                semantic[NSAttributedString.Key("italic")] = traits.contains(.traitItalic)
            }
            #endif
            semantic[.underlineStyle] = attributes[.underlineStyle]
            semantic[.strikethroughStyle] = attributes[.strikethroughStyle]
            semantic[ComposeRichTextAttribute.inlineCode] = attributes[ComposeRichTextAttribute.inlineCode]
            semantic[ComposeRichTextAttribute.headingLevel] = attributes[ComposeRichTextAttribute.headingLevel]
            if let blockID = attributes[ComposeRichTextAttribute.codeBlockID] as? String {
                let canonicalIndex = codeBlockOrder[blockID] ?? {
                    let next = codeBlockOrder.count
                    codeBlockOrder[blockID] = next
                    return next
                }()
                semantic[NSAttributedString.Key("codeBlock")] = canonicalIndex
            }
            if let cell = attributes[ComposeRichTextAttribute.tableCell] as? ComposeTableCellMetadata {
                let canonicalTable = tableOrder[cell.tableID] ?? {
                    let next = tableOrder.count
                    tableOrder[cell.tableID] = next
                    return next
                }()
                semantic[NSAttributedString.Key("tableCell")] = "\(canonicalTable):\(cell.row):\(cell.column):\(cell.isHeader)"
            }
            semantic[ComposeInlineImageAttribute.contentID] = attributes[ComposeInlineImageAttribute.contentID]
            semantic[ComposeInlineImageAttribute.alt] = attributes[ComposeInlineImageAttribute.alt]
            // List objects compare by identity; compare their marker instead.
            if let style = attributes[.paragraphStyle] as? NSParagraphStyle {
                semantic[NSAttributedString.Key("list")] = style.textLists.first?.markerFormat.rawValue
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
