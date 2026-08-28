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

/// Rendering style for HTML mail bodies.
enum HTMLBodyRenderingMode: Equatable {
    case original
    case dark

    static func `default`(for theme: BrevTheme) -> HTMLBodyRenderingMode {
        theme.mode == .dark ? .dark : .original
    }

    var toggled: HTMLBodyRenderingMode {
        switch self {
        case .original:
            return .dark
        case .dark:
            return .original
        }
    }

    /// Short label for the toggle button — names the mode it switches *to*.
    /// The leading sun/moon icon carries the rest of the meaning.
    var toggleTitle: String {
        switch self {
        case .original:
            return String(localized: "Dark", bundle: .module)
        case .dark:
            return String(localized: "Original", bundle: .module)
        }
    }

    /// Spelled-out label for VoiceOver (the visible title is intentionally
    /// terse). Avoids the old "white mode" wording, which wrongly implied the
    /// original styling is always light.
    var toggleAccessibilityLabel: String {
        switch self {
        case .original:
            return String(localized: "Switch to dark reading mode", bundle: .module)
        case .dark:
            return String(localized: "Switch to the email's original styling", bundle: .module)
        }
    }
}

struct HTMLBodyRenderingModeToggleButton: View {
    @Environment(\.brevTheme) private var theme

    let mode: HTMLBodyRenderingMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BrevSpacing.xs) {
                Image(systemName: mode == .dark ? "sun.max" : "moon.stars")
                Text(mode.toggleTitle)
            }
            .brevFont(.caption)
            .foregroundStyle(theme.textPrimary.color)
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, BrevSpacing.xs)
            .background(theme.bgTertiary.color)
            .overlay {
                RoundedRectangle(cornerRadius: BrevRadius.sm)
                    .stroke(theme.border.color, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
            .contentShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.toggleAccessibilityLabel)
    }
}
