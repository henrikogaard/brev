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

/// Per-device opt-in for cross-device preference sync (ADR-0056).
///
/// The toggle is itself device-local and deliberately absent from
/// `PreferenceSyncAllowlist`, so enabling sync on one device never
/// enables it elsewhere.
public struct PreferenceSyncSettings: Equatable, Sendable {
    public enum Key {
        public static let iCloudSyncEnabled = "sync.preferences.iCloudEnabled"
    }

    /// `true` when the user has opted in to mirroring allowlisted
    /// preferences through iCloud Key-Value Storage. Off by default.
    public var isICloudSyncEnabled: Bool

    public static let defaults = PreferenceSyncSettings(isICloudSyncEnabled: false)

    public init(isICloudSyncEnabled: Bool) {
        self.isICloudSyncEnabled = isICloudSyncEnabled
    }

    public static func load(from defaults: UserDefaults = .standard) -> PreferenceSyncSettings {
        PreferenceSyncSettings(
            isICloudSyncEnabled: defaults.bool(forKey: Key.iCloudSyncEnabled)
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(isICloudSyncEnabled, forKey: Key.iCloudSyncEnabled)
    }
}

/// The exact `UserDefaults` keys that phase-1 preference sync mirrors.
///
/// Every entry must be per-user (not per-device), contain no mail
/// content or credentials, and stay small. Adding a key means editing
/// this list and the table in ADR-0056. Consent flags that gate network
/// features are intentionally absent so an opt-in on one device never
/// silently enables a data flow on another.
public enum PreferenceSyncAllowlist {
    public static let keys: [String] = [
        // Workflow state: snoozes, done markers, local notes (BrevBackend).
        "message.workflowState.v1",
        // VIP senders.
        "vip.senders",
        // Manual inbox category overrides (BrevMail, ADR-0035).
        "list.inboxCategoryOverrides",
        // Pinned messages (BrevMail).
        "list.pinnedMessageIDs",
        "list.pinnedSourceMessageIDs.v2",
        // Blocked senders.
        "blockedSenders.emails",
        // Follow-up reminders.
        "followUp.reminders",
        // Signatures.
        "signature.settings",
        // Message templates.
        "messageTemplates.v1",
        // Smart mailboxes.
        "smartMailbox.mailboxes",
        // Compose preferences.
        "compose.messageFormat",
        "compose.quotePlacement",
        "compose.attachmentReminderEnabled",
        "compose.externalRecipientWarningEnabled",
        "compose.undoSendDelay",
        // Sidebar smart-folder visibility.
        "folders.showAllMail",
        "folders.showArchive",
        "folders.showScheduled",
        "folders.showSnoozed",
        "folders.showSpam",
        "folders.showStarred",
        "folders.showTrash"
    ]
}
