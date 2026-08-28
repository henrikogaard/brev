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

/// Semantic treatment for compact inline status surfaces.
public enum BrevInlineStatusTone: Sendable, Hashable, CaseIterable {
    case info
    case success
    case warning
    case danger

    var symbolName: String {
        switch self {
        case .info:
            return "info.circle"
        case .success:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .danger:
            return "xmark.octagon"
        }
    }

    func color(in theme: BrevTheme) -> Color {
        switch self {
        case .info:
            return theme.info.color
        case .success:
            return theme.success.color
        case .warning:
            return theme.warning.color
        case .danger:
            return theme.danger.color
        }
    }
}

/// Compact, theme-aware status banner for retryable or dismissible
/// states inside mail surfaces.
public struct BrevInlineStatus: View {
    @Environment(\.brevTheme) private var theme

    private let message: String
    private let tone: BrevInlineStatusTone
    private let actionTitle: String?
    private let onAction: (() -> Void)?
    private let onDismiss: (() -> Void)?
    private let lineLimit: Int?
    private let combinesInteractiveAccessibilityChildren = false

    public init(
        message: String,
        tone: BrevInlineStatusTone = .info,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        lineLimit: Int? = 2
    ) {
        self.message = message
        self.tone = tone
        self.actionTitle = actionTitle
        self.onAction = onAction
        self.onDismiss = onDismiss
        self.lineLimit = lineLimit
    }

    public var body: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: tone.symbolName)
                .foregroundStyle(tone.color(in: theme))
                .accessibilityHidden(true)

            Text(message)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: BrevSpacing.sm)

            if let actionTitle,
               let onAction {
                Button(actionTitle, action: onAction)
                    .buttonStyle(.borderless)
                    .foregroundStyle(theme.accent.color)
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .accessibilityHidden(true)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.textTertiary.color)
                .accessibilityLabel(Text("Dismiss", bundle: .module))
            }
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.xs)
        .background(theme.bgSecondary.color)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrevSeparator.color(for: theme))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: combinesInteractiveAccessibilityChildren ? .combine : .contain)
    }
}
