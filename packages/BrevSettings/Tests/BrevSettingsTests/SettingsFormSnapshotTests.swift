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
    typealias Variant = SettingsReviewVariant
    private typealias Fixture = SettingsReviewFixture

    private func snapshot(
        _ name: String, variant: Variant, scrollToBottom: Bool = false, compareReference: Bool = true,
        quietHoursEnabled: Bool = false,
        @ViewBuilder _ content: (Fixture) -> some View
    ) async throws {
        try #require(Bundle.main.bundleIdentifier == "eu.brevmail.brev.settings-snapshots")
        try #require(Bundle.main.object(forInfoDictionaryKey: "DTXcodeBuild") as? String == "17F113")
        try #require(Bundle.main.object(forInfoDictionaryKey: "DTSDKName") as? String == "iphonesimulator26.5")
        try #require(UIDevice.current.systemVersion == "26.5")
        let runtimeBuild = try #require(ProcessInfo.processInfo.environment["BREV_SETTINGS_EXPECTED_RUNTIME_BUILD"])
        try #require(ProcessInfo.processInfo.operatingSystemVersionString.contains("Build \(runtimeBuild)"))
        let fixture = try Fixture(variant: variant, quietHoursEnabled: quietHoursEnabled)
        defer { fixture.cleanUp() }
        let view = fixture.styled(content(fixture), variant: variant)
        let host = UIHostingController(rootView: view)
        host.safeAreaRegions = []
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(displayScale: 2),
            UITraitCollection(horizontalSizeClass: .compact),
            UITraitCollection(userInterfaceStyle: variant.isDark ? .dark : .light),
            UITraitCollection(preferredContentSizeCategory: variant == .ax3 ? .accessibilityExtraLarge : .large)
        ])
        let image = try await SceneSnapshotCapture.image(
            of: host, size: CGSize(width: 375, height: variant.height),
            traits: traits, name: "\(name)-\(variant.rawValue)", scrollToBottom: scrollToBottom
        )
        if !compareReference || ProcessInfo.processInfo.environment["BREV_SETTINGS_SNAPSHOT_CANDIDATES"] == "YES" { return }
        assertSnapshot(
            of: image,
            as: .image,
            named: "\(name)-\(variant.rawValue)",
            record: .never,
            testName: "forms"
        )
    }

    @Test("settings root is one grouped list", arguments: Variant.allCases)
    func root(variant: Variant) async throws {
        try await snapshot("root", variant: variant) { fixture in
            SettingsRootHost(accountStore: fixture.accountStore, settingsStore: fixture.store)
        }
    }

    @Test("accounts pane is a form", arguments: Variant.allCases)
    func accounts(variant: Variant) async throws {
        try await snapshot("accounts", variant: variant) { fixture in
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
    func notifications(variant: Variant) async throws {
        try await snapshot("notifications", variant: variant) { $0.notifications }
    }

    @Test("sign-in code consent shows switches only for assessed accounts", arguments: Variant.allCases)
    func signInCodes(variant: Variant) async throws {
        try await snapshot("signin-codes", variant: variant) { $0.signInCodes }
    }

    @Test("appearance pane is a form", arguments: Variant.allCases)
    func appearance(variant: Variant) async throws {
        try await snapshot("appearance", variant: variant) { $0.appearance }
    }

    @Test("calendar & contacts sources list one line per collection", arguments: Variant.allCases)
    func pimSources(variant: Variant) async throws {
        let model = try await PIMSourcesFixture.model()
        try await snapshot("pim-sources", variant: variant) { $0.pimSources(model) }
    }

    @Test("lower panes remain visible in review captures",
          arguments: [SettingsReviewPane.appearance, .notifications, .notificationsQuietHours], Variant.allCases)
    func lowerPanes(pane: SettingsReviewPane, variant: Variant) async throws {
        try await snapshot("\(pane.rawValue)-bottom", variant: variant,
                           scrollToBottom: true, compareReference: false,
                           quietHoursEnabled: pane == .notificationsQuietHours) { fixture in
            if pane == .appearance {
                fixture.appearance
            } else {
                fixture.notifications
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
