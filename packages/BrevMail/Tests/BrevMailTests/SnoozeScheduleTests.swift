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

@testable import BrevMail
import Foundation
import Testing

@Suite("SnoozeSchedule")
struct SnoozeScheduleTests {
    private static let en = Locale(identifier: "en_US")
    private static let nb = Locale(identifier: "nb_NO")

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private static func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 10, day: day, hour: hour, minute: minute
        )) ?? .distantPast
    }

    // 2026-10-05 is a Monday, so 08 is Thursday, 09 Friday, 10 Saturday, 11 Sunday.
    private func wake(_ option: SnoozeQuickOption, now: Date) -> Date? {
        option.wakeDate(now: now, calendar: Self.calendar)
    }

    @Test("Monday morning offers every option with the expected times")
    func mondayMorningOffersEverything() {
        let now = Self.date(5, 10)
        let suggestions = SnoozeSchedule.suggestions(now: now, calendar: Self.calendar)

        #expect(suggestions.map(\.option) == [
            .laterToday, .thisEvening, .tomorrowMorning, .thisWeekend, .nextWeek
        ])
        #expect(suggestions.map(\.wakeDate) == [
            Self.date(5, 13), Self.date(5, 18), Self.date(6, 9), Self.date(10, 9), Self.date(12, 9)
        ])
    }

    @Test("This evening is offered strictly before 17:00")
    func eveningCutoff() {
        #expect(wake(.thisEvening, now: Self.date(5, 16, 59)) == Self.date(5, 18))
        #expect(wake(.thisEvening, now: Self.date(5, 17)) == nil)
        #expect(wake(.thisEvening, now: Self.date(5, 23)) == nil)
    }

    @Test("This weekend is Saturday 09:00 and only offered Monday to Thursday")
    func weekendWindow() {
        #expect(wake(.thisWeekend, now: Self.date(5, 10)) == Self.date(10, 9))
        #expect(wake(.thisWeekend, now: Self.date(8, 22)) == Self.date(10, 9))
        #expect(wake(.thisWeekend, now: Self.date(9, 10)) == nil)
        #expect(wake(.thisWeekend, now: Self.date(10, 10)) == nil)
        #expect(wake(.thisWeekend, now: Self.date(11, 10)) == nil)
    }

    @Test("Friday evening drops the weekend and a late evening drops this evening")
    func fridayLateShrinksTheList() {
        let suggestions = SnoozeSchedule.suggestions(now: Self.date(9, 20), calendar: Self.calendar)

        #expect(suggestions.map(\.option) == [.laterToday, .tomorrowMorning, .nextWeek])
        #expect(suggestions.map(\.wakeDate) == [
            Self.date(9, 23), Self.date(10, 9), Self.date(16, 9)
        ])
    }

    @Test("Excluding extended options keeps the original three")
    func originalThreeOptions() {
        let suggestions = SnoozeSchedule.suggestions(
            now: Self.date(5, 10),
            calendar: Self.calendar,
            includeExtended: false
        )

        #expect(suggestions.map(\.option) == [.laterToday, .tomorrowMorning, .nextWeek])
    }

    @Test("A custom wake must lie in the future")
    func customWakeValidity() {
        let now = Self.date(5, 10)

        #expect(SnoozeSchedule.isValidCustomWake(Self.date(5, 10, 1), now: now))
        #expect(!SnoozeSchedule.isValidCustomWake(now, now: now))
        #expect(!SnoozeSchedule.isValidCustomWake(Self.date(5, 9), now: now))
    }

    @Test("Compact labels use a relative day, then weekday, then date")
    func compactLabels() {
        let now = Self.date(5, 10)
        func label(_ date: Date, _ locale: Locale = Self.en) -> String {
            SnoozeSchedule.label(
                for: date, now: now, calendar: Self.calendar, locale: locale, style: .compact
            )
        }

        #expect(label(Self.date(5, 18)).hasPrefix("Today"))
        #expect(label(Self.date(5, 18)).contains("6:00"))
        #expect(label(Self.date(6, 9)).hasPrefix("Tomorrow"))
        #expect(label(Self.date(10, 9)).hasPrefix("Sat"))
        #expect(!label(Self.date(10, 9)).contains("Oct"))
        #expect(label(Self.date(12, 9)).contains("Oct"))
        #expect(label(Self.date(12, 9)).contains("12"))
        // The relative words come from the string catalog (app language), not the
        // injected locale; the time and weekday follow the locale.
        #expect(label(Self.date(6, 9), Self.nb).contains("09:00"))
        #expect(label(Self.date(10, 9), Self.nb).contains("09:00"))
    }

    @Test("Spoken labels spell the weekday out")
    func spokenLabels() {
        let now = Self.date(5, 10)
        func label(_ date: Date, _ locale: Locale = Self.en) -> String {
            SnoozeSchedule.label(
                for: date, now: now, calendar: Self.calendar, locale: locale, style: .spoken
            )
        }

        #expect(label(Self.date(5, 18)).hasPrefix("Today"))
        #expect(label(Self.date(6, 9)).hasPrefix("Tuesday"))
        #expect(label(Self.date(10, 9)).hasPrefix("Saturday"))
        #expect(label(Self.date(12, 9)).hasPrefix("Monday"))
        #expect(label(Self.date(12, 9)).contains("October"))
        #expect(label(Self.date(6, 9), Self.nb).lowercased().hasPrefix("tirsdag"))
    }
}
