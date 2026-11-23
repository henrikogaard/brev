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

/// Lock-screen-safe local notification policy for iOS sign-in codes and links
/// (#239, ADR-0088 iOS amendment).
///
/// Raw codes and magic-link URLs are strictly excluded from every notification
/// field (`title`, `subtitle`, `body`, `threadIdentifier`, and `userInfo`).
public enum SignInCodeNotificationPolicy {
    /// Stable prefix for all sign-in notification request identifiers.
    public static let identifierPrefix = "brev.signIn."

    /// Category for one-time code notifications (biometric-gated background copy).
    public static let codeCategoryIdentifier = "brev.signIn.code"

    /// Category for sign-in link notifications (biometric-gated foreground host confirmation).
    public static let linkCategoryIdentifier = "brev.signIn.link"

    /// Biometric-gated background action that copies the code to a local-only expiring pasteboard.
    public static let copyCodeActionIdentifier = "brev.signIn.copyCode"

    /// Biometric-gated foreground action that opens Brev to confirm the real destination host.
    public static let openLinkActionIdentifier = "brev.signIn.openLink"

    /// Maximum freshness age (10 minutes) matching ADR-0088 Decision 3 and the iOS amendment.
    public static let freshnessWindow: TimeInterval = 600

    /// Lock-screen-safe notification payload carrying only generic copy and an opaque mail route.
    public struct Payload: Equatable, Sendable {
        /// Whether this notification announces a code or a sign-in link.
        public enum Kind: String, Equatable, Sendable {
            case code
            case link
        }

        public let title: String
        public let body: String
        public let categoryIdentifier: String
        public let threadIdentifier: String
        public let userInfo: [String: String]
        public let kind: Kind

        public init(
            title: String,
            body: String,
            categoryIdentifier: String,
            threadIdentifier: String,
            userInfo: [String: String],
            kind: Kind
        ) {
            self.title = title
            self.body = body
            self.categoryIdentifier = categoryIdentifier
            self.threadIdentifier = threadIdentifier
            self.userInfo = userInfo
            self.kind = kind
        }
    }

    /// Stable per-message notification identifier used for delivery replacement and cleanup.
    public static func notificationIdentifier(accountID: String, messageID: String) -> String {
        identifierPrefix + encodedPart(accountID) + "." + encodedPart(messageID)
    }

    /// Prefix shared by every sign-in notification belonging to `accountID`.
    public static func accountIdentifierPrefix(accountID: String) -> String {
        identifierPrefix + encodedPart(accountID) + "."
    }

    /// Biometric-gated background `Copy code` action (no `.foreground`).
    public static func makeCopyCodeAction() -> UNNotificationAction {
        UNNotificationAction(
            identifier: copyCodeActionIdentifier,
            title: String(localized: "Copy code", bundle: .module),
            options: [.authenticationRequired]
        )
    }

    /// Biometric-gated foreground `Open link` action (shows real host before browser handoff).
    public static func makeOpenLinkAction() -> UNNotificationAction {
        UNNotificationAction(
            identifier: openLinkActionIdentifier,
            title: String(localized: "Open link", bundle: .module),
            options: [.authenticationRequired, .foreground]
        )
    }

