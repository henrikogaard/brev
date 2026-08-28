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

struct MessageEventSheet: View {
    @Environment(\.brevTheme) private var theme
    @State private var draft: MessageEventDraft
    @State private var isCreating = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private let create: (MessageEventDraft) async throws -> MessageEventCreationResult
    private let onClose: () -> Void

    init(
        draft: MessageEventDraft,
        create: @escaping (MessageEventDraft) async throws -> MessageEventCreationResult,
        onClose: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
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
        .frame(minWidth: 380, idealWidth: 460, minHeight: 460, idealHeight: 560)
        .background(theme.bgPrimary.color)
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "calendar.badge.plus")
                .foregroundStyle(theme.accent.color)
            Text("Create Meeting", bundle: .module)
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
                    TextField(String(localized: "Meeting title", bundle: .module), text: $draft.title)
                        .textFieldStyle(.roundedBorder)
                }

                fieldGroup("Starts") {
                    DatePicker(
                        String(localized: "Starts", bundle: .module),
                        selection: $draft.startDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .onChange(of: draft.startDate) { _, newValue in
                        if draft.endDate < newValue {
                            draft.endDate = newValue.addingTimeInterval(3600)
                        }
                    }
                }

                fieldGroup("Ends") {
                    DatePicker(
                        String(localized: "Ends", bundle: .module),
                        selection: $draft.endDate,
                        in: draft.startDate...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                }

                if !draft.attendees.isEmpty {
                    fieldGroup("Attendees") {
                        Text(draft.attendees.joined(separator: ", "))
                            .brevFont(.caption)
                            .foregroundStyle(theme.textSecondary.color)
                            .textSelection(.enabled)
                    }
                }

                fieldGroup("Notes") {
                    TextEditor(text: $draft.notes)
                        .font(.body)
                        .foregroundStyle(theme.textPrimary.color)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(BrevSpacing.xs)
                        .background(theme.bgSecondary.color)
                        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous))
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
            Spacer()
            BrevButton("Cancel", style: .secondary) {
                onClose()
            }
            BrevButton(isCreating ? "Creating..." : "Create Meeting", style: .primary) {
                Task { await createEvent() }
            }
            .disabled(isCreating || !draft.isCreateEnabled)
        }
        .padding(BrevSpacing.md)
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

    private func createEvent() async {
        isCreating = true
        errorMessage = nil
        statusMessage = nil
        do {
            let result = try await create(draft)
            statusMessage = result.message
        } catch {
            errorMessage = MessageEventSheetPresentation.errorMessage(for: error)
        }
        isCreating = false
    }
}

enum MessageEventSheetPresentation {
    static func errorMessage(for error: any Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Couldn't create this meeting." : "Couldn't create this meeting: \(message)"
    }
}

struct MessageEventUnavailableSheet: View {
    @Environment(\.brevTheme) private var theme
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            HStack(spacing: BrevSpacing.sm) {
                Image(systemName: "calendar.badge.plus")
                    .foregroundStyle(theme.textTertiary.color)
                Text("Create Meeting", bundle: .module)
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
                message: "Open the message again before creating a meeting.",
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
