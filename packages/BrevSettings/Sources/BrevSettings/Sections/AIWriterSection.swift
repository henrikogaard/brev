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

struct AIWriterSection: View {
    @Environment(\.brevTheme) private var theme
    @State private var settings: AIWriterSettings
    @State private var providerSummary: AIWriterSectionProviderSummary
    @State private var providerRefreshRevision = 0

    private let settingsStore: SettingsPersistenceStore
    private let providerSecretStore: any AIProviderSecretStore
    private let accounts: [BrevAccount]
    private let appleIntelligenceAvailability: AppleIntelligenceAvailability
    private let localModelDownloadManager: LocalModelDownloadManager
    private let isLocalModelPlatformSupported: Bool
    private let onProviderConfigurationChanged: () async -> Void

    init(
        settingsStore: SettingsPersistenceStore = .standard,
        providerSecretStore: any AIProviderSecretStore = AIProviderKeychainSecretStore(),
        accounts: [BrevAccount] = [],
        appleIntelligenceAvailability: AppleIntelligenceAvailability = .current(),
        localModelDownloadManager: LocalModelDownloadManager = .shared,
        isLocalModelPlatformSupported: Bool = DefaultLocalModelInferenceRuntime.isPlatformSupported,
        onProviderConfigurationChanged: @escaping () async -> Void = {}
    ) {
        self.settingsStore = settingsStore
        self.providerSecretStore = providerSecretStore
        self.accounts = accounts
        self.appleIntelligenceAvailability = appleIntelligenceAvailability
        self.localModelDownloadManager = localModelDownloadManager
        self.isLocalModelPlatformSupported = isLocalModelPlatformSupported
        self.onProviderConfigurationChanged = onProviderConfigurationChanged
        _settings = State(initialValue: settingsStore.aiWriterSettings())
        _providerSummary = State(
            initialValue: AIWriterSectionProviderSummary.load(
                from: settingsStore,
                accounts: accounts,
                appleIntelligenceAvailability: appleIntelligenceAvailability
            )
        )
    }

    private var configuredProvider: AIProviderConfiguration? {
        providerSummary.configuredProvider
    }

    private var hasNonOnDeviceAccountOverride: Bool {
        providerSummary.hasNonOnDeviceAccountOverride
    }

    private var canToggleProactiveOnDeviceTriage: Bool {
        settings.isAvailable && providerSummary.hasActiveOnDeviceProvider
    }

