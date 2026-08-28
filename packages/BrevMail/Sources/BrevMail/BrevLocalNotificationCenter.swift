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
import Observation
import UserNotifications

/// User-visible authorization state for the local notification center.
///
/// Mirrors the subset of `UNAuthorizationStatus` Brev actually surfaces to
/// the view layer. Provisional is treated as a separate value because
/// notifications can be delivered quietly without an explicit prompt and
/// the settings UI distinguishes that from a fully authorized user.
public enum BrevNotificationAuthStatus: String, Sendable, CaseIterable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    public var displayTitle: String {
        switch self {
        case .notDetermined: return "Not requested"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        case .provisional: return "Quiet delivery"
        case .ephemeral: return "App-clip only"
        }
    }

    public var displaySubtitle: String {
        switch self {
        case .notDetermined:
            return "Brev hasn't asked for permission yet."
        case .denied:
            return "Open System Settings to allow notifications from Brev."
        case .authorized:
            return "Alerts, sounds, and badges are enabled."
        case .provisional:
            return "Notifications deliver quietly to Notification Center."
        case .ephemeral:
            return "Allowed only while an app clip is active."
        }
    }
}

/// Local-notification surface used by the mail view to surface new-mail
/// events. Wraps `UNUserNotificationCenter` and registers the "newMail"
/// category with Mark-Read and Archive actions.
///
/// The class is `@Observable` so the settings view can render the live
/// authorization state without an extra `@State`/`@Binding` hop.
@Observable
@MainActor
public final class BrevLocalNotificationCenter {
    public nonisolated static let newMailCategoryIdentifier = "brev.newMail"
    public nonisolated static let newMailReplyCategoryIdentifier = "brev.newMail.replyEnabled"

    public static let markReadActionIdentifier = "brev.newMail.markRead"
    public static let archiveActionIdentifier = "brev.newMail.archive"
    public static let replyActionIdentifier = "brev.newMail.reply"

    private let providedCenter: UNUserNotificationCenter?
    private var center: UNUserNotificationCenter? {
        guard Self.canUseSystemNotificationCenterInCurrentProcess else {
            return providedCenter
        }
        return providedCenter ?? .current()
    }

    static var canUseSystemNotificationCenterInCurrentProcess: Bool {
        let path = Bundle.main.bundleURL.path
        // SPM `swift test` and Xcode's iOS test agent both lack a real app
        // bundle proxy — calling UNUserNotificationCenter.current() crashes.
        if path.contains("/usr/libexec/swift/pm") { return false }
        if path.contains("/Developer/Library/Xcode/Agents") { return false }
        if path.contains("xctest") { return false }
        return true
    }

    public private(set) var authorizationStatus: BrevNotificationAuthStatus = .notDetermined

    public init(center: UNUserNotificationCenter? = nil) {
        providedCenter = center
    }

