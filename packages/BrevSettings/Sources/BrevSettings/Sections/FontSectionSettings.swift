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

/// Appearance group with one font family picker per window section (ADR-0086).
struct FontSectionSettings: View {
    @Environment(\.brevTheme) private var theme
    @SectionFontFamily private var sidebarFamily: MailboxFontFamily
    @SectionFontFamily private var listFamily: MailboxFontFamily
    @SectionFontFamily private var readerFamily: MailboxFontFamily
    private let defaults: UserDefaults

    init(settingsStore: SettingsPersistenceStore = .standard) {
        defaults = settingsStore.defaults
        _sidebarFamily = SectionFontFamily(.sidebar, store: settingsStore.defaults)
        _listFamily = SectionFontFamily(.messageList, store: settingsStore.defaults)
        _readerFamily = SectionFontFamily(.reader, store: settingsStore.defaults)
    }

    /// Writes `family` to every section key.
    static func applyToAll(_ family: MailboxFontFamily, in defaults: UserDefaults) {
        for section in BrevFontSection.allCases {
            defaults.set(family.rawValue, forKey: section.preferenceKey)
        }
    }

    var body: some View {
        SettingsGroup(
            title: String(localized: "Fonts", bundle: .module),
            subtitle: String(
                localized: "Pick a font for each part of the mail window. Compose uses the reading font.",
                bundle: .module
            ),
            symbolName: "textformat"
        ) {
            SettingsRowStack {
                ForEach(BrevFontSection.allCases) { section in
                    SettingsPickerRow(
                        symbolName: section.symbolName,
                        title: section.title,
                        subtitle: family(for: section).subtitle,
                        selection: binding(for: section)
                    ) {
                        ForEach(MailboxFontFamily.allCases) { family in
                            Text(family.title).tag(family)
                        }
                    }
                }

                // No fixedSize: at accessibility sizes the label must wrap
                // rather than widen the whole pane.
                Menu(String(localized: "Use One Font Everywhere", bundle: .module)) {
                    ForEach(MailboxFontFamily.allCases) { family in
                        Button(family.title) {
                            Self.applyToAll(family, in: defaults)
                        }
                    }
                }

                preview
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            ForEach(BrevFontSection.allCases) { section in
                VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                    Text(verbatim: section.title)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textTertiary.color)
                    Text("Brev keeps message text calm, readable, and easy to scan.", bundle: .module)
                        .brevFont(.body)
                        .environment(\.brevFontFamily, family(for: section))
                        .foregroundStyle(theme.textPrimary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(BrevSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsInlineSurface(cornerRadius: BrevRadius.sm)
    }

    private func family(for section: BrevFontSection) -> MailboxFontFamily {
        switch section {
        case .sidebar: sidebarFamily
        case .messageList: listFamily
        case .reader: readerFamily
        }
    }

    private func binding(for section: BrevFontSection) -> Binding<MailboxFontFamily> {
        Binding(
            get: { family(for: section) },
            set: { defaults.set($0.rawValue, forKey: section.preferenceKey) }
        )
    }
}