    /// Notification category for one-time sign-in codes.
    public static func makeCodeCategory() -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: codeCategoryIdentifier,
            actions: [makeCopyCodeAction()],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: String(localized: "Sign-in code", bundle: .module),
            options: [.customDismissAction]
        )
    }

    /// Notification category for sign-in links.
    public static func makeLinkCategory() -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: linkCategoryIdentifier,
            actions: [makeOpenLinkAction()],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: String(localized: "Sign-in link", bundle: .module),
            options: [.customDismissAction]
        )
    }

    /// Builds a lock-screen-safe notification payload for `presentation`.
    /// Never writes the extracted code or magic-link URL into any field.
    public static func contentPayload(
        for presentation: SignInCodePresentation
    ) -> Payload {
        let trimmedSender = presentation.sender.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedSender.isEmpty ? "Brev" : trimmedSender
        let kind: Payload.Kind
        let body: String
        let categoryIdentifier: String
        switch presentation.content {
        case .code:
            kind = .code
            body = String(localized: "Sign-in code arrived", bundle: .module)
            categoryIdentifier = codeCategoryIdentifier
        case .link:
            kind = .link
            body = String(localized: "Sign-in link arrived", bundle: .module)
            categoryIdentifier = linkCategoryIdentifier
        }

        var userInfo: [String: String] = [
            "accountID": presentation.accountID,
            "messageID": presentation.messageID,
            "signInKind": kind.rawValue
        ]
        if let folderID = presentation.folderID {
            userInfo["folderID"] = folderID
        }

        return Payload(
            title: title,
            body: body,
            categoryIdentifier: categoryIdentifier,
            threadIdentifier: "brev.signIn.\(presentation.accountID)",
            userInfo: userInfo,
            kind: kind
        )
    }

    private static func encodedPart(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Scheduler seam for lock-screen-safe sign-in notifications (ADR-0088 iOS amendment).
@MainActor
public protocol SignInCodeNotificationScheduling: AnyObject {
    /// Posts a time-sensitive lock-screen-safe sign-in notification.
    func postSignInNotification(
        identifier: String,
        payload: SignInCodeNotificationPolicy.Payload
    ) async

    /// Removes delivered and pending sign-in notifications by identifier.
    func removeSignInNotifications(withIdentifiers identifiers: [String])

    /// Removes all delivered and pending sign-in notifications for `accountID`.
    func removeAllSignInNotifications(forAccountID accountID: String) async

    /// Removes delivered sign-in notifications posted on or before `cutoff`
    /// so stale notifications from a previous process are cleaned up on relaunch.
    func removeExpiredSignInNotifications(olderThan cutoff: Date) async
}

/// Foreground host-confirmation request shown before opening a sign-in link on iOS
/// (ADR-0088 Decision 6 & iOS amendment).
///
/// Redacted from default logging/mirrors so magic-link destinations stay memory-only.
public struct SignInCodeLinkConfirmation: Identifiable, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var id: String { "\(accountID):\(messageID)" }
    public let accountID: String
    public let messageID: String
    public let sender: String
    public let destination: String
    public let host: String

    public init(
        accountID: String,
        messageID: String,
        sender: String,
        destination: String,
        host: String
    ) {
        self.accountID = accountID
        self.messageID = messageID
        self.sender = sender
        self.destination = destination
        self.host = host
    }

    /// Validated HTTPS URL ready for browser handoff once the user confirms `host`.
    public var destinationURL: URL? {
        guard let url = URL(string: destination),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false
        else { return nil }
        return url
    }

    /// Localized title for the foreground link confirmation alert.
    public var alertTitle: String {
        String(localized: "Open sign-in link?", bundle: .module)
    }

    /// Localized message showing the real destination host before opening the browser.
    public var alertMessage: String {
        let trimmedSender = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSender.isEmpty {
            return String(
                format: String(localized: "This sign-in link opens %@ in your browser.", bundle: .module),
                host
            )
        }
        return String(
            format: String(localized: "Sign-in link from %@ opens %@ in your browser.", bundle: .module),
            trimmedSender,
            host
        )
    }

    /// Localized confirm button label.
    public var openButtonTitle: String {
        String(localized: "Open link", bundle: .module)
    }

    /// Localized cancel button label.
    public var cancelButtonTitle: String {
        String(localized: "Cancel", bundle: .module)
    }

    public var description: String { "SignInCodeLinkConfirmation(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: EmptyCollection<Mirror.Child>()) }
}

/// Memory-only sign-in notification presenter and action coordinator for iOS
/// (#239, ADR-0088 iOS amendment).
///
/// Extracted codes and links live only in memory; Notification Center receives only
/// generic lock-screen-safe copy and an opaque mail route.
@MainActor
@Observable
public final class SignInCodeNotificationPresenter: SignInCodePresenting,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private struct EntryKey: Hashable {
        let accountID: String
        let messageID: String
    }

    private struct StoredEntry {
        let presentation: SignInCodePresentation
        let recordedAt: Date
        let identifier: String
    }

    /// Async callback used when a biometric-gated notification action wakes the app
    /// without an in-memory entry; must re-verify trust, consent, and freshness.
    public typealias BackgroundReextractor = @MainActor (NotificationMailRoute) async -> SignInCodePresentation?

    /// Foreground link confirmation waiting for the user to verify the real host.
    public var pendingLinkConfirmation: SignInCodeLinkConfirmation?

    private var entries: [EntryKey: StoredEntry] = [:]
    private let scheduler: any SignInCodeNotificationScheduling
    private let pasteboard: any SignInCodePasteboardWriting
    private let settings: () -> SignInCodeSettings
    private let now: () -> Date
    /// Optional re-extractor for cold background notification wakes.
    public var backgroundReextractor: BackgroundReextractor?

    var storedEntryCount: Int { entries.count }

    /// - Parameters:
    ///   - scheduler: Local notification center bridge (defaults to `BrevLocalNotificationCenter`).
    ///   - pasteboard: Concealed/expiring pasteboard writer (defaults to `SystemSignInCodePasteboard`).
    ///   - settings: Reads current device-local consent before performing any action.
    ///   - now: Clock provider for deterministic freshness tests.
    public init(
        scheduler: (any SignInCodeNotificationScheduling)? = nil,
        pasteboard: any SignInCodePasteboardWriting = SystemSignInCodePasteboard(),
        settings: @escaping () -> SignInCodeSettings = { SignInCodeSettings.load(from: .standard) },
        now: @escaping () -> Date = Date.init
    ) {
        self.scheduler = scheduler ?? BrevLocalNotificationCenter()
        self.pasteboard = pasteboard
        self.settings = settings
        self.now = now
    }

    /// Stores `presentation` in memory only and posts a lock-screen-safe local notification.
    /// A newer sign-in message from the same account and sender replaces and removes the older one.
    public func present(_ presentation: SignInCodePresentation) {
        let key = EntryKey(accountID: presentation.accountID, messageID: presentation.messageID)
        let identifier = SignInCodeNotificationPolicy.notificationIdentifier(
            accountID: presentation.accountID,
            messageID: presentation.messageID
        )

        var replacedIdentifiers: [String] = []
        let normalizedSender = presentation.sender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !normalizedSender.isEmpty {
            let duplicateKeys = entries.compactMap { existingKey, entry -> EntryKey? in
                guard existingKey != key,
                      existingKey.accountID == presentation.accountID,
                      entry.presentation.sender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedSender
                else { return nil }
                return existingKey
            }
            for duplicateKey in duplicateKeys {
                if let removed = entries.removeValue(forKey: duplicateKey) {
                    replacedIdentifiers.append(removed.identifier)
                }
            }
        }
        if !replacedIdentifiers.isEmpty {
            scheduler.removeSignInNotifications(withIdentifiers: replacedIdentifiers)
        }

        let anchorDate = presentation.receivedAt ?? now()
        entries[key] = StoredEntry(
            presentation: presentation,
            recordedAt: anchorDate,
            identifier: identifier
        )
        let payload = SignInCodeNotificationPolicy.contentPayload(for: presentation)
        Task { [scheduler] in
            await scheduler.postSignInNotification(identifier: identifier, payload: payload)
        }
    }

    /// Drops all in-memory candidates for `accountID`, clears any pending confirmation
    /// for that account, and removes its delivered/pending sign-in notifications.
    public func dismiss(accountID: String) {
        var identifiersToRemove: [String] = []
        for (key, entry) in entries where key.accountID == accountID {
            identifiersToRemove.append(entry.identifier)
        }
        entries = entries.filter { $0.key.accountID != accountID }
        if pendingLinkConfirmation?.accountID == accountID {
            pendingLinkConfirmation = nil
        }
        if !identifiersToRemove.isEmpty {
            scheduler.removeSignInNotifications(withIdentifiers: identifiersToRemove)
        }
        Task { [scheduler] in
            await scheduler.removeAllSignInNotifications(forAccountID: accountID)
        }
    }

    /// Removes expired (> 10 minutes) in-memory candidates and their delivered notifications,
    /// and reconciles delivered sign-in notifications left over from a previous process.
    public func pruneExpired(at referenceDate: Date? = nil) {
        let current = referenceDate ?? now()
        var expiredKeys: [EntryKey] = []
        var expiredIdentifiers: [String] = []
        for (key, entry) in entries
            where current.timeIntervalSince(entry.recordedAt) >= SignInCodeNotificationPolicy.freshnessWindow {
            expiredKeys.append(key)
            expiredIdentifiers.append(entry.identifier)
        }
        for key in expiredKeys {
            entries.removeValue(forKey: key)
        }
        if !expiredIdentifiers.isEmpty {
            scheduler.removeSignInNotifications(withIdentifiers: expiredIdentifiers)
        }
        let cutoff = current.addingTimeInterval(-SignInCodeNotificationPolicy.freshnessWindow)
        Task { [scheduler] in
            await scheduler.removeExpiredSignInNotifications(olderThan: cutoff)
        }
    }

    /// Handles the biometric-gated `Copy code` notification action without foregrounding.
    /// Rechecks per-account consent and the 10-minute freshness window before writing
    /// to the concealed, 60-second-expiring local pasteboard. Always removes the delivered
    /// notification immediately.
    @discardableResult
    public func handleCopyCodeAction(route: NotificationMailRoute) async -> Bool {
        let key = EntryKey(accountID: route.accountID, messageID: route.messageID)
        let identifier = SignInCodeNotificationPolicy.notificationIdentifier(
            accountID: route.accountID,
            messageID: route.messageID
        )
        defer {
            entries.removeValue(forKey: key)
            scheduler.removeSignInNotifications(withIdentifiers: [identifier])
        }

        guard settings().accountOverride(for: route.accountID).codesEnabled else {
            return false
        }

        let current = now()
        pruneExpired(at: current)

        let presentation: SignInCodePresentation?
        if let entry = entries[key],
           current.timeIntervalSince(entry.recordedAt) < SignInCodeNotificationPolicy.freshnessWindow {
            presentation = entry.presentation
        } else if let reextractor = backgroundReextractor {
            presentation = await reextractor(route)
        } else {
            presentation = nil
        }

        // Recheck consent after any async re-extraction.
        guard settings().accountOverride(for: route.accountID).codesEnabled,
              let presentation,
              case .code(let code) = presentation.content
        else { return false }

        _ = pasteboard.writeConcealed(code)
        return true
    }

    /// Handles the biometric-gated foreground `Open link` notification action.
    /// Never opens a browser directly; instead populates `pendingLinkConfirmation`
    /// so Brev displays the real destination host first (ADR-0088 Decision 6).
    @discardableResult
    public func handleOpenLinkAction(route: NotificationMailRoute) async -> SignInCodeLinkConfirmation? {
        let key = EntryKey(accountID: route.accountID, messageID: route.messageID)
        let identifier = SignInCodeNotificationPolicy.notificationIdentifier(
            accountID: route.accountID,
            messageID: route.messageID
        )
        defer {
            entries.removeValue(forKey: key)
            scheduler.removeSignInNotifications(withIdentifiers: [identifier])
        }

        guard settings().accountOverride(for: route.accountID).linksEnabled else {
            return nil
        }

        let current = now()
        pruneExpired(at: current)

        let presentation: SignInCodePresentation?
        if let entry = entries[key],
           current.timeIntervalSince(entry.recordedAt) < SignInCodeNotificationPolicy.freshnessWindow {
            presentation = entry.presentation
        } else if let reextractor = backgroundReextractor {
            presentation = await reextractor(route)
        } else {
            presentation = nil
        }

        // Recheck consent after any async re-extraction.
        guard settings().accountOverride(for: route.accountID).linksEnabled,
              let presentation,
              case .link(let destination, let host) = presentation.content
        else { return nil }

        let confirmation = SignInCodeLinkConfirmation(
            accountID: presentation.accountID,
            messageID: presentation.messageID,
            sender: presentation.sender,
            destination: destination,
            host: host
        )
        guard confirmation.destinationURL != nil else { return nil }
        pendingLinkConfirmation = confirmation
        return confirmation
    }

    /// Clears the pending foreground link confirmation after the user opens or cancels it.
    public func clearPendingLinkConfirmation() {
        pendingLinkConfirmation = nil
    }

    public nonisolated var description: String { "SignInCodeNotificationPresenter(redacted)" }
    public nonisolated var debugDescription: String { description }
    public nonisolated var customMirror: Mirror { Mirror(self, children: EmptyCollection<Mirror.Child>()) }
}
