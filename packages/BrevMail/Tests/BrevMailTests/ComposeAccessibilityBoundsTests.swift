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

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
#endif
