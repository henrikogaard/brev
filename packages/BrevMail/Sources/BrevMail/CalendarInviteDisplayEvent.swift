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

import BrevBackend
import BrevCalendar
import Foundation

enum CalendarInviteDisplayEvent {
    static func makeCalendarEvent(from parsed: ICSParser.ParsedEvent) -> CalendarEvent? {
        guard let start = parsed.start else { return nil }
        return CalendarEvent(
            id: parsed.uid ?? "local-calendar-invite-\(start.timeIntervalSince1970)",
            title: parsed.summary?.isEmpty == false ? parsed.summary! : "Calendar invite",
            start: start,
            end: parsed.end ?? start,
            isAllDay: parsed.isAllDay,
            location: parsed.location,
            organizer: parsed.organizer.map(makeCorrespondent),
            attendees: parsed.attendees.map(makeCorrespondent),
            description: parsed.description
        )
    }

    private static func makeCorrespondent(_ person: ICSParser.ParsedPerson) -> Correspondent {
        Correspondent(name: person.name, email: person.email)
    }
}
