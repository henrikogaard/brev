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

import BrevCalendar
import Foundation

/// Presentation strings for cached calendar events (ADR-0072 browsing).
///
/// Pure functions over `PIMEvent` so the agenda and detail surfaces share
/// one formatting contract and stay testable without rendering a view.
/// All-day events carry a floating `VALUE=DATE` that the sync layer pins to
/// midnight UTC; every helper that renders an all-day value therefore works
/// in UTC so a viewer west of UTC never sees the date a day early.
public enum CalendarEventPresentation {
    /// The day an event buckets under in the agenda — the viewer's local
    /// day for timed events, the literal UTC date for all-day events.
    public static func dayStart(
        for event: PIMEvent,
        calendar: Calendar
    ) -> Date? {
        guard let start = event.start else { return nil }
        if event.isAllDay {
            var utc = calendar
            utc.timeZone = TimeZone(identifier: "UTC") ?? utc.timeZone
            return utc.startOfDay(for: start)
        }
        return calendar.startOfDay(for: start)
    }

    /// Compact row text: "All day", "9:00 – 10:30", or a start-only time
    /// when the provider sent no end.
    public static func agendaTimeText(
        for event: PIMEvent,
        calendar: Calendar
    ) -> String {
        if event.isAllDay {
            return String(localized: "All day", bundle: .module)
        }
        guard let start = event.start else {
            return String(localized: "No time", bundle: .module)
        }
        let startText = start.formatted(.dateTime.hour().minute())
        guard let end = event.end,
              calendar.isDate(start, inSameDayAs: end)
        else {
            return startText
        }
        return "\(startText) – \(end.formatted(.dateTime.hour().minute()))"
    }

