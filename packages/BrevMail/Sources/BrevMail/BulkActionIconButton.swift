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

/// Compact icon-only button for bulk action toolbars.
struct BulkActionIconButton: View {
    let label: String
    let systemImage: String
    let isDisabled: Bool
    let isDestructive: Bool
    let action: () -> Void

    @Environment(\.brevTheme) private var theme

    init(
        label: String,
        systemImage: String,
        isDisabled: Bool,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.isDisabled = isDisabled
        self.isDestructive = isDestructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isDestructive ? theme.danger.color : theme.textSecondary.color)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityLabel(label)
        .help(label)
    }
}

/// The shared bulk-selection action bar used by `MessageListView` and
/// `UnifiedInboxListView`. Selection counts, capability differences (whether
/// Archive is shown vs disabled), and the view-specific overflow menu are
/// injected so each list keeps its own item-resolution semantics while the
/// layout, labels, icons, and hit targets stay identical.
struct MailBulkActionBar<Overflow: View>: View {
    let selectionCount: Int
    /// When false the Archive button is omitted entirely (a folder mailbox
    /// with no archive folder); when true it is shown and `isArchiveEnabled`
    /// decides whether it can be tapped.
    let showsArchive: Bool
    let isArchiveEnabled: Bool
    let isDisabled: Bool
    let onMarkRead: () -> Void
    let onMarkUnread: () -> Void
    let onFlag: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void
    @ViewBuilder var overflow: () -> Overflow

    @Environment(\.brevTheme) private var theme

    init(
        selectionCount: Int,
        showsArchive: Bool = true,
        isArchiveEnabled: Bool = true,
        isDisabled: Bool,
        onMarkRead: @escaping () -> Void,
        onMarkUnread: @escaping () -> Void,
        onFlag: @escaping () -> Void,
        onArchive: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder overflow: @escaping () -> Overflow
    ) {
        self.selectionCount = selectionCount
        self.showsArchive = showsArchive
        self.isArchiveEnabled = isArchiveEnabled
        self.isDisabled = isDisabled
        self.onMarkRead = onMarkRead
        self.onMarkUnread = onMarkUnread
        self.onFlag = onFlag
        self.onArchive = onArchive
        self.onDelete = onDelete
        self.overflow = overflow
    }

    var body: some View {
        HStack(spacing: BrevSpacing.xs) {
            Text("\(selectionCount) selected", bundle: .module)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
            Spacer(minLength: BrevSpacing.sm)
            BulkActionIconButton(
                label: String(localized: "Mark Read", bundle: .module),
                systemImage: "envelope.open",
                isDisabled: isDisabled,
                action: onMarkRead
            )
            BulkActionIconButton(
                label: String(localized: "Mark Unread", bundle: .module),
                systemImage: "envelope.badge",
                isDisabled: isDisabled,
                action: onMarkUnread
            )
            // Canonical terminology is Flag/Unflag (see MessageCommandPresentation).
            BulkActionIconButton(
                label: String(localized: "Flag", bundle: .module),
                systemImage: "flag",
                isDisabled: isDisabled,
                action: onFlag
            )
            if showsArchive {
                BulkActionIconButton(
                    label: String(localized: "Archive", bundle: .module),
                    systemImage: "archivebox",
                    isDisabled: isDisabled || !isArchiveEnabled,
                    action: onArchive
                )
            }
            BulkActionIconButton(
                label: String(localized: "Delete", bundle: .module),
                systemImage: "trash",
                isDisabled: isDisabled,
                isDestructive: true,
                action: onDelete
            )
            overflow()
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrevSeparator.color(for: theme))
                .frame(height: 0.5)
        }
    }
}
