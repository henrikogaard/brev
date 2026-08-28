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
import BrevThemes
import SwiftUI

/// Native chrome for a standalone message reader with a visible subject title.
enum DetachedMessageWindowChrome {
    static let styleMask: NSWindow.StyleMask = [
        .titled,
        .closable,
        .miniaturizable,
        .resizable,
        .fullSizeContentView
    ]
    static let titleVisibility: NSWindow.TitleVisibility = .visible
    static let titlebarAppearsTransparent = true
    static let toolbarStyle: NSWindow.ToolbarStyle = .automatic

    static func apply(to window: NSWindow) {
        window.titleVisibility = titleVisibility
        window.titlebarAppearsTransparent = titlebarAppearsTransparent
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = toolbarStyle
    }
}

/// Opens a message in a standalone window detached from the main reading pane.
///
/// Multiple windows can coexist; each closes independently. Windows are
/// cascaded so they don't overlap exactly when opened in quick succession.
@MainActor
enum DetachedMessageWindow {
    private static var lastCascadePoint: NSPoint = .zero

    static func open(
        header: MessageHeader,
        backend: any MailBackend,
        sourceID: MailSourceID?,
        allFolders: [Folder],
        theme: BrevTheme
    ) {
        // Capture the main window (the one the user double-clicked in) before
        // the new window becomes key, so the message window can open aligned to
        // it rather than in the bottom-left corner.
        let referenceWindow = NSApp.keyWindow ?? NSApp.mainWindow
        let referenceFrame = referenceWindow?.frame
        let screen = referenceWindow?.screen ?? NSScreen.main

        let initialFrame = Self.placement(
            relativeTo: referenceFrame,
            visibleFrame: screen?.visibleFrame
        )
        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: DetachedMessageWindowChrome.styleMask,
            backing: .buffered,
            defer: false
        )

        // Build the content after the window exists so the in-content action bar
        // can close this window after a destructive action (archive/delete/move).
        let content = MessageDetailView(
            backend: backend,
            sourceID: sourceID,
            header: header,
            navigation: nil,
            allFolders: allFolders,
            closeWindow: { [weak window] in window?.close() }
        )
        .brevMailPaneSurface(.content)
        .background(BrevWindowSurfaceBackground(role: .utility).ignoresSafeArea())
        .brevWindowTranslucency(windowRole: .utility)
        .brevTheme(theme)
        let hostingController = NSHostingController(rootView: content)

        let subject = header.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        window.title = subject.isEmpty ? "Message" : subject
        window.minSize = CGSize(width: 640, height: 480)
        window.contentMinSize = CGSize(width: 640, height: 480)
        // Detached readers are not retained in a registry. Let AppKit release
        // the window (and its hosting controller/WebKit view) after close;
        // retaining every closed reader would leak one full view hierarchy per
        // open/close cycle.
        window.isReleasedWhenClosed = true
        window.isRestorable = false
        window.contentViewController = hostingController
        DetachedMessageWindowChrome.apply(to: window)
        window.setFrame(initialFrame, display: false)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A generous reading-window frame, centered horizontally over the reference
    /// window with its top aligned to that window's top. Subsequent windows
    /// cascade down-right so they don't land exactly on top of each other.
    private static func placement(
        relativeTo referenceFrame: NSRect?,
        visibleFrame: NSRect?
    ) -> NSRect {
        let visible = visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let base = referenceFrame ?? visible

        let width = min(960, max(720, visible.width * 0.62))
        let height = min(1180, max(560, visible.height * 0.9))

        var origin = NSPoint(
            x: base.midX - width / 2,
            // Bottom-origin coordinates: align the new window's top edge with the
            // reference window's top edge.
            y: base.maxY - height
        )
        if lastCascadePoint != .zero {
            origin = NSPoint(x: lastCascadePoint.x + 28, y: lastCascadePoint.y - 28)
        }
        lastCascadePoint = origin

        let frame = NSRect(origin: origin, size: CGSize(width: width, height: height))
        return MacMailAuxiliaryWindowPlacementPolicy.constrainedFrame(
            frame,
            visibleFrame: visible
        )
    }
}
#endif
