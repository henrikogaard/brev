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

import CoreGraphics
import Foundation
#if os(macOS)
import AppKit
import SwiftUI
#endif

/// How the window reacts when the AI Sidebar opens and closes.
///
/// The sidebar is an in-window trailing column, so its width comes out of the
/// reader beside it. At the shipped 960pt default that left the reader around
/// 160pt — one word per line. macOS inspectors do not do that: they widen the
/// window and give the inspector its own space, then hand the width back when
/// the inspector closes.
enum MailContextWindowGrowthPolicy {
    /// Duration of the window resize, and therefore of the whole open/close
    /// motion: `MailContextInspectorModifier` freezes the content layout for
    /// this long while the window edge reveals or conceals the column.
    /// AppKit's `setFrame(animate:)` derives its own duration from the resize
    /// distance, which is why the window resize goes through an explicit
    /// animation context instead.
    static let animationDuration: TimeInterval = 0.25

    /// Width to grow to when the column appears, or nil to leave the window be.
    ///
    /// Capped at the screen so the window cannot grow off the display; a window
    /// already at that cap keeps its width and the column takes its space from
    /// the reader, which is the best available outcome on a small display.
    static func widthOnOpen(
        currentWidth: CGFloat,
        columnWidth: CGFloat,
        maximumWidth: CGFloat
    ) -> CGFloat? {
        let target = min(currentWidth + columnWidth, maximumWidth)
        return target > currentWidth ? target : nil
    }

    /// Width to return to when the column closes, or nil to leave the window be.
    ///
    /// Only gives back growth this policy caused, and only when the user has not
    /// since made the window narrower than it was before — resizing by hand wins
    /// over restoring a remembered width.
    static func widthOnClose(currentWidth: CGFloat, widthBeforeOpen: CGFloat?) -> CGFloat? {
        guard let widthBeforeOpen, widthBeforeOpen < currentWidth else { return nil }
        return widthBeforeOpen
    }

    /// Origin that keeps a resized window on its screen.
    ///
    /// Growing from the trailing edge alone pushes the window off the right of
    /// the display, so a window that would overhang slides left instead.
    static func originX(
        currentOriginX: CGFloat,
        newWidth: CGFloat,
        screenMinX: CGFloat,
        screenMaxX: CGFloat
    ) -> CGFloat {
        let overhang = (currentOriginX + newWidth) - screenMaxX
        guard overhang > 0 else { return currentOriginX }
        return max(screenMinX, currentOriginX - overhang)
    }
}

#if os(macOS)
/// Applies `MailContextWindowGrowthPolicy` to the hosting window.
struct MailContextWindowWidthAdjuster: NSViewRepresentable {
    let isPresented: Bool
    let columnWidth: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The window is not attached yet during `makeNSView`.
        DispatchQueue.main.async { [weak view] in
            context.coordinator.apply(
                isPresented: isPresented,
                columnWidth: columnWidth,
                window: view?.window
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            context.coordinator.apply(
                isPresented: isPresented,
                columnWidth: columnWidth,
                window: nsView?.window
            )
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        private var widthBeforeOpen: CGFloat?
        private var lastPresented: Bool?

        func apply(isPresented: Bool, columnWidth: CGFloat, window: NSWindow?) {
            guard let window else { return }
            guard let lastPresented else {
                // First attach. Record the state without resizing, so restoring a
                // window that was already showing the sidebar does not jump.
                self.lastPresented = isPresented
                return
            }
            guard lastPresented != isPresented else { return }
            self.lastPresented = isPresented

            let frame = window.frame
            let screen = window.screen ?? NSScreen.main
            let visible = screen?.visibleFrame ?? frame

            let newWidth: CGFloat? = if isPresented {
                MailContextWindowGrowthPolicy.widthOnOpen(
                    currentWidth: frame.width,
                    columnWidth: columnWidth,
                    maximumWidth: visible.width
                )
            } else {
                MailContextWindowGrowthPolicy.widthOnClose(
                    currentWidth: frame.width,
                    widthBeforeOpen: widthBeforeOpen
                )
            }

            if isPresented {
                widthBeforeOpen = newWidth == nil ? nil : frame.width
            } else {
                widthBeforeOpen = nil
            }

            guard let newWidth else { return }

            let originX = MailContextWindowGrowthPolicy.originX(
                currentOriginX: frame.origin.x,
                newWidth: newWidth,
                screenMinX: visible.minX,
                screenMaxX: visible.maxX
            )
            let target = NSRect(
                x: originX, y: frame.origin.y, width: newWidth, height: frame.height
            )
            // The animator only runs for windows that are actually on screen,
            // and an animated resize is unwanted under Reduce Motion anyway —
            // resize instantly in both cases.
            if !window.isVisible || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                window.setFrame(target, display: true)
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = MailContextWindowGrowthPolicy.animationDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(target, display: true)
                }
            }
        }
    }
}
#endif
