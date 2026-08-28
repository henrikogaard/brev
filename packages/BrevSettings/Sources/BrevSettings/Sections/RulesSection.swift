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

// MARK: - RulesSection

/// Top-level rules section. Shows a segmented control switching
/// between server-side rules (when the active account supports them)
/// and the always-available local rules.
///
/// The section needs access to a `MailBackend` so it can call the
/// `ServerRuleManaging` extension service. The caller passes a
/// `backendProvider` closure; the section uses the active account
/// id to look up the matching backend.
public struct RulesSection: View {
    @Environment(\.brevTheme) private var theme
    @State private var selectedTab: RulesTab = .local

    private let settingsStore: SettingsPersistenceStore
    private let accounts: [BrevAccount]
    private let currentAccountID: BrevAccount.ID?
    private let backendProvider: @MainActor (BrevAccount.ID) -> (any MailBackend)?

    public init(
        settingsStore: SettingsPersistenceStore,
        accounts: [BrevAccount],
        currentAccountID: BrevAccount.ID?,
        backendProvider: @escaping @MainActor (BrevAccount.ID) -> (any MailBackend)?
    ) {
        self.settingsStore = settingsStore
        self.accounts = accounts
        self.currentAccountID = currentAccountID
        self.backendProvider = backendProvider
    }

    public var body: some View {
        SectionScaffold(
            title: String(localized: "Rules", bundle: .module),
            subtitle: String(
                localized: "Provider-side filters and local-only rules. Local rules run regardless of server support.",
                bundle: .module
            )
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                tabPicker
                if let backend = activeBackend {
                    tabContent(for: backend)
                } else {
                    SettingsInfoCallout(
                        symbolName: "person.crop.circle.badge.questionmark",
                        message: String(localized: "Sign in to an account to manage rules.", bundle: .module),
                        tone: .info
                    )
                }
            }
        }
    }

    private var activeBackend: (any MailBackend)? {
        guard let currentAccountID else { return nil }
        return backendProvider(currentAccountID)
    }

    private var tabPicker: some View {
        Picker(String(localized: "Rules source", bundle: .module), selection: $selectedTab) {
            ForEach(RulesTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private func tabContent(for backend: any MailBackend) -> some View {
        switch selectedTab {
        case .server:
            ServerRulesPane(
                backend: backend,
                accounts: accounts,
                currentAccountID: currentAccountID,
                backendProvider: backendProvider
            )
        case .local:
            LocalRulesPane(
                settingsStore: settingsStore,
                backend: backend
            )
        }
    }
}

private enum RulesTab: String, CaseIterable, Identifiable, Hashable {
    case local
    case server

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return String(localized: "Local rules", bundle: .module)
        case .server: return String(localized: "Server rules", bundle: .module)
        }
    }
}

// MARK: - Server rules pane

private struct ServerRulesPane: View {
    @Environment(\.brevTheme) private var theme
    let backend: any MailBackend
    let accounts: [BrevAccount]
    let currentAccountID: BrevAccount.ID?
    let backendProvider: @MainActor (BrevAccount.ID) -> (any MailBackend)?

