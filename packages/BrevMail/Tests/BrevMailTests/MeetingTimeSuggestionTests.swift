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

@Suite("Meeting time suggestions")
struct MeetingTimeSuggestionTests {
    @Test("suggestions respect working hours, timezone, and enabled availability sources")
    func suggestionsRespectWorkingHoursTimezoneAndEnabledSources() throws {
        let timezone = try #require(TimeZone(identifier: "Europe/Oslo"))
        let settings = MeetingTimeSuggestionSettings(
            isEnabled: true,
            workingDays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            workdayStartMinute: 9 * 60,
            workdayEndMinute: 17 * 60,
            timeZoneIdentifier: timezone.identifier,
            enabledAvailabilitySourceIDs: ["local-calendar"]
        )
        let now = try Self.date("2026-06-05T08:00:00+02:00")
        let busy = try [
            MeetingBusyInterval(
                sourceID: "local-calendar",
                start: Self.date("2026-06-05T09:00:00+02:00"),
                end: Self.date("2026-06-05T10:00:00+02:00")
            ),
            MeetingBusyInterval(
                sourceID: "disabled-calendar",
                start: Self.date("2026-06-05T10:00:00+02:00"),
                end: Self.date("2026-06-05T11:00:00+02:00")
            )
        ]

        let result = MeetingTimeSuggestionPolicy.suggestions(
            settings: settings,
            busyIntervals: busy,
            now: now,
            durationMinutes: 30,
            count: 3
        )

        let slots = try #require(result.slots)
        #expect(slots.map { Self.localHourMinute($0.start, timeZone: timezone) } == ["10:00", "10:30", "11:00"])
        #expect(result.requiresExternalCall == false)
    }

    @Test("suggestions require explicit availability source opt-in")
    func suggestionsRequireExplicitAvailabilitySourceOptIn() throws {
        let settings = MeetingTimeSuggestionSettings(
            isEnabled: true,
            workingDays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            workdayStartMinute: 9 * 60,
            workdayEndMinute: 17 * 60,
            timeZoneIdentifier: "Europe/Oslo",
            enabledAvailabilitySourceIDs: []
        )

        let result = try MeetingTimeSuggestionPolicy.suggestions(
            settings: settings,
            busyIntervals: [],
            now: Self.date("2026-06-05T08:00:00+02:00"),
            durationMinutes: 30,
            count: 3
        )

        #expect(result.slots == nil)
        #expect(result.unavailableReason == .noAvailabilitySourcesEnabled)
        #expect(result.requiresExternalCall == false)
    }

    @Test("invalid timezone and invalid working hours are graceful unavailable states")
    func invalidTimezoneAndWorkingHoursAreUnavailableStates() throws {
        var settings = MeetingTimeSuggestionSettings(
            isEnabled: true,
            workingDays: [.monday],
            workdayStartMinute: 9 * 60,
            workdayEndMinute: 17 * 60,
            timeZoneIdentifier: "Mars/Olympus",
            enabledAvailabilitySourceIDs: ["local-calendar"]
        )

        var result = try MeetingTimeSuggestionPolicy.suggestions(
            settings: settings,
            busyIntervals: [],
            now: Self.date("2026-06-05T08:00:00+02:00"),
            durationMinutes: 30,
            count: 3
        )

        #expect(result.unavailableReason == .invalidTimeZone)

        settings.timeZoneIdentifier = "Europe/Oslo"
        settings.workdayStartMinute = 17 * 60
        settings.workdayEndMinute = 9 * 60

        result = try MeetingTimeSuggestionPolicy.suggestions(
            settings: settings,
            busyIntervals: [],
            now: Self.date("2026-06-05T08:00:00+02:00"),
            durationMinutes: 30,
            count: 3
        )

        #expect(result.unavailableReason == .invalidWorkingHours)
    }

    @Test("draft insertion appends editable text and does not request send")
    func draftInsertionAppendsEditableTextAndDoesNotRequestSend() throws {
        let timezone = try #require(TimeZone(identifier: "Europe/Oslo"))
        let slots = try [
            MeetingTimeSuggestionSlot(
                start: Self.date("2026-06-05T10:00:00+02:00"),
                end: Self.date("2026-06-05T10:30:00+02:00")
            ),
            MeetingTimeSuggestionSlot(
                start: Self.date("2026-06-05T10:30:00+02:00"),
                end: Self.date("2026-06-05T11:00:00+02:00")
            )
        ]
        let text = MeetingTimeSuggestionFormatter.editableText(
            for: slots,
            timeZone: timezone
        )

        let insertion = MeetingTimeSuggestionInsertion.insert(
            text,
            into: "Hi Ada,",
            selection: nil,
            insertionPoint: nil
        )

        #expect(insertion
            .body ==
            "Hi Ada,\n\nHere are a few times that work for me:\n- Fri, Jun 5, 10:00-10:30 Europe/Oslo\n- Fri, Jun 5, 10:30-11:00 Europe/Oslo")
        #expect(insertion.shouldSend == false)
        #expect(insertion.isEditable)
    }

    private static func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try #require(formatter.date(from: value))
    }

    private static func localHourMinute(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}
