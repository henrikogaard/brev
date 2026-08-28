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

/// A token-based email address input field. Each confirmed address is
/// rendered as a removable chip; the user types into a trailing text
/// field and commits with Return, comma, semicolon, space, or by moving
/// focus away (e.g. clicking Subject or Send). Addresses that don't look
/// like valid email are tinted so the mistake is visible before sending.
struct RecipientChipField: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let label: String
    let labelWidth: CGFloat
    @Binding var recipients: [String]
    @Binding var inputText: String
    let suggestions: [RecipientAutocompleteSuggestion]
    let onInputTextChanged: (String) -> Void
    let onSuggestionSelected: (RecipientAutocompleteSuggestion) -> Void
    @FocusState private var isFocused: Bool

    init(
        label: String,
        labelWidth: CGFloat = 48,
        recipients: Binding<[String]>,
        inputText: Binding<String>,
        suggestions: [RecipientAutocompleteSuggestion] = [],
        onInputTextChanged: @escaping (String) -> Void = { _ in },
        onSuggestionSelected: @escaping (RecipientAutocompleteSuggestion) -> Void = { _ in }
    ) {
        self.label = label
        self.labelWidth = labelWidth
        self.suggestions = suggestions
        self.onInputTextChanged = onInputTextChanged
        self.onSuggestionSelected = onSuggestionSelected
        _recipients = recipients
        _inputText = inputText
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                    labelView
                    fieldContent
                }
            } else {
                HStack(alignment: .top, spacing: BrevSpacing.sm) {
                    labelView
                        .frame(width: labelWidth, alignment: .trailing)
                    fieldContent
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }

    private var labelView: some View {
        Text(label)
            .brevFont(.subheadline)
            .foregroundStyle(theme.textSecondary.color)
            .padding(.top, dynamicTypeSize.isAccessibilitySize ? 0 : BrevSpacing.xs)
    }

    private var fieldContent: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            FlowLayout(spacing: 4) {
                ForEach(recipients, id: \.self) { address in
                    chip(for: address)
                }
                TextField("", text: $inputText, prompt: recipientPrompt)
                    .textFieldStyle(.plain)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
                    .focused($isFocused)
                    .frame(minWidth: 120)
                    .onSubmit { commitInput() }
                    .onChange(of: inputText) { _, newValue in
                        if let last = newValue.last, last == "," || last == ";" || last == " " {
                            inputText = String(newValue.dropLast())
                            commitInput()
                        } else {
                            onInputTextChanged(newValue)
                        }
                    }
                    .onChange(of: isFocused) { _, focused in
                        // Commit a half-typed address when focus leaves the
                        // field (tabbing to Subject, clicking Send) so the
                        // chip — and the send button's enabled state — match
                        // what the user sees.
                        if !focused { commitInput() }
                    }
                #if os(macOS)
                    .onExitCommand { commitInput() }
                #endif
            }
            if isFocused, !suggestions.isEmpty {
                suggestionList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func chip(for address: String) -> some View {
        let isValid = RecipientAddressValidator.isLikelyEmailAddress(address)
        HStack(spacing: 2) {
            Text(address)
                .brevFont(.footnote)
                .foregroundStyle(isValid ? theme.textPrimary.color : theme.danger.color)
                .lineLimit(1)
            Button {
                recipients.removeAll { $0 == address }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary.color)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BrevSpacing.sm)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill((isValid ? theme.bgSecondary.color : theme.danger.color).opacity(isValid ? 1 : 0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.danger.color.opacity(isValid ? 0 : 0.7), lineWidth: 1)
        )
        .help(isValid ? address : "\(address) doesn't look like a valid email address")
    }

    private var recipientPrompt: Text? {
        RecipientChipFieldPresentation.promptText(
            recipientCount: recipients.count
        )
        .map { Text($0) }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button {
                    selectSuggestion(suggestion)
                } label: {
                    HStack(spacing: BrevSpacing.sm) {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(theme.textTertiary.color)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion.title)
                                .brevFont(.subheadline)
                                .foregroundStyle(theme.textPrimary.color)
                                .lineLimit(1)
                            HStack(spacing: BrevSpacing.xs) {
                                Text(suggestion.subtitle)
                                Text(suggestion.sourceLabel)
                            }
                            .brevFont(.caption)
                            .foregroundStyle(theme.textSecondary.color)
                            .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, BrevSpacing.sm)
                    .padding(.vertical, BrevSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Add \(suggestion.email)", bundle: .module))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.bgSecondary.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.border.color.opacity(0.7), lineWidth: 1)
        )
        .frame(maxWidth: 360, alignment: .leading)
    }

    private func selectSuggestion(_ suggestion: RecipientAutocompleteSuggestion) {
        if !recipients.contains(where: { $0.caseInsensitiveCompare(suggestion.email) == .orderedSame }) {
            recipients.append(suggestion.email)
        }
        inputText = ""
        onSuggestionSelected(suggestion)
    }

    private func commitInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Split on commas/semicolons/whitespace in case multiple addresses
        // were pasted at once.
        let addresses = trimmed
            .split(omittingEmptySubsequences: true) { $0 == "," || $0 == ";" || $0.isWhitespace }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for addr in addresses where !recipients.contains(addr) {
            recipients.append(addr)
        }
        inputText = ""
        onInputTextChanged("")
    }
}

enum RecipientChipFieldPresentation {
    static func promptText(recipientCount: Int) -> String? {
        recipientCount == 0 ? "name@example.com" : nil
    }
}

/// Lightweight, deliberately permissive check for "does this look like an
/// email address?" — enough to flag obvious typos (missing `@`, no domain
/// dot) without rejecting valid-but-unusual addresses. Full RFC 5322
/// validation is intentionally out of scope.
enum RecipientAddressValidator {
    static func isLikelyEmailAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let local = parts[0]
        let domain = parts[1]
        guard !local.isEmpty, !domain.isEmpty else { return false }
        guard domain.contains("."),
              !domain.hasPrefix("."),
              !domain.hasSuffix(".") else { return false }
        return !trimmed.contains { $0.isWhitespace }
    }
}
