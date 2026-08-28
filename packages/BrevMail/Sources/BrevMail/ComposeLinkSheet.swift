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

/// Input passed into `ComposeLinkSheet` from the compose toolbar.
///
/// Pre-fill is derived from the current selection in the text view: if text is
/// selected and an existing `.link` attribute is present, both fields are
/// pre-populated; if only text is selected, the display text is pre-filled.
struct ComposeLinkSheetInput: Identifiable {
    /// Unique instance ID so `sheet(item:)` can distinguish successive presentations.
    let id = UUID()
    /// Text to pre-fill in the URL field; empty means the field starts blank.
    var urlString: String
    /// Text to pre-fill in the display-text field; empty means use the URL as display text.
    var displayText: String
    /// Whether a link already exists at the selection (enabling the Remove button).
    var hasExistingLink: Bool
}

/// The sheet presented when the user clicks the "Insert Link" toolbar button.
///
/// Validates the URL via `ComposeLinkPolicy.normalizedURL(from:)` and calls
/// `onConfirm` with the normalized URL and display text, or `onRemove` when the
/// user wants to clear an existing link.
struct ComposeLinkSheet: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let input: ComposeLinkSheetInput
    /// Called with a valid URL and display text on confirm.
    let onConfirm: (URL, String) -> Void
    /// Called when the user removes an existing link.
    let onRemove: () -> Void

    @State private var urlString: String
    @State private var displayText: String
    @State private var validationError: String?

    init(
        input: ComposeLinkSheetInput,
        onConfirm: @escaping (URL, String) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.input = input
        self.onConfirm = onConfirm
        self.onRemove = onRemove
        _urlString = State(initialValue: input.urlString)
        _displayText = State(initialValue: input.displayText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.lg) {
            Text("Insert Link", bundle: .module)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)

            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                fieldRow(label: "URL") {
                    TextField(String(localized: "https://example.com or email@example.com", bundle: .module), text: $urlString)
                        .textFieldStyle(.plain)
                        .brevFont(.body)
                        .foregroundStyle(theme.textPrimary.color)
                        .onSubmit { attemptConfirm() }
                }

                fieldRow(label: "Display text") {
                    TextField(String(localized: "Optional — uses URL if left blank", bundle: .module), text: $displayText)
                        .textFieldStyle(.plain)
                        .brevFont(.body)
                        .foregroundStyle(theme.textPrimary.color)
                        .onSubmit { attemptConfirm() }
                }

                if let validationError {
                    Text(validationError)
                        .brevFont(.caption)
                        .foregroundStyle(theme.danger.color)
                }
            }

            HStack(spacing: BrevSpacing.sm) {
                if input.hasExistingLink {
                    Button(String(localized: "Remove Link", bundle: .module)) {
                        onRemove()
                        dismiss()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(theme.danger.color)
                }

                Spacer()

                Button(String(localized: "Cancel", bundle: .module)) {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Insert", bundle: .module)) {
                    attemptConfirm()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(BrevSpacing.xl)
        .frame(minWidth: 380)
    }

    private func fieldRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            Text(label)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            content()
                .padding(.horizontal, BrevSpacing.sm)
                .padding(.vertical, BrevSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous)
                        .fill(theme.bgSecondary.color)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous)
                        .stroke(theme.border.color, lineWidth: 1)
                )
        }
    }

    private func attemptConfirm() {
        let raw = urlString.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else {
            validationError = "Please enter a URL."
            return
        }
        guard let url = ComposeLinkPolicy.normalizedURL(from: raw) else {
            validationError = "Enter a valid URL (https://, http://) or email address."
            return
        }
        validationError = nil
        onConfirm(url, displayText)
        dismiss()
    }
}
