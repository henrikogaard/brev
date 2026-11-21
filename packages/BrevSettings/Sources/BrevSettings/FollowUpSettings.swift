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
    /// Present only for reminders created by exact cached no-reply reconciliation.
    public var noReplyMetadata: NoReplyFollowUpMetadata?

    /// Creates a manual or automatic follow-up reminder.
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
        createdAt: Date = Date(),
        noReplyMetadata: NoReplyFollowUpMetadata? = nil
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
        self.noReplyMetadata = noReplyMetadata
    }

    /// Full source identity when this reminder has been written by the source-aware flow.
    public var sourceID: MailSourceID? {
        guard let accountID, let mailboxID else { return nil }
        return MailSourceID(accountID: accountID, mailboxID: mailboxID)
    }

    /// `true` only when this reminder was created by no-reply reconciliation.
    public var isAutomaticNoReply: Bool { noReplyMetadata != nil }

    /// `true` when the reminder is active: not dismissed, not completed,
    /// and the due date has passed or is within the next 24 hours.
    public func isDue(at now: Date = Date()) -> Bool {
        !isDismissed && !isCompleted && dueAt <= now.addingTimeInterval(86400)
    }
}

/// Exact source and RFC identity for an automatically reconciled no-reply reminder.
public struct NoReplyFollowUpMetadata: Codable, Equatable, Sendable {
    /// Exact mailbox source that owns the Sent copy.
    public let sourceID: MailSourceID
    /// Stable local draft identity that opted in.
    public let draftID: String
    /// Canonical outbound RFC Message-ID.
    public let expectedMessageID: String
    /// Delivery time from the matched Sent header.
    public let sentAt: Date

    /// Creates automatic reminder metadata for one exact source and message.
    public init(sourceID: MailSourceID, draftID: String, expectedMessageID: String, sentAt: Date) {
        self.sourceID = sourceID
        self.draftID = draftID
        self.expectedMessageID = expectedMessageID
        self.sentAt = sentAt
    }
}

/// Pending local intent registered only after a send or queue operation is accepted.
public struct PendingNoReplyFollowUpIntent: Codable, Equatable, Sendable, Identifiable {
    /// Stable deduplication key for this source and draft.
    public let id: String
    /// Exact mailbox source that owns the pending send.
    public let sourceID: MailSourceID
    /// Stable local draft identity that opted in.
    public let draftID: String
    /// Canonical outbound RFC Message-ID.
    public let expectedMessageID: String
    /// Fixed delay to apply after the actual Sent header date.
    public let delay: TimeInterval
    /// Optional exact provider locator hint; not an RFC identifier.
    public let sentMessageIDHint: String?

    /// Creates the pending intent for an accepted send on one exact source.
    public init(
        sourceID: MailSourceID,
        draftID: String,
        expectedMessageID: String,
        sentMessageIDHint: String? = nil
    ) {
        id = Self.stableID(sourceID: sourceID, draftID: draftID)
        self.sourceID = sourceID
        self.draftID = draftID
        self.expectedMessageID = expectedMessageID
        delay = DraftNoReplyFollowUpRequest.threeDayDelay
        self.sentMessageIDHint = sentMessageIDHint
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceID
        case draftID
        case expectedMessageID
        case delay
        case sentMessageIDHint
    }

    /// Decodes a pending intent while enforcing its fixed delay and stable identity.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = try container.decode(MailSourceID.self, forKey: .sourceID)
        draftID = try container.decode(String.self, forKey: .draftID)
        id = Self.stableID(sourceID: sourceID, draftID: draftID)
        expectedMessageID = try container.decode(String.self, forKey: .expectedMessageID)
        delay = DraftNoReplyFollowUpRequest.threeDayDelay
        sentMessageIDHint = try container.decodeIfPresent(String.self, forKey: .sentMessageIDHint)
    }

    /// Creates a source- and draft-scoped stable reminder identity.
    public static func stableID(sourceID: MailSourceID, draftID: String) -> String {
        let value = [sourceID.accountID, sourceID.mailboxID, draftID].joined(separator: "\0")
        return "no-reply-\(Data(value.utf8).base64EncodedString())"
    }
}

/// Persisted store for all local follow-up reminders.
public struct FollowUpSettings: Codable, Equatable, Sendable {
    public enum Key {
        public static let reminders = "followUp.reminders"
    }

    public var reminders: [FollowUpReminder]
    /// Accepted sends waiting for an exact cached Sent copy.
    public var pendingNoReplyIntents: [PendingNoReplyFollowUpIntent]

    public static let defaults = FollowUpSettings(reminders: [])

    /// Creates reminder settings and any accepted sends awaiting Sent copies.
    public init(
        reminders: [FollowUpReminder],
        pendingNoReplyIntents: [PendingNoReplyFollowUpIntent] = []
    ) {
        self.reminders = reminders
        self.pendingNoReplyIntents = pendingNoReplyIntents
    }

    private enum CodingKeys: String, CodingKey {
        case reminders
        case pendingNoReplyIntents
    }

    /// Decodes legacy settings with an empty pending-intent collection by default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reminders = try container.decodeIfPresent([FollowUpReminder].self, forKey: .reminders) ?? []
        pendingNoReplyIntents = try container.decodeIfPresent(
            [PendingNoReplyFollowUpIntent].self, forKey: .pendingNoReplyIntents
        ) ?? []
    }

    /// Encodes reminders and pending accepted-send intents for backup and sync.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reminders, forKey: .reminders)
        try container.encode(pendingNoReplyIntents, forKey: .pendingNoReplyIntents)
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
                && !$0.isAutomaticNoReply
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
            if reminder.isAutomaticNoReply, reminder.noReplyMetadata?.sourceID != sourceID { continue }
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
        if reminder.isAutomaticNoReply, reminders.contains(where: { $0.id == reminder.id }) { return }
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

    /// Replaces a pending intent with the same exact source and draft identity.
    public mutating func upsertPendingNoReplyIntent(_ intent: PendingNoReplyFollowUpIntent) {
        pendingNoReplyIntents.removeAll { $0.id == intent.id }
        pendingNoReplyIntents.append(intent)
    }

    /// Removes the pending intent associated with a cancelled scheduled draft.
    public mutating func removePendingNoReplyIntent(sourceID: MailSourceID, draftID: String) {
        let id = PendingNoReplyFollowUpIntent.stableID(sourceID: sourceID, draftID: draftID)
        pendingNoReplyIntents.removeAll { $0.id == id }
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
