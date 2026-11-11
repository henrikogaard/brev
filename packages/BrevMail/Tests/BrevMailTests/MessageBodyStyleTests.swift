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
@testable import BrevMail
import BrevThemes
import Foundation
import SwiftUI
import Testing

#if canImport(AppKit)
import AppKit

private typealias BodyTestFont = NSFont
#elseif canImport(UIKit)
import UIKit

private typealias BodyTestFont = UIFont
#endif

@Suite("MessageBodyStyle")
struct MessageBodyStyleTests {
    @Test("dark mode CSS uses theme hexes and bans legacy hardcoded palette")
    func darkModeUsesThemeHexes() {
        let theme = BrevTheme.brevSlate
        let style = MessageBodyStyle.resolve(
            theme: theme,
            fontFamily: .system,
            textSize: .medium,
            renderingMode: .dark,
            bodyInsetPoints: 16
        )
        let css = style.documentCSS
        #expect(css.contains(normalizedHex(theme.textPrimary.hex)))
        #expect(css.contains(normalizedHex(theme.accent.hex)))
        #expect(!css.contains("#111114"))
        #expect(!css.contains("#E5E7EB"))
        #expect(!css.contains("#93C5FD"))
        #expect(css.contains("padding:16px"))
        #expect(css.contains("line-height:1.5"))
        #expect(style.backgroundColorHex == normalizedHex(theme.bgPrimary.hex))
        #expect(css.contains("background:\(normalizedHex(theme.bgPrimary.hex))"))
    }

    @Test("original mode embeds font size and family in CSS")
    func originalEmbedsTypography() {
        let theme = BrevTheme.brevPaper
        let style = MessageBodyStyle.resolve(
            theme: theme,
            fontFamily: .serif,
            textSize: .large,
            renderingMode: .original,
            bodyInsetPoints: 20
        )
        #expect(style.documentCSS.contains("17px"))
        #expect(style.documentCSS.contains("ui-serif"))
        #expect(style.documentCSS.contains("padding:20px"))
    }

    @Test("detail and thread body fonts resolve from the same mailbox prefs")
    func sharedBodyFontResolution() {
        let style = MessageBodyStyle.resolve(
            theme: .brevPaper,
            fontFamily: .rounded,
            textSize: .small,
            renderingMode: .original,
            bodyInsetPoints: 16
        )
        #expect(style.textSize.bodyPointSize == 14)
        #expect(style.fontFamily == .rounded)
    }

    @Test("body scaling preserves mailbox typography as its baseline")
    func bodyScalingPreservesMailboxTypography() {
        let style = MessageBodyStyle.resolve(
            theme: .brevPaper,
            fontFamily: .serif,
            textSize: .medium,
            renderingMode: .original,
            bodyInsetPoints: 0,
            bodyScale: 2
        )

        #expect(style.bodyPointSize == 30)
        #expect(style.fontFamily == .serif)
        #expect(style.textSize == .medium)
        #expect(style.documentCSS.contains("font:30px ui-serif"))
    }

    private func normalizedHex(_ hex: String) -> String {
        var stripped = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("#") { stripped.removeFirst() }
        return "#\(stripped)"
    }

