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

/// Opt-in, device-local **Closed-App Push (Self-Hosted)** configuration group
/// embedded in `NotificationSection` (#11).
///
/// Collapsed to a single off-by-default toggle until enabled so users who do
/// not run a self-hosted relay or JMAP server see minimal visual weight and
/// existing notification snapshots remain clean.
struct PushRelaySettingsGroup: View {
    @Environment(\.brevTheme) private var theme
    @State private var settings: PushRelaySettings
    @State private var bearerTokenInput = ""
    @State private var hasSavedBearerToken = false
    @State private var isWorking = false

    private let settingsStore: SettingsPersistenceStore
    private let secretStore: any PushRelaySecretStore
    private let accounts: [BrevAccount]
    private let statusTimeZone: TimeZone
    private let statusLocale: Locale
    private let onRegister: (PushRelaySettings, String?) async throws -> PushRelayRegistrationResponse
    private let onUnregister: (PushRelaySettings, String?) async throws -> Void

    init(
        settingsStore: SettingsPersistenceStore = .standard,
        secretStore: any PushRelaySecretStore = PushRelayKeychainSecretStore(),
        accounts: [BrevAccount] = [],
        statusTimeZone: TimeZone = .current,
        statusLocale: Locale = .current,
        onRegister: ((PushRelaySettings, String?) async throws -> PushRelayRegistrationResponse)? = nil,
        onUnregister: ((PushRelaySettings, String?) async throws -> Void)? = nil
    ) {
        self.settingsStore = settingsStore
        self.secretStore = secretStore
        self.accounts = accounts
        self.statusTimeZone = statusTimeZone
        self.statusLocale = statusLocale
        let loaded = settingsStore.pushRelaySettings()
        _settings = State(initialValue: loaded)
        _hasSavedBearerToken = State(initialValue: (try? secretStore.bearerToken()) != nil)

        self.onRegister = onRegister ?? { currentSettings, bearerToken in
            let client = PushRelayClient()
            let keyMaterial = try secretStore.loadOrCreateEncryptionKeyMaterial()
            let publicKeys = try keyMaterial.publicKeys()
            var mutable = currentSettings
            let clientID = mutable.ensureDeviceClientID()
            let request = PushRelayRegistrationRequest(
                mode: currentSettings.mode,
                deviceClientID: clientID,
                devicePushToken: Self.localDeviceRegistrationToken(for: currentSettings, clientID: clientID),
                accountIDs: Array(currentSettings.enabledAccountIDs).sorted(),
                keys: publicKeys,
                platform: Self.currentPlatformIdentifier
            )
            if let existingID = currentSettings.subscriptionID {
                return try await client.refresh(
                    endpointURLString: currentSettings.endpointURLString,
                    subscriptionID: existingID,
                    request: request,
                    bearerToken: bearerToken
                )
            }
            return try await client.register(
                endpointURLString: currentSettings.endpointURLString,
                request: request,
                bearerToken: bearerToken
            )
        }

        self.onUnregister = onUnregister ?? { currentSettings, bearerToken in
            let client = PushRelayClient()
            let request = PushRelayUnregistrationRequest(
                deviceClientID: currentSettings.deviceClientID,
                subscriptionID: currentSettings.subscriptionID,
                accountIDs: Array(currentSettings.enabledAccountIDs).sorted()
            )
            try await client.unregister(
                endpointURLString: currentSettings.endpointURLString,
                request: request,
                mode: currentSettings.mode,
                bearerToken: bearerToken
            )
        }
    }

    var body: some View {
        SettingsGroup(
            title: String(localized: "Closed-App Push (Self-Hosted)", bundle: .module),
            subtitle: String(
                localized: "Brev never runs a mail proxy or holds your credentials. Connect your own HTTPS push relay or JMAP WebPush server to wake Brev when the app is closed.",
                bundle: .module
            ),
            symbolName: "antenna.radiowaves.left.and.right"
        ) {
            SettingsRowStack(spacing: BrevSpacing.md) {
                SettingsToggleRow(
                    symbolName: "antenna.radiowaves.left.and.right",
                    title: String(localized: "Enable self-hosted closed-app push", bundle: .module),
                    subtitle: String(
                        localized: "Off by default and stored only on this device. Wakes carry only an opaque account hint, never mail bodies or passwords.",
                        bundle: .module
                    ),
                    isOn: enabledBinding
                )

                if settings.isEnabled {
                    enabledConfigurationRows
                }
            }
        }
    }

