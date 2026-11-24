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
import Foundation
import Observation

/// Coordinates device-local closed-app push relay configuration, origin-scoped
/// Keychain bearer credentials, opaque account token mapping, JMAP RFC 8620 §7.2.2
/// verification, and concurrent-disable reconciliation (#11).
@MainActor
@Observable
public final class PushRelayRegistrationController {
    /// Persisted device-local settings (always free of invalid/credential URLs).
    public private(set) var settings: PushRelaySettings
    /// Unsaved draft text for the HTTPS push relay / JMAP API endpoint URL.
    public var endpointDraft: String
    /// Unsaved draft text for the separate HTTPS JMAP WebPush delivery receiver URL.
    public var webPushDeliveryURLDraft: String
    /// Unsaved draft text for a new Keychain bearer token for the current endpoint origin.
    public var bearerTokenInput = ""
    /// Unsaved draft text for an RFC 8620 §7.2.2 JMAP verification code.
    public var verificationCodeInput = ""
    /// Whether a Keychain bearer token is currently saved for `endpointDraft`'s normalized origin.
    public private(set) var hasSavedBearerToken = false
    /// Whether a registration, verification, or unregistration request is currently in flight.
    public private(set) var isWorking = false

    private let settingsStore: SettingsPersistenceStore
    private let secretStore: any PushRelaySecretStore
    private let client: PushRelayClient
    private let devicePushTokenProvider: () -> String?
    private let now: () -> Date
    private var pendingDisableCleanup = false

    /// Creates a push relay controller with injectable storage, client, and APNs token seams.
    public init(
        settingsStore: SettingsPersistenceStore = .standard,
        secretStore: any PushRelaySecretStore = PushRelayKeychainSecretStore(),
        client: PushRelayClient = PushRelayClient(),
        devicePushTokenProvider: @escaping () -> String? = { nil },
        now: @escaping () -> Date = { Date() }
    ) {
        self.settingsStore = settingsStore
        self.secretStore = secretStore
        self.client = client
        self.devicePushTokenProvider = devicePushTokenProvider
        self.now = now
        let loaded = settingsStore.pushRelaySettings()
        settings = loaded
        endpointDraft = loaded.endpointURLString
        webPushDeliveryURLDraft = loaded.webPushDeliveryURLString
        refreshSavedBearerTokenIndicator()
    }