    @Test("native attributed bodies use reader family and size without losing emphasis",
          arguments: MailboxFontFamily.allCases, MailboxTextSize.allCases)
    func nativeAttributedTypography(family: MailboxFontFamily, size: MailboxTextSize) async throws {
        let imported = try #require(await MessageHTMLImporter.importAttributedHTML(
            "<p>Regular <strong>Bold</strong> <em>Italic</em> <strong><em>Both</em></strong></p><blockquote>Quote</blockquote>"
        ))
        let original = imported
        let style = bodyStyle(family: family, size: size)
        let displayed = style.nativeAttributedBody(imported)
        try assertNativeTypography(displayed, style: style, original: imported)

        for word in ["Regular", "Bold", "Italic", "Both", "Quote"] {
            let range = try #require(displayed.range(of: word))
            var expected = family.font(size: size.bodyPointSize)
            if ["Bold", "Both"].contains(word) { expected = expected.bold() }
            if ["Italic", "Both"].contains(word) { expected = expected.italic() }
            #expect(displayed[range].font == expected)
        }
        #expect(withoutFonts(displayed) == withoutFonts(imported))
        #expect(imported == original)
    }

    @Test("native attributed preference changes reuse the original without mutation or compounding scale")
    func nativeAttributedPreferenceChanges() async throws {
        let imported = try #require(await MessageHTMLImporter.importAttributedHTML("<p>Text <b><i>Both</i></b></p>"))
        let original = imported
        let styles = [
            bodyStyle(family: .system, size: .medium),
            bodyStyle(family: .serif, size: .large),
            bodyStyle(family: .rounded, size: .medium, scale: 2),
            bodyStyle(family: .monospaced, size: .small),
            bodyStyle(family: .system, size: .medium)
        ]
        #expect(styles[2].bodyPointSize == 30)
        var first: AttributedString?
        for style in styles {
            let displayed = style.nativeAttributedBody(imported)
            try assertNativeTypography(displayed, style: style, original: imported)
            #expect(withoutFonts(displayed) == withoutFonts(original))
            #expect(imported == original)
            if first == nil { first = displayed }
        }
        #expect(styles.last?.nativeAttributedBody(imported) == first)
    }

    @Test("native attributed transform preserves links, paragraphs and mixed or missing font attributes")
    func nativeAttributedMixedRuns() throws {
        let text = "Bare Styled Link\n"
        let native = NSMutableAttributedString(string: text)
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = 12
        paragraph.paragraphSpacing = 9
        native.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: native.length))
        let styledRange = (text as NSString).range(of: "Styled")
        native.addAttribute(.font, value: expectedFont(family: .serif, size: .small), range: styledRange)
        let linkRange = (text as NSString).range(of: "Link")
        try native.addAttribute(.link, value: #require(URL(string: "mailto:qa@example.test")), range: linkRange)
        native.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: linkRange)
        var imported = AttributedString(native)
        imported.tracking = 2
        let original = imported
        let style = bodyStyle(family: .rounded, size: .large)
        let displayed = style.nativeAttributedBody(imported)
        try assertNativeTypography(displayed, style: style, original: imported)
        #expect(withoutFonts(displayed) == withoutFonts(imported))
        #expect(imported == original)

        let plain = AttributedString("No font attributes")
        try assertNativeTypography(style.nativeAttributedBody(plain), style: style, original: plain)
        #expect(style.nativeAttributedBody(AttributedString()).characters.isEmpty)
    }

    private func bodyStyle(family: MailboxFontFamily, size: MailboxTextSize, scale: CGFloat = 1) -> MessageBodyStyle {
        MessageBodyStyle.resolve(theme: .brevPaper, fontFamily: family, textSize: size,
                                 renderingMode: .original, bodyInsetPoints: 0, bodyScale: scale)
    }

    private func assertNativeTypography(_ value: AttributedString, style: MessageBodyStyle, original: AttributedString) throws {
        for run in original.runs {
            var expected = style.fontFamily.font(size: style.bodyPointSize)
            #if canImport(AppKit)
            let originalFont = run.appKit.font
            #expect(value[run.range].appKit.font == nil)
            #else
            let originalFont = run.uiKit.font
            #expect(value[run.range].uiKit.font == nil)
            #endif
            if let originalFont {
                if isBold(originalFont) { expected = expected.bold() }
                if isItalic(originalFont) { expected = expected.italic() }
            }
            let font = try #require(value[run.range].font)
            #expect(font == expected)
        }
    }

    private func withoutFonts(_ value: AttributedString) -> AttributedString {
        var result = value
        result.font = nil
        #if canImport(AppKit)
        result.appKit.font = nil
        #elseif canImport(UIKit)
        result.uiKit.font = nil
        #endif
        return result
    }

    private func expectedFont(family: MailboxFontFamily, size: MailboxTextSize) -> BodyTestFont {
        #if canImport(AppKit)
        ComposeEditorTypography.nsFont(family: family, textSize: size)
        #else
        ComposeEditorTypography.uiFont(family: family, textSize: size)
        #endif
    }

    private func isBold(_ font: BodyTestFont) -> Bool {
        #if canImport(AppKit)
        font.fontDescriptor.symbolicTraits.contains(.bold)
        #else
        font.fontDescriptor.symbolicTraits.contains(.traitBold)
        #endif
    }

    private func isItalic(_ font: BodyTestFont) -> Bool {
        #if canImport(AppKit)
        font.fontDescriptor.symbolicTraits.contains(.italic)
        #else
        font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        #endif
    }

    @Test("reading measure scales with typography without constraining sender HTML")
    func readingMeasure() {
        let normal = MessageBodyStyle.resolve(theme: .brevMonoGrey, fontFamily: .system, textSize: .medium,
                                              renderingMode: .original, bodyInsetPoints: 0)
        let large = MessageBodyStyle.resolve(theme: .brevMonoGrey, fontFamily: .system, textSize: .medium,
                                             renderingMode: .original, bodyInsetPoints: 0, bodyScale: 2)
        #expect(normal.maximumReadingWidth == 540)
        #expect(large.maximumReadingWidth == 1080)
        let plain = HTMLBodyDocument.wrap("Synthetic plain text", style: normal)
        #expect(plain.contains(#"<div class="brev-plain-text">Synthetic plain text</div>"#))
        let sender = #"<table width="1100"><tr><td>Sender HTML</td></tr></table>"#
        let rich = HTMLBodyDocument.wrap(sender, style: normal)
        #expect(rich.contains(sender))
        #expect(!rich.contains(#"<div class="brev-plain-text">"#))
    }
}
