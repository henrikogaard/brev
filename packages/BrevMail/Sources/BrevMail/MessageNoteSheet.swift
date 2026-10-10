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

struct MessageNoteSheet: View {
    @Environment(\.brevTheme) private var theme
    @State private var bodyText: String

    private let header: MessageHeader
    private let note: LocalMessageNote?
    private let onSave: (String) -> Void
    private let onDelete: (() -> Void)?
    private let onClose: () -> Void

    init(
        header: MessageHeader,
        note: LocalMessageNote?,
        onSave: @escaping (String) -> Void,
        onDelete: (() -> Void)? = nil,
        onClose: @escaping () -> Void
    ) {
        self.header = header
        self.note = note
        _bodyText = State(initialValue: note?.body ?? "")
        self.onSave = onSave
        self.onDelete = onDelete
        self.onClose = onClose
    }

    var body: some View {
        #if os(iOS)
        nativeBody
        #else
        desktopBody
        #endif
    }

    private var subjectText: String {
        header.subject.isEmpty ? String(localized: "noSubject.plain", bundle: .module) : header.subject
    }

    #if os(iOS)
    /// iOS: a standard form sheet with Cancel / Save in the navigation bar.
    private var nativeBody: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $bodyText)
                        .brevFont(.body)
                        .foregroundStyle(theme.textPrimary.color)
                        .frame(minHeight: 180)
                        .accessibilityLabel(String(localized: "Note body", bundle: .module))
                        .brevSheetRow()
                } header: {
                    Text(verbatim: subjectText)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                        .textCase(nil)
                        .lineLimit(2)
                }

                if note != nil {
                    Section {
                        Button(role: .destructive) {
                            deleteNote()
                        } label: {
                            Text("Delete Note", bundle: .module)
                                .foregroundStyle(theme.danger.color)
                        }
                        .accessibilityHint(
                            String(localized: "Removes the local note from this message", bundle: .module)
                        )
                        .brevSheetRow()
                    }
                }
            }
            .navigationTitle(
                note == nil
                    ? Text("addNote.action", bundle: .module)
                    : Text("editNote.action", bundle: .module)
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onClose()
                    } label: {
                        Text("Cancel", bundle: .module)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(bodyText)
                        onClose()
                    } label: {
                        Text("Save", bundle: .module)
                    }
                    .accessibilityHint(
                        String(localized: "Saves the note body to local message workflow state", bundle: .module)
                    )
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    #endif

    private func deleteNote() {
        if let onDelete {
            onDelete()
        } else {
            onSave("")
        }
        onClose()
    }

    #if os(macOS)
    private var desktopBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            BrevDivider()
            form
            BrevDivider()
            footer
        }
        .frame(minWidth: 380, idealWidth: 460, minHeight: 340, idealHeight: 420)
        .background(theme.bgPrimary.color)
        .presentationDetents([.medium, .large])
    }

    private var headerView: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: note == nil ? "note.text.badge.plus" : "note.text")
                .foregroundStyle(theme.accent.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    note == nil
                        ? String(localized: "addNote.action", bundle: .module)
                        : String(localized: "editNote.action", bundle: .module)
                )
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
                Text(verbatim: subjectText)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .lineLimit(1)
            }
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
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Text("Note", bundle: .module)
                .brevFont(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.textSecondary.color)
            TextEditor(text: $bodyText)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 180)
                .padding(BrevSpacing.xs)
                .background(theme.bgSecondary.color)
                .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous))
                .accessibilityLabel(String(localized: "Note body", bundle: .module))
        }
        .padding(BrevSpacing.md)
    }

    private var footer: some View {
        HStack(spacing: BrevSpacing.sm) {
            if note != nil {
                BrevButton("Delete Note", style: .secondary, bundle: .module) {
                    deleteNote()
                }
                .accessibilityHint(String(localized: "Removes the local note from this message", bundle: .module))
            }
            Spacer()
            BrevButton("Cancel", style: .secondary, bundle: .module) {
                onClose()
            }
            .keyboardShortcut(.cancelAction)
            BrevButton("Save", style: .primary, bundle: .module) {
                onSave(bodyText)
                onClose()
            }
            .accessibilityHint(String(localized: "Saves the note body to local message workflow state", bundle: .module))
        }
        .padding(BrevSpacing.md)
    }
    #endif
}
