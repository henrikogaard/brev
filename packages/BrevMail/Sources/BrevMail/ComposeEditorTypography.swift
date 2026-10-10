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

import BrevDesign
import Foundation

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Maps mailbox reading font prefs onto native compose editor fonts.
enum ComposeEditorTypography {
    static func pointSize(for textSize: MailboxTextSize) -> CGFloat {
        textSize.bodyPointSize
    }

    #if canImport(AppKit)
    static func nsFont(family: MailboxFontFamily, textSize: MailboxTextSize) -> NSFont {
        let size = pointSize(for: textSize)
        let system = NSFont.systemFont(ofSize: size)
        let design: NSFontDescriptor.SystemDesign = switch family {
        case .system: .default
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        }
        guard let descriptor = system.fontDescriptor.withDesign(design) else {
            return system
        }
        return NSFont(descriptor: descriptor, size: size) ?? system
    }
    #endif

    #if canImport(UIKit)
    /// Body font for the UIKit editor. The mailbox text-size preference sets the
    /// base size at the default Dynamic Type setting; `UIFontMetrics` scales it
    /// with the user's content size category (pass the text view's
    /// `traitCollection` so the result tracks that view).
    static func uiFont(
        family: MailboxFontFamily,
        textSize: MailboxTextSize,
        compatibleWith traitCollection: UITraitCollection? = nil
    ) -> UIFont {
        let size = pointSize(for: textSize)
        let design: UIFontDescriptor.SystemDesign = switch family {
        case .system: .default
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        }
        let base = UIFont.systemFont(ofSize: size)
        let designed = base.fontDescriptor.withDesign(design).map { UIFont(descriptor: $0, size: size) } ?? base
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: designed, compatibleWith: traitCollection)
    }
    #endif
}
