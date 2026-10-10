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
    @ScaledMetric(relativeTo: .title2) private var sendGlyphSize: CGFloat = 24
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

    /// Side of the square buttons: Apple's 44 pt minimum target on iOS.
    private static let buttonSize: CGFloat = {
        #if os(iOS)
        44
        #else
        32
        #endif
    }()

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

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.border.color)
                .frame(height: 0.5)
            HStack(alignment: .bottom, spacing: BrevSpacing.sm) {
                quickReplyField
                    .lineLimit(1 ... 5)
                    .textFieldStyle(.plain)
                #if os(iOS)
                    // Return sends, as the keyboard's label says; longer replies
                    // go through "Open in Composer".
                    .submitLabel(.send)
                    .onSubmit(beginSend)
                #endif
                    .padding(.horizontal, BrevSpacing.sm)
                    .padding(.vertical, BrevSpacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: BrevRadius.lg, style: .continuous)
                            .fill(theme.bgSecondary.color)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: BrevRadius.lg, style: .continuous)
                            .stroke(theme.border.color, lineWidth: 0.5)
                    }
                    .disabled(isDisabled || isSending)
                #if os(macOS)
                    .focusEffectDisabled()
                #endif
                Button {
                    onExpand(draftText)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .foregroundStyle(theme.textSecondary.color)
                        .frame(width: Self.buttonSize, height: Self.buttonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Open in Composer", bundle: .module))
                .accessibilityLabel(String(localized: "Open in Composer", bundle: .module))
                .disabled(isDisabled || isSending)

                Button(action: beginSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: sendGlyphSize))
                        .foregroundStyle(theme.accent.color)
                        .frame(width: Self.buttonSize, height: Self.buttonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Send reply", bundle: .module))
                .disabled(isDisabled || isSending || draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #if os(macOS)
                    .keyboardShortcut(.return, modifiers: .command)
                #endif
            }
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.sm)

            if let remainingSeconds {
                HStack(spacing: BrevSpacing.sm) {
                    Text(String(localized: "Sending in \(remainingSeconds)s…", bundle: .module))
                    Spacer()
                    Button(action: cancelSend) {
                        Text(String(localized: "Undo", bundle: .module))
                            .frame(minWidth: Self.buttonSize, minHeight: Self.buttonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.accent.color)
                }
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
                .padding(.horizontal, BrevSpacing.md)
                .padding(.bottom, BrevSpacing.sm)
            } else if isSending {
                Text("Sending", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, BrevSpacing.md)
                    .padding(.bottom, BrevSpacing.sm)
            } else if status == .sent {
                Text("Sent", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, BrevSpacing.md)
                    .padding(.bottom, BrevSpacing.sm)
            } else if status == .failed {
                Text(draftWasSaved
                    ? String(localized: "Couldn't send. Your reply was saved as a draft.", bundle: .module)
                    : String(localized: "Couldn't send reply.", bundle: .module))
                    .brevFont(.caption)
                    .foregroundStyle(theme.danger.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, BrevSpacing.md)
                    .padding(.bottom, BrevSpacing.sm)
            }
        }
        .background(theme.bgPrimary.color)
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
