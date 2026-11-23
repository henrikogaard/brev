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
import BrevSettings
import BrevThemes
import Foundation
import SwiftUI

/// Ephemeral in-memory sign-in code match for message-list, reader, and Today
/// surfaces (#239, ADR-0088 §7). Never `Codable`, never logged, and always
/// redacted in default descriptions and mirrors.
public struct SignInCodeSurfaceMatch: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public let code: String
    public let sender: String
    public let sentAt: Date
    public let messageID: MessageHeader.ID
    public let folderID: Folder.ID
    public let sourceID: MailSourceID?

    public init(
        code: String,
        sender: String,
        sentAt: Date,
        messageID: MessageHeader.ID,
        folderID: Folder.ID,
        sourceID: MailSourceID?
    ) {
        self.code = code
        self.sender = sender
        self.sentAt = sentAt
        self.messageID = messageID
        self.folderID = folderID
        self.sourceID = sourceID
    }

    public var description: String { "SignInCodeSurfaceMatch(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: EmptyCollection<Mirror.Child>()) }
}

/// Opt-in-gated local extractor for sign-in code chips/cards in message list,
/// reader, and Today (#239, ADR-0088 §2). Performs zero detection unless
/// `codesEnabled` is true for the account.
public enum SignInCodeSurfacePolicy {
    public static func headerCode(
        for header: MessageHeader,
        sourceID: MailSourceID?,
        accountID: String,
        settings: SignInCodeSettings
    ) -> SignInCodeSurfaceMatch? {
        guard settings.accountOverride(for: accountID).codesEnabled else { return nil }
        let code = detectCode(in: header.subject)
            ?? detectCode(in: header.snippet)
            ?? detectCode(in: "\(header.subject)\n\(header.snippet)")
        guard let code else { return nil }
        return SignInCodeSurfaceMatch(
            code: code,
            sender: header.from.displayName,
            sentAt: header.date,
            messageID: header.id,
            folderID: header.folderID,
            sourceID: sourceID
        )
    }

    public static func bodyCode(
        plainText: String?,
        header: MessageHeader,
        sourceID: MailSourceID?,
        accountID: String,
        settings: SignInCodeSettings
    ) -> SignInCodeSurfaceMatch? {
        guard settings.accountOverride(for: accountID).codesEnabled else { return nil }
        if let plainText, let code = detectCode(in: plainText) {
            return SignInCodeSurfaceMatch(
                code: code,
                sender: header.from.displayName,
                sentAt: header.date,
                messageID: header.id,
                folderID: header.folderID,
                sourceID: sourceID
            )
        }
        return headerCode(for: header, sourceID: sourceID, accountID: accountID, settings: settings)
    }

    /// Returns the newest non-expired sign-in code for Today (#239).
    public static func newestActiveCode(
        headers: [MessageHeader],
        sourceID: MailSourceID?,
        accountID: String,
        settings: SignInCodeSettings,
        now: Date = Date()
    ) -> SignInCodeSurfaceMatch? {
        guard settings.accountOverride(for: accountID).codesEnabled else { return nil }
        let sorted = headers.sorted { $0.date > $1.date }
        for header in sorted {
            guard !SignInCodePresentationFormat.isProbablyExpired(sentAt: header.date, now: now) else {
                continue
            }
            if let match = headerCode(for: header, sourceID: sourceID, accountID: accountID, settings: settings) {
                return match
            }
        }
        return nil
    }

    private static func detectCode(in text: String) -> String? {
        guard !text.isEmpty,
              case .code(let code) = SignInCodeDetector.detect(in: text) else { return nil }
        return code
    }
}

/// Compact chip shown under the subject in a message-list row (#239).
struct SignInCodeListChip: View {
    @Environment(\.brevTheme) private var theme
    let code: String
    let pasteboard: any SignInCodePasteboardWriting
    @State private var copied = false

    init(
        code: String,
        pasteboard: any SignInCodePasteboardWriting = SystemSignInCodePasteboard()
    ) {
        self.code = code
        self.pasteboard = pasteboard
    }

