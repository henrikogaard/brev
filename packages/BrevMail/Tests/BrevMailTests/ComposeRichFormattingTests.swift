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

/// Formatting commands found broken in native QA on #279: the Format menu's
/// Bold and Italic did nothing, the composer had no Cmd-B/I/U, a confirmed
/// link was lost when the sheet left focus elsewhere, and reopened Drafts
/// showed the HTML importer's Times instead of the editor font.
@Suite("Compose rich formatting commands", .serialized)
@MainActor
struct ComposeRichFormattingTests {
    @Test("every Format menu text command names a selector the macOS editor answers")
    func formatCommandsReachTheEditor() throws {
        let harness = Harness(text: "Body")
        let editor = try harness.mount()
        // Undo and Redo belong to the window's undo manager, not the text view.
        for command in ComposeRichTextCommand.allCases where command != .undo && command != .redo {
            #expect(editor.responds(to: command.actionSelector), "\(command) is a no-op in the editor")
        }
    }

    @Test("Clear Formatting returns the selection to plain body text")
    func clearFormatting() throws {
        let harness = Harness(text: "Keep styled words")
        let editor = try harness.mount()
        let styled = (editor.string as NSString).range(of: "styled")
        editor.setSelectedRange(styled)
        try harness.perform(.bold, in: editor)
        try harness.perform(.underline, in: editor)
        editor.setSelectedRange(styled)
        try harness.perform(.clearFormatting, in: editor)
        #expect(!Self.traits(in: editor, at: styled.location).contains(.bold))
        #expect(editor.textStorage?.attribute(.underlineStyle, at: styled.location, effectiveRange: nil) == nil)
        #expect(harness.html == "Keep styled words")
    }

    @Test("Bold and Italic toggle the selection and keep the HTML in step", arguments: [false, true])
    func toggleSelection(italic: Bool) throws {
        let harness = Harness(text: "Plain word end")
        let editor = try harness.mount()
        let word = (editor.string as NSString).range(of: "word")
        editor.setSelectedRange(word)
        let trait: NSFontDescriptor.SymbolicTraits = italic ? .italic : .bold
        let tag = italic ? "em" : "strong"
        try harness.perform(italic ? .italic : .bold, in: editor)
        #expect(Self.traits(in: editor, at: word.location).contains(trait))
        #expect(!Self.traits(in: editor, at: 0).contains(trait))
        #expect(harness.html?.contains("<\(tag)>word</\(tag)>") == true)
        try harness.perform(italic ? .italic : .bold, in: editor)
        #expect(!Self.traits(in: editor, at: word.location).contains(trait))
        #expect(harness.html?.contains("<\(tag)>") == false)
    }

    @Test("Bold and Italic with no selection apply to the next typed text")
    func toggleTyping() throws {
        let harness = Harness(text: "Start ")
        let editor = try harness.mount()
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        try harness.perform(.bold, in: editor)
        try harness.perform(.italic, in: editor)
        editor.insertText("both", replacementRange: editor.selectedRange())
        harness.flush.performFlush()
        let typed = (editor.string as NSString).range(of: "both")
        #expect(Self.traits(in: editor, at: typed.location).contains([.bold, .italic]))
        #expect(!Self.traits(in: editor, at: 0).contains(.bold))
        #expect(harness.html?.contains("<strong><em>both</em></strong>") == true)
    }

    @Test("Cmd-B, Cmd-I and Cmd-U format the focused body instead of reaching the main menu")
    func keyboardShortcuts() throws {
        let harness = Harness(text: "Bold Italic Under")
        let editor = try harness.mount(inWindow: true)
        let text = editor.string as NSString
        for (word, key, check) in [
            ("Bold", "b", { (editor: NSTextView, at: Int) in Self.traits(in: editor, at: at).contains(.bold) }),
            ("Italic", "i", { (editor: NSTextView, at: Int) in Self.traits(in: editor, at: at).contains(.italic) }),
            ("Under", "u", { (editor: NSTextView, at: Int) in
                editor.textStorage?.attribute(.underlineStyle, at: at, effectiveRange: nil) != nil
            })
        ] {
            let range = text.range(of: word)
            editor.setSelectedRange(range)
            #expect(try editor.performKeyEquivalent(with: Self.commandKey(key, window: editor.window)))
            #expect(check(editor, range.location), "Cmd-\(key) did not format \(word)")
        }
        harness.flush.performFlush()
        #expect(harness.html == "<strong>Bold</strong> <em>Italic</em> <u>Under</u>")
    }

    @Test("Cmd-B is left alone when the body is not the focused view")
    func shortcutsNeedFocus() throws {
        let harness = Harness(text: "Bold")
        let editor = try harness.mount(inWindow: true)
        editor.window?.makeFirstResponder(nil)
        editor.setSelectedRange(NSRange(location: 0, length: 4))
        #expect(try !editor.performKeyEquivalent(with: Self.commandKey("b", window: editor.window)))
        #expect(!Self.traits(in: editor, at: 0).contains(.bold))
    }

