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

/// Surface-level loading indicator for async operations.
///
/// Shows a platform-native spinner with an optional descriptive label.
/// When `isVisible` is false the view retains its frame so the
/// surrounding layout does not shift when the indicator appears or
/// disappears. Per ADR-0013 and ADR-0002.
///
/// - Parameters:
///   - label: Optional label displayed below the spinner.
///   - isVisible: When false the view is hidden but still occupies space.
public struct BrevProgressSurface: View {
    @Environment(\.brevTheme) private var theme

    private let label: LocalizedStringKey?
    private let isVisible: Bool

    public init(
        label: LocalizedStringKey? = nil,
        isVisible: Bool = true
    ) {
        self.label = label
        self.isVisible = isVisible
    }

    public var body: some View {
        VStack(spacing: BrevSpacing.md) {
            ProgressView()
                .tint(theme.accent.color)

            if let label {
                Text(label)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(BrevSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .hidden(!isVisible)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label.map { Text($0) } ?? Text("Loading", bundle: .module))
    }
}

private extension View {
    /// Hides the view without removing it from layout.
    @ViewBuilder
    func hidden(_ hidden: Bool) -> some View {
        if hidden {
            self.hidden()
        } else {
            self
        }
    }
}
