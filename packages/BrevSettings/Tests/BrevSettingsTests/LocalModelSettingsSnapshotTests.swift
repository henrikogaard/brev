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

@Suite("Downloaded local model settings macOS snapshots (#304, Slice 2)")
@MainActor
struct LocalModelSettingsSnapshotTests {
    @Test("Local models group renders installed, downloading, and catalog states", arguments: ["light", "dark"])
    func localModelCatalogAndInstalledStates(_ mode: String) throws {
        guard #available(macOS 26.0, *) else { return }

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let models = LocalModelCatalog.curatedModels
        let firstID = try #require(models.first?.id)
        let secondID = try #require(models.dropFirst().first?.id)
        let thirdID = try #require(models.dropFirst(2).first?.id)

        let states: [String: LocalModelDownloadState] = [
            firstID: .installed(
                installedAt: Date(timeIntervalSince1970: 1_760_000_000),
                fileSizeBytes: 2_104_932_736
            ),
            secondID: .downloading(
                progress: 0.52,
                bytesWritten: 1_050_076_402,
                totalBytes: 2_019_377_696
            ),
            thirdID: .notDownloaded
        ]

        let view = LocalModelsSettingsGroup(
            catalog: models,
            activeModelID: firstID,
            initialStates: states,
            initialTotalInstalledBytes: 2_104_932_736
        )
        .padding(16)
        .frame(width: 680, height: 620, alignment: .topLeading)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .tint(theme.accent.color)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: Self.retinaImage(of: host, size: CGSize(width: 680, height: 620)),
            as: .image(precision: 0.99),
            named: "local-models-\(mode)",
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