    /// Section header for an agenda day bucket: "Today", "Tomorrow",
    /// or the localized weekday + date for anything further out.
    public static func daySectionTitle(
        for day: Date,
        calendar: Calendar,
        now: Date
    ) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            return String(localized: "Today", bundle: .module)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(day, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow", bundle: .module)
        }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }

    /// Long-form range for the detail header, e.g.
    /// "Tuesday, September 22, 2026, 9:00 AM – 10:30 AM" or the all-day
    /// date. Multi-day timed events render start and end in full.
    public static func detailRangeText(for event: PIMEvent) -> String {
        guard let start = event.start else {
            return String(localized: "No scheduled time", bundle: .module)
        }
        return CalendarEventRangeFormatter.string(
            start: start,
            end: event.end,
            isAllDay: event.isAllDay,
            separator: "–"
        )
    }

    /// Human-readable repeat rule: "Every 2 weeks on Monday and Friday",
    /// "Daily", "Monthly, until June 1, 2027". Falls back to a plain
    /// frequency word when the rule carries no modifiers.
    public static func recurrenceSummary(
        for rule: ICSParser.RecurrenceRule,
        calendar: Calendar
    ) -> String {
        var parts: [String] = []
        let frequencyWord: String
        switch rule.frequency {
        case .daily:
            frequencyWord = rule.interval > 1
                ? String(localized: "days", bundle: .module)
                : String(localized: "day", bundle: .module)
        case .weekly:
            frequencyWord = rule.interval > 1
                ? String(localized: "weeks", bundle: .module)
                : String(localized: "week", bundle: .module)
        case .monthly:
            frequencyWord = rule.interval > 1
                ? String(localized: "months", bundle: .module)
                : String(localized: "month", bundle: .module)
        case .yearly:
            frequencyWord = rule.interval > 1
                ? String(localized: "years", bundle: .module)
                : String(localized: "year", bundle: .module)
        }
        if rule.interval > 1 {
            parts.append(
                String(
                    localized: "Every \(rule.interval) \(frequencyWord)",
                    bundle: .module
                )
            )
        } else {
            let capitalized = frequencyWord.prefix(1).uppercased()
                + frequencyWord.dropFirst()
            parts.append(
                String(
                    localized: "Every \(capitalized)",
                    bundle: .module
                )
            )
        }
        if let byDay = rule.byDay, !byDay.isEmpty {
            let names = byDay
                .sorted { weekdayIndex($0) < weekdayIndex($1) }
                .map(weekdayName)
            parts.append(
                String(
                    localized: "on \(names.formatted(.list(type: .and)))",
                    bundle: .module
                )
            )
        }
        if let until = rule.until {
            parts.append(
                String(
                    localized: "until \(until.formatted(.dateTime.month().day().year()))",
                    bundle: .module
                )
            )
        } else if let count = rule.count {
            parts.append(
                String(
                    localized: "\(count) times",
                    bundle: .module
                )
            )
        }
        return parts.joined(separator: " ")
    }

    /// RSVP badge text for an attendee row.
    public static func rsvpText(for rsvp: PIMEventPerson.RSVP) -> String {
        switch rsvp {
        case .accepted:
            String(localized: "Accepted", bundle: .module)
        case .declined:
            String(localized: "Declined", bundle: .module)
        case .tentative:
            String(localized: "Maybe", bundle: .module)
        case .needsAction:
            String(localized: "No reply", bundle: .module)
        case .delegated:
            String(localized: "Delegated", bundle: .module)
        case .unknown:
            String(localized: "No reply", bundle: .module)
        }
    }

    /// Reminder row text: "15 minutes before" or the provider default.
    public static func reminderText(for reminder: PIMEventReminder) -> String {
        guard let minutes = reminder.minutesBefore else {
            return String(localized: "Default reminder", bundle: .module)
        }
        if minutes == 0 {
            return String(localized: "At start", bundle: .module)
        }
        if minutes < 60 {
            return String(
                localized: "\(minutes) minutes before",
                bundle: .module
            )
        }
        if minutes < 60 * 24, minutes % 60 == 0 {
            return String(
                localized: "\(minutes / 60) hours before",
                bundle: .module
            )
        }
        if minutes % (60 * 24) == 0 {
            return String(
                localized: "\(minutes / (60 * 24)) days before",
                bundle: .module
            )
        }
        return String(
            localized: "\(minutes) minutes before",
            bundle: .module
        )
    }

    /// Status badge for cancelled/tentative events; nil for confirmed.
    public static func statusText(for status: PIMEventStatus) -> String? {
        switch status {
        case .confirmed: nil
        case .tentative:
            String(localized: "Tentative", bundle: .module)
        case .cancelled:
            String(localized: "Cancelled", bundle: .module)
        }
    }

    /// The local-only search corpus for an event — title, location,
    /// description, organizer and attendee names and addresses. Provider
    /// payloads are never searched here; the cache fields are.
    public static func searchableText(of event: PIMEvent) -> String {
        var fields: [String] = []
        if let summary = event.summary { fields.append(summary) }
        if let location = event.location { fields.append(location) }
        if let description = event.eventDescription {
            fields.append(description)
        }
        if let organizer = event.organizer {
            fields.append(organizer.email)
            if let name = organizer.name { fields.append(name) }
        }
        for attendee in event.attendees {
            fields.append(attendee.email)
            if let name = attendee.name { fields.append(name) }
        }
        return fields.joined(separator: "\n")
    }

    /// Whether an event matches a trimmed, case- and diacritic-insensitive
    /// query across the cached fields.
    public static func matches(_ event: PIMEvent, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return searchableText(of: event).range(
            of: trimmed,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    /// The display name used when an event carries no summary.
    public static func untitledTitle() -> String {
        String(localized: "(No title)", bundle: .module)
    }

    private static func weekdayName(
        _ weekday: ICSParser.Weekday
    ) -> String {
        // Localized standalone weekday names, ordered Monday-first to
        // match the RFC 5545 BYDAY vocabulary.
        let symbols = Calendar.current.standaloneWeekdaySymbols
        return symbols[weekdayIndex(weekday)]
    }

    /// Sunday-first index matching `Calendar.standaloneWeekdaySymbols`.
    private static func weekdayIndex(_ weekday: ICSParser.Weekday) -> Int {
        switch weekday {
        case .sunday: return 0
        case .monday: return 1
        case .tuesday: return 2
        case .wednesday: return 3
        case .thursday: return 4
        case .friday: return 5
        case .saturday: return 6
        }
    }
}