    /// Current platform-supplied APNs device token, if available on this build.
    public var availableDevicePushToken: String? {
        let trimmed = devicePushTokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Inline validation error for `endpointDraft`, or `nil` when blank or valid HTTPS without credentials.
    public var endpointValidationError: String? {
        let trimmed = endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            _ = try PushRelayEndpointValidator.validate(trimmed)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Inline validation error for `webPushDeliveryURLDraft` in `.jmapWebPush` mode.
    public var webPushDeliveryValidationError: String? {
        guard settings.mode == .jmapWebPush else { return nil }
        let trimmed = webPushDeliveryURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let deliveryURL = try PushRelayEndpointValidator.validate(trimmed)
            if let apiURL = try? PushRelayEndpointValidator.validate(endpointDraft),
               PushRelayEndpointValidator.representsSameDestination(apiURL, deliveryURL) {
                return PushRelayClientError.webPushDeliveryURLMatchesAPIEndpoint.errorDescription
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Whether the current draft configuration is eligible to register or refresh.
    public var canRegister: Bool {
        guard settings.isEnabled, settings.mode != .disabled else { return false }
        guard !settings.enabledAccountIDs.isEmpty else { return false }
        guard let apiURL = try? PushRelayEndpointValidator.validate(endpointDraft) else { return false }
        switch settings.mode {
        case .userHostedRelay:
            return availableDevicePushToken != nil
        case .jmapWebPush:
            guard let deliveryURL = try? PushRelayEndpointValidator.validate(webPushDeliveryURLDraft) else {
                return false
            }
            return !PushRelayEndpointValidator.representsSameDestination(apiURL, deliveryURL)
        case .disabled:
            return false
        }
    }

    /// Whether an active remote registration exists and can be unregistered.
    public var canUnregister: Bool {
        settings.activeRegistration != nil
    }

    /// Whether the active registration is a JMAP subscription awaiting RFC 8620 §7.2.2 verification.
    public var isAwaitingJMAPVerification: Bool {
        guard let active = settings.activeRegistration else { return false }
        return active.mode == .jmapWebPush && active.state == .pendingVerification
    }

    /// Updates `endpointDraft`, persisting ONLY when blank or valid HTTPS with zero credentials,
    /// and refreshes the origin-scoped Keychain bearer indicator.
    public func updateEndpointDraft(_ value: String) {
        let previousOrigin = try? PushRelayEndpointValidator.originKey(from: endpointDraft)
        endpointDraft = value
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            settings.endpointURLString = ""
            settingsStore.save(settings)
        } else if let validated = try? PushRelayEndpointValidator.validate(trimmed) {
            settings.endpointURLString = validated.absoluteString
            settingsStore.save(settings)
        }
        let nextOrigin = try? PushRelayEndpointValidator.originKey(from: value)
        if previousOrigin != nextOrigin {
            bearerTokenInput = ""
        }
        refreshSavedBearerTokenIndicator()
    }

    /// Updates `webPushDeliveryURLDraft`, persisting ONLY when blank or valid HTTPS with zero credentials.
    public func updateWebPushDeliveryURLDraft(_ value: String) {
        webPushDeliveryURLDraft = value
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            settings.webPushDeliveryURLString = ""
            settingsStore.save(settings)
        } else if let validated = try? PushRelayEndpointValidator.validate(trimmed) {
            settings.webPushDeliveryURLString = validated.absoluteString
            settingsStore.save(settings)
        }
    }

    /// Updates the transport mode without clobbering `activeRegistration`.
    public func setMode(_ mode: PushRelayMode) {
        settings.mode = mode
        settingsStore.save(settings)
    }

    /// Updates per-account opt-in, generating an opaque device-local account token when enabled.
    public func setAccount(_ accountID: String, enabled: Bool) {
        settings.setAccount(accountID, enabled: enabled)
        settingsStore.save(settings)
    }

    /// Clears the saved Keychain bearer token strictly for the current draft endpoint's origin.
    public func clearSavedBearerTokenForCurrentOrigin() {
        guard let origin = try? PushRelayEndpointValidator.originKey(from: endpointDraft) else {
            bearerTokenInput = ""
            hasSavedBearerToken = false
            return
        }
        try? secretStore.saveBearerToken(nil, forOrigin: origin)
        bearerTokenInput = ""
        hasSavedBearerToken = false
    }

    /// Toggles closed-app push on or off, scheduling or performing clean unregistration when turned off.
    public func setEnabled(_ newValue: Bool) async {
        settings.isEnabled = newValue
        if newValue {
            pendingDisableCleanup = false
            if settings.mode == .disabled {
                settings.mode = .userHostedRelay
            }
            _ = settings.ensureDeviceClientID()
            settingsStore.save(settings)
            return
        }

        settings.lastRegistrationError = nil
        settingsStore.save(settings)

        if isWorking {
            // An in-flight register will see `isEnabled == false` upon completion and unregister immediately.
            pendingDisableCleanup = true
            return
        }
        if settings.activeRegistration != nil {
            await unregisterActiveRegistration()
        }
    }

    /// Registers or refreshes the subscription against the current validated draft target.
    ///
    /// - Sends ONLY device-local opaque account tokens (`acct-<uuid>`), never raw email IDs.
    /// - Uses ONLY the Keychain bearer token scoped to the target origin.
    /// - Creates a fresh subscription when target URL/mode changed and unregisters the old target cleanly.
    /// - If push was disabled while this call was in flight, immediately unregisters the returned subscription.
    public func register() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let endpointURL = try PushRelayEndpointValidator.validate(endpointDraft)
            let endpointOrigin = PushRelayEndpointValidator.originKey(for: endpointURL)
            let targetMode = settings.mode
            var validatedDeliveryURLString: String?

            switch targetMode {
            case .disabled:
                throw PushRelayClientError.disabled
            case .userHostedRelay:
                guard availableDevicePushToken != nil else {
                    throw PushRelayClientError.missingDevicePushToken
                }
            case .jmapWebPush:
                let deliveryURL = try PushRelayEndpointValidator.validate(webPushDeliveryURLDraft)
                guard !PushRelayEndpointValidator.representsSameDestination(endpointURL, deliveryURL) else {
                    throw PushRelayClientError.webPushDeliveryURLMatchesAPIEndpoint
                }
                validatedDeliveryURLString = deliveryURL.absoluteString
            }

            let bearerToken = try persistPendingBearerTokenIfNeeded(forOrigin: endpointOrigin)
            let keyMaterial = try secretStore.loadOrCreateEncryptionKeyMaterial()
            let publicKeys = try keyMaterial.publicKeys()

            let clientID = settings.ensureDeviceClientID()
            let opaqueTokens = settings.opaqueTokensForEnabledAccounts()
            settings.endpointURLString = endpointURL.absoluteString
            if let validatedDeliveryURLString {
                settings.webPushDeliveryURLString = validatedDeliveryURLString
            }
            settingsStore.save(settings)

            let previousActive = settings.activeRegistration
            let matchesPreviousTarget = previousActive?.matchesTarget(
                mode: targetMode,
                endpointURLString: endpointURL.absoluteString,
                webPushDeliveryURLString: validatedDeliveryURLString
            ) ?? false

            let request = PushRelayRegistrationRequest(
                mode: targetMode,
                deviceClientID: clientID,
                devicePushToken: targetMode == .userHostedRelay ? (availableDevicePushToken ?? "") : "",
                webPushDeliveryURL: validatedDeliveryURLString,
                accountIDs: opaqueTokens,
                keys: publicKeys
            )

            let response: PushRelayRegistrationResponse
            if matchesPreviousTarget, let existingID = previousActive?.subscriptionID {
                response = try await client.refresh(
                    endpointURLString: endpointURL.absoluteString,
                    subscriptionID: existingID,
                    request: request,
                    bearerToken: bearerToken
                )
            } else {
                response = try await client.register(
                    endpointURLString: endpointURL.absoluteString,
                    request: request,
                    bearerToken: bearerToken
                )
            }

            let newRegistration = ActivePushRelayRegistration(
                mode: targetMode,
                endpointURLString: endpointURL.absoluteString,
                webPushDeliveryURLString: validatedDeliveryURLString,
                subscriptionID: response.subscriptionID,
                state: response.state,
                registeredAt: now()
            )

            // Reconcile concurrent disable: if the user turned push off while awaiting the server,
            // immediately unregister the newly returned subscription (and any superseded previous one).
            let stillEnabled = settings.isEnabled && settingsStore.pushRelaySettings().isEnabled && !pendingDisableCleanup
            if !stillEnabled {
                pendingDisableCleanup = false
                do {
                    try await performUnregister(registration: newRegistration, opaqueTokens: opaqueTokens)
                    if let previousActive, !matchesPreviousTarget {
                        try? await performUnregister(registration: previousActive, opaqueTokens: opaqueTokens)
                    }
                    settings.activeRegistration = nil
                    settings.lastRegistrationError = nil
                } catch {
                    settings.activeRegistration = newRegistration
                    settings.lastRegistrationError = error.localizedDescription
                }
                settingsStore.save(settings)
                return
            }

            // Target changed: clean up the superseded registration on the old relay/server.
            var cleanupWarning: String?
            if let previousActive, !matchesPreviousTarget {
                do {
                    try await performUnregister(registration: previousActive, opaqueTokens: opaqueTokens)
                } catch {
                    cleanupWarning = error.localizedDescription
                }
            }

            settings.activeRegistration = newRegistration
            settings.lastRegistrationError = cleanupWarning
            if let inlineCode = response.verificationCode, !inlineCode.isEmpty {
                verificationCodeInput = inlineCode
            }
            settingsStore.save(settings)
        } catch {
            settings.lastRegistrationError = error.localizedDescription
            settingsStore.save(settings)
        }
    }