    var body: some View {
        Button {
            _ = pasteboard.writeConcealed(code)
            copied = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: SignInCodePresentationFormat.groupedCode(code))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
            }
            .foregroundStyle(theme.textPrimary.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(theme.bgTertiary.color))
            .overlay(Capsule().strokeBorder(theme.border.color, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Copy code", bundle: .module))
    }
}

/// Reader banner above the message body showing a detected sign-in code (#239).
struct SignInCodeReaderCard: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    let match: SignInCodeSurfaceMatch
    let now: Date
    let pasteboard: any SignInCodePasteboardWriting
    @State private var copied = false

    init(
        match: SignInCodeSurfaceMatch,
        now: Date = Date(),
        pasteboard: any SignInCodePasteboardWriting = SystemSignInCodePasteboard()
    ) {
        self.match = match
        self.now = now
        self.pasteboard = pasteboard
    }

    private var isExpired: Bool {
        SignInCodePresentationFormat.isProbablyExpired(sentAt: match.sentAt, now: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            HStack(alignment: .center, spacing: BrevSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        isExpired
                            ? String(localized: "Sign-in code · probably expired", bundle: .module)
                            : String(localized: "Sign-in code", bundle: .module)
                    )
                    .brevFont(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.textSecondary.color)

                    Text(verbatim: SignInCodePresentationFormat.groupedCode(match.code))
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.textPrimary.color)
                        .monospacedDigit()
                }

                Spacer(minLength: BrevSpacing.sm)

                Button {
                    _ = pasteboard.writeConcealed(match.code)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                        Text(
                            copied
                                ? String(localized: "Copied", bundle: .module)
                                : String(localized: "Copy code", bundle: .module)
                        )
                        .brevFont(.caption)
                        .fontWeight(.semibold)
                    }
                    .foregroundStyle(theme.bgPrimary.color)
                    .padding(.horizontal, BrevSpacing.sm)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(theme.accent.color))
                }
                .buttonStyle(.plain)
            }

            let timeText = Self.formattedSentTime(match.sentAt, locale: locale, timeZone: timeZone)
            Text(
                verbatim: String(
                    format: String(
                        localized: "Sent at %@. Codes usually stop working after a few minutes.",
                        bundle: .module
                    ),
                    timeText
                )
            )
            .brevFont(.caption)
            .foregroundStyle(theme.textTertiary.color)
        }
        .padding(BrevSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .fill(theme.bgSecondary.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .strokeBorder(theme.border.color, lineWidth: 0.75)
        )
    }

    private static func formattedSentTime(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute().locale(locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }
}

/// Today-page banner for the newest non-expired sign-in code (#239).
struct TodaySignInCodeCard: View {
    @Environment(\.brevTheme) private var theme
    let match: SignInCodeSurfaceMatch
    let pasteboard: any SignInCodePasteboardWriting
    @State private var copied = false

    init(
        match: SignInCodeSurfaceMatch,
        pasteboard: any SignInCodePasteboardWriting = SystemSignInCodePasteboard()
    ) {
        self.match = match
        self.pasteboard = pasteboard
    }

    var body: some View {
        HStack(spacing: BrevSpacing.md) {
            Image(systemName: "key.viewfinder")
                .foregroundStyle(theme.accent.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: match.sender)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                Text(verbatim: SignInCodePresentationFormat.groupedCode(match.code))
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textPrimary.color)
                    .monospacedDigit()
            }

            Spacer(minLength: BrevSpacing.sm)

            Button {
                _ = pasteboard.writeConcealed(match.code)
                copied = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Text(
                    copied
                        ? String(localized: "Copied", bundle: .module)
                        : String(localized: "Copy code", bundle: .module)
                )
                .brevFont(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.bgPrimary.color)
                .padding(.horizontal, BrevSpacing.sm)
                .padding(.vertical, 6)
                .background(Capsule().fill(theme.accent.color))
            }
            .buttonStyle(.plain)
        }
        .padding(BrevSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .fill(theme.bgSecondary.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .strokeBorder(theme.border.color, lineWidth: 0.75)
        )
    }
}
