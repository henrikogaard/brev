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

import AppKit
import SwiftUI

/// Pure encode/decode and validation for a persisted window frame.
enum WindowFramePersistence {
    /// Frames smaller than this are treated as absent — a defence against a
    /// truncated, zero, or legacy defaults value restoring a degenerate window.
    static let minimumSize = NSSize(width: 200, height: 150)

    static func encode(_ frame: NSRect) -> String {
        NSStringFromRect(frame)
    }

    /// Decodes a stored frame, or `nil` when the string is missing or the
    /// decoded frame is too small to be a real window.
    static func decode(_ string: String?) -> NSRect? {
        guard let string, !string.isEmpty else { return nil }
        let frame = NSRectFromString(string)
        guard frame.width >= minimumSize.width, frame.height >= minimumSize.height else {
            return nil
        }
        return frame
    }
}

/// Saves the host window's frame on user resize/move and restores it on the
/// next launch, keyed in `UserDefaults`.
///
/// `SwiftUI`'s `WindowGroup` sizes the window to its content on every launch
/// and does not reliably honour `NSWindow.setFrameAutosaveName`, so the frame
/// is persisted and re-applied here directly. Restore is applied *after*
/// SwiftUI's initial content sizing settles; saving stays suppressed until
/// then so neither the programmatic restore nor SwiftUI's launch-time sizing
/// can overwrite the stored frame with a default.
/// Holds `NotificationCenter` tokens and removes them when it is released.
/// Kept separate from the main-actor view so this cleanup runs in a plain
/// nonisolated `deinit`.
private final class WindowFrameObserverBag {
    private var tokens: [NSObjectProtocol] = []

    func add(_ token: NSObjectProtocol) {
        tokens.append(token)
    }

    deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
    }
}

private final class WindowFrameStoreView: NSView {
    private let defaultsKey: String
    private weak var boundWindow: NSWindow?
    private var isLive = false
    private let observerBag = WindowFrameObserverBag()

    init(defaultsKey: String) {
        self.defaultsKey = defaultsKey
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, window !== boundWindow else { return }
        boundWindow = window
        isLive = false
        restore(window)
        observe(window)
    }

    private func restore(_ window: NSWindow) {
        guard let frame = WindowFramePersistence.decode(
            UserDefaults.standard.string(forKey: defaultsKey)
        ) else {
            // First run for this key: let this session's changes start saving.
            markLiveSoon()
            return
        }
        // SwiftUI sizes the window around now; applying on the next runloop
        // tick lands after that, and a second pass a beat later wins if the
        // sizing arrives between the two.
        apply(frame, to: window, after: 0)
        apply(frame, to: window, after: 0.12)
        markLiveSoon()
    }

    private func apply(_ frame: NSRect, to window: NSWindow, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak window] in
            window?.setFrame(frame, display: true)
        }
    }

    /// Enables saving once the launch-time restore/sizing churn is over, so the
    /// initial programmatic frame changes are not mistaken for user intent.
    private func markLiveSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.isLive = true
        }
    }

    private func observe(_ window: NSWindow) {
        let center = NotificationCenter.default
        let names: [NSNotification.Name] = [
            NSWindow.didEndLiveResizeNotification,
            NSWindow.didMoveNotification,
            NSWindow.willCloseNotification,
        ]
        for name in names {
            observerBag.add(
                center.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                    MainActor.assumeIsolated {
                        guard let self, let window, self.isLive else { return }
                        UserDefaults.standard.set(
                            WindowFramePersistence.encode(window.frame),
                            forKey: self.defaultsKey
                        )
                    }
                }
            )
        }
    }
}

private struct WindowFrameStore: NSViewRepresentable {
    let defaultsKey: String

    func makeNSView(context: Context) -> WindowFrameStoreView {
        WindowFrameStoreView(defaultsKey: defaultsKey)
    }

    func updateNSView(_ nsView: WindowFrameStoreView, context: Context) {}
}

extension View {
    /// Restores the host window's size and position on launch, and persists the
    /// user's resizes and moves, under `name`.
    func brevRestoresWindowFrame(named name: String) -> some View {
        background(WindowFrameStore(defaultsKey: "brev.window.frame.\(name)"))
    }
}
