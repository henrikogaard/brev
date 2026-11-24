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

@Suite("Background indexing settings macOS snapshots", .serialized)
@MainActor
struct BackgroundIndexingSettingsSnapshotTests {
    @Test("disabled state renders single opt-in toggle", arguments: ["light", "dark"])
    func backgroundIndexingOff(_ mode: String) throws {
        guard #available(macOS 26.0, *) else { return }

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let suite = "BackgroundIndexingOff-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        BackgroundIndexingSettings.defaults.save(to: defaults)

        let view = BackgroundIndexingSettingsGroup(
            settingsStore: SettingsPersistenceStore(defaults: defaults),
            statusModel: BackgroundIndexingStatusModel(status: .idle),
            referenceDate: Date(timeIntervalSince1970: 1_750_000_000)
        )
        .padding(24)
        .frame(width: 600, height: 220, alignment: .topLeading)
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
            of: Self.retinaImage(of: host, size: CGSize(width: 600, height: 220)),
            as: .image(precision: 0.99),
            named: "background-indexing-off-\(mode)",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("enabled running state renders window, toggles, progress, and actions", arguments: ["light", "dark"])
    func backgroundIndexingRunning(_ mode: String) throws {
        guard #available(macOS 26.0, *) else { return }

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let suite = "BackgroundIndexingRunning-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        BackgroundIndexingSettings(
            isEnabled: true,
            windowDays: .days90,
            indexAttachments: true,
            requireUnmeteredNetworkAndPower: true
        ).save(to: defaults)

        let model = BackgroundIndexingStatusModel(
            status: BackgroundIndexingStatus(
                state: .running(completed: 12, total: 40),
                indexedMessagesCount: 12,
                indexedAttachmentsCount: 4,
                pendingCount: 28,
                lastIndexedAt: Date(timeIntervalSince1970: 1_749_999_400)
            )
        )

        let view = BackgroundIndexingSettingsGroup(
            settingsStore: SettingsPersistenceStore(defaults: defaults),
            statusModel: model,
            referenceDate: Date(timeIntervalSince1970: 1_750_000_000)
        )
        .padding(24)
        .frame(width: 600, height: 520, alignment: .topLeading)
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
            of: Self.retinaImage(of: host, size: CGSize(width: 600, height: 520)),
            as: .image(precision: 0.99),
            named: "background-indexing-running-\(mode)",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("paused state renders battery/cellular warning callout and resume controls", arguments: ["light", "dark"])
    func backgroundIndexingPaused(_ mode: String) throws {
        guard #available(macOS 26.0, *) else { return }

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let suite = "BackgroundIndexingPaused-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        BackgroundIndexingSettings(
            isEnabled: true,
            windowDays: .days365,
            indexAttachments: true,
            requireUnmeteredNetworkAndPower: true
        ).save(to: defaults)

        let model = BackgroundIndexingStatusModel(
            status: BackgroundIndexingStatus(
                state: .paused(.lowPowerMode),
                indexedMessagesCount: 24,
                indexedAttachmentsCount: 6,
                pendingCount: 16,
                lastIndexedAt: Date(timeIntervalSince1970: 1_749_996_400)
            )
        )

        let view = BackgroundIndexingSettingsGroup(
            settingsStore: SettingsPersistenceStore(defaults: defaults),
            statusModel: model,
            referenceDate: Date(timeIntervalSince1970: 1_750_000_000)
        )
        .padding(24)
        .frame(width: 600, height: 520, alignment: .topLeading)
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
            of: Self.retinaImage(of: host, size: CGSize(width: 600, height: 520)),
            as: .image(precision: 0.99),
            named: "background-indexing-paused-\(mode)",
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
