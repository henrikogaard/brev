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

    let isScheduled: Bool
    let isEnabled: Bool
    let hitTargetSize: CGFloat
    var usesToolbarStyle = false
    let action: () -> Void

    private static let selectedTintOpacity = 0.18

    var body: some View {
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

    /// Monochrome glass-matched label for the macOS window toolbar capsule so
    /// the unselected button never paints an opaque pill inside the glass bar.
    private var toolbarLabel: some View {
        Label(String(localized: "Later", bundle: .module), systemImage: "clock")
            .brevFont(.footnote)
            .foregroundStyle(
                isScheduled
                    ? theme.accentTextOnTint(opacity: Self.selectedTintOpacity).color
                    : theme.textSecondary.color
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
