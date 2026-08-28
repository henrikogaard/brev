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
import OSLog
#endif
import SwiftUI

extension View {
    /// Mounts the scroll edge blur band at the top of one split-view pane.
    ///
    /// Per pane, not once across the whole split view: a single full-width
    /// band backdrop-samples the split divider along with the content, which
    /// blurred away the divider's top `bandHeight` points. Scoped to a pane,
    /// the backdrop samples only that pane's rows and the divider pixel
    /// column between panes stays crisp. No-op off macOS.
    @ViewBuilder
    func brevMailPaneScrollEdgeBlur() -> some View {
        #if os(macOS)
        overlay(alignment: .top) {
            MailWindowScrollEdgeBlur()
                .frame(height: MailScrollEdgeBlurView.bandHeight)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .top)
        }
        #else
        self
        #endif
    }
}

#if os(macOS)
/// Mail's soft scroll edge: rows dissolve into a progressive blur as they
/// scroll under the toolbar band, instead of being cut off at a hard line.
///
/// Blur only — no material, no wash, no lens, no hover behaviour. The band is
/// a within-window `NSVisualEffectView` reduced to its raw backdrop: the
/// material's tint sublayers are hidden and the backdrop's filter chain is cut
/// down to the gaussian blur alone, so what remains is a blurred copy of
/// exactly the content beneath, at the content's own colours. A gradient
/// alpha mask crossfades that copy into the live content by the bottom of the
/// band, which is luminance-neutral because a blurred copy has the same
/// average brightness as its source. If a future macOS reshapes the
/// material's layer tree, the reduction degrades to hiding the whole strip —
/// never to showing the stock material.
///
/// Approaches that do NOT deliver this, verified on the running build so
/// nobody retries them: Liquid Glass (`glassEffect(.clear)`) blurs but adds
/// the material's lens and sheen, which reads as a brightness gradient over
/// themed panes; the macOS 26.1 titlebar scroll edge effect hover-gates and
/// colour-washes; re-rendering a `cacheDisplay` snapshot through
/// `CIMaskedVariableBlur` cannot match the screen because the snapshot misses
/// the window-server vibrancy under translucent panes; AppKit views injected
/// as siblings into `window.contentView` never composite at all; and SwiftUI
/// `scrollEdgeEffectStyle(.soft)` never engages with this window's chrome.
struct MailWindowScrollEdgeBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> MailScrollEdgeBlurView {
        MailScrollEdgeBlurView()
    }

    func updateNSView(_ nsView: MailScrollEdgeBlurView, context: Context) {}
}

/// Budget for the self-scheduled reduction retries a single trigger may
/// spend while waiting for the material's layer tree to materialize.
struct MailScrollEdgeBlurRetryState {
    /// Total reduction attempts allowed per trigger, the first one included.
    static let maxAttempts = 5

    private var attemptsMade = 0

    /// Records a failed attempt; returns whether another retry is allowed.
    mutating func noteAttemptFailed() -> Bool {
        attemptsMade += 1
        return attemptsMade < Self.maxAttempts
    }

    mutating func reset() {
        attemptsMade = 0
    }
}

/// The blurred band: a tint-stripped within-window backdrop under a gradient
/// alpha mask.
final class MailScrollEdgeBlurView: NSView {
    /// Height of the band content visibly scrolls under.
    static let bandHeight: CGFloat = 52
    /// Fraction of the band, from the top, at full strength before the fade.
    private static let fadeStart: CGFloat = 0.35
    /// Gaussian radius. Small on purpose: a large radius drags distant bright
    /// rows into the band, which reads as a glow.
    private static let blurRadius: CGFloat = 10

    private let effectView = NSVisualEffectView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        effectView.blendingMode = .withinWindow
        effectView.material = .fullScreenUI
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        effectView.frame = bounds
        addSubview(effectView)