    @State private var rules: [ServerRule] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var editorDraft: ServerRuleEditorDraft?
    @State private var pendingDeleteID: ServerRule.ID?
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.lg) {
            capabilityGroup
            listGroup
        }
        .task(id: backend.account.id) { await reload() }
        .sheet(item: $editorDraft) { draft in
            ServerRuleEditorView(
                draft: draft,
                backend: backend,
                onSave: { saved in
                    upsertRule(saved)
                    statusMessage = String(localized: "Saved \"\(saved.name)\".", bundle: .module)
                },
                onClose: { editorDraft = nil }
            )
        }
        .confirmationDialog(
            String(localized: "Delete server rule?", bundle: .module),
            isPresented: deleteDialogBinding,
            presenting: pendingDeleteID
        ) { ruleID in
            Button(String(localized: "Delete rule", bundle: .module), role: .destructive) { confirmDelete(ruleID: ruleID) }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) { pendingDeleteID = nil }
        } message: { ruleID in
            let name = rules.first(where: { $0.id == ruleID })?.name ?? String(localized: "this rule", bundle: .module)
            Text("Server rule \"\(name)\" will be removed. Local rules are not affected.", bundle: .module)
        }
    }

    private var isServerRulesSupported: Bool {
        backend.capabilities.contains(.serverRules)
    }

    private var capabilityGroup: some View {
        SettingsGroup(
            title: String(localized: "Server rules", bundle: .module),
            subtitle: isServerRulesSupported
                ? String(localized: "Provider-side filters evaluated on the mail server.", bundle: .module)
                : String(localized: "Server-side rules are not supported by this account.", bundle: .module),
            symbolName: "server.rack"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                if isServerRulesSupported {
                    SettingsInfoCallout(
                        symbolName: "checkmark.seal",
                        message: String(
                            localized: "Server rules are evaluated before mail reaches your device. Local rules still run on top of them.",
                            bundle: .module
                        ),
                        tone: .info
                    )
                } else {
                    SettingsInfoCallout(
                        symbolName: "exclamationmark.triangle",
                        message: String(localized: "Use local rules instead — they work for every account.", bundle: .module),
                        tone: .warning
                    )
                }
            }
        }
    }

    private var listGroup: some View {
        SettingsGroup(
            title: String(localized: "Configured rules", bundle: .module),
            subtitle: String(
                localized: "Each rule runs in order. Drag to reorder server-side rules via your provider.",
                bundle: .module
            ),
            symbolName: "list.bullet.rectangle"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                if !isServerRulesSupported {
                    notSupportedCallout
                } else if isLoading && rules.isEmpty {
                    HStack(spacing: BrevSpacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Loading server rules…", bundle: .module)
                            .brevFont(.body)
                            .foregroundStyle(theme.textSecondary.color)
                    }
                } else if let loadError {
                    SettingsInfoCallout(
                        symbolName: "exclamationmark.triangle",
                        message: loadError,
                        tone: .warning
                    )
                } else if rules.isEmpty {
                    SettingsInfoCallout(
                        symbolName: "checklist.unchecked",
                        message: String(
                            localized: "No server rules yet. Add one to filter mail before it reaches your device.",
                            bundle: .module
                        ),
                        tone: .info
                    )
                } else {
                    VStack(spacing: BrevSpacing.xs) {
                        ForEach(rules) { rule in
                            ServerRuleRow(
                                rule: rule,
                                onToggle: { isEnabled in toggle(rule: rule, isEnabled: isEnabled) },
                                onEdit: { editorDraft = ServerRuleEditorDraft(rule: rule) },
                                onDelete: { pendingDeleteID = rule.id }
                            )
                        }
                    }
                }

                HStack(spacing: BrevSpacing.sm) {
                    BrevButton(String(localized: "Add rule", bundle: .module), style: .secondary) {
                        editorDraft = ServerRuleEditorDraft.newRule()
                    }
                    .disabled(!isServerRulesSupported)
                    BrevButton(String(localized: "Refresh", bundle: .module), style: .tertiary) {
                        Task { await reload(force: true) }
                    }
                    .disabled(isLoading || !isServerRulesSupported)
                    Spacer(minLength: 0)
                }

                if let statusMessage {
                    SettingsInfoCallout(
                        symbolName: "checkmark.circle",
                        message: statusMessage,
                        tone: .success
                    )
                }
            }
        }
    }

    private var notSupportedCallout: some View {
        SettingsInfoCallout(
            symbolName: "exclamationmark.triangle",
            message: String(
                localized: "Server rules are not supported by the current account's backend. The list below is read-only.",
                bundle: .module
            ),
            tone: .warning
        )
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteID != nil },
            set: { if !$0 { pendingDeleteID = nil } }
        )
    }

    private func reload(force: Bool = false) async {
        guard isServerRulesSupported else {
            rules = []
            loadError = nil
            return
        }
        guard let service = backend.extensionService(ServerRuleManaging.self) else {
            rules = []
            loadError = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let sourceID = currentSourceID
            let fetched = try await service.serverRules(for: sourceID)
            rules = fetched
            loadError = nil
            _ = force // explicit no-op; placeholder for future cache-busting
        } catch {
            loadError = String(localized: "Couldn't load server rules: \(error.localizedDescription)", bundle: .module)
        }
    }

    private var currentSourceID: MailSourceID {
        // Prefer the active source for the backend; fall back to a
        // synthesized source id matching the account + its first
        // available mailbox id.
        let mailboxID = backend.account.id
        return MailSourceID(accountID: backend.account.id, mailboxID: mailboxID)
    }

    private func toggle(rule: ServerRule, isEnabled: Bool) {
        guard let service = backend.extensionService(ServerRuleManaging.self),
              isServerRulesSupported else { return }
        var updated = rule
        updated.isEnabled = isEnabled
        Task {
            do {
                let saved = try await service.saveServerRule(updated, sourceID: currentSourceID)
                upsertRule(saved)
                statusMessage = isEnabled
                    ? String(localized: "Enabled \"\(saved.name)\".", bundle: .module)
                    : String(localized: "Disabled \"\(saved.name)\".", bundle: .module)
            } catch {
                loadError = String(localized: "Couldn't update rule: \(error.localizedDescription)", bundle: .module)
            }
        }
    }

    private func upsertRule(_ saved: ServerRule) {
        if let index = rules.firstIndex(where: { $0.id == saved.id }) {
            rules[index] = saved
        } else {
            rules.append(saved)
        }
    }

    private func confirmDelete(ruleID: ServerRule.ID) {
        guard let service = backend.extensionService(ServerRuleManaging.self),
              isServerRulesSupported else {
            pendingDeleteID = nil
            return
        }
        let name = rules.first(where: { $0.id == ruleID })?.name ?? String(localized: "rule", bundle: .module)
        Task {
            do {
                try await service.deleteServerRule(id: ruleID, sourceID: currentSourceID)
                rules.removeAll { $0.id == ruleID }
                statusMessage = String(localized: "Deleted \"\(name)\".", bundle: .module)
            } catch {
                loadError = String(localized: "Couldn't delete rule: \(error.localizedDescription)", bundle: .module)
            }
            pendingDeleteID = nil
        }
    }
}

