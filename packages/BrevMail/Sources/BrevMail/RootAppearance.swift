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
#if os(macOS)
import AppKit
#endif

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
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Bindable var session: AppSession
    let defaults: UserDefaults
    /// Cached at init and refreshed only when the persisted theme settings
    /// change — the root view re-evaluates often enough that reading the
    /// defaults keys inside `body` was measurable launch/scroll work.
    @State private var followsSystem: Bool
    @State private var hasAppearanceSettings: Bool
    @State private var themeSettings: AppearanceThemeSettings
    @State private var systemColorsRevision = 0

    init(session: AppSession, defaults: UserDefaults) {
        _session = Bindable(session)
        self.defaults = defaults
        _followsSystem = State(
            initialValue: ThemePreferences.followsSystemAppearance(defaults: defaults)
        )
        _themeSettings = State(initialValue: AppearanceThemeSettings.load(from: defaults))
        _hasAppearanceSettings = State(initialValue: AppearanceThemeSettings.hasSavedValue(in: defaults))
    }

    private var displayedTheme: BrevTheme {
        _ = systemColorsRevision
        guard hasAppearanceSettings else { return session.theme }
        return themeSettings.resolvedTheme(
            prefersDark: colorScheme == .dark,
            increasedContrast: colorSchemeContrast == .increased
        )
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
                hasAppearanceSettings = AppearanceThemeSettings.hasSavedValue(in: defaults)
                applyAppearanceTheme()
            }
            .onChange(of: colorSchemeContrast) { _, _ in applyAppearanceTheme() }
        #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSColor.systemColorsDidChangeNotification)) { _ in
                systemColorsRevision += 1
                applyAppearanceTheme()
            }
        #endif
    }

    @MainActor
    private func applyAppearanceTheme() {
        if !AppearanceThemeSettings.hasSavedValue(in: defaults),
           !ThemePreferences.hasSavedTheme(defaults: defaults) {
            AppearanceThemeSettings.defaults.save(to: defaults)
        }

        guard AppearanceThemeSettings.hasSavedValue(in: defaults) else { return }

        let resolvedTheme = AppearanceThemeSettings.load(from: defaults).resolvedTheme(
            prefersDark: colorScheme == .dark,
            increasedContrast: colorSchemeContrast == .increased
        )
        if session.theme != resolvedTheme {
            session.theme = resolvedTheme
        }
    }
}

// MARK: - Presented sheets

extension View {
    /// Themes a presented view (sheet, popover content, auxiliary window).
    ///
    /// Replaces the per-sheet `.brevTheme(_:)` pin, which fixed the sheet's
    /// colour scheme from a theme that could be stale (the system flipping
    /// while a sheet is open produced light sheets in a dark app). On iOS the
    /// sheet reads the same persisted appearance settings as
    /// `brevRootAppearance(session:)`: follow-system leaves the scheme unpinned,
    /// and a pinned mode resolves its theme from the settings rather than from
    /// the presenter. It also paints the sheet background, hides the grouped
    /// list background, and applies the accent tint. macOS windows keep the
    /// plain theme pin.
    ///
    /// - Parameter theme: The presenter's theme; used on macOS and when no
    ///   appearance settings have been saved yet.
    func brevSheetAppearance(_ theme: BrevTheme, defaults: UserDefaults = .standard) -> some View {
        modifier(BrevSheetAppearanceModifier(presenterTheme: theme, defaults: defaults))
    }

    /// Row styling for lists inside themed sheets: the theme's secondary
    /// surface and separator instead of the system grouped colours.
    func brevSheetRow() -> some View {
        modifier(BrevSheetRowModifier())
    }
}

/// The theme and colour-scheme pin a sheet should use.
struct BrevSheetAppearanceResolution: Equatable {
    let theme: BrevTheme
    /// `nil` in follow-system mode so the sheet keeps tracking the system.
    let preferredColorScheme: ColorScheme?

    /// - Parameters:
    ///   - presenterTheme: Theme the presenting view runs with; the answer when
    ///     no appearance settings were saved (legacy single-theme installs).
    ///   - settings: Persisted appearance settings, `nil` when none were saved.
    ///   - prefersDark: The sheet's own colour scheme before any pin.
    ///   - increasedContrast: Whether Increase Contrast is on.
    static func resolve(
        presenterTheme: BrevTheme,
        settings: AppearanceThemeSettings?,
        prefersDark: Bool,
        increasedContrast: Bool
    ) -> BrevSheetAppearanceResolution {
        guard let settings else {
            return BrevSheetAppearanceResolution(
                theme: presenterTheme,
                preferredColorScheme: presenterTheme.mode.colorScheme
            )
        }
        let theme = settings.resolvedTheme(prefersDark: prefersDark, increasedContrast: increasedContrast)
        return BrevSheetAppearanceResolution(
            theme: theme,
            preferredColorScheme: settings.followsSystemAppearance ? nil : theme.mode.colorScheme
        )
    }
}

private struct BrevSheetAppearanceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let presenterTheme: BrevTheme
    let defaults: UserDefaults
    @State private var settings: AppearanceThemeSettings?

    init(presenterTheme: BrevTheme, defaults: UserDefaults) {
        self.presenterTheme = presenterTheme
        self.defaults = defaults
        _settings = State(initialValue: Self.savedSettings(in: defaults))
    }

    private static func savedSettings(in defaults: UserDefaults) -> AppearanceThemeSettings? {
        AppearanceThemeSettings.hasSavedValue(in: defaults)
            ? AppearanceThemeSettings.load(from: defaults)
            : nil
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        let resolved = BrevSheetAppearanceResolution.resolve(
            presenterTheme: presenterTheme,
            settings: settings,
            prefersDark: colorScheme == .dark,
            increasedContrast: colorSchemeContrast == .increased
        )
        content
            .environment(\.brevTheme, resolved.theme)
            .preferredColorScheme(resolved.preferredColorScheme)
            .tint(resolved.theme.accent.color)
            .presentationBackground(resolved.theme.bgPrimary.color)
            .scrollContentBackground(.hidden)
            .onReceive(
                NotificationCenter.default.publisher(for: .brevAppearanceThemeSettingsDidChange)
            ) { _ in
                settings = Self.savedSettings(in: defaults)
            }
        #else
        content.brevTheme(presenterTheme)
        #endif
    }
}

private struct BrevSheetRowModifier: ViewModifier {
    @Environment(\.brevTheme) private var theme

    func body(content: Content) -> some View {
        content
            .listRowBackground(theme.bgSecondary.color)
            .listRowSeparatorTint(theme.separator.color)
    }
}
