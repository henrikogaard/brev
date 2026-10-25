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

/// Shared grouped-form chrome for a settings detail pane.
struct SectionScaffold<Content: View>: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.settingsSearchTarget) private var searchTarget
    @Environment(\.settingsScopeCaption) private var scopeCaption
    @Environment(\.settingsScopeAccessory) private var scopeAccessory
    let title: String
    let subtitle: String?
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        formBody
    }

    /// Settings panes render as grouped forms; explanatory copy sits in
    /// section footers, not in cards.
    private var formBody: some View {
        ScrollViewReader { proxy in
            Form {
                #if os(iOS)
                if hasPaneHeader {
                    Section {
                        if let scopeAccessory {
                            scopeAccessory
                        }
                    } footer: {
                        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                            if let subtitle {
                                Text(subtitle)
                            }
                            if let scopeCaption {
                                Text(scopeCaption)
                            }
                        }
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                    }
                    .listRowBackground(theme.bgPrimary.color)
                }
                #endif
                content
            }
            .environment(\.settingsUsesNativeForm, true)
            #if os(macOS)
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background(BrevWindowSurfaceBackground(role: .content).ignoresSafeArea())
            #else
                .scrollContentBackground(.hidden)
                .background(theme.bgSecondary.color.ignoresSafeArea())
            #endif
                .tint(theme.accent.color)
                .task(id: searchTarget) {
                    guard let searchTarget else { return }
                    await Task.yield()
                    proxy.scrollTo(searchTarget, anchor: .top)
                }
        }
    }

    private var hasPaneHeader: Bool {
        subtitle != nil || scopeCaption != nil || scopeAccessory != nil
    }
}

#if os(iOS)
extension View {
    /// Theme chrome for a `Form` pushed below a settings pane (account
    /// details, per-account switches): hidden system background over the
    /// grouped theme surface, matching `SectionScaffold`.
    func settingsFormChrome() -> some View {
        modifier(SettingsFormChrome())
    }
}

private struct SettingsFormChrome: ViewModifier {
    @Environment(\.brevTheme) private var theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.bgSecondary.color.ignoresSafeArea())
    }
}
#endif
