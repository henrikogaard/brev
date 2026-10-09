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

#if os(iOS)
import BrevBackend
@testable import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

/// iPhone Settings panes render as inset-grouped forms: root list, Accounts,
/// Notifications and Appearance in light, dark and accessibility-3 text.
@Suite("Settings forms on iPhone", .serialized)
@MainActor
struct SettingsFormSnapshotTests {
    enum Variant: String, CaseIterable {
        case light
        case dark
        case ax3

        var isDark: Bool { self == .dark }
        var height: CGFloat { self == .ax3 ? 1800 : 812 }
    }

    private struct Fixture {
        let defaults: UserDefaults
        let store: SettingsPersistenceStore
        let theme: BrevTheme
        let account: BrevAccount
        let accountStore: InMemoryAccountStore
        let suite: String

        init(variant: Variant) throws {
            suite = "SettingsForm-" + UUID().uuidString
            defaults = try #require(UserDefaults(suiteName: suite))
            store = SettingsPersistenceStore(defaults: defaults)
            var settings = AppearanceThemeSettings.defaults
            settings.mode = variant.isDark ? .alwaysDark : .alwaysLight
            settings.save(to: defaults)
            theme = settings.resolvedTheme(prefersDark: variant.isDark)
            account = BrevAccount(id: "demo", displayName: "Henrik Øgård", emailAddress: "henrik@ogard.example")
            accountStore = InMemoryAccountStore(accounts: [account], current: account)
        }

        func cleanUp() { defaults.removePersistentDomain(forName: suite) }
    }

    private func snapshot(_ name: String, variant: Variant, _ content: (Fixture) -> some View) throws {
        let fixture = try Fixture(variant: variant)
        defer { fixture.cleanUp() }
        let theme = fixture.theme
        let view = content(fixture)
            .brevTheme(theme)
            .tint(theme.accent.color)
            .environment(\.colorScheme, variant.isDark ? .dark : .light)
            .environment(\.dynamicTypeSize, variant == .ax3 ? .accessibility3 : .large)
        let host = UIHostingController(rootView: view)
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(displayScale: 2),
            UITraitCollection(horizontalSizeClass: .compact),
            UITraitCollection(userInterfaceStyle: variant.isDark ? .dark : .light)
        ])
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 375, height: variant.height), traits: traits),
            named: "\(name)-\(variant.rawValue)",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil,
            testName: "forms"
        )
    }

    @Test("settings root is one grouped list", arguments: Variant.allCases)
    func root(variant: Variant) throws {
        try snapshot("root", variant: variant) { fixture in
            SettingsRootHost(accountStore: fixture.accountStore, settingsStore: fixture.store)
        }
    }

    @Test("accounts pane is a form", arguments: Variant.allCases)
    func accounts(variant: Variant) throws {
        try snapshot("accounts", variant: variant) { fixture in
            NavigationStack {
                AccountsSection(
                    accounts: [fixture.account],
                    currentAccountID: fixture.account.id,
                    settingsStore: fixture.store,
                    onAddAccount: {},
                    onSetDefault: { _ in },
                    onSignOut: { _ in },
                    onRemoveAccount: { _, _ in }
                )
                .navigationTitle("Accounts")
            }
        }
    }

    @Test("notifications pane is a form", arguments: Variant.allCases)
    func notifications(variant: Variant) throws {
        try snapshot("notifications", variant: variant) { fixture in
            NavigationStack {
                NotificationSection(
                    settingsStore: fixture.store,
                    accounts: [fixture.account],
                    authorizationStatus: { .denied }
                )
                .navigationTitle("Notifications")
            }
        }
    }

    @Test("appearance pane is a form", arguments: Variant.allCases)
    func appearance(variant: Variant) throws {
        try snapshot("appearance", variant: variant) { fixture in
            NavigationStack {
                AppearanceSection(
                    activeTheme: .constant(fixture.theme),
                    activeAppIcon: .constant(.defaultVariant),
                    settingsStore: fixture.store
                )
                .navigationTitle("Appearance")
            }
        }
    }
}

private struct SettingsRootHost: View {
    let accountStore: InMemoryAccountStore
    let settingsStore: SettingsPersistenceStore
    @State private var theme = BrevTheme.brevPaper

    var body: some View {
        SettingsView(
            accountStore: accountStore,
            activeTheme: $theme,
            settingsStore: settingsStore
        )
    }
}
#endif
