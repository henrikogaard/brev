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

#if os(macOS)
import AppKit
import BrevBackend
import BrevDesign
@testable import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

@Suite("Closed-app push relay macOS snapshots (#11)", .serialized)
@MainActor
struct PushRelaySettingsSnapshotTests {
    @Test("PushRelaySettingsGroup renders enabled self-hosted push UI", arguments: ["light", "dark"])
    func pushRelayEnabledRenders(_ mode: String) throws {
        guard #available(macOS 26.0, *) else { return }

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let suite = "PushRelaySnapshot-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let endpoint = "https://push.northwind.example/v1/register"
        let settings = PushRelaySettings(
            isEnabled: true,
            mode: .userHostedRelay,
            endpointURLString: endpoint,
            enabledAccountIDs: ["acct-work"],
            opaqueAccountTokens: ["acct-work": "acct-opaque-work"],
            deviceClientID: "brev-dev-snapshot",
            activeRegistration: ActivePushRelayRegistration(
                mode: .userHostedRelay,
                endpointURLString: endpoint,
                subscriptionID: "sub-snapshot-1",
                state: .active,
                registeredAt: Date(timeIntervalSince1970: 1_750_000_000)
            ),
            lastRegistrationError: nil
        )
        settings.save(to: defaults)

        let secretStore = InMemoryPushRelaySecretStore(
            bearerTokensByOrigin: ["https://push.northwind.example": "saved-keychain-secret"]
        )
        let accounts = [
            BrevAccount(id: "acct-work", displayName: "Work", emailAddress: "work@northwind.example"),
            BrevAccount(id: "acct-personal", displayName: "Personal", emailAddress: "personal@example.org")
        ]

        let view = ScrollView {
            PushRelaySettingsGroup(
                settingsStore: SettingsPersistenceStore(defaults: defaults),
                secretStore: secretStore,
                accounts: accounts,
                devicePushTokenProvider: { "deadbeef01234567" },
                statusTimeZone: TimeZone(secondsFromGMT: 0) ?? .gmt,
                statusLocale: Locale(identifier: "en_US")
            )
            .padding(BrevSpacing.xl)
        }
        .frame(width: 680, height: 700)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .tint(theme.accent.color)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .defaultAppStorage(defaults)
        .transaction { $0.animation = nil }

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: Self.retinaImage(of: host, size: CGSize(width: 680, height: 700)),
            as: .image(precision: 0.99),
            named: "push-relay-enabled-\(mode)",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    private static func retinaImage<Content: View>(
        of host: NSHostingController<Content>,
        size: CGSize
    ) -> NSImage {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = host
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        defer {
            window.contentViewController = nil
            window.close()
        }
        let view = host.view
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}
#endif