    var body: some View {
        SectionScaffold(
            title: String(localized: "AI Writer", bundle: .module),
            subtitle: String(
                localized: "Brev sends text only when you invoke it, directly to the provider you choose. Brev does not proxy requests, sell credits, or meter usage.",
                bundle: .module
            )
        ) {
            SettingsGroupStack {
                SettingsGroup(
                    title: String(localized: "Availability", bundle: .module),
                    subtitle: String(localized: "Turn the compose shortcuts on or off.", bundle: .module),
                    symbolName: "wand.and.stars"
                ) {
                    SettingsToggleRow(
                        symbolName: "sparkles",
                        title: String(localized: "Enable AI Writer", bundle: .module),
                        subtitle: String(
                            localized: "Compose shortcuts for rewriting, translating, and polishing drafts.",
                            bundle: .module
                        ),
                        isOn: enabledBinding
                    )

                    providerStatus

                    SettingsToggleRow(
                        symbolName: "text.badge.star",
                        title: String(localized: "Automatic on-device summaries & priority", bundle: .module),
                        subtitle: String(
                            localized: "Generates short thread summaries and Urgent or Needs reply badges automatically only when an on-device AI provider is active. Never sends mail to cloud providers.",
                            bundle: .module
                        ),
                        isOn: proactiveOnDeviceBinding
                    )
                    .disabled(!canToggleProactiveOnDeviceTriage)

                    if let proactiveStatusNote {
                        Text(proactiveStatusNote)
                            .brevFont(.caption)
                            .foregroundStyle(theme.textSecondary.color)
                    }
                }

                AIProviderSettingsPanel(
                    settingsStore: settingsStore,
                    secretStore: providerSecretStore,
                    accounts: accounts,
                    appleIntelligenceAvailability: appleIntelligenceAvailability,
                    localModelDownloadManager: localModelDownloadManager,
                    isLocalModelPlatformSupported: isLocalModelPlatformSupported,
                    refreshRevision: providerRefreshRevision,
                    onProviderConfigurationChanged: {
                        await refreshConfiguredProvider()
                        await onProviderConfigurationChanged()
                    }
                )

                LocalModelsSettingsGroup(
                    downloadManager: localModelDownloadManager,
                    activeModelID: activeDownloadedModelID,
                    isPlatformSupported: isLocalModelPlatformSupported,
                    onSelectModel: { descriptor in
                        await selectDownloadedLocalModel(descriptor)
                    },
                    onModelDeleted: { descriptor in
                        await handleDeletedLocalModel(descriptor)
                    }
                )

                DisclosureGroup(String(localized: "Privacy and consent", bundle: .module)) {
                    VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                        Text(privacySummary)
                            .brevFont(.footnote)
                            .foregroundStyle(theme.textSecondary.color)

                        SettingsButton(String(localized: "Reset AI consent", bundle: .module), style: .secondary) {
                            settings.resetConsent()
                            settingsStore.save(settings)
                        }
                        .disabled(!settings.consentGiven)
                    }
                    .padding(.top, BrevSpacing.xs)
                }
            }
            .task { await refreshConfiguredProvider() }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isAvailable },
            set: { newValue in
                settings.setAvailable(newValue)
                settingsStore.save(settings)
            }
        )
    }

    private var proactiveOnDeviceBinding: Binding<Bool> {
        Binding(
            get: {
                canToggleProactiveOnDeviceTriage && settings.proactiveOnDeviceTriageEnabled
            },
            set: { newValue in
                guard canToggleProactiveOnDeviceTriage || !newValue else { return }
                settings.proactiveOnDeviceTriageEnabled = newValue
                settingsStore.save(settings)
            }
        )
    }

    private var proactiveStatusNote: String? {
        if !settings.isAvailable {
            return String(
                localized: "Turn on AI Writer above and choose an on-device provider to enable automatic summaries.",
                bundle: .module
            )
        }
        if !providerSummary.hasActiveOnDeviceProvider {
            return String(
                localized: "Only available when an on-device AI provider is active. Cloud and BYOK providers require an explicit click.",
                bundle: .module
            )
        }
        if hasNonOnDeviceAccountOverride, settings.proactiveOnDeviceTriageEnabled {
            return String(
                localized: "Runs automatically only for accounts using on-device AI. Accounts with a cloud or BYOK override stay manual.",
                bundle: .module
            )
        }
        return nil
    }

    @ViewBuilder
    private var providerStatus: some View {
        if let configuredProvider {
            Text("Using \(configuredProvider.displayName) · \(configuredProvider.transparencyLabel)", bundle: .module)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
        } else {
            Text("Choose a provider below before AI Writer can send a request.", bundle: .module)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
        }
    }

    private var privacySummary: String {
        let consentState = settings.consentGiven
            ? String(localized: "granted", bundle: .module)
            : String(localized: "not granted", bundle: .module)
        if let configuredProvider {
            if configuredProvider.kind.isOnDevice {
                if hasNonOnDeviceAccountOverride {
                    return String(
                        localized: "Consent is \(consentState). Default AI Writer requests stay on this device (\(configuredProvider.transparencyLabel)); accounts with a custom provider override follow that provider’s policy.",
                        bundle: .module
                    )
                }
                return String(
                    localized: "Consent is \(consentState). When you use AI Writer, text is processed locally (\(configuredProvider.transparencyLabel)) and never leaves this device.",
                    bundle: .module
                )
            }
            return String(
                localized: "Consent is \(consentState). When you use AI Writer, \(configuredProvider.transparencyLabel). Review that provider’s privacy policy before enabling it.",
                bundle: .module
            )
        }
        return String(
            localized: "Consent is \(consentState). AI Writer cannot send anything until you configure a provider.",
            bundle: .module
        )
    }

    private var activeDownloadedModelID: String? {
        guard let configuredProvider,
              configuredProvider.kind == .onDeviceDownloadedModel,
              configuredProvider.isEnabled
        else { return nil }
        return configuredProvider.modelID
    }

    @MainActor
    private func selectDownloadedLocalModel(_ descriptor: LocalModelDescriptor) async {
        guard isLocalModelPlatformSupported else { return }
        let existing = ((try? settingsStore.aiProviderConfigurations()) ?? [])
            .first { $0.id == LocalDownloadedModelAIBackend.providerID }
        let configuration = AIProviderConfiguration.onDeviceDownloadedModel(
            modelID: descriptor.id,
            isEnabled: true,
            isDefault: true,
            assignedAccountID: existing?.assignedAccountID
        )
        let draft = AIProviderSettingsDraft(configuration: configuration, hasSavedAPIKey: false)
        _ = try? await AIProviderSettingsPersistence.save(
            draft,
            settingsStore: settingsStore,
            secretStore: providerSecretStore
        )
        providerRefreshRevision += 1
        await refreshConfiguredProvider()
        await onProviderConfigurationChanged()
    }

    @MainActor
    private func handleDeletedLocalModel(_ descriptor: LocalModelDescriptor) async {
        guard activeDownloadedModelID == descriptor.id else { return }
        try? AIProviderSettingsPersistence.disable(
            providerID: LocalDownloadedModelAIBackend.providerID,
            settingsStore: settingsStore
        )
        providerRefreshRevision += 1
        await refreshConfiguredProvider()
        await onProviderConfigurationChanged()
    }

    @MainActor
    private func refreshConfiguredProvider() async {
        providerSummary = AIWriterSectionProviderSummary.load(
            from: settingsStore,
            accounts: accounts,
            appleIntelligenceAvailability: appleIntelligenceAvailability
        )
    }
}

