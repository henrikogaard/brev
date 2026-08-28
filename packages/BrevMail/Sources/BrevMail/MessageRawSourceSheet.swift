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

import BrevBackend
import BrevDesign
import BrevThemes
import SwiftUI

/// Whether the raw-source viewer shows the full RFC 822 message or only its
/// leading header block.
enum MessageRawSourceMode: Equatable, Sendable {
    case fullSource
    case headersOnly

    var title: String {
        switch self {
        case .fullSource: "View Source"
        case .headersOnly: "Show Headers"
        }
    }

    var symbolName: String {
        switch self {
        case .fullSource: "chevron.left.forwardslash.chevron.right"
        case .headersOnly: "list.bullet.rectangle"
        }
    }
}

/// Pure transforms for the raw-source viewer, kept separate from SwiftUI so the
/// header-extraction rule is unit-testable.
enum MessageRawSourcePresentation {
    /// Returns the portion of `rawSource` to display for `mode`. In
    /// `.headersOnly` mode this is everything up to (but excluding) the first
    /// blank line that separates RFC 822 headers from the body, normalised to
    /// `\n` line endings. If no blank-line separator is present the whole input
    /// is treated as headers.
    static func body(from rawSource: String, mode: MessageRawSourceMode) -> String {
        let normalised = rawSource
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        switch mode {
        case .fullSource:
            return normalised
        case .headersOnly:
            if let separator = normalised.range(of: "\n\n") {
                return String(normalised[normalised.startIndex ..< separator.lowerBound])
            }
            return normalised
        }
    }
}

/// Read-only viewer for a message's raw RFC 822 source (full body or just the
/// header block). Presented from the "View Source" / "Show Headers" context-menu
/// actions. The source is fetched once through the injected `loadSource` closure,
/// which reads from the cache when available (ADR-0045); the sheet itself adds no
/// network behaviour.
struct MessageRawSourceSheet: View {
    @Environment(\.brevTheme) private var theme
    let header: MessageHeader
    let mode: MessageRawSourceMode
    let loadSource: () async throws -> String
    let onClose: () -> Void

    @State private var loadState: LoadState = .loading

    private enum LoadState: Equatable {
        case loading
        case loaded(String)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            BrevDivider()
            content
        }
        .frame(minWidth: 420, idealWidth: 560, minHeight: 360, idealHeight: 520)
        .background(theme.bgPrimary.color)
        .presentationDetents([.large])
        .task {
            do {
                let raw = try await loadSource()
                loadState = .loaded(MessageRawSourcePresentation.body(from: raw, mode: mode))
            } catch {
                loadState = .failed(MessageRawSourceErrorText.message(for: error))
            }
        }
    }

    private var titleBar: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: mode.symbolName)
                .foregroundStyle(theme.accent.color)
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(mode.title)
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)
                Text(header.subject.isEmpty ? "(No subject)" : header.subject)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.textTertiary.color)
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            statusView(symbol: "hourglass", message: "Loading message source…")
        case .failed(let message):
            statusView(symbol: "exclamationmark.triangle", message: message)
        case .loaded(let text):
            ScrollView([.vertical, .horizontal]) {
                Text(text.isEmpty ? "(Empty source)" : text)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(theme.textPrimary.color)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BrevSpacing.md)
            }
        }
    }

    private func statusView(symbol: String, message: String) -> some View {
        VStack(spacing: BrevSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(theme.textTertiary.color)
            Text(message)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textSecondary.color)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(BrevSpacing.lg)
    }
}

private enum MessageRawSourceErrorText {
    static func message(for error: Error) -> String {
        if let backendError = error as? MailBackendError {
            return MessageCommandPresentation.mutationErrorStatus(for: backendError).message
        }
        return "Couldn't load the message source."
    }
}
