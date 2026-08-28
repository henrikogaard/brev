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

/// Actions the iOS compose formatting toolbar can invoke on the focused body editor.
@MainActor
protocol ComposeIOSRichTextTarget: AnyObject {
    func toggleBold()
    func toggleItalic()
    func toggleUnderline()
    func toggleBulletedList()
    func toggleNumberedList()
    func clearFormatting()
    func requestLinkSheet()
    func applyLink(url: URL, displayText: String)
    func removeLink()
    @discardableResult
    func insertInlineImage(data: Data, mimeType: String) -> Bool
}

/// Holds a weak reference to the active iOS `UITextView` rich-text coordinator.
///
/// ComposeView owns the box; the editor registers its coordinator on update so
/// toolbar buttons can reach the focused text view without AppKit's responder-chain
/// `sendAction`.
@MainActor
final class ComposeIOSRichTextTargetBox {
    weak var target: ComposeIOSRichTextTarget?
}
