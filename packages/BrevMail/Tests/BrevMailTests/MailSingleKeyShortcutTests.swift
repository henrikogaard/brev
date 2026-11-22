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

    @Test("reader navigation and message actions target only the displayed selection")
    func readerRouting() {
        let header = MessageHeader(id: "a", threadID: "t", folderID: "inbox", from: .init(email: "a@example.org"),
                                   subject: "A", snippet: "", date: .now)
        // The next header is in another conversation in the same folder.
        let next = MessageHeader(id: "b", threadID: "u", folderID: "inbox", from: header.from,
                                 subject: "B", snippet: "", date: .now)
        let navigation = MailNavigationState(selectedMessageID: header.id, currentFolderHeaders: [header, next])
        var actions: [MessageContextMenuAction] = []
        func run(_ key: MailSingleKeyShortcut, header: MessageHeader?, allowed: Bool = true) -> Bool {
            key.performInReader(navigation: navigation, header: header, sourceID: nil) { action, _ in
                guard allowed else { return false }
                actions.append(action)
                return true
            }
        }
        #expect(run(.archive, header: header))
        #expect(!run(.delete, header: header, allowed: false))
        #expect(run(.next, header: header))
        #expect(navigation.selectedMessageID == next.id)
        #expect(!run(.delete, header: header))
        #expect(run(.previous, header: next))
        navigation.bulkSelection = [header.id, next.id]
        #expect(!run(.star, header: header))
        #expect(actions == [.archive])
    }

    @Test("tooltips name the single key only while the setting is on")
    func tooltipHints() throws {
        #expect(MailSingleKeyShortcut.archive.help("Archive", enabled: true) == "Archive (E)")
        #expect(MailSingleKeyShortcut.delete.help("Delete", enabled: true) == "Delete (#)")
        #expect(MailSingleKeyShortcut.snooze.help("Snooze", enabled: false) == "Snooze")
        let strings = try LocalizationCatalogTestSupport.loadCatalogStrings()
        #expect(MailSingleKeyShortcut
            .legend == "In the message list or reader: J next · K previous · E archive · R reply · S star · # delete · H snooze.")
        let legendEntry = try #require(strings[MailSingleKeyShortcut.legend] as? [String: Any])
        let legendNB = (legendEntry["localizations"] as? [String: Any])?["nb"] as? [String: Any]
        #expect((legendNB?["stringUnit"] as? [String: Any])?["value"] as? String != nil)
        let entry = try #require(strings["%@ (%@)"] as? [String: Any])
        let nb = (entry["localizations"] as? [String: Any])?["nb"] as? [String: Any]
        #expect((nb?["stringUnit"] as? [String: Any])?["value"] as? String == "%1$@ (%2$@)")
    }
}
#endif
