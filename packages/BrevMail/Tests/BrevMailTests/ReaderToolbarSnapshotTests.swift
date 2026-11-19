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
@testable import BrevMail
import BrevSettings
import SnapshotTesting
import SwiftUI
import Testing

/// The macOS reader toolbar (#306 slice 3), rendered in a real window so the
/// system draws its capsules: Reply / Reply All / Forward, then Archive /
/// Delete / Move / Snooze / More, then the AI Sidebar toggle, then search.
/// A narrow window folds the extra actions into More.
@Suite("Reader toolbar snapshots", .serialized)
@MainActor
struct ReaderToolbarSnapshotTests {
    @Test("reader toolbar capsules at wide and narrow window widths", arguments: [
        ("wide", CGFloat(1600)), ("narrow", CGFloat(1000)),
    ])
    func toolbar(_ name: String, width: CGFloat) async throws {
        let image = try await Self.renderToolbar(windowWidth: width)
        assertSnapshot(of: image, as: .image(precision: 0.98), named: name,
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

    /// Hosts the real root view with a mock message open, then crops the
    /// window's titlebar, where SwiftUI bridges the toolbar.
    private static func renderToolbar(windowWidth: CGFloat) async throws -> NSImage {
        let defaults = try #require(UserDefaults(suiteName: "ReaderToolbarSnapshotTests-\(UUID().uuidString)"))
        var route: NotificationMailRoute?
        let routeBinding = Binding(get: { route }, set: { route = $0 })
        let host = NSHostingController(rootView: BrevMailRootView(
            backend: MockBackend(),
            settingsStore: SettingsPersistenceStore(defaults: defaults),
            pendingNotificationRoute: routeBinding
        ))
        host.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(NSSize(width: windowWidth, height: 720))
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        await settle(seconds: 3)
        route = NotificationMailRoute(accountID: BrevAccount.preview.id, folderID: "inbox", messageID: "m1")
        host.rootView = BrevMailRootView(
            backend: MockBackend(),
            settingsStore: SettingsPersistenceStore(defaults: defaults),
            pendingNotificationRoute: routeBinding
        )
        await settle(seconds: 3)

        let frameView = try #require(window.contentView?.superview)
        let toolbarHeight: CGFloat = 52
        let rect = NSRect(x: 0, y: frameView.bounds.height - toolbarHeight,
                          width: frameView.bounds.width, height: toolbarHeight)
        let rep = try #require(frameView.bitmapImageRepForCachingDisplay(in: rect))
        frameView.cacheDisplay(in: rect, to: rep)
        let image = NSImage(size: rect.size)
        image.addRepresentation(rep)
        return image
    }

    /// Lets both the main run loop (SwiftUI transactions, toolbar bridging)
    /// and main-actor tasks (mailbox loading) make progress.
    private static func settle(seconds: Double) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
#endif
