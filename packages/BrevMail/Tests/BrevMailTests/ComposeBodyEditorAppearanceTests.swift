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
import BrevBackend
import BrevDesign
@testable import BrevMail
import BrevThemes
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

    @Test("table header NSTextTableBlock, borders, inline code, and code blocks adapt across Light -> Dark -> Light")
    func tableHeadersInlineCodeAndExplicitColorsAdaptAcrossDarkMode() throws {
        let harness = Harness(text: "Intro CustomColor ", format: .richTextHTML)
        let host = harness.host()
        let editor = try #require(Self.editor(in: host))
        let storage = try #require(editor.textStorage)

        // Apply an explicit user-authored color that appearance switches must never clobber.
        let customColor = NSColor.systemRed
        storage.addAttribute(.foregroundColor, value: customColor, range: Self.range("CustomColor", in: editor.string))

        // Insert inline code, a code block, and a semantic table via the live editor actions in Light mode.
        editor.setSelectedRange(NSRange(location: storage.length, length: 0))
        #expect(editor.brevInsertSanitizedHTML("<code>inlineCode()</code><pre><code>let x = 1</code></pre>"))
        editor.setSelectedRange(NSRange(location: storage.length, length: 0))
        try #require(editor.tryToPerform(#selector(ComposeBodyEditorRichActions.brevInsertTable(_:)), with: nil))
        harness.flush.performFlush()
        let originalHTML = try #require(harness.html)
        #expect(originalHTML.contains("<table><thead><tr><th>"))

        // Activate inline-code typing attributes to ensure pending background color updates too.
        editor.typingAttributes[ComposeRichTextAttribute.inlineCode] = true
        editor.typingAttributes[.backgroundColor] = NSColor(ComposeBodyAppearance.light.editorTheme.bgSecondary.color)

        let header1Range = Self.range("Header 1", in: editor.string)
        let header2Range = Self.range("Header 2", in: editor.string)
        let cell1Range = Self.range("Cell 1", in: editor.string)
        let inlineCodeRange = Self.range("inlineCode()", in: editor.string)
        let customColorRange = Self.range("CustomColor", in: editor.string)
        let introRange = Self.range("Intro", in: editor.string)

        for appearance in [ComposeBodyAppearance.light, .dark, .light] {
            harness.appearance = appearance
            try harness.rerender(host, editor: editor)
            harness.flush.performFlush()

            let expectedText = NSColor(appearance.editorTheme.textPrimary.color)
            let expectedSurface = NSColor(appearance.editorTheme.bgSecondary.color)
            let expectedBorder = NSColor(appearance.editorTheme.border.color)

            // Table headers: background + border + text must adapt and preserve > 4.5:1 contrast.
            for headerRange in [header1Range, header2Range] {
                let paraStyle = try #require(
                    storage.attribute(.paragraphStyle, at: headerRange.location, effectiveRange: nil) as? NSParagraphStyle
                )
                let block = try #require(paraStyle.textBlocks.compactMap { $0 as? NSTextTableBlock }.first)
                let headerBG = try #require(block.backgroundColor)
                let headerFG = try #require(
                    storage.attribute(.foregroundColor, at: headerRange.location, effectiveRange: nil) as? NSColor
                )
                #expect(Self.colorsMatch(headerBG, expectedSurface))
                #expect(Self.colorsMatch(block.borderColor(for: .minX), expectedBorder))
                #expect(Self.colorsMatch(headerFG, expectedText))
                #expect(Self.contrastRatio(between: headerFG, and: headerBG) > 4.5)
            }

            // Table body cells: stay transparent over canvas while borders and text adapt.
            let bodyParaStyle = try #require(
                storage.attribute(.paragraphStyle, at: cell1Range.location, effectiveRange: nil) as? NSParagraphStyle
            )
            let bodyBlock = try #require(bodyParaStyle.textBlocks.compactMap { $0 as? NSTextTableBlock }.first)
            #expect(bodyBlock.backgroundColor == nil)
            #expect(Self.colorsMatch(bodyBlock.borderColor(for: .minX), expectedBorder))
            let bodyFG = try #require(
                storage.attribute(.foregroundColor, at: cell1Range.location, effectiveRange: nil) as? NSColor
            )
            #expect(Self.colorsMatch(bodyFG, expectedText))

            // Inline code run & pending typingAttributes background color adapt with > 4.5:1 contrast.
            let inlineCodeBG = try #require(
                storage.attribute(.backgroundColor, at: inlineCodeRange.location, effectiveRange: nil) as? NSColor
            )
            let inlineCodeFG = try #require(
                storage.attribute(.foregroundColor, at: inlineCodeRange.location, effectiveRange: nil) as? NSColor
            )
            #expect(Self.colorsMatch(inlineCodeBG, expectedSurface))
            #expect(Self.colorsMatch(inlineCodeFG, expectedText))
            #expect(Self.contrastRatio(between: inlineCodeFG, and: inlineCodeBG) > 4.5)
            #expect(Self.colorsMatch(editor.typingAttributes[.backgroundColor] as? NSColor, expectedSurface))
            #expect(Self.colorsMatch(editor.typingAttributes[.foregroundColor] as? NSColor, expectedText))

            // Code block backdrop colors update cleanly.
            #expect(Self.colorsMatch(editor.codeBlockBackgroundColor, expectedSurface))
            #expect(Self.colorsMatch(editor.codeBlockBorderColor, expectedBorder))

            // Default body text adapts while explicit user-authored color is preserved.
            let introFG = try #require(
                storage.attribute(.foregroundColor, at: introRange.location, effectiveRange: nil) as? NSColor
            )
            #expect(Self.colorsMatch(introFG, expectedText))
            let preservedCustomFG = try #require(
                storage.attribute(.foregroundColor, at: customColorRange.location, effectiveRange: nil) as? NSColor
            )
            #expect(Self.colorsMatch(preservedCustomFG, customColor))

            // Semantic HTML remains lossless across appearance switches.
            #expect(harness.html == originalHTML)
        }
    }

    @Test("restored rich draft with table headers and inline code resolves Dark Mode colors on open")
    func restoredRichDraftWithTableAndInlineCodeAdaptsWhenOpenedInDarkMode() async throws {
        let html = """
        <p>Use <code>git status</code></p>\
        <table><thead><tr><th>Task</th><th>Status</th></tr></thead>\
        <tbody><tr><td>Contrast</td><td>Pass</td></tr></tbody></table>
        """
        let restored = try await ComposeDraftBodyRestoration.prepare(
            draft: Draft(id: "dark-table-draft", htmlBody: html),
            format: .richTextHTML
        )
        let harness = Harness(
            text: restored.attributedText.string,
            format: .richTextHTML,
            appearance: .dark,
            restoredAttributedText: restored.attributedText
        )
        let host = harness.host()
        let editor = try #require(Self.editor(in: host))
        let storage = try #require(editor.textStorage)

        let darkText = NSColor(ComposeBodyAppearance.dark.editorTheme.textPrimary.color)
        let darkSurface = NSColor(ComposeBodyAppearance.dark.editorTheme.bgSecondary.color)
        let darkBorder = NSColor(ComposeBodyAppearance.dark.editorTheme.border.color)

        let taskRange = Self.range("Task", in: editor.string)
        let paraStyle = try #require(
            storage.attribute(.paragraphStyle, at: taskRange.location, effectiveRange: nil) as? NSParagraphStyle
        )
        let headerBlock = try #require(paraStyle.textBlocks.compactMap { $0 as? NSTextTableBlock }.first)
        let headerBG = try #require(headerBlock.backgroundColor)
        let headerFG = try #require(
            storage.attribute(.foregroundColor, at: taskRange.location, effectiveRange: nil) as? NSColor
        )
        #expect(Self.colorsMatch(headerBG, darkSurface))
        #expect(Self.colorsMatch(headerBlock.borderColor(for: .minX), darkBorder))
        #expect(Self.colorsMatch(headerFG, darkText))
        #expect(Self.contrastRatio(between: headerFG, and: headerBG) > 4.5)

        let codeRange = Self.range("git status", in: editor.string)
        let codeBG = try #require(
            storage.attribute(.backgroundColor, at: codeRange.location, effectiveRange: nil) as? NSColor
        )
        let codeFG = try #require(
            storage.attribute(.foregroundColor, at: codeRange.location, effectiveRange: nil) as? NSColor
        )
        #expect(Self.colorsMatch(codeBG, darkSurface))
        #expect(Self.colorsMatch(codeFG, darkText))
        #expect(Self.contrastRatio(between: codeFG, and: codeBG) > 4.5)
    }

    @Test("converting a code block to Heading 1 clears code-block marker and background while preserving unrelated backgrounds")
    func convertingCodeBlockToHeadingClearsCodeBackgroundAcrossDarkMode() throws {
        let harness = Harness(text: "", format: .richTextHTML)
        let host = harness.host()
        let editor = try #require(Self.editor(in: host))
        let storage = try #require(editor.textStorage)

        #expect(editor.brevInsertSanitizedHTML("<p>Plain note</p><pre><code>let x = 1</code></pre>"))
        let plainRange = Self.range("Plain note", in: editor.string)
        let codeRange = Self.range("let x = 1", in: editor.string)
        let unrelatedBG = NSColor.systemYellow
        storage.addAttribute(.backgroundColor, value: unrelatedBG, range: plainRange)
        storage.addAttribute(
            .backgroundColor,
            value: NSColor(ComposeBodyAppearance.light.editorTheme.bgSecondary.color),
            range: codeRange
        )

        editor.setSelectedRange(NSRange(location: codeRange.location, length: 0))
        try #require(editor.tryToPerform(#selector(ComposeBodyEditorRichActions.brevToggleHeading1(_:)), with: nil))
        editor.setSelectedRange(NSRange(location: plainRange.location, length: 0))
        try #require(editor.tryToPerform(#selector(ComposeBodyEditorRichActions.brevToggleHeading1(_:)), with: nil))

        for appearance in [ComposeBodyAppearance.dark, .light, .dark] {
            harness.appearance = appearance
            try harness.rerender(host, editor: editor)

            let expectedText = NSColor(appearance.editorTheme.textPrimary.color)
            let expectedCanvas = NSColor(appearance.editorTheme.bgPrimary.color)

            let updatedCodeLoc = Self.range("let x = 1", in: editor.string).location
            #expect(storage.attribute(ComposeRichTextAttribute.codeBlockID, at: updatedCodeLoc, effectiveRange: nil) == nil)
            #expect(storage
                .attribute(ComposeRichTextAttribute.headingLevel, at: updatedCodeLoc, effectiveRange: nil) as? Int == 1)
            #expect(storage.attribute(.backgroundColor, at: updatedCodeLoc, effectiveRange: nil) == nil)
            let headingFG = try #require(
                storage.attribute(.foregroundColor, at: updatedCodeLoc, effectiveRange: nil) as? NSColor
            )
            #expect(Self.colorsMatch(headingFG, expectedText))
            #expect(Self.contrastRatio(between: headingFG, and: expectedCanvas) > 4.5)

            let updatedPlainLoc = Self.range("Plain note", in: editor.string).location
            let preservedBG = try #require(
                storage.attribute(.backgroundColor, at: updatedPlainLoc, effectiveRange: nil) as? NSColor
            )
            #expect(Self.colorsMatch(preservedBG, unrelatedBG))
        }
    }

    @Test("reply body starts with leading blank composing line and places initial caret at offset 0 above attribution")
    func replyBodyStartsWithBlankLineAndCaretAtOffsetZero() throws {
        let header = MessageHeader(
            id: "reply-caret-1",
            threadID: "thread-caret-1",
            folderID: "inbox",
            from: Correspondent(name: "Sigrid Solberg", email: "sigrid@harbour.example"),
            subject: "Berth schedule",
            snippet: "Can you confirm the Friday slot?",
            date: Date(timeIntervalSince1970: 1_779_960_600)
        )
        let locale = Locale(identifier: "en_GB")
        let utc = TimeZone(identifier: "UTC")!
        let marker = ComposeReplyFormatter.quoteMarker(for: header, locale: locale, timeZone: utc)
        let replyBody = ComposeReplyFormatter.body(
            for: header,
            placement: .belowReply,
            locale: locale,
            timeZone: utc
        )
        let protection = ComposeQuoteProtection(marker: marker, edge: .bottom)

        #expect(replyBody.hasPrefix("\n\n\(marker)"))
        let protected = try #require(ComposeQuoteEditGuard.protectedRange(
            in: replyBody as NSString,
            protection: protection
        ))
        #expect(protected.location == 2)

        let harness = Harness(
            text: replyBody,
            format: .richTextHTML,
            quoteProtection: protection
        )
        let host = harness.host()
        let editor = try #require(Self.editor(in: host))

        #expect(editor.selectedRange() == NSRange(location: 0, length: 0))
        #expect(harness.insertion?.nsRange == NSRange(location: 0, length: 0))

        // Upgrading the provisional quote snippet with decoded body text must
        // keep the caret at offset 0 above the attribution line.
        harness.text = ComposeReplyFormatter.body(
            for: header,
            quoteText: "Full decoded message body line 1.\nLine 2.",
            placement: .belowReply,
            locale: locale,
            timeZone: utc
        )
        try harness.rerender(host, editor: editor)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 0))
        #expect(editor.string.hasPrefix("\n\n\(marker)"))

        // Explicit focus request places caret at offset 0 even if previously moved.
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        harness.focusRequest = ComposeBodyFocusRequest(
            id: 1,
            selection: ComposeFocusPolicy.initialBodySelection(
                in: editor.string as NSString,
                quoteProtection: protection
            )
        )
        try harness.rerender(host, editor: editor)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test("inserted and parsed macOS tables inset trailing edge and draw 1 pt four-sided borders")
    func macTablesInsetTrailingEdgeForFourSidedBorders() throws {
        let style = ComposeRichHTMLAttributedBuilder.Style.default(theme: .brevMonoDark)
        let inserted = ComposeRichHTMLAttributedBuilder.makeTableAttributedString(
            headers: ["Header 1", "Header 2"],
            rows: [["Cell 1", "Cell 2"]],
            style: style
        )
        let parsed = try #require(ComposeRichHTMLAttributedBuilder.attributedString(
            from: "<table><thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td>1</td><td>2</td></tr></tbody></table>",
            style: style,
            strict: true
        ))

        for attributed in [inserted, parsed] {
            let paraStyle = try #require(attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            let block = try #require(paraStyle.textBlocks.compactMap { $0 as? NSTextTableBlock }.first)
            let table = block.table
            #expect(table.contentWidth < 100)
            #expect(table.width(for: .margin, edge: .maxX) >= 1)
            for edge: NSRectEdge in [.minX, .maxX, .minY, .maxY] {
                #expect(block.width(for: .border, edge: edge) >= 1)
                #expect(block.borderColor(for: edge) != nil)
            }
        }
    }

    private static func colorsMatch(_ lhs: NSColor?, _ rhs: NSColor?) -> Bool {
        guard let lhs, let rhs,
              let left = lhs.usingColorSpace(.sRGB),
              let right = rhs.usingColorSpace(.sRGB) else {
            return false
        }
        return abs(left.redComponent - right.redComponent) <= 0.005
            && abs(left.greenComponent - right.greenComponent) <= 0.005
            && abs(left.blueComponent - right.blueComponent) <= 0.005
            && abs(left.alphaComponent - right.alphaComponent) <= 0.005
    }

    private static func contrastRatio(between first: NSColor, and second: NSColor) -> Double {
        let l1 = relativeLuminance(of: first)
        let l2 = relativeLuminance(of: second)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private static func relativeLuminance(of color: NSColor) -> Double {
        guard let srgb = color.usingColorSpace(.sRGB) else { return 0 }
        func linearize(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return linearize(Double(srgb.redComponent)) * 0.2126
            + linearize(Double(srgb.greenComponent)) * 0.7152
            + linearize(Double(srgb.blueComponent)) * 0.0722
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

    @Test("bottom content inset reserves scrollable space beneath macOS floating formatting bar without recreating the editor")
    func bottomContentInsetReservesScrollableSpaceWhilePreservingEditorIdentity() throws {
        let harness = Harness(text: "Line 1\nLine 2\nFinal line", format: .richTextHTML)
        let host = harness.host()
        let editor = try #require(Self.editor(in: host))
        let scrollView = try #require(editor.enclosingScrollView)
        editor.setSelectedRange(NSRange(location: 7, length: 6))

        #expect(!scrollView.automaticallyAdjustsContentInsets)
        #expect(scrollView.contentInsets.bottom == 0)

        let reservedInset = ComposeLiquidGlass.macFloatingFormattingBarBottomInset(isVisible: true)
        #expect(reservedInset > 0)
        harness.bottomContentInset = reservedInset
        try harness.rerender(host, editor: editor)
        #expect(scrollView.contentInsets.bottom == reservedInset)
        #expect(editor.selectedRange() == NSRange(location: 7, length: 6))

        harness.bottomContentInset = ComposeLiquidGlass.macFloatingFormattingBarBottomInset(isVisible: false)
        try harness.rerender(host, editor: editor)
        #expect(scrollView.contentInsets.bottom == 0)
        #expect(editor.selectedRange() == NSRange(location: 7, length: 6))
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
        var restoredAttributedText: NSAttributedString?
        var quoteProtection: ComposeQuoteProtection?
        var focusRequest: ComposeBodyFocusRequest?
        var family = MailboxFontFamily.system
        var size = MailboxTextSize.medium
        var bottomContentInset: CGFloat = 0
        var generation = 0
        var deliveredGeneration = -1

        init(
            text: String,
            format: ComposeBodyFormat,
            appearance: ComposeBodyAppearance = .light,
            restoredAttributedText: NSAttributedString? = nil,
            quoteProtection: ComposeQuoteProtection? = nil
        ) {
            self.text = text
            self.format = format
            self.appearance = appearance
            self.restoredAttributedText = restoredAttributedText
            self.quoteProtection = quoteProtection ?? Self.quote
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
                quoteProtection: quoteProtection,
                focusRequest: focusRequest,
                restoredAttributedText: restoredAttributedText,
                bottomContentInset: bottomContentInset
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
