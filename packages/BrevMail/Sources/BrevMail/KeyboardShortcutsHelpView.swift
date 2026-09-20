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
import BrevThemes
import SwiftUI

/// One row in the keyboard-shortcuts reference: a user-facing action name and
/// its display-form shortcut glyphs (e.g. "⌘⇧U"). `alternates` lists secondary
/// bindings registered for the same action.
struct MailKeyboardShortcut: Equatable, Sendable {
    let action: String
    let shortcut: String
    let alternates: String?
    /// Whether the command is registered only on macOS (the help window is
    /// macOS-only today, but the inventory is shared with iOS tests).
    let isMacOSOnly: Bool

    init(action: String, shortcut: String, alternates: String? = nil, isMacOSOnly: Bool = false) {
        self.action = action
        self.shortcut = shortcut
        self.alternates = alternates
        self.isMacOSOnly = isMacOSOnly
    }
}

struct MailKeyboardShortcutSection: Equatable, Sendable {
    let title: String
    let entries: [MailKeyboardShortcut]
}

/// The single source of truth for the shortcuts listed in the Keyboard
/// Shortcuts help window. Every entry must correspond to a real
/// `keyboardShortcut` registration in `MailCommands`, `BrevMailCommands`
/// (macOS), `MailUndoCommands`, or the compose window — the
/// `MailKeyboardShortcutInventoryTests` pin that contract.
enum MailKeyboardShortcutInventory {
    static var sections: [MailKeyboardShortcutSection] {
        #if os(macOS)
        let mailUndoShortcut = "⌘Z"
        #else
        let mailUndoShortcut = "⌘⌥Z"
        #endif
        let messages: [MailKeyboardShortcut] = [
            .init(
                action: String(localized: "New Message", bundle: .module),
                shortcut: "⌘N"
            ),
            .init(
                action: String(localized: "Reply", bundle: .module),
                shortcut: "⌘R"
            ),
            .init(
                action: String(localized: "Reply All", bundle: .module),
                shortcut: "⌘⇧R"
            ),
            .init(
                action: String(localized: "Forward", bundle: .module),
                shortcut: "⌘⇧F",
                alternates: "⌘F"
            ),
            .init(
                action: String(localized: "Send", bundle: .module),
                shortcut: "⌘↵"
            ),
            .init(
                action: String(localized: "Cancel / Close Compose", bundle: .module),
                shortcut: "Escape"
            ),
        ]
        let actions: [MailKeyboardShortcut] = [
            .init(
                action: String(localized: "Archive", bundle: .module),
                shortcut: "⌘E"
            ),
            .init(
                action: String(localized: "Delete", bundle: .module),
                shortcut: "⌘⌫"
            ),
            .init(
                action: String(localized: "Toggle Read / Unread", bundle: .module),
                shortcut: "⌘⇧U",
                alternates: "⌘U"
            ),
            // Canonical terminology is Flag/Unflag.
            .init(
                action: String(localized: "Flag / Unflag", bundle: .module),
                shortcut: "⌘⇧L",
                alternates: "⌘S"
            ),
            .init(
                action: String(localized: "Report Junk", bundle: .module),
                shortcut: "⌘⇧J"
            ),
        ]
        let navigation: [MailKeyboardShortcut] = [
            .init(
                action: String(localized: "Previous Message", bundle: .module),
                shortcut: "⌘↑",
                alternates: "⌘["
            ),
            .init(
                action: String(localized: "Next Message", bundle: .module),
                shortcut: "⌘↓",
                alternates: "⌘]"
            ),
            // Two distinct search bindings exist: ⌘/ focuses the list's
            // search field on every platform; ⌘⌥F is the macOS Edit-menu
            // "Search Mail" command (Apple Mail parity).
            .init(
                action: String(localized: "Focus Search", bundle: .module),
                shortcut: "⌘/"
            ),
            .init(
                action: String(localized: "Search Mail", bundle: .module),
                shortcut: "⌘⌥F",
                isMacOSOnly: true
            ),
            .init(
                action: String(localized: "Undo Mail Action", bundle: .module),
                shortcut: mailUndoShortcut
            ),
            .init(
                action: String(localized: "Redo", bundle: .module),
                shortcut: "⌘⇧Z"
            ),
        ]
        let mailbox: [MailKeyboardShortcut] = [
            .init(
                action: String(localized: "Get New Mail", bundle: .module),
                shortcut: "⌘⌥R"
            ),
            .init(
                action: String(localized: "Print…", bundle: .module),
                shortcut: "⌘P",
                isMacOSOnly: true
            ),
            .init(
                action: String(localized: "Export as PDF…", bundle: .module),
                shortcut: "⌘⇧P",
                isMacOSOnly: true
            ),
            .init(
                action: String(localized: "Import Mail…", bundle: .module),
                shortcut: "⌘⇧I",
                isMacOSOnly: true
            ),
            .init(
                action: String(localized: "Export Mail…", bundle: .module),
                shortcut: "⌘⇧E",
                isMacOSOnly: true
            ),
            .init(
                action: String(localized: "AI Sidebar", bundle: .module),
                shortcut: "⌘⌥I",
                isMacOSOnly: true
            ),
            .init(
                action: String(localized: "Settings", bundle: .module),
                shortcut: "⌘,",
                isMacOSOnly: true
            ),
        ]
        let sections: [MailKeyboardShortcutSection] = [
            .init(title: String(localized: "Messages", bundle: .module), entries: messages),
            .init(title: String(localized: "Message Actions", bundle: .module), entries: actions),
            .init(title: String(localized: "Navigation", bundle: .module), entries: navigation),
            .init(title: String(localized: "Mailbox", bundle: .module), entries: mailbox),
        ]
        #if os(macOS)
        return sections
        #else
        return sections.map { section in
            MailKeyboardShortcutSection(
                title: section.title,
                entries: section.entries.filter { !$0.isMacOSOnly }
            )
        }
        #endif
    }
}

/// Read-only reference panel listing every Brev keyboard shortcut.
///
/// Shown in its own window via the Help menu. Intentionally simple —
/// no interaction beyond scrolling and window close.
public struct KeyboardShortcutsHelpView: View {
    @Environment(\.brevTheme) private var theme

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                ForEach(MailKeyboardShortcutInventory.sections, id: \.title) { section in
                    sectionView(section)
                }
            }
            .padding(BrevSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.bgPrimary.color)
        #if os(macOS)
            .frame(minWidth: 380, idealWidth: 440, minHeight: 400, idealHeight: 520)
        #endif
    }

    @ViewBuilder
    private func sectionView(_ section: MailKeyboardShortcutSection) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Text(section.title)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)

            BrevDivider()

            ForEach(section.entries, id: \.action) { entry in
                HStack {
                    Text(entry.action)
                        .brevFont(.body)
                        .foregroundStyle(theme.textPrimary.color)
                    Spacer()
                    if let alternates = entry.alternates {
                        Text(alternates)
                            .brevFont(.footnote)
                            .foregroundStyle(theme.textSecondary.color)
                    }
                    Text(entry.shortcut)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                        .padding(.horizontal, BrevSpacing.xs)
                        .padding(.vertical, BrevSpacing.xxs)
                        .background(
                            RoundedRectangle(cornerRadius: BrevRadius.sm)
                                .fill(theme.bgSecondary.color)
                        )
                }
                .padding(.vertical, BrevSpacing.xxs)
            }
        }
    }
}
