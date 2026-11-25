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
import BrevAI
@testable import BrevSettings
import BrevThemes
import SwiftUI
import Testing
import UIKit

/// Regression coverage for #362: at Dynamic Type `accessibility-extra-large`
/// (`AXL`), `PrivacyOnboardingSheet` must scroll header, cards, and footer
/// actions without horizontal clipping or collapsing the scrollable height.
@Suite("Privacy onboarding sheet iOS AXL layout", .serialized)
@MainActor
struct PrivacyOnboardingAXLLayoutIOSTests {
    @Test(
        "PrivacyOnboardingSheet stays within phone width with generous scroll area at AXL (#362)",
        arguments: [PrivacyOnboardingMode.firstRun, .reviewFromSettings],
        [CGSize(width: 393, height: 852), CGSize(width: 320, height: 852)]
    )
    func staysWithinPhoneBoundsAtAXL(mode: PrivacyOnboardingMode, viewport: CGSize) throws {
        let suite = "PrivacyOnboardingAXL-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let view = PrivacyOnboardingSheet(
            mode: mode,
            settingsStore: SettingsPersistenceStore(defaults: defaults),
            appleIntelligenceAvailability: .available,
            onAvatarPreferencesChanged: { _ in }
        )
        .brevTheme(.brevMonoLight)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .accessibility2)
        .defaultAppStorage(defaults)

        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: viewport))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        host.view.traitOverrides.preferredContentSizeCategory = .accessibilityExtraLarge
        host.view.frame = CGRect(origin: .zero, size: viewport)
        host.view.layoutIfNeeded()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        window.layoutIfNeeded()

        let allViews = descendants(of: host.view)
        let scrollViews = allViews.compactMap { $0 as? UIScrollView }
        let mainScroll = try #require(scrollViews.max(by: { $0.bounds.height < $1.bounds.height }))
        let scrollFrame = mainScroll.convert(mainScroll.bounds, to: window)
        #expect(
            scrollFrame.height >= viewport.height * 0.6,
            "Scroll area should fill most of the sheet at AXL: \(scrollFrame) in \(viewport)"
        )

        let horizontalOffenders = allViews.filter { subview in
            guard !subview.isHidden, subview.alpha > 0 else { return false }
            let frame = subview.convert(subview.bounds, to: window)
            guard frame.width > 0, frame.height > 0 else { return false }
            return frame.minX < -0.5 || frame.maxX > viewport.width + 0.5
        }
        for offender in horizontalOffenders {
            let frame = offender.convert(offender.bounds, to: window)
            print("AXL OVERFLOW \(type(of: offender)) \(frame)")
        }
        #expect(horizontalOffenders.isEmpty)
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
#endif
