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

import Foundation

/// One locally stored correspondence observation for the recent-recipient list.
public struct RecentRecipientObservation: Sendable, Hashable {
    /// The owning mail account identifier.
    public let accountID: String
    /// The best local display name known for the address.
    public let displayName: String?
    /// The recipient email address.
    public let email: String
    /// When this correspondence was last seen.
    public let date: Date

    /// Creates a local correspondence observation.
    public init(accountID: String, displayName: String?, email: String, date: Date) {
        self.accountID = accountID
        self.displayName = displayName
        self.email = email
        self.date = date
    }
}

/// A local recipient learned from already-cached correspondence or successful sends.
public struct RecentRecipient: Identifiable, Codable, Hashable, Sendable {
    /// The mail account whose local correspondence produced this record.
    public let accountID: String
    /// The best local display name known for this address.
    public let displayName: String?
    /// The normalized recipient email address.
    public let email: String
    /// The newest message or successful send associated with this recipient.
    public let lastCorrespondenceAt: Date

    /// Stable per-account identity for SwiftUI lists and persistence updates.
    public var id: String { "\(accountID)|\(email.lowercased())" }

    /// Creates a locally persisted recipient record.
    public init(accountID: String, displayName: String?, email: String, lastCorrespondenceAt: Date) {
        self.accountID = accountID
        self.displayName = displayName
        self.email = email
        self.lastCorrespondenceAt = lastCorrespondenceAt
    }
}

/// Preference controlling whether composer suggestions read local Apple Contacts.
public struct RecipientSuggestionSettings: Equatable, Sendable {
    /// Stable UserDefaults keys shared by settings and compose surfaces.
    public enum Key {
        /// Whether Apple Contacts may appear in recipient suggestions.
        public static let useAppleContacts = "compose.recipientSuggestions.useAppleContacts"
    }

    /// Whether the composer reads the user's local Apple Contacts database.
    public var useAppleContacts: Bool

    /// The privacy-preserving default: Contacts stay off until the user opts in
    /// from Settings, so autocomplete never triggers a system permission prompt.
    public static let defaults = RecipientSuggestionSettings(useAppleContacts: false)

    /// Creates recipient suggestion settings.
    public init(useAppleContacts: Bool) {
        self.useAppleContacts = useAppleContacts
    }

    /// Loads the setting from local preferences.
    public static func load(from defaults: UserDefaults = .standard) -> RecipientSuggestionSettings {
        guard defaults.object(forKey: Key.useAppleContacts) != nil else { return .defaults }
        return RecipientSuggestionSettings(useAppleContacts: defaults.bool(forKey: Key.useAppleContacts))
    }

    /// Persists the setting in local preferences.
    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(useAppleContacts, forKey: Key.useAppleContacts)
    }
}

/// Stores a private, removable list of recipients learned from local mail data.
public struct RecentRecipientStore {
    /// Maximum records retained for any one account to keep local lookup bounded.
    public static let maximumRecipientsPerAccount = 500

    private enum Key {
        static let recipients = "compose.recentRecipients.v1"
        static let dismissedAtByRecipientID = "compose.recentRecipients.dismissedAtByRecipientID.v1"
        static let clearedAt = "compose.recentRecipients.clearedAt.v1"
    }

    private let defaults: UserDefaults

    /// Creates a store backed by local preferences.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Records local correspondence without creating or modifying Apple Contacts.
    public func record(_ observations: [RecentRecipientObservation]) {
        guard !observations.isEmpty else { return }

        var byID = Dictionary(
            uniqueKeysWithValues: storedRecipients().map { ($0.id, $0) }
        )
        let dismissedAtByRecipientID = storedDismissedAtByRecipientID()
        let clearedAt = defaults.object(forKey: Key.clearedAt) as? Date
        var didChange = false
        for observation in observations {
            let accountID = observation.accountID.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = normalizedEmail(observation.email)
            guard !accountID.isEmpty, isLikelyEmail(email) else { continue }

            let id = "\(accountID)|\(email)"
            if let clearedAt, observation.date <= clearedAt {
                continue
            }
            if let dismissedAt = dismissedAtByRecipientID[id], observation.date <= dismissedAt {
                continue
            }
            let displayName = normalizedDisplayName(observation.displayName)
            if let existing = byID[id] {
                let resolvedDisplayName: String?
                if existing.displayName == nil, let displayName {
                    resolvedDisplayName = displayName
                } else if observation.date >= existing.lastCorrespondenceAt, let displayName {
                    resolvedDisplayName = displayName
                } else {
                    resolvedDisplayName = existing.displayName
                }
                let next = RecentRecipient(
                    accountID: accountID,
                    displayName: resolvedDisplayName,
                    email: email,
                    lastCorrespondenceAt: max(existing.lastCorrespondenceAt, observation.date)
                )
                if next != existing {
                    byID[id] = next
                    didChange = true
                }
            } else {
                byID[id] = RecentRecipient(
                    accountID: accountID,
                    displayName: displayName,
                    email: email,
                    lastCorrespondenceAt: observation.date
                )
                didChange = true
            }
        }

        guard didChange else { return }

        let retained = Dictionary(grouping: byID.values, by: \.accountID)
            .values
            .flatMap { records in
                records
                    .sorted(by: newestFirst)
                    .prefix(Self.maximumRecipientsPerAccount)
            }
            .sorted(by: newestFirst)
        save(retained)
    }

