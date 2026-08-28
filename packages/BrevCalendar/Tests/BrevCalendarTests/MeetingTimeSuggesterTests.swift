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

@Suite("MeetingTimeSuggester")
struct MeetingTimeSuggesterTests {
    // A fixed reference: 2026-06-15 14:00:00 UTC.
    private let base = Date(timeIntervalSince1970: 1_781_532_000)

    @Test("slices a window into aligned, duration-long slots, earliest first")
    func slicesWindow() {
        let window = MeetingAvailabilityWindow(start: base, end: base.addingTimeInterval(3600))
        let slots = MeetingTimeSuggester.suggest(
            availability: [window], duration: 1800, maxSuggestions: 5, granularity: 1800
        )
        #expect(slots.count == 2)
        #expect(slots[0].start == base)
        #expect(slots[0].end == base.addingTimeInterval(1800))
        #expect(slots[1].start == base.addingTimeInterval(1800))
    }

    @Test("respects maxSuggestions across multiple windows")
    func capsSuggestions() {
        let windows = [
            MeetingAvailabilityWindow(start: base, end: base.addingTimeInterval(7200)),
            MeetingAvailabilityWindow(
                start: base.addingTimeInterval(86400),
                end: base.addingTimeInterval(86400 + 3600)
            )
        ]
        let slots = MeetingTimeSuggester.suggest(
            availability: windows, duration: 1800, maxSuggestions: 3
        )
        #expect(slots.count == 3)
        // All three come from the first (earlier) window before the next day.
        #expect(slots.allSatisfy { $0.start < windows[1].start })
    }

    @Test("a window shorter than the duration yields nothing")
    func tooShort() {
        let window = MeetingAvailabilityWindow(start: base, end: base.addingTimeInterval(600))
        #expect(MeetingTimeSuggester.suggest(availability: [window], duration: 1800).isEmpty)
    }

    @Test("invalid inputs return no suggestions")
    func invalidInputs() {
        let window = MeetingAvailabilityWindow(start: base, end: base.addingTimeInterval(3600))
        #expect(MeetingTimeSuggester.suggest(availability: [window], duration: 0).isEmpty)
        #expect(MeetingTimeSuggester.suggest(availability: [window], duration: 1800, maxSuggestions: 0).isEmpty)
        #expect(MeetingTimeSuggester.suggest(availability: [], duration: 1800).isEmpty)
    }

    @Test("formats slots as a readable bulleted list")
    func formatsList() {
        let slots = [MeetingTimeSlot(start: base, end: base.addingTimeInterval(1800))]
        let text = MeetingTimeSuggester.format(slots, timeZone: TimeZone(identifier: "UTC")!)
        #expect(text == "- Monday, June 15 at 2:00 PM – 2:30 PM")
    }
}
