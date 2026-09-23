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

/// The Tasks browsing surface (ADR-0072, issue #12).
///
/// A two-column split: the collection-sectioned task list (searchable,
/// list-filterable, completion-toggleable) on the leading side and the
/// read-only task detail on the trailing side. On iOS the split
/// collapses into push navigation. All content comes from the local
/// sync cache — the view never issues provider requests on its own;
/// the only provider-adjacent actions are the explicit Sync Now
/// toolbar item and, when an editing model is wired, the New Task /
/// Edit / Delete / complete affordances that run through
/// TasksEditingModel.
public struct TasksRootView: View {
    @Environment(\.brevTheme) private var theme

    @State private var model: TasksBrowsingModel
    /// Task authoring; nil keeps the surface read-only.
    private let editing: TasksEditingModel?
    /// Dismisses the hosting surface (iOS presents the view in a full-screen
    /// cover); nil hides the Done affordance.
    private let onDismiss: (() -> Void)?
    @State private var columnVisibility = NavigationSplitViewVisibility
        .automatic
    /// Drives iOS push navigation onto the detail column on selection.
    @State private var preferredCompactColumn = NavigationSplitViewColumn
        .sidebar
    /// The sheet request: a new task, or an edit of the cached one.
    @State private var editorRequest: EditorRequest?

