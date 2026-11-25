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

#if os(iOS)
import BrevBackend
@testable import BrevMail
import SwiftUI
import Testing
import UIKit

/// Regression coverage for #49: at the largest Dynamic Type sizes the
/// compose sheet used to lay out wider than the phone viewport — the
/// recipient/subject text adaptors report their intrinsic text width as
/// their ideal width, and sheet presentations size content to that ideal.
/// The test hosts the real view at ideal (unspecified) width with
/// accessibility-size traits and asserts no laid-out subview exceeds the
/// narrowest supported phone width.
@Suite("Compose accessibility bounds", .serialized)
@MainActor
struct ComposeAccessibilityBoundsTests {
    /// Narrowest supported phone viewport (iPhone SE class).
    private static let narrowestPhoneWidth: CGFloat = 320

    @Test("compose content stays inside the narrowest phone width at accessibility sizes")
    func idealWidthStaysInsidePhone() {
        let backend = MockBackend()
        // .fixedSize() forces ideal sizing — the same width the sheet
        // presentation derives its frame from.
        let view = ComposeView(backend: backend, from: backend.account)
            .environment(\.horizontalSizeClass, .compact)
            .brevTheme(.brevMonoLight)
            .htmlBodyRenderTarget(.staticSnapshot)
            .fixedSize()
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 2000, height: 1200))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.traitOverrides.preferredContentSizeCategory =
            .accessibilityExtraExtraExtraLarge
        host.view.layoutIfNeeded()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        window.layoutIfNeeded()

        let offenders = descendants(of: host.view).filter { subview in
            guard !subview.isHidden, subview.alpha > 0 else { return false }
            return subview.convert(subview.bounds, to: window).width
                > Self.narrowestPhoneWidth + 0.5
        }
        for offender in offenders {
            let frame = offender.convert(offender.bounds, to: window)
            print("OVERFLOW \(type(of: offender)) \(frame)")
        }
        #expect(offenders.isEmpty)
    }

    @Test(
        "landscape compose keeps top bar, scrollable body, and utility bar inside a keyboard-constrained viewport (#362)",
        arguments: [CGSize(width: 852, height: 393), CGSize(width: 852, height: 185)]
    )
    func landscapeComposeKeepsChromeAndScrollViewWithinBounds(_ viewport: CGSize) throws {
        let backend = MockBackend()
        var controlFrames: [ComposeChromeControlKey: CGRect] = [:]
        let view = ComposeView(
            backend: backend,
            from: backend.account,
            prefill: ComposePrefill(
                to: ["qa@example.test"],
                subject: "iOS Rich QA",
                bodyText: "Testing rich editor"
            )
        )
        .frame(width: viewport.width, height: viewport.height)
        .environment(\.horizontalSizeClass, .compact)
        .environment(\.verticalSizeClass, .compact)
        .brevTheme(.brevMonoLight)
        .htmlBodyRenderTarget(.staticSnapshot)
        .onPreferenceChange(ComposeChromeControlFramesKey.self) { frames in
            controlFrames = frames
        }

        let host = UIHostingController(rootView: view)
        // Host inside a window taller than the simulator's portrait safe-area
        // insets so `ComposeView` receives the exact `viewport` height (full
        // landscape `393 pt` and keyboard-constrained `185 pt`).
        let windowSize = CGSize(width: viewport.width, height: max(viewport.height + 160, 600))
        let window = UIWindow(frame: CGRect(origin: .zero, size: windowSize))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        host.view.frame = CGRect(origin: .zero, size: windowSize)
        host.view.layoutIfNeeded()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        window.layoutIfNeeded()

        let allViews = descendants(of: host.view)
        let scrollViews = allViews.compactMap { $0 as? UIScrollView }.filter { !($0 is UITextView) }
        let scrollView = try #require(
            scrollViews.first,
            "Landscape compose should wrap header fields and body in a ScrollView"
        )
        #expect(
            scrollView.keyboardDismissMode == .interactive
                || scrollView.keyboardDismissMode == .interactiveWithAccessory,
            "Landscape compose ScrollView should dismiss the keyboard interactively (got \(scrollView.keyboardDismissMode.rawValue))"
        )

        let scrollFrame = try #require(
            controlFrames[.scrollArea],
            "Expected scrollable body region frame; captured: \(controlFrames)"
        )
        #expect(scrollFrame.minY >= 43.5, "Top navigation bar should remain pinned above ScrollView: \(scrollFrame)")
        #expect(scrollFrame.height >= 90, "ScrollView should leave generous scrollable height: \(scrollFrame)")
        #expect(
            scrollFrame.maxY <= viewport.height - 43.5,
            "Bottom utility bar should remain pinned below ScrollView: \(scrollFrame) in \(viewport)"
        )
        if viewport.height <= 200 {
            #expect(
                scrollView.contentSize.height > scrollFrame.height,
                "ScrollView content (\(scrollView.contentSize.height)) should exceed compact viewport (\(scrollFrame.height)) so header fields scroll out of the way to reach the body"
            )
        }

        // Verify the actual rendered top-bar and bottom utility controls sit
        // inside the visible viewport bounds with tappable dimensions (#366).
        for key in [ComposeChromeControlKey.cancel, .send] {
            let frame = try #require(
                controlFrames[key],
                "Expected top toolbar control \(key) frame; captured: \(controlFrames)"
            )
            #expect(frame.width >= 44 && frame.height >= 44, "Top control \(key) below 44pt target: \(frame)")
            #expect(frame.minY >= -0.5 && frame.maxY <= scrollFrame.minY + 1.5, "Top control \(key) clipped: \(frame)")
            #expect(
                frame.minX >= -0.5 && frame.maxX <= viewport.width + 0.5,
                "Top control \(key) horizontal overflow: \(frame)"
            )
        }

        for key in [ComposeChromeControlKey.attach, .format, .moreActions] {
            let frame = try #require(
                controlFrames[key],
                "Expected bottom utility control \(key) frame; captured: \(controlFrames)"
            )
            #expect(frame.width >= 44 && frame.height >= 44, "Bottom control \(key) below 44pt target: \(frame)")
            #expect(
                frame.minY >= scrollFrame.maxY - 1.5 && frame.maxY <= viewport.height + 0.5,
                "Bottom control \(key) clipped: \(frame)"
            )
            #expect(
                frame.minX >= -0.5 && frame.maxX <= viewport.width + 0.5,
                "Bottom control \(key) horizontal overflow: \(frame)"
            )
        }

        let horizontalOffenders = allViews.filter { subview in
            guard !subview.isHidden, subview.alpha > 0 else { return false }
            let frame = subview.convert(subview.bounds, to: window)
            guard frame.width > 0, frame.height > 0 else { return false }
            return frame.minX < -0.5 || frame.maxX > viewport.width + 0.5
        }
        #expect(horizontalOffenders.isEmpty)
    }

    @Test("rotating between portrait and landscape preserves live rich body editor identity and formatting (#366)")
    func landscapeRotationPreservesRichBodyEditorIdentityAndFormatting() throws {
        let backend = MockBackend()
        let model = ComposeRotationHarnessModel(verticalSizeClass: .regular)
        let host = UIHostingController(rootView: ComposeRotationHarnessView(backend: backend, model: model))
        let portraitSize = CGSize(width: 393, height: 852)
        let landscapeSize = CGSize(width: 852, height: 393)

        let window = UIWindow(frame: CGRect(origin: .zero, size: portraitSize))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        host.view.frame = CGRect(origin: .zero, size: portraitSize)
        host.view.layoutIfNeeded()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        window.layoutIfNeeded()

        let initialTextView = try #require(
            descendants(of: host.view).compactMap { $0 as? ComposeBodyTextView }.first,
            "Expected live ComposeBodyTextView in portrait compose"
        )
        let initialIdentity = ObjectIdentifier(initialTextView)

        // Apply live bold formatting inside the rich UITextView session.
        let boldRange = NSRange(location: 0, length: 7) // "Testing"
        initialTextView.selectedRange = boldRange
        let richTarget = try #require(
            initialTextView.delegate as? ComposeIOSRichTextTarget,
            "Expected ComposeBodyTextView delegate to conform to ComposeIOSRichTextTarget"
        )
        richTarget.toggleBold()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let fontBeforeRotation = try #require(
            initialTextView.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        )
        #expect(fontBeforeRotation.fontDescriptor.symbolicTraits.contains(.traitBold))

        // Rotate portrait -> landscape (.regular -> .compact).
        model.verticalSizeClass = .compact
        window.frame = CGRect(origin: .zero, size: landscapeSize)
        host.view.frame = CGRect(origin: .zero, size: landscapeSize)
        host.view.layoutIfNeeded()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        window.layoutIfNeeded()

        let landscapeTextView = try #require(
            descendants(of: host.view).compactMap { $0 as? ComposeBodyTextView }.first
        )
        #expect(
            ObjectIdentifier(landscapeTextView) == initialIdentity,
            "Rotating to landscape must not recreate ComposeBodyTextView"
        )
        #expect(landscapeTextView.text == "Testing rich editor")
        let fontInLandscape = try #require(
            landscapeTextView.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        )
        #expect(fontInLandscape.fontDescriptor.symbolicTraits.contains(.traitBold))

        // Rotate landscape -> portrait (.compact -> .regular).
        model.verticalSizeClass = .regular
        window.frame = CGRect(origin: .zero, size: portraitSize)
        host.view.frame = CGRect(origin: .zero, size: portraitSize)
        host.view.layoutIfNeeded()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        window.layoutIfNeeded()

        let portraitTextView = try #require(
            descendants(of: host.view).compactMap { $0 as? ComposeBodyTextView }.first
        )
        #expect(
            ObjectIdentifier(portraitTextView) == initialIdentity,
            "Rotating back to portrait must not recreate ComposeBodyTextView"
        )
        #expect(portraitTextView.text == "Testing rich editor")
        let fontBackInPortrait = try #require(
            portraitTextView.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        )
        #expect(fontBackInPortrait.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    @Test("regular portrait compose keeps nested preview ScrollViews scrollable (#366)")
    func portraitComposePreservesNestedPreviewScrolling() throws {
        let backend = MockBackend()
        let longGeneratedText = (1 ... 30)
            .map { "Line \($0): Follow-up summary for the quarterly review meeting." }
            .joined(separator: "\n")
        let request = ComposeAIShortcutRequest(
            action: .formal,
            bodyText: "Quick note",
            target: .wholeDraft
        )
        let preview = ComposeAIPreviewState(
            id: 1,
            action: .shortcut(.formal, scope: .wholeDraft),
            request: request,
            providerLabel: "On-device",
            phase: .loading
        ).succeeded(with: longGeneratedText)

        let viewport = CGSize(width: 393, height: 852)
        let view = ComposeView(
            backend: backend,
            from: backend.account,
            prefill: ComposePrefill(
                to: ["qa@example.test"],
                subject: "Portrait preview scroll check",
                bodyText: "Quick note"
            )
        )
        .initialAIPreview(preview)
        .environment(\.horizontalSizeClass, .compact)
        .environment(\.verticalSizeClass, .regular)
        .brevTheme(.brevMonoLight)
        .htmlBodyRenderTarget(.staticSnapshot)

        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: viewport))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        host.view.frame = CGRect(origin: .zero, size: viewport)
        host.view.layoutIfNeeded()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        window.layoutIfNeeded()

        let scrollViews = descendants(of: host.view)
            .compactMap { $0 as? UIScrollView }
            .filter { !($0 is UITextView) }
        let outerScrollView = try #require(scrollViews.first, "Expected outer compose UIScrollView")
        let nestedPreviewScrollView = try #require(
            scrollViews.first { $0 !== outerScrollView && $0.isDescendant(of: outerScrollView) },
            "Expected nested AI preview UIScrollView inside portrait compose"
        )

        #expect(
            nestedPreviewScrollView.isScrollEnabled,
            "Nested preview ScrollView must remain scrollable in regular portrait compose"
        )
        #expect(
            nestedPreviewScrollView.contentSize.height > nestedPreviewScrollView.bounds.height,
            "Long AI preview content (\(nestedPreviewScrollView.contentSize.height)) should exceed capped height (\(nestedPreviewScrollView.bounds.height)) so it scrolls"
        )
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

@MainActor
private final class ComposeRotationHarnessModel: ObservableObject {
    @Published var verticalSizeClass: UserInterfaceSizeClass

    init(verticalSizeClass: UserInterfaceSizeClass) {
        self.verticalSizeClass = verticalSizeClass
    }
}

private struct ComposeRotationHarnessView: View {
    let backend: MockBackend
    @ObservedObject var model: ComposeRotationHarnessModel

    var body: some View {
        ComposeView(
            backend: backend,
            from: backend.account,
            prefill: ComposePrefill(
                to: ["qa@example.test"],
                subject: "iOS Rich QA",
                bodyText: "Testing rich editor"
            )
        )
        .environment(\.horizontalSizeClass, .compact)
        .environment(\.verticalSizeClass, model.verticalSizeClass)
        .brevTheme(.brevMonoLight)
        .htmlBodyRenderTarget(.staticSnapshot)
    }
}
#endif
