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
/// not run a self-hosted relay or JMAP server see minimal visual weight.
struct PushRelaySettingsGroup: View {
    @Environment(\.brevTheme) private var theme
    @State private var controller: PushRelayRegistrationController

    private let accounts: [BrevAccount]
    private let statusTimeZone: TimeZone
    private let statusLocale: Locale

    init(
        settingsStore: SettingsPersistenceStore = .standard,
        secretStore: any PushRelaySecretStore = PushRelayKeychainSecretStore(),
        client: PushRelayClient = PushRelayClient(),
        accounts: [BrevAccount] = [],
        devicePushTokenProvider: @escaping () -> String? = { nil },
        statusTimeZone: TimeZone = .current,
        statusLocale: Locale = .current
    ) {
        self.accounts = accounts
        self.statusTimeZone = statusTimeZone
        self.statusLocale = statusLocale
        _controller = State(
            initialValue: PushRelayRegistrationController(
                settingsStore: settingsStore,
                secretStore: secretStore,
                client: client,
                devicePushTokenProvider: devicePushTokenProvider
            )
        )
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
                        localized: "Off by default and stored only on this device. Wakes carry only an opaque account token, never email addresses, mail bodies, or passwords.",
                        bundle: .module
                    ),
                    isOn: enabledBinding
                )

                if controller.settings.isEnabled {
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
                localized: "Push wakes carry only an opaque device-local account token—never email addresses, message bodies, or mail passwords. Relay secrets stay in this device's Keychain, scoped per relay origin, and never sync.",
                bundle: .module
            ),
            tone: .info
        )

        SettingsPickerRow(
            symbolName: "arrow.triangle.branch",
            title: String(localized: "Push transport", bundle: .module),
            subtitle: controller.settings.mode.settingsSubtitle,
            selection: modeBinding
        ) {
            ForEach(PushRelayMode.configurableModes) { mode in
                Text(mode.settingsTitle).tag(mode)
            }
        }

        if controller.settings.mode == .userHostedRelay,
           controller.availableDevicePushToken == nil {
            SettingsInfoCallout(
                symbolName: "info.circle",
                message: String(
                    localized: "A real APNs device token is required before this device can register with a self-hosted push relay. This build does not have APNs push entitlements enabled.",
                    bundle: .module
                ),
                tone: .info
            )
        }

        endpointFieldSection
        if controller.settings.mode == .jmapWebPush {
            webPushDeliveryFieldSection
        }
        bearerTokenSection
        accountOptInSection
        actionAndStatusSection
        if controller.isAwaitingJMAPVerification {
            jmapVerificationSection
        }
    }

    private var endpointFieldSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            SettingsRowLabel(
                symbolName: "link",
                title: controller.settings.mode == .jmapWebPush
                    ? String(localized: "JMAP API endpoint URL", bundle: .module)
                    : String(localized: "Push relay URL", bundle: .module),
                subtitle: String(
                    localized: "HTTPS endpoint owned by you (credentials in URLs and plain HTTP are rejected and never saved).",
                    bundle: .module
                )
            )

            TextField(
                controller.settings.mode == .jmapWebPush
                    ? String(localized: "https://jmap.example.com/jmap/api/", bundle: .module)
                    : String(localized: "https://push.example.com/register", bundle: .module),
                text: endpointDraftBinding
            )
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            #endif
                .settingsStackedControl()

            if let validationError = controller.endpointValidationError {
                Text(validationError)
                    .brevFont(.caption)
                    .foregroundStyle(theme.danger.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .settingsStackedControl()
            }
        }
    }

    private var webPushDeliveryFieldSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            SettingsRowLabel(
                symbolName: "arrow.down.to.line",
                title: String(localized: "WebPush delivery URL", bundle: .module),
                subtitle: String(
                    localized: "Separate HTTPS receiver URL where your JMAP server posts encrypted RFC 8291 pushes and verification challenges.",
                    bundle: .module
                )
            )

            TextField(
                String(localized: "https://webpush.example.com/push/device", bundle: .module),
                text: webPushDeliveryDraftBinding
            )
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            #endif
                .settingsStackedControl()

            if let validationError = controller.webPushDeliveryValidationError {
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
                    localized: "Stored in this device's Keychain scoped to the relay origin and never reused for another server.",
                    bundle: .module
                )
            )

            HStack(spacing: BrevSpacing.sm) {
                SecureField(
                    controller.hasSavedBearerToken
                        ? String(localized: "Saved in Keychain for this origin (enter new value to replace)", bundle: .module)
                        : String(localized: "Optional bearer token", bundle: .module),
                    text: $controller.bearerTokenInput
                )
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif

                if controller.hasSavedBearerToken {
                    SettingsButton(
                        String(localized: "Clear token", bundle: .module),
                        style: .secondary
                    ) {
                        controller.clearSavedBearerTokenForCurrentOrigin()
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
                    localized: "Only randomly generated opaque tokens for checked accounts are registered; disabled accounts ignore wakes.",
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
                    controller.isWorking
                        ? String(localized: "Working…", bundle: .module)
                        : String(localized: "Test & Register", bundle: .module),
                    style: .primary
                ) {
                    Task { await controller.register() }
                }
                .disabled(!controller.canRegister || controller.isWorking)

                SettingsButton(
                    String(localized: "Unregister", bundle: .module),
                    style: .secondary
                ) {
                    Task { await controller.unregisterActiveRegistration() }
                }
                .disabled(!controller.canUnregister || controller.isWorking)
            }

            statusReadout
        }
    }

    private var jmapVerificationSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            SettingsRowLabel(
                symbolName: "checkmark.shield",
                title: String(localized: "JMAP verification code", bundle: .module),
                subtitle: String(
                    localized: "Enter the RFC 8620 §7.2.2 verification code delivered to your WebPush URL to activate this subscription.",
                    bundle: .module
                )
            )

            HStack(spacing: BrevSpacing.sm) {
                TextField(
                    String(localized: "Verification code", bundle: .module),
                    text: $controller.verificationCodeInput
                )
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif

                SettingsButton(
                    String(localized: "Verify Subscription", bundle: .module),
                    style: .primary
                ) {
                    Task { await controller.verifyActiveJMAPSubscription() }
                }
                .disabled(
                    controller.verificationCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || controller.isWorking
                )
            }
            .settingsStackedControl()
        }
    }

    @ViewBuilder
    private var statusReadout: some View {
        if let errorMessage = controller.settings.lastRegistrationError {
            SettingsInfoCallout(
                symbolName: "exclamationmark.triangle",
                message: errorMessage,
                tone: .warning
            )
        } else if let active = controller.settings.activeRegistration {
            switch active.state {
            case .pendingVerification:
                HStack(spacing: BrevSpacing.xs) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(theme.warning.color)
                    Text(
                        String(
                            localized: "Pending JMAP verification • \(formattedStatusDate(active.registeredAt))",
                            bundle: .module
                        )
                    )
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                }
            case .active:
                HStack(spacing: BrevSpacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.success.color)
                    Text(
                        String(
                            localized: "Registered with relay • \(formattedStatusDate(active.registeredAt))",
                            bundle: .module
                        )
                    )
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                }
            }
        } else {
            Text("Not registered with a relay yet.", bundle: .module)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { controller.settings.isEnabled },
            set: { newValue in
                Task { await controller.setEnabled(newValue) }
            }
        )
    }

    private var modeBinding: Binding<PushRelayMode> {
        Binding(
            get: { controller.settings.mode == .disabled ? .userHostedRelay : controller.settings.mode },
            set: { controller.setMode($0) }
        )
    }

    private var endpointDraftBinding: Binding<String> {
        Binding(
            get: { controller.endpointDraft },
            set: { controller.updateEndpointDraft($0) }
        )
    }

    private var webPushDeliveryDraftBinding: Binding<String> {
        Binding(
            get: { controller.webPushDeliveryURLDraft },
            set: { controller.updateWebPushDeliveryURLDraft($0) }
        )
    }

    private func accountBinding(for accountID: String) -> Binding<Bool> {
        Binding(
            get: { controller.settings.enabledAccountIDs.contains(accountID) },
            set: { controller.setAccount(accountID, enabled: $0) }
        )
    }

    private func formattedStatusDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = statusTimeZone
        formatter.locale = statusLocale
        return formatter.string(from: date)
    }
}
