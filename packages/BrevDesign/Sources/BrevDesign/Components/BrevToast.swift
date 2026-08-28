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

/// Themed transient feedback surface. `BrevToast` renders one message;
/// queueing and timing belong to the feature that presents it.
public struct BrevToast: View {
    @Environment(\.brevTheme) private var theme

    private let message: String
    private let tone: BrevInlineStatusTone
    private let actionTitle: String?
    private let onAction: (() -> Void)?
    private let onDismiss: (() -> Void)?

    public init(
        message: String,
        tone: BrevInlineStatusTone = .info,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.message = message
        self.tone = tone
        self.actionTitle = actionTitle
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    /// Widest the message text may grow before it wraps. The toast hugs its
    /// content so it reads as a floating pill instead of a full-width bar.
    private static let maxMessageWidth: CGFloat = 320

    public var body: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: tone.symbolName)
                .foregroundStyle(tone.color(in: theme))
                .accessibilityHidden(true)

            Text(message)
                .brevFont(.footnote)
                .foregroundStyle(theme.textPrimary.color)
                .lineLimit(2)
                .frame(maxWidth: Self.maxMessageWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle,
               let onAction {
                Button(actionTitle, action: onAction)
                    .buttonStyle(.borderless)
                    .foregroundStyle(theme.accent.color)
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.textTertiary.color)
                .accessibilityLabel(Text("Dismiss", bundle: .module))
            }
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .background(theme.bgTertiary.color)
        .overlay {
            RoundedRectangle(cornerRadius: BrevRadius.lg)
                .stroke(theme.border.color, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.lg))
        .accessibilityElement(children: .contain)
    }
}

/// Alias for platforms and call sites that use snackbar terminology.
public typealias BrevSnackbar = BrevToast
