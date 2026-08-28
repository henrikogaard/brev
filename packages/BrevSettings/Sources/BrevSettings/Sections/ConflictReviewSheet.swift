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

// MARK: - Presentation helpers

/// Derives the button title for the "open conflict list" action.
enum ConflictReviewPresentation {
    /// Returns the button title or `nil` when the button should be hidden.
    static func reviewButtonTitle(conflictCount: Int) -> String? {
        guard conflictCount > 0 else { return nil }
        return conflictCount == 1
            ? String(localized: "Review 1 conflict", bundle: .module)
            : String(localized: "Review \(conflictCount) conflicts", bundle: .module)
    }
}

// MARK: - Sheet view

/// Sheet listing undismissed replay conflicts for one account source.
///
/// Opened from `AccountsSection` when `replayConflictCount > 0`. Each row
/// lets the user dismiss a single conflict; toolbar buttons dismiss all or
/// trigger a sync retry.
struct ConflictReviewSheet: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// Live conflict list. Caller owns this state and mutates it in place
    /// so the sheet reflects changes immediately without a full reload.
    @Binding var conflicts: [ReplayConflict]

    let onDismissConflict: (ReplayConflict) async -> Void
    let onDismissAll: () async -> Void
    let onRetryConflict: (ReplayConflict) async -> Void
    let onRetryAll: () async -> Void

    @State private var retryingIDs: Set<UUID> = []
    @State private var isRetryingAll = false

    var body: some View {
        NavigationStack {
            Group {
                if conflicts.isEmpty {
                    emptyState
                } else {
                    conflictList
                }
            }
            .navigationTitle(String(localized: "Sync conflicts", bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar { toolbarContent }
        }
    }

    // MARK: - Sub-views

    private var emptyState: some View {
        VStack(spacing: BrevSpacing.md) {
            Image(systemName: "checkmark.circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.success.color)
                .font(.system(size: 48))
            Text("All conflicts resolved", bundle: .module)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
            Text("There are no outstanding sync conflicts for this account.", bundle: .module)
                .brevFont(.body)
                .foregroundStyle(theme.textSecondary.color)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrevSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var conflictList: some View {
        List {
            Section {
                SettingsInfoCallout(
                    symbolName: "exclamationmark.triangle",
                    message: String(
                        localized: "These changes couldn't be applied to the server. Dismiss individual conflicts once you've reviewed them, or dismiss all to clear the list.",
                        bundle: .module
                    ),
                    tone: .warning
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            ForEach(conflicts) { conflict in
                ConflictRow(
                    conflict: conflict,
                    isRetrying: retryingIDs.contains(conflict.id),
                    onDismiss: {
                        Task { @MainActor in await dismissSingle(conflict) }
                    },
                    onRetry: {
                        Task { @MainActor in await retrySingle(conflict) }
                    }
                )
                .listRowBackground(theme.bgSecondary.color)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(String(localized: "Done", bundle: .module)) { dismiss() }
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    Task { @MainActor in await dismissAll() }
                } label: {
                    Label(String(localized: "Dismiss all", bundle: .module), systemImage: "trash")
                }
                .disabled(conflicts.isEmpty)

                Divider()

                Button {
                    Task { @MainActor in await retryAll() }
                } label: {
                    Label(
                        isRetryingAll ? String(localized: "Retrying…", bundle: .module) : String(
                            localized: "Retry all",
                            bundle: .module
                        ),
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(isRetryingAll)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.accent.color)
            }
            .accessibilityLabel(String(localized: "Conflict actions", bundle: .module))
        }
    }

    // MARK: - Actions

    private func dismissSingle(_ conflict: ReplayConflict) async {
        conflicts.removeAll { $0.id == conflict.id }
        await onDismissConflict(conflict)
    }

    private func dismissAll() async {
        conflicts.removeAll()
        await onDismissAll()
    }

    private func retrySingle(_ conflict: ReplayConflict) async {
        retryingIDs.insert(conflict.id)
        defer { retryingIDs.remove(conflict.id) }
        await onRetryConflict(conflict)
        conflicts.removeAll { $0.id == conflict.id }
    }

    private func retryAll() async {
        isRetryingAll = true
        defer { isRetryingAll = false }
        await onRetryAll()
    }
}

// MARK: - Conflict row

private struct ConflictRow: View {
    @Environment(\.brevTheme) private var theme
    let conflict: ReplayConflict
    let isRetrying: Bool
    let onDismiss: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                    Text(conflict.operationDescription)
                        .brevFont(.subheadline)
                        .foregroundStyle(theme.textPrimary.color)
                        .lineLimit(2)
                    Text(conflict.folderName)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                HStack(spacing: BrevSpacing.xxs) {
                    Button {
                        onRetry()
                    } label: {
                        Image(systemName: isRetrying ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(theme.accent.color)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRetrying)
                    .accessibilityLabel(String(localized: "Retry conflict: \(conflict.operationDescription)", bundle: .module))

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(theme.textTertiary.color)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Dismiss conflict: \(conflict.operationDescription)", bundle: .module))
                }
            }

            Text(conflict.failureReason)
                .brevFont(.caption)
                .foregroundStyle(theme.warning.color)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
        }
        .padding(.vertical, BrevSpacing.xs)
    }
}