    @Test("a confirmed link reaches the editor even when another field holds focus")
    func linkWithoutFocus() throws {
        let harness = Harness(text: "Read the website today")
        let editor = try harness.mount(inWindow: true)
        let word = (editor.string as NSString).range(of: "website")
        editor.setSelectedRange(word)
        let elsewhere = NSTextField()
        editor.window?.contentView?.addSubview(elsewhere)
        editor.window?.makeFirstResponder(elsewhere)
        let url = try #require(URL(string: "https://example.invalid/qa"))
        harness.targetBox.target?.brevApplyLink(ComposeBodyEditorLinkPayload(url: url, displayText: "website"))
        harness.flush.performFlush()
        let link = editor.textStorage?.attribute(.link, at: word.location, effectiveRange: nil)
        #expect((link as? URL) == url)
        #expect(harness.html == "Read the <a href=\"https://example.invalid/qa\">website</a> today")
        #expect(editor.window?.firstResponder === editor)
    }

    @Test("a reopened Draft uses the editor font and keeps its emphasis", arguments: MailboxFontFamily.allCases)
    func restoredTypography(family: MailboxFontFamily) async throws {
        let html = "Plain <strong>bold</strong> <em>italic</em> <u>under</u>"
        let draft = Draft(id: UUID().uuidString, subject: "Restored", htmlBody: html)
        let restored = try await ComposeDraftBodyRestoration.prepare(draft: draft, format: .richTextHTML)
        let harness = Harness(text: restored.attributedText.string)
        harness.family = family
        harness.restored = restored.attributedText
        let editor = try harness.mount()
        let expected = ComposeEditorTypography.nsFont(family: family, textSize: harness.size)
        let text = editor.string as NSString
        for (word, traits) in [
            ("Plain", NSFontDescriptor.SymbolicTraits()),
            ("bold", .bold),
            ("italic", .italic),
            ("under", NSFontDescriptor.SymbolicTraits())
        ] {
            let font = try #require(editor.textStorage?.attribute(
                .font, at: text.range(of: word).location, effectiveRange: nil
            ) as? NSFont)
            #expect(font.pointSize == expected.pointSize, "\(word) kept the importer's size")
            #expect(font.fontDescriptor.symbolicTraits.intersection([.bold, .italic]) == traits)
            if traits.isEmpty {
                // Emphasis may fall back to the system face (SF Rounded has no italic).
                #expect(font.familyName == expected.familyName, "\(word) kept the importer's family")
            }
        }
        #expect(harness.html == restored.initialEditorHTML)
    }

    @Test("the body paints its own background only when it contrasts with the window theme", arguments: [
        (ComposeBodyAppearance.system, BrevThemeMode.dark, false),
        (.system, .light, false),
        (.dark, .dark, false),
        (.light, .light, false),
        (.light, .dark, true),
        (.dark, .light, true)
    ])
    func paintsContrastingBody(fixture: (ComposeBodyAppearance, BrevThemeMode, Bool)) {
        #expect(fixture.0.paintsOwnBackground(themeMode: fixture.1) == fixture.2)
    }

    // MARK: - Helpers

    private static func traits(in editor: NSTextView, at location: Int) -> NSFontDescriptor.SymbolicTraits {
        let font = editor.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        return font?.fontDescriptor.symbolicTraits ?? []
    }

    private static func commandKey(_ key: String, window: NSWindow?) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key,
            isARepeat: false,
            keyCode: 0
        ))
    }

    @MainActor
    private final class Harness {
        var text: String
        var html: String?
        var selection: ComposeBodyTextSelection?
        var insertion: ComposeBodyInsertionPoint?
        var family = MailboxFontFamily.system
        var size = MailboxTextSize.medium
        var restored: NSAttributedString?
        let flush = ComposeHTMLPublicationFlushBox()
        let targetBox = ComposeMacRichTextTargetBox()
        private var host: NSHostingView<ComposeBodyEditor>?
        private var window: NSWindow?

        init(text: String) {
            self.text = text
        }

        func mount(inWindow: Bool = false) throws -> ComposeRichTextView {
            let host = NSHostingView(rootView: ComposeBodyEditor(
                text: Binding(get: { self.text }, set: { self.text = $0 }),
                richHTML: Binding(get: { self.html }, set: { self.html = $0 }),
                selection: Binding(get: { self.selection }, set: { self.selection = $0 }),
                insertionPoint: Binding(get: { self.insertion }, set: { self.insertion = $0 }),
                bodyFormat: .richTextHTML,
                appearance: .light,
                htmlPublicationFlushBox: flush,
                textCheckingConfiguration: ComposeTextCheckingPolicy.configuration(isEnabled: false),
                fontFamily: family,
                textSize: size,
                macRichTextTargetBox: targetBox,
                restoredAttributedText: restored
            ))
            host.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
            if inWindow {
                let window = NSWindow(
                    contentRect: host.frame,
                    styleMask: [.titled],
                    backing: .buffered,
                    defer: true
                )
                window.isReleasedWhenClosed = false
                window.contentView = host
                self.window = window
            }
            host.layoutSubtreeIfNeeded()
            self.host = host
            let editor = try #require(Self.editor(in: host))
            if inWindow { window?.makeFirstResponder(editor) }
            flush.performFlush()
            return editor
        }

        /// Sends the command the way the Format menu does when the body has focus.
        func perform(_ command: ComposeRichTextCommand, in editor: ComposeRichTextView) throws {
            try #require(editor.tryToPerform(command.actionSelector, with: nil))
            flush.performFlush()
        }

        private static func editor(in view: NSView) -> ComposeRichTextView? {
            if let editor = view as? ComposeRichTextView { return editor }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
    }
}
#endif
