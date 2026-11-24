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
import BrevAI
@testable import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

@Suite("Privacy onboarding sheet macOS snapshots", .serialized)
@MainActor
struct PrivacyOnboardingSnapshotTests {
    @Test("first-run walkthrough renders all-off defaults cleanly", arguments: ["light", "dark"])
    func firstRunAllOffDefaults(_ mode: String) throws {
        guard #available(macOS 26.0, *) else { return }

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let suite = "PrivacyOnboardingFirstRun-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let size = CGSize(width: 620, height: 860)
        let view = PrivacyOnboardingSheet(
            mode: .firstRun,
            settingsStore: SettingsPersistenceStore(defaults: defaults),
            appleIntelligenceAvailability: .available,
            onAvatarPreferencesChanged: { _ in }
        )
        .frame(width: size.width, height: size.height)
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
            of: Self.retinaImage(of: host, size: size),
            as: .image(precision: 0.99),
            named: "privacy-onboarding-first-run-\(mode)",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("review from Settings reflects enabled choices and unavailable on-device AI", arguments: ["light", "dark"])
    func reviewFromSettingsWithUnavailableAI(_ mode: String) throws {
        guard #available(macOS 26.0, *) else { return }

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let suite = "PrivacyOnboardingReview-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsPersistenceStore(defaults: defaults)
        var saved = PrivacyOnboardingChoices.allOff
        saved.useDomainAvatars = true
        saved.allowRemoteContentForTrustedSenders = true
        saved.iCloudPreferenceSyncEnabled = true
        saved.backgroundIndexingEnabled = true
        saved.apply(
            to: store,
            relativeTo: .allOff,
            appleIntelligenceAvailability: .deviceNotEligible
        )

        let size = CGSize(width: 620, height: 860)
        let view = PrivacyOnboardingSheet(
            mode: .reviewFromSettings,
            settingsStore: store,
            appleIntelligenceAvailability: .deviceNotEligible,
            onAvatarPreferencesChanged: { _ in }
        )
        .frame(width: size.width, height: size.height)
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
            of: Self.retinaImage(of: host, size: size),
            as: .image(precision: 0.99),
            named: "privacy-onboarding-review-unavailable-ai-\(mode)",
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
