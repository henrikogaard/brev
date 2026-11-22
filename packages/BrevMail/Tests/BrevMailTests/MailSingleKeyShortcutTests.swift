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
@testable import BrevMail
import Testing

@Suite("Single-key mail shortcuts")
@MainActor
struct MailSingleKeyShortcutTests {
    @Test("only unmodified actions and a layout-produced number sign are accepted")
    func commands() {
        let expected: [String: MailSingleKeyShortcut] = [
            "e": .archive, "r": .reply, "s": .star, "#": .delete,
            "j": .next, "k": .previous, "h": .snooze,
        ]
        for (key, action) in expected {
            #expect(MailSingleKeyShortcut.match(key, modifiers: []) == action)
            #expect(MailSingleKeyShortcut.match(key, modifiers: [.command]) == nil)
            #expect(MailSingleKeyShortcut.match(key, modifiers: [.control]) == nil)
        }
        #expect(MailSingleKeyShortcut.match("#", modifiers: [.shift]) == .delete)
        #expect(MailSingleKeyShortcut.match("#", modifiers: [.option]) == .delete)
        #expect(MailSingleKeyShortcut.match("J", modifiers: [.shift]) == nil)
        #expect(MailSingleKeyShortcut.match("h", modifiers: [.option]) == nil)
        #expect(MailSingleKeyShortcut.match("3", modifiers: [.shift]) == nil)
    }

    @Test("compose body and search field retain typed shortcut characters")
    func nativeTextInputs() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 180),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let compose = ComposeRichTextView(frame: window.contentLayoutRect)
        window.contentView = compose
        #expect(window.makeFirstResponder(compose))
        try typeShortcutLetters(in: window)
        #expect(compose.string == "erjksh#")

        let search = NSSearchField(frame: NSRect(x: 0, y: 0, width: 260, height: 30))
        window.contentView = search
        search.selectText(nil)
        let editor = try #require(search.currentEditor() as? NSTextView)
        #expect(window.firstResponder === editor)
        try typeShortcutLetters(in: window)
        #expect(editor.string == "erjksh#")
    }

    private func typeShortcutLetters(in window: NSWindow) throws {
        for character in "erjksh#" {
            let key = String(character)
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: key,
                charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0
            ))
            // Even a stale SwiftUI focus value cannot claim a native editor's event.
            #expect(MailSingleKeyShortcut.resolve(event, window: window, enabled: true, focused: true) == nil)
            window.sendEvent(event)
        }
    }

    @Test("the setting, repeated events and pane focus gate an otherwise valid key")
    func paneOwnership() throws {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        func event(repeating: Bool = false) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "e",
                charactersIgnoringModifiers: "e", isARepeat: repeating, keyCode: 14
            ))
        }
        let press = try event()
        #expect(MailSingleKeyShortcut.resolve(press, window: window, enabled: true, focused: true) == .archive)
        #expect(MailSingleKeyShortcut.resolve(press, window: window, enabled: false, focused: true) == nil)
        #expect(MailSingleKeyShortcut.resolve(press, window: window, enabled: true, focused: false) == nil)
        #expect(try MailSingleKeyShortcut.resolve(event(repeating: true), window: window, enabled: true, focused: true) == nil)
    }

    @Test("tooltips name the single key only while the setting is on")
    func tooltipHints() throws {
        #expect(MailSingleKeyShortcut.archive.help("Archive", enabled: true) == "Archive (E)")
        #expect(MailSingleKeyShortcut.delete.help("Delete", enabled: true) == "Delete (#)")
        #expect(MailSingleKeyShortcut.snooze.help("Snooze", enabled: false) == "Snooze")
        let strings = try LocalizationCatalogTestSupport.loadCatalogStrings()
        let entry = try #require(strings["%@ (%@)"] as? [String: Any])
        let nb = (entry["localizations"] as? [String: Any])?["nb"] as? [String: Any]
        #expect((nb?["stringUnit"] as? [String: Any])?["value"] as? String == "%1$@ (%2$@)")
    }
}
#endif
