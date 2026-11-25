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
    struct LayoutCase: Sendable, CustomTestStringConvertible {
        let label: String
        let mode: PrivacyOnboardingMode
        let viewport: CGSize
        let dynamicTypeSize: DynamicTypeSize
        let contentSizeCategory: UIContentSizeCategory

        var testDescription: String { label }

        static let all: [Self] = {
            let modes: [(String, PrivacyOnboardingMode)] = [
                ("firstRun", .firstRun),
                ("reviewFromSettings", .reviewFromSettings)
            ]
            let viewports: [(String, CGSize)] = [
                ("393x852", CGSize(width: 393, height: 852)),
                ("320x852", CGSize(width: 320, height: 852))
            ]
            let sizes: [(String, DynamicTypeSize, UIContentSizeCategory)] = [
                ("AXL(.accessibility3)", .accessibility3, .accessibilityExtraLarge),
                ("AX5(.accessibility5)", .accessibility5, .accessibilityExtraExtraExtraLarge)
            ]
            return modes.flatMap { modeName, mode in
                viewports.flatMap { viewportName, viewport in
                    sizes.map { sizeName, dynamicTypeSize, category in
                        Self(
                            label: "\(modeName) \(viewportName) \(sizeName)",
                            mode: mode,
                            viewport: viewport,
                            dynamicTypeSize: dynamicTypeSize,
                            contentSizeCategory: category
                        )
                    }
                }
            }
        }()
    }

    @Test(
        "PrivacyOnboardingSheet stays within phone width with generous scroll area at AXL and AX5 (#362)",
        arguments: LayoutCase.all
    )
    func staysWithinPhoneBoundsAtAXL(_ layoutCase: LayoutCase) throws {
        let suite = "PrivacyOnboardingAXL-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let view = PrivacyOnboardingSheet(
            mode: layoutCase.mode,
            settingsStore: SettingsPersistenceStore(defaults: defaults),
            appleIntelligenceAvailability: .available,
            onAvatarPreferencesChanged: { _ in }
        )
        .brevTheme(.brevMonoLight)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, layoutCase.dynamicTypeSize)
        .defaultAppStorage(defaults)

        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: layoutCase.viewport))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        host.view.traitOverrides.preferredContentSizeCategory = layoutCase.contentSizeCategory
        host.view.frame = CGRect(origin: .zero, size: layoutCase.viewport)
        host.view.layoutIfNeeded()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        window.layoutIfNeeded()

        let allViews = descendants(of: host.view)
        let scrollViews = allViews.compactMap { $0 as? UIScrollView }
        let mainScroll = try #require(scrollViews.max(by: { $0.bounds.height < $1.bounds.height }))
        let scrollFrame = mainScroll.convert(mainScroll.bounds, to: window)
        #expect(
            scrollFrame.height >= layoutCase.viewport.height * 0.6,
            "Scroll area should fill most of the sheet at \(layoutCase.label): \(scrollFrame) in \(layoutCase.viewport)"
        )

        let horizontalOffenders = allViews.filter { subview in
            guard !subview.isHidden, subview.alpha > 0 else { return false }
            let frame = subview.convert(subview.bounds, to: window)
            guard frame.width > 0, frame.height > 0 else { return false }
            return frame.minX < -0.5 || frame.maxX > layoutCase.viewport.width + 0.5
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
