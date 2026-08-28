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
    static let toolbarLabel = "AI Sidebar"

    /// Title shown when the sidebar has no selected message context yet.
    ///
    /// Names the missing state rather than repeating `toolbarLabel`: the column
    /// already carries that title at its top, so the idle panel below printed
    /// "AI Sidebar" a second time and said nothing about why it was empty.
    static let idleTitle = "No message selected"

    /// AI-specific SF Symbol for the assistant sidebar toggle.
    static let toolbarSymbolName = "sparkles"
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
        isPresented ? "Hide AI Sidebar" : MailContextColumnVisibility.toolbarLabel
    }

    @MainActor
    func toggle() {
        guard isAvailable else { return }
        action()
    }
}
