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

#if os(iOS)
import BrevBackend
import BrevDesign
@testable import BrevMail
import BrevThemes
import SwiftUI
import Testing
import UIKit

@Suite("Compose body editor appearance on iOS", .serialized)
@MainActor
struct ComposeBodyEditorAppearanceIOSTests {
    private static let link = URL(string: "https://example.invalid/ios-compose-fixture")!

    @Test("rich compose body text, typingAttributes, code surfaces, and quotes adapt across Light -> Dark -> Light")
    func richBodyAndTypingAttributesAdaptAcrossDarkMode() throws {
        let harness = Harness(text: "Testing rich editor", format: .richTextHTML, appearance: .light)
        let mounted = try harness.mount()
        defer { mounted.teardown() }
        let editor = mounted.editor
        let storage = editor.textStorage

        // Initial Light mode text starts readable with light primary color.
        let initialColor = try #require(
            storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        )
        #expect(Self.colorsMatch(initialColor, UIColor(BrevTheme.brevMonoLight.textPrimary.color)))

        // Enrich the body with bold, italic, underline, link, inline code, code block,
        // table cells, explicit custom color, and a protected reply quote.
        let target = try #require(harness.iosTargetBox.target)
        let rich = Self.richFixture()
        storage.setAttributedString(rich)
        harness.text = rich.string
        let customColor = UIColor.systemRed
        storage.addAttribute(.foregroundColor, value: customColor, range: Self.range("Custom", in: rich.string))
        editor.selectedRange = NSRange(location: storage.length, length: 0)
        #expect(target.insertSanitizedHTML(
            "<p>Use <code>git status</code></p><pre><code>let x = 1</code></pre>"
                + "<table><thead><tr><th>Header 1</th></tr></thead><tbody><tr><td>Cell 1</td></tr></tbody></table>"
        ))
        storage.append(NSAttributedString(string: "\nQuoted original:\n> Keep this quote"))
        harness.text = editor.text
        try harness.rerender(mounted)
        harness.flush.performFlush()
        let originalHTML = try #require(harness.html)

        // Set selection and emphasized typingAttributes with inline-code surface.
        let selection = Self.range("Both", in: editor.text)
        editor.selectedRange = selection
        let boldItalicFont = Self.emphasizedFont([.traitBold, .traitItalic])
        editor.typingAttributes[.font] = boldItalicFont
        editor.typingAttributes[.kern] = 1.25
        editor.typingAttributes[ComposeRichTextAttribute.inlineCode] = true
        editor.typingAttributes[.backgroundColor] = UIColor(BrevTheme.brevMonoLight.bgSecondary.color)

        for appearance in [ComposeBodyAppearance.light, .dark, .light] {
            harness.appearance = appearance
            try harness.rerender(mounted)
            harness.flush.performFlush()

            let expectedText = UIColor(appearance.editorTheme.textPrimary.color)
            let expectedCanvas = UIColor(appearance.editorTheme.bgPrimary.color)
            let expectedSurface = UIColor(appearance.editorTheme.bgSecondary.color)
            let expectedQuote = UIColor(appearance.editorTheme.textTertiary.color)

            // Default body text, formatted runs, and table cells adapt with > 4.5:1 contrast.
            for word in ["Testing", "Bold", "Italic", "Both", "Link", "Header 1", "Cell 1"] {
                let loc = Self.range(word, in: editor.text).location
                let fg = try #require(storage.attribute(.foregroundColor, at: loc, effectiveRange: nil) as? UIColor)
                #expect(Self.colorsMatch(fg, expectedText))
                #expect(Self.contrastRatio(between: fg, and: expectedCanvas) > 4.5)
            }

            // Explicit user-authored color is preserved untouched.
            let customLoc = Self.range("Custom", in: editor.text).location
            let preserved = try #require(storage.attribute(.foregroundColor, at: customLoc, effectiveRange: nil) as? UIColor)
            #expect(Self.colorsMatch(preserved, customColor))

            // Inline code and code block surfaces adapt with > 4.5:1 contrast.
            for snippet in ["git status", "let x = 1"] {
                let loc = Self.range(snippet, in: editor.text).location
                let bg = try #require(storage.attribute(.backgroundColor, at: loc, effectiveRange: nil) as? UIColor)
                let fg = try #require(storage.attribute(.foregroundColor, at: loc, effectiveRange: nil) as? UIColor)
                #expect(Self.colorsMatch(bg, expectedSurface))
                #expect(Self.colorsMatch(fg, expectedText))
                #expect(Self.contrastRatio(between: fg, and: bg) > 4.5)
            }

            // Protected reply quote adapts to textTertiary.
            let quoteLoc = Self.range("Keep this quote", in: editor.text).location
            let quoteColor = try #require(storage.attribute(.foregroundColor, at: quoteLoc, effectiveRange: nil) as? UIColor)
            #expect(Self.colorsMatch(quoteColor, expectedQuote))

            // typingAttributes adapt without losing bold/italic/kern.
            #expect(Self.colorsMatch(editor.typingAttributes[.foregroundColor] as? UIColor, expectedText))
            #expect(Self.colorsMatch(editor.typingAttributes[.backgroundColor] as? UIColor, expectedSurface))
            let typingFont = try #require(editor.typingAttributes[.font] as? UIFont)
            #expect(typingFont.fontDescriptor.symbolicTraits.contains([.traitBold, .traitItalic]))
            #expect(editor.typingAttributes[.kern] as? Double == 1.25)

            // Formatting traits, links, selection, and serialized HTML remain intact.
            #expect(editor.selectedRange == selection)
            let linkLoc = Self.range("Link", in: editor.text).location
            #expect(storage.attribute(.link, at: linkLoc, effectiveRange: nil) as? URL == Self.link)
            #expect(storage.attribute(.underlineStyle, at: linkLoc, effectiveRange: nil) as? Int == 1)
            #expect(harness.html == originalHTML)
        }
    }

    @Test("system-appearance rich UITextView adapts on UIKit userInterfaceStyle trait changes")
    func systemAppearanceAdaptsOnUIKitTraitChange() throws {
        let harness = Harness(text: "Testing rich editor", format: .richTextHTML, appearance: .system)
        let mounted = try harness.mount()
        defer { mounted.teardown() }
        let editor = mounted.editor

        for (style, expectedTheme) in [
            (UIUserInterfaceStyle.light, BrevTheme.brevMonoLight),
            (.dark, .brevMonoDark),
            (.light, .brevMonoLight)
        ] {
            mounted.host.traitOverrides.userInterfaceStyle = style
            mounted.host.view.setNeedsLayout()
            mounted.host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            let expectedText = UIColor(expectedTheme.textPrimary.color)
            let expectedCanvas = UIColor(expectedTheme.bgPrimary.color)
            let fg = try #require(
                editor.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
            )
            #expect(Self.colorsMatch(fg, expectedText))
            #expect(Self.contrastRatio(between: fg, and: expectedCanvas) > 4.5)
            #expect(Self.colorsMatch(editor.typingAttributes[.foregroundColor] as? UIColor, expectedText))
        }
    }

    @Test("restored rich draft resolves Dark Mode text and code backgrounds when opened in Dark Mode on iOS")
    func restoredRichDraftAdaptsWhenOpenedInDarkMode() async throws {
        let html = "<p>Draft body <code>status</code></p><pre><code>let ok = true</code></pre>"
        let restored = try await ComposeDraftBodyRestoration.prepare(
            draft: Draft(id: "ios-dark-draft", htmlBody: html),
            format: .richTextHTML
        )
        let harness = Harness(
            text: restored.attributedText.string,
            format: .richTextHTML,
            appearance: .dark,
            restoredAttributedText: restored.attributedText
        )
        let mounted = try harness.mount()
        defer { mounted.teardown() }
        let editor = mounted.editor

        let darkText = UIColor(BrevTheme.brevMonoDark.textPrimary.color)
        let darkSurface = UIColor(BrevTheme.brevMonoDark.bgSecondary.color)

        let bodyFG = try #require(
            editor.textStorage.attribute(
                .foregroundColor,
                at: Self.range("Draft body", in: editor.text).location,
                effectiveRange: nil
            ) as? UIColor
        )
        #expect(Self.colorsMatch(bodyFG, darkText))

        for snippet in ["status", "let ok = true"] {
            let loc = Self.range(snippet, in: editor.text).location
            let bg = try #require(editor.textStorage.attribute(.backgroundColor, at: loc, effectiveRange: nil) as? UIColor)
            let fg = try #require(editor.textStorage.attribute(.foregroundColor, at: loc, effectiveRange: nil) as? UIColor)
            #expect(Self.colorsMatch(bg, darkSurface))
            #expect(Self.colorsMatch(fg, darkText))
            #expect(Self.contrastRatio(between: fg, and: bg) > 4.5)
        }
    }

    @Test("converting an imported code block to Heading 1 clears stale code background while preserving unrelated backgrounds")
    func convertingCodeBlockToHeadingClearsCodeBackgroundAcrossDarkMode() throws {
        let harness = Harness(text: "", format: .richTextHTML, appearance: .light)
        let mounted = try harness.mount()
        defer { mounted.teardown() }
        let editor = mounted.editor
        let storage = editor.textStorage
        let target = try #require(harness.iosTargetBox.target)

        #expect(target.insertSanitizedHTML("<p>Plain note</p><pre><code>let x = 1</code></pre>"))
        let plainRange = Self.range("Plain note", in: editor.text)
        let unrelatedBG = UIColor.systemYellow
        storage.addAttribute(.backgroundColor, value: unrelatedBG, range: plainRange)

        let codeRange = Self.range("let x = 1", in: editor.text)
        let initialCodeBG = try #require(
            storage.attribute(.backgroundColor, at: codeRange.location, effectiveRange: nil) as? UIColor
        )
        #expect(Self.colorsMatch(initialCodeBG, UIColor(BrevTheme.brevMonoLight.bgSecondary.color)))
        #expect(storage.attribute(ComposeRichTextAttribute.codeBlockID, at: codeRange.location, effectiveRange: nil) != nil)

        // Convert the imported code block paragraph and the plain paragraph to Heading 1.
        editor.selectedRange = NSRange(location: codeRange.location, length: 0)
        target.toggleHeading(1)
        editor.selectedRange = NSRange(location: plainRange.location, length: 0)
        target.toggleHeading(1)

        // Switch Light -> Dark -> Light and verify the converted code heading has no stale code background.
        for appearance in [ComposeBodyAppearance.dark, .light, .dark] {
            harness.appearance = appearance
            try harness.rerender(mounted)

            let expectedText = UIColor(appearance.editorTheme.textPrimary.color)
            let expectedCanvas = UIColor(appearance.editorTheme.bgPrimary.color)

            let updatedCodeLoc = Self.range("let x = 1", in: editor.text).location
            #expect(storage.attribute(ComposeRichTextAttribute.codeBlockID, at: updatedCodeLoc, effectiveRange: nil) == nil)
            #expect(storage
                .attribute(ComposeRichTextAttribute.headingLevel, at: updatedCodeLoc, effectiveRange: nil) as? Int == 1)
            #expect(storage.attribute(.backgroundColor, at: updatedCodeLoc, effectiveRange: nil) == nil)
            let headingFG = try #require(
                storage.attribute(.foregroundColor, at: updatedCodeLoc, effectiveRange: nil) as? UIColor
            )
            #expect(Self.colorsMatch(headingFG, expectedText))
            #expect(Self.contrastRatio(between: headingFG, and: expectedCanvas) > 4.5)

            // Unrelated background on the non-code-block heading remains intact.
            let updatedPlainLoc = Self.range("Plain note", in: editor.text).location
            #expect(storage
                .attribute(ComposeRichTextAttribute.headingLevel, at: updatedPlainLoc, effectiveRange: nil) as? Int == 1)
            let preservedBG = try #require(
                storage.attribute(.backgroundColor, at: updatedPlainLoc, effectiveRange: nil) as? UIColor
            )
            #expect(Self.colorsMatch(preservedBG, unrelatedBG))
        }
    }

    @Test("ComposeView Match Theme handoff adapts rich UITextView body text across Light -> Dark -> Light")
    func composeViewMatchThemeHandoffAdaptsRichBodyTextAcrossDarkMode() throws {
        let suiteName = "ComposeBodyEditorAppearanceIOSTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(ComposeBodyAppearance.system.rawValue, forKey: ComposeBodyAppearance.storageKey)
        defaults.set("richText", forKey: "compose.messageFormat")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backend = MockBackend()
        let size = CGSize(width: 390, height: 844)
        func makeRoot(theme: BrevTheme) -> AnyView {
            AnyView(
                ComposeView(
                    backend: backend,
                    from: Correspondent(email: backend.account.emailAddress),
                    senderOptions: [],
                    prefill: ComposePrefill(bodyText: "Testing rich editor"),
                    recoveryDefaults: defaults
                )
                .defaultAppStorage(defaults)
                .environment(\.horizontalSizeClass, .compact)
                .brevTheme(theme)
                .environment(\.colorScheme, theme.mode.colorScheme)
                .htmlBodyRenderTarget(.staticSnapshot)
            )
        }

        let host = UIHostingController(rootView: makeRoot(theme: .brevMonoLight))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let editor = try #require(Self.editor(in: host.view))
        #expect(editor.text == "Testing rich editor")

        for (theme, style) in [
            (BrevTheme.brevMonoLight, UIUserInterfaceStyle.light),
            (.brevMonoDark, .dark),
            (.brevMonoLight, .light)
        ] {
            host.traitOverrides.userInterfaceStyle = style
            host.rootView = makeRoot(theme: theme)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))

            let currentEditor = try #require(Self.editor(in: host.view))
            #expect(currentEditor === editor)
            let expectedText = UIColor(theme.textPrimary.color)
            let expectedCanvas = UIColor(theme.bgPrimary.color)
            let fg = try #require(
                editor.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
            )
            #expect(Self.colorsMatch(fg, expectedText))
            #expect(Self.contrastRatio(between: fg, and: expectedCanvas) > 4.5)
            #expect(Self.colorsMatch(editor.typingAttributes[.foregroundColor] as? UIColor, expectedText))
        }
    }

    // MARK: - Helpers

    private static func richFixture() -> NSMutableAttributedString {
        let baseFont = UIFont.preferredFont(forTextStyle: .body)
        let value = NSMutableAttributedString(
            string: "Testing Bold Italic Both Link Custom",
            attributes: [.font: baseFont]
        )
        value.addAttribute(.font, value: emphasizedFont(.traitBold), range: range("Bold", in: value.string))
        value.addAttribute(.font, value: emphasizedFont(.traitItalic), range: range("Italic", in: value.string))
        value.addAttribute(.font, value: emphasizedFont([.traitBold, .traitItalic]), range: range("Both", in: value.string))
        value.addAttributes([.link: link, .underlineStyle: 1], range: range("Link", in: value.string))
        return value
    }

    private static func emphasizedFont(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: .body)
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }

    private static func range(_ word: String, in text: String) -> NSRange {
        (text as NSString).range(of: word)
    }

    private static func colorsMatch(_ lhs: UIColor?, _ rhs: UIColor?) -> Bool {
        guard let lhs, let rhs,
              let left = rgba(of: lhs),
              let right = rgba(of: rhs) else {
            return false
        }
        return abs(left.r - right.r) <= 0.005
            && abs(left.g - right.g) <= 0.005
            && abs(left.b - right.b) <= 0.005
            && abs(left.a - right.a) <= 0.005
    }

    private static func contrastRatio(between first: UIColor, and second: UIColor) -> Double {
        let l1 = relativeLuminance(of: first)
        let l2 = relativeLuminance(of: second)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private static func relativeLuminance(of color: UIColor) -> Double {
        guard let components = rgba(of: color) else { return 0 }
        func linearize(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return linearize(Double(components.r)) * 0.2126
            + linearize(Double(components.g)) * 0.7152
            + linearize(Double(components.b)) * 0.0722
    }

    private static func rgba(of color: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return (r, g, b, a)
        }
        var white: CGFloat = 0
        if color.getWhite(&white, alpha: &a) {
            return (white, white, white, a)
        }
        return nil
    }

    private static func editor(in view: UIView) -> ComposeBodyTextView? {
        if let editor = view as? ComposeBodyTextView { return editor }
        return view.subviews.lazy.compactMap { editor(in: $0) }.first
    }

    @MainActor
    private final class MountedHost {
        let window: UIWindow
        let host: UIHostingController<ComposeBodyEditor>
        let editor: ComposeBodyTextView

        init(window: UIWindow, host: UIHostingController<ComposeBodyEditor>, editor: ComposeBodyTextView) {
            self.window = window
            self.host = host
            self.editor = editor
        }

        func teardown() {
            window.isHidden = true
            window.rootViewController = nil
        }
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
        let iosTargetBox = ComposeIOSRichTextTargetBox()
        var appearance: ComposeBodyAppearance
        var restoredAttributedText: NSAttributedString?

        init(
            text: String,
            format: ComposeBodyFormat,
            appearance: ComposeBodyAppearance = .light,
            restoredAttributedText: NSAttributedString? = nil
        ) {
            self.text = text
            self.format = format
            self.appearance = appearance
            self.restoredAttributedText = restoredAttributedText
        }

        func root() -> ComposeBodyEditor {
            ComposeBodyEditor(
                text: Binding(get: { self.text }, set: { self.text = $0 }),
                richHTML: Binding(get: { self.html }, set: { self.html = $0 }),
                selection: Binding(get: { self.selection }, set: { self.selection = $0 }),
                insertionPoint: Binding(get: { self.insertion }, set: { self.insertion = $0 }),
                bodyFormat: format,
                appearance: appearance,
                htmlPublicationFlushBox: flush,
                textCheckingConfiguration: ComposeTextCheckingPolicy.configuration(isEnabled: false),
                iosRichTextTargetBox: iosTargetBox,
                quoteProtection: Self.quote,
                restoredAttributedText: restoredAttributedText
            )
        }

        func mount() throws -> MountedHost {
            let size = CGSize(width: 390, height: 600)
            let host = UIHostingController(rootView: root())
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            let editor = try #require(ComposeBodyEditorAppearanceIOSTests.editor(in: host.view))
            return MountedHost(window: window, host: host, editor: editor)
        }

        func rerender(_ mounted: MountedHost) throws {
            mounted.host.rootView = root()
            mounted.host.view.setNeedsLayout()
            mounted.host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            let current = ComposeBodyEditorAppearanceIOSTests.editor(in: mounted.host.view)
            try #require(current === mounted.editor, "Rerender must reuse the native UITextView")
        }
    }
}
#endif