    @ViewBuilder
    private var enabledConfigurationRows: some View {
        SettingsInfoCallout(
            symbolName: "lock.shield",
            message: String(
                localized: "Push wakes carry only an opaque account hint—never message bodies, subjects, or mail passwords. Relay secrets stay in this device's Keychain and never sync.",
                bundle: .module
            ),
            tone: .info
        )

        SettingsPickerRow(
            symbolName: "arrow.triangle.branch",
            title: String(localized: "Push transport", bundle: .module),
            subtitle: settings.mode.settingsSubtitle,
            selection: modeBinding
        ) {
            ForEach(PushRelayMode.configurableModes) { mode in
                Text(mode.settingsTitle).tag(mode)
            }
        }

        endpointFieldSection
        bearerTokenSection
        accountOptInSection
        actionAndStatusSection
    }

    private var endpointFieldSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            SettingsRowLabel(
                symbolName: "link",
                title: String(localized: "Push relay URL", bundle: .module),
                subtitle: String(
                    localized: "HTTPS endpoint owned by you (credentials in URLs and plain HTTP are rejected).",
                    bundle: .module
                )
            )

            TextField(
                String(localized: "https://push.example.com/register", bundle: .module),
                text: endpointBinding
            )
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            #endif
                .settingsStackedControl()

