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
import SwiftUI

enum ReaderQuickReplyLayoutPolicy {
    /// Continuous corner radius for the expanding quick-reply glass capsule.
    static let inputCornerRadius: CGFloat = 20

    /// Diameter of the circular send button: 44 pt on iOS, 34 pt on macOS.
    static func sendButtonSize(isTouchPlatform: Bool) -> CGFloat {
        isTouchPlatform ? 44 : 34
    }

    /// Touch/click target size for inline composer-expand buttons.
    static func auxiliaryButtonSize(isTouchPlatform: Bool) -> CGFloat {
        isTouchPlatform ? 44 : 28
    }

    /// Touch/click target size for the Undo Send countdown button: 44 pt on iOS, 32 pt on macOS.
    static func undoButtonSize(isTouchPlatform: Bool) -> CGFloat {
        isTouchPlatform ? 44 : 32
    }

    /// Returns `true` when the quick-reply draft is non-empty and sending is allowed.
    static func canSend(draftText: String, isDisabled: Bool, isSending: Bool) -> Bool {
        !isDisabled
            && !isSending
            && !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Subtle non-hit-testing bottom scroll fade rendered behind the floating glass
/// quick-reply dock so scrolled reader copy glides smoothly beneath it.
struct ReaderQuickReplyBottomFade: View {
    @Environment(\.brevTheme) private var theme

    var body: some View {
        LinearGradient(
            colors: [
                Color.clear,
                theme.bgPrimary.color.opacity(0.85)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .padding(.top, -BrevSpacing.md)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ReaderQuickReplyBar: View {
    private enum Status: Equatable {
        case sent
        case failed
    }

    let recipientName: String
    let onSend: (String) async -> Bool
    let onExpand: (String) -> Void
    let isDisabled: Bool

    @Environment(\.brevTheme) private var theme
    /// Scales the send glyph with Dynamic Type; 44 pt targets hold it on iOS.
    #if os(iOS)
    @ScaledMetric(relativeTo: .body) private var sendGlyphSize: CGFloat = 17
    #else
    @ScaledMetric(relativeTo: .body) private var sendGlyphSize: CGFloat = 14
    #endif
    @Binding private var draftWasSaved: Bool
    @State private var draftText = ""
    @State private var isSending = false
    @State private var remainingSeconds: Int?
    @State private var pendingSendText: String?
    @State private var sendTask: Task<Void, Never>?
    @State private var status: Status?

    init(
        recipientName: String,
        onSend: @escaping (String) async -> Bool,
        onExpand: @escaping (String) -> Void,
        isDisabled: Bool,
        draftWasSaved: Binding<Bool> = .constant(false)
    ) {
        self.recipientName = recipientName
        self.onSend = onSend
        self.onExpand = onExpand
        self.isDisabled = isDisabled
        _draftWasSaved = draftWasSaved
    }

    private static var isTouchPlatform: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    /// Circular Send button diameter: 44 pt minimum target on iOS, 34 pt on macOS.
    private static let sendButtonSize: CGFloat = ReaderQuickReplyLayoutPolicy.sendButtonSize(
        isTouchPlatform: isTouchPlatform
    )

    /// Inline Open in Composer button target: 44 pt on iOS, compact on macOS.
    private static let auxiliaryButtonSize: CGFloat = ReaderQuickReplyLayoutPolicy.auxiliaryButtonSize(
        isTouchPlatform: isTouchPlatform
    )

    /// Undo Send countdown button target: 44 pt on iOS, 32 pt on macOS.
    private static let undoButtonSize: CGFloat = ReaderQuickReplyLayoutPolicy.undoButtonSize(
        isTouchPlatform: isTouchPlatform
    )

    private static let expandGlyphSize: CGFloat = {
        #if os(iOS)
        15
        #else
        12
        #endif
    }()

    private static let fieldVerticalPadding: CGFloat = {
        #if os(iOS)
        11
        #else
        8
        #endif
    }()

    private static let expandInsetPadding: CGFloat = {
        #if os(iOS)
        0
        #else
        3
        #endif
    }()

    private var canSend: Bool {
        ReaderQuickReplyLayoutPolicy.canSend(
            draftText: draftText,
            isDisabled: isDisabled,
            isSending: isSending
        )
    }

    @ViewBuilder
    private var quickReplyField: some View {
        let placeholder = String(localized: "Reply to \(recipientName)…", bundle: .module)
        #if os(iOS)
        // The system placeholder colour fails contrast on the field's
        // surface; use the theme's secondary text.
        TextField(
            placeholder,
            text: $draftText,
            prompt: Text(placeholder).foregroundStyle(theme.textSecondary.color),
            axis: .vertical
        )
        #else
        TextField(placeholder, text: $draftText, axis: .vertical)
        #endif
    }

    @ViewBuilder
    private var statusPill: some View {
        if let remainingSeconds {
            HStack(spacing: BrevSpacing.sm) {
                Text(String(localized: "Sending in \(remainingSeconds)s…", bundle: .module))
                    .brevFont(.caption)
                    .foregroundStyle(theme.textPrimary.color)
                Button(action: cancelSend) {
                    Text(String(localized: "Undo", bundle: .module))
                        .brevFont(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.accent.color)
                        .frame(minWidth: Self.undoButtonSize, minHeight: Self.undoButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.xxs)
            .brevGlassCapsule(interactive: true)
        } else if isSending {
            HStack(spacing: BrevSpacing.xs) {
                ProgressView()
                    .controlSize(.small)
                Text("Sending", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            }
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.xs)
            .brevGlassCapsule()
        } else if status == .sent {
            HStack(spacing: BrevSpacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.success.color)
                    .accessibilityHidden(true)
                Text("Sent", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textPrimary.color)
            }
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.xs)
            .brevGlassCapsule()
        } else if status == .failed {
            HStack(spacing: BrevSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.danger.color)
                    .accessibilityHidden(true)
                Text(draftWasSaved
                    ? String(localized: "Couldn't send. Your reply was saved as a draft.", bundle: .module)
                    : String(localized: "Couldn't send reply.", bundle: .module))
                    .brevFont(.caption)
                    .foregroundStyle(theme.danger.color)
            }
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.xs)
            .brevGlassCapsule()
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: BrevSpacing.xs) {
            statusPill

            BrevGlassContainer(spacing: BrevSpacing.sm) {
                HStack(alignment: .bottom, spacing: BrevSpacing.sm) {
                    HStack(alignment: .bottom, spacing: BrevSpacing.xs) {
                        quickReplyField
                            .lineLimit(1 ... 5)
                            .textFieldStyle(.plain)
                            .foregroundStyle(theme.textPrimary.color)
                        #if os(iOS)
                            // Return sends, as the keyboard's label says; longer replies
                            // go through "Open in Composer".
                            .submitLabel(.send)
                            .onSubmit(beginSend)
                        #endif
                            .padding(.leading, BrevSpacing.md)
                            .padding(.vertical, Self.fieldVerticalPadding)
                            .disabled(isDisabled || isSending)
                        #if os(macOS)
                            .focusEffectDisabled()
                        #endif

                        Button {
                            onExpand(draftText)
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: Self.expandGlyphSize, weight: .medium))
                                .foregroundStyle(theme.textSecondary.color)
                                .frame(width: Self.auxiliaryButtonSize, height: Self.auxiliaryButtonSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Open in Composer", bundle: .module))
                        .accessibilityLabel(String(localized: "Open in Composer", bundle: .module))
                        .disabled(isDisabled || isSending)
                        .padding(.trailing, Self.expandInsetPadding)
                        .padding(.bottom, Self.expandInsetPadding)
                    }
                    .frame(minHeight: Self.sendButtonSize)
                    .brevGlassSurface(
                        cornerRadius: ReaderQuickReplyLayoutPolicy.inputCornerRadius,
                        interactive: true
                    )

                    Button(action: beginSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: sendGlyphSize, weight: .semibold))
                            .foregroundStyle(canSend ? theme.onAccent.color : theme.textTertiary.color)
                            .frame(width: Self.sendButtonSize, height: Self.sendButtonSize)
                            .contentShape(Circle())
                    }
                    .buttonBorderShape(.circle)
                    .brevGlassButtonStyle(prominent: canSend, tint: theme.accent.color)
                    .accessibilityLabel(String(localized: "Send reply", bundle: .module))
                    .disabled(!canSend)
                    #if os(macOS)
                        .keyboardShortcut(.return, modifiers: .command)
                    #endif
                }
            }
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.sm)
        }
        #if os(iOS)
        // Countdown, "Sent" and failure are otherwise silent for VoiceOver.
        .onChange(of: status) { _, newStatus in
            switch newStatus {
            case .sent:
                announce(String(localized: "Sent", bundle: .module))
            case .failed:
                announce(draftWasSaved
                    ? String(localized: "Couldn't send. Your reply was saved as a draft.", bundle: .module)
                    : String(localized: "Couldn't send reply.", bundle: .module))
            case nil:
                break
            }
        }
        .onChange(of: remainingSeconds != nil) { _, isCountingDown in
            if isCountingDown { announce(String(localized: "Sending", bundle: .module)) }
        }
        #endif
        .onDisappear {
            if remainingSeconds != nil {
                sendTask?.cancel()
            }
        }
    }

    #if os(iOS)
    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
    #endif

    private func beginSend() {
        let text = draftText
        guard !isDisabled,
              !isSending,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let send = onSend
        status = nil
        draftWasSaved = false
        pendingSendText = text
        isSending = true

        let delaySeconds = ComposeUndoSendPolicy.delaySeconds()
        guard delaySeconds > 0 else {
            sendTask = Task { await deliver(text, using: send) }
            return
        }

        sendTask = Task {
            for remaining in ComposeUndoSendPolicy.countdownValues(for: delaySeconds) {
                guard !Task.isCancelled else { return }
                remainingSeconds = remaining
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            remainingSeconds = nil
            await deliver(text, using: send)
        }
    }

    private func cancelSend() {
        sendTask?.cancel()
        sendTask = nil
        remainingSeconds = nil
        isSending = false
        if let pendingSendText {
            draftText = pendingSendText
        }
        pendingSendText = nil
        status = nil
    }

    private func deliver(
        _ text: String,
        using send: @escaping (String) async -> Bool
    ) async {
        let sent = await send(text)
        sendTask = nil
        remainingSeconds = nil
        isSending = false
        pendingSendText = nil
        if sent {
            draftText = ""
            draftWasSaved = false
            status = .sent
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if status == .sent {
                    status = nil
                }
            }
        } else {
            status = .failed
        }
    }
}
