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
import BrevSettings
import Foundation

/// Outcome of processing an incoming silent-push / self-hosted relay wake (#11).
public enum PushWakeHandlingResult: Equatable, Sendable {
    /// Triggered a bounded incremental refresh for the opted-in account.
    case synced(accountID: String)
    /// Ignored because closed-app push is turned off on this device.
    case ignoredDisabled
    /// Ignored because the targeted account is not opted in on this device.
    case ignoredAccountNotOptedIn(accountID: String)
    /// Ignored because the targeted account is not connected in the current session.
    case ignoredAccountNotConnected(accountID: String)
    /// Ignored because the incoming payload was missing required fields or malformed.
    case ignoredInvalidPayload
    /// Sync was attempted for the opted-in account and returned an error summary.
    case failed(accountID: String, message: String)

    /// Localized diagnostic summary of how the wake event was handled.
    public var statusSummary: String {
        switch self {
        case .synced:
            String(localized: "Synced account after closed-app push wake.", bundle: .module)
        case .ignoredDisabled:
            String(localized: "Ignored push wake because closed-app push is disabled.", bundle: .module)
        case .ignoredAccountNotOptedIn:
            String(localized: "Ignored push wake because the account is not opted in.", bundle: .module)
        case .ignoredAccountNotConnected:
            String(localized: "Ignored push wake because the account is not connected.", bundle: .module)
        case .ignoredInvalidPayload:
            String(localized: "Ignored malformed push wake payload.", bundle: .module)
        case .failed(_, let message):
            String(localized: "Push wake sync failed: \(message)", bundle: .module)
        }
    }
}

/// Handles opaque incoming push wakes from a user-hosted HTTPS relay or
/// JMAP WebPush subscription (#11).
///
/// Wakes carry only an opaque account hint (never mail bodies or credentials).
/// This coordinator strictly verifies device-local opt-in (`PushRelaySettings`)
/// before triggering a bounded incremental sync for the single targeted account
/// through Brev's normal local sync/notification pipeline.
@MainActor
public final class PushWakeCoordinator {
    /// Supplies the currently connected backends when a wake arrives.
    public var backendsProvider: @MainActor () -> [any MailBackend]

    /// Optional cold-launch restoration hook invoked when no backends are loaded yet.
    public var ensureAccountsRestored: (@MainActor () async -> Void)?

    private let settingsProvider: () -> PushRelaySettings
    private let refreshBackends: @Sendable ([any MailBackend]) async -> String?

    /// Creates a wake coordinator with injectable settings, backend, and refresh seams.
    ///
    /// - Parameters:
    ///   - settingsProvider: Reads the current device-local `PushRelaySettings`.
    ///   - backendsProvider: Returns currently connected mail backends.
    ///   - ensureAccountsRestored: Restores accounts on a cold background wake when needed.
    ///   - refreshBackends: Performs a bounded refresh for the matched backend.
    public init(
        settingsProvider: @escaping () -> PushRelaySettings = { PushRelaySettings.load() },
        backendsProvider: @escaping @MainActor () -> [any MailBackend] = { [] },
        ensureAccountsRestored: (@MainActor () async -> Void)? = nil,
        refreshBackends: (@Sendable ([any MailBackend]) async -> String?)? = nil
    ) {
        self.settingsProvider = settingsProvider
        self.backendsProvider = backendsProvider
        self.ensureAccountsRestored = ensureAccountsRestored
        self.refreshBackends = refreshBackends ?? { backends in
            await MailFetchScheduler.performBackgroundRefresh(backends: backends)
        }
    }

    /// Processes a decoded opaque wake payload.
    @discardableResult
    public func handleWake(_ payload: PushWakePayload) async -> PushWakeHandlingResult {
        let settings = settingsProvider()
        guard settings.isEnabled, settings.mode != .disabled else {
            return .ignoredDisabled
        }
        guard settings.enabledAccountIDs.contains(payload.accountID) else {
            return .ignoredAccountNotOptedIn(accountID: payload.accountID)
        }

        var backends = backendsProvider()
        if backends.isEmpty, let ensureAccountsRestored {
            await ensureAccountsRestored()
            backends = backendsProvider()
        }

        guard let targetBackend = backends.first(where: { $0.account.id == payload.accountID }) else {
            return .ignoredAccountNotConnected(accountID: payload.accountID)
        }

        if let failure = await refreshBackends([targetBackend]) {
            return .failed(accountID: payload.accountID, message: failure)
        }
        return .synced(accountID: payload.accountID)
    }

    /// Decodes an APNs/remote-notification `userInfo` dictionary and handles the wake.
    @discardableResult
    public func handleRemoteNotificationUserInfo(
        _ userInfo: [AnyHashable: Any]
    ) async -> PushWakeHandlingResult {
        guard let payload = PushWakePayload(userInfo: userInfo) else {
            return .ignoredInvalidPayload
        }
        return await handleWake(payload)
    }

    /// Decodes a JSON wake payload and handles the wake.
    @discardableResult
    public func handleWakeData(_ data: Data) async -> PushWakeHandlingResult {
        guard let payload = PushWakePayload(jsonData: data) else {
            return .ignoredInvalidPayload
        }
        return await handleWake(payload)
    }
}
