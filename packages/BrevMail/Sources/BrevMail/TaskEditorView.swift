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

/// The task editor sheet (ADR-0072 #12).
///
/// Create and edit share one form: title, notes, due date, status, and
/// the target list picker (writable collections only). Saves go through
/// TasksEditingModel so capability checks, provider dispatch, and
/// conflict errors stay off the view.
public struct TaskEditorView: View {
    @Environment(\.brevTheme) private var theme

    @State private var draft: TaskDraft
    @State private var includesDueDate: Bool
    @State private var selectedDueDate: Date
    /// The task being edited; nil on create.
    private let editing: PIMTask?
    private let model: TasksEditingModel
    private let onSaved: () async -> Void
    private let onClose: () -> Void

    /// - Parameters:
    ///   - model: The authoring model; its targets drive the list picker.
    ///   - task: The cached task to edit; nil creates a new task.
    ///   - defaultTargetID: Pre-selected list for a new task.
    ///   - onSaved: Called after a successful save so the caller reloads.
    ///   - onClose: Dismisses the sheet.
    public init(
        model: TasksEditingModel,
        task: PIMTask? = nil,
        defaultTargetID: String? = nil,
        onSaved: @escaping () async -> Void = {},
        onClose: @escaping () -> Void = {}
    ) {
        self.model = model
        editing = task
        self.onSaved = onSaved
        self.onClose = onClose
        var draft = task.map(TaskDraft.init) ?? TaskDraft()
        if task == nil {
            draft.targetID = defaultTargetID ?? model.defaultTarget?.id
        }
        _draft = State(initialValue: draft)
        _includesDueDate = State(initialValue: draft.due != nil)
        _selectedDueDate = State(
            initialValue: draft.due ?? Date().addingTimeInterval(86400)
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            BrevDivider()
            form
            BrevDivider()
            footer
        }
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 460, minHeight: 400, idealHeight: 480)
        #endif
        .background(theme.bgPrimary.color)
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "checklist")
                .foregroundStyle(theme.accent.color)
            Text(
                editing == nil ? "New Task" : "Edit Task",
                bundle: .module
            )
            .brevFont(.headline)
            .foregroundStyle(theme.textPrimary.color)
            Spacer()
            BrevIconButton(
                systemName: "xmark.circle.fill",
                accessibilityLabel: "Close",
                bundle: .module,
                iconSize: 18
            ) {
                onClose()
            }
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                fieldGroup(String(localized: "Title", bundle: .module)) {
                    TextField(
                        String(localized: "Task title", bundle: .module),
                        text: $draft.title
                    )
                    .textFieldStyle(.roundedBorder)
                }

                fieldGroup(String(localized: "List", bundle: .module)) {
                    Picker(
                        String(localized: "List", bundle: .module),
                        selection: $draft.targetID
                    ) {
                        ForEach(model.targets) { target in
                            Text(target.title).tag(target.id as String?)
                        }
                    }
                    .labelsHidden()
                }

                fieldGroup(String(localized: "Status", bundle: .module)) {
                    Picker(
                        String(localized: "Status", bundle: .module),
                        selection: $draft.status
                    ) {
                        ForEach(PIMTaskStatus.allCases, id: \.self) { status in
                            Text(statusTitle(status)).tag(status)
                        }
                    }
                    .labelsHidden()
                    #if os(macOS)
                        .pickerStyle(.segmented)
                    #endif
                }

                fieldGroup(String(localized: "Due Date", bundle: .module)) {
                    Toggle(
                        String(localized: "Add due date", bundle: .module),
                        isOn: $includesDueDate
                    )
                    .onChange(of: includesDueDate) { _, newValue in
                        draft.due = newValue ? selectedDueDate : nil
                    }
                    if includesDueDate {
                        DatePicker(
                            String(localized: "Due date", bundle: .module),
                            selection: $selectedDueDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .onChange(of: selectedDueDate) { _, newValue in
                            draft.due = newValue
                        }
                    }
                }

                fieldGroup(String(localized: "Notes", bundle: .module)) {
                    TextEditor(text: $draft.notes)
                        .font(.body)
                        .foregroundStyle(theme.textPrimary.color)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(BrevSpacing.xs)
                        .background(theme.bgSecondary.color)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: BrevRadius.sm,
                                style: .continuous
                            )
                        )
                }

                if let lastError = model.lastError {
                    BrevInlineStatus(message: lastError, tone: .danger)
                }
            }
            .padding(BrevSpacing.md)
        }
    }

    private var footer: some View {
        HStack(spacing: BrevSpacing.sm) {
            Spacer()
            BrevButton("Cancel", style: .secondary, bundle: .module) {
                onClose()
            }
            .keyboardShortcut(.cancelAction)
            BrevButton(
                editing == nil ? "Create Task" : "Save",
                style: .primary,
                bundle: .module
            ) {
                Task { await save() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(
                model.isSaving || !draft.isSaveEnabled
                    || draft.targetID == nil
            )
        }
        .padding(BrevSpacing.md)
    }

    private func statusTitle(_ status: PIMTaskStatus) -> String {
        switch status {
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

    private func fieldGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Text(title)
                .brevFont(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.textSecondary.color)
            content()
        }
    }

    private func save() async {
        do {
            if let editing {
                _ = try await model.update(draft, for: editing)
            } else {
                _ = try await model.create(draft)
            }
            await onSaved()
            onClose()
        } catch {
            // The model carries the displayable error.
        }
    }
}
