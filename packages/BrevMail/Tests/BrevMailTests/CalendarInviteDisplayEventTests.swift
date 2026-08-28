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

@Suite("CalendarInviteDisplayEvent")
struct CalendarInviteDisplayEventTests {
    @Test("client parsed invites use the backend calendar event display model")
    func clientParsedInvitesUseBackendCalendarEventDisplayModel() throws {
        let parsed = try #require(ICSParser.parseFirstEvent(from: Self.invite))

        let event = try #require(CalendarInviteDisplayEvent.makeCalendarEvent(from: parsed))

        #expect(event.id == "event-1")
        #expect(event.title == "Product review")
        #expect(event.location == "Room 4")
        #expect(event.organizer?.email == "alex@example.org")
        #expect(event.attendees.map(\.email) == ["henrik@example.org"])
    }

    private static let invite = """
    BEGIN:VCALENDAR
    VERSION:2.0
    BEGIN:VEVENT
    UID:event-1
    DTSTART:20260601T120000Z
    DTEND:20260601T130000Z
    SUMMARY:Product review
    LOCATION:Room 4
    ORGANIZER;CN=Alex:mailto:alex@example.org
    ATTENDEE;CN=Henrik:mailto:henrik@example.org
    END:VEVENT
    END:VCALENDAR
    """
}
