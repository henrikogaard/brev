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

/// Chooses which HTML fragment the macOS compose preview WebView should load.
enum ComposeHTMLPreviewSource {
    /// Prefers serialized rich HTML when present; otherwise escapes plain editor text.
    /// When a reopened draft carries a preserved quoted HTML tail, appends a
    /// script-sanitized preview copy so the user sees the full outgoing message.
    /// Rewrites local `cid:` image sources to in-memory `data:` URIs using
    /// `inlineImages` without ever making external network requests.
    static func html(
        richHTML: String?,
        plainBody: String,
        preservedQuotedHTML: String? = nil,
        quoteSeparatorHTML: String = "",
        outerWrapperOpenHTML: String = "",
        outerWrapperCloseHTML: String = "",
        inlineImages: [ComposeInlineImage] = []
    ) -> String {
        let topHTML: String
        if let richHTML, !richHTML.isEmpty {
            topHTML = richHTML
        } else {
            topHTML = ComposeHTMLBodyPolicy.html(fromEditorText: plainBody)
        }
        let combined: String
        if let preservedQuotedHTML, !preservedQuotedHTML.isEmpty {
            combined = ComposeRestoredBody.reassembledHTML(
                editedTopHTML: topHTML,
                separatorHTML: quoteSeparatorHTML,
                preservedQuotedHTML: sanitizedPreviewHTML(preservedQuotedHTML),
                outerWrapperOpenHTML: outerWrapperOpenHTML,
                outerWrapperCloseHTML: outerWrapperCloseHTML
            )
        } else {
            combined = topHTML
        }
        return rewriteLocalCIDImages(in: combined, inlineImages: inlineImages)
    }

    /// Returns preview-safe HTML for a preserved quote fragment, wrapping it in
    /// any inherited text direction (`dir="rtl"` / `"ltr"` / resolved `"auto"`)
    /// so mixed-direction quoted content renders identically to the original wrapper.
    ///
    /// When `inheritedDirection == "auto"`, resolves the explicit direction from
    /// `leadingContextText` followed by the quoted text using the HTML5 first-strong-
    /// directional-character rule so a quote-only preview does not flip direction
    /// when the enclosing document begins with text in another script.
    static func sanitizedQuotePreviewHTML(
        _ html: String,
        inheritedDirection: String? = nil,
        leadingContextText: String = "",
        inlineImages: [ComposeInlineImage] = []
    ) -> String {
        let sanitized = rewriteLocalCIDImages(
            in: sanitizedPreviewHTML(html),
            inlineImages: inlineImages
        )
        guard let dir = resolvedQuotePreviewDirection(
            inheritedDirection,
            leadingContextText: leadingContextText,
            quoteHTML: html
        ) else {
            return sanitized
        }
        return "<div dir=\"\(dir)\">\(sanitized)</div>"
    }

    private static func rewriteLocalCIDImages(
        in html: String,
        inlineImages: [ComposeInlineImage]
    ) -> String {
        guard !inlineImages.isEmpty,
              html.range(of: "cid:", options: [.caseInsensitive]) != nil else {
            return html
        }
        let payloads = inlineImages.map {
            MessageInlineCIDImagePayload(
                contentID: $0.contentID,
                mimeType: $0.mimeType,
                data: $0.data
            )
        }
        return MessageInlineCIDRenderPolicy.rewriteCIDImageSources(in: html, payloads: payloads)
    }

    private static func resolvedQuotePreviewDirection(
        _ inheritedDirection: String?,
        leadingContextText: String,
        quoteHTML: String
    ) -> String? {
        switch inheritedDirection?.lowercased() {
        case "rtl":
            return "rtl"
        case "ltr":
            return "ltr"
        case "auto":
            let combined = leadingContextText.isEmpty
                ? ComposeQuoteTextPolicy.htmlToPlainText(quoteHTML)
                : "\(leadingContextText)\n\(ComposeQuoteTextPolicy.htmlToPlainText(quoteHTML))"
            return firstStrongDirection(in: combined)
        default:
            return nil
        }
    }

    /// Implements the HTML5 `dir="auto"` first-strong-directional-character rule,
    /// returning `"rtl"` when the first strong directional scalar is RTL (Hebrew,
    /// Arabic, Syriac, Thaana, NKo, etc.) and `"ltr"` otherwise.
    private static func firstStrongDirection(in text: String) -> String {
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if value == 0x200F || value == 0x061C {
                return "rtl"
            }
            if value == 0x200E {
                return "ltr"
            }
            guard scalar.properties.isAlphabetic else {
                continue
            }
            if isStrongRTLScalar(value) {
                return "rtl"
            }
            return "ltr"
        }
        return "ltr"
    }

    private static func isStrongRTLScalar(_ value: UInt32) -> Bool {
        switch value {
        case 0x0590 ... 0x08FF, // Hebrew, Arabic, Syriac, Thaana, NKo, Samaritan, Mandaic, Arabic Extended
             0xFB1D ... 0xFDFF, // Hebrew & Arabic Presentation Forms-A
             0xFE70 ... 0xFEFC, // Arabic Presentation Forms-B
             0x10800 ... 0x10FFF, // Historic RTL scripts
             0x1E800 ... 0x1EFFF: // Mende Kikakui, Adlam, Arabic Math
            return true
        default:
            return false
        }
    }

    /// Strips active script/embed blocks, inline event handlers, and executable
    /// URL schemes from preserved quoted HTML before preview rendering. Never
    /// mutates the stored `preservedQuotedHTML` used on save/send.
    static func sanitizedPreviewHTML(_ html: String) -> String {
        var result = html
        for pattern in [
            #"(?is)<\s*(script|iframe|object|embed|applet)\b[^>]*>.*?</\s*\1\s*>"#,
            #"(?is)<\s*(script|iframe|object|embed|applet|base)\b[^>]*/?\s*>"#,
            #"(?is)<\s*meta\b[^>]*http-equiv\s*=\s*["']?refresh["']?[^>]*>"#
        ] {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        result = result.replacingOccurrences(
            of: #"(?i)\s+on[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)(href|src)\s*=\s*(?:"\s*(?:javascript|vbscript):[^"]*"|'\s*(?:javascript|vbscript):[^']*')"#,
            with: "$1=\"#\"",
            options: .regularExpression
        )
        return result
    }

    /// Maps compose editor appearance onto the reader HTML rendering mode.
    static func renderingMode(for appearance: ComposeBodyAppearance) -> HTMLBodyRenderingMode {
        switch appearance {
        case .system, .light:
            return .original
        case .dark:
            return .dark
        }
    }
}
