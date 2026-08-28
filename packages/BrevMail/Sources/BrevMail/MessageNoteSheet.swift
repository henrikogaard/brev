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
                        ? String(localized: "Add Note", bundle: .module)
                        : String(localized: "Edit Note", bundle: .module)
                )
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
                Text(verbatim: header.subject.isEmpty
                    ? String(localized: "No subject", bundle: .module)
                    : header.subject)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.textTertiary.color)
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Close", bundle: .module))
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
                .font(.body)
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
                    if let onDelete {
                        onDelete()
                    } else {
                        onSave("")
                    }
                    onClose()
                }
                .accessibilityHint(String(localized: "Removes the local note from this message", bundle: .module))
            }
            Spacer()
            BrevButton("Cancel", style: .secondary, bundle: .module) {
                onClose()
            }
            BrevButton("Save", style: .primary, bundle: .module) {
                onSave(bodyText)
                onClose()
            }
            .accessibilityHint(String(localized: "Saves the note body to local message workflow state", bundle: .module))
        }
        .padding(BrevSpacing.md)
    }
}
