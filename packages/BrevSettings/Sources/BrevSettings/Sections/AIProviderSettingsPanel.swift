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
    @State private var baselineDraft: AIProviderSettingsDraft?
    @State private var configurations: [AIProviderConfiguration] = []
    @State private var selectedProviderID: AIProviderID?
    @State private var installedLocalModelIDs: Set<String> = []
    @State private var hasLoaded = false
    @State private var isEditingProvider = false
    @State private var isWorking = false
    @State private var statusMessage: ProviderStatusMessage?

    private let settingsStore: SettingsPersistenceStore
    private let secretStore: any AIProviderSecretStore
    private let accounts: [BrevAccount]
    private let appleIntelligenceAvailability: AppleIntelligenceAvailability
    private let localModelDownloadManager: LocalModelDownloadManager
    private let isLocalModelPlatformSupported: Bool
    private let refreshRevision: Int
    private let installedModelsRevision: Int
    private let onProviderConfigurationChanged: () async -> Void

    init(
        settingsStore: SettingsPersistenceStore,
        secretStore: any AIProviderSecretStore,
        accounts: [BrevAccount] = [],
        appleIntelligenceAvailability: AppleIntelligenceAvailability = .current(),
        localModelDownloadManager: LocalModelDownloadManager = .shared,
        isLocalModelPlatformSupported: Bool = DefaultLocalModelInferenceRuntime.isPlatformSupported,
        refreshRevision: Int = 0,
        installedModelsRevision: Int = 0,
        onProviderConfigurationChanged: @escaping () async -> Void = {}
    ) {
        self.settingsStore = settingsStore
        self.secretStore = secretStore
        self.accounts = accounts
        self.appleIntelligenceAvailability = appleIntelligenceAvailability
        self.localModelDownloadManager = localModelDownloadManager
        self.isLocalModelPlatformSupported = isLocalModelPlatformSupported
        self.refreshRevision = refreshRevision
        self.installedModelsRevision = installedModelsRevision
        self.onProviderConfigurationChanged = onProviderConfigurationChanged
    }

    var body: some View {
        SettingsGroup(
            title: String(localized: "AI provider", bundle: .module),
            subtitle: String(localized: "Choose where Brev processes requests when you invoke an AI feature.", bundle: .module),
            symbolName: "server.rack"
        ) {
            SettingsRowStack(spacing: BrevSpacing.md) {
                onDeviceAppleIntelligenceCard
                providerContent
            }
            .task {
                await loadDraftIfNeeded()
                await refreshInstalledLocalModels()
            }
            .onChange(of: refreshRevision) { _, _ in
                Task {
                    await handleExternalRefresh()
                }
            }
            .onChange(of: installedModelsRevision) { _, _ in
                Task {
                    await refreshInstalledLocalModels()
                }
            }
            .onChange(of: isEditingProvider) { _, editing in
                if editing {
                    Task { await refreshInstalledLocalModels() }
                }
            }
            .onChange(of: selectedProviderID) { _, providerID in
                Task { await selectProvider(providerID) }
            }
        }
    }

    private var isAppleIntelligenceActiveDefault: Bool {
        configurations.contains {
            $0.kind == .appleIntelligence && $0.isEnabled && $0.isDefault
        }
    }

    private var onDeviceAppleIntelligenceCard: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: BrevSpacing.sm) {
                Image(systemName: "cpu")
                    .foregroundStyle(
                        appleIntelligenceAvailability.isSelectable
                            ? theme.accent.color
                            : theme.textSecondary.color
                    )
                VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                    Text(OnDeviceAIPlatformLabel.appleIntelligenceDisplayName)
                        .brevFont(.headline)
                        .foregroundStyle(theme.textPrimary.color)
                    Text(appleIntelligenceAvailability.settingsStatusMessage)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                }
                Spacer(minLength: BrevSpacing.sm)
                if isAppleIntelligenceActiveDefault && appleIntelligenceAvailability.isSelectable {
                    Text(OnDeviceAIPlatformLabel.transparencyLabel)
                        .brevFont(.caption)
                        .foregroundStyle(theme.accent.color)
                } else {
                    SettingsButton(
                        String(localized: "Use on this device", bundle: .module),
                        style: .secondary
                    ) {
                        Task { await enableAppleIntelligence() }
                    }
                    .disabled(isWorking || !appleIntelligenceAvailability.isSelectable)
                }
            }
        }
        .padding(BrevSpacing.md)
        .settingsInlineSurface()
        .opacity(appleIntelligenceAvailability.isSelectable ? 1 : 0.72)
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

            SettingsButton(String(localized: "Choose provider", bundle: .module)) {
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
            .settingsInlineSurface()

            ViewThatFits(in: .horizontal) {
                SettingsButtonRow {
                    SettingsButton(String(localized: "Edit provider", bundle: .module)) {
                        isEditingProvider = true
                        statusMessage = nil
                    }
                    SettingsButton(String(localized: "Add provider", bundle: .module), style: .secondary) {
                        beginAddingProvider()
                    }
                }

                VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                    SettingsButton(String(localized: "Edit provider", bundle: .module)) {
                        isEditingProvider = true
                        statusMessage = nil
                    }
                    SettingsButton(String(localized: "Add provider", bundle: .module), style: .secondary) {
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
                ForEach(editablePresets, id: \.self) { kind in
                    Text(kind.settingsTitle).tag(kind)
                }
            }
            .disabled(draft.kind.isOnDevice)

            providerTextField(
                title: String(localized: "Display name", bundle: .module),
                text: $draft.displayName,
                prompt: draft.kind.settingsDisplayName
            )

            if !draft.kind.isOnDevice {
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
            } else if draft.kind == .onDeviceDownloadedModel {
                SettingsPickerRow(
                    symbolName: "arrow.down.circle",
                    title: String(localized: "Downloaded model", bundle: .module),
                    subtitle: String(
                        localized: "Manage model downloads and SHA-256 verification in Local Models below.",
                        bundle: .module
                    ),
                    selection: $draft.modelID
                ) {
                    ForEach(LocalModelCatalog.curatedModels) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                if let blockingReason = editorBlockingReason {
                    SettingsInfoCallout(
                        symbolName: "exclamationmark.triangle",
                        message: blockingReason,
                        tone: .warning
                    )
                }
            } else if !appleIntelligenceAvailability.isSelectable {
                SettingsInfoCallout(
                    symbolName: "exclamationmark.triangle",
                    message: appleIntelligenceAvailability.settingsStatusMessage,
                    tone: .warning
                )
            }

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

    private var editablePresets: [AIProviderKind] {
        switch draft.kind {
        case .appleIntelligence:
            return [.appleIntelligence]
        case .onDeviceDownloadedModel:
            return [.onDeviceDownloadedModel]
        case .openAICompatible, .ollamaLocal, .customOpenAICompatible:
            return AIProviderKind.allCases.filter { !$0.isOnDevice }
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

    private var editorBlockingReason: String? {
        AIProviderEditorValidation.blockingReason(
            for: draft,
            appleIntelligenceAvailability: appleIntelligenceAvailability,
            isLocalModelPlatformSupported: isLocalModelPlatformSupported,
            installedLocalModelIDs: installedLocalModelIDs
        )
    }

    private var saveButton: some View {
        SettingsButton(String(localized: "Save provider", bundle: .module)) {
            Task { await saveDraft() }
        }
        .disabled(
            isWorking
                || !draft.validationIssues.isEmpty
                || editorBlockingReason != nil
        )
    }

    private var cancelButton: some View {
        SettingsButton(String(localized: "Cancel", bundle: .module), style: .secondary) {
            Task { await cancelEditing() }
        }
        .disabled(isWorking)
    }

    private var existingProviderActions: some View {
        DisclosureGroup(String(localized: "Provider actions", bundle: .module)) {
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                SettingsButton(String(localized: "Restore preset", bundle: .module), style: .secondary) {
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
        SettingsButton(String(localized: "Disable", bundle: .module), style: .secondary) {
            Task { await disableProvider() }
        }
        .disabled(isWorking || !draft.isEnabled)
    }

    private var deleteButton: some View {
        SettingsButton(
            String(localized: "Delete", bundle: .module),
            style: .destructive,
            confirmationTitle: String(localized: "Delete this AI provider?", bundle: .module)
        ) {
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
        let newDraft = AIProviderSettingsDraft.new(kind: .openAICompatible)
        draft = newDraft
        baselineDraft = newDraft
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
        let loaded = await AIProviderSettingsPersistence.loadDraft(
            providerID: selectedProviderID,
            settingsStore: settingsStore,
            secretStore: secretStore
        )
        draft = loaded
        baselineDraft = loaded
    }

    @MainActor
    private func refreshInstalledLocalModels() async {
        let installed = await localModelDownloadManager.installedModels()
        installedLocalModelIDs = Set(installed.map(\.id))
        if editorBlockingReason == nil, statusMessage?.tone == .warning {
            statusMessage = nil
        }
    }

    @MainActor
    private func handleExternalRefresh() async {
        await refreshInstalledLocalModels()
        let updatedConfigurations = (try? settingsStore.aiProviderConfigurations()) ?? []
        let outcome = AIProviderEditorPresentation.stateAfterExternalRefresh(
            isEditingProvider: isEditingProvider,
            selectedProviderID: selectedProviderID,
            currentDraft: draft,
            baselineDraft: baselineDraft,
            updatedConfigurations: updatedConfigurations
        )
        configurations = updatedConfigurations
        selectedProviderID = outcome.selectedProviderID
        if outcome.shouldExitEditing {
            isEditingProvider = false
        }
        if let rebasedDraft = outcome.rebasedDraft {
            draft = rebasedDraft
        }
        if let updatedBaselineDraft = outcome.updatedBaselineDraft {
            baselineDraft = updatedBaselineDraft
        }
        if outcome.shouldReloadDraft {
            await loadSelectedDraft()
        }
    }

    @MainActor
    private func refreshConfigurations(selecting providerID: AIProviderID?) {
        configurations = (try? settingsStore.aiProviderConfigurations()) ?? []
        selectedProviderID = providerID ?? configurations.first?.id
    }

    @MainActor
    private func enableAppleIntelligence() async {
        guard appleIntelligenceAvailability.isSelectable else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let existing = ((try? settingsStore.aiProviderConfigurations()) ?? [])
                .first { $0.id == AppleIntelligenceAIBackend.providerID }
            let configuration = AIProviderConfiguration.appleIntelligence(
                isEnabled: true,
                isDefault: true,
                assignedAccountID: existing?.assignedAccountID
            )
            let onDeviceDraft = AIProviderSettingsDraft(
                configuration: configuration,
                hasSavedAPIKey: false
            )
            let saved = try await AIProviderSettingsPersistence.save(
                onDeviceDraft,
                settingsStore: settingsStore,
                secretStore: secretStore
            )
            let savedDraft = AIProviderSettingsDraft(configuration: saved, hasSavedAPIKey: false)
            draft = savedDraft
            baselineDraft = savedDraft
            refreshConfigurations(selecting: saved.id)
            await onProviderConfigurationChanged()
            isEditingProvider = false
            statusMessage = ProviderStatusMessage(
                message: String(
                    localized: "Apple Intelligence selected for on-device AI. Requests stay on this device.",
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
    private func saveDraft() async {
        await refreshInstalledLocalModels()
        if let blockingReason = editorBlockingReason {
            statusMessage = ProviderStatusMessage(
                message: blockingReason,
                tone: .warning
            )
            return
        }
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
            let savedDraft = AIProviderSettingsDraft(
                configuration: saved,
                hasSavedAPIKey: hasSavedKey
            )
            draft = savedDraft
            baselineDraft = savedDraft
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

/// Resolves the provider selection after cancelling the Add provider editor or refreshing externally.
enum AIProviderEditorPresentation {
    struct RefreshOutcome: Equatable {
        let selectedProviderID: AIProviderID?
        let rebasedDraft: AIProviderSettingsDraft?
        let updatedBaselineDraft: AIProviderSettingsDraft?
        let shouldReloadDraft: Bool
        let shouldExitEditing: Bool
    }

    static func selectionAfterCancellingAdd(
        selectedProviderID: AIProviderID?,
        configuredProviderIDs: [AIProviderID]
    ) -> AIProviderID? {
        selectedProviderID ?? configuredProviderIDs.first
    }

    /// Computes how an external configuration refresh (such as selecting or deleting a local model)
    /// updates the provider panel via a field-level three-way rebase:
    /// user-edited fields stay intact, untouched fields pull the latest stored values, and
    /// `updatedBaselineDraft` advances to the latest stored configuration.
    static func stateAfterExternalRefresh(
        isEditingProvider: Bool,
        selectedProviderID: AIProviderID?,
        currentDraft: AIProviderSettingsDraft,
        baselineDraft: AIProviderSettingsDraft?,
        updatedConfigurations: [AIProviderConfiguration]
    ) -> RefreshOutcome {
        let fallbackSelection = updatedConfigurations.first(where: \.isDefault)?.id
            ?? updatedConfigurations.first?.id

        guard isEditingProvider else {
            let preserved = selectedProviderID.flatMap { id in
                updatedConfigurations.contains(where: { $0.id == id }) ? id : nil
            }
            return RefreshOutcome(
                selectedProviderID: preserved ?? fallbackSelection,
                rebasedDraft: nil,
                updatedBaselineDraft: nil,
                shouldReloadDraft: true,
                shouldExitEditing: false
            )
        }

        // Adding a new provider: never clobber the unsaved draft.
        guard let selectedProviderID else {
            return RefreshOutcome(
                selectedProviderID: nil,
                rebasedDraft: nil,
                updatedBaselineDraft: nil,
                shouldReloadDraft: false,
                shouldExitEditing: false
            )
        }

        // Edited provider was removed externally: fall back cleanly.
        guard let latestConfig = updatedConfigurations.first(where: { $0.id == selectedProviderID }) else {
            return RefreshOutcome(
                selectedProviderID: fallbackSelection,
                rebasedDraft: nil,
                updatedBaselineDraft: nil,
                shouldReloadDraft: true,
                shouldExitEditing: updatedConfigurations.isEmpty
            )
        }

        let latestDraft = AIProviderSettingsDraft(
            configuration: latestConfig,
            hasSavedAPIKey: currentDraft.hasSavedAPIKey
        )
        let rebased = rebaseDraft(
            current: currentDraft,
            baseline: baselineDraft,
            latest: latestDraft
        )
        return RefreshOutcome(
            selectedProviderID: selectedProviderID,
            rebasedDraft: rebased,
            updatedBaselineDraft: latestDraft,
            shouldReloadDraft: false,
            shouldExitEditing: false
        )
    }

    /// Performs a field-level three-way merge between `current` (user edits), `baseline`
    /// (loaded snapshot), and `latest` (updated stored configuration).
    private static func rebaseDraft(
        current: AIProviderSettingsDraft,
        baseline: AIProviderSettingsDraft?,
        latest: AIProviderSettingsDraft
    ) -> AIProviderSettingsDraft {
        guard let baseline else { return current }
        return AIProviderSettingsDraft(
            id: latest.id,
            kind: current.kind != baseline.kind ? current.kind : latest.kind,
            displayName: current.displayName != baseline.displayName ? current.displayName : latest.displayName,
            endpointURLString: current.endpointURLString != baseline.endpointURLString
                ? current.endpointURLString
                : latest.endpointURLString,
            modelID: current.modelID != baseline.modelID ? current.modelID : latest.modelID,
            isEnabled: current.isEnabled != baseline.isEnabled ? current.isEnabled : latest.isEnabled,
            isDefault: current.isDefault != baseline.isDefault ? current.isDefault : latest.isDefault,
            assignedAccountID: current.assignedAccountID != baseline.assignedAccountID
                ? current.assignedAccountID
                : latest.assignedAccountID,
            pendingAPIKey: current.pendingAPIKey,
            hasSavedAPIKey: current.hasSavedAPIKey
        )
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