private struct ServerRuleRow: View {
    @Environment(\.brevTheme) private var theme
    let rule: ServerRule
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            HStack(spacing: BrevSpacing.sm) {
                Toggle(
                    rule.name,
                    isOn: Binding(
                        get: { rule.isEnabled },
                        set: { onToggle($0) }
                    )
                )
                .toggleStyle(.switch)
                .tint(theme.accent.color)
                .labelsHidden()

                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name)
                        .brevFont(.subheadline)
                        .foregroundStyle(theme.textPrimary.color)
                    Text(conditionSummary)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .lineLimit(1)
                }

                Spacer(minLength: BrevSpacing.sm)

                BrevButton(String(localized: "Edit", bundle: .module), style: .tertiary) { onEdit() }
                BrevButton(String(localized: "Delete", bundle: .module), style: .destructive) { onDelete() }
            }

            HStack(spacing: BrevSpacing.xs) {
                ForEach(Array(rule.actions.enumerated()), id: \.offset) { _, action in
                    ActionBadge(action: action)
                }
                if rule.actions.isEmpty {
                    Text("No actions", bundle: .module)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textTertiary.color)
                }
            }
        }
        .padding(BrevSpacing.md)
        .background(theme.bgSecondary.color.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .stroke(theme.border.color.opacity(0.45), lineWidth: 1)
        }
    }

    private var conditionSummary: String {
        if rule.conditions.isEmpty {
            return String(localized: "Always", bundle: .module)
        }
        return rule.conditions
            .map(ServerRuleConditionSummary.shortLabel(for:))
            .joined(separator: " · ")
    }
}

