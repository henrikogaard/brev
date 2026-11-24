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

/// Platform-independent background fetch outcome mapped to `UIBackgroundFetchResult` on iOS (#11).
public enum PushWakeFetchOutcome: Equatable, Sendable {
    /// At least one account synced new data or a JMAP verification challenge was handled.
    case newData
    /// Wake was ignored or succeeded without new data arriving.
    case noData
    /// Every attempted account refresh failed.
    case failed
}

/// Outcome of processing an incoming silent-push / self-hosted relay wake (#11).
public enum PushWakeHandlingResult: Equatable, Sendable {
    /// Triggered a bounded incremental refresh and observed new data/arrivals for an opted-in account.
    case synced(accountID: String)
    /// Triggered a bounded incremental refresh for an opted-in account with no newly arrived data.
    case syncedNoNewData(accountID: String)
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
    /// Every attempted account sync failed and returned an error summary.
    case failed(accountID: String, message: String)

    /// Platform-independent fetch outcome suitable for iOS `UIBackgroundFetchResult`.
    public var fetchOutcome: PushWakeFetchOutcome {
        switch self {
        case .synced, .jmapVerificationChallenge:
            .newData
        case .syncedNoNewData, .ignoredDisabled, .ignoredAccountNotOptedIn,
             .ignoredAccountNotConnected, .ignoredInvalidPayload:
            .noData
        case .failed:
            .failed
        }
    }

