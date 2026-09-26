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

@testable import BrevMail
import Testing

/// Pins the help-window shortcut inventory against the real command
/// registrations in `MailCommands`, `BrevMailCommands` (macOS),
/// `MailUndoCommands`, and the compose window. If a registration changes, the
/// matching expectation here must change with it — the help panel is otherwise
/// invisible drift.
@Suite("MailKeyboardShortcutInventory")
struct MailKeyboardShortcutInventoryTests {
    @Test("every section has a title and at least one fully-formed entry")
    func sectionsAreWellFormed() {
        let sections = MailKeyboardShortcutInventory.sections

        #expect(!sections.isEmpty)
        for section in sections {
            #expect(!section.title.isEmpty)
            #expect(!section.entries.isEmpty, "section \(section.title) is empty")
            for entry in section.entries {
                #expect(!entry.action.isEmpty)
                #expect(!entry.shortcut.isEmpty, "\(entry.action) has no shortcut")
            }
        }
    }

    @Test("no action is listed twice across the inventory")
    func actionsAreUnique() {
        let actions = MailKeyboardShortcutInventory.sections
            .flatMap(\.entries)
            .map(\.action)

        #expect(Set(actions).count == actions.count)
    }

    @Test("registered shortcuts are listed with their real bindings")
    func inventoryMatchesRegistrations() {
        let entries = MailKeyboardShortcutInventory.sections.flatMap(\.entries)

        func entry(_ action: String) -> MailKeyboardShortcut? {
            entries.first { $0.action == action }
        }

        // MailCommands (both platforms).
        #expect(entry("New Message")?.shortcut == "⌘N")
        #expect(entry("Reply")?.shortcut == "⌘R")
        #expect(entry("Reply All")?.shortcut == "⌘⇧R")
        #expect(entry("Forward")?.shortcut == "⌘⇧F")
        #expect(entry("Forward")?.alternates == "⌘F")
        #expect(entry("Archive")?.shortcut == "⌘E")
        #expect(entry("Delete")?.shortcut == "⌘⌫")
        #expect(entry("Toggle Read / Unread")?.shortcut == "⌘⇧U")
        #expect(entry("Toggle Read / Unread")?.alternates == "⌘U")
        #expect(entry("Flag / Unflag")?.shortcut == "⌘⇧L")
        #expect(entry("Flag / Unflag")?.alternates == "⌘S")
        #expect(entry("Report Junk")?.shortcut == "⌘⇧J")
        #expect(entry("Previous Message")?.shortcut == "⌘↑")
        #expect(entry("Previous Message")?.alternates == "⌘[")
        #expect(entry("Next Message")?.shortcut == "⌘↓")
        #expect(entry("Next Message")?.alternates == "⌘]")
        #expect(entry("Focus Search")?.shortcut == "⌘/")
        #expect(entry("Get New Mail")?.shortcut == "⌘⌥R")
        #expect(entry("Message Viewer")?.shortcut == "⌘0")

        // iPad preserves native text Undo/Redo and gives mail Undo a distinct chord.
        #if os(macOS)
        #expect(entry("Undo Mail Action")?.shortcut == "⌘Z")
        #else
        #expect(entry("Undo Mail Action")?.shortcut == "⌘⌥Z")
        #endif
        #expect(entry("Undo Mail Action")?.isMacOSOnly == false)

        // Compose window.
        #expect(entry("Send")?.shortcut == "⌘↵")
        #expect(entry("Cancel / Close Compose")?.shortcut == "Escape")
    }

    @Test("macOS-only entries match registrations gated behind macOS commands")
    func macOSOnlyEntriesMatchGatedRegistrations() {
        let entries = MailKeyboardShortcutInventory.sections.flatMap(\.entries)

        func isMacOSOnly(_ action: String) -> Bool? {
            entries.first { $0.action == action }?.isMacOSOnly
        }

        // Registered only in BrevMailCommands (macOS app target) or behind
        // `#if os(macOS)` in MailCommands.
        #if os(macOS)
        let expectedPlatformEntry: Bool? = true
        #else
        let expectedPlatformEntry: Bool? = nil
        #endif
        #expect(isMacOSOnly("Search Mail") == expectedPlatformEntry)
        #expect(isMacOSOnly("Print…") == expectedPlatformEntry)
        #expect(isMacOSOnly("Export as PDF…") == expectedPlatformEntry)
        #expect(isMacOSOnly("Import Mail…") == expectedPlatformEntry)
        #expect(isMacOSOnly("Export Mail…") == expectedPlatformEntry)
        #expect(isMacOSOnly("AI Sidebar") == expectedPlatformEntry)
        #expect(isMacOSOnly("Redo") == false)

        // Settings (⌘,) is registered by the macOS app only.
        #expect(isMacOSOnly("Settings") == expectedPlatformEntry)
        #expect(isMacOSOnly("Message Viewer") == expectedPlatformEntry)
    }
}