private struct ActionBadge: View {
    @Environment(\.brevTheme) private var theme
    let action: ServerRuleAction

    var body: some View {
        Text(ServerRuleActionSummary.shortLabel(for: action))
            .brevFont(.caption)
            .foregroundStyle(action.isDestructive ? theme.danger.color : theme.textSecondary.color)
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, BrevSpacing.xxs)
            .background(theme.bgSecondary.color)
            .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
    }
}

// MARK: - Local rules pane

private struct LocalRulesPane: View {
    @Environment(\.brevTheme) private var theme
    let settingsStore: SettingsPersistenceStore
    let backend: any MailBackend

    @State private var settings: LocalRulesSettings
    @State private var editorDraft: LocalRuleEditorDraft?
    @State private var statusMessage: String?
    @State private var syncErrorMessage: String?
    @State private var isSyncingServerRules = false
    @State private var pendingDeleteID: ServerRule.ID?

    init(
        settingsStore: SettingsPersistenceStore,
        backend: any MailBackend
    ) {
        self.settingsStore = settingsStore
        self.backend = backend
        _settings = State(initialValue: settingsStore.localRulesSettings())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.lg) {
            controlsGroup
            listGroup
        }
        .confirmationDialog(
            String(localized: "Delete local rule?", bundle: .module),
            isPresented: deleteDialogBinding,
            presenting: pendingDeleteID
        ) { ruleID in
            Button(String(localized: "Delete rule", bundle: .module), role: .destructive) { confirmDelete(ruleID: ruleID) }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) { pendingDeleteID = nil }
        } message: { ruleID in
            let name = settings.rules.first(where: { $0.id == ruleID })?.name ?? String(localized: "this rule", bundle: .module)
            Text("Local rule \"\(name)\" will be removed.", bundle: .module)
        }
        .onReceive(NotificationCenter.default.publisher(for: .brevLocalRulesDidChange)) { _ in
            settings = settingsStore.localRulesSettings()
            statusMessage = String(localized: "Local rules refreshed.", bundle: .module)
            syncErrorMessage = nil
        }
    }

    private var controlsGroup: some View {
        SettingsGroup(
            title: String(localized: "Local rules", bundle: .module),
            subtitle: String(localized: "Provider-neutral rules evaluated deterministically by Brev.", bundle: .module),
            symbolName: "line.3.horizontal.decrease.circle"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsToggleRow(
                    symbolName: "bolt.badge.clock",
                    title: String(localized: "Run local rules automatically", bundle: .module),
                    subtitle: String(localized: "Apply enabled local rules whenever a folder reloads.", bundle: .module),
                    isOn: automaticExecutionBinding
                )
                SettingsInfoCallout(
                    symbolName: "info.circle",
                    message: String(
                        localized: "Local rules work for every account, including providers that don't expose server rules.",
                        bundle: .module
                    ),
                    tone: .info
                )
                manageSieveSyncControls
            }
        }
    }

    @ViewBuilder
    private var manageSieveSyncControls: some View {
        if isManageSieveAvailable {
            SettingsInfoCallout(
                symbolName: "server.rack",
                message: String(
                    localized: "This account can push compatible local rules to a Brev-owned server script.",
                    bundle: .module
                ),
                tone: .info
            )
            HStack(spacing: BrevSpacing.sm) {
                BrevButton(
                    isSyncingServerRules ? String(localized: "Syncing...", bundle: .module) : String(
                        localized: "Sync to server",
                        bundle: .module
                    ),
                    style: .secondary
                ) {
                    syncLocalRulesToServer()
                }
                .disabled(isSyncingServerRules || settings.rules.isEmpty)
                Spacer(minLength: 0)
            }
            if let syncErrorMessage {
                SettingsInfoCallout(
                    symbolName: "exclamationmark.triangle",
                    message: syncErrorMessage,
                    tone: .warning
                )
            }
        }
    }

    private var listGroup: some View {
        SettingsGroup(
            title: String(localized: "Configured rules", bundle: .module),
            subtitle: String(
                localized: "Local rules are evaluated in order. The first matching rule wins per message.",
                bundle: .module
            ),
            symbolName: "list.bullet.rectangle"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                if settings.rules.isEmpty {
                    SettingsInfoCallout(
                        symbolName: "checklist.unchecked",
                        message: String(
                            localized: "No local rules yet. Add one to enable deterministic local filtering.",
                            bundle: .module
                        ),
                        tone: .info
                    )
                } else {
                    VStack(spacing: BrevSpacing.xs) {
                        ForEach(Array(settings.rules.enumerated()), id: \.element.id) { index, rule in
                            LocalRuleRow(
                                rule: rule,
                                isFirst: index == 0,
                                isLast: index == settings.rules.count - 1,
                                onToggle: { isEnabled in
                                    settings.setEnabled(isEnabled, id: rule.id)
                                    persist()
                                },
                                onEdit: { editorDraft = LocalRuleEditorDraft(rule: rule) },
                                onMoveUp: {
                                    settings.moveUp(id: rule.id)
                                    persist()
                                },
                                onMoveDown: {
                                    settings.moveDown(id: rule.id)
                                    persist()
                                },
                                onDelete: { pendingDeleteID = rule.id }
                            )
                        }
                    }
                }

                HStack(spacing: BrevSpacing.sm) {
                    BrevButton(String(localized: "Add rule", bundle: .module), style: .secondary) {
                        editorDraft = LocalRuleEditorDraft.newRule()
                    }
                    Spacer(minLength: 0)
                }

                if let statusMessage {
                    SettingsInfoCallout(
                        symbolName: "checkmark.circle",
                        message: statusMessage,
                        tone: .success
                    )
                }
            }
        }
        .sheet(item: $editorDraft) { draft in
            LocalRuleEditorSheet(
                draft: draft,
                onSave: { rule in
                    if settings.rules.contains(where: { $0.id == rule.id }) {
                        settings.update(rule)
                    } else {
                        settings.add(rule)
                    }
                    persist()
                },
                onClose: { editorDraft = nil }
            )
        }
    }

    private var automaticExecutionBinding: Binding<Bool> {
        Binding(
            get: { settings.isAutomaticExecutionEnabled },
            set: { newValue in
                settings.isAutomaticExecutionEnabled = newValue
                persist()
            }
        )
    }

    private var isManageSieveAvailable: Bool {
        backend.capabilities.contains(.manageSieve)
            && backend.extensionService(ManageSieveRuleSyncing.self) != nil
    }

    private var currentSourceID: MailSourceID {
        MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteID != nil },
            set: { if !$0 { pendingDeleteID = nil } }
        )
    }

    private func persist() {
        settingsStore.save(settings)
        statusMessage = String(localized: "Local rules saved.", bundle: .module)
        syncErrorMessage = nil
    }

    private func confirmDelete(ruleID: ServerRule.ID) {
        let name = settings.rules.first(where: { $0.id == ruleID })?.name ?? String(localized: "rule", bundle: .module)
        settings.remove(id: ruleID)
        persist()
        statusMessage = String(localized: "Deleted \"\(name)\".", bundle: .module)
        pendingDeleteID = nil
    }

    private func syncLocalRulesToServer() {
        guard let service = backend.extensionService(ManageSieveRuleSyncing.self),
              isManageSieveAvailable else {
            syncErrorMessage = String(localized: "Server-side filter sync is not available for this account.", bundle: .module)
            return
        }
        isSyncingServerRules = true
        syncErrorMessage = nil
        Task {
            defer { isSyncingServerRules = false }
            do {
                let plan = try await service.syncLocalRulesToServer(
                    settings.rules,
                    sourceID: currentSourceID
                )
                let omittedCount = plan.unsupportedRules.count
                let syncedCount = max(0, settings.rules.count - omittedCount)
                statusMessage = omittedCount == 0
                    ? String(localized: "Synced \(syncedCount) local rules to the server.", bundle: .module)
                    : String(
                        localized: "Synced \(syncedCount) compatible rules. \(omittedCount) rules stayed local.",
                        bundle: .module
                    )
            } catch {
                syncErrorMessage = String(localized: "Couldn't sync local rules: \(error.localizedDescription)", bundle: .module)
            }
        }
    }
}