    /// Identifiable sheet payload for the task editor.
    private enum EditorRequest: Identifiable {
        case create
        case edit(PIMTask)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let task): "edit-\(task.id)"
            }
        }
    }

    /// - Parameter model: The browsing model; the app shell builds it
    ///   over the session's PIM services.
    /// - Parameter editing: The authoring model; pass nil (default) for
    ///   a read-only task list.
    /// - Parameter onDismiss: Dismiss action for a host that presents the
    ///   view modally; nil (default) shows no Done button.
    public init(
        model: TasksBrowsingModel,
        editing: TasksEditingModel? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        _model = State(initialValue: model)
        self.editing = editing
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
            listColumn
                .navigationTitle(
                    String(localized: "Tasks", bundle: .module)
                )
        } detail: {
            detailColumn
        }
        .searchable(
            text: Bindable(model).searchText,
            prompt: String(
                localized: "Search tasks",
                bundle: .module
            )
        )
        .task { await model.load() }
        .task { await editing?.load() }
        .onChange(of: model.selectedTaskID) { _, newValue in
            if newValue != nil {
                preferredCompactColumn = .detail
            }
        }
        .sheet(item: $editorRequest) { request in
            if let editing {
                editorSheet(for: request, editing: editing)
            }
        }
    }

    // MARK: - List column

    private var listColumn: some View {
        VStack(spacing: 0) {
            if !model.staleSources.isEmpty {
                staleBanner
            }
            if let lastError = model.lastError {
                errorBanner(lastError)
            }
            if let lastError = editing?.lastError {
                errorBanner(lastError)
            }
            if let deepLinkNotice = model.deepLinkNotice {
                errorBanner(deepLinkNotice)
            }
            content
        }
        .toolbar { toolbarContent }
        // The sidebar renders ~90pt wide in a small aux window on macOS,
        // which wraps empty-state copy mid-word. Give the column a floor
        // wide enough for the copy and the source list.
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 360)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading, model.tasks.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(
                    String(localized: "Loading tasks", bundle: .module)
                )
        } else if !model.hasSources {
            emptyState(
                symbol: "checklist",
                title: String(
                    localized: "No tasks sources connected",
                    bundle: .module
                ),
                message: String(
                    localized:
                    "Connect a tasks source in Settings → Calendar & Contacts to see tasks here.",
                    bundle: .module
                )
            )
        } else if model.sections.isEmpty {
            emptyState(
                symbol: "checklist",
                title: String(
                    localized: "No tasks",
                    bundle: .module
                ),
                message: model.searchText.isEmpty
                    ? String(
                        localized:
                        "Synced tasks will appear here. Use Sync Now to refresh the cache.",
                        bundle: .module
                    )
                    : String(
                        localized: "No tasks match your search.",
                        bundle: .module
                    )
            )
        } else {
            TasksListView(
                sections: model.sections,
                selectedTaskID: Bindable(model).selectedTaskID,
                onToggleCompleted: toggleAction
            )
        }
    }

    /// The completion toggle for list rows — present only while an
    /// editing model is wired; per-task writability is checked inside.
    private var toggleAction: ((PIMTask) -> Void)? {
        guard editing != nil else { return nil }
        return { task in
            Task { await toggleCompleted(task) }
        }
    }

    private func toggleCompleted(_ task: PIMTask) async {
        guard let editing, editing.canEdit(task) else { return }
        do {
            _ = try await editing.toggleCompleted(task)
            await model.load()
        } catch {
            // The editing model carries the displayable error.
        }
    }

    // MARK: - Detail column

    @ViewBuilder
    private var detailColumn: some View {
        if let task = model.task(id: model.selectedTaskID) {
            TaskDetailView(
                task: task,
                collection: model.collection(for: task),
                source: model.source(for: task),
                onEdit: editAction(for: task),
                onDelete: deleteAction(for: task)
            )
        } else {
            ContentUnavailableView(
                String(localized: "No task selected", bundle: .module),
                systemImage: "checklist",
                description: Text(String(
                    localized: "Pick a task from the list.",
                    bundle: .module
                ))
            )
            .foregroundStyle(theme.textSecondary.color)
        }
    }

    /// The Edit action for the detail pane — present only while the
    /// task's source is writable.
    private func editAction(for task: PIMTask) -> (() -> Void)? {
        guard let editing, editing.canEdit(task) else { return nil }
        return {
            Task { await presentEditor(for: task) }
        }
    }

    /// The Delete action for the detail pane — same writability gate.
    private func deleteAction(for task: PIMTask) -> (() -> Void)? {
        guard let editing, editing.canEdit(task) else { return nil }
        return {
            Task { await delete(task) }
        }
    }

    /// Refreshes writable targets before presenting so the picker never
    /// offers a stale (or misses a newly enabled) task list.
    private func presentEditor(for task: PIMTask) async {
        await editing?.load()
        editorRequest = .edit(task)
    }

    private func presentNewTask() async {
        await editing?.load()
        editorRequest = .create
    }

    private func delete(_ task: PIMTask) async {
        do {
            try await editing?.delete(task)
            model.selectedTaskID = nil
            await model.load()
        } catch {
            // The editing model carries the displayable error.
        }
    }

    @ViewBuilder
    private func editorSheet(
        for request: EditorRequest,
        editing: TasksEditingModel
    ) -> some View {
        let onSaved: () async -> Void = {
            await editing.load()
            await model.load()
        }
        switch request {
        case .create:
            TaskEditorView(
                model: editing,
                onSaved: onSaved,
                onClose: { editorRequest = nil }
            )
        case .edit(let task):
            TaskEditorView(
                model: editing,
                task: task,
                onSaved: onSaved,
                onClose: { editorRequest = nil }
            )
        }
    }

    // MARK: - Banners

    /// Kept-cache warning: a failed/disconnected/auth-required source
    /// still renders its last snapshot, flagged so the data's age is
    /// never ambiguous (ADR-0072 staleness contract).
    private var staleBanner: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(String(
                    localized: "Showing cached data",
                    bundle: .module
                ))
                .brevFont(.subheadline)
                if let lastSyncAt = model.lastSyncAt {
                    Text(String(
                        localized:
                        "Last updated \(lastSyncAt.formatted(.relative(presentation: .named)))",
                        bundle: .module
                    ))
                    .brevFont(.caption)
                }
            }
            Spacer(minLength: BrevSpacing.sm)
        }
        .foregroundStyle(theme.warning.color)
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .background(theme.bgSecondary.color)
        .accessibilityElement(children: .combine)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "exclamationmark.circle")
                .accessibilityHidden(true)
            Text(message)
                .brevFont(.caption)
            Spacer(minLength: BrevSpacing.sm)
        }
        .foregroundStyle(theme.danger.color)
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .background(theme.bgSecondary.color)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Empty state + toolbar

    private func emptyState(
        symbol: String,
        title: String,
        message: String
    ) -> some View {
        ContentUnavailableView(
            title,
            systemImage: symbol,
            description: Text(message)
        )
        .foregroundStyle(theme.textSecondary.color)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let onDismiss {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Done", bundle: .module), action: onDismiss)
            }
        }
        if !model.allCollections.isEmpty {
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button {
                        model.selectedCollectionID = nil
                    } label: {
                        if model.selectedCollectionID == nil {
                            Label(
                                String(
                                    localized: "All lists",
                                    bundle: .module
                                ),
                                systemImage: "checkmark"
                            )
                        } else {
                            Text(String(
                                localized: "All lists",
                                bundle: .module
                            ))
                        }
                    }
                    ForEach(model.allCollections) { collection in
                        Button {
                            model.selectedCollectionID = collection.id
                        } label: {
                            if model.selectedCollectionID == collection.id {
                                Label(
                                    collection.displayName,
                                    systemImage: "checkmark"
                                )
                            } else {
                                Text(collection.displayName)
                            }
                        }
                    }
                } label: {
                    Label(
                        String(localized: "Filter", bundle: .module),
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }
                .accessibilityLabel(
                    String(
                        localized: "Filter by list",
                        bundle: .module
                    )
                )
            }
            ToolbarItem(placement: .secondaryAction) {
                Toggle(
                    String(localized: "Completed", bundle: .module),
                    isOn: Bindable(model).showsCompleted
                )
                .toggleStyle(.button)
                .accessibilityLabel(
                    String(
                        localized: "Show completed tasks",
                        bundle: .module
                    )
                )
            }
        }
        if let editing,
           editing.canAuthor, editing.defaultTarget != nil {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await presentNewTask() }
                } label: {
                    Label(
                        String(
                            localized: "New Task",
                            bundle: .module
                        ),
                        systemImage: "plus"
                    )
                }
                .accessibilityLabel(
                    String(localized: "New task", bundle: .module)
                )
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await model.syncAll() }
            } label: {
                if model.syncingSourceIDs.isEmpty {
                    Label(
                        String(localized: "Sync Now", bundle: .module),
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .disabled(!model.canSyncAny)
            .accessibilityLabel(
                String(localized: "Sync tasks now", bundle: .module)
            )
        }
    }
}
