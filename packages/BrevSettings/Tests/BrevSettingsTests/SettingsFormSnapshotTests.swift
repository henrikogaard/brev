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
import BrevCalendar
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

    @Test("sign-in code consent shows switches only for assessed accounts", arguments: Variant.allCases)
    func signInCodes(variant: Variant) throws {
        try snapshot("signin-codes", variant: variant) { fixture in
            let other = BrevAccount(id: "imap", displayName: "Work IMAP", emailAddress: "work@ogard.example")
            return NavigationStack {
                Form {
                    SignInCodeSettingsGroup(
                        accounts: [fixture.account, other],
                        settingsStore: fixture.store,
                        isAvailable: { $0 == fixture.account.id }
                    )
                }
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

    @Test("calendar & contacts sources list one line per collection", arguments: Variant.allCases)
    func pimSources(variant: Variant) async throws {
        let model = try await PIMSourcesFixture.model()
        try snapshot("pim-sources", variant: variant) { _ in
            NavigationStack {
                Form {
                    PIMSourcesSettingsView(model: model, googleAccounts: [])
                }
                .navigationTitle("Calendar & Contacts")
            }
        }
    }
}

/// Seeded Google calendar + contacts sources and a DAV calendar, so the
/// snapshot shows source switches and a long contact-group list.
@MainActor
private enum PIMSourcesFixture {
    actor SourceStore: PIMSourceStore {
        var records: [PIMSource]
        init(_ records: [PIMSource]) { self.records = records }
        func allSources() async throws -> [PIMSource] { records }
        func save(_ source: PIMSource) async throws {}
        func deleteSource(id: PIMSource.ID) async throws {}
    }

    actor CollectionStore: PIMCollectionStore {
        var records: [PIMSource.ID: [PIMCollection]]
        init(_ records: [PIMSource.ID: [PIMCollection]]) { self.records = records }
        func collections(for sourceID: PIMSource.ID) async throws -> [PIMCollection] { records[sourceID] ?? [] }
        func saveCollections(_ collections: [PIMCollection], for sourceID: PIMSource.ID) async throws {}
        func deleteCollections(for sourceID: PIMSource.ID) async throws {}
    }

    struct LocalData: PIMSourceLocalDataStore {
        func deleteSyncAndDraftData(for sourceID: PIMSource.ID) async throws {}
        func deleteCachedContent(for sourceID: PIMSource.ID) async throws {}
        func markCacheDisconnected(for sourceID: PIMSource.ID) async throws {}
    }

    static func model() async throws -> PIMSourceSettingsModel {
        let sources = [
            PIMSource(id: "g-cal", kind: .calendar, provider: .google, linkedAccountID: "demo",
                      displayName: "henrik@ogard.example", syncEnabled: true, status: .ready),
            PIMSource(id: "g-con", kind: .contacts, provider: .google, linkedAccountID: "demo",
                      displayName: "henrik@ogard.example", status: .ready),
            PIMSource(id: "dav", kind: .calendar, provider: .calDAV, displayName: "dav.example.com",
                      endpointURL: URL(string: "https://dav.example.com/"), status: .ready)
        ]
        func collection(_ id: String, _ source: String, _ kind: PIMSourceKind, _ name: String,
                        primary: Bool = false, readOnly: Bool = false, color: String? = nil) -> PIMCollection {
            PIMCollection(id: id, sourceID: source, kind: kind, displayName: name, colorHex: color,
                          isReadOnly: readOnly, isPrimary: primary, providerKey: id)
        }
        let groups = ["All contacts", "Blocked", "Family", "Coworkers", "Chat contacts", "Starred", "Friends"]
        let collections: [PIMSource.ID: [PIMCollection]] = [
            "g-cal": [collection("c1", "g-cal", .calendar, "henrik@ogard.example", primary: true, color: "#4FC3F7")],
            "g-con": [collection("my", "g-con", .contacts, "My contacts", primary: true, readOnly: true)]
                + groups.map { collection($0, "g-con", .contacts, $0, readOnly: true) },
            "dav": [collection("qa", "dav", .calendar, "QA Calendar", color: "#E57373")]
        ]
        let credentials = InMemoryCalDAVCredentialStore()
        let coordinator = PIMSourceCoordinator(
            store: SourceStore(sources),
            credentials: credentials,
            localData: LocalData()
        )
        let model = PIMSourceSettingsModel(
            coordinator: coordinator,
            collectionService: PIMCollectionService(
                coordinator: coordinator,
                store: CollectionStore(collections),
                credentials: credentials
            )
        )
        await model.load()
        return model
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
