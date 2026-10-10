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

/// Shared capsule chip styling for filter/toggle chips (inbox categories,
/// attachment filters, chat scopes). Selected state is an accent-tinted
/// capsule; unselected is a quiet secondary capsule. Distinct from the
/// filled-accent scope toggles, which are a stronger selection idiom.
public struct BrevChipStyle: ViewModifier {
    @Environment(\.brevTheme) private var theme
    @ScaledMetric(relativeTo: .caption) private var scaledHitHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var verticalPadding: CGFloat = BrevSpacing.xxs

    private static let selectedTintOpacity = 0.18

    private let isSelected: Bool

    /// Creates chip styling for the supplied selection state.
    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    /// Applies the shared selected or unselected capsule treatment.
    public func body(content: Content) -> some View {
        content
            // Accent text on its own 18% tint failed 4.5:1 in 15 built-in
            // themes; `accentTextOnTint` keeps the accent where it passes and
            // otherwise darkens (or lightens) it just enough.
            .foregroundStyle(
                isSelected
                    ? theme.accentTextOnTint(opacity: Self.selectedTintOpacity).color
                    : theme.textSecondary.color
            )
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, verticalPadding)
            .background(
                Capsule().fill(
                    isSelected ? theme.accent.color.opacity(Self.selectedTintOpacity) : theme.bgSecondary.color
                )
            )
            .overlay {
                if isSelected {
                    Capsule().stroke(theme.accent.color.opacity(0.55), lineWidth: 1)
                }
            }
            .modifier(ChipHitArea(scaledHeight: scaledHitHeight))
    }
}

public extension View {
    /// Applies the shared capsule chip styling for filter/toggle chips.
    func brevChip(selected: Bool) -> some View {
        modifier(BrevChipStyle(isSelected: selected))
    }
}

/// The capsule stays compact; on iOS only the tappable slot grows to the
/// 44 pt floor and scales with Dynamic Type. macOS keeps the compact layout.
private struct ChipHitArea: ViewModifier {
    let scaledHeight: CGFloat

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .frame(minHeight: BrevHitTarget.resolved(scaled: scaledHeight))
            .contentShape(Rectangle())
        #else
        content
        #endif
    }
}
