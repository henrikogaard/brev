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

/// Theme-aware card surface for grouped settings and compact mail UI
/// panels.
public struct BrevCard<Content: View>: View {
    @Environment(\.brevTheme) private var theme

    private let style: BrevCardStyle
    private let padding: CGFloat
    private let content: Content

    public init(
        style: BrevCardStyle = .bordered,
        padding: CGFloat = BrevSpacing.lg,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .brevGlassSurface(
            role: .card,
            in: RoundedRectangle(cornerRadius: BrevRadius.md)
        )
        .overlay(border)
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        .contentShape(RoundedRectangle(cornerRadius: BrevRadius.md))
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .plain, .bordered:
            BrevWindowSurfaceBackground(role: .card)
        case .selected:
            theme.selection.color
        }
    }

    @ViewBuilder
    private var border: some View {
        switch style {
        case .plain:
            EmptyView()
        case .bordered:
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .stroke(theme.border.color, lineWidth: 1)
        case .selected:
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .stroke(theme.accent.color, lineWidth: 1)
        }
    }
}

/// Visual treatment for `BrevCard`.
public enum BrevCardStyle: Sendable, Hashable, CaseIterable {
    /// Filled surface without a stroke.
    case plain
    /// Filled surface with the standard border.
    case bordered
    /// Selected surface with selection fill and accent stroke.
    case selected
}
