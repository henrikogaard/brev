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
import Testing

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
        #expect(css.contains("line-height:1.45"))
        #expect(style.backgroundColorHex == nil)
        #expect(css.contains("background:transparent"))
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

    private func normalizedHex(_ hex: String) -> String {
        var stripped = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("#") { stripped.removeFirst() }
        return "#\(stripped)"
    }
}
