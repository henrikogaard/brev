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

@Suite("ScheduleSendDateResolver")
struct ScheduleSendDateResolverTests {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private static let mondayMorningUTC: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 8
        components.hour = 9
        components.minute = 0
        return utc.date(from: components) ?? Date(timeIntervalSince1970: 1_750_000_000)
    }()

    @Test("send now resolves to nil")
    func sendNowResolvesToNil() {
        #expect(ScheduleSendDateResolver.date(for: .sendNow, now: Date()) == nil)
        #expect(ScheduleSendDateResolver.date(for: .custom, now: Date()) == nil)
    }

    @Test("in one hour adds exactly sixty minutes")
    func inOneHourAddsSixtyMinutes() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = ScheduleSendDateResolver.date(for: .inOneHour, now: now)
        #expect(result == now.addingTimeInterval(60 * 60))
    }

    @Test("tonight eight returns later of today 8pm or tomorrow 8pm")
    func tonightEightRespectsTimeOfDay() {
        let morning = Self.utc.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 8))!
        let morningResult = ScheduleSendDateResolver.date(for: .tonightEight, now: morning, calendar: Self.utc)
        #expect(morningResult == Self.utc.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 20, minute: 0)))

        let lateEvening = Self.utc.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 22))!
        let lateResult = ScheduleSendDateResolver.date(for: .tonightEight, now: lateEvening, calendar: Self.utc)
        #expect(lateResult == Self.utc.date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 20, minute: 0)))
    }

    @Test("tomorrow nine returns next day 9am")
    func tomorrowNineReturnsNextDayNineAM() {
        let now = Self.utc.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 15))!
        let result = ScheduleSendDateResolver.date(for: .tomorrowNine, now: now, calendar: Self.utc)
        #expect(result == Self.utc.date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 9, minute: 0)))
    }

    @Test("next Monday from a Sunday lands on the upcoming Monday")
    func nextMondayFromSunday() {
        let sunday = Self.utc.date(from: DateComponents(year: 2026, month: 6, day: 7, hour: 12))!
        let result = ScheduleSendDateResolver.date(for: .nextMonday, now: sunday, calendar: Self.utc)
        let expected = Self.utc.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 9, minute: 0))
        #expect(result == expected)
    }

    @Test("next Monday from a Monday jumps a full week forward")
    func nextMondayFromMonday() {
        let mondayNoon = Self.utc.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 12))!
        let result = ScheduleSendDateResolver.date(for: .nextMonday, now: mondayNoon, calendar: Self.utc)
        let expected = Self.utc.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9, minute: 0))
        #expect(result == expected)
    }

    @Test("formatted schedule date includes date and time")
    func formattedScheduleDateIncludesDateAndTime() {
        let date = Self.utc.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 9, minute: 0))!
        let formatted = ScheduleSendDateResolver.formattedScheduleDate(date, calendar: Self.utc)
        #expect(!formatted.isEmpty)
        #expect(formatted.contains("8") || formatted.contains("08"))
    }

    @Test("quit warning names the pending scheduled message count")
    func quitWarningNamesPendingCount() {
        #expect(ScheduleSendReliabilityPresentation.quitWarningMessage(pendingCount: 0) == nil)
        let one = ScheduleSendReliabilityPresentation.quitWarningMessage(pendingCount: 1)
        #expect(one?.contains("1 scheduled message ") == true)
        #expect(one?.contains("next opened") == true)
        let many = ScheduleSendReliabilityPresentation.quitWarningMessage(pendingCount: 3)
        #expect(many?.contains("3 scheduled messages ") == true)
    }

    @Test("scheduled send notice surfaces fully quit behavior")
    func scheduledSendNoticeSurfacesFullyQuitBehavior() {
        #expect(ScheduleSendReliabilityPresentation.localDeliveryNotice.contains("fully quit"))
        #expect(ScheduleSendReliabilityPresentation.localDeliveryNotice.contains("next time you open Brev"))
    }
}
