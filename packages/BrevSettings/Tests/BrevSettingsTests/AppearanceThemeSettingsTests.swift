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
        #expect(settings.darkThemeID == "brev-mono-grey")
        #expect(settings.resolvedThemeID(prefersDark: false) == "brev-mono-light")
        #expect(settings.resolvedThemeID(prefersDark: true) == "brev-mono-grey")
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

    @Test("saved Mono Dark remains selected after the default changes")
    func preservesSavedDarkTheme() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("brev-mono-dark", forKey: AppearanceThemeSettings.Key.darkThemeID)
        let settings = AppearanceThemeSettings.load(from: defaults)
        #expect(settings.resolvedTheme(prefersDark: true) == .brevMonoDark)
        #expect(settings.resolvedTheme(prefersDark: false) == .brevMonoLight)
    }

    @Test("saving and resolving preserves a custom accent override")
    func savingAndResolvingPreservesCustomAccentOverride() throws {
        let defaults = try Self.makeDefaults()
        var settings = AppearanceThemeSettings.defaults
        settings.accentHex = "#E85D75"
        settings.accentSource = .custom

        settings.save(to: defaults)
        let restored = AppearanceThemeSettings.load(from: defaults)
        let resolved = restored.resolvedTheme(
            in: BrevTheme.brevBuiltIns,
            prefersDark: true
        )

        #expect(restored.accentHex == "#E85D75")
        #expect(restored.accentSource == .custom)
        #expect(
            [resolved.bgPrimary, resolved.bgSecondary, resolved.bgTertiary]
                .allSatisfy { resolved.accent.contrastRatio(against: $0) >= 4.5 }
        )
        #expect(resolved.bgPrimary == BrevTheme.brevMonoGrey.bgPrimary)

        var reset = restored
        reset.accentHex = nil
        reset.accentSource = .theme
        reset.save(to: defaults)

        #expect(AppearanceThemeSettings.load(from: defaults).accentHex == nil)
        #expect(AppearanceThemeSettings.load(from: defaults).accentSource == .theme)
        #expect(
            AppearanceThemeSettings.load(from: defaults)
                .resolvedTheme(in: BrevTheme.brevBuiltIns, prefersDark: true)
                .accent == BrevTheme.brevMonoGrey.accent
        )
    }

    @Test("legacy saved accents infer the custom source")
    func legacySavedAccentsInferCustomSource() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("#e85d75", forKey: AppearanceThemeSettings.Key.accentHex)

        let settings = AppearanceThemeSettings.load(from: defaults)

        #expect(settings.accentSource == .custom)
        #expect(settings.accentHex == "#E85D75")
    }

    @Test("legacy defaults without a valid accent use the theme source")
    func legacyDefaultsWithoutValidAccentUseThemeSource() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("invalid", forKey: AppearanceThemeSettings.Key.accentHex)

        let settings = AppearanceThemeSettings.load(from: defaults)

        #expect(settings.accentHex == nil)
        #expect(settings.accentSource == .theme)
    }

    @Test("invalid accent source preserves a valid custom accent")
    func invalidAccentSourcePreservesValidAccent() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("#E85D75", forKey: AppearanceThemeSettings.Key.accentHex)
        defaults.set("invalid", forKey: AppearanceThemeSettings.Key.accentSource)

        let settings = AppearanceThemeSettings.load(from: defaults)

        #expect(settings.accentSource == .custom)
        #expect(settings.accentHex == "#E85D75")
    }

    @Test("invalid accent source without a valid accent falls back to theme")
    func invalidAccentSourceWithoutValidAccentFallsBackToTheme() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("invalid", forKey: AppearanceThemeSettings.Key.accentHex)
        defaults.set("unknown", forKey: AppearanceThemeSettings.Key.accentSource)

        let settings = AppearanceThemeSettings.load(from: defaults)

        #expect(settings.accentHex == nil)
        #expect(settings.accentSource == .theme)
    }

    @Test("legacy JSON without a source infers the custom source")
    func legacyJSONInfersCustomSource() throws {
        let data = Data(
            """
            {
              "mode": "followSystem",
              "lightThemeID": "brev-mono-light",
              "darkThemeID": "brev-mono-grey",
              "accentHex": "#E85D75"
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(AppearanceThemeSettings.self, from: data)

        #expect(settings.accentSource == .custom)
        #expect(settings.accentHex == "#E85D75")
    }

    @Test("legacy JSON without a valid accent uses the theme source")
    func legacyJSONWithoutValidAccentUsesThemeSource() throws {
        let data = Data(
            """
            {
              "mode": "followSystem",
              "lightThemeID": "brev-mono-light",
              "darkThemeID": "brev-mono-grey",
              "accentHex": "invalid"
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(AppearanceThemeSettings.self, from: data)

        #expect(settings.accentHex == nil)
        #expect(settings.accentSource == .theme)
    }

    @Test("source changes preserve the saved custom accent")
    func sourceChangesPreserveSavedCustomAccent() throws {
        var settings = AppearanceThemeSettings.defaults
        settings.accentHex = "#E85D75"
        settings.accentSource = .custom

        settings.accentSource = .theme
        #expect(settings.accentHex == "#E85D75")
        settings.accentSource = .system
        #expect(settings.accentHex == "#E85D75")
    }

    @Test("settings transfer round-trip preserves accent source and saved hex")
    func settingsTransferRoundTripsAccentSource() throws {
        let defaults = try Self.makeDefaults()
        let store = SettingsPersistenceStore(defaults: defaults)
        var settings = AppearanceThemeSettings.defaults
        settings.accentHex = "#E85D75"
        settings.accentSource = .custom
        store.save(settings)

        let payload = SettingsBackupCodec.export(from: store)
        let data = try BackupWriter.encoder.encode(payload)
        let restored = try BackupWriter.decoder.decode(SettingsBackupPayload.self, from: data)

        #expect(restored.appearanceTheme == settings)
    }

    #if os(macOS)
    @Test("injected system accents resolve through the readable accent transform")
    func injectedSystemAccentResolvesAtTheThemeBoundary() {
        var settings = AppearanceThemeSettings.defaults
        settings.accentSource = .system
        let resolved = settings.resolvedTheme(
            in: BrevTheme.brevBuiltIns,
            prefersDark: false,
            systemAccent: BrevColor("#FF0000")
        )

        #expect(resolved.accent != BrevColor("#FF0000"))
        #expect(
            [resolved.bgPrimary, resolved.bgSecondary, resolved.bgTertiary]
                .allSatisfy { resolved.accent.contrastRatio(against: $0) >= 4.5 }
        )
    }
    #endif

    #if os(iOS)
    @Test("imported system source falls back to the selected theme on iOS")
    func importedSystemSourceFallsBackToThemeOnIOS() {
        var settings = AppearanceThemeSettings.defaults
        settings.accentSource = .system

        let resolved = settings.resolvedTheme(
            in: BrevTheme.brevBuiltIns,
            prefersDark: false
        )

        #expect(resolved.accent == BrevTheme.brevMonoLight.accent)
    }
    #endif

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
        settings.accentSource = .custom

        #expect(settings.resolvedTheme(prefersDark: false).accent.hex != "#E85D75")
        #expect(settings.resolvedTheme(prefersDark: true).accent.hex != "#E85D75")
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
        #expect(settings.resolvedTheme(in: BrevTheme.brevBuiltIns, prefersDark: true) == .brevMonoGrey)
    }

    @Test("unsaved appearance theme settings are distinguishable from defaults")
    func unsavedAppearanceThemeSettingsAreDistinguishableFromDefaults() throws {
        let defaults = try Self.makeDefaults()

        #expect(AppearanceThemeSettings.hasSavedValue(in: defaults) == false)
    }

    @Test("Reset to Defaults restores every Appearance preference")
    func resetRestoresAppearanceDefaults() throws {
        let defaults = try Self.makeDefaults()
        let store = SettingsPersistenceStore(defaults: defaults)
        var custom = AppearanceThemeSettings.defaults
        custom.mode = .alwaysDark
        custom.accentSource = .custom
        custom.accentHex = "#FF0000"
        store.save(custom)
        store.save(AppIconVariant.envelopeCarbon)
        defaults.set(false, forKey: AppearancePreferenceKey.transparentMainTitlebar)

        AppearanceReset.apply(to: store)

        #expect(store.appearanceThemeSettings() == AppearanceThemeSettings.defaults)
        #expect(store.appIconVariant() == AppIconVariant.defaultVariant)
        #expect(defaults.bool(forKey: AppearancePreferenceKey.transparentMainTitlebar))
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "AppearanceThemeSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
