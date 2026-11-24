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

import BrevAI
import BrevDesign
import BrevSettings
import BrevThemes
import SwiftUI

/// Compact pill badge rendering `.urgent` or `.needsReply` from proactive on-device triage.
struct ProactiveTriagePriorityBadge: View {
    @Environment(\.brevTheme) private var theme
    let priority: ThreadTriagePriority
    let isSelected: Bool
    var selectionTextColor: Color?
    var selectionDetailColor: Color?

    var body: some View {
        if let label = priority.badgeLabel, let symbolName = priority.symbolName {
            HStack(spacing: 3) {
                Image(systemName: symbolName)
                    .font(.system(size: 9, weight: .semibold))
                Text(verbatim: label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(backgroundColor))
            .overlay(Capsule().stroke(borderColor, lineWidth: 0.5))
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var foregroundColor: Color {
        if isSelected, let selectionTextColor {
            return selectionTextColor
        }
        switch priority {
        case .urgent:
            return theme.warning.color
        case .needsReply:
            return theme.accent.color
        case .normal:
            return theme.textSecondary.color
        }
    }

    private var backgroundColor: Color {
        if isSelected, let selectionDetailColor {
            return selectionDetailColor.opacity(0.18)
        }
        switch priority {
        case .urgent:
            return theme.warning.color.opacity(0.14)
        case .needsReply:
            return theme.accentMuted.color
        case .normal:
            return theme.bgSecondary.color
        }
    }

    private var borderColor: Color {
        if isSelected, let selectionDetailColor {
            return selectionDetailColor.opacity(0.35)
        }
        switch priority {
        case .urgent:
            return theme.warning.color.opacity(0.32)
        case .needsReply:
            return theme.accent.color.opacity(0.28)
        case .normal:
            return theme.border.color
        }
    }
}

/// Compact message-list snippet & priority indicator for cached on-device triage insights.
struct MessageListRowTriageSnippet: View {
    @Environment(\.brevTheme) private var theme
    let insight: ThreadTriageInsight
    let isSelected: Bool
    let selectionTextColor: Color
    let selectionDetailColor: Color
    let fontFamily: MailboxFontFamily
    let detailPointSize: CGFloat
    let captionPointSize: CGFloat
    let previewLineCount: Int
    let usesAccessibilityLayout: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: BrevSpacing.xs) {
                if insight.priority != .normal {
                    ProactiveTriagePriorityBadge(
                        priority: insight.priority,
                        isSelected: isSelected,
                        selectionTextColor: selectionTextColor,
                        selectionDetailColor: selectionDetailColor
                    )
                }

                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(isSelected ? selectionDetailColor : theme.accent.color)
                    Text(verbatim: insight.attribution)
                        .font(fontFamily.font(size: max(10.5, captionPointSize - 1)))
                        .foregroundStyle(isSelected ? selectionDetailColor : theme.textTertiary.color)
                        .lineLimit(1)
                }
                .accessibilityHidden(true)
            }

            if previewLineCount > 0 {
                Text(verbatim: insight.summary)
                    .font(fontFamily.font(size: detailPointSize))
                    .foregroundStyle(isSelected ? selectionDetailColor : theme.textSecondary.color)
                    .lineLimit(usesAccessibilityLayout ? max(2, previewLineCount) : previewLineCount)
                    .truncationMode(.tail)
            }
        }
        .help(insight.attribution)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts: [String] = []
        if let badge = insight.priority.badgeLabel {
            parts.append(badge)
        }
        parts.append(insight.summary)
        parts.append(insight.attribution)
        return parts.joined(separator: ". ")
    }
}

/// Thread header card showing a cached proactive on-device summary and priority pill.
struct ProactiveThreadTriageCard: View {
    @Environment(\.brevTheme) private var theme
    let insight: ThreadTriageInsight

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            HStack(spacing: BrevSpacing.xs) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.accent.color)
                    .accessibilityHidden(true)
                Text("On-device summary", bundle: .module)
                    .brevFont(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textPrimary.color)
                if insight.priority != .normal {
                    ProactiveTriagePriorityBadge(
                        priority: insight.priority,
                        isSelected: false
                    )
                }
                Spacer(minLength: BrevSpacing.xs)
                Text(verbatim: insight.attribution)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
            }

            Text(verbatim: insight.summary)
                .brevFont(.footnote)
                .foregroundStyle(theme.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BrevSpacing.sm)
        .background(theme.bgSecondary.color)
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous)
                .stroke(theme.border.color, lineWidth: 0.5)
        )
    }
}
