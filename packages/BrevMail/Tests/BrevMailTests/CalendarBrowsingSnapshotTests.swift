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

#if os(macOS)
import AppKit
import BrevCalendar
@testable import BrevMail
import BrevThemes
import Foundation
import SnapshotTesting
import SwiftUI
import Testing

/// Snapshot coverage for the Calendar browsing surface (ADR-0072 #6).
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh the baselines.
@Suite("Calendar browsing snapshots")
@MainActor
struct CalendarBrowsingSnapshotTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func event(
        id: String,
        summary: String?,
        startOffset: TimeInterval = 0,
        isAllDay: Bool = false,
        location: String? = nil,
        status: PIMEventStatus = .confirmed,
        attendees: [PIMEventPerson] = [],
        conferenceURL: String? = nil
    ) -> PIMEvent {
        PIMEvent(
            id: id,
            sourceID: "s1",
            collectionID: "c1",
            providerItemKey: id,
            summary: summary,
            location: location,
            start: start.addingTimeInterval(startOffset),
            end: start.addingTimeInterval(startOffset + 3600),
            isAllDay: isAllDay,
            status: status,
            attendees: attendees,
            conferenceURL: conferenceURL,
            syncedAt: start
        )
    }

    @Test("agenda rows render time, title, and status", arguments: ["light", "dark"])
    func agendaRow(mode: String) {
        // Rows render standalone — List cells never materialize inside a
        // bare NSHostingController, so the suite snapshots the row view
        // the List reuses (same convention as MessageListRowSnapshotTests).
        let rows = VStack(alignment: .leading, spacing: 0) {
            CalendarEventRowView(
                event: Self.event(
                    id: "e1",
                    summary: "Design review",
                    location: "Oslo office",
                    conferenceURL: "https://meet.example.com/x"
                )
            )
            CalendarEventRowView(
                event: Self.event(
                    id: "e2",
                    summary: "Cancelled sync",
                    startOffset: 7200,
                    status: .cancelled
                )
            )
        }

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let view = rows
            .frame(width: 360, height: 200)
            .brevTheme(theme)
            .environment(\.colorScheme, theme.mode.colorScheme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 360, height: 200)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 360, height: 200)),
            named: "agenda-\(mode)",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("event detail renders all fields", arguments: ["light", "dark"])
    func eventDetail(mode: String) {
        var event = Self.event(
            id: "e1",
            summary: "Quarterly planning",
            location: "Meeting room 3",
            attendees: [
                PIMEventPerson(
                    name: "Ada",
                    email: "ada@example.com",
                    rsvp: .accepted
                ),
                PIMEventPerson(
                    name: "Bo",
                    email: "bo@example.com",
                    rsvp: .tentative
                ),
            ],
            conferenceURL: "https://meet.example.com/planning"
        )
        event.eventDescription = "Quarterly planning session."
        event.reminders = [PIMEventReminder(minutesBefore: 15)]
        event.organizer = PIMEventPerson(
            name: "Carol",
            email: "carol@example.com"
        )

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let view = CalendarEventDetailView(event: event)
            .frame(width: 420, height: 560)
            .brevTheme(theme)
            .environment(\.colorScheme, theme.mode.colorScheme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 420, height: 560)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 420, height: 560)),
            named: "detail-\(mode)",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
