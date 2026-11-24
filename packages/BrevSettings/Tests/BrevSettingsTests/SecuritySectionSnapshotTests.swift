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
@testable import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

@Suite("Security settings macOS snapshots", .serialized)
@MainActor
struct SecuritySectionSnapshotTests {
    @Test("SecuritySection renders S/MIME defaults, key catalog, and import/export", arguments: ["light", "dark"])
    func securitySectionRenders(_ mode: String) throws {
        guard #available(macOS 26.0, *) else { return }

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let suite = "SecuritySectionSnapshot-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let encryption = EncryptionSettings(smimeEnabled: true, preferSign: true, preferEncrypt: false)
        encryption.save(to: defaults)

        let keyMaterial = SecurityKeyMaterialSettings(
            records: [
                SecurityKeyMaterialSettings.Record(
                    id: "smime-snapshot-1",
                    family: .smime,
                    label: "Work S/MIME Identity",
                    emailAddress: "work@northwind.example",
                    fingerprint: "SHA256:9F86D081884C7D65",
                    algorithm: "RSA-2048",
                    canSign: true,
                    canEncrypt: true,
                    hasPrivateMaterial: true,
                    trust: .trusted,
                    importedAt: Date(timeIntervalSince1970: 1_735_689_600)
                )
            ],
            importExport: .defaults
        )
        keyMaterial.save(to: defaults)

        let view = SecuritySection(settingsStore: SettingsPersistenceStore(defaults: defaults))
            .frame(width: 700, height: 960)
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
            of: Self.retinaImage(of: host, size: CGSize(width: 700, height: 960)),
            as: .image(precision: 0.99),
            named: "security-section-\(mode)",
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
