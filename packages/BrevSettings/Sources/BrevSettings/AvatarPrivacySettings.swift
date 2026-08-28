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

import BrevAvatars
import Foundation

struct AvatarPrivacySettings: Equatable, Sendable {
    enum Key {
        static let useContacts = "avatar.useContacts"
        static let useGravatar = "avatar.useGravatar"
        static let useBIMI = "avatar.useBIMI"
        static let useFavicon = "avatar.useFavicon"
    }

    var useContacts: Bool
    var useGravatar: Bool
    var useBIMI: Bool
    var useFavicon: Bool

    var usesExternalSources: Bool {
        useGravatar || useBIMI || useFavicon
    }

    var avatarPreferences: AvatarPreferences {
        AvatarPreferences(
            useContacts: useContacts,
            useGravatar: useGravatar,
            useBIMI: useBIMI,
            useFavicon: useFavicon
        )
    }

    static let initialsOnly = AvatarPrivacySettings(
        useContacts: false,
        useGravatar: false,
        useBIMI: false,
        useFavicon: false
    )

    static func load(from defaults: UserDefaults = .standard) -> AvatarPrivacySettings {
        AvatarPrivacySettings(
            useContacts: bool(for: Key.useContacts, defaultValue: false, defaults: defaults),
            useGravatar: bool(for: Key.useGravatar, defaultValue: false, defaults: defaults),
            useBIMI: bool(for: Key.useBIMI, defaultValue: false, defaults: defaults),
            useFavicon: bool(for: Key.useFavicon, defaultValue: false, defaults: defaults)
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(useContacts, forKey: Key.useContacts)
        defaults.set(useGravatar, forKey: Key.useGravatar)
        defaults.set(useBIMI, forKey: Key.useBIMI)
        defaults.set(useFavicon, forKey: Key.useFavicon)
    }

    mutating func useInitialsOnly() {
        self = .initialsOnly
    }

    private static func bool(
        for key: String,
        defaultValue: Bool,
        defaults: UserDefaults
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }
}
