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

/// Consistent progress, retry, and success affordances for mail reversals,
/// presented as floating Liquid Glass HUD pills on OS 26+ with a material/solid fallback.
struct MailUndoToast: View {
    let queue: UndoQueue
    let isBlocked: Bool
    let onUndo: () -> Void
    let onRetry: () -> Void

    var body: some View {
        BrevGlassContainer(spacing: BrevSpacing.sm) {
            VStack(spacing: BrevSpacing.sm) {
                if queue.isUndoing {
                    MailUndoGlassProgressPill(
                        message: String(localized: "Undoing change…", bundle: .module)
                    )
                } else {
                    if let error = queue.errorMessage {
                        MailUndoGlassToastPill(
                            message: String(localized: "Couldn’t undo the change: \(error)", bundle: .module),
                            tone: .danger,
                            actionTitle: isBlocked ? nil : String(localized: "Retry Undo", bundle: .module),
                            onAction: isBlocked ? nil : onRetry,
                            onDismiss: { queue.dismissFailure() }
                        )
                    }
                    if let mutation = queue.current {
                        MailUndoGlassToastPill(
                            message: mutation.description,
                            tone: .info,
                            actionTitle: isBlocked ? nil : String(localized: "Undo", bundle: .module),
                            onAction: isBlocked ? nil : onUndo,
                            onDismiss: { queue.dismiss() }
                        )
                    }
                }
            }
        }
    }
}

private struct MailUndoGlassProgressPill: View {
    @Environment(\.brevTheme) private var theme
    let message: String

    var body: some View {
        HStack(spacing: BrevSpacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .brevFont(.footnote)
                .foregroundStyle(theme.textPrimary.color)
                .lineLimit(2)
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .brevGlassCapsule()
        .accessibilityElement(children: .combine)
    }
}

private struct MailUndoGlassToastPill: View {
    @Environment(\.brevTheme) private var theme

    let message: String
    let tone: BrevInlineStatusTone
    let actionTitle: String?
    let onAction: (() -> Void)?
    let onDismiss: (() -> Void)?

    /// Keeps floating HUD pills compact instead of stretching full-width.
    private static let maxMessageWidth: CGFloat = 320

    #if os(iOS)
    /// Apple's minimum touch target; the Undo and Dismiss buttons keep it.
    private static let minimumTouchTarget: CGFloat = 44
    #endif

    var body: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: symbolName)
                .foregroundStyle(toneColor)
                .accessibilityHidden(true)

            Text(message)
                .brevFont(.footnote)
                .foregroundStyle(theme.textPrimary.color)
                .lineLimit(2)
                .frame(maxWidth: Self.maxMessageWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let onAction {
                Button(action: onAction) {
                    Text(actionTitle)
                        .fontWeight(.medium)
                    #if os(iOS)
                        .frame(minWidth: Self.minimumTouchTarget, minHeight: Self.minimumTouchTarget)
                        .contentShape(Rectangle())
                    #endif
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.accent.color)
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    #if os(iOS)
                        .frame(minWidth: Self.minimumTouchTarget, minHeight: Self.minimumTouchTarget)
                        .contentShape(Rectangle())
                    #endif
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.textTertiary.color)
                .accessibilityLabel(String(localized: "Dismiss", bundle: .module))
            }
        }
        .padding(.horizontal, BrevSpacing.md)
        #if os(iOS)
            // The 44 pt buttons already provide the vertical breathing room.
            .padding(.vertical, BrevSpacing.xxs)
        #else
            .padding(.vertical, BrevSpacing.sm)
        #endif
            .brevGlassCapsule(interactive: true)
            .accessibilityElement(children: .contain)
        #if os(iOS)
            // Announce completed or failed reversals to VoiceOver.
            .onAppear { announce(message) }
            .onChange(of: message) { _, newMessage in announce(newMessage) }
        #endif
    }

    private var symbolName: String {
        switch tone {
        case .info:
            "info.circle"
        case .success:
            "checkmark.circle"
        case .warning:
            "exclamationmark.triangle"
        case .danger:
            "xmark.octagon"
        }
    }

    private var toneColor: Color {
        switch tone {
        case .info:
            theme.info.color
        case .success:
            theme.success.color
        case .warning:
            theme.warning.color
        case .danger:
            theme.danger.color
        }
    }

    #if os(iOS)
    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
    #endif
}
