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

    /// Relative point-size multiplier for semantic heading levels (`h1`–`h3`).
    static func headingScale(for level: Int) -> CGFloat {
        switch level {
        case 1: return 1.5
        case 2: return 1.3
        case 3: return 1.15
        default: return 1.0
        }
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

    /// Monospaced editor font used for inline `<code>` and `<pre><code>` blocks.
    static func monospacedNSFont(textSize: MailboxTextSize) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: pointSize(for: textSize), weight: .regular)
    }

    /// Replaces every run's font with `base`, preserving bold/italic traits,
    /// heading scale (`h1`–`h3`), monospaced code runs, and inline image attachments.
    static func applyBaseFont(_ base: NSFont, to storage: NSTextStorage) {
        let range = NSRange(location: 0, length: storage.length)
        guard range.length > 0 else { return }
        let mono = NSFont.monospacedSystemFont(ofSize: base.pointSize, weight: .regular)
        storage.beginEditing()
        storage.enumerateAttributes(in: range) { attributes, run, _ in
            if attributes[ComposeInlineImageAttribute.contentID] != nil || attributes[.attachment] != nil {
                return
            }
            let currentFont = attributes[.font] as? NSFont
            var emphasis = (currentFont?.fontDescriptor.symbolicTraits ?? []).intersection(emphasisTraits)
            if (attributes[ComposeRichTextAttribute.inlineCode] as? Bool) == true
                || attributes[ComposeRichTextAttribute.codeBlockID] != nil {
                storage.addAttribute(.font, value: font(mono, emphasis: emphasis) ?? mono, range: run)
                return
            }
            if let level = attributes[ComposeRichTextAttribute.headingLevel] as? Int, (1 ... 3).contains(level) {
                emphasis.insert(.bold)
                let scaledSize = base.pointSize * headingScale(for: level)
                let scaledBase = NSFont(descriptor: base.fontDescriptor, size: scaledSize) ?? base
                storage.addAttribute(.font, value: font(scaledBase, emphasis: emphasis) ?? scaledBase, range: run)
                return
            }
            if let cell = attributes[ComposeRichTextAttribute.tableCell] as? ComposeTableCellMetadata,
               cell.isHeader {
                emphasis.insert(.bold)
            }
            storage.addAttribute(.font, value: font(base, emphasis: emphasis) ?? currentFont ?? base, range: run)
        }
        storage.endEditing()
    }

    /// `font` with exactly the bold/italic `emphasis`, or the system font of the
    /// same size when the family lacks it (SF Rounded has no italic). Nil when
    /// neither can carry it, so callers keep the emphasis they already have.
    static func font(_ font: NSFont, emphasis: NSFontDescriptor.SymbolicTraits) -> NSFont? {
        let wanted = emphasis.intersection(emphasisTraits)
        for candidate in [font, NSFont.systemFont(ofSize: font.pointSize)] {
            let traits = candidate.fontDescriptor.symbolicTraits.subtracting(emphasisTraits).union(wanted)
            let resolved = NSFont(descriptor: candidate.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize)
            if let resolved, resolved.fontDescriptor.symbolicTraits.intersection(emphasisTraits) == wanted {
                return resolved
            }
        }
        return nil
    }

    private static let emphasisTraits: NSFontDescriptor.SymbolicTraits = [.bold, .italic]
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

    /// Monospaced editor font used for inline `<code>` and `<pre><code>` blocks on iOS.
    static func monospacedUIFont(
        textSize: MailboxTextSize,
        compatibleWith traitCollection: UITraitCollection? = nil
    ) -> UIFont {
        let base = UIFont.monospacedSystemFont(ofSize: pointSize(for: textSize), weight: .regular)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base, compatibleWith: traitCollection)
    }

    /// Replaces every run's font with `base` on iOS while keeping bold/italic traits,
    /// heading scale, monospaced code runs, and inline image attachments intact.
    static func applyBaseFont(_ base: UIFont, to storage: NSTextStorage) {
        let range = NSRange(location: 0, length: storage.length)
        guard range.length > 0 else { return }
        let mono = UIFont.monospacedSystemFont(ofSize: base.pointSize, weight: .regular)
        storage.beginEditing()
        storage.enumerateAttributes(in: range) { attributes, run, _ in
            if attributes[ComposeInlineImageAttribute.contentID] != nil || attributes[.attachment] != nil {
                return
            }
            let currentFont = attributes[.font] as? UIFont
            var traits = (currentFont?.fontDescriptor.symbolicTraits ?? []).intersection([.traitBold, .traitItalic])
            if (attributes[ComposeRichTextAttribute.inlineCode] as? Bool) == true
                || attributes[ComposeRichTextAttribute.codeBlockID] != nil {
                let target = mono.fontDescriptor.withSymbolicTraits(traits).map {
                    UIFont(descriptor: $0, size: mono.pointSize)
                } ?? mono
                storage.addAttribute(.font, value: target, range: run)
                return
            }
            if let level = attributes[ComposeRichTextAttribute.headingLevel] as? Int, (1 ... 3).contains(level) {
                traits.insert(.traitBold)
                let scaled = base.withSize(base.pointSize * headingScale(for: level))
                let target = scaled.fontDescriptor.withSymbolicTraits(traits).map {
                    UIFont(descriptor: $0, size: scaled.pointSize)
                } ?? scaled
                storage.addAttribute(.font, value: target, range: run)
                return
            }
            if let cell = attributes[ComposeRichTextAttribute.tableCell] as? ComposeTableCellMetadata,
               cell.isHeader {
                traits.insert(.traitBold)
            }
            let target = base.fontDescriptor.withSymbolicTraits(traits).map {
                UIFont(descriptor: $0, size: base.pointSize)
            } ?? base
            storage.addAttribute(.font, value: target, range: run)
        }
        storage.endEditing()
    }
    #endif
}
