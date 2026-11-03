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
        guard draft.inReplyToMessageID == nil, draft.forwardedMessageID == nil,
              html.utf8.count <= 1_048_576,
              ComposeHTMLBodyPolicy.richHTML(fromEditorHTML: html) == html,
              html.range(of: #"(?i)<\s*/?\s*(img|blockquote|ul|ol|li|p|div)\b"#, options: .regularExpression) == nil else {
            throw MailBackendError.backendSpecific(message: unsupportedMessage)
        }
        let attributed: NSAttributedString
        if html.isEmpty {
            attributed = NSAttributedString(string: "")
        } else {
            guard let imported = await MessageHTMLImporter.importAttributedHTML(html) else {
                throw MailBackendError.backendSpecific(message: unsupportedMessage)
            }
            attributed = NSAttributedString(imported)
        }
        try Task.checkCancellation()
        let serialized = ComposeRichTextHTMLSerializer.html(from: attributed)
        if !serialized.isEmpty {
            guard let importedAgain = await MessageHTMLImporter.importAttributedHTML(serialized),
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
