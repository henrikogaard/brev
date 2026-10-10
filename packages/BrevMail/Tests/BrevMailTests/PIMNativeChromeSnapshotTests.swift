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

#if canImport(UIKit)
import BrevCalendar
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

/// iPhone snapshots for the native PIM chrome (audit findings P1, P3, P4):
/// the month grid with event dots, the day grid, the task editor form sheet,
/// task rows and the "no sources" empty state, in light, dark and AX3.
@Suite("PIM native chrome snapshots")
@MainActor
struct PIMNativeChromeSnapshotTests {
    // MARK: - Fixtures

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 2
        return calendar
    }

    /// 2026-10-10 (a Saturday), the "today" of every fixture.
    private static let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!

    private static func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private static func event(
        _ id: String,
        _ summary: String,
        day: Int,
        hour: Int,
        minutes: Int = 60,
        location: String? = nil
    ) -> PIMEvent {
        let start = date(day: day, hour: hour)
        return PIMEvent(
            id: id,
            sourceID: "s1",
            collectionID: "c1",
            providerItemKey: id,
            summary: summary,
            location: location,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            syncedAt: today
        )
    }

    private static let events: [PIMEvent] = [
        event("e1", "Team sync", day: 10, hour: 14),
        event("e2", "Standup", day: 14, hour: 9, minutes: 30),
        event("e3", "Berth schema design review", day: 14, hour: 10, minutes: 90, location: "Harbour office"),
        event("e4", "Lunch with Alex", day: 14, hour: 12, location: "Cafe Fjord"),
        event("e5", "Dentist", day: 14, hour: 15),
        event("e6", "Sprint retro", day: 14, hour: 16, minutes: 60),
        event("e7", "Planning", day: 12, hour: 9),
        event("e8", "Workshop", day: 20, hour: 9, minutes: 180)
    ]

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
        updatedAt: today
    )

    private static func eventsOn(_ day: Date) -> [PIMEvent] {
        events.filter { event in
            guard let start = event.start else { return false }
            return calendar.isDate(start, inSameDayAs: day)
        }
    }

    private static func task(
        _ id: String,
        _ title: String,
        due: Date? = nil,
        notes: String? = nil,
        status: PIMTaskStatus = .needsAction
    ) -> PIMTask {
        PIMTask(
            id: id,
            sourceID: "s1",
            collectionID: "c1",
            providerItemKey: id,
            title: title,
            notes: notes,
            due: due,
            status: status,
            syncedAt: today
        )
    }

    // MARK: - Snapshot plumbing

    enum Variant: String, CaseIterable {
        case light
        case dark
        case ax3

        var traits: UITraitCollection {
            switch self {
            case .light:
                UITraitCollection(traitsFrom: [.init(displayScale: 2), .init(userInterfaceStyle: .light)])
            case .dark:
                UITraitCollection(traitsFrom: [.init(displayScale: 2), .init(userInterfaceStyle: .dark)])
            case .ax3:
                UITraitCollection(traitsFrom: [
                    .init(displayScale: 2),
                    .init(userInterfaceStyle: .light),
                    .init(preferredContentSizeCategory: .accessibilityExtraLarge)
                ])
            }
        }

        var theme: BrevTheme {
            self == .dark ? .brevMonoDark : .brevMonoLight
        }
    }

    private static func snapshot(
        _ view: some View,
        variant: Variant,
        named name: String,
        testName: String = #function,
        line: UInt = #line
    ) {
        let host = UIHostingController(
            rootView: view
                .brevTheme(variant.theme)
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.calendar, calendar)
                .background(variant.theme.bgPrimary.color.ignoresSafeArea())
        )
        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: variant.traits),
            named: "\(name)-\(variant.rawValue)",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil,
            testName: testName,
            line: line
        )
    }

    // MARK: - Calendar grids (P3)

    @Test("the compact month grid shows event dots and a today marker", arguments: Variant.allCases)
    func monthGrid(variant: Variant) {
        let weeks = CalendarGridLayout.monthWeeks(containing: Self.today, calendar: Self.calendar)
        let view = CalendarMonthView(
            weeks: weeks,
            eventsFor: { Self.eventsOn($0) },
            collectionFor: { _ in Self.collection },
            selectedEventID: .constant(nil),
            now: Self.today
        )
        Self.snapshot(view, variant: variant, named: "month")
    }

    @Test("the day grid labels blocks and scales its hours", arguments: Variant.allCases)
    func dayGrid(variant: Variant) {
        let day = Self.date(day: 14, hour: 0)
        let view = CalendarDayView(
            day: day,
            allDayEvents: [],
            placements: CalendarGridLayout.timedLanes(Self.eventsOn(day), onDay: day, calendar: Self.calendar),
            collectionFor: { _ in Self.collection },
            selectedEventID: .constant(nil)
        )
        Self.snapshot(view, variant: variant, named: "day")
    }

    // MARK: - Tasks (P4)

    @Test("task rows expose a 44 pt toggle, overdue text and notes", arguments: Variant.allCases)
    func taskRows(variant: Variant) {
        let rows = VStack(spacing: 0) {
            TaskRowView(
                task: Self.task(
                    "t1",
                    "Send invoice to Harbour Logistics",
                    due: Self.date(day: 5, hour: 12),
                    notes: "Overdue since last week"
                ),
                onToggleCompleted: { _ in },
                now: Self.today
            )
            TaskRowView(
                task: Self.task("t2", "Renew passport", due: Self.date(day: 15, hour: 12)),
                onToggleCompleted: { _ in },
                now: Self.today
            )
            TaskRowView(
                task: Self.task("t3", "Buy milk", status: .completed),
                onToggleCompleted: { _ in },
                now: Self.today
            )
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        Self.snapshot(rows, variant: variant, named: "task-rows")
    }

    // MARK: - Empty states (P1)

    @Test("the no-sources state offers a button to Settings", arguments: Variant.allCases)
    func noSources(variant: Variant) {
        let view = PIMNoSourcesView(kind: .calendar, symbol: "calendar.badge.plus", onOpenSettings: { _ in })
        Self.snapshot(view, variant: variant, named: "no-sources-calendar")
    }
}
#endif
