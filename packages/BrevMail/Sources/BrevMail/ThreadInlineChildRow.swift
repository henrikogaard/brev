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

import BrevAvatars
import BrevBackend
import BrevDesign
import BrevThemes
import SwiftUI

/// Shared selection metrics for inline thread rows.
enum ThreadInlineChildRowPresentation {
    static let selectionCornerRadius = BrevRadius.md
    static let selectionHorizontalInset = BrevSpacing.xxs
}

/// An indented child row shown inside the message list when a thread is expanded inline.
///
/// Tapping the row calls `onSelect`. The row is visually lighter than a top-level
/// `MessageListRow` to indicate subordinate status.
struct ThreadInlineChildRow: View {
    @Environment(\.brevTheme) private var theme
    // Read from the environment so locale/time-zone overrides reach the row
    // and snapshots stay deterministic, matching MessageListRow.
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone

    let header: MessageHeader
    let isSelected: Bool
    let onSelect: () -> Void
    /// "Now" for the relative date label. Injectable so snapshots don't
    /// drift as wall-clock time passes the fixture date.
    var referenceDate = Date()

    var body: some View {
        HStack(spacing: BrevSpacing.sm) {
            // Unread indicator
            Circle()
                .fill(header.isRead ? Color.clear : theme.accent.color)
                .frame(width: 7, height: 7)

            // Sender avatar
            BrevAvatarView(
                email: header.from.email,
                displayName: header.from.name,
                size: 28
            )

            // Sender + snippet
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(header.from.name ?? header.from.email)
                        .font(.subheadline)
                        .fontWeight(MessageListSenderPresentation.fontWeight)
                        .foregroundStyle(theme.textPrimary.color)
                        .lineLimit(1)

                    Spacer()

                    Text(dateLabel)
                        .font(.caption)
                        .foregroundStyle(theme.textTertiary.color)
                }

                Text(MessageListPresentation.previewText(from: header.snippet, subject: header.subject))
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, BrevSpacing.xs)
        .padding(.horizontal, BrevSpacing.md)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Relative label via the shared list formatter instead of SwiftUI's
    /// live `.relative` text style: deterministic under test, and the same
    /// wording as the top-level row. Stays relative pending ADR-0054's
    /// decision on the arrival timestamp format.
    private var dateLabel: String {
        Self.dateLabel(
            for: header,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
    }

    /// Static so tests can pin every input; the view passes its environment.
    static func dateLabel(
        for header: MessageHeader,
        referenceDate: Date,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        MessageListDatePresentation.label(
            for: header.date,
            showsAbsoluteArrivalTime: false,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            RoundedRectangle(
                cornerRadius: ThreadInlineChildRowPresentation.selectionCornerRadius,
                style: .continuous
            )
            .fill(theme.selection.color)
            .padding(.horizontal, ThreadInlineChildRowPresentation.selectionHorizontalInset)
        } else {
            Color.clear
        }
    }
}
