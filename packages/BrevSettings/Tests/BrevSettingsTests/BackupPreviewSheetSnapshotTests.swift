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

@Suite("Backup preview sheet snapshots")
@MainActor
struct BackupPreviewSheetSnapshotTests {
    @Test("Preview sheet renders in light and dark", arguments: ["light", "dark"])
    func previewSheetRenders(_ mode: String) {
        guard #available(macOS 26.0, *) else { return }
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let preview = BackupPreview(
            url: URL(fileURLWithPath: "/tmp/Brev backup.brevbackup"),
            manifest: BrevBackupManifest(
                createdAt: Date(timeIntervalSince1970: 1_770_000_000),
                appVersion: "1.2.3",
                appBuild: "45",
                platform: "macOS",
                payloads: []
            ),
            settings: SettingsBackupPayload(
                localRules: LocalRulesSettings(
                    rules: [
                        ServerRule(
                            id: "r1", name: "Receipts", isEnabled: true,
                            conditions: [.subjectContains("receipt")], actions: [.archive]
                        )
                    ],
                    isAutomaticExecutionEnabled: true
                )
            ),
            accounts: [
                AccountBackupEntry(
                    account: BrevAccount(
                        id: "imap-smtp:ada@example.org",
                        displayName: "Ada",
                        emailAddress: "ada@example.org"
                    ),
                    imapConfiguration: nil
                )
            ],
            skippedUnknownKeys: 1,
            strippedFields: ["calDAV.credentialAccount"],
            alreadySignedInAccounts: 0
        )
        let view = BackupPreviewSheet(preview: preview, onCancel: {}, onRestore: { _ in })
            .brevTheme(theme)
            .environment(\.colorScheme, theme.mode.colorScheme)

        let size = CGSize(width: 460, height: 560)
        let host = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = host
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        defer { window.contentViewController = nil; window.close() }
        let rendered = host.view
        rendered.frame.size = size
        rendered.layoutSubtreeIfNeeded()

        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: .alphaFirst,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.size = size
        rendered.cacheDisplay(in: rendered.bounds, to: bitmap)
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)

        assertSnapshot(
            of: image,
            as: .image,
            named: "backup-preview-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES"
        )
    }
}
#endif
