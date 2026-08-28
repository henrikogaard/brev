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

public extension Notification.Name {
    /// Posted after local follow-up reminders change so mail surfaces can refresh.
    static let brevFollowUpDidChange = Notification.Name("brev.followUpDidChange")
}

/// A local follow-up reminder attached to a specific message or thread.
///
/// Reminders are entirely local. Provider-synced follow-up state is
/// a v2 concern and must be capability-gated before shipping.
public struct FollowUpReminder: Codable, Equatable, Sendable, Identifiable {
    /// Stable identifier for this reminder.
    public let id: String
    /// The message this reminder is attached to.
    public let messageID: String
    /// The thread this reminder is attached to (may equal `messageID`).
    public let threadID: String
    /// Optional account/source scope; `nil` means the reminder applies globally.
    public let accountID: String?
    /// Optional mailbox scope. Missing values are legacy account/global records.
    public let mailboxID: String?
    /// Folder containing the message, used to route reminder taps back to mail.
    public let folderID: String?
    /// The date/time by which the user wants to follow up.
    public var dueAt: Date
    /// `true` once the user has completed or dismissed the reminder.
    public var isDismissed: Bool
    /// `true` when the user has explicitly marked the follow-up done.
    public var isCompleted: Bool
    /// Creation date — used for stable ordering when `dueAt` is the same.
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        messageID: String,
        threadID: String,
        accountID: String? = nil,
        mailboxID: String? = nil,
        folderID: String? = nil,
        dueAt: Date,
        isDismissed: Bool = false,
        isCompleted: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.messageID = messageID
        self.threadID = threadID
        self.accountID = accountID
        self.mailboxID = mailboxID
        self.folderID = folderID
        self.dueAt = dueAt
        self.isDismissed = isDismissed
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }

    /// Full source identity when this reminder has been written by the source-aware flow.
    public var sourceID: MailSourceID? {
        guard let accountID, let mailboxID else { return nil }
        return MailSourceID(accountID: accountID, mailboxID: mailboxID)
    }

    /// `true` when the reminder is active: not dismissed, not completed,
    /// and the due date has passed or is within the next 24 hours.
    public func isDue(at now: Date = Date()) -> Bool {
        !isDismissed && !isCompleted && dueAt <= now.addingTimeInterval(86400)
    }
}

/// Persisted store for all local follow-up reminders.
public struct FollowUpSettings: Codable, Equatable, Sendable {
    public enum Key {
        public static let reminders = "followUp.reminders"
    }

    public var reminders: [FollowUpReminder]

    public static let defaults = FollowUpSettings(reminders: [])

    public init(reminders: [FollowUpReminder]) {
        self.reminders = reminders
    }

    public static func load(from defaults: UserDefaults = .standard) -> FollowUpSettings {
        guard let data = defaults.data(forKey: Key.reminders),
              let settings = try? JSONDecoder().decode(FollowUpSettings.self, from: data)
        else {
            return .defaults
        }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Key.reminders)
    }

    /// All active (not dismissed, not completed) reminders, sorted by due date.
    public var activeReminders: [FollowUpReminder] {
        reminders
            .filter { !$0.isDismissed && !$0.isCompleted }
            .sorted { $0.dueAt < $1.dueAt }
    }

    /// Reminders due now or within the next 24 hours.
    public func dueReminders(at now: Date = Date()) -> [FollowUpReminder] {
        activeReminders.filter { $0.isDue(at: now) }
    }

    /// Returns the active reminder for the given message, if any.
    public func reminder(for messageID: String) -> FollowUpReminder? {
        reminders.first {
            $0.messageID == messageID
                && !$0.isDismissed
                && !$0.isCompleted
        }
    }

    /// Returns the source-aware active reminder, preferring an exact mailbox match.
    /// Legacy account/global records remain eligible as a migration fallback.
    public func reminder(for messageID: String, sourceID: MailSourceID?) -> FollowUpReminder? {
        var exactMatch: FollowUpReminder?
        var accountMatch: FollowUpReminder?
        var globalMatch: FollowUpReminder?

        for reminder in reminders where reminder.messageID == messageID
            && !reminder.isDismissed
            && !reminder.isCompleted {
            guard let sourceID else {
                globalMatch = Self.earlier(globalMatch, reminder)
                continue
            }
            if reminder.accountID == sourceID.accountID,
               reminder.mailboxID == sourceID.mailboxID {
                exactMatch = Self.earlier(exactMatch, reminder)
            } else if reminder.accountID == sourceID.accountID,
                      reminder.mailboxID == nil {
                accountMatch = Self.earlier(accountMatch, reminder)
            } else if reminder.accountID == nil, reminder.mailboxID == nil {
                globalMatch = Self.earlier(globalMatch, reminder)
            }
        }

        return exactMatch ?? accountMatch ?? globalMatch
    }

    private static func earlier(
        _ current: FollowUpReminder?,
        _ candidate: FollowUpReminder
    ) -> FollowUpReminder {
        guard let current else { return candidate }
        return candidate.dueAt < current.dueAt ? candidate : current
    }

    public mutating func add(_ reminder: FollowUpReminder) {
        // Dedup only within the same source scope. Legacy records are retained
        // unless they are themselves being replaced, so older persisted data
        // remains available as a migration fallback.
        reminders.removeAll {
            $0.messageID == reminder.messageID
                && !$0.isDismissed
                && !$0.isCompleted
                && Self.sameScope($0, reminder)
        }
        reminders.append(reminder)
    }

    private static func sameScope(_ lhs: FollowUpReminder, _ rhs: FollowUpReminder) -> Bool {
        guard lhs.messageID == rhs.messageID else { return false }
        if lhs.mailboxID != nil || rhs.mailboxID != nil {
            return lhs.accountID == rhs.accountID && lhs.mailboxID == rhs.mailboxID
        }
        return lhs.accountID == rhs.accountID
    }

    public mutating func dismiss(id: FollowUpReminder.ID) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[index].isDismissed = true
    }

    public mutating func complete(id: FollowUpReminder.ID) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[index].isCompleted = true
    }

    public mutating func remove(id: FollowUpReminder.ID) {
        reminders.removeAll { $0.id == id }
    }

    /// Removes dismissed and completed reminders older than `olderThan`.
    public mutating func prune(olderThan cutoff: Date = Date().addingTimeInterval(-30 * 86400)) {
        reminders.removeAll { ($0.isDismissed || $0.isCompleted) && $0.dueAt < cutoff }
    }
}
