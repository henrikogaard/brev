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

import BrevBackend
@testable import BrevMail
import BrevThemes
import Foundation
import Testing

@Suite("ThemePreferences")
struct ThemePreferencesTests {
    @Test("saving a theme restores it into a new session")
    func savingThemeRestoresItIntoNewSession() {
        let suiteName = "app.brev.tests.theme.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(ThemePreferences.hasSavedTheme(defaults: defaults) == false)

        ThemePreferences.save(BrevTheme.tokyoNight, defaults: defaults)
        let restored = ThemePreferences.load(defaults: defaults)

        #expect(restored == BrevTheme.tokyoNight)
        #expect(ThemePreferences.hasSavedTheme(defaults: defaults))
    }

    @Test("unknown persisted theme IDs fall back to Brev Mono Light")
    func unknownPersistedThemeIDsFallBackToBrevMonoLight() {
        let suiteName = "app.brev.tests.theme.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("missing-theme", forKey: ThemePreferences.themeIDKey)

        #expect(ThemePreferences.load(defaults: defaults) == BrevTheme.brevMonoLight)
    }

    @Test("first launch follows system appearance before asynchronous bootstrap")
    func firstLaunchFollowsSystemAppearanceBeforeBootstrap() {
        let suiteName = "app.brev.tests.launch-theme.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(ThemePreferences.resolvedForLaunch(prefersDark: false, defaults: defaults) == .brevMonoLight)
        #expect(ThemePreferences.resolvedForLaunch(prefersDark: true, defaults: defaults) == .brevMonoDark)
        #expect(ThemePreferences.followsSystemAppearance(defaults: defaults))

        ThemePreferences.save(.tokyoNight, defaults: defaults)
        #expect(ThemePreferences.resolvedForLaunch(prefersDark: false, defaults: defaults) == .tokyoNight)
        #expect(!ThemePreferences.followsSystemAppearance(defaults: defaults))
    }

    @MainActor
    @Test("AppSession saves theme changes and restores them on next launch")
    func appSessionSavesThemeChangesAndRestoresThemOnNextLaunch() {
        let suiteName = "app.brev.tests.theme.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstSession = makeSession(defaults: defaults)
        firstSession.theme = .tokyoNight

        let restoredSession = makeSession(defaults: defaults)
        #expect(restoredSession.theme == .tokyoNight)
    }

    @MainActor
    private func makeSession(defaults: UserDefaults) -> AppSession {
        let backend = MockBackend()
        return AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: ThemePreferencesTokenStore(),
            themeDefaults: defaults
        ) {
            AppSession.LoginResult(backend: backend, account: backend.account)
        }
    }
}

private actor ThemePreferencesTokenStore: TokenStore {
    func token(for accountID: String) async -> Token? {
        nil
    }

    func setToken(_ token: Token, for accountID: String) async {}

    func clearToken(for accountID: String) async {}
}
