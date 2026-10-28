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

/// The shared empty state for Calendar, Contacts and Tasks without sources.
struct PIMNoSourcesView: View {
    @Environment(\.brevTheme) private var theme

    let kind: PIMNoSourcesPresentation.Kind
    let symbol: String
    /// Opens the Settings pane; nil hides the button.
    let onOpenSettings: ((SettingsSection) -> Void)?

    var body: some View {
        let copy = PIMNoSourcesPresentation.copy(for: kind)
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
                #if os(iOS)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(minHeight: 44)
                .tint(theme.accent.color)
                .foregroundStyle(theme.bgPrimary.color)
                #else
                .buttonStyle(.bordered)
                .controlSize(.large)
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgPrimary.color)
    }
}
