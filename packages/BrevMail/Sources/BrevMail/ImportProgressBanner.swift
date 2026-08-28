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

/// Non-blocking import/sync affordance for the mailbox workspace chrome.
struct ImportProgressBanner: View {
    @Environment(\.brevTheme) private var theme

    let presentation: ImportProgressBannerPresentation
    let onRetry: (() -> Void)?

    var body: some View {
        Group {
            #if os(macOS)
            compactMacOSBody
            #else
            standardBody
            #endif
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private var compactMacOSBody: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: BrevSpacing.sm) {
                if presentation.showsDeterminateProgress, presentation.progressFraction == nil {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }

                Text(presentation.title)
                    .brevFont(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.textPrimary.color)
                    .lineLimit(1)

                if let message = presentation.message {
                    Text(message)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                if presentation.showsRetryAction, let onRetry {
                    Button(String(localized: "Retry", bundle: .module), action: onRetry)
                        .buttonStyle(.borderless)
                        .brevFont(.caption)
                        .foregroundStyle(theme.accent.color)
                } else if let completed = presentation.progressCompleted,
                          let total = presentation.progressTotal,
                          total > 0 {
                    Text(verbatim: "\(completed)/\(total)")
                        .brevFont(.caption)
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary.color)
                }
            }
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.xs)

            if presentation.showsDeterminateProgress, let fraction = presentation.progressFraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(theme.accent.color)
                    .frame(height: 3)
                    .padding(.horizontal, BrevSpacing.md)
                    .padding(.bottom, BrevSpacing.xs)
            }
        }
        .background(backgroundColor)
        .overlay(alignment: .bottom) {
            BrevDivider()
        }
    }

    private var standardBody: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                HStack(alignment: .center, spacing: BrevSpacing.sm) {
                    if presentation.showsDeterminateProgress, presentation.progressFraction == nil {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(presentation.title)
                            .brevFont(.caption)
                            .foregroundStyle(theme.textPrimary.color)

                        if let message = presentation.message {
                            Text(message)
                                .brevFont(.caption)
                                .foregroundStyle(theme.textSecondary.color)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 0)

                    if presentation.showsRetryAction, let onRetry {
                        Button(String(localized: "Retry", bundle: .module), action: onRetry)
                            .buttonStyle(.borderless)
                            .brevFont(.caption)
                            .foregroundStyle(theme.accent.color)
                    }
                }

                if presentation.showsDeterminateProgress, let fraction = presentation.progressFraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(theme.accent.color)

                    if let completed = presentation.progressCompleted,
                       let total = presentation.progressTotal,
                       total > 0 {
                        Text(verbatim: "\(completed)/\(total)")
                            .brevFont(.caption)
                            .monospacedDigit()
                            .foregroundStyle(theme.textSecondary.color)
                    }
                }
            }
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.xs)
            .background(backgroundColor)
            .overlay(alignment: .bottom) {
                BrevDivider()
            }
        }
    }

    private var backgroundColor: Color {
        switch presentation.style {
        case .info:
            return theme.info.color.opacity(0.08)
        case .warning:
            return theme.warning.color.opacity(0.08)
        case .error:
            return theme.danger.color.opacity(0.08)
        }
    }
}
