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

/// Draft mapping coverage for the event editor (ADR-0072 #7):
/// event-to-form round-trips, recurrence mapping, validation, and
/// provider-identity preservation.
@Suite("CalendarEventDraft")
struct CalendarEventDraftTests {
    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private static func event(
        recurrenceRule: ICSParser.RecurrenceRule? = nil
    ) -> PIMEvent {
        PIMEvent(
            id: "e1",
            sourceID: "s1",
            collectionID: "c1",
            providerItemKey: "g-1",
            providerVersion: "\"v3\"",
            uid: "uid-e1@brev",
            summary: "Design review",
            eventDescription: "Bring sketches",
            location: "Oslo",
            start: fixedNow,
            end: fixedNow.addingTimeInterval(3600),
            isAllDay: false,
            timeZoneIdentifier: "Europe/Oslo",
            status: .confirmed,
            organizer: PIMEventPerson(
                name: "Boss",
                email: "boss@example.com",
                rsvp: .accepted
            ),
            attendees: [
                PIMEventPerson(
                    name: "Ana",
                    email: "ana@example.com",
                    rsvp: .accepted
                ),
            ],
            reminders: [PIMEventReminder(minutesBefore: 10, method: .alert)],
            conferenceURL: "https://meet.example.com/x",
            recurrenceRule: recurrenceRule,
            providerUpdatedAt: fixedNow,
            syncedAt: fixedNow
        )
    }

    @Test("init(event:) maps every editable field")
    func initFromEvent() {
        let draft = CalendarEventDraft(event: Self.event())

        #expect(draft.isEditing)
        #expect(draft.summary == "Design review")
        #expect(draft.notes == "Bring sketches")
        #expect(draft.location == "Oslo")
        #expect(draft.timeZoneIdentifier == "Europe/Oslo")
        #expect(draft.reminderMinutes == [10])
        #expect(draft.attendeeEmails == ["ana@example.com"])
        #expect(draft.targetCollectionID == "c1")
        #expect(!draft.repeats)
    }

    @Test("makeEvent preserves provider identity and attendee RSVP")
    func makeEventPreservesIdentity() {
        var draft = CalendarEventDraft(event: Self.event())
        draft.summary = "Renamed"
        draft.attendeeEmails = ["ana@example.com", "new@example.com"]

        let event = draft.makeEvent(sourceID: "s1", collectionID: "c1")

        #expect(event.providerItemKey == "g-1")
        #expect(event.providerVersion == "\"v3\"")
        #expect(event.uid == "uid-e1@brev")
        #expect(event.conferenceURL == "https://meet.example.com/x")
        #expect(event.organizer?.email == "boss@example.com")
        #expect(event.summary == "Renamed")
        #expect(
            event.attendees.first { $0.email == "ana@example.com" }?.rsvp
                == .accepted
        )
        #expect(
            event.attendees.first { $0.email == "new@example.com" }?.rsvp
                == .needsAction
        )
    }

    @Test("makeEvent maps a Meet create intent to a pending conference")
    func makeEventConferenceIntent() {
        var draft = CalendarEventDraft(
            start: Self.fixedNow,
            duration: 3600
        )
        draft.requestsConference = true

        let event = draft.makeEvent(sourceID: "s1", collectionID: "c1")

        #expect(event.conference?.kind == .meet)
        #expect(event.conference?.status == .pending)
        #expect(event.conference?.isCreationRequest == true)
    }

    @Test("init(event:) preserves the synced conference over the intent flag")
    func editPreservesConference() {
        var event = Self.event()
        event.conference = PIMConference(
            kind: .other,
            name: "Zoom",
            joinURL: "https://zoom.us/j/9",
            status: .success
        )
        var draft = CalendarEventDraft(event: event)
        draft.requestsConference = true

        let rebuilt = draft.makeEvent(
            sourceID: "s1",
            collectionID: "c1"
        )

        // The synced conference survives the edit — the intent flag
        // only applies when no conference exists.
        #expect(rebuilt.conference?.joinURL == "https://zoom.us/j/9")
        #expect(rebuilt.conference?.isCreationRequest == false)
    }

    @Test("a create draft produces a record without provider identity")
    func createDraft() {
        var draft = CalendarEventDraft(start: Self.fixedNow)
        draft.summary = "New"
        draft.attendeeEmails = ["  spaced@example.com  ", ""]

        let event = draft.makeEvent(sourceID: "s1", collectionID: "c1")

        #expect(!draft.isEditing)
        #expect(event.providerItemKey == "draft")
        #expect(event.uid == nil)
        #expect(event.attendees.map(\.email) == ["spaced@example.com"])
    }

    @Test("recurrenceRule maps frequency, interval, weekdays, and end")
    func recurrenceMapping() {
        var draft = CalendarEventDraft(start: Self.fixedNow)
        draft.repeatFrequency = .weekly
        draft.repeatInterval = 2
        draft.repeatWeekdays = [.monday, .wednesday]
        draft.repeatEnd = .afterCount
        draft.repeatCount = 6

        let rule = draft.recurrenceRule

        #expect(rule?.frequency == .weekly)
        #expect(rule?.interval == 2)
        #expect(rule?.count == 6)
        #expect(
            Set(rule?.byDay ?? []) == Set([
                ICSParser.Weekday.monday, .wednesday,
            ])
        )
    }

    @Test("init(event:) maps an existing RRULE back into the form")
    func recurrenceRoundTrip() {
        let until = Self.fixedNow.addingTimeInterval(86400 * 30)
        let event = Self.event(
            recurrenceRule: ICSParser.RecurrenceRule(
                frequency: .monthly,
                interval: 3,
                count: nil,
                until: until,
                byDay: nil
            )
        )

        let draft = CalendarEventDraft(event: event)

        #expect(draft.repeatFrequency == .monthly)
        #expect(draft.repeatInterval == 3)
        #expect(draft.repeatEnd == .onDate)
        #expect(draft.repeatUntil == until)
    }

    @Test("isValid requires a title and a sane range")
    func validation() {
        var draft = CalendarEventDraft(start: Self.fixedNow)
        #expect(!draft.isValid)

        draft.summary = "  "
        #expect(!draft.isValid)

        draft.summary = "Ok"
        #expect(draft.isValid)

        draft.end = draft.start.addingTimeInterval(-60)
        #expect(!draft.isValid)
    }
}
