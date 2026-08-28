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

struct TemplatesSection: View {
    @Environment(\.brevTheme) private var theme
    private static let globalScopeID = "__brev_global_template_scope"

    private let settingsStore: SettingsPersistenceStore
    private let accounts: [BrevAccount]
    @State private var templateSettings: MessageTemplateSettings
    @State private var draftTemplate: MessageTemplate?
    @State private var isEditing = false
    @State private var pendingDeleteID: MessageTemplate.ID?

    init(
        settingsStore: SettingsPersistenceStore = .standard,
        accounts: [BrevAccount] = []
    ) {
        self.settingsStore = settingsStore
        self.accounts = accounts
        _templateSettings = State(initialValue: settingsStore.messageTemplateSettings())
    }

    var body: some View {
        SectionScaffold(
            title: String(localized: "Templates", bundle: .module),
            subtitle: String(localized: "Reusable compose text for repeated replies and common messages.", bundle: .module)
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                templateListGroup
                if isEditing, let draft = draftTemplate {
                    templateEditorGroup(draft: draft)
                }
            }
        }
        .alert(String(localized: "Delete template?", bundle: .module), isPresented: isPendingDeletePresented) {
            Button(String(localized: "Delete", bundle: .module), role: .destructive) { confirmDelete() }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) { pendingDeleteID = nil }
        } message: {
            if let id = pendingDeleteID,
               let name = templateSettings.templates.first(where: { $0.id == id })?.name {
                Text("Delete \"\(name)\"?", bundle: .module)
            } else {
                Text("Delete this template?", bundle: .module)
            }
        }
    }

    // MARK: - Template list

    private var templateListGroup: some View {
        SettingsGroup(
            title: String(localized: "Saved templates", bundle: .module),
            subtitle: String(localized: "Templates appear in the compose toolbar for quick insertion.", bundle: .module),
            symbolName: "doc.text"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                if templateSettings.templates.isEmpty {
                    Text("No templates yet. Add one to speed up repetitive replies.", bundle: .module)
                        .brevFont(.body)
                        .foregroundStyle(theme.textSecondary.color)
                } else {
                    VStack(spacing: BrevSpacing.xs) {
                        ForEach(templateSettings.templates) { template in
                            TemplateRow(
                                template: template,
                                scopeTitle: scopeTitle(for: template.accountID),
                                onPin: { togglePin(template.id) },
                                onMoveUp: { moveTemplate(template.id, direction: .up) },
                                onMoveDown: { moveTemplate(template.id, direction: .down) },
                                canMoveUp: templateSettings.canMoveTemplate(id: template.id, direction: .up),
                                canMoveDown: templateSettings.canMoveTemplate(id: template.id, direction: .down),
                                onEdit: { startEditing(template) },
                                onDelete: { pendingDeleteID = template.id }
                            )
                        }
                    }
                }

                HStack(spacing: BrevSpacing.sm) {
                    BrevButton(String(localized: "New template", bundle: .module), style: .secondary) { startNewTemplate() }
                        .disabled(isEditing)
                    Spacer(minLength: 0)
                }

                SettingsInfoCallout(
                    symbolName: "info.circle",
                    message: String(
                        localized: "Templates are local to this device. Provider-native templates are a future roadmap item.",
                        bundle: .module
                    ),
                    tone: .info
                )
            }
        }
    }

    // MARK: - Template editor

    @ViewBuilder
    private func templateEditorGroup(draft: MessageTemplate) -> some View {
        let editorTitle = draftTemplate?.name.isEmpty == false
            ? String(localized: "Edit \"\(draft.name)\"", bundle: .module)
            : String(localized: "New template", bundle: .module)
        SettingsGroup(
            title: editorTitle,
            subtitle: String(localized: "Give the template a name, optional account scope, and body.", bundle: .module),
            symbolName: "square.and.pencil"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                editorFieldLabel(
                    title: String(localized: "Name", bundle: .module),
                    subtitle: String(localized: "Shown in the compose picker.", bundle: .module)
                )
                TextField(String(localized: "Template name", bundle: .module), text: Binding(
                    get: { draftTemplate?.name ?? "" },
                    set: { draftTemplate?.name = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                editorFieldLabel(
                    title: String(localized: "Scope", bundle: .module),
                    subtitle: String(localized: "Global templates appear for every account.", bundle: .module)
                )
                Picker(String(localized: "Scope", bundle: .module), selection: templateScopeBinding) {
                    Text("All accounts", bundle: .module).tag(Self.globalScopeID)
                    ForEach(accounts) { account in
                        Text(account.displayName.isEmpty ? account.emailAddress : account.displayName)
                            .tag(account.id)
                    }
                    if let accountID = draftTemplate?.accountID,
                       !accounts.contains(where: { $0.id == accountID }) {
                        Text("Account scoped", bundle: .module).tag(accountID)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                editorFieldLabel(
                    title: String(localized: "Subject (optional)", bundle: .module),
                    subtitle: String(localized: "Pre-fills the subject line when inserting.", bundle: .module)
                )
                TextField(String(localized: "Subject line (optional)", bundle: .module), text: Binding(
                    get: { draftTemplate?.subject ?? "" },
                    set: { draftTemplate?.subject = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)

                editorFieldLabel(
                    title: String(localized: "Body", bundle: .module),
                    subtitle: String(localized: "Plain text. Leave blank for subject-only templates.", bundle: .module)
                )
                TextEditor(text: Binding(
                    get: { draftTemplate?.body ?? "" },
                    set: { draftTemplate?.body = $0 }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: BrevRadius.sm)
                        .stroke(theme.border.color, lineWidth: 1)
                )

                HStack(spacing: BrevSpacing.sm) {
                    BrevButton(String(localized: "Save", bundle: .module), style: .primary) { saveTemplate() }
                        .disabled(draftTemplate?.name.isEmpty == true)
                    BrevButton(String(localized: "Cancel", bundle: .module), style: .tertiary) { cancelEditing() }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Private helpers

    @ViewBuilder
    private func editorFieldLabel(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
            Text(subtitle)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
        }
    }

    private var isPendingDeletePresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteID != nil },
            set: { if !$0 { pendingDeleteID = nil } }
        )
    }

    private func startNewTemplate() {
        draftTemplate = MessageTemplate(name: "", body: "")
        isEditing = true
    }

    private func startEditing(_ template: MessageTemplate) {
        draftTemplate = template
        isEditing = true
    }

    private func saveTemplate() {
        guard var draft = draftTemplate, !draft.name.isEmpty else { return }
        // Trim empty subject to nil.
        if draft.subject?.isEmpty == true { draft.subject = nil }
        if templateSettings.templates.contains(where: { $0.id == draft.id }) {
            templateSettings.update(draft)
        } else {
            templateSettings.add(draft)
        }
        settingsStore.save(templateSettings)
        draftTemplate = nil
        isEditing = false
    }

    private func cancelEditing() {
        draftTemplate = nil
        isEditing = false
    }

    private func togglePin(_ id: MessageTemplate.ID) {
        templateSettings.togglePin(id: id)
        settingsStore.save(templateSettings)
    }

    private func moveTemplate(
        _ id: MessageTemplate.ID,
        direction: MessageTemplateMoveDirection
    ) {
        templateSettings.moveTemplate(id: id, direction: direction)
        settingsStore.save(templateSettings)
    }

    private func confirmDelete() {
        guard let id = pendingDeleteID else { return }
        templateSettings.remove(id: id)
        settingsStore.save(templateSettings)
        pendingDeleteID = nil
    }

    private var templateScopeBinding: Binding<String> {
        Binding(
            get: {
                draftTemplate?.accountID ?? Self.globalScopeID
            },
            set: { newValue in
                draftTemplate?.accountID = newValue == Self.globalScopeID ? nil : newValue
            }
        )
    }

    private func scopeTitle(for accountID: String?) -> String {
        guard let accountID else { return String(localized: "All accounts", bundle: .module) }
        guard let account = accounts.first(where: { $0.id == accountID }) else {
            return String(localized: "Account scoped", bundle: .module)
        }
        if account.displayName.isEmpty {
            return account.emailAddress
        }
        return "\(account.displayName) · \(account.emailAddress)"
    }
}

// MARK: - Row

private struct TemplateRow: View {
    @Environment(\.brevTheme) private var theme
    let template: MessageTemplate
    let scopeTitle: String
    let onPin: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: template.isPinned ? "pin.fill" : "pin")
                .foregroundStyle(template.isPinned ? theme.accent.color : theme.textTertiary.color)
                .font(.system(size: 12))
                .onTapGesture { onPin() }

            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textPrimary.color)
                Text(scopeTitle)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                if let subject = template.subject {
                    Text("Subject: \(subject)", bundle: .module)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                }
                Text(template.body.prefix(60).description + (template.body.count > 60 ? "…" : ""))
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onMoveUp()
            } label: {
                Label(String(localized: "Move Template Up", bundle: .module), systemImage: "chevron.up")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveUp)
            .help(String(localized: "Move template up", bundle: .module))

            Button {
                onMoveDown()
            } label: {
                Label(String(localized: "Move Template Down", bundle: .module), systemImage: "chevron.down")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveDown)
            .help(String(localized: "Move template down", bundle: .module))

            BrevButton(String(localized: "Edit", bundle: .module), style: .tertiary) { onEdit() }
            BrevButton(String(localized: "Delete", bundle: .module), style: .tertiary) { onDelete() }
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .background(theme.bgSecondary.color)
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
    }
}
