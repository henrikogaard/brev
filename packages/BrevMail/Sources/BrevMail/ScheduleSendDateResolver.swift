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

/// Pure date math for the compose "Schedule send" sheet.
///
/// Calendar is injected so tests can pin a specific date; the default
/// uses the user's current calendar so "Tonight 8pm" lands on the
/// right day in the right timezone.
enum ScheduleSendDateResolver {
    /// Catalog of quick-pick options exposed by the schedule sheet.
    /// The `.custom` case carries no date; the sheet reveals a
    /// `DatePicker` only after the user picks it.
    enum Option: String, CaseIterable, Identifiable, Sendable {
        case sendNow
        case inOneHour
        case tonightEight
        case tomorrowNine
        case nextMonday
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sendNow: "Send now"
            case .inOneHour: "In 1 hour"
            case .tonightEight: "Tonight 8:00 PM"
            case .tomorrowNine: "Tomorrow 9:00 AM"
            case .nextMonday: "Next Monday 9:00 AM"
            case .custom: "Custom…"
            }
        }

        /// System symbol used in the row.
        var symbolName: String {
            switch self {
            case .sendNow: "paperplane"
            case .inOneHour: "clock"
            case .tonightEight: "moon.stars"
            case .tomorrowNine: "sunrise"
            case .nextMonday: "calendar"
            case .custom: "calendar.badge.plus"
            }
        }

        /// `true` for non-custom options, `false` for the date-picker
        /// case. Used by the sheet to decide when to reveal the picker.
        var isQuickPick: Bool { self != .custom }
    }

    /// Resolves a quick-pick option to a concrete `Date` in the
    /// supplied calendar relative to `now`. `Option.custom` returns
    /// `nil` because the sheet handles custom dates via the
    /// `DatePicker`.
    static func date(
        for option: Option,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        switch option {
        case .sendNow:
            return nil
        case .inOneHour:
            return now.addingTimeInterval(60 * 60)
        case .tonightEight:
            return eveningAnchor(now: now, calendar: calendar)
        case .tomorrowNine:
            return morningAnchor(now: now, calendar: calendar, dayOffset: 1)
        case .nextMonday:
            return nextMondayMorning(now: now, calendar: calendar)
        case .custom:
            return nil
        }
    }

    /// Returns the next 8:00 PM strictly in the future relative to
    /// `now`. If 8 PM has already passed today, rolls over to
    /// tomorrow at 8 PM.
    private static func eveningAnchor(
        now: Date,
        calendar: Calendar
    ) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        guard let startOfDay = calendar.date(from: components),
              let eveningStart = calendar.date(
                  bySettingHour: 20,
                  minute: 0,
                  second: 0,
                  of: startOfDay
              ) else {
            return now.addingTimeInterval(60 * 60)
        }
        if eveningStart > now {
            return eveningStart
        }
        return calendar.date(byAdding: .day, value: 1, to: eveningStart) ?? eveningStart
    }

    /// Returns the 9:00 AM of `now + dayOffset` days. Negative or
    /// zero offsets are normalized to "next available morning".
    private static func morningAnchor(
        now: Date,
        calendar: Calendar,
        dayOffset: Int
    ) -> Date {
        let base = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
        let components = calendar.dateComponents([.year, .month, .day], from: base)
        return calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: calendar.date(from: components) ?? base
        ) ?? base
    }

    /// Returns 9:00 AM of the *next* Monday strictly in the future.
    /// If today is Monday, jumps to the following Monday so we never
    /// schedule "now or earlier".
    private static func nextMondayMorning(
        now: Date,
        calendar: Calendar
    ) -> Date {
        let weekday = calendar.component(.weekday, from: now)
        let daysUntilMonday: Int
        if weekday == Self.mondayWeekday {
            daysUntilMonday = 7
        } else {
            daysUntilMonday = (Self.mondayWeekday - weekday + 7) % 7
        }
        let target = calendar.date(byAdding: .day, value: max(daysUntilMonday, 1), to: now) ?? now
        let components = calendar.dateComponents([.year, .month, .day], from: target)
        return calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: calendar.date(from: components) ?? target
        ) ?? target
    }

    /// Foundation's weekday numbering is Sunday = 1, Monday = 2.
    private static let mondayWeekday = 2

    /// Lightweight formatter for the inline status banner.
    static func formattedScheduleDate(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// Copy shared by the schedule-send sheet and the app-level quit warning.
public enum ScheduleSendReliabilityPresentation {
    static let localDeliveryNotice =
        "Brev sends scheduled messages while it is running. If Brev is fully quit at the send time, the message sends the next time you open Brev."

    /// Body text for the quit confirmation shown while scheduled sends are
    /// still pending, or `nil` when there is nothing to warn about.
    public static func quitWarningMessage(pendingCount: Int) -> String? {
        guard pendingCount > 0 else { return nil }
        let noun = pendingCount == 1 ? "message" : "messages"
        return "\(pendingCount) scheduled \(noun) will not be sent until Brev is next opened."
    }
}