    /// Completes RFC 8620 §7.2.2 JMAP verification for the active `.pendingVerification` subscription,
    /// transitioning its state to `.active` only after the JMAP server accepts the `update`.
    public func verifyActiveJMAPSubscription(code: String? = nil) async {
        guard !isWorking else { return }
        guard var active = settings.activeRegistration, active.mode == .jmapWebPush else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let trimmedCode = (code ?? verificationCodeInput).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedCode.isEmpty else {
                throw PushRelayClientError.missingVerificationCode
            }
            let origin = active.endpointOrigin
            let bearerToken = try origin.flatMap { try secretStore.bearerToken(forOrigin: $0) }
            let verified = try await client.verifyJMAPSubscription(
                endpointURLString: active.endpointURLString,
                subscriptionID: active.subscriptionID,
                verificationCode: trimmedCode,
                bearerToken: bearerToken
            )
            active.state = verified.state
            active.registeredAt = now()
            settings.activeRegistration = active
            settings.lastRegistrationError = nil
            verificationCodeInput = ""
            settingsStore.save(settings)
        } catch {
            settings.lastRegistrationError = error.localizedDescription
            settingsStore.save(settings)
        }
    }

    /// Unregisters the currently active remote subscription using its stored endpoint, mode,
    /// and origin-scoped bearer token. Retains `activeRegistration` if the server rejects deletion.
    public func unregisterActiveRegistration() async {
        guard !isWorking else { return }
        guard let active = settings.activeRegistration else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let opaqueTokens = settings.opaqueTokensForEnabledAccounts()
            try await performUnregister(registration: active, opaqueTokens: opaqueTokens)
            settings.activeRegistration = nil
            settings.lastRegistrationError = nil
            settingsStore.save(settings)
        } catch {
            settings.lastRegistrationError = error.localizedDescription
            settingsStore.save(settings)
        }
    }

    // MARK: - Private helpers

    private func refreshSavedBearerTokenIndicator() {
        guard let origin = try? PushRelayEndpointValidator.originKey(from: endpointDraft) else {
            hasSavedBearerToken = false
            return
        }
        hasSavedBearerToken = (try? secretStore.bearerToken(forOrigin: origin)) != nil
    }

    private func persistPendingBearerTokenIfNeeded(forOrigin origin: String) throws -> String? {
        let trimmedInput = bearerTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInput.isEmpty {
            try secretStore.saveBearerToken(trimmedInput, forOrigin: origin)
            bearerTokenInput = ""
            hasSavedBearerToken = true
            return trimmedInput
        }
        return try secretStore.bearerToken(forOrigin: origin)
    }

    private func performUnregister(
        registration: ActivePushRelayRegistration,
        opaqueTokens: [String]
    ) async throws {
        let clientID = settings.ensureDeviceClientID()
        let bearerToken: String? = if let origin = registration.endpointOrigin {
            try secretStore.bearerToken(forOrigin: origin)
        } else {
            nil
        }
        let request = PushRelayUnregistrationRequest(
            deviceClientID: clientID,
            subscriptionID: registration.subscriptionID,
            accountIDs: opaqueTokens
        )
        try await client.unregister(
            endpointURLString: registration.endpointURLString,
            request: request,
            mode: registration.mode,
            bearerToken: bearerToken
        )
    }
}
