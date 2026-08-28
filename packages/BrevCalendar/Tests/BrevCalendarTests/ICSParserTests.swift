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

@testable import BrevCalendar
import Foundation
import Testing

@Suite("ICSParser")
struct ICSParserTests {
    @Test("parses folded event text, organizer, attendees, and UTC dates")
    func parsesFoldedEventTextOrganizerAttendeesAndUTCDates() throws {
        let event = try #require(ICSParser.parseFirstEvent(from: [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "BEGIN:VEVENT",
            "UID:event-123",
            "SUMMARY:Quarterly planning\\, Q2",
            "DESCRIPTION:Line one\\nline two",
            " continued",
            "LOCATION:Oslo\\; Room 4",
            "DTSTART:20260601T120000Z",
            "DTEND:20260601T130000Z",
            "ORGANIZER;CN=Henrik Øgård:mailto:henrik@example.com",
            "ATTENDEE;CN=Alex Berg:mailto:alex@example.com",
            "END:VEVENT",
            "END:VCALENDAR"
        ].joined(separator: "\r\n")))

        #expect(event.uid == "event-123")
        #expect(event.summary == "Quarterly planning, Q2")
        #expect(event.description == "Line one\nline twocontinued")
        #expect(event.location == "Oslo; Room 4")
        #expect(event.isAllDay == false)
        #expect(event.organizer == ICSParser.ParsedPerson(
            name: "Henrik Øgård",
            email: "henrik@example.com"
        ))
        #expect(event.attendees == [
            ICSParser.ParsedPerson(name: "Alex Berg", email: "alex@example.com")
        ])

        let calendar = Calendar(identifier: .gregorian)
        let startComponents = try calendar.dateComponents(
            in: TimeZone(identifier: "UTC")!,
            from: #require(event.start)
        )
        #expect(startComponents.year == 2026)
        #expect(startComponents.month == 6)
        #expect(startComponents.day == 1)
        #expect(startComponents.hour == 12)
    }

    @Test("parses all-day date values")
    func parsesAllDayDateValues() throws {
        let event = try #require(ICSParser.parseFirstEvent(from: """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:day-1
        SUMMARY:Focus day
        DTSTART;VALUE=DATE:20260714
        DTEND;VALUE=DATE:20260715
        END:VEVENT
        END:VCALENDAR
        """))

        #expect(event.isAllDay)
        #expect(event.start == Self.utcDate(year: 2026, month: 7, day: 14))
        #expect(event.end == Self.utcDate(year: 2026, month: 7, day: 15))
    }

    // MARK: - VTIMEZONE

    @Test("DTSTART with TZID is converted to UTC using the VTIMEZONE offset")
    func dtStartWithTZIDConvertedToUTCFromVTIMEZONE() throws {
        // Europe/Oslo is UTC+2 in summer (STANDARD offset here is +0100 for
        // the winter standard time; we use +0200 to represent a UTC+2 zone
        // that is easier to verify against the expected UTC time).
        let ics = [
            "BEGIN:VCALENDAR",
            "BEGIN:VTIMEZONE",
            "TZID:TestZone/UTC+2",
            "BEGIN:STANDARD",
            "TZOFFSETTO:+0200",
            "TZOFFSETFROM:+0100",
            "DTSTART:19701025T030000",
            "END:STANDARD",
            "END:VTIMEZONE",
            "BEGIN:VEVENT",
            "UID:tz-test-1",
            "SUMMARY:Timezone test",
            "DTSTART;TZID=TestZone/UTC+2:20261201T090000",
            "DTEND;TZID=TestZone/UTC+2:20261201T100000",
            "END:VEVENT",
            "END:VCALENDAR"
        ].joined(separator: "\r\n")

        let event = try #require(ICSParser.parseFirstEvent(from: ics))

        // 09:00 in UTC+2 == 07:00 UTC
        let cal = Calendar(identifier: .gregorian)
        let startUTC = try cal.dateComponents(
            in: TimeZone(identifier: "UTC")!,
            from: #require(event.start)
        )
        #expect(startUTC.year == 2026)
        #expect(startUTC.month == 12)
        #expect(startUTC.day == 1)
        #expect(startUTC.hour == 7)
        #expect(startUTC.minute == 0)
    }

    @Test("DTSTART with an IANA TZID applies the event-date DST offset, not today's")
    func dtStartWithIANATZIDAppliesEventDateDST() throws {
        // America/New_York is EST (UTC-5) in winter and EDT (UTC-4) in summer.
        // The correct offset depends on the EVENT's date, not when parsing runs —
        // the previous fixed-offset approach applied today's offset to both.
        func startUTCHour(forDate yyyymmdd: String) throws -> Int {
            let ics = [
                "BEGIN:VCALENDAR",
                "BEGIN:VEVENT",
                "UID:dst-test",
                "SUMMARY:DST test",
                "DTSTART;TZID=America/New_York:\(yyyymmdd)T120000",
                "DTEND;TZID=America/New_York:\(yyyymmdd)T130000",
                "END:VEVENT",
                "END:VCALENDAR"
            ].joined(separator: "\r\n")
            let event = try #require(ICSParser.parseFirstEvent(from: ics))
            let comps = try Calendar(identifier: .gregorian).dateComponents(
                in: #require(TimeZone(identifier: "UTC")),
                from: #require(event.start)
            )
            return try #require(comps.hour)
        }

        #expect(try startUTCHour(forDate: "20261215") == 17) // noon EST (UTC-5)
        #expect(try startUTCHour(forDate: "20260715") == 16) // noon EDT (UTC-4)
    }

    // MARK: - RRULE

    @Test("RRULE FREQ=WEEKLY;BYDAY=MO,WE;COUNT=3 parses correctly")
    func rruleWeeklyByDayCount() throws {
        let ics = [
            "BEGIN:VCALENDAR",
            "BEGIN:VEVENT",
            "UID:recur-1",
            "SUMMARY:Team sync",
            "DTSTART:20260602T100000Z",
            "RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=3",
            "END:VEVENT",
            "END:VCALENDAR"
        ].joined(separator: "\r\n")

        let event = try #require(ICSParser.parseFirstEvent(from: ics))
        let rule = try #require(event.recurrenceRule)

        #expect(rule.frequency == .weekly)
        #expect(rule.interval == 1)
        #expect(rule.count == 3)
        #expect(rule.until == nil)
        #expect(rule.byDay == [.monday, .wednesday])
    }

    @Test("ICS without RRULE parses correctly with recurrenceRule == nil")
    func noRRuleProducesNilRecurrenceRule() throws {
        let ics = [
            "BEGIN:VCALENDAR",
            "BEGIN:VEVENT",
            "UID:no-recur",
            "SUMMARY:One-off meeting",
            "DTSTART:20260610T140000Z",
            "DTEND:20260610T150000Z",
            "END:VEVENT",
            "END:VCALENDAR"
        ].joined(separator: "\r\n")

        let event = try #require(ICSParser.parseFirstEvent(from: ics))

        #expect(event.recurrenceRule == nil)
    }

    @Test("RRULE with FREQ=DAILY;INTERVAL=2;UNTIL parses interval and until date")
    func rruleDailyIntervalUntil() throws {
        let ics = [
            "BEGIN:VCALENDAR",
            "BEGIN:VEVENT",
            "UID:recur-2",
            "SUMMARY:Daily standup",
            "DTSTART:20260601T090000Z",
            "RRULE:FREQ=DAILY;INTERVAL=2;UNTIL=20261231T000000Z",
            "END:VEVENT",
            "END:VCALENDAR"
        ].joined(separator: "\r\n")

        let event = try #require(ICSParser.parseFirstEvent(from: ics))
        let rule = try #require(event.recurrenceRule)

        #expect(rule.frequency == .daily)
        #expect(rule.interval == 2)
        #expect(rule.count == nil)
        #expect(rule.byDay == nil)
        let until = try #require(rule.until)
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: until)
        #expect(comps.year == 2026)
        #expect(comps.month == 12)
        #expect(comps.day == 31)
    }

    // MARK: - Helpers

    private static func utcDate(year: Int, month: Int, day: Int) -> Date? {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: year,
            month: month,
            day: day
        ).date
    }
}
