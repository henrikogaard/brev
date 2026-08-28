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

// MARK: - Server rule editor

/// Sheet-based editor for `ServerRule`.
///
/// The editor is intentionally non-modal: a single sheet contains a
/// list of conditions, a list of actions, and a name/enabled field at
/// the top. The sheet saves via the `ServerRuleManaging` extension
/// service and re-fetches the rule list on success.
public struct ServerRuleEditorView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ServerRuleEditorDraft
    @State private var folders: [Folder] = []
    @State private var isLoadingFolders = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var hasFetchedFolders = false

    private let backend: any MailBackend
    private let onSave: (ServerRule) -> Void
    private let onClose: () -> Void

    public init(
        draft: ServerRuleEditorDraft,
        backend: any MailBackend,
        onSave: @escaping (ServerRule) -> Void,
        onClose: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        self.backend = backend
        self.onSave = onSave
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            Form {
                identitySection
                conditionsSection
                actionsSection
                if let saveError {
                    Section {
                        SettingsInfoCallout(
                            symbolName: "exclamationmark.triangle",
                            message: saveError,
                            tone: .warning
                        )
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(BrevWindowSurfaceBackground(role: .content).ignoresSafeArea())
            .navigationTitle(draft.isNew ? String(localized: "New server rule", bundle: .module) : String(
                localized: "Edit server rule",
                bundle: .module
            ))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { onClose() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? String(localized: "Saving…", bundle: .module) : String(
                        localized: "Save",
                        bundle: .module
                    )) {
                        Task { await save() }
                    }
                    .disabled(!draft.canSave || isSaving)
                }
            }
            .task { await loadFoldersIfNeeded() }
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    private var identitySection: some View {
        Section(String(localized: "Rule", bundle: .module)) {
            TextField(String(localized: "Rule name", bundle: .module), text: $draft.name)
                .textFieldStyle(.roundedBorder)
            Toggle(String(localized: "Enabled", bundle: .module), isOn: $draft.isEnabled)
        }
    }

    private var conditionsSection: some View {
        Section(String(localized: "Conditions", bundle: .module)) {
            if draft.conditions.isEmpty {
                Text("Add at least one condition, or leave empty to match every message.", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
            }
            ForEach(Array(draft.conditions.enumerated()), id: \.offset) { index, _ in
                conditionRow(at: index)
            }
            BrevButton(String(localized: "Add condition", bundle: .module), style: .tertiary) {
                draft.conditions.append(.subjectContains(""))
            }
        }
    }

    private func conditionRow(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            HStack {
                Picker(String(localized: "Type", bundle: .module), selection: conditionKindBinding(at: index)) {
                    ForEach(ServerRuleEditorDraft.ConditionKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .labelsHidden()
                Spacer(minLength: BrevSpacing.sm)
                BrevButton(String(localized: "Remove", bundle: .module), style: .destructive) {
                    draft.conditions.remove(at: index)
                }
            }
            if conditionKind(at: index).requiresValue {
                TextField(String(localized: "Value", bundle: .module), text: conditionValueBinding(at: index))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var actionsSection: some View {
        Section(String(localized: "Actions", bundle: .module)) {
            if draft.actions.isEmpty {
                Text("Add at least one action.", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
            }
            ForEach(Array(draft.actions.enumerated()), id: \.offset) { index, _ in
                actionRow(at: index)
            }
            BrevButton(String(localized: "Add action", bundle: .module), style: .tertiary) {
                draft.actions.append(.markRead)
            }
        }
    }

    private func actionRow(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            HStack {
                Picker(String(localized: "Type", bundle: .module), selection: actionKindBinding(at: index)) {
                    ForEach(ServerRuleEditorDraft.ActionKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .labelsHidden()
                Spacer(minLength: BrevSpacing.sm)
                BrevButton(String(localized: "Remove", bundle: .module), style: .destructive) {
                    draft.actions.remove(at: index)
                }
            }
            if actionKind(at: index) == .moveToFolder {
                if isLoadingFolders {
                    HStack(spacing: BrevSpacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Loading folders…", bundle: .module)
                            .brevFont(.caption)
                            .foregroundStyle(theme.textTertiary.color)
                    }
                } else {
                    Picker(String(localized: "Folder", bundle: .module), selection: actionValueBinding(at: index)) {
                        ForEach(folders) { folder in
                            Text(folder.name).tag(folder.id as String)
                        }
                    }
                    .labelsHidden()
                }
            } else if actionKind(at: index).requiresValue {
                TextField(String(localized: "Value", bundle: .module), text: actionValueBinding(at: index))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Bindings

    private func conditionKind(at index: Int) -> ServerRuleEditorDraft.ConditionKind {
        ServerRuleEditorDraft.conditionKind(for: draft.conditions[index])
    }

    private func conditionKindBinding(at index: Int) -> Binding<ServerRuleEditorDraft.ConditionKind> {
        Binding(
            get: { conditionKind(at: index) },
            set: { newKind in
                draft.conditions[index] = newKind
                    .makeCondition(value: ServerRuleEditorDraft.conditionValue(for: draft.conditions[index]))
            }
        )
    }

    private func conditionValueBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { ServerRuleEditorDraft.conditionValue(for: draft.conditions[index]) },
            set: { newValue in
                let kind = conditionKind(at: index)
                draft.conditions[index] = kind.makeCondition(value: newValue)
            }
        )
    }

    private func actionKind(at index: Int) -> ServerRuleEditorDraft.ActionKind {
        ServerRuleEditorDraft.actionKind(for: draft.actions[index])
    }

    private func actionKindBinding(at index: Int) -> Binding<ServerRuleEditorDraft.ActionKind> {
        Binding(
            get: { actionKind(at: index) },
            set: { newKind in
                draft.actions[index] = newKind.makeAction(value: ServerRuleEditorDraft.actionValue(for: draft.actions[index]))
            }
        )
    }

    private func actionValueBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { ServerRuleEditorDraft.actionValue(for: draft.actions[index]) },
            set: { newValue in
                let kind = actionKind(at: index)
                draft.actions[index] = kind.makeAction(value: newValue)
            }
        )
    }

    // MARK: - Networking

    private func loadFoldersIfNeeded() async {
        guard !hasFetchedFolders else { return }
        hasFetchedFolders = true
        isLoadingFolders = true
        defer { isLoadingFolders = false }
        do {
            let sourceID = MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)
            folders = try await backend.folders(in: sourceID)
        } catch {
            // Folder picker falls back to a free-form text field via
            // the underlying value; the user can still type an id.
        }
    }

    private func save() async {
        guard draft.canSave else { return }
        guard let service = backend.extensionService(ServerRuleManaging.self) else {
            saveError = String(localized: "Server rules are not supported by this account.", bundle: .module)
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let rule = draft.makeRule()
            let sourceID = MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)
            let saved = try await service.saveServerRule(rule, sourceID: sourceID)
            onSave(saved)
            onClose()
        } catch {
            saveError = String(localized: "Couldn't save rule: \(error.localizedDescription)", bundle: .module)
        }
    }
}

// MARK: - Local rule editor

/// Sheet-based editor for a single `ServerRule` stored locally.
public struct LocalRuleEditorSheet: View {
    @Environment(\.brevTheme) private var theme
    @State private var draft: LocalRuleEditorDraft
    private let onSave: (ServerRule) -> Void
    private let onClose: () -> Void

    public init(
        draft: LocalRuleEditorDraft,
        onSave: @escaping (ServerRule) -> Void,
        onClose: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Rule", bundle: .module)) {
                    TextField(String(localized: "Rule name", bundle: .module), text: $draft.name)
                    Toggle(String(localized: "Enabled", bundle: .module), isOn: $draft.isEnabled)
                }

                Section(String(localized: "Condition", bundle: .module)) {
                    Picker(String(localized: "Condition", bundle: .module), selection: $draft.conditionKind) {
                        ForEach(LocalRuleEditorDraft.ConditionKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    if draft.conditionKind.requiresValue {
                        TextField(String(localized: "Value", bundle: .module), text: $draft.conditionValue)
                    }
                }

                Section(String(localized: "Action", bundle: .module)) {
                    Picker(String(localized: "Action", bundle: .module), selection: $draft.actionKind) {
                        ForEach(LocalRuleEditorDraft.ActionKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    if draft.actionKind.requiresValue {
                        TextField(String(localized: "Value", bundle: .module), text: $draft.actionValue)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(BrevWindowSurfaceBackground(role: .content).ignoresSafeArea())
            .navigationTitle(draft.name.isEmpty ? String(localized: "New local rule", bundle: .module) : String(
                localized: "Edit local rule",
                bundle: .module
            ))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { onClose() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save", bundle: .module)) { save() }
                        .disabled(!draft.canSave)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 460)
    }

    private func save() {
        var trimmed = draft
        trimmed.name = trimmed.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.name.isEmpty else { return }
        onSave(trimmed.makeRule())
        onClose()
    }
}

// MARK: - Server rule editor draft

public struct ServerRuleEditorDraft: Identifiable, Equatable {
    public enum ConditionKind: String, CaseIterable, Identifiable, Hashable {
        case senderContains
        case recipientContains
        case subjectContains
        case hasAttachment
        case isUnread
        case providerPredicate

        public var id: String { rawValue }

        var title: String {
            switch self {
            case .senderContains: return String(localized: "Sender contains", bundle: .module)
            case .recipientContains: return String(localized: "Recipient contains", bundle: .module)
            case .subjectContains: return String(localized: "Subject contains", bundle: .module)
            case .hasAttachment: return String(localized: "Has attachment", bundle: .module)
            case .isUnread: return String(localized: "Is unread", bundle: .module)
            case .providerPredicate: return String(localized: "Provider predicate", bundle: .module)
            }
        }

        var requiresValue: Bool {
            switch self {
            case .hasAttachment, .isUnread: return false
            default: return true
            }
        }

        func makeCondition(value: String) -> ServerRuleCondition {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            switch self {
            case .senderContains: return .senderContains(trimmed)
            case .recipientContains: return .recipientContains(trimmed)
            case .subjectContains: return .subjectContains(trimmed)
            case .hasAttachment: return .hasAttachment
            case .isUnread: return .isUnread
            case .providerPredicate: return .providerPredicate(trimmed)
            }
        }
    }

    public enum ActionKind: String, CaseIterable, Identifiable, Hashable {
        case moveToFolder
        case archive
        case markRead
        case markUnread
        case flag
        case delete
        case forward
        case providerAction

        public var id: String { rawValue }

        var title: String {
            switch self {
            case .moveToFolder: return String(localized: "Move to folder", bundle: .module)
            case .archive: return String(localized: "Archive", bundle: .module)
            case .markRead: return String(localized: "Mark read", bundle: .module)
            case .markUnread: return String(localized: "Mark unread", bundle: .module)
            case .flag: return String(localized: "Flag", bundle: .module)
            case .delete: return String(localized: "Delete", bundle: .module)
            case .forward: return String(localized: "Forward to", bundle: .module)
            case .providerAction: return String(localized: "Provider action", bundle: .module)
            }
        }

        var requiresValue: Bool {
            switch self {
            case .moveToFolder, .forward, .providerAction: return true
            default: return false
            }
        }

        func makeAction(value: String) -> ServerRuleAction {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            switch self {
            case .moveToFolder: return .moveToFolder(id: trimmed)
            case .archive: return .archive
            case .markRead: return .markRead
            case .markUnread: return .markUnread
            case .flag: return .flag
            case .delete: return .delete
            case .forward: return .forward(to: trimmed)
            case .providerAction: return .providerAction(trimmed)
            }
        }
    }

    public let id: String
    public var name: String
    public var isEnabled: Bool
    public var conditions: [ServerRuleCondition]
    var actions: [ServerRuleAction]

    var isNew: Bool { id == Self.unpersistedID }

    private static let unpersistedID = "draft.newRule"

    var canSave: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        guard !actions.isEmpty else { return false }
        return true
    }

    init(
        id: String,
        name: String,
        isEnabled: Bool,
        conditions: [ServerRuleCondition],
        actions: [ServerRuleAction]
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.conditions = conditions
        self.actions = actions
    }

    public static func newRule() -> ServerRuleEditorDraft {
        ServerRuleEditorDraft(
            id: unpersistedID,
            name: "",
            isEnabled: true,
            conditions: [.subjectContains("")],
            actions: [.markRead]
        )
    }

    public init(rule: ServerRule) {
        id = rule.id
        name = rule.name
        isEnabled = rule.isEnabled
        conditions = rule.conditions
        actions = rule.actions
    }

    func makeRule() -> ServerRule {
        ServerRule(
            id: id,
            name: name,
            isEnabled: isEnabled,
            conditions: conditions,
            actions: actions
        )
    }

    // MARK: Kind / value helpers

    static func conditionKind(for condition: ServerRuleCondition) -> ConditionKind {
        switch condition {
        case .senderContains: return .senderContains
        case .recipientContains: return .recipientContains
        case .subjectContains: return .subjectContains
        case .hasAttachment: return .hasAttachment
        case .isUnread: return .isUnread
        case .providerPredicate: return .providerPredicate
        }
    }

    static func conditionValue(for condition: ServerRuleCondition) -> String {
        switch condition {
        case .senderContains(let value),
             .recipientContains(let value),
             .subjectContains(let value),
             .providerPredicate(let value):
            return value
        case .hasAttachment, .isUnread:
            return ""
        }
    }

    static func actionKind(for action: ServerRuleAction) -> ActionKind {
        switch action {
        case .moveToFolder: return .moveToFolder
        case .archive: return .archive
        case .markRead: return .markRead
        case .markUnread: return .markUnread
        case .flag: return .flag
        case .delete: return .delete
        case .forward: return .forward
        case .providerAction: return .providerAction
        }
    }

    static func actionValue(for action: ServerRuleAction) -> String {
        switch action {
        case .moveToFolder(let id): return id
        case .forward(let value),
             .providerAction(let value):
            return value
        case .archive, .markRead, .markUnread, .flag, .delete:
            return ""
        }
    }
}

// MARK: - Local rule editor draft

public struct LocalRuleEditorDraft: Identifiable, Equatable {
    public enum ConditionKind: String, CaseIterable, Identifiable, Hashable {
        case senderContains
        case recipientContains
        case subjectContains
        case hasAttachment
        case isUnread
        case providerPredicate

        public var id: String { rawValue }

        var title: String {
            switch self {
            case .senderContains: return String(localized: "Sender contains", bundle: .module)
            case .recipientContains: return String(localized: "Recipient contains", bundle: .module)
            case .subjectContains: return String(localized: "Subject contains", bundle: .module)
            case .hasAttachment: return String(localized: "Has attachment", bundle: .module)
            case .isUnread: return String(localized: "Is unread", bundle: .module)
            case .providerPredicate: return String(localized: "Provider predicate", bundle: .module)
            }
        }

        var requiresValue: Bool {
            switch self {
            case .hasAttachment, .isUnread: return false
            default: return true
            }
        }
    }

    public enum ActionKind: String, CaseIterable, Identifiable, Hashable {
        case moveToFolder
        case archive
        case markRead
        case markUnread
        case flag
        case delete
        case forward
        case providerAction

        public var id: String { rawValue }

        var title: String {
            switch self {
            case .moveToFolder: return String(localized: "Move to folder", bundle: .module)
            case .archive: return String(localized: "Archive", bundle: .module)
            case .markRead: return String(localized: "Mark read", bundle: .module)
            case .markUnread: return String(localized: "Mark unread", bundle: .module)
            case .flag: return String(localized: "Flag", bundle: .module)
            case .delete: return String(localized: "Delete", bundle: .module)
            case .forward: return String(localized: "Forward to", bundle: .module)
            case .providerAction: return String(localized: "Provider action", bundle: .module)
            }
        }

        var requiresValue: Bool {
            switch self {
            case .moveToFolder, .forward, .providerAction: return true
            default: return false
            }
        }
    }

    public let id: String
    public var name: String
    public var isEnabled: Bool
    public var conditionKind: ConditionKind
    var conditionValue: String
    var actionKind: ActionKind
    var actionValue: String

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        id: String,
        name: String,
        isEnabled: Bool,
        conditionKind: ConditionKind,
        conditionValue: String,
        actionKind: ActionKind,
        actionValue: String
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.conditionKind = conditionKind
        self.conditionValue = conditionValue
        self.actionKind = actionKind
        self.actionValue = actionValue
    }

    public static func newRule() -> LocalRuleEditorDraft {
        LocalRuleEditorDraft(
            id: UUID().uuidString,
            name: String(localized: "New local rule", bundle: .module),
            isEnabled: true,
            conditionKind: .subjectContains,
            conditionValue: "",
            actionKind: .markRead,
            actionValue: ""
        )
    }

    public init(rule: ServerRule) {
        id = rule.id
        name = rule.name
        isEnabled = rule.isEnabled
        let condition = rule.conditions.first
        let action = rule.actions.first
        conditionKind = Self.conditionKind(for: condition)
        conditionValue = Self.conditionValue(for: condition)
        actionKind = Self.actionKind(for: action)
        actionValue = Self.actionValue(for: action)
    }

    func makeRule() -> ServerRule {
        ServerRule(
            id: id,
            name: name,
            isEnabled: isEnabled,
            conditions: [makeCondition()],
            actions: [makeAction()]
        )
    }

    private func makeCondition() -> ServerRuleCondition {
        let value = conditionValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch conditionKind {
        case .senderContains: return .senderContains(value)
        case .recipientContains: return .recipientContains(value)
        case .subjectContains: return .subjectContains(value)
        case .hasAttachment: return .hasAttachment
        case .isUnread: return .isUnread
        case .providerPredicate: return .providerPredicate(value)
        }
    }

    private func makeAction() -> ServerRuleAction {
        let value = actionValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch actionKind {
        case .moveToFolder: return .moveToFolder(id: value)
        case .archive: return .archive
        case .markRead: return .markRead
        case .markUnread: return .markUnread
        case .flag: return .flag
        case .delete: return .delete
        case .forward: return .forward(to: value)
        case .providerAction: return .providerAction(value)
        }
    }

    private static func conditionKind(for condition: ServerRuleCondition?) -> ConditionKind {
        switch condition {
        case .senderContains: return .senderContains
        case .recipientContains: return .recipientContains
        case .subjectContains: return .subjectContains
        case .hasAttachment: return .hasAttachment
        case .isUnread: return .isUnread
        case .providerPredicate: return .providerPredicate
        case nil: return .subjectContains
        }
    }

    private static func conditionValue(for condition: ServerRuleCondition?) -> String {
        switch condition {
        case .senderContains(let value),
             .recipientContains(let value),
             .subjectContains(let value),
             .providerPredicate(let value):
            return value
        case .hasAttachment, .isUnread, nil:
            return ""
        }
    }

    private static func actionKind(for action: ServerRuleAction?) -> ActionKind {
        switch action {
        case .moveToFolder: return .moveToFolder
        case .archive: return .archive
        case .markRead: return .markRead
        case .markUnread: return .markUnread
        case .flag: return .flag
        case .delete: return .delete
        case .forward: return .forward
        case .providerAction: return .providerAction
        case nil: return .markRead
        }
    }

    private static func actionValue(for action: ServerRuleAction?) -> String {
        switch action {
        case .moveToFolder(let id): return id
        case .forward(let value),
             .providerAction(let value):
            return value
        case .archive, .markRead, .markUnread, .flag, .delete, nil:
            return ""
        }
    }
}
