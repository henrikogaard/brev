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

import BrevDesign
import BrevThemes
import SwiftUI
import Testing
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite("BrevLiquidGlass")
struct BrevLiquidGlassTests {
    @Test("policy enables native Liquid Glass only on OS 26+ without Reduce Transparency")
    func policyMatrix() {
        #expect(BrevLiquidGlassPolicy.usesNativeLiquidGlass(
            reduceTransparency: false,
            isAvailableOnOS: true
        ))
        #expect(!BrevLiquidGlassPolicy.usesNativeLiquidGlass(
            reduceTransparency: true,
            isAvailableOnOS: true
        ))
        #expect(!BrevLiquidGlassPolicy.usesNativeLiquidGlass(
            reduceTransparency: false,
            isAvailableOnOS: false
        ))
        #expect(!BrevLiquidGlassPolicy.usesNativeLiquidGlass(
            reduceTransparency: true,
            isAvailableOnOS: false
        ))
    }

    @Test("policy default availability matches runtime OS support")
    func runtimeAvailabilityMatchesOS() {
        let expected: Bool = {
            #if compiler(>=6.2)
            if #available(macOS 26.0, iOS 26.0, *) {
                return true
            }
            #endif
            return false
        }()
        #expect(BrevLiquidGlassPolicy.isAvailableOnCurrentOS == expected)
        #expect(BrevLiquidGlassPolicy.usesNativeLiquidGlass(reduceTransparency: false) == expected)
        #expect(!BrevLiquidGlassPolicy.usesNativeLiquidGlass(reduceTransparency: true))
    }

    @Test(
        "glass container, surfaces, capsules, and button styles lay out cleanly in light and dark themes",
        arguments: [false, true]
    )
    @MainActor
    func primitivesLayoutCleanly(dark: Bool) {
        let theme = dark ? BrevTheme.brevMonoDark : .brevMonoLight
        let sample = BrevGlassContainer(spacing: BrevSpacing.sm) {
            VStack(spacing: BrevSpacing.sm) {
                Text(verbatim: "Glass surface")
                    .padding(BrevSpacing.md)
                    .brevGlassSurface(cornerRadius: 18, interactive: true)

                HStack(spacing: BrevSpacing.sm) {
                    Text(verbatim: "Capsule")
                        .padding(.horizontal, BrevSpacing.md)
                        .padding(.vertical, BrevSpacing.xs)
                        .brevGlassCapsule(interactive: true, tint: theme.accent.color)

                    Button(action: {}) {
                        Image(systemName: "arrow.up")
                    }
                    .brevGlassButtonStyle(prominent: true, tint: theme.accent.color)

                    Button(action: {}) {
                        Image(systemName: "xmark")
                    }
                    .brevGlassButtonStyle(prominent: false)
                }
            }
            .padding(BrevSpacing.md)
        }
        .brevTheme(theme)
        .environment(\.colorScheme, dark ? .dark : .light)

        #if os(macOS)
        let host = NSHostingController(rootView: sample)
        host.view.frame = NSRect(x: 0, y: 0, width: 320, height: 160)
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.fittingSize.width > 0)
        #expect(host.view.fittingSize.height > 0)
        #elseif canImport(UIKit)
        let host = UIHostingController(rootView: sample)
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 160)
        host.view.layoutIfNeeded()
        #expect(host.sizeThatFits(in: CGSize(width: 320, height: 160)).height > 0)
        #endif
    }
}
