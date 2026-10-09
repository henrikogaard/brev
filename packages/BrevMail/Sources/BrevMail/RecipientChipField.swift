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
/// field and commits with Return, comma, semicolon, or by moving focus
/// away (e.g. clicking Subject or Send). A space commits only once the
/// text already looks like an email address — the iOS keyboard
/// capitalises/autocorrects partial input (e.g. "He") and appends a
/// space, which would otherwise commit a bogus chip. Addresses that
/// don't look like valid email are tinted so the mistake is visible
/// before sending.
struct RecipientChipField<Accessory: View>: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let label: String
    let labelWidth: CGFloat
    @Binding var recipients: [String]
    @Binding var inputText: String
    let suggestions: [RecipientAutocompleteSuggestion]
    let onInputTextChanged: (String) -> Void
    let onSuggestionSelected: (RecipientAutocompleteSuggestion) -> Void
    let trailingAccessory: Accessory
    /// Compose-level focus, so the container can focus this field when the
    /// sheet opens and move on from it with Return. Nil outside compose.
    let focusedField: FocusState<ComposeFocusField?>.Binding?
    let field: ComposeFocusField
    let onSubmit: (() -> Void)?
    @FocusState private var ownFocus: Bool
    /// Escape hides the suggestion list once; typing again reopens it.
    @State private var suggestionsDismissed = false

    init(
        label: String,
        labelWidth: CGFloat = 48,
        recipients: Binding<[String]>,
        inputText: Binding<String>,
        suggestions: [RecipientAutocompleteSuggestion] = [],
        onInputTextChanged: @escaping (String) -> Void = { _ in },
        onSuggestionSelected: @escaping (RecipientAutocompleteSuggestion) -> Void = { _ in },
        focusedField: FocusState<ComposeFocusField?>.Binding? = nil,
        field: ComposeFocusField = .to,
        onSubmit: (() -> Void)? = nil,
        @ViewBuilder trailingAccessory: () -> Accessory
    ) {
        self.focusedField = focusedField
        self.field = field
        self.onSubmit = onSubmit
        self.label = label
        self.labelWidth = labelWidth
        self.suggestions = suggestions
        self.onInputTextChanged = onInputTextChanged
        self.onSuggestionSelected = onSuggestionSelected
        self.trailingAccessory = trailingAccessory()
        _recipients = recipients
        _inputText = inputText
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                    labelView
                    fieldContent
                    trailingAccessory
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: BrevSpacing.sm) {
                    labelView
                        .frame(width: labelWidth, alignment: .trailing)
                    fieldContent
                    trailingAccessory
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { setFocused() }
    }

    private var isFocused: Bool {
        if let focusedField { return focusedField.wrappedValue == field }
        return ownFocus
    }

    private func setFocused() {
        if let focusedField {
            focusedField.wrappedValue = field
        } else {
            ownFocus = true
        }
    }

    private var labelView: some View {
        // One shared label column with the other compose header rows
        // (From/Subject via ComposeView.fieldRow): same type, colour,
        // width, trailing alignment and baseline alignment.
        ComposeFieldLabel(label)
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
                    .modifier(RecipientFocusModifier(own: $ownFocus, external: focusedField, field: field))
                    .accessibilityLabel(label)
                    .frame(minWidth: 120)
                    .autocorrectionDisabled()
                #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .submitLabel(onSubmit == nil ? .return : .next)
                #endif
                    .onSubmit {
                        commitInput()
                        onSubmit?()
                    }
                    .onChange(of: inputText) { _, newValue in
                        suggestionsDismissed = false
                        switch RecipientChipFieldPresentation.commitAction(afterTyping: newValue) {
                        case .commit(let text):
                            inputText = text
                            commitInput()
                        case .none:
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
                    // Escape dismisses open suggestions first; with no list
                    // showing it cancels the half-typed text rather than
                    // committing it as a chip.
                    .onExitCommand {
                        if !suggestions.isEmpty, !suggestionsDismissed {
                            suggestionsDismissed = true
                        } else {
                            inputText = ""
                            onInputTextChanged("")
                        }
                    }
                #endif
            }
            if recipients.contains(where: { !RecipientAddressValidator.isLikelyEmailAddress($0) }) {
                Text("Correct or remove the highlighted address before sending.", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.danger.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isFocused, !suggestions.isEmpty, !suggestionsDismissed {
                RecipientSuggestionList(suggestions: suggestions) { suggestion in
                    selectSuggestion(suggestion)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func chip(for address: String) -> some View {
        let isValid = RecipientAddressValidator.isLikelyEmailAddress(address)
        HStack(spacing: BrevSpacing.xxs) {
            Text(address)
                .brevFont(.footnote)
                .foregroundStyle(isValid ? theme.textPrimary.color : theme.danger.color)
                .lineLimit(1)
            BrevIconButton(
                systemName: "xmark.circle.fill",
                accessibilityLabel: "Remove \(address)",
                bundle: .module,
                iconSize: 12
            ) {
                recipients.removeAll { $0 == address }
            }
        }
        .padding(.horizontal, BrevSpacing.sm)
        .padding(.vertical, BrevSpacing.xxs)
        .modifier(RecipientChipAccessibility(address: address, isValid: isValid) {
            recipients.removeAll { $0 == address }
        })
        .background(
            RoundedRectangle(cornerRadius: BrevRadius.sm)
                .fill((isValid ? theme.bgSecondary.color : theme.danger.color).opacity(isValid ? 1 : 0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BrevRadius.sm)
                .stroke(theme.danger.color.opacity(isValid ? 0 : 0.7), lineWidth: 1)
        )
        .help(
            isValid
                ? address
                : String(localized: "\(address) doesn't look like a valid email address", bundle: .module)
        )
    }

    private var recipientPrompt: Text? {
        RecipientChipFieldPresentation.promptText(
            recipientCount: recipients.count
        )
        .map { Text($0) }
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

/// iOS: one VoiceOver stop per recipient, the address, with Remove as a custom
/// action instead of a second focusable button. macOS keeps the button.
private struct RecipientChipAccessibility: ViewModifier {
    let address: String
    let isValid: Bool
    let remove: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(address)
            .accessibilityHint(
                isValid ? "" : String(localized: "\(address) doesn't look like a valid email address", bundle: .module)
            )
            .accessibilityAction(named: Text("Remove \(address)", bundle: .module), remove)
        #else
        content
        #endif
    }
}

/// Routes a recipient text field's focus to the compose-level focus state when
/// one is supplied, otherwise to the field's own.
private struct RecipientFocusModifier: ViewModifier {
    var own: FocusState<Bool>.Binding
    var external: FocusState<ComposeFocusField?>.Binding?
    var field: ComposeFocusField

    @ViewBuilder
    func body(content: Content) -> some View {
        if let external {
            content.focused(external, equals: field)
        } else {
            content.focused(own)
        }
    }
}

extension RecipientChipField where Accessory == EmptyView {
    init(
        label: String,
        labelWidth: CGFloat = 48,
        recipients: Binding<[String]>,
        inputText: Binding<String>,
        suggestions: [RecipientAutocompleteSuggestion] = [],
        onInputTextChanged: @escaping (String) -> Void = { _ in },
        onSuggestionSelected: @escaping (RecipientAutocompleteSuggestion) -> Void = { _ in },
        focusedField: FocusState<ComposeFocusField?>.Binding? = nil,
        field: ComposeFocusField = .to,
        onSubmit: (() -> Void)? = nil
    ) {
        self.init(
            label: label,
            labelWidth: labelWidth,
            recipients: recipients,
            inputText: inputText,
            suggestions: suggestions,
            onInputTextChanged: onInputTextChanged,
            onSuggestionSelected: onSuggestionSelected,
            focusedField: focusedField,
            field: field,
            onSubmit: onSubmit
        ) {
            EmptyView()
        }
    }
}

/// Autocomplete suggestions below a recipient field — full-width rows
/// matching the mail-client pattern rather than floating chips.
struct RecipientSuggestionList: View {
    @Environment(\.brevTheme) private var theme

    let suggestions: [RecipientAutocompleteSuggestion]
    let onSelect: (RecipientAutocompleteSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button {
                    onSelect(suggestion)
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
                    #if os(iOS)
                        .frame(minHeight: 44)
                    #endif
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Add \(suggestion.email)", bundle: .module))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: BrevRadius.sm)
                .fill(theme.bgSecondary.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BrevRadius.sm)
                .stroke(theme.border.color.opacity(0.7), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What to do with the last keystroke in a recipient field. `.commit`
/// carries the input with the separator dropped; `.none` leaves the text
/// as typed.
enum RecipientCommitAction: Equatable {
    case none
    case commit(String)
}

enum RecipientChipFieldPresentation {
    static func promptText(recipientCount: Int) -> String? {
        recipientCount == 0 ? "name@example.com" : nil
    }

    /// Comma and semicolon always commit the preceding text as an
    /// address. A space commits only when the text already looks like an
    /// email address — iOS autocorrection appends spaces after partial
    /// input ("He "), and committing those produced garbage chips.
    static func commitAction(afterTyping newValue: String) -> RecipientCommitAction {
        guard let last = newValue.last else { return .none }
        let text = String(newValue.dropLast())
        switch last {
        case ",", ";":
            return .commit(text)
        case " ":
            return RecipientAddressValidator.isLikelyEmailAddress(text) ? .commit(text) : .none
        default:
            return .none
        }
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
