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
@testable import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

/// macOS 26+ snapshot coverage for `SignInCodeSettingsGroup` with inline
/// verification guidance enabled (`showsVerificationGuidance: true`, #5).
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh baselines on macOS 26+.
@Suite("Sign-in code verification guidance macOS snapshots (#5)", .serialized)
@MainActor
struct SignInCodeVerificationGuidanceSnapshotTests {
    @Test(
        "SignInCodeSettingsGroup renders inline verification guidance on eligible accounts",
        arguments: ["light", "dark"]
    )
    func signInCodeVerificationGuidanceRenders(_ mode: String) throws {
        guard #available(macOS 26.0, *) else { return }

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let suite = "SignInCodeGuidanceSnapshot-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let accounts = [
            BrevAccount(
                id: "imap-smtp:alex@fastmail.example",
                displayName: "Fastmail",
                emailAddress: "alex@fastmail.example"
            ),
            BrevAccount(
                id: "imap-smtp:local@bridge.example",
                displayName: "Local Bridge",
                emailAddress: "local@bridge.example"
            )
        ]

        let view = VStack(alignment: .leading, spacing: 0) {
            SignInCodeSettingsGroup(
                accounts: accounts,
                settingsStore: SettingsPersistenceStore(defaults: defaults),
                isAvailable: { $0 == "imap-smtp:alex@fastmail.example" },
                showsVerificationGuidance: true
            )
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 640, height: 430, alignment: .topLeading)
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
            of: Self.retinaImage(of: host, size: CGSize(width: 640, height: 430)),
            as: .image(precision: 0.99),
            named: "signin-code-verification-guidance-\(mode)",
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
