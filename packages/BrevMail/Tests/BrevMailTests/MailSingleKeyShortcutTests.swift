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
import BrevSettings
import SwiftUI
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
        var actions: [MailSingleKeyShortcut] = []
        var bodyText = "", searchText = ""
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: MailKeyboardPreferences.singleKeyShortcuts)
        // Mount the real controls inside a pane that still considers itself focused.
        let host = NSHostingView(rootView: VStack {
            MessageListSearchField(text: Binding(get: { searchText }, set: { searchText = $0 }), prompt: "Search")
            ComposeBodyEditor(
                text: Binding(get: { bodyText }, set: { bodyText = $0 }),
                richHTML: .constant(nil), selection: .constant(nil), insertionPoint: .constant(nil),
                bodyFormat: .plainText, appearance: .light,
                textCheckingConfiguration: ComposeTextCheckingPolicy.configuration(isEnabled: false)
            )
        }
        .focusable()
        .modifier(MailSingleKeyShortcutModifier(focused: true) { actions.append($0); return true })
        .defaultAppStorage(defaults))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        let compose = try #require(descendant(ComposeRichTextView.self, in: host))
        try #require(window.makeFirstResponder(compose))
        try typeShortcutLetters(in: window)
        #expect(compose.string == "erjksh#")
        #expect(actions.isEmpty)

        let search = try #require(descendant(NSSearchField.self, in: host))
        search.selectText(nil)
        let editor = try #require(search.currentEditor() as? NSTextView)
        #expect(window.firstResponder === editor)
        try typeShortcutLetters(in: window)
        #expect(editor.string == "erjksh#")
        #expect(actions.isEmpty)
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { descendant(type, in: $0) }.first
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
            NSApplication.shared.sendEvent(event)
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
        // Unread-only thread presentation hides this selected read card.
        #expect(!run(.archive, header: nil))
        #expect(run(.next, header: nil))
        #expect(navigation.selectedMessageID == next.id)
        #expect(run(.previous, header: nil))
        #expect(navigation.selectedMessageID == header.id)
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
        let entry = try #require(strings["mail.shortcut.tooltip"] as? [String: Any])
        let nb = (entry["localizations"] as? [String: Any])?["nb"] as? [String: Any]
        #expect((nb?["stringUnit"] as? [String: Any])?["value"] as? String == "%1$@ (%2$@)")
    }

    @Test("J and K step through Updates selectable rows using the same flat order as arrow keys")
    func updatesTabSingleKeyNavigation() {
        let now = Date(timeIntervalSince1970: 1_735_689_600)
        let first = MessageHeader(
            id: "u1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "News A", email: "a@news.example"),
            subject: "Digest 1",
            snippet: "",
            date: now
        )
        let bundled1 = MessageHeader(
            id: "u2",
            threadID: "t2",
            folderID: "inbox",
            from: Correspondent(name: "News B", email: "b@news.example"),
            subject: "Digest 2a",
            snippet: "",
            date: now.addingTimeInterval(-60)
        )
        let bundled2 = MessageHeader(
            id: "u3",
            threadID: "t3",
            folderID: "inbox",
            from: Correspondent(name: "News B", email: "b@news.example"),
            subject: "Digest 2b",
            snippet: "",
            date: now.addingTimeInterval(-120)
        )
        let last = MessageHeader(
            id: "u4",
            threadID: "t4",
            folderID: "inbox",
            from: Correspondent(name: "News C", email: "c@news.example"),
            subject: "Digest 3",
            snippet: "",
            date: now.addingTimeInterval(-180)
        )
        let all = [first, bundled1, bundled2, last]
        let collapsedRows = UpdatesSenderBundler.selectableHeaders(from: all, sourceID: nil, expandedBundleIDs: [])
        #expect(collapsedRows.map(\.id) == ["u1", "u4"])

        let navigation = MailNavigationState(selectedMessageID: "u1", currentFolderHeaders: collapsedRows)
        #expect(MailSingleKeyShortcut.next.performInReader(navigation: navigation, header: first, sourceID: nil) { _, _ in
            false
        })
        #expect(navigation.selectedMessageID == "u4")
        #expect(MailSingleKeyShortcut.previous.performInReader(navigation: navigation, header: last, sourceID: nil) { _, _ in
            false
        })
        #expect(navigation.selectedMessageID == "u1")
    }
}
#endif
