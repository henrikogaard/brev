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
import BrevBackend
@testable import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

@Suite("On-device AI settings macOS snapshots (#304, ADR-0094)")
@MainActor
struct AIOnDeviceSettingsSnapshotTests {
    @Test("AI settings render Apple Intelligence ready and unavailable states", arguments: ["light", "dark"])
    func appleIntelligenceSettingsStates(_ mode: String) throws {
        guard #available(macOS 26.0, *) else { return }

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let readySuite = "AIOnDeviceReady-\(UUID().uuidString)"
        let readyDefaults = try #require(UserDefaults(suiteName: readySuite))
        defer { readyDefaults.removePersistentDomain(forName: readySuite) }
        let readyStore = SettingsPersistenceStore(defaults: readyDefaults)
        try readyStore.saveAIProviderConfigurations([
            AIProviderConfiguration.appleIntelligence(isEnabled: true, isDefault: true)
        ])

        let unavailableSuite = "AIOnDeviceUnavailable-\(UUID().uuidString)"
        let unavailableDefaults = try #require(UserDefaults(suiteName: unavailableSuite))
        defer { unavailableDefaults.removePersistentDomain(forName: unavailableSuite) }
        let unavailableStore = SettingsPersistenceStore(defaults: unavailableDefaults)

        let combined = VStack(alignment: .leading, spacing: 20) {
            AIProviderSettingsPanel(
                settingsStore: readyStore,
                secretStore: NoOpSecretStore(),
                appleIntelligenceAvailability: .available
            )

            AIProviderSettingsPanel(
                settingsStore: unavailableStore,
                secretStore: NoOpSecretStore(),
                appleIntelligenceAvailability: .appleIntelligenceNotEnabled
            )
        }
        .padding(16)
        .frame(width: 680, height: 760, alignment: .topLeading)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .tint(theme.accent.color)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .defaultAppStorage(readyDefaults)

        let host = NSHostingController(rootView: combined)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: Self.retinaImage(of: host, size: CGSize(width: 680, height: 760)),
            as: .image(precision: 0.99),
            named: "ai-on-device-\(mode)",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("AIWriterSection renders proactive toggle enabled on-device and disabled for cloud BYOK", arguments: ["light", "dark"])
    func proactiveOnDeviceToggleStates(_ mode: String) throws {
        guard #available(macOS 26.0, *) else { return }

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight

        let onDeviceSuite = "AIProactiveOnDevice-\(UUID().uuidString)"
        let onDeviceDefaults = try #require(UserDefaults(suiteName: onDeviceSuite))
        defer { onDeviceDefaults.removePersistentDomain(forName: onDeviceSuite) }
        let onDeviceStore = SettingsPersistenceStore(defaults: onDeviceDefaults)
        onDeviceStore.save(AIWriterSettings(
            isEnabled: true,
            consentGiven: true,
            proactiveOnDeviceTriageEnabled: true
        ))
        try onDeviceStore.saveAIProviderConfigurations([
            AIProviderConfiguration.appleIntelligence(isEnabled: true, isDefault: true)
        ])

        let cloudSuite = "AIProactiveCloud-\(UUID().uuidString)"
        let cloudDefaults = try #require(UserDefaults(suiteName: cloudSuite))
        defer { cloudDefaults.removePersistentDomain(forName: cloudSuite) }
        let cloudStore = SettingsPersistenceStore(defaults: cloudDefaults)
        cloudStore.save(AIWriterSettings(
            isEnabled: true,
            consentGiven: true,
            proactiveOnDeviceTriageEnabled: true
        ))
        let cloudConfig = try #require(AIProviderConfiguration(
            id: AIProviderID("openai"),
            kind: .openAICompatible,
            displayName: "OpenAI",
            endpointURL: URL(string: "https://api.openai.com/v1"),
            modelID: "gpt-4o",
            isEnabled: true,
            isDefault: true,
            assignedAccountID: nil
        ))
        try cloudStore.saveAIProviderConfigurations([cloudConfig])

        let combined = VStack(alignment: .leading, spacing: 20) {
            AIWriterSection(
                settingsStore: onDeviceStore,
                providerSecretStore: NoOpSecretStore(),
                appleIntelligenceAvailability: .available
            )
            .frame(height: 280, alignment: .top)
            .clipped()

            AIWriterSection(
                settingsStore: cloudStore,
                providerSecretStore: NoOpSecretStore(),
                appleIntelligenceAvailability: .available
            )
            .frame(height: 292, alignment: .top)
            .clipped()
        }
        .padding(16)
        .frame(width: 680, height: 616, alignment: .topLeading)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .tint(theme.accent.color)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .defaultAppStorage(onDeviceDefaults)

        let host = NSHostingController(rootView: combined)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: Self.retinaImage(of: host, size: CGSize(width: 680, height: 616)),
            as: .image(precision: 0.99),
            named: "ai-proactive-toggle-\(mode)",
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

private actor NoOpSecretStore: AIProviderSecretStore {
    func apiKey(for _: AIProviderID) async throws -> String? { nil }
    func setAPIKey(_: String, for _: AIProviderID) async throws {}
    func deleteAPIKey(for _: AIProviderID) async throws {}
}
#endif
