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
@testable import BrevMail
import Foundation
import Testing

/// Presentation-helper coverage for the Calendar surface (ADR-0072 #6):
/// day bucketing, time text, recurrence summaries, RSVP labels, and the
/// local search corpus.
@Suite("CalendarEventPresentation")
struct CalendarEventPresentationTests {
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func event(
        start: Date? = nil,
        end: Date? = nil,
        isAllDay: Bool = false,
        summary: String? = nil,
        location: String? = nil
    ) -> PIMEvent {
        PIMEvent(
            id: UUID().uuidString,
            sourceID: "s",
            collectionID: "c",
            providerItemKey: "k",
            summary: summary,
            location: location,
            start: start,
            end: end,
            isAllDay: isAllDay
        )
    }

    // MARK: - Day bucketing

    @Test("all-day events bucket by their literal UTC date, not local")
    func allDayBucketsInUTC() {
        // VALUE=DATE:20260615 pins to midnight UTC. A viewer at UTC-7
        // would otherwise bucket it under June 14.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let start = utc.date(
            from: DateComponents(year: 2026, month: 6, day: 15)
        )!
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let event = Self.event(start: start, isAllDay: true)

        let bucket = CalendarEventPresentation.dayStart(
            for: event,
            calendar: pacific
        )
        #expect(
            bucket == utc.date(
                from: DateComponents(year: 2026, month: 6, day: 15)
            )
        )
    }

    @Test("timed events bucket by the viewer's local day")
    func timedBucketsLocally() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(
            from: DateComponents(
                year: 2026, month: 6, day: 15, hour: 14
            )
        )!

        let event = Self.event(start: start)

        #expect(
            CalendarEventPresentation.dayStart(
                for: event,
                calendar: calendar
            ) == calendar.startOfDay(for: start)
        )
    }

    // MARK: - Agenda time text

    @Test("all-day rows read All day")
    func agendaAllDay() {
        let event = Self.event(
            start: Date(timeIntervalSince1970: 1_800_000_000),
            isAllDay: true
        )
        #expect(
            CalendarEventPresentation.agendaTimeText(
                for: event,
                calendar: Self.utcCalendar
            ) == "All day"
        )
    }

    @Test("timed rows join start and end times in the same day")
    func agendaTimedRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(
            from: DateComponents(
                year: 2026, month: 6, day: 15, hour: 9
            )
        )!
        let end = calendar.date(
            from: DateComponents(
                year: 2026, month: 6, day: 15, hour: 10
            )
        )!
        let event = Self.event(start: start, end: end)

        let text = CalendarEventPresentation.agendaTimeText(
            for: event,
            calendar: calendar
        )

        // Timed text renders in the viewer's zone, so compare against
        // the same formatter rather than absolute hours.
        let startText = start.formatted(.dateTime.hour().minute())
        let endText = end.formatted(.dateTime.hour().minute())
        #expect(text == "\(startText) – \(endText)")
        #expect(text.contains("–"))
    }

    // MARK: - Recurrence

    @Test("weekly rule names its BYDAY weekdays in order")
    func recurrenceWeekly() {
        let rule = ICSParser.RecurrenceRule(
            frequency: .weekly,
            byDay: [.friday, .monday]
        )

        let text = CalendarEventPresentation.recurrenceSummary(
            for: rule,
            calendar: Self.utcCalendar
        )

        // Weekday order follows the week, not the BYDAY token order.
        let monday = Calendar.current.standaloneWeekdaySymbols[1]
        let friday = Calendar.current.standaloneWeekdaySymbols[5]
        #expect(text.contains(monday))
        #expect(text.contains(friday))
        #expect(
            text.range(of: monday)!.lowerBound
                < text.range(of: friday)!.lowerBound
        )
    }

    @Test("interval and until both render")
    func recurrenceIntervalUntil() {
        let until = Self.utcCalendar.date(
            from: DateComponents(year: 2027, month: 1, day: 5)
        )!
        let rule = ICSParser.RecurrenceRule(
            frequency: .weekly,
            interval: 2,
            until: until
        )

        let text = CalendarEventPresentation.recurrenceSummary(
            for: rule,
            calendar: Self.utcCalendar
        )

        #expect(text.contains("2"))
        #expect(text.contains("2027"))
    }

    // MARK: - RSVP + reminders

    @Test("RSVP states map to their badge text")
    func rsvpText() {
        #expect(
            CalendarEventPresentation.rsvpText(for: .accepted)
                == "Accepted"
        )
        #expect(
            CalendarEventPresentation.rsvpText(for: .declined)
                == "Declined"
        )
        #expect(
            CalendarEventPresentation.rsvpText(for: .tentative)
                == "Maybe"
        )
    }

    @Test("reminder minutes compress to hours and days")
    func reminderText() {
        #expect(
            CalendarEventPresentation.reminderText(
                for: PIMEventReminder(minutesBefore: 15)
            ) == "15 minutes before"
        )
        #expect(
            CalendarEventPresentation.reminderText(
                for: PIMEventReminder(minutesBefore: 120)
            ) == "2 hours before"
        )
        #expect(
            CalendarEventPresentation.reminderText(
                for: PIMEventReminder(minutesBefore: 1440)
            ) == "1 days before"
        )
        #expect(
            CalendarEventPresentation.reminderText(
                for: PIMEventReminder(minutesBefore: nil)
            ) == "Default reminder"
        )
    }

    // MARK: - Search

    @Test("search is case- and diacritic-insensitive over cached fields")
    func searchMatching() {
        var event = Self.event(
            summary: "Réunion équipe",
            location: "Oslo"
        )
        event.attendees = [
            PIMEventPerson(name: "Åsa", email: "asa@example.com")
        ]

        #expect(CalendarEventPresentation.matches(event, query: "REUNION"))
        #expect(CalendarEventPresentation.matches(event, query: "åsa@"))
        #expect(CalendarEventPresentation.matches(event, query: "oslo"))
        #expect(!CalendarEventPresentation.matches(event, query: "dentist"))
        #expect(CalendarEventPresentation.matches(event, query: "  "))
    }
}
