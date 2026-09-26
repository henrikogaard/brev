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
    #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
    #endif
    private var selectionPalette: MailSelectionPalette {
        #if os(macOS)
        // Same focused-pane tint contract as the parent MessageListRow —
        // an expanded child demotes when the list loses keyboard focus.
        MailSelectionPalette(
            theme: theme,
            isActive: controlActiveState != .inactive && isFocusedPane
        )
        #else
        MailSelectionPalette(theme: theme)
        #endif
    }

    @Environment(\.brevTheme) private var theme
    // Read from the environment so locale/time-zone overrides reach the row
    // and snapshots stay deterministic, matching MessageListRow.
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone

    let header: MessageHeader
    let isSelected: Bool
    /// macOS: whether the owning list column holds keyboard focus —
    /// mirrors `MessageListRow.isFocusedPane`.
    var isFocusedPane = true
    let onSelect: () -> Void
    /// Mailbox typography preferences, matching `MessageListRow` so expanded
    /// thread children honor the same font family, text size, and density.
    var fontFamily: MailboxFontFamily = .system
    var textSize: MailboxTextSize = .medium
    var density: MailboxListDensity = .comfortable
    /// "Now" for the relative date label. Injectable so snapshots don't
    /// drift as wall-clock time passes the fixture date.
    var referenceDate = Date()

    var body: some View {
        HStack(spacing: BrevSpacing.sm) {
            // Unread indicator — labelled so the combined row element
            // announces the state instead of a bare dot being skipped.
            Circle()
                .fill(header.isRead ? Color.clear : theme.textPrimary.color)
                .frame(width: 7, height: 7)
                .accessibilityLabel(String(localized: "Unread", bundle: .module))
                .accessibilityHidden(header.isRead)

            // Sender avatar — slightly smaller than the top-level row to keep
            // the subordinate hierarchy, but still density-driven.
            BrevAvatarView(
                email: header.from.email,
                displayName: header.from.name,
                size: max(20, density.avatarSize - 8)
            )

            // Sender + snippet
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(header.from.name ?? header.from.email)
                        .font(fontFamily.font(
                            size: textSize.listTitlePointSize,
                            weight: MessageListSenderPresentation.fontWeight
                        ))
                        .foregroundStyle(theme.textPrimary.color)
                        .lineLimit(1)

                    Spacer()

                    Text(dateLabel)
                        .font(fontFamily.font(size: max(12, textSize.captionPointSize)))
                        .foregroundStyle(isSelected ? selectionPalette.detail.color : theme.textTertiary.color)
                }

                Text(MessageListPresentation.previewText(from: header.snippet, subject: header.subject))
                    .font(fontFamily.font(size: max(12, textSize.captionPointSize)))
                    .foregroundStyle(theme.textSecondary.color)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, density.verticalPadding * 0.75)
        .padding(.horizontal, BrevSpacing.md)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1).fill(selectionPalette.indicator.color)
                    .frame(width: 2).padding(.vertical, BrevSpacing.xs)
                    .padding(.leading, ThreadInlineChildRowPresentation.selectionHorizontalInset)
            }
        }
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
            .fill(selectionPalette.background.color)
            .padding(.horizontal, ThreadInlineChildRowPresentation.selectionHorizontalInset)
        } else {
            Color.clear
        }
    }
}
