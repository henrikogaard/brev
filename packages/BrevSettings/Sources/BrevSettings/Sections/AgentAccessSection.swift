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
#if canImport(AppKit)
import AppKit
#endif

/// macOS-only **Settings → Agent access** pane for local MCP mail access (ADR-0095, #305).
struct AgentAccessSection: View {
    enum AuditFilter: String, CaseIterable, Identifiable {
        case all
        case allowed
        case approved
        case rejected

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                String(localized: "All events", bundle: .module)
            case .allowed:
                String(localized: "Allowed", bundle: .module)
            case .approved:
                String(localized: "Approved", bundle: .module)
            case .rejected:
                String(localized: "Denied / Blocked", bundle: .module)
            }
        }

        func matches(_ outcome: AgentAccessAuditOutcome) -> Bool {
            switch self {
            case .all: true
            case .allowed: outcome == .allowed
            case .approved: outcome == .approved
            case .rejected: outcome.isRejected
            }
        }
    }

    @Environment(\.brevTheme) private var theme
    @State private var settings: AgentAccessSettings
    @State private var auditEntries: [AgentAccessAuditEntry]
    @State private var selectedFilter: AuditFilter = .all
    @State private var selectedClientFormat: AgentAccessClientFormat = .json
    @State private var visibleAuditLimit = 25
    @State private var copiedConfig = false

    private let settingsStore: SettingsPersistenceStore
    private let auditStore: AgentAccessAuditLogStore
    private let accounts: [BrevAccount]
    private let helperPath: String
    private let socketPath: String
    private let onSettingsChanged: (AgentAccessSettings) -> Void

    init(
        settingsStore: SettingsPersistenceStore = .standard,
        auditStore: AgentAccessAuditLogStore = .shared,
        accounts: [BrevAccount] = [],
        helperPath: String = AgentAccessSocketConfiguration.defaultHelperPath(),
        socketPath: String = AgentAccessSocketConfiguration.defaultSocketURL().path,
        onSettingsChanged: @escaping (AgentAccessSettings) -> Void = { _ in }
    ) {
        self.settingsStore = settingsStore
        self.auditStore = auditStore
        self.accounts = accounts
        self.helperPath = helperPath
        self.socketPath = socketPath
        self.onSettingsChanged = onSettingsChanged
        _settings = State(initialValue: AgentAccessSettings.load(from: settingsStore.defaults))
        _auditEntries = State(initialValue: auditStore.entries())
    }

    var body: some View {
        SectionScaffold(
            title: String(localized: "Agent access", bundle: .module),
            subtitle: String(
                localized: "Let local AI agents on this Mac search and read cached mail through a private local socket, with no network ports and per-call approval in Brev for any change.",
                bundle: .module
            )
        ) {
            SettingsGroupStack {
                masterAccessGroup
                    .id(String(localized: "Local MCP server", bundle: .module))
                accountScopeGroup
                exposedToolsGroup
                    .id(String(localized: "Exposed tools", bundle: .module))
                clientSnippetGroup
                auditLogGroup
                    .id(String(localized: "Audit log", bundle: .module))
            }
            .onReceive(NotificationCenter.default.publisher(for: .brevAgentAccessAuditLogDidChange)) { _ in
                auditEntries = auditStore.entries()
            }
        }
    }

    private var masterAccessGroup: some View {
        SettingsGroup(
            title: String(localized: "Local MCP server", bundle: .module),
            subtitle: String(
                localized: "Off by default and stored only on this Mac. Never synced via iCloud or included in settings backups.",
                bundle: .module
            ),
            symbolName: "terminal"
        ) {
            SettingsToggleRow(
                symbolName: "bolt.shield",
                title: String(localized: "Allow local agents to access mail", bundle: .module),
                subtitle: String(
                    localized: "Listens only on a user-private Unix socket while Brev is running. Zero TCP or UDP ports.",
                    bundle: .module
                ),
                isOn: masterBinding
            )

            SettingsInfoCallout(
                symbolName: "exclamationmark.shield",
                message: String(
                    localized: "External agents you connect (such as Claude, Codex, or Cursor) may send email text they read to whichever AI provider those agents use. Only enable accounts you are comfortable sharing with your local agents.",
                    bundle: .module
                ),
                tone: .warning
            )
        }
    }

    private var accountScopeGroup: some View {
        SettingsGroup(
            title: String(localized: "Allowed accounts", bundle: .module),
            subtitle: String(
                localized: "Accounts left off are invisible to MCP clients.",
                bundle: .module
            ),
            symbolName: "person.2"
        ) {
            if accounts.isEmpty {
                Text("Add a mail account to grant per-account local agent access.", bundle: .module)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
            } else {
                SettingsRowStack(spacing: BrevSpacing.sm) {
                    ForEach(accounts) { account in
                        SettingsToggleRow(
                            symbolName: "envelope",
                            title: account.displayName.isEmpty ? account.emailAddress : account.displayName,
                            subtitle: account.emailAddress,
                            isOn: accountBinding(for: account.id)
                        )
                        .disabled(!settings.isEnabled)
                    }
                }
            }
        }
    }

    private var exposedToolsGroup: some View {
        SettingsGroup(
            title: String(localized: "Exposed tools", bundle: .module),
            subtitle: String(
                localized: "Sending mail, deleting or trashing mail, and credential or settings changes are permanently excluded.",
                bundle: .module
            ),
            symbolName: "wrench.and.screwdriver"
        ) {
            SettingsRowStack(spacing: BrevSpacing.sm) {
                ForEach(AgentAccessToolSpec.exposedTools) { tool in
                    HStack(alignment: .firstTextBaseline, spacing: BrevSpacing.sm) {
                        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                            Text(tool.name)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(theme.textPrimary.color)
                            Text(tool.summary)
                                .brevFont(.footnote)
                                .foregroundStyle(theme.textSecondary.color)
                        }
                        Spacer(minLength: BrevSpacing.sm)
                        Text(tool.permission.badgeTitle)
                            .brevFont(.caption)
                            .foregroundStyle(
                                tool.permission == .approvalRequired
                                    ? theme.accent.color
                                    : theme.textSecondary.color
                            )
                            .padding(.horizontal, BrevSpacing.xs)
                            .padding(.vertical, 3)
                            .background(theme.bgSecondary.color)
                            .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
                    }
                }
            }
        }
    }

    private var clientSnippetGroup: some View {
        SettingsGroup(
            title: String(localized: "MCP client setup", bundle: .module),
            subtitle: String(
                localized: "Configure Claude Desktop, Claude Code, Codex, or Cursor to launch the local stdio bridge.",
                bundle: .module
            ),
            symbolName: "doc.on.clipboard"
        ) {
            let snippet = AgentAccessSocketConfiguration.clientConfigSnippet(
                for: selectedClientFormat,
                helperPath: helperPath,
                socketPath: socketPath
            )
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                Picker(String(localized: "Client format", bundle: .module), selection: $selectedClientFormat) {
                    ForEach(AgentAccessClientFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .onChange(of: selectedClientFormat) { _, _ in
                    copiedConfig = false
                }

                Text(snippet)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.textPrimary.color)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BrevSpacing.sm)
                    .background(theme.bgSecondary.color)
                    .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))

                SettingsButton(
                    copiedConfig
                        ? String(localized: "Copied snippet", bundle: .module)
                        : String(localized: "Copy snippet", bundle: .module),
                    style: .secondary
                ) {
                    copySnippet(snippet)
                }
            }
        }
    }

    private var auditLogGroup: some View {
        SettingsGroup(
            title: String(localized: "Audit log", bundle: .module),
            subtitle: String(
                localized: "Every request received by Brev is logged locally (up to 1,000 entries, never storing bodies or sign-in codes).",
                bundle: .module
            ),
            symbolName: "list.bullet.clipboard"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                HStack(spacing: BrevSpacing.sm) {
                    Picker(String(localized: "Filter", bundle: .module), selection: $selectedFilter) {
                        ForEach(AuditFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .onChange(of: selectedFilter) { _, _ in
                        visibleAuditLimit = 25
                    }

                    Spacer(minLength: BrevSpacing.sm)

                    SettingsButton(String(localized: "Clear log", bundle: .module), style: .secondary) {
                        auditStore.clear()
                        auditEntries = []
                        visibleAuditLimit = 25
                    }
                    .disabled(auditEntries.isEmpty)
                }

                let filtered = auditEntries.filter { selectedFilter.matches($0.outcome) }
                if filtered.isEmpty {
                    Text("No local agent requests recorded yet.", bundle: .module)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                } else {
                    SettingsRowStack(spacing: BrevSpacing.xs) {
                        ForEach(filtered.prefix(visibleAuditLimit)) { entry in
                            auditEntryRow(entry)
                        }
                    }
                    if filtered.count > visibleAuditLimit {
                        SettingsButton(
                            String(
                                format: String(localized: "Show more (%lld remaining)", bundle: .module),
                                Int64(filtered.count - visibleAuditLimit)
                            ),
                            style: .secondary
                        ) {
                            visibleAuditLimit += 50
                        }
                    }
                }
            }
        }
    }

    private func auditEntryRow(_ entry: AgentAccessAuditEntry) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            HStack(spacing: BrevSpacing.xs) {
                Text(entry.toolName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.textPrimary.color)
                Text("·")
                    .foregroundStyle(theme.textSecondary.color)
                Text(entry.clientName)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                Spacer(minLength: BrevSpacing.xs)
                Text(entry.outcome.displayTitle)
                    .brevFont(.caption)
                    .foregroundStyle(entry.outcome.isRejected ? theme.textSecondary.color : theme.accent.color)
            }
            if !entry.parameterSummary.isEmpty {
                Text(entry.parameterSummary)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .lineLimit(2)
            }
        }
        .padding(BrevSpacing.xs)
        .background(theme.bgSecondary.color)
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
    }

    private var masterBinding: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { newValue in
                settings.isEnabled = newValue
                settings.save(to: settingsStore.defaults)
                onSettingsChanged(settings)
            }
        )
    }

    private func accountBinding(for accountID: String) -> Binding<Bool> {
        Binding(
            get: { settings.enabledAccountIDs.contains(accountID) },
            set: { newValue in
                settings.setAccount(accountID, enabled: newValue)
                settings.save(to: settingsStore.defaults)
                onSettingsChanged(settings)
            }
        )
    }

    private func copySnippet(_ snippet: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet, forType: .string)
        #endif
        copiedConfig = true
    }
}
