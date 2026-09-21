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

/// Snapshot coverage for the Calendar grid layouts (ADR-0072 #6).
/// Set RECORD_SNAPSHOTS=YES to record or refresh the baselines.
@Suite("Calendar grid snapshots")
@MainActor
struct CalendarGridSnapshotTests {
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// 2026-09-21 is a Monday — a clean anchor for week/month fixtures.
    private static let monday = Date(timeIntervalSince1970: 1_790_265_600)

    private static func event(
        id: String,
        summary: String,
        hour: Int,
        minute: Int = 0,
        durationMinutes: Int = 60,
        isAllDay: Bool = false,
        status: PIMEventStatus = .confirmed
    ) -> PIMEvent {
        let start = utc.date(
            from: DateComponents(
                year: 2026, month: 9, day: 21, hour: hour, minute: minute
            )
        )!
        return PIMEvent(
            id: id,
            sourceID: "s1",
            collectionID: "c1",
            providerItemKey: id,
            summary: summary,
            start: start,
            end: isAllDay
                ? start.addingTimeInterval(86400)
                : start.addingTimeInterval(
                    TimeInterval(durationMinutes * 60)
                ),
            isAllDay: isAllDay,
            status: status,
            syncedAt: monday
        )
    }

    private static let collection = PIMCollection(
        id: "c1",
        sourceID: "s1",
        kind: .calendar,
        displayName: "Work",
        colorHex: "#4A7FB5",
        isReadOnly: false,
        isPrimary: true,
        supportsSyncToken: true,
        providerKey: "c1",
        providerVersion: nil,
        isVisible: true,
        updatedAt: monday
    )

    @Test("the day column renders lanes and the hour ruler",
          arguments: ["light", "dark"])
    func dayColumn(mode: String) {
        let day = Self.monday
        let events = [
            Self.event(id: "e1", summary: "Standup", hour: 9,
                       durationMinutes: 30),
            Self.event(id: "e2", summary: "Design review", hour: 10,
                       durationMinutes: 90),
            Self.event(id: "e3", summary: "Overlap", hour: 10,
                       minute: 30, durationMinutes: 60),
        ]
        let placements = CalendarGridLayout.timedLanes(
            events,
            onDay: day,
            calendar: Self.utc
        )

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let view = CalendarDayColumn(
            placements: placements,
            collectionFor: { _ in Self.collection },
            selectedEventID: .constant("e2"),
            hourHeight: 40,
            showsHourLabels: true
        )
        .frame(width: 420)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.calendar, Self.utc)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 420, height: 960)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 420, height: 960)),
            named: "dayColumn-\(mode)",
            record: ProcessInfo.processInfo
                .environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("the month grid renders day cells with chips and overflow",
          arguments: ["light", "dark"])
    func monthGrid(mode: String) {
        let weeks = CalendarGridLayout.monthWeeks(
            containing: Self.monday,
            calendar: Self.utc
        )
        let events: [PIMEvent] = [
            Self.event(id: "e1", summary: "Standup", hour: 9),
            Self.event(id: "e2", summary: "Review", hour: 11),
            Self.event(id: "e3", summary: "Lunch", hour: 12),
            Self.event(id: "e4", summary: "Extra", hour: 14),
        ]

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let view = CalendarMonthView(
            weeks: weeks,
            eventsFor: { day in
                CalendarGridLayout.events(
                    events,
                    onDay: day,
                    calendar: Self.utc
                )
            },
            collectionFor: { _ in Self.collection },
            selectedEventID: .constant(nil),
            onSelectDay: { _ in },
            now: Self.monday
        )
        .frame(width: 720, height: 560)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.calendar, Self.utc)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 720, height: 560)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 720, height: 560)),
            named: "month-\(mode)",
            record: ProcessInfo.processInfo
                .environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
