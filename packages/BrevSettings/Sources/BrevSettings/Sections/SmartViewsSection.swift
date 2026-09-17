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

/// Visibility, order, and saved conditions for the sidebar's Smart Views.
public struct SmartViewsSection: View {
    @Environment(\.brevTheme) private var theme
    @AppStorage(SmartMailboxSettings.storageKey) private var settingsData = Data()
    @State private var editing: SmartMailbox?
    @State private var showsEditor = false
    private let mailboxes: [SettingsMailbox]
    private let settingsStore: SettingsPersistenceStore

    /// Creates the same management panel for the sidebar and the Settings window.
    public init(mailboxes: [SettingsMailbox] = [], settingsStore: SettingsPersistenceStore = .standard) {
        self.mailboxes = mailboxes
        self.settingsStore = settingsStore
        _settingsData = AppStorage(wrappedValue: Data(), SmartMailboxSettings.storageKey, store: settingsStore.defaults)
    }

    public var body: some View {
        SectionScaffold(title: String(localized: "Smart Views", bundle: .module),
                        subtitle: String(
                            localized: "Choose what appears in the sidebar and arrange it in your preferred order.",
                            bundle: .module
                        )) {
            Toggle(String(localized: "Show Smart Views in sidebar", bundle: .module), isOn: Binding(
                get: { settings.showInSidebar }, set: { value in update { $0.showInSidebar = value } }
            ))
            .id(String(localized: "Show Smart Views in sidebar", bundle: .module))
            VStack(spacing: 0) {
                ForEach(Array(settings.orderedEntries.enumerated()), id: \.element.id) { index, entry in
                    row(entry, index: index)
                }
            }
            .id(String(localized: "Display order", bundle: .module))
            Button {
                editing = nil
                showsEditor = true
            } label: {
                Label(String(localized: "New Smart View", bundle: .module), systemImage: "plus")
            }
        }
        .sheet(isPresented: $showsEditor) {
            SavedSearchEditorView(editing: editing, mailboxes: mailboxes, settingsStore: settingsStore) {
                showsEditor = false
            }
        }
    }

    private var settings: SmartMailboxSettings {
        (try? JSONDecoder().decode(SmartMailboxSettings.self, from: settingsData)) ?? .defaults
    }

    private func update(_ change: (inout SmartMailboxSettings) -> Void) {
        var current = settings
        change(&current)
        if let data = try? JSONEncoder().encode(current) { settingsData = data }
    }

    private func row(_ entry: SmartViewDisplayEntry, index: Int) -> some View {
        HStack(spacing: BrevSpacing.sm) {
            Toggle(isOn: Binding(get: { entry.isEnabled }, set: { enabled in
                update { $0.setEntry(entry, isEnabled: enabled) }
            })) {
                Label(entry.title, systemImage: entry.symbolName)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.checkboxOnMac)
            .accessibilityLabel(String(localized: "Show \(entry.title)", bundle: .module))
            if let mailbox = entry.mailbox {
                Button(String(localized: "Edit", bundle: .module)) {
                    editing = mailbox
                    showsEditor = true
                }
                .accessibilityLabel(String(localized: "Edit \(entry.title)", bundle: .module))
            }
            moveButton(entry, offset: -1, disabled: index == 0)
            moveButton(entry, offset: 1, disabled: index == settings.orderedEntries.count - 1)
        }
        .brevFont(.body)
        .foregroundStyle(theme.textPrimary.color)
        .padding(.vertical, BrevSpacing.sm)
    }

    private func moveButton(_ entry: SmartViewDisplayEntry, offset: Int, disabled: Bool) -> some View {
        Button { update { $0.moveEntry(id: entry.id, by: offset) } } label: {
            Image(systemName: offset < 0 ? "chevron.up" : "chevron.down")
            #if os(iOS)
                .frame(minWidth: 44, minHeight: 44)
            #endif
        }
        .disabled(disabled)
        .accessibilityLabel(offset < 0
            ? String(localized: "Move \(entry.title) up", bundle: .module)
            : String(localized: "Move \(entry.title) down", bundle: .module))
        .help(offset < 0 ? String(localized: "Move up", bundle: .module) : String(localized: "Move down", bundle: .module))
    }
}

private struct SmartViewToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        Toggle(configuration).toggleStyle(.checkbox)
        #else
        Toggle(configuration).toggleStyle(.switch)
        #endif
    }
}

private extension ToggleStyle where Self == SmartViewToggleStyle {
    static var checkboxOnMac: SmartViewToggleStyle { SmartViewToggleStyle() }
}
