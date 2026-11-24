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
    static func html(
        richHTML: String?,
        plainBody: String,
        preservedQuotedHTML: String? = nil,
        quoteSeparatorHTML: String = ""
    ) -> String {
        let topHTML: String
        if let richHTML, !richHTML.isEmpty {
            topHTML = richHTML
        } else {
            topHTML = ComposeHTMLBodyPolicy.html(fromEditorText: plainBody)
        }
        guard let preservedQuotedHTML, !preservedQuotedHTML.isEmpty else {
            return topHTML
        }
        return ComposeRestoredBody.reassembledHTML(
            editedTopHTML: topHTML,
            separatorHTML: quoteSeparatorHTML,
            preservedQuotedHTML: sanitizedPreviewHTML(preservedQuotedHTML)
        )
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
