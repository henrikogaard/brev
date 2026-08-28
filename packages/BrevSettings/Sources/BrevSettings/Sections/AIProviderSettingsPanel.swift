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

import BrevAI
import BrevBackend
import BrevDesign
import BrevThemes
import SwiftUI

struct AIProviderSettingsPanel: View {
    @Environment(\.brevTheme) private var theme
    @State private var draft = AIProviderSettingsDraft.new(kind: .openAICompatible)
    @State private var configurations: [AIProviderConfiguration] = []
    @State private var selectedProviderID: AIProviderID?
    @State private var hasLoaded = false
    @State private var isEditingProvider = false
    @State private var isWorking = false
    @State private var statusMessage: ProviderStatusMessage?

    private let settingsStore: SettingsPersistenceStore
    private let secretStore: any AIProviderSecretStore
    private let accounts: [BrevAccount]
    private let onProviderConfigurationChanged: () async -> Void

    init(
        settingsStore: SettingsPersistenceStore,
        secretStore: any AIProviderSecretStore,
        accounts: [BrevAccount] = [],
        onProviderConfigurationChanged: @escaping () async -> Void = {}
    ) {
        self.settingsStore = settingsStore
        self.secretStore = secretStore
        self.accounts = accounts
        self.onProviderConfigurationChanged = onProviderConfigurationChanged
    }

