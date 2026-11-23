/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions: The above copyright
 notice and this permission notice shall be included in all copies or
 substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

import BrevDesign
import BrevThemes
import Foundation
import SwiftUI

/// Compact countdown-ring toast shown in compose while an undo-send delay is active (#297).
struct ComposeUndoSendToastView: View {
    @Environment(\.brevTheme) private var theme

    let remainingSeconds: Int
    let progress: Double
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: BrevSpacing.sm) {
            ZStack {
                Circle().stroke(theme.border.color, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(theme.accent.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Undo send countdown", bundle: .module))
            .accessibilityValue(
                String(localized: "Sending in \(remainingSeconds)s…", bundle: .module)
            )

            Text(String(localized: "Sending in \(remainingSeconds)s…", bundle: .module))
                .brevFont(.footnote)
                .foregroundStyle(theme.textPrimary.color)
                .lineLimit(2)
                .frame(maxWidth: 320, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onUndo) {
                Text(String(localized: "Undo", bundle: .module))
                #if os(iOS)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                #endif
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.accent.color)
        }
        .padding(.horizontal, BrevSpacing.md)
        #if os(iOS)
            .padding(.vertical, BrevSpacing.xxs)
        #else
            .padding(.vertical, BrevSpacing.sm)
        #endif
            .background(theme.bgTertiary.color)
            .overlay {
                RoundedRectangle(cornerRadius: BrevRadius.lg)
                    .stroke(theme.border.color, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: BrevRadius.lg))
            .accessibilityElement(children: .contain)
    }
}

enum ComposeUndoSendProgress {
    static func fraction(startedAt: TimeInterval, now: TimeInterval, duration: TimeInterval) -> Double {
        guard startedAt.isFinite, now.isFinite, duration.isFinite else { return 0 }
        guard duration > 0 else { return 1 }
        return min(max((now - startedAt) / duration, 0), 1)
    }
}

enum ComposeUndoSendCountdown {
    typealias Sleeper = @MainActor (UInt64) async throws -> Void

    @MainActor
    static func run(
        delaySeconds: Int,
        sleeper: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) },
        onProgress: @escaping @MainActor (_ remainingSeconds: Int, _ progress: Double) -> Void,
        onCountdownComplete: @escaping @MainActor () -> Void,
        send: @escaping @MainActor () async -> Void
    ) async throws {
        guard delaySeconds > 0 else {
            try Task.checkCancellation()
            await send()
            return
        }

        for (elapsed, remaining) in ComposeUndoSendPolicy.countdownValues(for: delaySeconds).enumerated() {
            try Task.checkCancellation()
            onProgress(remaining, Double(elapsed) / Double(delaySeconds))
            try await sleeper(1_000_000_000)
        }

        try Task.checkCancellation()
        onProgress(0, 1)
        try Task.checkCancellation()
        onCountdownComplete()
        try Task.checkCancellation()
        await send()
    }
}