    /// Returns recent recipients matching a local query for one account.
    public func recipients(matching query: String, accountID: String) -> [RecentRecipient] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        return storedRecipients()
            .filter { recipient in
                recipient.accountID == accountID
                    && (recipient.email.localizedCaseInsensitiveContains(needle)
                        || (recipient.displayName?.localizedCaseInsensitiveContains(needle) ?? false))
            }
            .sorted(by: newestFirst)
    }

    /// Returns each saved email once, newest correspondence first, for management UI.
    public func allRecipients() -> [RecentRecipient] {
        var seen = Set<String>()
        return storedRecipients()
            .sorted(by: newestFirst)
            .filter { seen.insert(normalizedEmail($0.email)).inserted }
    }

    /// Removes a local recipient from every account without touching Apple Contacts.
    public func remove(email: String) {
        let normalized = normalizedEmail(email)
        guard !normalized.isEmpty else { return }
        let existing = storedRecipients()
        let removed = existing.filter { normalizedEmail($0.email) == normalized }
        guard !removed.isEmpty else { return }

        var dismissedAtByRecipientID = storedDismissedAtByRecipientID()
        let dismissedAt = Date()
        for recipient in removed {
            dismissedAtByRecipientID[recipient.id] = dismissedAt
        }
        saveDismissedAtByRecipientID(dismissedAtByRecipientID)
        save(existing.filter { normalizedEmail($0.email) != normalized })
    }

    /// Clears all Brev-only recent-recipient records without touching Apple Contacts.
    public func removeAll() {
        defaults.removeObject(forKey: Key.recipients)
        defaults.removeObject(forKey: Key.dismissedAtByRecipientID)
        defaults.set(Date(), forKey: Key.clearedAt)
    }

    /// Removes all recent-recipient data scoped to an account being removed.
    public func removeAccount(_ accountID: String) {
        let normalizedAccountID = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAccountID.isEmpty else { return }

        save(storedRecipients().filter { $0.accountID != normalizedAccountID })
        let prefix = "\(normalizedAccountID)|"
        saveDismissedAtByRecipientID(
            storedDismissedAtByRecipientID().filter { !$0.key.hasPrefix(prefix) }
        )
    }

    private func storedRecipients() -> [RecentRecipient] {
        guard let data = defaults.data(forKey: Key.recipients),
              let records = try? JSONDecoder().decode([RecentRecipient].self, from: data) else {
            return []
        }
        return records
    }

    private func save(_ records: [RecentRecipient]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Key.recipients)
    }

    private func storedDismissedAtByRecipientID() -> [String: Date] {
        guard let data = defaults.data(forKey: Key.dismissedAtByRecipientID),
              let dismissals = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return [:]
        }
        return dismissals
    }

    private func saveDismissedAtByRecipientID(_ dismissals: [String: Date]) {
        guard !dismissals.isEmpty else {
            defaults.removeObject(forKey: Key.dismissedAtByRecipientID)
            return
        }
        guard let data = try? JSONEncoder().encode(dismissals) else { return }
        defaults.set(data, forKey: Key.dismissedAtByRecipientID)
    }

    private func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedDisplayName(_ displayName: String?) -> String? {
        guard let displayName else { return nil }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isLikelyEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        return parts[1].contains(".") && !email.contains(where: \.isWhitespace)
    }

    private func newestFirst(_ lhs: RecentRecipient, _ rhs: RecentRecipient) -> Bool {
        if lhs.lastCorrespondenceAt != rhs.lastCorrespondenceAt {
            return lhs.lastCorrespondenceAt > rhs.lastCorrespondenceAt
        }
        return lhs.email.localizedCaseInsensitiveCompare(rhs.email) == .orderedAscending
    }
}

/// Serializes deferred local recent-recipient writes from mail-list updates.
public actor RecentRecipientRecorder {
    /// Shared recorder for the app's standard local recipient store.
    public static let shared = RecentRecipientRecorder()

    private let store: RecentRecipientStore

    /// Creates a recorder for one local recipient store.
    public init(store: RecentRecipientStore = RecentRecipientStore()) {
        self.store = store
    }

    /// Merges correspondence observations without blocking the caller's UI work.
    public func record(_ observations: [RecentRecipientObservation]) {
        store.record(observations)
    }
}

/// Performs local recent-recipient reads away from the compose main actor.
///
/// UserDefaults JSON decoding is intentionally deferred until after the
/// compose autocomplete debounce and runs on this actor's executor, so typing
/// remains responsive while the visible editor state stays synchronous.
public actor RecentRecipientLookup {
    /// Shared lookup actor for the app's standard local recipient store.
    public static let shared = RecentRecipientLookup()

    private let store: RecentRecipientStore

    /// Creates a lookup actor for one local recipient store.
    public init(store: RecentRecipientStore = RecentRecipientStore()) {
        self.store = store
    }

    /// Decodes and filters local recipients without running on the caller's actor.
    public func recipients(matching query: String, accountID: String) -> [RecentRecipient] {
        store.recipients(matching: query, accountID: accountID)
    }
}
