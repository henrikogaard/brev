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
    @State private var configuredProvider: AIProviderConfiguration?

    private let settingsStore: SettingsPersistenceStore
    private let providerSecretStore: any AIProviderSecretStore
    private let accounts: [BrevAccount]
    private let onProviderConfigurationChanged: () async -> Void

    init(
        settingsStore: SettingsPersistenceStore = .standard,
        providerSecretStore: any AIProviderSecretStore = AIProviderKeychainSecretStore(),
        accounts: [BrevAccount] = [],
        onProviderConfigurationChanged: @escaping () async -> Void = {}
    ) {
        self.settingsStore = settingsStore
        self.providerSecretStore = providerSecretStore
        self.accounts = accounts
        self.onProviderConfigurationChanged = onProviderConfigurationChanged
        _settings = State(initialValue: settingsStore.aiWriterSettings())
    }

    var body: some View {
        SectionScaffold(
            title: String(localized: "AI Writer", bundle: .module),
            subtitle: String(
                localized: "Brev sends text only when you invoke it, directly to the provider you choose. Brev does not proxy requests, sell credits, or meter usage.",
                bundle: .module
            )
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
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
                }

                AIProviderSettingsPanel(
                    settingsStore: settingsStore,
                    secretStore: providerSecretStore,
                    accounts: accounts,
                    onProviderConfigurationChanged: {
                        await refreshConfiguredProvider()
                        await onProviderConfigurationChanged()
                    }
                )

                DisclosureGroup(String(localized: "Privacy and consent", bundle: .module)) {
                    VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                        Text(privacySummary)
                            .brevFont(.footnote)
                            .foregroundStyle(theme.textSecondary.color)

                        BrevButton(String(localized: "Reset AI consent", bundle: .module), style: .secondary) {
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

    @MainActor
    private func refreshConfiguredProvider() async {
        let configurations = (try? settingsStore.aiProviderConfigurations()) ?? []
        configuredProvider = configurations.first(where: \.isDefault) ?? configurations.first
    }
}