            if let validationError = endpointValidationError {
                Text(validationError)
                    .brevFont(.caption)
                    .foregroundStyle(theme.danger.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .settingsStackedControl()
            }
        }
    }

    private var bearerTokenSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            SettingsRowLabel(
                symbolName: "key",
                title: String(localized: "Bearer token (optional)", bundle: .module),
                subtitle: String(
                    localized: "Stored only in this device's Keychain and sent as an Authorization header to your relay.",
                    bundle: .module
                )
            )

            HStack(spacing: BrevSpacing.sm) {
                SecureField(
                    hasSavedBearerToken
                        ? String(localized: "Saved in Keychain (enter new value to replace)", bundle: .module)
                        : String(localized: "Optional bearer token", bundle: .module),
                    text: $bearerTokenInput
                )
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif

                if hasSavedBearerToken {
                    SettingsButton(
                        String(localized: "Clear token", bundle: .module),
                        style: .secondary
                    ) {
                        clearSavedBearerToken()
                    }
                }
            }
            .settingsStackedControl()
        }
    }

    private var accountOptInSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            SettingsRowLabel(
                symbolName: "person.2",
                title: String(localized: "Accounts eligible for push wakes", bundle: .module),
                subtitle: String(
                    localized: "Only opaque account identifiers for checked accounts are registered; disabled accounts ignore wakes.",
                    bundle: .module
                )
            )

            if accounts.isEmpty {
                SettingsInfoCallout(
                    symbolName: "person.crop.circle.badge.questionmark",
                    message: String(
                        localized: "Connect an account to choose which mailboxes can wake Brev.",
                        bundle: .module
                    ),
                    tone: .info
                )
            } else {
                VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                    ForEach(accounts) { account in
                        SettingsToggleRow(
                            symbolName: "envelope",
                            title: account.displayName.isEmpty ? account.emailAddress : account.displayName,
                            subtitle: account.emailAddress,
                            isOn: accountBinding(for: account.id)
                        )
                    }
                }
                .padding(BrevSpacing.md)
                .settingsInlineSurface()
            }
        }
    }

    private var actionAndStatusSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            SettingsButtonRow {
                SettingsButton(
                    isWorking
                        ? String(localized: "Working…", bundle: .module)
                        : String(localized: "Test & Register", bundle: .module),
                    style: .primary
                ) {
                    Task { await registerRelay() }
                }
                .disabled(!canRegister || isWorking)

                SettingsButton(
                    String(localized: "Unregister", bundle: .module),
                    style: .secondary
                ) {
                    Task { await unregisterRelay() }
                }
                .disabled(!canUnregister || isWorking)
            }

            statusReadout
        }
    }

    @ViewBuilder
    private var statusReadout: some View {
        if let errorMessage = settings.lastRegistrationError {
            SettingsInfoCallout(
                symbolName: "exclamationmark.triangle",
                message: errorMessage,
                tone: .warning
            )
        } else if let registeredAt = settings.lastRegisteredAt {
            HStack(spacing: BrevSpacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.success.color)
                Text(
                    String(
                        localized: "Registered with relay • \(formattedStatusDate(registeredAt))",
                        bundle: .module
                    )
                )
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            }
        } else {
            Text("Not registered with a relay yet.", bundle: .module)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
        }
    }

    private var endpointValidationError: String? {
        let trimmed = settings.endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            _ = try PushRelayEndpointValidator.validate(trimmed)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var canRegister: Bool {
        guard settings.isEnabled, settings.mode != .disabled else { return false }
        guard !settings.enabledAccountIDs.isEmpty else { return false }
        return (try? settings.validatedEndpointURL()) != nil
    }

    private var canUnregister: Bool {
        guard (try? settings.validatedEndpointURL()) != nil else { return false }
        return settings.lastRegisteredAt != nil || settings.subscriptionID != nil
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { newValue in
                let previousSettings = settings
                settings.isEnabled = newValue
                if newValue {
                    if settings.mode == .disabled {
                        settings.mode = .userHostedRelay
                    }
                    _ = settings.ensureDeviceClientID()
                } else {
                    settings.lastRegistrationError = nil
                }
                settingsStore.save(settings)

                if !newValue, previousSettings.subscriptionID != nil || previousSettings.lastRegisteredAt != nil {
                    Task { await unregisterRelay(using: previousSettings) }
                }
            }
        )
    }

    private var modeBinding: Binding<PushRelayMode> {
        Binding(
            get: { settings.mode == .disabled ? .userHostedRelay : settings.mode },
            set: { newValue in
                settings.mode = newValue
                settingsStore.save(settings)
            }
        )
    }

    private var endpointBinding: Binding<String> {
        Binding(
            get: { settings.endpointURLString },
            set: { newValue in
                settings.endpointURLString = newValue
                settingsStore.save(settings)
            }
        )
    }

    private func accountBinding(for accountID: String) -> Binding<Bool> {
        Binding(
            get: { settings.enabledAccountIDs.contains(accountID) },
            set: { isOn in
                settings.setAccount(accountID, enabled: isOn)
                settingsStore.save(settings)
            }
        )
    }

    private func clearSavedBearerToken() {
        try? secretStore.saveBearerToken(nil)
        bearerTokenInput = ""
        hasSavedBearerToken = false
    }

    private func persistPendingBearerTokenIfNeeded() throws -> String? {
        let trimmedInput = bearerTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInput.isEmpty {
            try secretStore.saveBearerToken(trimmedInput)
            bearerTokenInput = ""
            hasSavedBearerToken = true
            return trimmedInput
        }
        return try secretStore.bearerToken()
    }

    @MainActor
    private func registerRelay() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            _ = try settings.validatedEndpointURL()
            let token = try persistPendingBearerTokenIfNeeded()
            _ = settings.ensureDeviceClientID()
            let response = try await onRegister(settings, token)
            settings.subscriptionID = response.subscriptionID
            settings.lastRegisteredAt = Date()
            settings.lastRegistrationError = nil
            settingsStore.save(settings)
        } catch {
            settings.lastRegistrationError = error.localizedDescription
            settingsStore.save(settings)
        }
    }

    @MainActor
    private func unregisterRelay(using snapshot: PushRelaySettings? = nil) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        let target = snapshot ?? settings
        do {
            let token = try secretStore.bearerToken()
            if (try? target.validatedEndpointURL()) != nil {
                try await onUnregister(target, token)
            }
            settings.subscriptionID = nil
            settings.lastRegisteredAt = nil
            settings.lastRegistrationError = nil
            settingsStore.save(settings)
        } catch {
            settings.lastRegistrationError = error.localizedDescription
            settingsStore.save(settings)
        }
    }

    private func formattedStatusDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = statusTimeZone
        formatter.locale = statusLocale
        return formatter.string(from: date)
    }

    private static var currentPlatformIdentifier: String {
        #if os(iOS)
        "ios"
        #else
        "macos"
        #endif
    }

    private static func localDeviceRegistrationToken(
        for settings: PushRelaySettings,
        clientID: String
    ) -> String {
        switch settings.mode {
        case .jmapWebPush:
            settings.endpointURLString
        case .userHostedRelay, .disabled:
            clientID
        }
    }
}
