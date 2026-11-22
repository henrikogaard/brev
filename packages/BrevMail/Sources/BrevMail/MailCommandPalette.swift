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
import BrevDesign
import BrevSettings
import BrevThemes
import SwiftUI

/// Opens the macOS command palette over the window whose menu and destinations it searches.
@MainActor
public enum MailCommandPalette {
    /// Localized Edit menu command title.
    public static var title: String { String(localized: "Command Palette…", bundle: .module) }

    /// Snapshot the owner's menu before presenting; run its command after the sheet releases focus.
    public static func present(theme: BrevTheme, mailbox: MailPaletteMailboxContext?, settings: [SettingsSection],
                               openSettings: @escaping @MainActor (SettingsSection) -> Void) {
        guard let owner = NSApp.keyWindow, owner.attachedSheet == nil, owner.sheetParent == nil,
              let menu = NSApp.mainMenu else { return }
        var entries = MailPaletteEntry.commands(in: menu)
        if let mailbox {
            entries += MailPaletteEntry.mailDestinations(in: mailbox.sections(), select: mailbox.select)
        }
        entries += MailPaletteEntry.settings(settings, open: openSettings)
        let sheet = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = title
        sheet.isReleasedWhenClosed = false
        var chosen: MailPaletteEntry?
        sheet.contentViewController = contentController(theme: theme, entries: entries) { entry in
            guard owner.attachedSheet === sheet else { return }
            chosen = entry
            owner.endSheet(sheet)
        }
        owner.beginSheet(sheet) { _ in
            sheet.orderOut(nil)
            sheet.contentViewController = nil
            guard owner.isVisible, owner.attachedSheet == nil else { return }
            owner.makeKey()
            guard NSApp.keyWindow === owner else { return }
            chosen?.run()
        }
    }

    static func contentController(theme: BrevTheme, entries: [MailPaletteEntry],
                                  choose: @escaping (MailPaletteEntry?) -> Void) -> NSViewController {
        NSHostingController(rootView: MailCommandPaletteView(entries: entries, choose: choose)
            .brevSheetAppearance(theme))
    }
}

@MainActor
private struct MailCommandPaletteView: View {
    @Environment(\.brevTheme) private var theme
    let entries: [MailPaletteEntry]
    let choose: (MailPaletteEntry?) -> Void
    @State private var query = ""
    @State private var cursor = 0
    @FocusState private var searching: Bool

    var body: some View {
        let matches = entries.filter { $0.matches(query) }
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            TextField(text: $query) {
                Text("Search commands, mailboxes, accounts and settings", bundle: .module)
            }
            .textFieldStyle(.roundedBorder)
            .focused($searching)
            .onSubmit { if matches.indices.contains(cursor) { choose(matches[cursor]) } }
            .onKeyPress(.downArrow) { cursor = min(max(0, matches.count - 1), cursor + 1); return .handled }
            .onKeyPress(.upArrow) { cursor = max(0, cursor - 1); return .handled }
            if matches.isEmpty {
                Text("No matching commands or destinations", bundle: .module)
                    .foregroundStyle(theme.textSecondary.color)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(matches.enumerated()), id: \.element.id) { index, row in
                                Button {
                                    choose(row)
                                } label: {
                                    HStack {
                                        Image(systemName: "chevron.right").opacity(index == cursor ? 1 : 0)
                                            .accessibilityHidden(true)
                                        Text(verbatim: row.title)
                                        Spacer()
                                        Text(verbatim: row.detail).font(.caption).foregroundStyle(theme.textSecondary.color)
                                    }
                                    .padding(.vertical, BrevSpacing.xs)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(index == cursor ? .isSelected : [])
                                .id(row.id)
                            }
                        }
                    }
                    .onChange(of: cursor) { _, i in
                        if matches.indices.contains(i) { proxy.scrollTo(matches[i].id) }
                    }
                }
            }
        }
        .padding(BrevSpacing.lg)
        .frame(width: 560, height: 400, alignment: .topLeading)
        .foregroundStyle(theme.textPrimary.color)
        .background(theme.bgPrimary.color)
        .tint(theme.accent.color)
        .onAppear { searching = true }
        .onChange(of: query) { _, _ in cursor = 0 }
        .onExitCommand { choose(nil) }
    }
}
#endif
