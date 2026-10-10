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
///
/// On iOS the glyph and the hit area scale with Dynamic Type and never drop
/// below 44 pt (audit L1); macOS keeps the 28 pt toolbar button.
struct BulkActionIconButton: View {
    let label: String
    let systemImage: String
    let isDisabled: Bool
    let isDestructive: Bool
    let action: () -> Void

    @Environment(\.brevTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var scaledGlyphSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var scaledHitSize: CGFloat = 44

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
                .font(.system(size: glyphSize, weight: .medium))
                .foregroundStyle(isDestructive ? theme.danger.color : theme.textSecondary.color)
                .frame(minWidth: hitSize, minHeight: hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityLabel(label)
        .help(label)
    }

    private var glyphSize: CGFloat {
        #if os(iOS)
        scaledGlyphSize
        #else
        14
        #endif
    }

    private var hitSize: CGFloat {
        #if os(iOS)
        BrevHitTarget.resolved(scaled: scaledHitSize)
        #else
        28
        #endif
    }
}

#if os(iOS)
/// Navigation-bar and bottom-bar items for the phone's selection mode (audit L1):
/// Select All and Cancel at the top, Mark, Move, Archive and Delete at the bottom,
/// as in iOS Mail. The lists inject their own item resolution through the closures.
struct MailSelectionToolbar<MarkMenu: View>: ToolbarContent {
    let selectionCount: Int
    let allSelected: Bool
    let isDisabled: Bool
    /// When false the Archive button is omitted (a folder mailbox with no archive folder).
    let showsArchive: Bool
    let isArchiveEnabled: Bool
    let canMove: Bool
    let onToggleSelectAll: () -> Void
    let onCancel: () -> Void
    let onMove: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void
    @ViewBuilder var markMenu: () -> MarkMenu

    private var hasSelection: Bool { selectionCount > 0 }

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(
                allSelected
                    ? String(localized: "Deselect All", bundle: .module)
                    : String(localized: "Select All", bundle: .module),
                action: onToggleSelectAll
            )
            .disabled(isDisabled)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(String(localized: "Cancel", bundle: .module), action: onCancel)
        }
        ToolbarItem(placement: .bottomBar) {
            Menu {
                markMenu()
            } label: {
                Text("Mark", bundle: .module)
            }
            .disabled(!hasSelection || isDisabled)
        }
        ToolbarItem(placement: .bottomBar) {
            Spacer()
        }
        ToolbarItem(placement: .bottomBar) {
            Button(action: onMove) {
                Text("Move", bundle: .module)
            }
            .disabled(!hasSelection || isDisabled || !canMove)
        }
        ToolbarItem(placement: .bottomBar) {
            Spacer()
        }
        if showsArchive {
            ToolbarItem(placement: .bottomBar) {
                BulkActionIconButton(
                    label: String(localized: "Archive", bundle: .module),
                    systemImage: "archivebox",
                    isDisabled: !hasSelection || isDisabled || !isArchiveEnabled,
                    action: onArchive
                )
            }
        }
        ToolbarItem(placement: .bottomBar) {
            BulkActionIconButton(
                label: String(localized: "Delete", bundle: .module),
                systemImage: "trash",
                isDisabled: !hasSelection || isDisabled,
                isDestructive: true,
                action: onDelete
            )
        }
    }
}
#endif

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
