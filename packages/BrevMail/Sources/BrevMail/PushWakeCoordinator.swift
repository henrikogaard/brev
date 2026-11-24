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
    /// Triggered a bounded incremental refresh (and scene-less arrival check) for the opted-in account.
    case synced(accountID: String)
    /// Received an RFC 8620 §7.2.2 JMAP `PushVerification` challenge for the subscription.
    case jmapVerificationChallenge(subscriptionID: String, verificationCode: String)
    /// Ignored because closed-app push is turned off on this device.
    case ignoredDisabled
    /// Ignored because the opaque account token is unknown or the account is not opted in on this device.
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
        case .jmapVerificationChallenge:
            String(localized: "Received JMAP push verification challenge.", bundle: .module)
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

/// Handles opaque incoming push wakes and RFC 8620 §7.2.2 JMAP verification
/// challenges from a user-hosted HTTPS relay or JMAP WebPush server (#11).
///
/// Incoming wakes carry only a device-local opaque account token (`acct-<uuid>`),
/// never email addresses, mail bodies, or credentials. This coordinator resolves
/// the opaque token to a local opted-in `BrevAccount.ID`, runs a bounded refresh
/// for that single backend, and invokes the scene-less arrival/notification seam
/// so new mail alerts can fire even when no SwiftUI scene is mounted.
@MainActor
public final class PushWakeCoordinator {
    /// Supplies the currently connected backends when a wake arrives.
    public var backendsProvider: @MainActor () -> [any MailBackend]

    /// Optional cold-launch restoration hook invoked when no backends are loaded yet.
    public var ensureAccountsRestored: (@MainActor () async -> Void)?

    /// Optional handler invoked when an RFC 8620 §7.2.2 JMAP `PushVerification` challenge arrives.
    public var onJMAPVerificationChallenge: (@MainActor (_ subscriptionID: String, _ verificationCode: String) async -> Void)?

    private let settingsProvider: () -> PushRelaySettings
    private let refreshBackends: @Sendable ([any MailBackend]) async -> String?
    private let notifyArrivedMail: @MainActor (any MailBackend, PushWakePayload) async -> Void

    /// Creates a wake coordinator with injectable settings, backend, refresh, and notification seams.
    ///
    /// - Parameters:
    ///   - settingsProvider: Reads the current device-local `PushRelaySettings`.
    ///   - backendsProvider: Returns currently connected mail backends.
    ///   - ensureAccountsRestored: Restores accounts on a cold background wake when needed.
    ///   - refreshBackends: Performs a bounded refresh for the matched backend.
    ///   - notifyArrivedMail: Scene-less arrival notification check invoked after a successful refresh.
    public init(
        settingsProvider: @escaping () -> PushRelaySettings = { PushRelaySettings.load() },
        backendsProvider: @escaping @MainActor () -> [any MailBackend] = { [] },
        ensureAccountsRestored: (@MainActor () async -> Void)? = nil,
        refreshBackends: (@Sendable ([any MailBackend]) async -> String?)? = nil,
        notifyArrivedMail: (@MainActor (any MailBackend, PushWakePayload) async -> Void)? = nil
    ) {
        self.settingsProvider = settingsProvider
        self.backendsProvider = backendsProvider
        self.ensureAccountsRestored = ensureAccountsRestored
        self.refreshBackends = refreshBackends ?? { backends in
            await MailFetchScheduler.performBackgroundRefresh(backends: backends)
        }
        self.notifyArrivedMail = notifyArrivedMail ?? { backend, payload in
            await Self.deliverSceneLessNotificationIfNeeded(for: backend, payload: payload)
        }
    }

    /// Processes a decoded opaque wake payload or JMAP verification challenge.
    @discardableResult
    public func handleWake(_ payload: PushWakePayload) async -> PushWakeHandlingResult {
        let settings = settingsProvider()
        guard settings.isEnabled, settings.mode != .disabled else {
            return .ignoredDisabled
        }

        if payload.isJMAPVerificationChallenge,
           let subscriptionID = payload.pushSubscriptionID,
           let verificationCode = payload.verificationCode {
            await onJMAPVerificationChallenge?(subscriptionID, verificationCode)
            return .jmapVerificationChallenge(
                subscriptionID: subscriptionID,
                verificationCode: verificationCode
            )
        }

        guard let resolvedAccountID = settings.resolveAccountID(forOpaqueToken: payload.accountID) else {
            return .ignoredAccountNotOptedIn(accountID: payload.accountID)
        }

        var backends = backendsProvider()
        if backends.isEmpty, let ensureAccountsRestored {
            await ensureAccountsRestored()
            backends = backendsProvider()
        }

        guard let targetBackend = backends.first(where: { $0.account.id == resolvedAccountID }) else {
            return .ignoredAccountNotConnected(accountID: resolvedAccountID)
        }

        if let failure = await refreshBackends([targetBackend]) {
            return .failed(accountID: resolvedAccountID, message: failure)
        }

        await notifyArrivedMail(targetBackend, payload)
        return .synced(accountID: resolvedAccountID)
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

    /// Evaluates `NewMailNotificationPolicy` and posts a local notification for the
    /// newest unread Inbox message when woken without a mounted SwiftUI scene.
    private static func deliverSceneLessNotificationIfNeeded(
        for backend: any MailBackend,
        payload: PushWakePayload
    ) async {
        guard payload.eventKind == .newMail else { return }
        let notificationSettings = NotificationSettings.load()
        let decision = NewMailNotificationPolicy.decision(
            settings: notificationSettings,
            accountID: backend.account.id
        )
        guard decision.shouldDeliver else { return }
        guard let folders = try? await backend.folders(),
              let inbox = folders.first(where: { $0.role == .inbox }),
              let page = try? await backend.enumerateMessages(in: inbox, pageToken: nil),
              let newest = page.headers.first,
              !newest.isRead
        else {
            return
        }
        let notificationCenter = BrevLocalNotificationCenter()
        await notificationCenter.postNewMailNotification(
            from: newest.from,
            subject: newest.subject,
            snippet: newest.snippet,
            receivedAt: newest.date,
            messageID: newest.id,
            accountID: backend.account.id,
            folderID: inbox.id,
            folderName: inbox.name,
            showPreviews: decision.showPreviews,
            playSound: decision.playSound
        )
    }
}