    /// Localized diagnostic summary of how the wake event was handled.
    public var statusSummary: String {
        switch self {
        case .synced, .syncedNoNewData:
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

/// Newly arrived unread Inbox message metadata passed to local notification delivery
/// after a closed-app push wake diffs Inbox headers before and after sync (#11).
public struct PushWakeArrivedMessage: Equatable, Sendable {
    /// Local message identifier.
    public let messageID: String
    /// Sender address metadata.
    public let from: Correspondent
    /// Message subject line.
    public let subject: String
    /// Short preview snippet.
    public let snippet: String
    /// Message receipt timestamp.
    public let receivedAt: Date
    /// Local Brev account identifier.
    public let accountID: String
    /// Local Inbox folder identifier.
    public let folderID: String
    /// Localized Inbox folder display name.
    public let folderName: String
    /// Whether notification policy permits showing message previews.
    public let showPreviews: Bool
    /// Whether notification policy permits playing a sound.
    public let playSound: Bool

    /// Creates an arrived-message notification payload.
    public init(
        messageID: String,
        from: Correspondent,
        subject: String,
        snippet: String,
        receivedAt: Date,
        accountID: String,
        folderID: String,
        folderName: String,
        showPreviews: Bool,
        playSound: Bool
    ) {
        self.messageID = messageID
        self.from = from
        self.subject = subject
        self.snippet = snippet
        self.receivedAt = receivedAt
        self.accountID = accountID
        self.folderID = folderID
        self.folderName = folderName
        self.showPreviews = showPreviews
        self.playSound = playSound
    }
}

/// Handles opaque incoming push wakes, RFC 8620 §7.1 `StateChange` notifications,
/// and RFC 8620 §7.2.2 JMAP verification challenges from a user-hosted HTTPS relay
/// or JMAP WebPush delivery bridge (#11).
///
/// Incoming wakes carry only device-local opaque account tokens (`acct-<uuid>`),
/// never email addresses, mail bodies, or credentials. This coordinator resolves
/// opaque tokens to local opted-in `BrevAccount.ID`s, snapshots pre-refresh Inbox
/// message IDs, runs a bounded refresh for each matched backend, and invokes the
/// scene-less arrival notification pipeline strictly for genuinely newly arrived
/// unread messages so already-known unread messages are never re-notified.
@MainActor
public final class PushWakeCoordinator {
    /// Supplies the currently connected backends when a wake arrives.
    public var backendsProvider: @MainActor () -> [any MailBackend]

    /// Optional cold-launch restoration hook invoked when no backends are loaded yet.
    public var ensureAccountsRestored: (@MainActor () async -> Void)?

    /// Optional handler invoked when an RFC 8620 §7.2.2 JMAP `PushVerification` challenge arrives.
    public var onJMAPVerificationChallenge: (@MainActor (_ subscriptionID: String, _ verificationCode: String) async -> Void)?

    /// Fallback arrival window (15 minutes) used only when the local Inbox header cache
    /// was empty before refresh so ancient unread messages outside initial cache windows
    /// never trigger bogus closed-app alerts.
    private static let emptyCacheArrivalWindow: TimeInterval = 15 * 60

    private let settingsProvider: () -> PushRelaySettings
    private let notificationSettingsProvider: () -> NotificationSettings
    private let refreshBackends: @Sendable ([any MailBackend]) async -> String?
    private let customNotifyArrivedMail: (@MainActor (any MailBackend, PushWakePayload) async -> Void)?
    private let deliverNotification: @MainActor (PushWakeArrivedMessage) async -> Void
    private let now: @Sendable () -> Date

    /// Creates a wake coordinator with injectable settings, backend, refresh, clock, and notification seams.
    ///
    /// - Parameters:
    ///   - settingsProvider: Reads the current device-local `PushRelaySettings`.
    ///   - notificationSettingsProvider: Reads the current device-local `NotificationSettings`.
    ///   - backendsProvider: Returns currently connected mail backends.
    ///   - ensureAccountsRestored: Restores accounts on a cold background wake when needed.
    ///   - refreshBackends: Performs a bounded refresh for the matched backend.
    ///   - notifyArrivedMail: Optional override replacing the default scene-less arrival diff pipeline.
    ///   - deliverNotification: Injectable delivery sink used by the real arrival-diff pipeline.
    ///   - now: Clock used for empty-cache wake arrival window filtering.
    public init(
        settingsProvider: @escaping () -> PushRelaySettings = { PushRelaySettings.load() },
        notificationSettingsProvider: @escaping () -> NotificationSettings = { NotificationSettings.load() },
        backendsProvider: @escaping @MainActor () -> [any MailBackend] = { [] },
        ensureAccountsRestored: (@MainActor () async -> Void)? = nil,
        refreshBackends: (@Sendable ([any MailBackend]) async -> String?)? = nil,
        notifyArrivedMail: (@MainActor (any MailBackend, PushWakePayload) async -> Void)? = nil,
        deliverNotification: (@MainActor (PushWakeArrivedMessage) async -> Void)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.settingsProvider = settingsProvider
        self.notificationSettingsProvider = notificationSettingsProvider
        self.backendsProvider = backendsProvider
        self.ensureAccountsRestored = ensureAccountsRestored
        self.refreshBackends = refreshBackends ?? { backends in
            await MailFetchScheduler.performBackgroundRefresh(backends: backends)
        }
        customNotifyArrivedMail = notifyArrivedMail
        self.deliverNotification = deliverNotification ?? { arrived in
            let notificationCenter = BrevLocalNotificationCenter()
            await notificationCenter.postNewMailNotification(
                from: arrived.from,
                subject: arrived.subject,
                snippet: arrived.snippet,
                receivedAt: arrived.receivedAt,
                messageID: arrived.messageID,
                accountID: arrived.accountID,
                folderID: arrived.folderID,
                folderName: arrived.folderName,
                showPreviews: arrived.showPreviews,
                playSound: arrived.playSound
            )
        }
        self.now = now
    }

    /// Processes a decoded opaque wake payload, RFC 8620 `StateChange`, or JMAP verification challenge.
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

        let candidateTokens = payload.targetAccountTokens
        guard !candidateTokens.isEmpty else {
            return .ignoredInvalidPayload
        }

        var resolvedAccountIDs: [String] = []
        var seenAccountIDs: Set<String> = []
        for token in candidateTokens {
            if let resolved = settings.resolveAccountID(forOpaqueToken: token),
               seenAccountIDs.insert(resolved).inserted {
                resolvedAccountIDs.append(resolved)
            }
        }
        guard !resolvedAccountIDs.isEmpty else {
            return .ignoredAccountNotOptedIn(accountID: candidateTokens[0])
        }

        var backends = backendsProvider()
        if backends.isEmpty, let ensureAccountsRestored {
            await ensureAccountsRestored()
            backends = backendsProvider()
        }

        let matchedBackends = resolvedAccountIDs.compactMap { accountID in
            backends.first(where: { $0.account.id == accountID })
        }
        guard !matchedBackends.isEmpty else {
            return .ignoredAccountNotConnected(accountID: resolvedAccountIDs[0])
        }

        var syncedAccountIDs: [String] = []
        var deliveredNewDataAccountIDs: [String] = []
        var failures: [(accountID: String, message: String)] = []
        let wakeStartedAt = now()

        for targetBackend in matchedBackends {
            let baseline: CachedInboxBaseline? = if customNotifyArrivedMail == nil {
                await Self.snapshotCachedInboxBaseline(for: targetBackend)
            } else {
                nil
            }

            // Never call `targetBackend.subscribeToChanges()` here: on IMAP backends that
            // starts a new IDLE watcher and displaces the shared IDLE session.
            let failure = await refreshBackends([targetBackend])

            if let failure {
                failures.append((accountID: targetBackend.account.id, message: failure))
                continue
            }

            syncedAccountIDs.append(targetBackend.account.id)
            if let customNotifyArrivedMail {
                await customNotifyArrivedMail(targetBackend, payload)
                deliveredNewDataAccountIDs.append(targetBackend.account.id)
            } else {
                let didObserveNewData = await reconcilePostRefreshAndNotifyIfNeeded(
                    for: targetBackend,
                    payload: payload,
                    baseline: baseline,
                    wakeStartedAt: wakeStartedAt
                )
                if didObserveNewData {
                    deliveredNewDataAccountIDs.append(targetBackend.account.id)
                }
            }
        }

        // Report `.newData` when at least one account synced new data/mailbox changes,
        // `.noData` when at least one account synced cleanly with unchanged state,
        // and `.failed` only when ALL attempted accounts failed.
        if let firstWithNewData = deliveredNewDataAccountIDs.first {
            return .synced(accountID: firstWithNewData)
        }
        if let firstSynced = syncedAccountIDs.first {
            return .syncedNoNewData(accountID: firstSynced)
        }
        if let firstFailure = failures.first {
            let summary = failures.count == 1
                ? firstFailure.message
                : failures.map(\.message).joined(separator: "; ")
            return .failed(accountID: firstFailure.accountID, message: summary)
        }

        return .ignoredInvalidPayload
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

    /// Extracts a numeric IMAP UID from `IMAPSMTPBackend`'s canonical `"\(folderID):\(uid)"` header ID.
    /// Returns `nil` for non-IMAP backends (such as Gmail opaque message IDs).
    static func extractIMAPUID(from messageID: String, folderID: String) -> UInt32? {
        let prefix = "\(folderID):"
        guard messageID.hasPrefix(prefix) else { return nil }
        return UInt32(messageID.dropFirst(prefix.count))
    }

    private struct CachedHeaderState: Equatable {
        let isRead: Bool
        let isFlagged: Bool
        let flagColor: FlagColor?
        let labels: [String]
        let date: Date
        let subject: String
    }

    private struct CachedInboxBaseline {
        let inboxFolderID: String
        let messageIDs: Set<String>
        let headerStates: [String: CachedHeaderState]
        let latestCachedDate: Date?
        let maxCachedIMAPUID: UInt32?
    }

    private static func headerState(for header: MessageHeader) -> CachedHeaderState {
        CachedHeaderState(
            isRead: header.isRead,
            isFlagged: header.isFlagged,
            flagColor: header.flagColor,
            labels: header.labels,
            date: header.date,
            subject: header.subject
        )
    }

    /// Reads the pre-refresh Inbox state baseline strictly from the backend's
    /// local header cache (`cachedMessageHeaders`) without hitting the live server.
    ///
    /// Reading from the live server before refresh would already include the newly
    /// delivered message that triggered the push wake and suppress the arrival diff.
    private static func snapshotCachedInboxBaseline(for backend: any MailBackend) async -> CachedInboxBaseline? {
        guard backend.extendedCapabilities.contains(.cachedMessageHeaders) else {
            return nil
        }
        guard let folders = try? await backend.folders(),
              let inbox = folders.first(where: { $0.role == .inbox })
        else {
            return nil
        }
        let mailboxID = await (try? backend.currentMailbox().id) ?? backend.account.id
        let sourceID = MailSourceID(accountID: backend.account.id, mailboxID: mailboxID)
        guard let cachedHeaders = try? await backend.cachedMessageHeaders(in: inbox, sourceID: sourceID) else {
            return nil
        }
        var states: [String: CachedHeaderState] = [:]
        states.reserveCapacity(cachedHeaders.count)
        for header in cachedHeaders {
            states[header.id] = headerState(for: header)
        }
        let maxUID = cachedHeaders.compactMap { extractIMAPUID(from: $0.id, folderID: inbox.id) }.max()
        return CachedInboxBaseline(
            inboxFolderID: inbox.id,
            messageIDs: Set(cachedHeaders.map(\.id)),
            headerStates: states,
            latestCachedDate: cachedHeaders.map(\.date).max(),
            maxCachedIMAPUID: maxUID
        )
    }

    /// Determines whether a post-refresh message absent from `baseline.messageIDs` is a
    /// genuine newly delivered arrival rather than an older uncached backfill message.
    private static func isGenuineNewArrival(
        _ header: MessageHeader,
        inboxFolderID: String,
        baseline: CachedInboxBaseline,
        wakeStartedAt: Date
    ) -> Bool {
        guard !baseline.messageIDs.contains(header.id) else { return false }
        if baseline.messageIDs.isEmpty {
            let emptyCacheCutoff = wakeStartedAt.addingTimeInterval(-Self.emptyCacheArrivalWindow)
            return header.date >= emptyCacheCutoff
        }
        if let latestDate = baseline.latestCachedDate, header.date > latestDate {
            return true
        }
        if let maxUID = baseline.maxCachedIMAPUID,
           let candidateUID = extractIMAPUID(from: header.id, folderID: inboxFolderID),
           candidateUID > maxUID {
            return true
        }
        return false
    }

    /// Reconciles post-refresh Inbox state against the pre-refresh local-cache baseline:
    /// - Detects any mailbox state mutation (new arrival, read/flag/label change, or removal)
    ///   for both `.newMail` and `.mailboxChanged` wakes so iOS receives accurate `.newData` vs `.noData`.
    /// - Posts scene-less local alerts strictly on `.newMail` wakes for genuinely newly arrived
    ///   unread Inbox messages, avoiding re-alerts and older uncached Gmail backfill spam.
    private func reconcilePostRefreshAndNotifyIfNeeded(
        for backend: any MailBackend,
        payload: PushWakePayload,
        baseline: CachedInboxBaseline?,
        wakeStartedAt: Date
    ) async -> Bool {
        guard let baseline,
              let folders = try? await backend.folders(),
              let inbox = folders.first(where: { $0.role == .inbox }),
              let page = try? await backend.enumerateMessages(in: inbox, pageToken: nil)
        else {
            return false
        }

        let postHeaders = page.headers
        var postStates: [String: CachedHeaderState] = [:]
        postStates.reserveCapacity(postHeaders.count)
        for header in postHeaders {
            postStates[header.id] = Self.headerState(for: header)
        }

        let hasGenuineAddition = postHeaders.contains { header in
            Self.isGenuineNewArrival(
                header,
                inboxFolderID: inbox.id,
                baseline: baseline,
                wakeStartedAt: wakeStartedAt
            )
        }
        let hasFlagOrMetadataMutation = postHeaders.contains { header in
            guard let prior = baseline.headerStates[header.id] else { return false }
            return prior != Self.headerState(for: header)
        }
        let oldestPostDate = postHeaders.map(\.date).min()
        let hasRemovalInWindow = baseline.headerStates.contains { id, prior in
            guard postStates[id] == nil else { return false }
            guard let oldestPostDate else { return true }
            return prior.date >= oldestPostDate
        }
        let didObserveNewData = hasGenuineAddition || hasFlagOrMetadataMutation || hasRemovalInWindow

        if payload.eventKind == .newMail {
            let newlyArrivedUnread = postHeaders.filter { header in
                !header.isRead && Self.isGenuineNewArrival(
                    header,
                    inboxFolderID: inbox.id,
                    baseline: baseline,
                    wakeStartedAt: wakeStartedAt
                )
            }
            if !newlyArrivedUnread.isEmpty {
                let notificationSettings = notificationSettingsProvider()
                let decision = NewMailNotificationPolicy.decision(
                    settings: notificationSettings,
                    accountID: backend.account.id
                )
                if decision.shouldDeliver {
                    for header in newlyArrivedUnread.prefix(5) {
                        let arrived = PushWakeArrivedMessage(
                            messageID: header.id,
                            from: header.from,
                            subject: header.subject,
                            snippet: header.snippet,
                            receivedAt: header.date,
                            accountID: backend.account.id,
                            folderID: inbox.id,
                            folderName: inbox.name,
                            showPreviews: decision.showPreviews,
                            playSound: decision.playSound
                        )
                        await deliverNotification(arrived)
                    }
                }
            }
        }

        return didObserveNewData
    }
}
