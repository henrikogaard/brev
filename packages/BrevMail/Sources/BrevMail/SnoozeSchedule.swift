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

/// A quick snooze choice offered by the snooze picker.
enum SnoozeQuickOption: String, CaseIterable, Identifiable {
    case laterToday, thisEvening, tomorrowMorning, thisWeekend, nextWeek

    var id: String { rawValue }

    /// Options that only exist on some days; the macOS sheet keeps its original
    /// three-option list and leaves these out.
    var isExtended: Bool {
        self == .thisEvening || self == .thisWeekend
    }

    /// The moment the message should return, or nil when the option does not
    /// apply at `now` (This evening after 17:00, This weekend from Friday on).
    /// - Parameters:
    ///   - now: The reference "current" time.
    ///   - calendar: Calendar (and time zone) that decides day boundaries.
    func wakeDate(now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .laterToday:
            return calendar.date(byAdding: .hour, value: 3, to: now)
        case .thisEvening:
            guard let cutoff = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now),
                  now < cutoff else { return nil }
            return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now)
        case .tomorrowMorning:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        case .thisWeekend:
            // Foundation numbers weekdays Sunday = 1 for every calendar, so
            // Monday...Thursday is 2...5 and Saturday is 7.
            guard (2 ... 5).contains(calendar.component(.weekday, from: now)) else { return nil }
            return calendar.nextDate(
                after: now,
                matching: DateComponents(hour: 9, minute: 0, weekday: 7),
                matchingPolicy: .nextTime
            )
        case .nextWeek:
            guard let week = calendar.date(byAdding: .weekOfYear, value: 1, to: now) else { return nil }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: week)
        }
    }
}

/// A quick option paired with the date it resolves to.
struct SnoozeSuggestion: Identifiable, Equatable {
    let option: SnoozeQuickOption
    let wakeDate: Date

    var id: String { option.id }
}

/// Date logic and wording for the snooze picker, kept pure so tests can pin
/// `now`, the calendar and the locale.
enum SnoozeSchedule {
    /// Quick options that apply at `now`, in display order.
    static func suggestions(
        now: Date,
        calendar: Calendar,
        includeExtended: Bool = true
    ) -> [SnoozeSuggestion] {
        SnoozeQuickOption.allCases.compactMap { option in
            guard includeExtended || !option.isExtended,
                  let date = option.wakeDate(now: now, calendar: calendar) else { return nil }
            return SnoozeSuggestion(option: option, wakeDate: date)
        }
    }

    /// A custom wake time must lie in the future.
    static func isValidCustomWake(_ date: Date, now: Date) -> Bool {
        date > now
    }

    /// How a wake time is worded next to a row.
    enum LabelStyle {
        /// Short visual label such as "tomorrow 09:00" or "Mon 09:00".
        case compact
        /// VoiceOver wording that spells the weekday out, such as "Friday 09:00".
        case spoken
    }

    /// Locale-aware label for a wake time: a relative day for today and
    /// tomorrow (compact only), a weekday within the next week and a date
    /// beyond that, followed by the time.
    static func label(
        for date: Date,
        now: Date,
        calendar: Calendar,
        locale: Locale,
        style: LabelStyle
    ) -> String {
        let base = Date.FormatStyle(
            date: nil,
            time: nil,
            locale: locale,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        let dayDistance = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        let time = date.formatted(base.hour().minute())

        let day: String
        switch (style, dayDistance) {
        case (.compact, 0), (.spoken, 0):
            day = String(localized: "Today", bundle: .module, locale: locale)
        case (.compact, 1):
            day = String(localized: "Tomorrow", bundle: .module, locale: locale)
        case (.compact, 2 ... 6):
            day = date.formatted(base.weekday(.abbreviated))
        case (.spoken, 1 ... 6):
            day = date.formatted(base.weekday(.wide))
        case (.compact, _):
            day = date.formatted(base.weekday(.abbreviated).day().month(.abbreviated))
        case (.spoken, _):
            day = date.formatted(base.weekday(.wide).day().month(.wide))
        }
        return "\(day) \(time)"
    }
}
