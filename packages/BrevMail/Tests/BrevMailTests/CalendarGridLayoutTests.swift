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

/// Grid-math coverage for the day/week/month layouts (ADR-0072 #6):
/// day coverage incl. all-day exclusive ends and multi-day spans, week
/// and month grid shapes, overlap lanes, and range titles.
@Suite("CalendarGridLayout")
struct CalendarGridLayoutTests {
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday, European convention
        return calendar
    }

    private static func day(
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        utc.date(
            from: DateComponents(
                year: 2026,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private static func event(
        id: String,
        start: Date? = nil,
        end: Date? = nil,
        isAllDay: Bool = false
    ) -> PIMEvent {
        PIMEvent(
            id: id,
            sourceID: "s",
            collectionID: "c",
            providerItemKey: id,
            summary: id,
            start: start,
            end: end,
            isAllDay: isAllDay
        )
    }

    // MARK: - Day coverage

    @Test("a timed event covers only the days its interval intersects")
    func timedCoverage() {
        // 22:00 – 23:30 covers the 15th only.
        let event = Self.event(
            id: "e",
            start: Self.day(6, 15, hour: 22),
            end: Self.day(6, 15, hour: 23, minute: 30)
        )
        #expect(
            CalendarGridLayout.coversDay(
                event, day: Self.day(6, 15), calendar: Self.utc
            )
        )
        #expect(
            !CalendarGridLayout.coversDay(
                event, day: Self.day(6, 14), calendar: Self.utc
            )
        )
        #expect(
            !CalendarGridLayout.coversDay(
                event, day: Self.day(6, 16), calendar: Self.utc
            )
        )
    }

    @Test("a multi-day timed event covers every day it touches")
    func multiDayTimedCoverage() {
        let event = Self.event(
            id: "e",
            start: Self.day(6, 15, hour: 22),
            end: Self.day(6, 17, hour: 9)
        )
        for day in [15, 16, 17] {
            #expect(
                CalendarGridLayout.coversDay(
                    event, day: Self.day(6, day), calendar: Self.utc
                )
            )
        }
        #expect(
            !CalendarGridLayout.coversDay(
                event, day: Self.day(6, 18), calendar: Self.utc
            )
        )
    }

    @Test("an event ending at midnight does not bleed into that day")
    func midnightEndExcluded() {
        let event = Self.event(
            id: "e",
            start: Self.day(6, 15, hour: 22),
            end: Self.day(6, 16, hour: 0)
        )
        #expect(
            !CalendarGridLayout.coversDay(
                event, day: Self.day(6, 16), calendar: Self.utc
            )
        )
    }

    @Test("an all-day event's exclusive DTEND stays off the next day")
    func allDayExclusiveEnd() {
        // RFC 5545: DTEND for VALUE=DATE is the day AFTER the last
        // covered day. A one-day event stores start=15, end=16.
        let event = Self.event(
            id: "e",
            start: Self.day(6, 15),
            end: Self.day(6, 16),
            isAllDay: true
        )
        #expect(
            CalendarGridLayout.coversDay(
                event, day: Self.day(6, 15), calendar: Self.utc
            )
        )
        #expect(
            !CalendarGridLayout.coversDay(
                event, day: Self.day(6, 16), calendar: Self.utc
            )
        )
    }

    @Test("a three-day all-day event covers all three days")
    func allDayMultiDay() {
        let event = Self.event(
            id: "e",
            start: Self.day(6, 15),
            end: Self.day(6, 18), // exclusive — covers 15, 16, 17
            isAllDay: true
        )
        for day in [15, 16, 17] {
            #expect(
                CalendarGridLayout.coversDay(
                    event, day: Self.day(6, day), calendar: Self.utc
                )
            )
        }
        #expect(
            !CalendarGridLayout.coversDay(
                event, day: Self.day(6, 18), calendar: Self.utc
            )
        )
    }

    @Test("undated events cover no day")
    func undatedCoversNothing() {
        let event = Self.event(id: "e")
        #expect(
            !CalendarGridLayout.coversDay(
                event, day: Self.day(6, 15), calendar: Self.utc
            )
        )
    }

    @Test("events(onDay:) sorts all-day first, then by start")
    func dayOrdering() {
        let events = [
            Self.event(
                id: "timed2",
                start: Self.day(6, 15, hour: 14),
                end: Self.day(6, 15, hour: 15)
            ),
            Self.event(
                id: "allDay",
                start: Self.day(6, 15),
                end: Self.day(6, 16),
                isAllDay: true
            ),
            Self.event(
                id: "timed1",
                start: Self.day(6, 15, hour: 9),
                end: Self.day(6, 15, hour: 10)
            ),
        ]
        let day = CalendarGridLayout.events(
            events,
            onDay: Self.day(6, 15),
            calendar: Self.utc
        )
        #expect(day.map(\.id) == ["allDay", "timed1", "timed2"])
    }

    // MARK: - Week

    @Test("weekDays honors the first-weekday setting")
    func weekDays() {
        // June 15 2026 is a Monday; firstWeekday 2 → week starts on it.
        let days = CalendarGridLayout.weekDays(
            containing: Self.day(6, 17), // Wednesday
            calendar: Self.utc
        )
        #expect(days.count == 7)
        #expect(days.first == Self.day(6, 15))
        #expect(days.last == Self.day(6, 21))
    }

    @Test("weekDays with Sunday-first wraps the prior week")
    func weekDaysSundayFirst() {
        var sundayFirst = Self.utc
        sundayFirst.firstWeekday = 1
        let days = CalendarGridLayout.weekDays(
            containing: Self.day(6, 17),
            calendar: sundayFirst
        )
        #expect(days.first == Self.day(6, 14))
        #expect(days.last == Self.day(6, 20))
    }

    // MARK: - Month

    @Test("the month grid covers complete weeks in seven-cell rows")
    func monthGrid() {
        // June 2026: 1st is a Monday, 30th a Tuesday — a clean 5-week
        // grid Monday-first.
        let weeks = CalendarGridLayout.monthWeeks(
            containing: Self.day(6, 15),
            calendar: Self.utc
        )
        #expect(weeks.count == 5)
        #expect(weeks.allSatisfy { $0.count == 7 })
        #expect(weeks[0][0].day == Self.day(6, 1))
        #expect(weeks[0][0].inMonth)
        #expect(weeks[4].last?.day == Self.day(7, 5))
        #expect(weeks[4].last?.inMonth == false)
    }

    @Test("a month starting mid-week borrows leading days")
    func monthGridLeadingPadding() {
        // February 2026 starts on a Sunday — Monday-first grid borrows
        // January 26-31.
        let weeks = CalendarGridLayout.monthWeeks(
            containing: Self.day(2, 10),
            calendar: Self.utc
        )
        #expect(weeks[0][0].day == Self.day(1, 26))
        #expect(!weeks[0][0].inMonth)
        #expect(weeks[0].last?.day == Self.day(2, 1))
        #expect(weeks[0].last?.inMonth == true)
    }

    // MARK: - Timed lanes

    @Test("non-overlapping events each get a full-width lane")
    func lanesNoOverlap() {
        let placements = CalendarGridLayout.timedLanes(
            [
                Self.event(
                    id: "a",
                    start: Self.day(6, 15, hour: 9),
                    end: Self.day(6, 15, hour: 10)
                ),
                Self.event(
                    id: "b",
                    start: Self.day(6, 15, hour: 10),
                    end: Self.day(6, 15, hour: 11)
                ),
            ],
            onDay: Self.day(6, 15),
            calendar: Self.utc
        )
        #expect(placements.count == 2)
        #expect(placements.allSatisfy { $0.lane == 0 && $0.laneCount == 1 })
        #expect(placements[0].startMinute == 9 * 60)
        #expect(placements[0].durationMinutes == 60)
    }

    @Test("overlapping events split into lanes within one group")
    func lanesOverlap() {
        let placements = CalendarGridLayout.timedLanes(
            [
                Self.event(
                    id: "a",
                    start: Self.day(6, 15, hour: 9),
                    end: Self.day(6, 15, hour: 11)
                ),
                Self.event(
                    id: "b",
                    start: Self.day(6, 15, hour: 10),
                    end: Self.day(6, 15, hour: 12)
                ),
                Self.event(
                    id: "c",
                    start: Self.day(6, 15, hour: 10, minute: 30),
                    end: Self.day(6, 15, hour: 11, minute: 30)
                ),
            ],
            onDay: Self.day(6, 15),
            calendar: Self.utc
        )
        // a and c overlap; b overlaps both — three lanes.
        #expect(placements.count == 3)
        #expect(placements.allSatisfy { $0.laneCount == 3 })
        #expect(placements.map(\.lane).sorted() == [0, 1, 2])
    }

    @Test("a gap between overlaps closes the group")
    func lanesSeparateGroups() {
        let placements = CalendarGridLayout.timedLanes(
            [
                Self.event(
                    id: "a",
                    start: Self.day(6, 15, hour: 9),
                    end: Self.day(6, 15, hour: 10)
                ),
                Self.event(
                    id: "b",
                    start: Self.day(6, 15, hour: 9, minute: 30),
                    end: Self.day(6, 15, hour: 10, minute: 30)
                ),
                // Starts after every open lane ended — new group.
                Self.event(
                    id: "c",
                    start: Self.day(6, 15, hour: 12),
                    end: Self.day(6, 15, hour: 13)
                ),
            ],
            onDay: Self.day(6, 15),
            calendar: Self.utc
        )
        #expect(placements.map(\.laneCount) == [2, 2, 1])
        #expect(placements.map(\.lane) == [0, 1, 0])
    }

    @Test("a spanning event clips to the day boundary")
    func lanesClipToDay() {
        let placements = CalendarGridLayout.timedLanes(
            [
                Self.event(
                    id: "span",
                    start: Self.day(6, 14, hour: 22),
                    end: Self.day(6, 15, hour: 10)
                ),
            ],
            onDay: Self.day(6, 15),
            calendar: Self.utc
        )
        #expect(placements.count == 1)
        #expect(placements[0].startMinute == 0)
        #expect(placements[0].durationMinutes == 600)
    }

    // MARK: - Range titles

    @Test("range titles render per mode")
    func rangeTitles() {
        let day = Self.day(9, 22) // Tuesday, Sep 22 2026
        #expect(
            CalendarGridLayout.dayTitle(for: day, calendar: Self.utc)
                .contains("22")
        )
        #expect(
            CalendarGridLayout.monthTitle(containing: day, calendar: Self.utc)
                .contains("2026")
        )
        let week = CalendarGridLayout.weekTitle(
            containing: day,
            calendar: Self.utc
        )
        #expect(week.contains("21") && week.contains("27"))
    }
}
