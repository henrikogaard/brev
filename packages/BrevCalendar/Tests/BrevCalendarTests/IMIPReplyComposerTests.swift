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

@Suite("IMIPReplyComposer")
struct IMIPReplyComposerTests {
    @Test("creates an accepted METHOD REPLY with event identity and attendee status")
    func createsAcceptedMethodReplyWithEventIdentityAndAttendeeStatus() throws {
        let event = try #require(ICSParser.parseFirstEvent(from: """
        BEGIN:VCALENDAR
        VERSION:2.0
        METHOD:REQUEST
        BEGIN:VEVENT
        UID:event-123
        SUMMARY:Roadmap review
        DTSTART:20260601T120000Z
        DTEND:20260601T130000Z
        ORGANIZER;CN=Henrik Øgård:mailto:henrik@example.com
        ATTENDEE;CN=Alex Berg:mailto:alex@example.com
        END:VEVENT
        END:VCALENDAR
        """))

        let reply = try IMIPReplyComposer.compose(
            event: event,
            attendee: ICSParser.ParsedPerson(name: "Alex Berg", email: "alex@example.com"),
            status: .accepted,
            now: Self.utcDate(year: 2026, month: 5, day: 29, hour: 10)
        )

        #expect(reply.subject == "Accepted: Roadmap review")
        #expect(reply.plainTextBody.contains("accepted"))
        #expect(reply.ics.contains("\r\nMETHOD:REPLY\r\n"))
        #expect(reply.ics.contains("\r\nUID:event-123\r\n"))
        #expect(reply.ics.contains("\r\nDTSTAMP:20260529T100000Z\r\n"))
        #expect(reply.ics.contains("\r\nDTSTART:20260601T120000Z\r\n"))
        #expect(reply.ics.contains("\r\nDTEND:20260601T130000Z\r\n"))
        #expect(reply.ics.contains("\r\nSUMMARY:Roadmap review\r\n"))
        #expect(reply.ics.contains("\r\nORGANIZER;CN=\"Henrik Øgård\":mailto:henrik@example.com\r\n"))
        #expect(reply.ics.contains(
            "\r\nATTENDEE;CN=\"Alex Berg\";PARTSTAT=ACCEPTED;RSVP=FALSE:mailto:alex@example.com\r\n"
        ))
    }

    @Test("a malicious attendee email cannot inject ICS properties")
    func maliciousAttendeeEmailCannotInjectICSProperties() throws {
        let event = try #require(ICSParser.parseFirstEvent(from: """
        BEGIN:VCALENDAR
        VERSION:2.0
        METHOD:REQUEST
        BEGIN:VEVENT
        UID:event-1
        SUMMARY:Sync
        DTSTART:20260601T120000Z
        DTEND:20260601T130000Z
        ORGANIZER;CN=Org:mailto:org@example.com
        ATTENDEE;CN=Me:mailto:me@example.com
        END:VEVENT
        END:VCALENDAR
        """))

        let reply = try IMIPReplyComposer.compose(
            event: event,
            attendee: ICSParser.ParsedPerson(
                name: "Me",
                email: "me@example.com\r\nX-EVIL:injected;PARTSTAT=DECLINED"
            ),
            status: .accepted,
            now: Self.utcDate(year: 2026, month: 5, day: 29, hour: 10)
        )

        // The CR/LF, `:` and `;` are stripped from the address, so no new
        // property line or `X-EVIL:` property can be injected.
        #expect(!reply.ics.contains("\r\nX-EVIL"))
        #expect(!reply.ics.contains("X-EVIL:"))
    }

    @Test("maps maybe and decline replies to tentative and declined partstats")
    func mapsMaybeAndDeclineRepliesToTentativeAndDeclinedPartstats() throws {
        let event = ICSParser.ParsedEvent(
            uid: "event-456",
            summary: "Design critique",
            description: nil,
            location: nil,
            start: Self.utcDate(year: 2026, month: 6, day: 3, hour: 8),
            end: nil,
            isAllDay: false,
            organizer: nil,
            attendees: []
        )
        let attendee = ICSParser.ParsedPerson(name: nil, email: "alex@example.com")

        let maybe = try IMIPReplyComposer.compose(
            event: event,
            attendee: attendee,
            status: .tentative,
            now: Self.utcDate(year: 2026, month: 5, day: 29, hour: 10)
        )
        let decline = try IMIPReplyComposer.compose(
            event: event,
            attendee: attendee,
            status: .declined,
            now: Self.utcDate(year: 2026, month: 5, day: 29, hour: 10)
        )

        #expect(maybe.subject == "Maybe: Design critique")
        #expect(maybe.ics.contains("PARTSTAT=TENTATIVE"))
        #expect(decline.subject == "Declined: Design critique")
        #expect(decline.ics.contains("PARTSTAT=DECLINED"))
    }

    @Test("preserves all-day event dates in reply payload")
    func preservesAllDayEventDatesInReplyPayload() throws {
        let event = ICSParser.ParsedEvent(
            uid: "event-day",
            summary: "Company holiday",
            description: nil,
            location: nil,
            start: Self.utcDate(year: 2026, month: 12, day: 24),
            end: Self.utcDate(year: 2026, month: 12, day: 25),
            isAllDay: true,
            organizer: nil,
            attendees: []
        )

        let reply = try IMIPReplyComposer.compose(
            event: event,
            attendee: ICSParser.ParsedPerson(name: "Alex", email: "alex@example.com"),
            status: .accepted,
            now: Self.utcDate(year: 2026, month: 5, day: 29, hour: 10)
        )

        #expect(reply.ics.contains("\r\nDTSTART;VALUE=DATE:20261224\r\n"))
        #expect(reply.ics.contains("\r\nDTEND;VALUE=DATE:20261225\r\n"))
    }

    @Test("escapes text values and throws when the invite has no UID")
    func escapesTextValuesAndThrowsWhenInviteHasNoUID() throws {
        let event = ICSParser.ParsedEvent(
            uid: "event-special",
            summary: "Review, launch; notes",
            description: nil,
            location: nil,
            start: nil,
            end: nil,
            isAllDay: false,
            organizer: nil,
            attendees: []
        )
        let reply = try IMIPReplyComposer.compose(
            event: event,
            attendee: ICSParser.ParsedPerson(name: "Alex \"A\"", email: "alex@example.com"),
            status: .accepted,
            now: Self.utcDate(year: 2026, month: 5, day: 29, hour: 10)
        )

        #expect(reply.ics.contains("\r\nSUMMARY:Review\\, launch\\; notes\r\n"))
        #expect(reply.ics.contains("ATTENDEE;CN=\"Alex \\\"A\\\"\";PARTSTAT=ACCEPTED"))

        let missingUID = ICSParser.ParsedEvent(
            uid: nil,
            summary: "Untitled",
            description: nil,
            location: nil,
            start: nil,
            end: nil,
            isAllDay: false,
            organizer: nil,
            attendees: []
        )

        #expect(throws: IMIPReplyComposer.ComposeError.missingUID) {
            _ = try IMIPReplyComposer.compose(
                event: missingUID,
                attendee: ICSParser.ParsedPerson(name: nil, email: "alex@example.com"),
                status: .accepted,
                now: Self.utcDate(year: 2026, month: 5, day: 29, hour: 10)
            )
        }
    }

    private static func utcDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0
    ) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: year,
            month: month,
            day: day,
            hour: hour
        ).date!
    }
}
