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

#if os(macOS)
import AppKit
import BrevDesign
@testable import BrevMail
import SwiftUI
import Testing

@Suite("Compose body editor appearance", .serialized)
@MainActor
struct ComposeBodyEditorAppearanceTests {
    @Test("programmatic rich text changes retain quote and attachment attributes")
    func textDeltaPreservesAttributes() throws {
        let fixture = Self.richFixture()
        let harness = Harness(text: fixture.string, format: .richTextHTML)
        let host = harness.host()
        let editor = try #require(Self.editor(in: host))
        editor.textStorage?.setAttributedString(fixture)
        try harness.rerender(host, editor: editor)
        let original = NSAttributedString(attributedString: editor.attributedString())
        for prefix in ["🌱 ", "🌿 ", "e\u{301} ", "é ", ""] {
            harness.text = prefix + fixture.string
            try harness.rerender(host, editor: editor)
            harness.flush.performFlush()
            #expect(editor.string == harness.text)
            let unchanged = editor.attributedString().attributedSubstring(from: NSRange(
                location: prefix.utf16.count,
                length: original.length
            ))
            #expect(unchanged.isEqual(to: original))
            Self.expectEmphasis(in: editor, html: harness.html)
            let image = Self.range("\u{FFFC}", in: editor.string)
            #expect(editor.textStorage?
                .attribute(.attachment, at: image.location, effectiveRange: nil) as? NSTextAttachment === fixture.attribute(
                    .attachment,
                    at: Self.range("\u{FFFC}", in: fixture.string).location,
                    effectiveRange: nil
                ) as? NSTextAttachment)
            #expect(harness.html?.contains("cid:fixture@brev") == true)
            let protected = try #require(ComposeQuoteEditGuard.protectedRange(
                in: editor.string as NSString,
                protection: Harness.quote
            ))
            #expect(editor.quoteBarRange == protected)
            let before = editor.string
            editor.insertText("Not permitted", replacementRange: NSRange(location: protected.location + 1, length: 1))
            #expect(editor.string == before)
        }
    }

    @Test("rich editor rerenders preserve formatting and update theme foregrounds", arguments: [false, true], [false, true])
    func richRerender(selectedText: Bool, typedBody: Bool) throws {
        let fixture = Self.richFixture()
        let harness = Harness(text: typedBody ? "" : fixture.string, format: .richTextHTML)
        let host = harness.host()
        let editor = try #require(Self.editor(in: host))
        if typedBody {
            editor.insertText(fixture.string, replacementRange: NSRange(location: 0, length: 0))
        }
        fixture.enumerateAttributes(in: NSRange(location: 0, length: fixture.length)) { attributes, range, _ in
            editor.textStorage?.addAttributes(attributes, range: range)
        }
        let selection = selectedText ? Self.range("Both", in: fixture.string) : NSRange(location: 0, length: 0)
        editor.setSelectedRange(selection)
        editor.typingAttributes[.font] = Self.emphasizedFont([.boldFontMask, .italicFontMask])
        editor.typingAttributes[.kern] = 1.25
        harness.flush.performFlush()
        Self.expectEmphasis(in: editor, html: harness.html)
        let originalHTML = harness.html

        for appearance in [ComposeBodyAppearance.light, .dark, .light] {
            harness.appearance = appearance
            try harness.rerender(host, editor: editor)
            harness.flush.performFlush()
            Self.expectEmphasis(in: editor, html: harness.html)
            #expect(harness.html == originalHTML)
            #expect(editor.selectedRange() == selection)
            #expect(editor.string == fixture.string)
            #expect(harness.text == fixture.string)
            #expect(editor.typingAttributes[.kern] as? Double == 1.25)
            let typing = try #require(editor.typingAttributes[.font] as? NSFont)
            #expect(typing.fontDescriptor.symbolicTraits.contains([.bold, .italic]))
            let link = Self.range("Link", in: fixture.string)
            #expect(editor.textStorage?.attribute(.link, at: link.location, effectiveRange: nil) as? URL == Self.link)
            #expect(editor.textStorage?.attribute(.underlineStyle, at: link.location, effectiveRange: nil) as? Int == 1)
            let paragraph = editor.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            #expect(paragraph?.headIndent == 18)
            let image = Self.range("\u{FFFC}", in: fixture.string)
            #expect(editor.textStorage?
                .attribute(.attachment, at: image.location, effectiveRange: nil) as? NSTextAttachment === fixture.attribute(
                    .attachment,
                    at: image.location,
                    effectiveRange: nil
                ) as? NSTextAttachment)
            #expect(harness.html?.contains("cid:fixture@brev") == true)
            #expect(editor.quoteBarRange == ComposeQuoteEditGuard.protectedRange(
                in: fixture.string as NSString,
                protection: Harness.quote
            ))
            let primary = NSColor(appearance.editorTheme.textPrimary.color)
            for word in ["Regular", "Bold", "Italic", "Both", "Link"] {
                let color = editor.textStorage?.attribute(
                    .foregroundColor, at: Self.range(word, in: fixture.string).location, effectiveRange: nil
                ) as? NSColor
                #expect(color == primary)
            }
            #expect(editor.typingAttributes[.foregroundColor] as? NSColor == primary)
            let quoteRange = try #require(editor.quoteBarRange)
            let quoteColor = editor.textStorage?.attribute(
                .foregroundColor, at: quoteRange.location, effectiveRange: nil
            ) as? NSColor
            #expect(quoteColor == NSColor(appearance.editorTheme.textTertiary.color))
            #expect(editor.quoteBarColor == NSColor(appearance.editorTheme.accent.color))
        }
    }

    @Test("native text color setter preserves non-color storage and typing attributes", arguments: [false, true])
    func nativeTextColorSetter(selectedText: Bool) throws {
        let editor = NSTextView()
        editor.isRichText = true
        let fixture = Self.richFixture()
        editor.textStorage?.setAttributedString(fixture)
        let selection = selectedText ? Self.range("Both", in: fixture.string) : NSRange(location: 0, length: 0)
        editor.setSelectedRange(selection)
        editor.typingAttributes = [.font: Self.emphasizedFont([.boldFontMask, .italicFontMask]), .kern: 1.25]
        let originalTyping = editor.typingAttributes
        let original = NSMutableAttributedString(attributedString: editor.attributedString())
        original.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: original.length))
        for appearance in [ComposeBodyAppearance.light, .dark, .light] {
            let color = NSColor(appearance.editorTheme.textPrimary.color)
            editor.textColor = color
            editor.textStorage?.enumerateAttribute(
                .foregroundColor, in: NSRange(location: 0, length: fixture.length)
            ) { value, _, _ in
                #expect(value as? NSColor == color)
            }
            let actual = NSMutableAttributedString(attributedString: editor.attributedString())
            actual.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: actual.length))
            #expect(actual.isEqual(to: original))
            #expect(editor.selectedRange() == selection)
            var typing = editor.typingAttributes
            typing.removeValue(forKey: .foregroundColor)
            var expectedTyping = originalTyping
            expectedTyping.removeValue(forKey: .foregroundColor)
            #expect(NSDictionary(dictionary: typing).isEqual(to: expectedTyping))
            #expect(editor.typingAttributes[.foregroundColor] as? NSColor == color)
        }
    }

    @Test("reader preference changes do not restyle existing rich content", arguments: MailboxFontFamily.allCases)
    func typographyChange(family: MailboxFontFamily) throws {
        let fixture = Self.richFixture()
        let harness = Harness(text: fixture.string, format: .richTextHTML)
        let host = harness.host()
        let editor = try #require(Self.editor(in: host))
        editor.textStorage?.setAttributedString(fixture)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.typingAttributes = [.font: Self.emphasizedFont([.boldFontMask, .italicFontMask])]
        for size in [MailboxTextSize.large, .small, .medium] {
            harness.family = family
            harness.size = size
            try harness.rerender(host, editor: editor)
            harness.flush.performFlush()
            Self.expectEmphasis(in: editor, html: harness.html)
            let regular = try #require(editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            #expect(regular == NSFont.systemFont(ofSize: 15))
            for word in ["Bold", "Italic", "Both"] {
                let font = try #require(editor.textStorage?.attribute(
                    .font,
                    at: Self.range(word, in: fixture.string).location,
                    effectiveRange: nil
                ) as? NSFont)
                #expect(font.pointSize == 15)
            }
            let typing = try #require(editor.typingAttributes[.font] as? NSFont)
            #expect(typing.pointSize == 15)
            #expect(typing.fontDescriptor.symbolicTraits.contains([.bold, .italic]))
            #expect(editor.string == fixture.string)
        }
    }

    @Test("new rich editors start with reader typography", arguments: MailboxFontFamily.allCases, MailboxTextSize.allCases)
    func initialRichTypography(family: MailboxFontFamily, size: MailboxTextSize) throws {
        let harness = Harness(text: "Unstyled initial body", format: .richTextHTML)
        harness.family = family
        harness.size = size
        let host = harness.host()
        let editor = try #require(Self.editor(in: host))
        let expected = ComposeEditorTypography.nsFont(family: family, textSize: size)
        #expect(editor.font == expected)
        #expect(editor.typingAttributes[.font] as? NSFont == expected)
    }

    @Test("plain and empty editors retain their default typography", arguments: [false, true])
    func plainAndEmpty(rich: Bool) throws {
        let harness = Harness(text: rich ? "" : "Plain <body>", format: rich ? .richTextHTML : .plainText)
        let host = harness.host()
        let editor = try #require(Self.editor(in: host))
        if !rich { harness.html = "<strong>Stale publication</strong>" }
        for family in MailboxFontFamily.allCases {
            for size in MailboxTextSize.allCases {
                harness.family = family
                harness.size = size
                try harness.rerender(host, editor: editor)
                harness.flush.performFlush()
                let expected = ComposeEditorTypography.nsFont(family: family, textSize: size)
                #expect(editor.font == expected)
                #expect(editor.typingAttributes[.font] as? NSFont == expected)
                #expect(editor.isRichText == rich)
                #expect(editor.string == harness.text)
                #expect(rich ? harness.html == "" : harness.html == nil)
            }
        }
    }

    private static let link = URL(string: "https://example.invalid/compose-fixture")!

    @Test("empty rich editors preserve pending emphasis through rerender and first character", arguments: [
        NSFontTraitMask.boldFontMask, .italicFontMask, [.boldFontMask, .italicFontMask]
    ], [false, true])
    func emptyRichTyping(traits: NSFontTraitMask, changePreferences: Bool) throws {
        let harness = Harness(text: "", format: .richTextHTML)
        let host = harness.host()
        let editor = try #require(Self.editor(in: host))
        let emphasized = Self.emphasizedFont(traits)
        editor.typingAttributes[.font] = emphasized
        editor.typingAttributes[.kern] = 1.25
        #expect(editor.string.isEmpty)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 0))
        #expect(editor.typingAttributes[.font] as? NSFont == emphasized)

        for appearance in [ComposeBodyAppearance.light, .dark, .light] {
            harness.appearance = appearance
            try harness.rerender(host, editor: editor)
            #expect(editor.typingAttributes[.font] as? NSFont == emphasized)
            #expect(editor.typingAttributes[.kern] as? Double == 1.25)
            #expect(editor.typingAttributes[.foregroundColor] as? NSColor == NSColor(appearance.editorTheme.textPrimary.color))
        }
        if changePreferences {
            for family in MailboxFontFamily.allCases {
                for size in MailboxTextSize.allCases {
                    harness.family = family
                    harness.size = size
                    try harness.rerender(host, editor: editor)
                    #expect(editor.typingAttributes[.font] as? NSFont == emphasized)
                }
            }
        }
        editor.insertText("X", replacementRange: NSRange(location: 0, length: 0))
        harness.flush.performFlush()
        #expect(editor.string == "X")
        #expect(harness.text == "X")
        #expect(editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == emphasized)
        #expect(editor.selectedRange() == NSRange(location: 1, length: 0))
        #expect(harness.html?.contains("<strong>") == traits.contains(.boldFontMask))
        #expect(harness.html?.contains("<em>") == traits.contains(.italicFontMask))
    }

    private static func richFixture() -> NSMutableAttributedString {
        let value = NSMutableAttributedString(
            string: "Regular Bold Italic Both Link\n",
            attributes: [.font: NSFont.systemFont(ofSize: 15)]
        )
        for (word, traits) in [
            ("Bold", NSFontTraitMask.boldFontMask),
            ("Italic", .italicFontMask),
            ("Both", [.boldFontMask, .italicFontMask])
        ] {
            value.addAttribute(.font, value: emphasizedFont(traits), range: range(word, in: value.string))
        }
        value.addAttributes([.link: link, .underlineStyle: 1], range: range("Link", in: value.string))
        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = 18
        value.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: value.length))
        let image = NSMutableAttributedString(attributedString: NSAttributedString(attachment: NSTextAttachment()))
        image.addAttribute(ComposeInlineImageAttribute.contentID, value: "fixture@brev", range: NSRange(location: 0, length: 1))
        value.append(image)
        value.append(NSAttributedString(string: "\nQuoted original:\n> Keep this quote"))
        return value
    }

    private static func emphasizedFont(_ traits: NSFontTraitMask) -> NSFont {
        NSFontManager.shared.convert(NSFont.systemFont(ofSize: 15), toHaveTrait: traits)
    }

    private static func range(_ word: String, in text: String) -> NSRange {
        (text as NSString).range(of: word)
    }

    private static func expectEmphasis(in editor: NSTextView, html: String?) {
        for (word, traits) in [("Bold", NSFontDescriptor.SymbolicTraits.bold), ("Italic", .italic), ("Both", [.bold, .italic])] {
            let font = editor.textStorage?.attribute(
                .font,
                at: range(word, in: editor.string).location,
                effectiveRange: nil
            ) as? NSFont
            #expect(font?.fontDescriptor.symbolicTraits.contains(traits) == true)
        }
        #expect(html?.contains("<strong>Bold</strong>") == true)
        #expect(html?.contains("<em>Italic</em>") == true)
        #expect(html?.contains("<strong><em>Both</em></strong>") == true)
        #expect(html?.contains("href=\"\(link.absoluteString)\"") == true)
    }

    private static func editor(in view: NSView) -> ComposeRichTextView? {
        if let editor = view as? ComposeRichTextView { return editor }
        return view.subviews.lazy.compactMap { editor(in: $0) }.first
    }

    @MainActor
    private final class Harness {
        static let quote = ComposeQuoteProtection(marker: "Quoted original:", edge: .bottom)
        var text: String
        var html: String?
        var selection: ComposeBodyTextSelection?
        var insertion: ComposeBodyInsertionPoint?
        let format: ComposeBodyFormat
        let flush = ComposeHTMLPublicationFlushBox()
        var appearance = ComposeBodyAppearance.light
        var family = MailboxFontFamily.system
        var size = MailboxTextSize.medium
        var generation = 0
        var deliveredGeneration = -1

        init(text: String, format: ComposeBodyFormat) {
            self.text = text
            self.format = format
        }

        func root() -> ComposeBodyEditor {
            let revision = generation
            return ComposeBodyEditor(
                text: Binding(get: { self.text }, set: { self.text = $0 }),
                richHTML: Binding(get: { self.html }, set: { self.html = $0 }),
                selection: Binding(get: { self.selection }, set: { self.selection = $0 }),
                insertionPoint: Binding(get: { self.insertion }, set: { self.insertion = $0 }),
                bodyFormat: format, appearance: appearance, htmlPublicationFlushBox: flush,
                textCheckingConfiguration: ComposeTextCheckingPolicy.configuration(isEnabled: false),
                fontFamily: family, textSize: size,
                onFileDragTargetChanged: { _ in self.deliveredGeneration = revision },
                quoteProtection: Self.quote
            )
        }

        func host() -> NSHostingView<ComposeBodyEditor> {
            let host = NSHostingView(rootView: root())
            host.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
            host.layoutSubtreeIfNeeded()
            return host
        }

        func rerender(_ host: NSHostingView<ComposeBodyEditor>, editor: ComposeRichTextView) throws {
            generation += 1
            host.rootView = root()
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            editor.onFileDragTargetChanged?(false)
            try #require(deliveredGeneration == generation, "Production updateNSView must deliver the new callback")
            let currentEditor = ComposeBodyEditorAppearanceTests.editor(in: host)
            try #require(currentEditor === editor, "Rerender must reuse the native editor")
        }
    }
}
#endif
