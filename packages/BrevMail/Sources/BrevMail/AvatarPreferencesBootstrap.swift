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

enum AvatarPreferencesBootstrap {
    static func preferences(from defaults: UserDefaults = .standard) -> AvatarPreferences {
        preferences(from: defaults, allowsContacts: ContactsAccessPolicy.isEnabled())
    }

    /// - Parameter allowsContacts: See ``ContactsAccessPolicy``. When `false`
    ///   the Contacts source stays off no matter what the user has stored, so
    ///   the system permission prompt never fires.
    static func preferences(
        from defaults: UserDefaults = .standard,
        allowsContacts: Bool
    ) -> AvatarPreferences {
        AvatarPreferences(
            useContacts: allowsContacts
                && bool(for: "avatar.useContacts", defaultValue: false, defaults: defaults),
            useGravatar: bool(for: "avatar.useGravatar", defaultValue: false, defaults: defaults),
            useBIMI: bool(for: "avatar.useBIMI", defaultValue: false, defaults: defaults),
            useFavicon: bool(for: "avatar.useFavicon", defaultValue: false, defaults: defaults)
        )
    }

    static func preferences(
        afterSettingGravatar useGravatar: Bool,
        defaults: UserDefaults = .standard
    ) -> AvatarPreferences {
        defaults.set(useGravatar, forKey: "avatar.useGravatar")
        return preferences(from: defaults)
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