        // A CALayer mask on an ancestor of a backdrop layer is ignored, so
        // the fade goes through the effect view's own maskImage, which the
        // material machinery applies to the backdrop itself. The image is
        // resizable with fixed cap insets so AppKit does not re-request it on
        // every resize.
        effectView.maskImage = Self.fadeMaskImage()
    }

    /// A 1pt-wide gradient strip: opaque from the top through `fadeStart`,
    /// fading to clear at the bottom of the band.
    private static func fadeMaskImage() -> NSImage {
        let size = NSSize(width: 1, height: bandHeight)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let gradient = NSGradient(
                colorsAndLocations:
                (.black, 0),
                (.black, fadeStart),
                (.black.withAlphaComponent(0), 1)
            ) else { return false }
            gradient.draw(in: rect, angle: 90)
            return true
        }
        image.resizingMode = .stretch
        return image
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Purely decorative — clicks belong to the content underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleReduction()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Appearance changes rebuild the material's layers; re-reduce.
        scheduleReduction()
    }

    override func layout() {
        super.layout()
        scheduleReduction()
    }

    private static let logger = Logger(
        subsystem: "eu.brevmail.brev",
        category: "ScrollEdgeBlur"
    )
    /// Delay between self-scheduled reduction retries while the material's
    /// layer tree is still building.
    private static let retryDelay: DispatchTimeInterval = .milliseconds(100)

    private var retryState = MailScrollEdgeBlurRetryState()
    private var hasLoggedActiveOutcome = false

    /// The material builds its layer tree lazily, after it joins a window, so
    /// reduction runs on the next turn — and is cheap enough to re-run on
    /// every trigger.
    private func scheduleReduction() {
        guard window != nil else { return }
        retryState.reset()
        DispatchQueue.main.async { [weak self] in
            self?.reduceToBareBackdrop()
        }
    }

    /// Hides every part of the material except its backdrop, and cuts the
    /// backdrop's filters down to the gaussian blur at the design radius.
    /// The layer names here are Core Animation internals; if they ever stop
    /// matching, the strip hides itself rather than show the stock material.
    ///
    /// A missing backdrop is retried on a short ladder before giving up:
    /// under optimized builds the material can materialize its layers after
    /// the first post-join turn, and without an external trigger a one-shot
    /// check would hide the band permanently. Exhausting the ladder logs the
    /// fail-closed outcome so a silent visual regression stays diagnosable.
    private func reduceToBareBackdrop() {
        guard window != nil else { return }
        guard let root = effectView.layer else {
            failReductionAttempt(reason: "effect view has no layer")
            return
        }
        var foundBackdrop = false
        Self.walk(root) { layer in
            let isBackdrop = String(describing: type(of: layer)).contains("Backdrop")
            if isBackdrop {
                foundBackdrop = true
                if let filters = layer.filters {
                    let gaussian = filters.filter {
                        String(describing: $0).contains("gaussianBlur")
                    }
                    if gaussian.isEmpty {
                        foundBackdrop = false
                    } else {
                        layer.filters = gaussian
                        layer.setValue(
                            Self.blurRadius,
                            forKeyPath: "filters.gaussianBlur.inputRadius"
                        )
                    }
                }
            } else if (layer.sublayers ?? []).isEmpty, layer !== root {
                layer.isHidden = true
            }
            return !isBackdrop
        }
        if foundBackdrop {
            retryState.reset()
            isHidden = false
            // One notice per band instance: reading "active" (or the
            // fail-closed error) from the unified log is the only way to
            // tell a working band from a never-mounted one on a release
            // install, where nothing else records that this decorative
            // strip resolved.
            if !hasLoggedActiveOutcome {
                hasLoggedActiveOutcome = true
                // Captured outside the log macro's autoclosure: the release
                // compiler requires explicit self there, and SwiftFormat
                // strips the explicit self right back out.
                let paneWidth = bounds.width
                Self.logger.notice(
                    "Scroll edge blur active in \(paneWidth, format: .fixed(precision: 0), privacy: .public)pt pane"
                )
            }
        } else {
            failReductionAttempt(reason: "no backdrop layer with a gaussian blur filter")
        }
    }

    /// Fail closed for this attempt, retry while the ladder has budget, and
    /// log once when it runs out.
    private func failReductionAttempt(reason: StaticString) {
        isHidden = true
        if retryState.noteAttemptFailed() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay) { [weak self] in
                self?.reduceToBareBackdrop()
            }
        } else {
            Self.logger.error(
                "Scroll edge blur disabled after \(MailScrollEdgeBlurRetryState.maxAttempts) attempts: \(reason)"
            )
        }
    }

    /// Depth-first walk; the closure returns whether to descend further.
    private static func walk(_ layer: CALayer, _ visit: (CALayer) -> Bool) {
        guard visit(layer) else { return }
        for sub in layer.sublayers ?? [] {
            walk(sub, visit)
        }
    }
}
#endif
