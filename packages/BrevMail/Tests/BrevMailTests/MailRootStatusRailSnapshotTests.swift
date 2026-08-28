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
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

@Suite("Mail root status rail snapshots")
@MainActor
struct MailRootStatusRailSnapshotTests {
    @Test("Downloading rail reserves space above every workspace pane")
    func downloadingRailStacksAboveWorkspace() {
        let theme = BrevTheme.brevPaper
        let view = VStack(spacing: 0) {
            ImportProgressBanner(
                presentation: ImportProgressBannerPresentation(
                    phase: .backfillContinuing,
                    title: "Downloading mail",
                    message: "You can read available messages while Brev downloads the rest.",
                    style: .info,
                    showsDeterminateProgress: true,
                    progressCompleted: 2,
                    progressTotal: 5,
                    progressFraction: 0.4,
                    showsRetryAction: false,
                    accessibilityLabel: "Downloading mail. 2 of 5 folders complete."
                ),
                onRetry: nil
            )

            NavigationSplitView {
                Text("Folders")
                    .frame(minWidth: 200)
            } content: {
                Text("Messages")
                    .frame(minWidth: 280)
            } detail: {
                Text("Reader")
                    .frame(minWidth: 400)
            }
        }
        .frame(width: 960, height: 600)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 960, height: 600)

        assertSnapshot(
            of: Self.retinaImage(of: host, size: CGSize(width: 960, height: 600)),
            as: .image,
            named: "downloading-rail",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    private static func retinaImage<Content: View>(
        of host: NSHostingController<Content>,
        size: CGSize
    ) -> NSImage {
        let view = host.view
        let originalSize = view.frame.size
        view.frame.size = size
        view.layoutSubtreeIfNeeded()
        defer { view.frame.size = originalSize }

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
        view.cacheDisplay(in: view.bounds, to: bitmap)

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }
}
#endif
