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
import Foundation
import Testing

@Suite("AppIconPreferences")
struct AppIconPreferencesTests {
    @Test("Brev ships three selectable icon variants")
    func shipsThreeSelectableIconVariants() {
        #expect(AppIconVariant.allCases.count == 3)
        #expect(Set(AppIconVariant.allCases.map(\.assetName)).count == 3)
        #expect(Set(AppIconVariant.allCases.map(\.previewAssetName)).count == 3)
    }

    @Test("default icon is Smoke")
    func defaultIconIsSmoke() throws {
        let defaults = try Self.makeDefaults()

        #expect(AppIconPreferences.load(defaults: defaults) == .envelopeDarkMetal)
    }

    @Test("saving and loading preserves selected icon")
    func savingAndLoadingPreservesSelectedIcon() throws {
        let defaults = try Self.makeDefaults()

        AppIconPreferences.save(.envelopeCarbon, defaults: defaults)

        #expect(AppIconPreferences.load(defaults: defaults) == .envelopeCarbon)
    }

    @Test("unknown persisted icon falls back to Smoke")
    func unknownPersistedIconFallsBackToSmoke() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("missing-icon", forKey: AppIconPreferences.iconIDKey)

        #expect(AppIconPreferences.load(defaults: defaults) == .envelopeDarkMetal)
    }

    @Test("Smoke maps to the primary iOS app icon")
    func smokeMapsToPrimaryIOSAppIcon() {
        #expect(AppIconVariant.envelopeDarkMetal.alternateIconName == nil)
        #expect(AppIconVariant.envelopeLight.alternateIconName == "BrevIconEnvelopeLight")
        #expect(AppIconVariant.matchingAlternateIconName(nil) == .envelopeDarkMetal)
        #expect(
            AppIconVariant.matchingAlternateIconName(
                AppIconVariant.envelopeLight.alternateIconName
            ) == .envelopeLight
        )
        #expect(
            AppIconVariant.matchingAlternateIconName(
                AppIconVariant.envelopeCarbon.alternateIconName
            ) == .envelopeCarbon
        )
    }

    @Test("legacy persisted icon names migrate to matching envelope variants")
    func legacyPersistedIconNamesMigrateToMatchingEnvelopeVariants() throws {
        let defaults = try Self.makeDefaults()

        // Retired 20-variant raw values.
        defaults.set("aurora-original", forKey: AppIconPreferences.iconIDKey)
        #expect(AppIconPreferences.load(defaults: defaults) == .envelopeDarkMetal)

        defaults.set("solid-white", forKey: AppIconPreferences.iconIDKey)
        #expect(AppIconPreferences.load(defaults: defaults) == .envelopeLight)

        defaults.set("inverted-brushed-metal-carbon", forKey: AppIconPreferences.iconIDKey)
        #expect(AppIconPreferences.load(defaults: defaults) == .envelopeCarbon)

        // Older short legacy keys retained across two icon-pack migrations.
        defaults.set("graphite", forKey: AppIconPreferences.iconIDKey)
        #expect(AppIconPreferences.load(defaults: defaults) == .envelopeCarbon)

        defaults.set("paper", forKey: AppIconPreferences.iconIDKey)
        #expect(AppIconPreferences.load(defaults: defaults) == .envelopeLight)

        defaults.set("nordic-navy", forKey: AppIconPreferences.iconIDKey)
        #expect(AppIconPreferences.load(defaults: defaults) == .envelopeDarkMetal)
    }

    @Test("saved envelope choices and backups keep their identity", arguments: AppIconVariant.allCases)
    func savedEnvelopeChoicesKeepTheirIdentity(_ variant: AppIconVariant) throws {
        let defaults = try Self.makeDefaults()
        defaults.set(variant.rawValue, forKey: AppIconPreferences.iconIDKey)
        #expect(AppIconPreferences.load(defaults: defaults) == variant)
        let encoded = try JSONEncoder().encode(variant)
        #expect(try JSONDecoder().decode(AppIconVariant.self, from: encoded) == variant)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "AppIconPreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
