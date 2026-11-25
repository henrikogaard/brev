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
            entries += MailPaletteEntry.workspaceDestinations(mailbox.workspaceDestinations())
            entries += MailPaletteEntry.mailDestinations(in: mailbox.sections(), select: mailbox.select)
        }
        entries += MailPaletteEntry.settings(settings, open: openSettings)
        let sheet = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = title
        sheet.isReleasedWhenClosed = false
        if BrevLiquidGlassPolicy.usesNativeLiquidGlass(
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        ) {
            sheet.isOpaque = false
            sheet.backgroundColor = .clear
        }
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
        let isUnfiltered = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let matches = MailPaletteEntry.ranked(entries, for: query)
        let sections = isUnfiltered ? MailPaletteEntry.groupedSections(from: matches) : []
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack(spacing: BrevSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textSecondary.color)
                    .accessibilityHidden(true)
                TextField(text: $query) {
                    Text("Search commands, mailboxes, accounts and settings", bundle: .module)
                }
                .textFieldStyle(.plain)
                .brevFont(.body)
                .focused($searching)
                .onSubmit { if matches.indices.contains(cursor) { choose(matches[cursor]) } }
                .onKeyPress(.downArrow) { cursor = min(max(0, matches.count - 1), cursor + 1); return .handled }
                .onKeyPress(.upArrow) { cursor = max(0, cursor - 1); return .handled }
            }
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: BrevRadius.md)
                    .fill(theme.bgSecondary.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BrevRadius.md)
                    .strokeBorder(theme.border.color, lineWidth: 0.5)
            )

            if matches.isEmpty {
                Text("No matching commands or destinations", bundle: .module)
                    .brevFont(.callout)
                    .foregroundStyle(theme.textSecondary.color)
                    .padding(.horizontal, BrevSpacing.xs)
                    .padding(.top, BrevSpacing.xs)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            if isUnfiltered {
                                ForEach(Array(sections.enumerated()), id: \.element.id) { sectionOffset, section in
                                    Text(verbatim: section.title)
                                        .brevFont(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(theme.textTertiary.color)
                                        .padding(.horizontal, BrevSpacing.sm)
                                        .padding(.top, sectionOffset == 0 ? BrevSpacing.xs : BrevSpacing.sm)
                                        .padding(.bottom, 2)
                                        .accessibilityAddTraits(.isHeader)

                                    ForEach(section.rows, id: \.entry.id) { item in
                                        paletteRow(item.entry, index: item.index)
                                    }
                                }
                            } else {
                                ForEach(Array(matches.enumerated()), id: \.element.id) { index, row in
                                    paletteRow(row, index: index)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .onChange(of: cursor) { _, i in
                        if matches.indices.contains(i) { proxy.scrollTo(matches[i].id) }
                    }
                }
            }
        }
        .padding(BrevSpacing.lg)
        .frame(width: 560, height: 400, alignment: .topLeading)
        .foregroundStyle(theme.textPrimary.color)
        .brevGlassSurface(cornerRadius: 18, tint: theme.bgPrimary.color)
        .tint(theme.accent.color)
        .onAppear { searching = true }
        .onChange(of: query) { _, _ in cursor = 0 }
        .onExitCommand { choose(nil) }
    }

    private func paletteRow(_ row: MailPaletteEntry, index: Int) -> some View {
        let isSelected = index == cursor
        return Button {
            choose(row)
        } label: {
            HStack(spacing: BrevSpacing.sm) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? theme.accent.color : Color.clear)
                    .frame(width: 2.5, height: 14)
                    .accessibilityHidden(true)

                Text(verbatim: row.title)
                    .brevFont(.callout)
                    .fontWeight(isSelected ? .medium : .regular)
                    .foregroundStyle(theme.textPrimary.color)
                    .lineLimit(1)

                Spacer(minLength: BrevSpacing.sm)

                if !row.detail.isEmpty {
                    Text(verbatim: row.detail)
                        .brevFont(.caption)
                        .foregroundStyle(isSelected ? theme.textPrimary.color.opacity(0.72) : theme.textSecondary.color)
                        .lineLimit(1)
                }

                if !row.shortcutKeycaps.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(Array(row.shortcutKeycaps.enumerated()), id: \.offset) { _, cap in
                            Text(verbatim: cap)
                                .brevFont(.caption)
                                .fontWeight(.medium)
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? theme.textPrimary.color : theme.textSecondary.color)
                                .frame(minWidth: 18)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(isSelected ? theme.bgPrimary.color : theme.bgSecondary.color)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(theme.border.color, lineWidth: 0.5)
                                )
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: BrevRadius.md)
                    .fill(isSelected ? theme.selection.color : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BrevRadius.md)
                    .strokeBorder(isSelected ? theme.border.color : Color.clear, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(row.id)
    }
}
#endif
