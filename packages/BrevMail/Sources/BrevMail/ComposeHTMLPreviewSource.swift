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
    static func html(richHTML: String?, plainBody: String) -> String {
        if let richHTML, !richHTML.isEmpty {
            return richHTML
        }
        return ComposeHTMLBodyPolicy.html(fromEditorText: plainBody)
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