    var body: some View {
        SettingsGroup(
            title: String(localized: "AI provider", bundle: .module),
            subtitle: String(localized: "Choose where Brev sends requests when you invoke an AI feature.", bundle: .module),
            symbolName: "server.rack"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                providerContent
            }
            .task {
                await loadDraftIfNeeded()
            }
            .onChange(of: selectedProviderID) { _, providerID in
                Task { await selectProvider(providerID) }
            }
        }
    }

    @ViewBuilder
    private var providerContent: some View {
        if configurations.isEmpty && !isEditingProvider {
            providerSetup
        } else if isEditingProvider {
            providerEditor
        } else {
            configuredProviderOverview
        }
    }

    private var providerSetup: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            SettingsInfoCallout(
                symbolName: "hand.raised",
                message: String(
                    localized: "No provider is configured. Brev connects directly to the provider you choose, stores provider metadata locally, and keeps API keys in Keychain only.",
                    bundle: .module
                ),
                tone: .info
            )

            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text("Set up a provider", bundle: .module)
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)
                Text("Use OpenAI-compatible services, a self-hosted endpoint, or a local model such as Ollama.", bundle: .module)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
            }

            BrevButton(String(localized: "Choose provider", bundle: .module)) {
                beginAddingProvider()
            }
            .disabled(isWorking)

            statusCallout
        }
    }

    private var configuredProviderOverview: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            if configurations.count > 1 {
                configuredProviderPicker
            }

            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(selectedConfiguration?.displayName ?? String(localized: "Configured provider", bundle: .module))
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)
                Text(selectedConfiguration?.transparencyLabel ?? draft.transparencyPreview)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
                Text(selectedConfiguration?
                    .isEnabled == true ? String(localized: "Available for AI features after consent.", bundle: .module) : String(
                        localized: "Disabled for AI features.",
                        bundle: .module
                    ))
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            }
            .padding(BrevSpacing.md)
            .background(theme.bgSecondary.color)
            .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: BrevSpacing.sm) {
                    BrevButton(String(localized: "Edit provider", bundle: .module)) {
                        isEditingProvider = true
                        statusMessage = nil
                    }
                    BrevButton(String(localized: "Add provider", bundle: .module), style: .secondary) {
                        beginAddingProvider()
                    }
                }

                VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                    BrevButton(String(localized: "Edit provider", bundle: .module)) {
                        isEditingProvider = true
                        statusMessage = nil
                    }
                    BrevButton(String(localized: "Add provider", bundle: .module), style: .secondary) {
                        beginAddingProvider()
                    }
                }
            }
            .disabled(isWorking)

            statusCallout
        }
    }

    private var providerEditor: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            SettingsPickerRow(
                symbolName: "square.stack.3d.up",
                title: String(localized: "Provider preset", bundle: .module),
                subtitle: draft.kind.settingsSubtitle,
                selection: presetBinding
            ) {
                ForEach(AIProviderKind.allCases, id: \.self) { kind in
                    Text(kind.settingsTitle).tag(kind)
                }
            }

            providerTextField(
                title: String(localized: "Display name", bundle: .module),
                text: $draft.displayName,
                prompt: draft.kind.settingsDisplayName
            )

            providerTextField(
                title: String(localized: "Endpoint URL", bundle: .module),
                text: $draft.endpointURLString,
                prompt: draft.kind.defaultEndpointString
            )
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif

            providerTextField(
                title: String(localized: "Model ID", bundle: .module),
                text: $draft.modelID,
                prompt: draft.kind.defaultModelID.isEmpty ? "model-name" : draft.kind.defaultModelID
            )
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif

            if draft.requiresAPIKey {
                apiKeyField
            } else {
                SettingsInfoCallout(
                    symbolName: "key.slash",
                    message: draft.apiKeyStatusText,
                    tone: .success
                )
            }

            SettingsInfoCallout(
                symbolName: "lock.shield",
                message: draft.transparencyPreview,
                tone: .info
            )

            SettingsToggleRow(
                symbolName: "power",
                title: String(localized: "Enable provider", bundle: .module),
                subtitle: String(localized: "Allow AI features to use this provider after consent.", bundle: .module),
                isOn: $draft.isEnabled
            )

            if let caveat = draft.platformCaveatMessage {
                SettingsInfoCallout(
                    symbolName: "network",
                    message: caveat,
                    tone: .info
                )
            }

            if let transportWarning = draft.transportWarning {
                SettingsInfoCallout(
                    symbolName: "exclamationmark.shield",
                    message: transportWarning,
                    tone: .warning
                )
            }

            DisclosureGroup(String(localized: "Provider options", bundle: .module)) {
                VStack(alignment: .leading, spacing: BrevSpacing.md) {
                    SettingsToggleRow(
                        symbolName: "star",
                        title: String(localized: "Default provider", bundle: .module),
                        subtitle: String(localized: "Use this when an account has no override.", bundle: .module),
                        isOn: $draft.isDefault
                    )

                    accountRoutingPicker
                }
                .padding(.top, BrevSpacing.sm)
            }

            validationMessages
            statusCallout
            editorActionButtons

            if selectedProviderID != nil {
                existingProviderActions
            }
        }
    }

    private var configuredProviderPicker: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            Text("Configured providers", bundle: .module)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
            Picker(String(localized: "Configured provider", bundle: .module), selection: $selectedProviderID) {
                ForEach(configurations) { configuration in
                    Text(configuration.displayName).tag(Optional(configuration.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var selectedConfiguration: AIProviderConfiguration? {
        configurations.first(where: { $0.id == selectedProviderID }) ?? configurations.first
    }

    private var accountRoutingPicker: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            Text("Account routing", bundle: .module)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
            Picker(String(localized: "Account routing", bundle: .module), selection: $draft.assignedAccountID) {
                Text("No account override", bundle: .module).tag(String?.none)
                ForEach(accounts) { account in
                    Text(account.emailAddress).tag(Optional(account.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Text(
                "An account override wins over the default provider. A missing key never falls back to another provider.",
                bundle: .module
            )
            .brevFont(.caption)
            .foregroundStyle(theme.textSecondary.color)
        }
    }

    private var presetBinding: Binding<AIProviderKind> {
        Binding(
            get: { draft.kind },
            set: { newValue in
                draft.applyPreset(newValue)
                statusMessage = nil
            }
        )
    }

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            Text("API key", bundle: .module)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
            SecureField(draft.redactedKeyPresentation, text: $draft.pendingAPIKey)
                .textFieldStyle(.roundedBorder)
            Text(draft.apiKeyStatusText)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
        }
    }

    @ViewBuilder
    private var validationMessages: some View {
        if !draft.validationIssues.isEmpty {
            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                ForEach(draft.validationIssues, id: \.message) { issue in
                    SettingsInfoCallout(
                        symbolName: "exclamationmark.triangle",
                        message: issue.message,
                        tone: .warning
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var statusCallout: some View {
        if let statusMessage {
            SettingsInfoCallout(
                symbolName: statusMessage.symbolName,
                message: statusMessage.message,
                tone: statusMessage.tone
            )
        }
    }

    private var editorActionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: BrevSpacing.sm) {
                saveButton
                cancelButton
            }

            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                saveButton
                cancelButton
            }
        }
    }

    private var saveButton: some View {
        BrevButton(String(localized: "Save provider", bundle: .module)) {
            Task { await saveDraft() }
        }
        .disabled(isWorking || !draft.validationIssues.isEmpty)
    }

    private var cancelButton: some View {
        BrevButton(String(localized: "Cancel", bundle: .module), style: .secondary) {
            Task { await cancelEditing() }
        }
        .disabled(isWorking)
    }

    private var existingProviderActions: some View {
        DisclosureGroup(String(localized: "Provider actions", bundle: .module)) {
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                BrevButton(String(localized: "Restore preset", bundle: .module), style: .secondary) {
                    draft.applyPreset(draft.kind)
                    statusMessage = ProviderStatusMessage(
                        message: String(localized: "Provider fields restored to the selected preset.", bundle: .module),
                        tone: .info
                    )
                }
                .disabled(isWorking)

                disableButton
                deleteButton
            }
            .padding(.top, BrevSpacing.sm)
        }
    }

    private var disableButton: some View {
        BrevButton(String(localized: "Disable", bundle: .module), style: .secondary) {
            Task { await disableProvider() }
        }
        .disabled(isWorking || !draft.isEnabled)
    }

    private var deleteButton: some View {
        BrevButton(String(localized: "Delete", bundle: .module), style: .destructive) {
            Task { await deleteProvider() }
        }
        .disabled(isWorking)
    }

    private func providerTextField(
        title: String,
        text: Binding<String>,
        prompt: String
    ) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            Text(title)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    @MainActor
    private func loadDraftIfNeeded() async {
        guard !hasLoaded else { return }
        configurations = (try? settingsStore.aiProviderConfigurations()) ?? []
        selectedProviderID = configurations.first?.id
        await loadSelectedDraft()
        hasLoaded = true
    }

    private func beginAddingProvider() {
        selectedProviderID = nil
        draft = .new(kind: .openAICompatible)
        statusMessage = nil
        isEditingProvider = true
    }

    @MainActor
    private func cancelEditing() async {
        selectedProviderID = AIProviderEditorPresentation.selectionAfterCancellingAdd(
            selectedProviderID: selectedProviderID,
            configuredProviderIDs: configurations.map(\.id)
        )
        await loadSelectedDraft()
        statusMessage = nil
        isEditingProvider = false
    }

    @MainActor
    private func selectProvider(_ providerID: AIProviderID?) async {
        guard hasLoaded, providerID != nil else { return }
        selectedProviderID = providerID
        await loadSelectedDraft()
        statusMessage = nil
    }

    @MainActor
    private func loadSelectedDraft() async {
        draft = await AIProviderSettingsPersistence.loadDraft(
            providerID: selectedProviderID,
            settingsStore: settingsStore,
            secretStore: secretStore
        )
    }

    @MainActor
    private func refreshConfigurations(selecting providerID: AIProviderID?) {
        configurations = (try? settingsStore.aiProviderConfigurations()) ?? []
        selectedProviderID = providerID ?? configurations.first?.id
    }

    @MainActor
    private func saveDraft() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let saved = try await AIProviderSettingsPersistence.save(
                draft,
                settingsStore: settingsStore,
                secretStore: secretStore
            )
            let hasSavedKey = saved.requiresAPIKey
                && (draft.hasSavedAPIKey || !draft.pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            draft = AIProviderSettingsDraft(
                configuration: saved,
                hasSavedAPIKey: hasSavedKey
            )
            refreshConfigurations(selecting: saved.id)
            await onProviderConfigurationChanged()
            isEditingProvider = false
            statusMessage = ProviderStatusMessage(
                message: String(
                    localized: "Provider saved locally and its account routes are active. API keys stay in Keychain.",
                    bundle: .module
                ),
                tone: .success
            )
        } catch {
            statusMessage = ProviderStatusMessage(
                message: safeErrorMessage(error),
                tone: .warning
            )
        }
    }

    @MainActor
    private func disableProvider() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try AIProviderSettingsPersistence.disable(
                providerID: draft.id,
                settingsStore: settingsStore
            )
            draft.isEnabled = false
            refreshConfigurations(selecting: draft.id)
            await onProviderConfigurationChanged()
            isEditingProvider = false
            statusMessage = ProviderStatusMessage(
                message: String(localized: "Provider disabled.", bundle: .module),
                tone: .success
            )
        } catch {
            statusMessage = ProviderStatusMessage(
                message: safeErrorMessage(error),
                tone: .warning
            )
        }
    }

    @MainActor
    private func deleteProvider() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await AIProviderSettingsPersistence.delete(
                providerID: draft.id,
                settingsStore: settingsStore,
                secretStore: secretStore
            )
            refreshConfigurations(selecting: nil)
            await loadSelectedDraft()
            await onProviderConfigurationChanged()
            isEditingProvider = false
            statusMessage = ProviderStatusMessage(
                message: String(localized: "Provider deleted and saved API key removed from Keychain.", bundle: .module),
                tone: .success
            )
        } catch {
            statusMessage = ProviderStatusMessage(
                message: safeErrorMessage(error),
                tone: .warning
            )
        }
    }

    private func safeErrorMessage(_ error: Error) -> String {
        let rawMessage = (error as? LocalizedError)?.errorDescription
            ?? String(describing: error)
        let apiKey = draft.pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return rawMessage }
        return rawMessage.replacingOccurrences(of: apiKey, with: "[redacted]")
    }
}

/// Resolves the provider selection after cancelling the Add provider editor.
enum AIProviderEditorPresentation {
    static func selectionAfterCancellingAdd(
        selectedProviderID: AIProviderID?,
        configuredProviderIDs: [AIProviderID]
    ) -> AIProviderID? {
        selectedProviderID ?? configuredProviderIDs.first
    }
}

private struct ProviderStatusMessage: Equatable {
    let message: String
    let tone: SettingsCalloutTone

    var symbolName: String {
        switch tone {
        case .info:
            return "info.circle"
        case .success:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        }
    }
}
