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

@testable import BrevAvatars
import Foundation
import Testing

@Suite("Initials avatar contrast")
struct InitialsAvatarContrastTests {
    @Test("light fallback colors use dark foreground")
    func lightFallbackColorsUseDarkForeground() {
        #expect(InitialsAvatar.foregroundStyle(forBackgroundHex: "#FDF6E3") == .dark)
    }

    @Test("dark fallback colors use light foreground")
    func darkFallbackColorsUseLightForeground() {
        #expect(InitialsAvatar.foregroundStyle(forBackgroundHex: "#1D1F21") == .light)
    }

    @Test("initials extraction splits punctuation separators without regex and memoizes consistently")
    func initialsExtractionAndColorIndexAreDeterministic() {
        #expect(InitialsAvatar.initials(displayName: "Ada Lovelace", email: "ada@example.test") == "AL")
        #expect(InitialsAvatar.initials(displayName: "  grace_hopper-dev  ", email: "g@example.test") == "GH")
        #expect(InitialsAvatar.initials(displayName: nil, email: "first.last+tag@example.test") == "FL")
        #expect(InitialsAvatar.initials(displayName: "...", email: "...") == "?")
        #expect(InitialsAvatar.initials(displayName: "Ada Lovelace", email: "ada@example.test") == "AL")

        let firstIndex = InitialsAvatar.colorIndex(email: "Ada@Example.Test", paletteCount: 8)
        let secondIndex = InitialsAvatar.colorIndex(email: "ada@example.test", paletteCount: 8)
        let repeatedIndex = InitialsAvatar.colorIndex(email: "Ada@Example.Test", paletteCount: 8)
        #expect(firstIndex == secondIndex)
        #expect(firstIndex == repeatedIndex)
        #expect((0 ..< 8).contains(firstIndex))
        #expect(InitialsAvatar.colorIndex(email: "ada@example.test", paletteCount: 0) == 0)
    }

    @Test("shared avatar preferences observer tracks UserDefaults changes")
    @MainActor
    func preferencesObserverTracksChanges() throws {
        let suite = "AvatarPreferencesObserverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let observer = AvatarPreferencesObserver(defaults: defaults)
        #expect(observer.preferences == .default)

        defaults.set(true, forKey: "avatar.useGravatar")
        observer.refresh()
        #expect(observer.preferences.useGravatar)
        #expect(observer.preferences.useContacts)

        defaults.set(false, forKey: "avatar.useContacts")
        observer.refresh()
        #expect(!observer.preferences.useContacts)
    }
}
