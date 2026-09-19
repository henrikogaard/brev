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

/// Index over `FollowUpSettings` so per-row reminder lookups don't scan the
/// full reminders array once per rendered row. Active reminders are grouped
/// by message when settings (re)load; the per-message bucket keeps the
/// exact-mailbox → account-scoped → global priority order identical to
/// `FollowUpSettings.reminder(for:sourceID:)`.
struct FollowUpReminderIndex {
    private let activeRemindersByMessageID: [String: [FollowUpReminder]]

    init(settings: FollowUpSettings) {
        activeRemindersByMessageID = Dictionary(
            grouping: settings.reminders.filter { !$0.isDismissed && !$0.isCompleted },
            by: \.messageID
        )
    }

    /// Same resolution as `FollowUpSettings.reminder(for:sourceID:)`, but
    /// only over the active reminders for this message.
    func reminder(for messageID: String, sourceID: MailSourceID?) -> FollowUpReminder? {
        var exactMatch: FollowUpReminder?
        var accountMatch: FollowUpReminder?
        var globalMatch: FollowUpReminder?

        for reminder in activeRemindersByMessageID[messageID] ?? [] {
            guard let sourceID else {
                globalMatch = earlier(globalMatch, reminder)
                continue
            }
            if reminder.accountID == sourceID.accountID,
               reminder.mailboxID == sourceID.mailboxID {
                exactMatch = earlier(exactMatch, reminder)
            } else if reminder.accountID == sourceID.accountID,
                      reminder.mailboxID == nil {
                accountMatch = earlier(accountMatch, reminder)
            } else if reminder.accountID == nil, reminder.mailboxID == nil {
                globalMatch = earlier(globalMatch, reminder)
            }
        }

        return exactMatch ?? accountMatch ?? globalMatch
    }

    private func earlier(
        _ current: FollowUpReminder?,
        _ candidate: FollowUpReminder
    ) -> FollowUpReminder {
        guard let current else { return candidate }
        return candidate.dueAt < current.dueAt ? candidate : current
    }
}