private struct LocalRuleRow: View {
    @Environment(\.brevTheme) private var theme
    let rule: ServerRule
    let isFirst: Bool
    let isLast: Bool
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: BrevSpacing.sm) {
            Toggle(rule.name, isOn: Binding(get: { rule.isEnabled }, set: { onToggle($0) }))
                .toggleStyle(.switch)
                .tint(theme.accent.color)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textPrimary.color)
                Text("\(conditionSummary) → \(actionSummary)", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .lineLimit(1)
            }

            Spacer(minLength: BrevSpacing.sm)

            BrevButton("↑", style: .tertiary) { onMoveUp() }.disabled(isFirst)
            BrevButton("↓", style: .tertiary) { onMoveDown() }.disabled(isLast)
            BrevButton(String(localized: "Edit", bundle: .module), style: .tertiary) { onEdit() }
            BrevButton(String(localized: "Delete", bundle: .module), style: .destructive) { onDelete() }
        }
        .padding(BrevSpacing.sm)
        .background(theme.bgSecondary.color.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .stroke(theme.border.color.opacity(0.45), lineWidth: 1)
        }
    }

    private var conditionSummary: String {
        if rule.conditions.isEmpty { return String(localized: "Always", bundle: .module) }
        return rule.conditions
            .map(ServerRuleConditionSummary.shortLabel(for:))
            .joined(separator: " + ")
    }

    private var actionSummary: String {
        if rule.actions.isEmpty { return String(localized: "No action", bundle: .module) }
        return rule.actions
            .map(ServerRuleActionSummary.shortLabel(for:))
            .joined(separator: " + ")
    }
}

