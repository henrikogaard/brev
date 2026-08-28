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

@testable import BrevSettings
import BrevThemes
import Foundation
import Testing

@Suite("AppearanceThemeSettings")
struct AppearanceThemeSettingsTests {
    @Test("defaults follow system with Brev light and dark themes")
    func defaultsFollowSystemWithBrevThemePair() throws {
        let defaults = try Self.makeDefaults()

        let settings = AppearanceThemeSettings.load(from: defaults)

        #expect(settings.mode == .followSystem)
        #expect(settings.lightThemeID == "brev-mono-light")
        #expect(settings.darkThemeID == "brev-mono-dark")
        #expect(settings.resolvedThemeID(prefersDark: false) == "brev-mono-light")
        #expect(settings.resolvedThemeID(prefersDark: true) == "brev-mono-dark")
        #expect(settings.followsSystemAppearance)
    }

    @Test("saving and loading preserves appearance theme settings")
    func savingAndLoadingPreservesAppearanceThemeSettings() throws {
        let defaults = try Self.makeDefaults()
        let settings = AppearanceThemeSettings(
            mode: .alwaysDark,
            lightThemeID: "solarized-light",
            darkThemeID: "tokyo-night"
        )

        settings.save(to: defaults)
        let restored = AppearanceThemeSettings.load(from: defaults)

        #expect(restored == settings)
        #expect(!restored.followsSystemAppearance)
        #expect(restored.resolvedThemeID(prefersDark: false) == "tokyo-night")
        #expect(AppearanceThemeSettings.hasSavedValue(in: defaults))
    }

    @Test("saving and resolving preserves a custom accent override")
    func savingAndResolvingPreservesCustomAccentOverride() throws {
        let defaults = try Self.makeDefaults()
        var settings = AppearanceThemeSettings.defaults
        settings.accentHex = "#E85D75"

        settings.save(to: defaults)
        let restored = AppearanceThemeSettings.load(from: defaults)
        let resolved = restored.resolvedTheme(
            in: BrevTheme.brevBuiltIns,
            prefersDark: true
        )

        #expect(restored.accentHex == "#E85D75")
        #expect(resolved.accent.hex == "#E85D75")
        #expect(resolved.bgPrimary == BrevTheme.brevMonoDark.bgPrimary)

        var reset = restored
        reset.accentHex = nil
        reset.save(to: defaults)

        #expect(AppearanceThemeSettings.load(from: defaults).accentHex == nil)
        #expect(
            AppearanceThemeSettings.load(from: defaults)
                .resolvedTheme(in: BrevTheme.brevBuiltIns, prefersDark: true)
                .accent == BrevTheme.brevMonoDark.accent
        )
    }

    @Test("invalid persisted values fall back to defaults")
    func invalidPersistedValuesFallBackToDefaults() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("neon", forKey: AppearanceThemeSettings.Key.mode)
        defaults.set("", forKey: AppearanceThemeSettings.Key.lightThemeID)
        defaults.set("   ", forKey: AppearanceThemeSettings.Key.darkThemeID)
        defaults.set("#GGGGGG", forKey: AppearanceThemeSettings.Key.accentHex)

        let settings = AppearanceThemeSettings.load(from: defaults)

        #expect(settings == .defaults)
    }

    @Test("selecting built-in themes updates the matching light or dark slot")
    func selectingBuiltInThemesUpdatesMatchingThemeSlot() {
        var settings = AppearanceThemeSettings.defaults

        settings.selectTheme(.catppuccinLatte)
        settings.selectTheme(.tokyoNight)

        #expect(settings.lightThemeID == "catppuccin-latte")
        #expect(settings.darkThemeID == "tokyo-night")
        #expect(settings.resolvedTheme(in: BrevTheme.brevBuiltIns, prefersDark: false) == .catppuccinLatte)
        #expect(settings.resolvedTheme(in: BrevTheme.brevBuiltIns, prefersDark: true) == .tokyoNight)
    }

    @Test("selected themes provide their own accent until a custom override is set")
    func selectedThemesProvideTheirOwnAccentByDefault() {
        var settings = AppearanceThemeSettings.defaults
        settings.selectTheme(.catppuccinLatte)
        settings.selectTheme(.tokyoNight)

        #expect(settings.selectedTheme(for: .light) == .catppuccinLatte)
        #expect(settings.selectedTheme(for: .dark) == .tokyoNight)
        #expect(settings.resolvedTheme(prefersDark: false).accent == BrevTheme.catppuccinLatte.accent)
        #expect(settings.resolvedTheme(prefersDark: true).accent == BrevTheme.tokyoNight.accent)

        settings.accentHex = "#E85D75"

        #expect(settings.resolvedTheme(prefersDark: false).accent.hex == "#E85D75")
        #expect(settings.resolvedTheme(prefersDark: true).accent.hex == "#E85D75")
    }

    @Test("effective theme mode determines the initial theme picker tab")
    func effectiveThemeModeDeterminesInitialThemePickerTab() {
        var settings = AppearanceThemeSettings.defaults

        #expect(settings.resolvedThemeMode(prefersDark: false) == .light)
        #expect(settings.resolvedThemeMode(prefersDark: true) == .dark)

        settings.mode = .alwaysLight
        #expect(settings.resolvedThemeMode(prefersDark: true) == .light)

        settings.mode = .alwaysDark
        #expect(settings.resolvedThemeMode(prefersDark: false) == .dark)
    }

    @Test("resolved built-in theme falls back when a stored id is missing or has the wrong mode")
    func resolvedBuiltInThemeFallsBackWhenStoredIDIsMissingOrWrongMode() {
        let settings = AppearanceThemeSettings(
            mode: .followSystem,
            lightThemeID: "tokyo-night",
            darkThemeID: "missing-dark"
        )

        #expect(settings.resolvedTheme(in: BrevTheme.brevBuiltIns, prefersDark: false) == .brevMonoLight)
        #expect(settings.resolvedTheme(in: BrevTheme.brevBuiltIns, prefersDark: true) == .brevMonoDark)
    }

    @Test("unsaved appearance theme settings are distinguishable from defaults")
    func unsavedAppearanceThemeSettingsAreDistinguishableFromDefaults() throws {
        let defaults = try Self.makeDefaults()

        #expect(AppearanceThemeSettings.hasSavedValue(in: defaults) == false)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "AppearanceThemeSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
