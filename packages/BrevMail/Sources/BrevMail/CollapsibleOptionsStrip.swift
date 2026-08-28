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

/// Collapsible strip that shows a compact summary when collapsed and arbitrary
/// content when expanded. Used for search options, filter bars, etc.
struct CollapsibleOptionsStrip<Content: View>: View {
    @Binding var isExpanded: Bool
    let hasNonDefaultOptions: Bool
    let summary: String
    @ViewBuilder let content: () -> Content

    @Environment(\.brevTheme) private var theme

    /// Collapsed state: tap to expand.
    @ViewBuilder
    private var collapsedButton: some View {
        Button {
            isExpanded = true
        } label: {
            HStack(spacing: BrevSpacing.xs) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
                Text(summary)
                    .brevFont(.caption)
                    .lineLimit(1)
                Spacer(minLength: BrevSpacing.xs)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(theme.textSecondary.color)
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Show search options", bundle: .module))
        .accessibilityValue(summary)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrevSeparator.color(for: theme))
                .frame(height: 0.5)
        }
    }

    /// Expanded state: content + optional collapse button.
    @ViewBuilder
    private var expandedContent: some View {
        VStack(spacing: 0) {
            content()
            if !hasNonDefaultOptions {
                Button {
                    isExpanded = false
                } label: {
                    HStack(spacing: BrevSpacing.xxs) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Hide search options", bundle: .module)
                            .brevFont(.caption)
                    }
                    .foregroundStyle(theme.textTertiary.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, BrevSpacing.md)
                    .padding(.bottom, BrevSpacing.xs)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Hide search options", bundle: .module))
            }
        }
    }

    var body: some View {
        if isExpanded || hasNonDefaultOptions {
            expandedContent
        } else {
            collapsedButton
        }
    }
}
