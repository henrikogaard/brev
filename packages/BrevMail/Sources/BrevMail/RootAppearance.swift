/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions in the LICENSE file.
 */

import BrevSettings
import BrevThemes
import Foundation
import SwiftUI

public extension View {
    /// Applies Brev's persisted theme pair while leaving follow-system mode
    /// unpinned so the operating system controls light and dark appearance.
    func brevRootAppearance(
        session: AppSession,
        defaults: UserDefaults = .standard
    ) -> some View {
        modifier(BrevRootAppearanceModifier(session: session, defaults: defaults))
    }
}

private struct BrevRootAppearanceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var session: AppSession
    let defaults: UserDefaults
    /// Cached at init and refreshed only when the persisted theme settings
    /// change — the root view re-evaluates often enough that reading the
    /// defaults keys inside `body` was measurable launch/scroll work.
    @State private var followsSystem: Bool
    @State private var themeSettings: AppearanceThemeSettings

    init(session: AppSession, defaults: UserDefaults) {
        _session = Bindable(session)
        self.defaults = defaults
        _followsSystem = State(
            initialValue: ThemePreferences.followsSystemAppearance(defaults: defaults)
        )
        _themeSettings = State(initialValue: AppearanceThemeSettings.load(from: defaults))
    }

    private var displayedTheme: BrevTheme {
        guard followsSystem else { return session.theme }
        return themeSettings.resolvedTheme(prefersDark: colorScheme == .dark)
    }

    func body(content: Content) -> some View {
        let theme = displayedTheme

        content
            .environment(\.brevTheme, theme)
            .preferredColorScheme(followsSystem ? nil : theme.mode.colorScheme)
            .tint(theme.accent.color)
            .task(id: colorScheme) {
                applyAppearanceTheme()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .brevAppearanceThemeSettingsDidChange)
            ) { _ in
                themeSettings = AppearanceThemeSettings.load(from: defaults)
                followsSystem = ThemePreferences.followsSystemAppearance(defaults: defaults)
            }
    }

    @MainActor
    private func applyAppearanceTheme() {
        if !AppearanceThemeSettings.hasSavedValue(in: defaults),
           !ThemePreferences.hasSavedTheme(defaults: defaults) {
            AppearanceThemeSettings.defaults.save(to: defaults)
        }

        guard AppearanceThemeSettings.hasSavedValue(in: defaults) else { return }

        let resolvedTheme = AppearanceThemeSettings.load(from: defaults).resolvedTheme(
            prefersDark: colorScheme == .dark
        )
        if session.theme != resolvedTheme {
            session.theme = resolvedTheme
        }
    }
}