    /// Register the "newMail" category and its actions. Safe to call
    /// repeatedly; the system replaces the existing registration.
    public func setupNotificationCategories() {
        guard let center else {
            return
        }

        let markRead = UNNotificationAction(
            identifier: Self.markReadActionIdentifier,
            title: "Mark Read",
            options: [.foreground]
        )
        let archive = UNNotificationAction(
            identifier: Self.archiveActionIdentifier,
            title: "Archive",
            options: [.destructive, .authenticationRequired]
        )
        let reply = Self.makeReplyAction()
        let category = UNNotificationCategory(
            identifier: Self.newMailCategoryIdentifier,
            actions: [markRead, archive],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "New mail",
            options: [.customDismissAction]
        )
        let replyCategory = UNNotificationCategory(
            identifier: Self.newMailReplyCategoryIdentifier,
            actions: [markRead, archive, reply],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "New mail",
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category, replyCategory])
    }

    /// Text-input Reply action used by the new-mail category.
    ///
    /// Authentication protects sending from the lock screen while still
    /// allowing biometric authentication to reveal the inline text field.
    /// Omitting the foreground option keeps the user in the banner.
    static func makeReplyAction() -> UNNotificationAction {
        UNTextInputNotificationAction(
            identifier: replyActionIdentifier,
            title: String(localized: "Reply", bundle: .module),
            options: [.authenticationRequired],
            textInputButtonTitle: String(localized: "Send", bundle: .module),
            textInputPlaceholder: String(localized: "Reply", bundle: .module)
        )
    }

    /// Refresh `authorizationStatus` from the system. Cheap to call; the
    /// runtime caches the value.
    public func currentAuthorizationStatus() async {
        guard let center else {
            return
        }

        let settings = await center.notificationSettings()
        authorizationStatus = Self.map(settings.authorizationStatus)
    }

    /// Ask the user for alert/sound/badge permission. The system's
    /// provisional answer (no prompt, quiet delivery) is folded into
    /// `.provisional` for the view layer.
    @discardableResult
    public func requestAuthorization() async -> BrevNotificationAuthStatus {
        guard let center else {
            return authorizationStatus
        }

        do {
            let options: UNAuthorizationOptions = [.alert, .badge, .sound, .providesAppNotificationSettings]
            _ = try await center.requestAuthorization(options: options)
        } catch {
            // Permission is user-owned; surface the current cached state
            // so the caller can branch on the resulting status.
        }
        await currentAuthorizationStatus()
        return authorizationStatus
    }

    /// Remove every already-delivered notification from the notification
    /// center. Used by the macOS app delegate on foreground so reopening
    /// the app doesn't leave stale toasts in the tray.
    public func clearAllDelivered() {
        guard let center else {
            return
        }

        center.removeAllDeliveredNotifications()
    }

    /// Schedule a local "new mail" notification for a single message.
    ///
    /// Honours `NotificationSettings.showPreviews`: when off, the
    /// notification body is replaced with a generic "New mail" string
    /// and the subject is hidden.
    public func postNewMailNotification(
        from correspondent: Correspondent,
        subject: String,
        snippet: String = "",
        receivedAt: Date = Date(),
        messageID: String,
        accountID: String,
        folderID: String? = nil,
        sourceID: MailSourceID? = nil,
        folderName: String?,
        showPreviews: Bool,
        playSound: Bool = true,
        allowsInlineReply: Bool = false
    ) async {
        guard let center else {
            return
        }

        // The cached authorization status is captured once at setup, but the
        // user can grant permission afterwards (via the settings toggle or
        // System Settings). If we still think permission is undetermined or
        // denied, re-check with the system before dropping the alert —
        // otherwise new-mail notifications silently never fire even though
        // the Test button (which talks to the system directly) works.
        if authorizationStatus != .authorized,
           authorizationStatus != .provisional,
           authorizationStatus != .ephemeral {
            await currentAuthorizationStatus()
        }

        guard authorizationStatus == .authorized
            || authorizationStatus == .provisional
            || authorizationStatus == .ephemeral
        else {
            return
        }

        let payload = NewMailNotificationPolicy.contentPayload(
            correspondent: correspondent,
            subject: subject,
            snippet: snippet,
            receivedAt: receivedAt,
            messageID: messageID,
            accountID: accountID,
            folderID: folderID,
            sourceID: sourceID,
            folderName: folderName,
            showPreviews: showPreviews,
            playSound: playSound,
            allowsInlineReply: allowsInlineReply
        )

        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.threadIdentifier = payload.threadIdentifier
        content.categoryIdentifier = payload.categoryIdentifier
        content.userInfo = payload.userInfo
        content.sound = payload.playSound ? .default : nil

        let request = UNNotificationRequest(
            identifier: "brev.newMail.\(accountID).\(messageID).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            // Drop on the floor — the next event will surface another
            // notification, and we don't want to spam logs for transient
            // scheduling errors.
        }
    }

    /// Surface a notification-reply failure after the original action sheet
    /// has gone away. Tapping it reopens the exact message; no sender, subject,
    /// reply text, or raw error is exposed.
    public func postReplyFailureNotification(
        route: NotificationMailRoute,
        draftWasSaved: Bool
    ) async {
        guard let center else { return }
        if authorizationStatus != .authorized,
           authorizationStatus != .provisional,
           authorizationStatus != .ephemeral {
            await currentAuthorizationStatus()
        }
        guard authorizationStatus == .authorized
            || authorizationStatus == .provisional
            || authorizationStatus == .ephemeral
        else { return }

        let payload = NotificationReplyFailurePolicy.payload(
            route: route,
            draftWasSaved: draftWasSaved
        )
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default
        content.threadIdentifier = payload.threadIdentifier
        content.userInfo = payload.userInfo

        let request = UNNotificationRequest(
            identifier: "brev.replyFailed.\(route.accountID).\(route.messageID).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    /// Stable identifier for the inbox-refresh reminder. Fixed (not per-call)
    /// so each scheduling *replaces* the prior pending request instead of
    /// stacking — `applicationDidResignActive` fires on ordinary focus loss, so
    /// a unique-per-call id would queue a fresh reminder every time the user
    /// switched away and back. Public for testability.
    public static let inboxRefreshReminderID = "brev.inboxRefresh"

    /// Stable prefix for local follow-up reminder requests.
    public nonisolated static let followUpReminderIdentifierPrefix = "brev.followUp."

    /// Returns the legacy, message-only identifier used before source scoping.
    public nonisolated static func legacyFollowUpReminderIdentifier(for messageID: String) -> String {
        followUpReminderIdentifierPrefix + messageID
    }

    /// Backward-compatible message-only identifier accessor.
    public nonisolated static func followUpReminderIdentifier(for messageID: String) -> String {
        legacyFollowUpReminderIdentifier(for: messageID)
    }

    /// Returns a source-aware notification request identifier for a message.
    public nonisolated static func followUpReminderIdentifier(
        for messageID: String,
        sourceID: MailSourceID?
    ) -> String {
        guard let sourceID else {
            return legacyFollowUpReminderIdentifier(for: messageID)
        }
        return followUpReminderIdentifierPrefix
            + "v2."
            + encodedIdentifierPart(sourceID.accountID)
            + "."
            + encodedIdentifierPart(sourceID.mailboxID)
            + "."
            + encodedIdentifierPart(messageID)
    }

    /// Returns the stable notification request identifier for a persisted reminder.
    public nonisolated static func followUpReminderIdentifier(
        for reminder: FollowUpReminder
    ) -> String {
        followUpReminderIdentifier(for: reminder.messageID, sourceID: reminder.sourceID)
    }

    /// Identifiers that should remain pending for the current active reminders.
    /// Source-aware records intentionally keep only their v2 identifier so a
    /// migrated legacy request cannot remain as a duplicate.
    public nonisolated static func activeFollowUpReminderIdentifiers(
        for settings: FollowUpSettings
    ) -> Set<String> {
        Set(settings.activeReminders.map { followUpReminderIdentifier(for: $0) })
    }

    /// Builds notification metadata understood by `NotificationRoutingPolicy`.
    /// Folder and account data are omitted when legacy records cannot provide it.
    public nonisolated static func followUpNotificationUserInfo(
        for reminder: FollowUpReminder
    ) -> [String: String] {
        var userInfo = [
            "messageID": reminder.messageID,
            "threadID": reminder.threadID
        ]
        if let accountID = reminder.accountID {
            userInfo["accountID"] = accountID
        }
        if let folderID = reminder.folderID {
            userInfo["folderID"] = folderID
        }
        if let sourceID = reminder.sourceID {
            userInfo["sourceAccountID"] = sourceID.accountID
            userInfo["sourceMailboxID"] = sourceID.mailboxID
        }
        return userInfo
    }

    private nonisolated static func encodedIdentifierPart(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Schedule or replace a local reminder for a message.
    public func scheduleFollowUpReminder(_ reminder: FollowUpReminder, subject: String) async {
        guard let center else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Follow-Up Reminder", bundle: .module)
        let genericBody = String(localized: "Follow up on this message.", bundle: .module)
        content.body = NotificationSettings.load().showPreviews && !subject.isEmpty
            ? subject
            : genericBody
        content.sound = .default
        content.threadIdentifier = "brev.followUp"
        content.userInfo = Self.followUpNotificationUserInfo(for: reminder)

        let request = UNNotificationRequest(
            identifier: Self.followUpReminderIdentifier(for: reminder),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, reminder.dueAt.timeIntervalSinceNow),
                repeats: false
            )
        )
        try? await center.add(request)
    }

    /// Cancel the pending reminder for a persisted reminder, including its legacy ID.
    public func cancelFollowUpReminder(_ reminder: FollowUpReminder) {
        guard let center else { return }
        center.removePendingNotificationRequests(withIdentifiers: [
            Self.followUpReminderIdentifier(for: reminder),
            Self.legacyFollowUpReminderIdentifier(for: reminder.messageID)
        ])
    }

    /// Cancel a pending reminder by source-aware identity.
    public func cancelFollowUpReminder(messageID: String, sourceID: MailSourceID?) {
        guard let center else { return }
        let scopedID = Self.followUpReminderIdentifier(for: messageID, sourceID: sourceID)
        // Do not remove another source's legacy message-only request here;
        // callers with a persisted legacy reminder use the overload above.
        center.removePendingNotificationRequests(withIdentifiers: [scopedID])
    }

    /// Remove pending follow-up requests that no longer have an active local reminder.
    public func cancelInactiveFollowUpReminders(settings: FollowUpSettings) async {
        guard let center else { return }
        let activeIDs = Self.activeFollowUpReminderIdentifiers(for: settings)
        let pending = await center.pendingNotificationRequests()
        let staleIDs = pending.map(\.identifier).filter {
            $0.hasPrefix(Self.followUpReminderIdentifierPrefix) && !activeIDs.contains($0)
        }
        guard !staleIDs.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: staleIDs)
    }

    /// Schedule a low-priority "inbox refresh" reminder so the system has
    /// a non-zero budget of pending notifications while the app is in
    /// the background. Gated by the caller on the `pushNotifications`
    /// backend capability.
    public func scheduleInboxRefreshReminder() async {
        guard let center else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Brev"
        content.body = "Checking for new mail…"
        content.sound = nil
        content.interruptionLevel = .passive
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: 600,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: Self.inboxRefreshReminderID,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    /// Cancel any pending inbox-refresh reminder. Called when the app returns to
    /// the foreground so a queued "Checking for new mail…" banner doesn't fire
    /// while the user is actively in the app.
    public func cancelInboxRefreshReminder() {
        guard let center else {
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: [Self.inboxRefreshReminderID])
    }

    private static func map(_ status: UNAuthorizationStatus) -> BrevNotificationAuthStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .notDetermined
        }
    }
}
