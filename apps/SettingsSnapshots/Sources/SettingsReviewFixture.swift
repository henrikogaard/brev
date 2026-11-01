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
import BrevCalendar
@testable import BrevSettings
import BrevThemes
import SwiftUI

enum SettingsReviewVariant: String, CaseIterable {
    case light
    case dark
    case ax3

    var isDark: Bool { self == .dark }
    var height: CGFloat { self == .ax3 ? 1800 : 812 }
}

enum SettingsReviewPane: String, CaseIterable {
    case appearance
    case notifications
    case notificationsQuietHours = "notifications-quiet-hours"
    case signInCodes = "signin-codes"
    case pimSources = "pim-sources"
}

struct SettingsReviewSelection: Equatable {
    enum SelectionError: Error { case invalidSelection }
    let pane: SettingsReviewPane
    let variant: SettingsReviewVariant

    static func parse(_ environment: [String: String]) throws -> Self? {
        let pane = environment["BREV_SETTINGS_REVIEW_PANE"]
        let variant = environment["BREV_SETTINGS_REVIEW_VARIANT"]
        guard pane != nil || variant != nil else { return nil }
        guard let pane, let pane = SettingsReviewPane(rawValue: pane),
              let variant, let variant = SettingsReviewVariant(rawValue: variant) else {
            throw SelectionError.invalidSelection
        }
        return Self(pane: pane, variant: variant)
    }
}

@MainActor
struct SettingsReviewFixture {
    let defaults: UserDefaults
    let store: SettingsPersistenceStore
    let theme: BrevTheme
    let account: BrevAccount
    let accountStore: InMemoryAccountStore
    let suite: String

    init(variant: SettingsReviewVariant, suite: String = "SettingsForm-" + UUID().uuidString,
         quietHoursEnabled: Bool = false) throws {
        self.suite = suite
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.fileReadUnknown) }
        self.defaults = defaults
        defaults.removePersistentDomain(forName: suite)
        store = SettingsPersistenceStore(defaults: defaults)
        if quietHoursEnabled {
            var notifications = NotificationSettings.defaults
            notifications.quietHoursEnabled = true
            store.save(notifications)
        }
        var settings = AppearanceThemeSettings.defaults
        settings.mode = variant.isDark ? .alwaysDark : .alwaysLight
        settings.save(to: defaults)
        theme = settings.resolvedTheme(prefersDark: variant.isDark)
        account = BrevAccount(id: "demo", displayName: "Henrik Øgård", emailAddress: "henrik@ogard.example")
        accountStore = InMemoryAccountStore(accounts: [account], current: account)
    }

    func cleanUp() { defaults.removePersistentDomain(forName: suite) }

    func styled(_ content: some View, variant: SettingsReviewVariant) -> some View {
        content
            .brevTheme(theme)
            .tint(theme.accent.color)
            .environment(\.colorScheme, variant.isDark ? .dark : .light)
            .environment(\.dynamicTypeSize, variant == .ax3 ? .accessibility3 : .large)
            .environment(\.locale, Locale(identifier: "en_US"))
    }

    var appearance: some View {
        NavigationStack {
            AppearanceSection(
                activeTheme: .constant(theme), activeAppIcon: .constant(.defaultVariant), settingsStore: store
            )
            .navigationTitle("Appearance")
        }
    }

    var notifications: some View {
        NavigationStack {
            NotificationSection(settingsStore: store, accounts: [account], authorizationStatus: { .denied })
                .navigationTitle("Notifications")
        }
    }

    var signInCodes: some View {
        let other = BrevAccount(id: "imap", displayName: "Work IMAP", emailAddress: "work@ogard.example")
        return NavigationStack {
            Form {
                SignInCodeSettingsGroup(
                    accounts: [account, other], settingsStore: store, isAvailable: { $0 == account.id }
                )
            }
            .navigationTitle("Notifications")
        }
    }

    func pimSources(_ model: PIMSourceSettingsModel) -> some View {
        NavigationStack {
            Form {
                PIMSourcesSettingsView(model: model, googleAccounts: [])
            }
            .navigationTitle("Calendar & Contacts")
        }
    }
}

/// In-memory copies of the canonical sources, with all network transports denied.
@MainActor
enum PIMSourcesFixture {
    actor SourceStore: PIMSourceStore {
        var records: [PIMSource]
        init(_ records: [PIMSource]) { self.records = records }
        func allSources() async throws -> [PIMSource] { records }
        func save(_ source: PIMSource) async throws {
            records.removeAll { $0.id == source.id }
            records.append(source)
        }

        func deleteSource(id: PIMSource.ID) async throws { records.removeAll { $0.id == id } }
    }

    actor CollectionStore: PIMCollectionStore {
        var records: [PIMSource.ID: [PIMCollection]]
        init(_ records: [PIMSource.ID: [PIMCollection]]) { self.records = records }
        func collections(for sourceID: PIMSource.ID) async throws -> [PIMCollection] { records[sourceID] ?? [] }
        func saveCollections(_ collections: [PIMCollection], for sourceID: PIMSource.ID) async throws {
            records[sourceID] = collections
        }

        func deleteCollections(for sourceID: PIMSource.ID) async throws { records[sourceID] = nil }
    }

    struct LocalData: PIMSourceLocalDataStore {
        func deleteSyncAndDraftData(for sourceID: PIMSource.ID) async throws {}
        func deleteCachedContent(for sourceID: PIMSource.ID) async throws {}
        func markCacheDisconnected(for sourceID: PIMSource.ID) async throws {}
    }

    struct DeniedTransport: PIMDAVTransport {
        func send(_: URLRequest) async throws -> (Data, HTTPURLResponse) {
            throw URLError(.notConnectedToInternet)
        }
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
            store: SourceStore(sources), credentials: credentials, localData: LocalData(),
            davClient: PIMDAVClient(transport: DeniedTransport())
        )
        let model = PIMSourceSettingsModel(
            coordinator: coordinator,
            collectionService: PIMCollectionService(
                coordinator: coordinator, store: CollectionStore(collections), credentials: credentials,
                davDiscovery: PIMDAVCollectionDiscovery(transport: DeniedTransport()),
                googleDiscovery: GooglePIMCollectionDiscovery(transport: DeniedTransport())
            )
        )
        await model.load()
        return model
    }
}
