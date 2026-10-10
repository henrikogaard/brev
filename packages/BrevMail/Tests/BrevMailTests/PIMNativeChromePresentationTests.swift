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
import BrevSettings
import Foundation
import Testing

/// Presentation contracts for the iOS PIM covers (audit findings P1-P4):
/// the empty-state Settings destination, month-cell and event accessibility
/// text, calendar navigation labels and task row accessibility.
///
/// Runtime lookups assert English: CI copies the string catalog without
/// compiling it, so plural and `nb` forms are checked in the catalog source.
@Suite("PIM native chrome presentation")
struct PIMNativeChromePresentationTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 2
        return calendar
    }

    /// 2026-10-14 (a Wednesday) at 09:00 UTC.
    private static let day = calendar.date(
        from: DateComponents(year: 2026, month: 10, day: 14, hour: 9)
    )!

    private static func event(
        _ id: String,
        _ summary: String?,
        hour: Int = 9,
        minutes: Int = 60,
        isAllDay: Bool = false,
        location: String? = nil
    ) -> PIMEvent {
        let start = calendar.date(
            from: DateComponents(year: 2026, month: 10, day: 14, hour: hour)
        )!
        return PIMEvent(
            id: id,
            sourceID: "s1",
            collectionID: "c1",
            providerItemKey: id,
            summary: summary,
            location: location,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            isAllDay: isAllDay,
            syncedAt: start
        )
    }

    private static func task(
        due: Date? = nil,
        status: PIMTaskStatus = .needsAction,
        title: String? = "Buy milk",
        notes: String? = nil
    ) -> PIMTask {
        PIMTask(
            id: "t1",
            sourceID: "s1",
            collectionID: "c1",
            providerItemKey: "t1",
            title: title,
            notes: notes,
            due: due,
            status: status
        )
    }

    // MARK: Empty states (P1)

    @Test("every PIM empty state opens Calendar & Contacts settings")
    func emptyStateDestination() {
        #expect(PIMNoSourcesPresentation.settingsSection == .calendarContacts)
    }

    @Test("empty-state copy names the Settings path for the layout", arguments: PIMNoSourcesPresentation.Kind.allCases)
    func emptyStateCopyNamesPath(kind: PIMNoSourcesPresentation.Kind) {
        let phone = PIMNoSourcesPresentation.copy(for: kind, usesCategorySettings: false)
        let pad = PIMNoSourcesPresentation.copy(for: kind, usesCategorySettings: true)

        #expect(phone.message.contains("Settings → Calendar & Contacts"))
        #expect(!phone.message.contains("Accounts & Connections"))
        #expect(pad.message.contains("Settings → Accounts & Connections → Calendar & Contacts"))
        #expect(phone.actionTitle == "Open Calendar & Contacts Settings")
        #expect(phone.title == pad.title)
    }

    // MARK: Calendar navigation (P2)

    @Test("previous and next labels name the step for each layout")
    func navigationLabels() {
        #expect(CalendarNavigationPresentation.previousLabel(for: .day) == "Previous Day")
        #expect(CalendarNavigationPresentation.previousLabel(for: .week) == "Previous Week")
        #expect(CalendarNavigationPresentation.previousLabel(for: .month) == "Previous Month")
        #expect(CalendarNavigationPresentation.nextLabel(for: .day) == "Next Day")
        #expect(CalendarNavigationPresentation.nextLabel(for: .week) == "Next Week")
        #expect(CalendarNavigationPresentation.nextLabel(for: .month) == "Next Month")
        #expect(CalendarNavigationPresentation.previousLabel(for: .agenda) == "Previous")
        #expect(CalendarNavigationPresentation.nextLabel(for: .agenda) == "Next")
    }

    @Test("the minimum control size meets the 44 pt touch target")
    func minimumControlSize() {
        #expect(CalendarNavigationPresentation.minimumControlSize >= 44)
    }

    // MARK: Month cells (P3)

    @Test("a month cell label names the day, the event count and the titles")
    func monthCellLabelListsEvents() {
        let events = [
            Self.event("e1", "Standup"),
            Self.event("e2", "Review", hour: 11),
            Self.event("e3", "Lunch", hour: 12)
        ]
        let label = CalendarMonthCellPresentation.accessibilityLabel(
            day: Self.day, events: events, isToday: false, calendar: Self.calendar
        )
        #expect(label == "Wednesday, October 14, 3 events: Standup, Review, Lunch")
    }

    @Test("a month cell label reaches events beyond the visible titles")
    func monthCellLabelCountsOverflow() {
        let events = (1 ... 5).map { Self.event("e\($0)", "Event \($0)", hour: 8 + $0) }
        let label = CalendarMonthCellPresentation.accessibilityLabel(
            day: Self.day, events: events, isToday: false, calendar: Self.calendar
        )
        #expect(label == "Wednesday, October 14, 5 events: Event 1, Event 2, Event 3, +2 more")
    }

    @Test("a month cell label says so for a day without events and for today")
    func monthCellLabelEmptyAndToday() {
        let empty = CalendarMonthCellPresentation.accessibilityLabel(
            day: Self.day, events: [], isToday: false, calendar: Self.calendar
        )
        let today = CalendarMonthCellPresentation.accessibilityLabel(
            day: Self.day, events: [], isToday: true, calendar: Self.calendar
        )
        #expect(empty == "Wednesday, October 14, No events")
        #expect(today == "Today, Wednesday, October 14, No events")
    }

    @Test("untitled events read as the placeholder title in a month cell")
    func monthCellLabelUntitled() {
        let label = CalendarMonthCellPresentation.accessibilityLabel(
            day: Self.day,
            events: [Self.event("e1", nil), Self.event("e2", "Standup")],
            isToday: false,
            calendar: Self.calendar
        )
        #expect(label.hasSuffix("(No title), Standup"))
    }

    @Test("a month cell shows at most three dots and flags the overflow")
    func monthCellDots() {
        #expect(CalendarMonthCellPresentation.dotCount(forEventCount: 0) == 0)
        #expect(CalendarMonthCellPresentation.dotCount(forEventCount: 2) == 2)
        #expect(CalendarMonthCellPresentation.dotCount(forEventCount: 9) == 3)
        #expect(!CalendarMonthCellPresentation.hasOverflow(eventCount: 3))
        #expect(CalendarMonthCellPresentation.hasOverflow(eventCount: 4))
    }

    @Test("an event count is plural in the catalog for en and nb")
    func eventCountPlural() throws {
        for language in ["en", "nb"] {
            let forms = try LocalizationCatalogTestSupport.pluralForms(key: "%lld events", language: language)
            #expect(forms["one"]?.contains("%lld") == true)
            #expect(forms["other"]?.contains("%lld") == true)
        }
        #expect(CalendarMonthCellPresentation.eventCountText(3) == "3 events")
    }

    // MARK: Event blocks (P3)

    @Test("an event block label carries the title and the time range")
    func eventBlockLabel() {
        let event = Self.event("e1", "Standup", hour: 9, minutes: 30)
        let label = CalendarEventPresentation.accessibilityLabel(for: event, calendar: Self.calendar)
        let time = CalendarEventPresentation.agendaTimeText(for: event, calendar: Self.calendar)
        #expect(label == "Standup, \(time)")
    }

    @Test("an all-day event label says all day and keeps the location")
    func eventBlockLabelAllDayWithLocation() {
        let label = CalendarEventPresentation.accessibilityLabel(
            for: Self.event("e1", "Offsite", isAllDay: true, location: "Oslo"),
            calendar: Self.calendar
        )
        #expect(label == "Offsite, All day, Oslo")
    }

    // MARK: Tasks (P4)

    @Test("the completion toggle is labelled Completed and reads No while the task is open")
    func taskToggleOpen() {
        #expect(TaskRowPresentation.toggleLabel() == "Completed")
        #expect(TaskRowPresentation.toggleValue(for: Self.task()) == "No")
    }

    @Test("a completed task row toggle reads Yes")
    func taskToggleCompleted() {
        #expect(TaskRowPresentation.toggleValue(for: Self.task(status: .completed)) == "Yes")
    }

    @Test("overdue is a word, not only a colour, and never applies to completed tasks")
    func overdueIsText() {
        let now = Self.day
        let yesterday = now.addingTimeInterval(-86400)
        #expect(TaskRowPresentation.isOverdue(Self.task(due: yesterday), now: now))
        #expect(!TaskRowPresentation.isOverdue(Self.task(due: yesterday, status: .completed), now: now))
        #expect(!TaskRowPresentation.isOverdue(Self.task(due: now.addingTimeInterval(3600)), now: now))
        #expect(!TaskRowPresentation.isOverdue(Self.task(), now: now))
        #expect(TaskRowPresentation.overdueText() == "Overdue")
    }

    @Test("the row label joins title, notes, due date and overdue")
    func rowLabel() {
        let now = Self.day
        let yesterday = now.addingTimeInterval(-86400)
        let label = TaskRowPresentation.rowLabel(
            for: Self.task(due: yesterday, notes: "2 litres"),
            now: now,
            calendar: Self.calendar
        )
        #expect(label.hasPrefix("Buy milk, 2 litres, Due "))
        #expect(label.hasSuffix(", Overdue"))
    }

    @Test("a bare task row label is the title, and an untitled one the placeholder")
    func rowLabelBare() {
        let now = Self.day
        #expect(TaskRowPresentation.rowLabel(for: Self.task(), now: now, calendar: Self.calendar) == "Buy milk")
        #expect(
            TaskRowPresentation.rowLabel(for: Self.task(title: nil), now: now, calendar: Self.calendar)
                == "Untitled task"
        )
    }

    // MARK: Catalog

    @Test("new PIM chrome strings carry a Norwegian translation")
    func newStringsAreTranslated() throws {
        let strings = try LocalizationCatalogTestSupport.loadCatalogStrings()
        let keys = [
            "Open Calendar & Contacts Settings",
            "Connect a calendar in Settings → Accounts & Connections → Calendar & Contacts to see events here.",
            "Connect a contacts source in Settings → Accounts & Connections → Calendar & Contacts to see people here.",
            "Connect a tasks source in Settings → Accounts & Connections → Calendar & Contacts to see tasks here.",
            "Previous Day", "Previous Week", "Previous Month",
            "Next Day", "Next Week", "Next Month",
            "No", "Overdue", "Due %@",
            "Delete this task?"
        ]
        for key in keys {
            let entry = strings[key] as? [String: Any]
            let localizations = entry?["localizations"] as? [String: Any]
            let nb = (localizations?["nb"] as? [String: Any])?["stringUnit"] as? [String: Any]
            #expect((nb?["value"] as? String)?.isEmpty == false, "missing nb for \(key)")
        }
    }
}
