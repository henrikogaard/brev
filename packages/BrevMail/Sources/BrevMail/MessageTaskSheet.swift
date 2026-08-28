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

struct MessageTaskSheet: View {
    @Environment(\.brevTheme) private var theme
    @State private var draft: MessageTaskDraft
    @State private var includesDueDate: Bool
    @State private var selectedDueDate: Date
    @State private var isCreating = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private let create: (MessageTaskDraft) async throws -> MessageTaskCreationResult
    private let onClose: () -> Void

    init(
        draft: MessageTaskDraft,
        create: @escaping (MessageTaskDraft) async throws -> MessageTaskCreationResult,
        onClose: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        _includesDueDate = State(initialValue: draft.dueDate != nil)
        _selectedDueDate = State(initialValue: draft.dueDate ?? Date().addingTimeInterval(86400))
        self.create = create
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            BrevDivider()
            form
            BrevDivider()
            footer
        }
        .frame(minWidth: 380, idealWidth: 460, minHeight: 440, idealHeight: 520)
        .background(theme.bgPrimary.color)
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "checklist")
                .foregroundStyle(theme.accent.color)
            Text("Create Task", bundle: .module)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.textTertiary.color)
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                fieldGroup("Title") {
                    TextField(String(localized: "Task title", bundle: .module), text: $draft.title)
                        .textFieldStyle(.roundedBorder)
                }

                fieldGroup("Target") {
                    Picker(String(localized: "Target", bundle: .module), selection: $draft.target) {
                        ForEach(MessageTaskCreationTarget.allCases, id: \.self) { target in
                            Text(target.title).tag(target)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                fieldGroup("Due Date") {
                    Toggle(String(localized: "Add due date", bundle: .module), isOn: $includesDueDate)
                        .onChange(of: includesDueDate) { _, newValue in
                            draft.dueDate = newValue ? selectedDueDate : nil
                        }
                    if includesDueDate {
                        DatePicker(
                            String(localized: "Due date", bundle: .module),
                            selection: $selectedDueDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .onChange(of: selectedDueDate) { _, newValue in
                            draft.dueDate = newValue
                        }
                    }
                }

                fieldGroup("Notes") {
                    TextEditor(text: $draft.notes)
                        .font(.body)
                        .foregroundStyle(theme.textPrimary.color)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 150)
                        .padding(BrevSpacing.xs)
                        .background(theme.bgSecondary.color)
                        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous))
                }

                fieldGroup("Link") {
                    Text(draft.deepLink.absoluteString)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                if let statusMessage {
                    BrevInlineStatus(message: statusMessage, tone: .success)
                }
                if let errorMessage {
                    BrevInlineStatus(message: errorMessage, tone: .danger)
                }
            }
            .padding(BrevSpacing.md)
        }
    }

    private var footer: some View {
        HStack(spacing: BrevSpacing.sm) {
            if draft.target == .systemShare {
                ShareLink(item: MessageTaskSharePayload.text(for: draft)) {
                    Label(String(localized: "Share", bundle: .module), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            BrevButton("Cancel", style: .secondary) {
                onClose()
            }
            BrevButton(createButtonTitle, style: .primary) {
                Task { await createTask() }
            }
            .disabled(isCreating || !draft.isCreateEnabled || draft.target != .appleReminders)
        }
        .padding(BrevSpacing.md)
    }

    private var createButtonTitle: String {
        isCreating ? "Creating..." : "Create Task"
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

    private func createTask() async {
        isCreating = true
        errorMessage = nil
        statusMessage = nil
        do {
            let result = try await create(draft)
            statusMessage = result.message
        } catch {
            errorMessage = MessageTaskSheetPresentation.errorMessage(for: error)
        }
        isCreating = false
    }
}

enum MessageTaskSheetPresentation {
    static func errorMessage(for error: any Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Couldn't create this task." : "Couldn't create this task: \(message)"
    }
}

struct MessageTaskUnavailableSheet: View {
    @Environment(\.brevTheme) private var theme
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            HStack(spacing: BrevSpacing.sm) {
                Image(systemName: "checklist")
                    .foregroundStyle(theme.textTertiary.color)
                Text("Create Task", bundle: .module)
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.textTertiary.color)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }
            BrevInlineStatus(
                message: "Open the message again before creating a task.",
                tone: .info
            )
            BrevButton("Close", style: .secondary) {
                onClose()
            }
        }
        .padding(BrevSpacing.md)
        .frame(minWidth: 340, idealWidth: 400)
        .background(theme.bgPrimary.color)
    }
}
