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

import BrevCalendar
import BrevDesign
import BrevThemes
import SwiftUI

/// The read-only task detail pane (ADR-0072 #12).
///
/// Shows the synced record's fields plus provenance (source, list,
/// provider version) and the Copy Link / Edit / Delete affordances
/// when wired. The view never issues provider requests.
public struct TaskDetailView: View {
    @Environment(\.brevTheme) private var theme

    let task: PIMTask
    let collection: PIMCollection?
    let source: PIMSource?
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    public init(
        task: PIMTask,
        collection: PIMCollection? = nil,
        source: PIMSource? = nil,
        onEdit: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.task = task
        self.collection = collection
        self.source = source
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                header
                BrevDivider()
                fields
                provenance
            }
            .padding(BrevSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.bgPrimary.color)
    }

    private var header: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(
                systemName: task.isCompleted
                    ? "checkmark.circle.fill" : "circle"
            )
            .foregroundStyle(
                task.isCompleted
                    ? theme.success.color : theme.textTertiary.color
            )
            .accessibilityHidden(true)
            Text(task.title ?? String(
                localized: "Untitled task", bundle: .module
            ))
            .brevFont(.title)
            .foregroundStyle(theme.textPrimary.color)
            .strikethrough(task.isCompleted)
            Spacer()
            if let url = PIMDeepLinkPolicy.url(forTaskID: task.id) {
                BrevIconButton(
                    systemName: "link",
                    accessibilityLabel: "Copy link",
                    bundle: .module
                ) {
                    PIMDeepLinkCopy.copy(url)
                }
            }
            if let onEdit {
                BrevIconButton(
                    systemName: "pencil",
                    accessibilityLabel: "Edit task",
                    bundle: .module
                ) {
                    onEdit()
                }
            }
            if let onDelete {
                BrevIconButton(
                    systemName: "trash",
                    accessibilityLabel: "Delete task",
                    bundle: .module
                ) {
                    onDelete()
                }
            }
        }
    }

    @ViewBuilder
    private var fields: some View {
        field(String(localized: "Status", bundle: .module)) {
            Text(statusText)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
        }
        if let due = task.due {
            field(String(localized: "Due", bundle: .module)) {
                Text(due.formatted(date: .abbreviated, time: .shortened))
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
            }
        }
        if let completedAt = task.completedAt {
            field(String(localized: "Completed", bundle: .module)) {
                Text(
                    completedAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
            }
        }
        if let notes = task.notes,
           !notes.trimmingCharacters(in: .whitespacesAndNewlines)
           .isEmpty {
            field(String(localized: "Notes", bundle: .module)) {
                Text(notes)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
                    .textSelection(.enabled)
            }
        }
        ForEach(task.links, id: \.self) { link in
            field(String(localized: "Link", bundle: .module)) {
                Text(link)
                    .brevFont(.caption)
                    .foregroundStyle(theme.accent.color)
                    .textSelection(.enabled)
            }
        }
    }

    private var statusText: String {
        switch task.status {
        case .needsAction:
            String(localized: "Needs action", bundle: .module)
        case .inProcess:
            String(localized: "In progress", bundle: .module)
        case .completed:
            String(localized: "Completed", bundle: .module)
        case .cancelled:
            String(localized: "Cancelled", bundle: .module)
        }
    }

    private var provenance: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            BrevDivider()
            if let collection {
                Text(collection.displayName)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            }
            if let source {
                Text(source.displayName)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
            }
        }
    }

    private func field<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            Text(title)
                .brevFont(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.textSecondary.color)
            content()
        }
    }
}