struct AIWriterSectionProviderSummary: Equatable {
    let configuredProvider: AIProviderConfiguration?
    let hasActiveOnDeviceProvider: Bool
    let hasNonOnDeviceAccountOverride: Bool

    static func load(
        from settingsStore: SettingsPersistenceStore,
        accounts: [BrevAccount],
        appleIntelligenceAvailability: AppleIntelligenceAvailability
    ) -> AIWriterSectionProviderSummary {
        let configurations = (try? settingsStore.aiProviderConfigurations()) ?? []
        let assignments = (try? settingsStore.aiProviderAssignments()) ?? AIProviderAccountAssignments()
        return evaluate(
            configurations: configurations,
            assignments: assignments,
            accounts: accounts,
            appleIntelligenceAvailability: appleIntelligenceAvailability
        )
    }

    static func evaluate(
        configurations: [AIProviderConfiguration],
        assignments: AIProviderAccountAssignments,
        accounts: [BrevAccount],
        appleIntelligenceAvailability: AppleIntelligenceAvailability
    ) -> AIWriterSectionProviderSummary {
        let configuredProvider = configurations.first(where: \.isDefault)
            ?? configurations.first
        let providersByID = Dictionary(uniqueKeysWithValues: configurations.map { ($0.id, $0) })
        let legacyOverrideByAccountID: [String: AIProviderConfiguration] = configurations.reduce(into: [:]) { map, config in
            guard let accountID = config.assignedAccountID, map[accountID] == nil else { return }
            map[accountID] = config
        }
        let allAccountIDs = Set(accounts.map(\.id)).union(legacyOverrideByAccountID.keys)

        func isUsableOnDevice(_ provider: AIProviderConfiguration) -> Bool {
            guard provider.isEnabled,
                  provider.kind.isOnDevice,
                  provider.validationIssues.isEmpty
            else { return false }
            if provider.kind == .appleIntelligence {
                return appleIntelligenceAvailability.isSelectable
            }
            return true
        }

        // Mirror `AIProviderResolver` routing strictly: only an explicit default provider
        // (`isDefault == true`) or an explicit account assignment can make an account active.
        let usableDefaultProvider = configurations.first {
            $0.isDefault && $0.isEnabled && $0.validationIssues.isEmpty
        }

        let hasNonOnDeviceAccountOverride = allAccountIDs.contains { accountID in
            if let assignedProviderID = assignments.providerID(forAccountID: accountID) {
                guard let provider = providersByID[assignedProviderID] else { return false }
                return provider.isEnabled && !provider.kind.isOnDevice
            }
            guard let legacyProvider = legacyOverrideByAccountID[accountID] else { return false }
            return legacyProvider.isEnabled && !legacyProvider.kind.isOnDevice
        }

        let hasActiveOnDeviceRoute: Bool
        if allAccountIDs.isEmpty {
            hasActiveOnDeviceRoute = usableDefaultProvider.map(isUsableOnDevice) ?? false
        } else {
            hasActiveOnDeviceRoute = allAccountIDs.contains { accountID in
                if let assignedProviderID = assignments.providerID(forAccountID: accountID) {
                    guard let provider = providersByID[assignedProviderID] else { return false }
                    return isUsableOnDevice(provider)
                }
                if let legacyProvider = legacyOverrideByAccountID[accountID] {
                    return isUsableOnDevice(legacyProvider)
                }
                return usableDefaultProvider.map(isUsableOnDevice) ?? false
            }
        }

        return AIWriterSectionProviderSummary(
            configuredProvider: configuredProvider,
            hasActiveOnDeviceProvider: hasActiveOnDeviceRoute,
            hasNonOnDeviceAccountOverride: hasNonOnDeviceAccountOverride
        )
    }
}
