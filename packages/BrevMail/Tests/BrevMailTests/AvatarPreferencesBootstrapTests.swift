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

@testable import BrevMail
import Foundation
import Testing

@Suite("AvatarPreferencesBootstrap")
struct AvatarPreferencesBootstrapTests {
    @Test("defaults keep local Contacts off and external avatar sources off")
    func defaultsKeepLocalContactsOffAndExternalAvatarSourcesOff() throws {
        let defaults = try Self.makeDefaults()

        let preferences = AvatarPreferencesBootstrap.preferences(
            from: defaults,
            allowsContacts: true
        )

        #expect(preferences.useContacts == false)
        #expect(preferences.useGravatar == false)
        #expect(preferences.useBIMI == false)
        #expect(preferences.useFavicon == false)
    }

    @Test("persisted avatar settings restore every resolver preference")
    func persistedAvatarSettingsRestoreEveryResolverPreference() throws {
        let defaults = try Self.makeDefaults()
        defaults.set(false, forKey: "avatar.useContacts")
        defaults.set(true, forKey: "avatar.useGravatar")
        defaults.set(true, forKey: "avatar.useBIMI")
        defaults.set(true, forKey: "avatar.useFavicon")

        let preferences = AvatarPreferencesBootstrap.preferences(
            from: defaults,
            allowsContacts: true
        )

        #expect(preferences.useContacts == false)
        #expect(preferences.useGravatar == true)
        #expect(preferences.useBIMI == true)
        #expect(preferences.useFavicon == true)
    }

    @Test("a disallowed Contacts source overrides the persisted preference")
    func disallowedContactsSourceOverridesPersistedPreference() throws {
        let defaults = try Self.makeDefaults()
        defaults.set(true, forKey: "avatar.useContacts")
        defaults.set(true, forKey: "avatar.useGravatar")

        let preferences = AvatarPreferencesBootstrap.preferences(
            from: defaults,
            allowsContacts: false
        )

        #expect(preferences.useContacts == false)
        // Only Contacts is suppressed; the other sources raise no prompt.
        #expect(preferences.useGravatar == true)
    }

    @Test("Gravatar updates preserve the other persisted avatar settings")
    func gravatarUpdatesPreserveOtherPersistedAvatarSettings() throws {
        let defaults = try Self.makeDefaults()
        defaults.set(false, forKey: "avatar.useContacts")
        defaults.set(false, forKey: "avatar.useGravatar")
        defaults.set(true, forKey: "avatar.useBIMI")
        defaults.set(true, forKey: "avatar.useFavicon")

        let preferences = AvatarPreferencesBootstrap.preferences(
            afterSettingGravatar: true,
            defaults: defaults
        )

        #expect(defaults.bool(forKey: "avatar.useGravatar"))
        #expect(preferences.useContacts == false)
        #expect(preferences.useGravatar == true)
        #expect(preferences.useBIMI == true)
        #expect(preferences.useFavicon == true)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "AvatarPreferencesBootstrapTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