// MARK: - Shared rule summaries

enum ServerRuleConditionSummary {
    static func shortLabel(for condition: ServerRuleCondition) -> String {
        switch condition {
        case .senderContains(let value):
            return String(localized: "Sender contains \"\(value)\"", bundle: .module)
        case .recipientContains(let value):
            return String(localized: "Recipient contains \"\(value)\"", bundle: .module)
        case .subjectContains(let value):
            return String(localized: "Subject contains \"\(value)\"", bundle: .module)
        case .hasAttachment:
            return String(localized: "Has attachment", bundle: .module)
        case .isUnread:
            return String(localized: "Is unread", bundle: .module)
        case .providerPredicate(let value):
            return String(localized: "Provider predicate \"\(value)\"", bundle: .module)
        }
    }

    static var allLabels: [String] {
        ["Sender contains", "Recipient contains", "Subject contains", "Has attachment", "Is unread", "Provider predicate"]
    }
}

enum ServerRuleActionSummary {
    static func shortLabel(for action: ServerRuleAction) -> String {
        switch action {
        case .moveToFolder(let id):
            return String(localized: "Move to \(id)", bundle: .module)
        case .archive:
            return String(localized: "Archive", bundle: .module)
        case .markRead:
            return String(localized: "Mark read", bundle: .module)
        case .markUnread:
            return String(localized: "Mark unread", bundle: .module)
        case .flag:
            return String(localized: "Flag", bundle: .module)
        case .delete:
            return String(localized: "Delete", bundle: .module)
        case .forward(let value):
            return String(localized: "Forward to \(value)", bundle: .module)
        case .providerAction(let value):
            return String(localized: "Provider action \(value)", bundle: .module)
        }
    }

    static var allLabels: [String] {
        ["Move to folder", "Archive", "Mark read", "Mark unread", "Flag", "Delete", "Forward", "Provider action"]
    }
}
