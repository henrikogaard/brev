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

/// The collection-sectioned task list inside the Tasks surface
/// (ADR-0072 #12).
///
/// Renders pre-grouped `ListSection`s — already filtered for
/// hidden collections, the list filter, completion visibility, and the
/// local search query — with a completion checkbox, title, and due
/// date per row.
public struct TasksListView: View {
    @Environment(\.brevTheme) private var theme

    /// Collection buckets in display-name order.
    let sections: [TasksBrowsingModel.ListSection]
    /// Selection shared with the detail pane.
    @Binding var selectedTaskID: PIMTask.ID?
    /// Completion toggle — nil renders a read-only checkbox.
    let onToggleCompleted: ((PIMTask) -> Void)?

    public init(
        sections: [TasksBrowsingModel.ListSection],
        selectedTaskID: Binding<PIMTask.ID?>,
        onToggleCompleted: ((PIMTask) -> Void)? = nil
    ) {
        self.sections = sections
        _selectedTaskID = selectedTaskID
        self.onToggleCompleted = onToggleCompleted
    }

    public var body: some View {
        List(selection: $selectedTaskID) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.tasks) { task in
                        TaskRowView(
                            task: task,
                            onToggleCompleted: onToggleCompleted
                        )
                        .tag(task.id)
                    }
                } header: {
                    Text(section.title)
                        .brevFont(.subheadline)
                        .foregroundStyle(theme.textSecondary.color)
                }
            }
        }
        .listStyle(.plain)
        .accessibilityLabel(
            String(localized: "Tasks", bundle: .module)
        )
    }
}

/// One task row — completion checkbox, title, and a secondary line
/// (due date / notes preview). Extracted so the row renders identically
/// in the List and in snapshot fixtures.
public struct TaskRowView: View {
    @Environment(\.brevTheme) private var theme

    let task: PIMTask
    let onToggleCompleted: ((PIMTask) -> Void)?

    public init(
        task: PIMTask,
        onToggleCompleted: ((PIMTask) -> Void)? = nil
    ) {
        self.task = task
        self.onToggleCompleted = onToggleCompleted
    }

    public var body: some View {
        HStack(spacing: BrevSpacing.md) {
            Button {
                onToggleCompleted?(task)
            } label: {
                Image(
                    systemName: task.isCompleted
                        ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(
                    task.isCompleted
                        ? theme.success.color : theme.textTertiary.color
                )
            }
            .buttonStyle(.plain)
            .disabled(onToggleCompleted == nil)
            .accessibilityLabel(
                task.isCompleted
                    ? String(
                        localized: "Mark as not completed",
                        bundle: .module
                    )
                    : String(
                        localized: "Mark as completed",
                        bundle: .module
                    )
            )

            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(task.title ?? String(
                    localized: "Untitled task", bundle: .module
                ))
                .brevFont(.subheadline)
                .foregroundStyle(
                    task.isCompleted
                        ? theme.textSecondary.color
                        : theme.textPrimary.color
                )
                .strikethrough(task.isCompleted)
                .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: BrevSpacing.sm)
            if let due = task.due {
                Text(due.formatted(date: .abbreviated, time: .omitted))
                    .brevFont(.caption)
                    .foregroundStyle(
                        isOverdue
                            ? theme.danger.color
                            : theme.textSecondary.color
                    )
            }
        }
        .padding(.vertical, BrevSpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String? {
        let notes = task.notes?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return notes.isEmpty ? nil : notes
    }

    private var isOverdue: Bool {
        guard let due = task.due, !task.isCompleted else { return false }
        return due < Date()
    }
}
