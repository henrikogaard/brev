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

private struct ShortcutEntry: Identifiable {
    let id = UUID()
    let action: String
    let shortcut: String
}

private let shortcutSections: [(title: String, entries: [ShortcutEntry])] = [
    (
        title: "Messages",
        entries: [
            ShortcutEntry(action: "New Message", shortcut: "⌘N"),
            ShortcutEntry(action: "Reply", shortcut: "⌘R"),
            ShortcutEntry(action: "Reply All", shortcut: "⌘⇧R"),
            ShortcutEntry(action: "Forward", shortcut: "⌘⇧F"),
            ShortcutEntry(action: "Send", shortcut: "⌘↵"),
            ShortcutEntry(action: "Cancel / Close Compose", shortcut: "Escape"),
        ]
    ),
    (
        title: "Message Actions",
        entries: [
            ShortcutEntry(action: "Archive", shortcut: "⌘E"),
            ShortcutEntry(action: "Delete", shortcut: "⌘⌫"),
            ShortcutEntry(action: "Toggle Read / Unread", shortcut: "⌘U"),
            ShortcutEntry(action: "Toggle Star / Flag", shortcut: "⌘S"),
            ShortcutEntry(action: "Move To…", shortcut: "⌘M"),
        ]
    ),
    (
        title: "Navigation",
        entries: [
            ShortcutEntry(action: "Previous Message", shortcut: "⌘["),
            ShortcutEntry(action: "Next Message", shortcut: "⌘]"),
            ShortcutEntry(action: "Focus Search", shortcut: "⌘/"),
        ]
    ),
    (
        title: "Mailbox",
        entries: [
            ShortcutEntry(action: "Get New Mail", shortcut: "⌘⌥R"),
            ShortcutEntry(action: "Settings", shortcut: "⌘,"),
        ]
    ),
]

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
                ForEach(shortcutSections, id: \.title) { section in
                    sectionView(section)
                }
            }
            .padding(BrevSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.bgPrimary.color)
        .frame(minWidth: 380, idealWidth: 440, minHeight: 400, idealHeight: 520)
    }

    @ViewBuilder
    private func sectionView(_ section: (title: String, entries: [ShortcutEntry])) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Text(section.title)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)

            BrevDivider()

            ForEach(section.entries) { entry in
                HStack {
                    Text(entry.action)
                        .brevFont(.body)
                        .foregroundStyle(theme.textPrimary.color)
                    Spacer()
                    Text(entry.shortcut)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                        .padding(.horizontal, BrevSpacing.xs)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(theme.bgSecondary.color)
                        )
                }
                .padding(.vertical, BrevSpacing.xxs)
            }
        }
    }
}
