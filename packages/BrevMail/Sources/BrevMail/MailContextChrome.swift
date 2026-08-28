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

// The AI Sidebar column itself is macOS-only, but `MailboxChatPanel` uses this
// chrome on both platforms, so it cannot live behind that file's `#if os(macOS)`.

/// Hairline weights for the AI Sidebar.
///
/// The colours come from `BrevSeparator`, which every hairline in the app now
/// shares — see ADR-0053. This keeps only the weights the column picks from it.
enum MailContextSeparator {
    /// Rules inside the column.
    static let interiorOpacity = BrevSeparator.interiorOpacity
    /// The column's outer edge, which separates two panes rather than two rows.
    static let edgeOpacity = BrevSeparator.edgeOpacity
    /// Row highlight under the pointer, which carries the row boundary now that
    /// no rule does.
    static let rowHoverOpacity = 0.08
}

/// Horizontal hairline used inside the AI Sidebar.
///
/// Neutral, not accent-tinted: a coloured hairline between rows reads as a
/// selection or an active state rather than as structure, and macOS separators
/// are uniformly neutral. The accent is reserved here for things the user can
/// act on — the resize handle under the pointer, chips, and buttons.
struct MailContextDivider: View {
    @Environment(\.brevTheme) private var theme

    /// Leading inset. Row separators align with the text they divide, the way
    /// list separators do; section rules run full width.
    var leadingInset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(theme.textPrimary.color.opacity(MailContextSeparator.interiorOpacity))
            .frame(height: 1)
            .padding(.leading, leadingInset)
            .accessibilityHidden(true)
    }
}

/// Section heading inside the AI Sidebar.
///
/// Small, semibold, secondary — the macOS inspector idiom. These headings were
/// `.headline` in primary text, the same treatment as the sender's name, so a
/// column carrying one piece of identity and three labelled groups read as four
/// competing titles stacked down the panel. Demoting the labels leaves the
/// sender as the only primary-weight text in the column.
struct MailContextSectionHeader: View {
    @Environment(\.brevTheme) private var theme

    let title: String
    /// Optional trailing text — an account or provider label the heading scopes.
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: BrevSpacing.sm) {
            Text(title)
                .brevFont(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.textSecondary.color)

            Spacer(minLength: 0)

            if let trailing {
                Text(trailing)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                    .lineLimit(1)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}
