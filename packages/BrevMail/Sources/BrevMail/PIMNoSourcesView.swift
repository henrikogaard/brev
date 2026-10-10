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
import BrevSettings
import BrevThemes
import SwiftUI

/// The "nothing is connected" empty state shared by the Calendar, Contacts
/// and Tasks surfaces (audit finding P1).
///
/// On iOS the explanation is followed by a button that opens the Settings
/// pane that connects sources. macOS keeps the text-only state its windows
/// have always had.
struct PIMNoSourcesView: View {
    @Environment(\.brevTheme) private var theme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    let kind: PIMNoSourcesPresentation.Kind
    let symbol: String
    /// Opens the Settings pane; nil hides the button.
    let onOpenSettings: ((SettingsSection) -> Void)?
    /// Whether the macOS state paints the theme background (Calendar did,
    /// Contacts and Tasks did not); iOS always paints it.
    var fillsBackgroundOnMac = false

    var body: some View {
        #if os(iOS)
        let copy = PIMNoSourcesPresentation.copy(
            for: kind,
            usesCategorySettings: horizontalSizeClass == .regular
        )
        ContentUnavailableView {
            Label {
                Text(copy.title)
                    .foregroundStyle(theme.textPrimary.color)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(theme.textSecondary.color)
            }
        } description: {
            Text(copy.message)
                .foregroundStyle(theme.textSecondary.color)
        } actions: {
            if let onOpenSettings {
                Button(copy.actionTitle) {
                    onOpenSettings(PIMNoSourcesPresentation.settingsSection)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent.color)
                .foregroundStyle(theme.bgPrimary.color)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgPrimary.color)
        #else
        let copy = PIMNoSourcesPresentation.copy(for: kind, usesCategorySettings: false)
        ContentUnavailableView(
            copy.title,
            systemImage: symbol,
            description: Text(copy.message)
        )
        .foregroundStyle(theme.textSecondary.color)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(fillsBackgroundOnMac ? theme.bgPrimary.color : Color.clear)
        #endif
    }
}
