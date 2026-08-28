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

import BrevThemes
import SwiftUI

/// Hairline colour for separators drawn on Brev's window surfaces.
///
/// A low-alpha wash of the theme's text colour rather than the opaque
/// `theme.separator` token — which is what `NSColor.separatorColor` is, and for
/// the same reason. Brev's panes are `NSVisualEffectView` surfaces with the
/// themed colour painted over them at `surfaceFillOpacity`, so with translucency
/// on the *surface* blends toward neutral system grey (at the shipped sidebar
/// default it is 90% material) while an opaque hairline stays at full strength.
/// The separator was the only element in the window not participating in
/// translucency, so no palette value could be correct: whatever hue the token
/// carried showed at full saturation against a surface that had lost its own.
///
/// Measured on a running build in the Tender theme: dividers came out
/// (46, 59, 67) on a (64, 64, 64) surface — blue 21 points above red — from a
/// `#293B44` token sitting on a `#282828` background that was never painted.
/// A wash resolves against whatever the surface actually became, so it stays
/// neutral on the material and picks up a tinted theme's hue when one is drawn.
///
/// See ADR-0053. `theme.separator` remains public and is still the token for
/// hairlines an author wants to place on an opaque themed surface.
public enum BrevSeparator {
    /// Rules between rows and sections.
    public static let interiorOpacity = 0.10
    /// Boundaries between panes, which carry more structure than a row rule.
    public static let edgeOpacity = 0.16

    /// The hairline colour for `theme`.
    /// - Parameters:
    ///   - theme: Active palette; the wash takes its text colour.
    ///   - opacity: Defaults to `interiorOpacity`; pass `edgeOpacity` for a
    ///     boundary between panes.
    public static func color(
        for theme: BrevTheme,
        opacity: Double = interiorOpacity
    ) -> Color {
        theme.textPrimary.color.opacity(opacity)
    }
}

/// Themed hairline divider. Adapts to the active palette without view-side
/// color literals, and to the window's translucency — see `BrevSeparator`.
public struct BrevDivider: View {
    @Environment(\.brevTheme) private var theme

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(BrevSeparator.color(for: theme))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
