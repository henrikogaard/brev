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

enum FollowUpReminderPreset: String, CaseIterable, Sendable, Identifiable {
    case laterToday
    case tomorrow
    case nextWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .laterToday: return String(localized: "Later Today", bundle: .module)
        case .tomorrow: return String(localized: "Tomorrow", bundle: .module)
        case .nextWeek: return String(localized: "Next Week", bundle: .module)
        }
    }
}

enum FollowUpReminderPresentation {
    static let menuTitle = String(localized: "Follow Up", bundle: .module)

    static func dueAt(for preset: FollowUpReminderPreset, now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch preset {
        case .laterToday:
            return calendar.date(byAdding: .hour, value: 4, to: now) ?? now.addingTimeInterval(4 * 3600)
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(24 * 3600)
        case .nextWeek:
            return calendar.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(7 * 24 * 3600)
        }
    }

    static func reminder(
        for header: MessageHeader,
        sourceID: MailSourceID?,
        dueAt: Date,
        now: Date = Date()
    ) -> FollowUpReminder {
        FollowUpReminder(
            messageID: header.id,
            threadID: header.threadID,
            accountID: sourceID?.accountID,
            mailboxID: sourceID?.mailboxID,
            folderID: header.folderID,
            dueAt: max(dueAt, now)
        )
    }
}
