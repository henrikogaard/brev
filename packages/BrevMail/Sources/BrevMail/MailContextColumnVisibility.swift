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

import SwiftUI

/// Constants and helpers for the macOS AI Sidebar inspector column.
enum MailContextColumnVisibility {
    /// Character used with `keyboardShortcutModifiers` for the open/close chord.
    static let keyboardShortcutKey: Character = "i"

    /// Modifier set for the open/close chord (`⌘⌥I`).
    static let keyboardShortcutModifiers: EventModifiers = [.command, .option]

    /// Accessibility / toolbar label.
    static var toolbarLabel: String { String(localized: "AI Sidebar", bundle: .module) }

    /// Title shown when the sidebar has no selected message context yet.
    ///
    /// Names the missing state rather than repeating `toolbarLabel`: the column
    /// already carries that title at its top, so the idle panel below printed
    /// "AI Sidebar" a second time and said nothing about why it was empty.
    static let idleTitle = "No message selected"

    /// Trailing-sidebar glyph, as in Apple's inspector toggles: the button
    /// reads as "show or hide the right column", not as an AI action.
    static let toolbarSymbolName = "sidebar.right"
}

/// Root-owned toggle action shared by the native toolbar and macOS commands.
struct MailContextColumnAction {
    var isPresented = false
    var isAvailable = true

    private let action: @MainActor () -> Void

    init(
        isPresented: Bool = false,
        isAvailable: Bool = true,
        action: @escaping @MainActor () -> Void
    ) {
        self.isPresented = isPresented
        self.isAvailable = isAvailable
        self.action = action
    }

    var label: String {
        isPresented ? String(localized: "Hide AI Sidebar", bundle: .module) : MailContextColumnVisibility.toolbarLabel
    }

    @MainActor
    func toggle() {
        guard isAvailable else { return }
        action()
    }
}
