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

@Suite("AvatarPrivacySettings")
struct AvatarPrivacySettingsTests {
    @Test("defaults keep Contacts off and external lookups off")
    func defaultsKeepContactsOffAndExternalLookupsOff() throws {
        let defaults = try Self.makeDefaults()

        let settings = AvatarPrivacySettings.load(from: defaults)
        let preferences = settings.avatarPreferences

        #expect(settings.useContacts == false)
        #expect(settings.useGravatar == false)
        #expect(settings.useBIMI == false)
        #expect(settings.useFavicon == false)
        #expect(preferences.useContacts == false)
        #expect(preferences.useGravatar == false)
        #expect(preferences.useBIMI == false)
        #expect(preferences.useFavicon == false)
        #expect(settings.usesExternalSources == false)
    }

    @Test("saving and loading preserves every avatar privacy toggle")
    func savingAndLoadingPreservesEveryAvatarPrivacyToggle() throws {
        let defaults = try Self.makeDefaults()
        let settings = AvatarPrivacySettings(
            useContacts: false,
            useGravatar: true,
            useBIMI: true,
            useFavicon: true
        )

        settings.save(to: defaults)
        let restored = AvatarPrivacySettings.load(from: defaults)

        #expect(restored == settings)
        #expect(restored.avatarPreferences.useContacts == false)
        #expect(restored.avatarPreferences.useGravatar == true)
        #expect(restored.avatarPreferences.useBIMI == true)
        #expect(restored.avatarPreferences.useFavicon == true)
        #expect(restored.usesExternalSources == true)
    }

    @Test("initials only disables local contacts and external avatar sources")
    func initialsOnlyDisablesLocalContactsAndExternalAvatarSources() {
        var settings = AvatarPrivacySettings(
            useContacts: true,
            useGravatar: true,
            useBIMI: true,
            useFavicon: true
        )

        settings.useInitialsOnly()

        #expect(settings == AvatarPrivacySettings.initialsOnly)
        #expect(settings.avatarPreferences.useContacts == false)
        #expect(settings.avatarPreferences.useGravatar == false)
        #expect(settings.avatarPreferences.useBIMI == false)
        #expect(settings.avatarPreferences.useFavicon == false)
        #expect(settings.usesExternalSources == false)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "AvatarPrivacySettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
