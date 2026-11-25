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

/// Primary compose "Later" action chip placed adjacent to Send (#297).
struct ComposeLaterButtonView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let isScheduled: Bool
    let isEnabled: Bool
    let hitTargetSize: CGFloat
    var usesToolbarStyle = false
    let action: () -> Void

    private static let selectedTintOpacity = 0.18

    var body: some View {
        let usesGlass = !usesToolbarStyle && ComposeLiquidGlass.isEnabled(reduceTransparency: reduceTransparency)
        return Group {
            if usesGlass {
                glassPillButton
            } else {
                Button(action: action) {
                    if usesToolbarStyle {
                        toolbarLabel
                    } else {
                        Label(String(localized: "Later", bundle: .module), systemImage: "clock")
                            .brevFont(.footnote)
                            .brevChip(selected: isScheduled)
                            .frame(minHeight: hitTargetSize)
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(!isEnabled)
        .opacity(usesToolbarStyle && !isEnabled ? 0.45 : 1)
        .accessibilityLabel(
            isScheduled
                ? String(localized: "Edit scheduled send", bundle: .module)
                : String(localized: "Later", bundle: .module)
        )
        .accessibilityAddTraits(isScheduled ? .isSelected : [])
        .help(
            isScheduled
                ? String(localized: "Edit scheduled send", bundle: .module)
                : ComposeToolbarAction.scheduleSend.accessibilityLabel
        )
    }

    private var glassPillButton: some View {
        let pillFill = isScheduled
            ? theme.accent.color.opacity(Self.selectedTintOpacity)
            : theme.bgSecondary.color.opacity(isEnabled ? 0.48 : 0.30)
        let pillStroke = isScheduled
            ? theme.accent.color.opacity(0.60)
            : theme.border.color.opacity(isEnabled ? 0.50 : 0.30)
        return ComposeLiquidGlass.Container(spacing: BrevSpacing.xs) {
            Button(action: action) {
                Label(String(localized: "Later", bundle: .module), systemImage: "clock")
                    .brevFont(.footnote)
                    .foregroundStyle(glassForegroundColor)
                    .padding(.horizontal, BrevSpacing.sm)
                    .padding(.vertical, BrevSpacing.xs)
                    .background(Capsule().fill(pillFill))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(pillStroke, lineWidth: isScheduled ? 1 : 0.75))
                    .composeGlassCapsule(interactive: isEnabled, clear: isScheduled)
                    .frame(minHeight: hitTargetSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var glassForegroundColor: Color {
        if !isEnabled {
            return theme.textTertiary.color
        }
        if isScheduled {
            return theme.accentTextOnTint(opacity: Self.selectedTintOpacity).color
        }
        return theme.textPrimary.color
    }

    /// Monochrome glass-matched label for the macOS window toolbar capsule so
    /// the unselected button never paints an opaque pill inside the glass bar.
    private var toolbarLabel: some View {
        Label(String(localized: "Later", bundle: .module), systemImage: "clock")
            .brevFont(.footnote)
            .foregroundStyle(
                isScheduled
                    ? theme.accentTextOnTint(opacity: Self.selectedTintOpacity).color
                    : (ComposeLiquidGlass.isEnabled(reduceTransparency: reduceTransparency)
                        ? theme.textPrimary.color
                        : theme.textSecondary.color)
            )
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, BrevSpacing.xxs)
            .background(
                Capsule().fill(
                    isScheduled
                        ? theme.accent.color.opacity(Self.selectedTintOpacity)
                        : Color.clear
                )
            )
            .overlay {
                if isScheduled {
                    Capsule().strokeBorder(theme.accent.color.opacity(0.55), lineWidth: 1)
                }
            }
            .frame(minHeight: hitTargetSize)
            .contentShape(Rectangle())
    }
}
