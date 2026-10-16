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

/// Coverage for ADR-0089 bounded occurrence projection: the strict
/// validator, wall-clock generation across DST, defensive limits,
/// exception markers, and legacy-cache degradation.
@Suite("PIM occurrence projection")
struct PIMOccurrenceProjectionTests {
    private static let oslo = TimeZone(identifier: "Europe/Oslo")!

    private static func zoneDate(
        _ zone: TimeZone,
        _ value: String,
        dateOnly: Bool = false
    ) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = dateOnly ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    private static func utc(_ value: String) -> Date {
        zoneDate(TimeZone(identifier: "UTC")!, value)
    }

    private static func interval(
        _ start: String,
        _ end: String
    ) -> DateInterval {
        DateInterval(start: utc(start), end: utc(end))
    }

    /// A master record carrying a lossless descriptor; `start`/`end`
    /// are stored instants, `zoneID` becomes the zoned basis.
    private static func master(
        id: String = "m1",
        rrule: String = "FREQ=DAILY;COUNT=5",
        startBasis: PIMRecurrenceDescriptor.StartBasis,
        start: Date?,
        end: Date? = nil,
        isAllDay: Bool = false,
        status: PIMEventStatus = .confirmed,
        rdate: Bool = false,
        exdate: Bool = false,
        unrecognized: Bool = false,
        version: Int = PIMRecurrenceDescriptor.currentVersion
    ) -> PIMEvent {
        PIMEvent(
            id: id,
            sourceID: "s1",
            collectionID: "c1",
            providerItemKey: "item-\(id)",
            uid: "uid-\(id)",
            summary: id,
            start: start,
            end: end,
            isAllDay: isAllDay,
            status: status,
            recurrenceRule: ICSParser.parseRecurrenceRule(rrule),
            syncedAt: utc("2026-10-01 00:00"),
            recurrenceDescriptor: PIMRecurrenceDescriptor(
                version: version,
                rrules: [rrule],
                hasRDate: rdate,
                hasExDate: exdate,
                hasUnrecognizedEntries: unrecognized,
                startBasis: startBasis
            )
        )
    }

    private static func plainEvent(
        id: String,
        start: Date? = nil,
        end: Date? = nil
    ) -> PIMEvent {
        PIMEvent(
            id: id,
            sourceID: "s1",
            collectionID: "c1",
            providerItemKey: "item-\(id)",
            summary: id,
            start: start,
            end: end,
            syncedAt: utc("2026-10-01 00:00")
        )
    }

    private static func projectedStarts(
        _ projection: PIMOccurrenceProjection
    ) -> [Date] {
        projection.occurrences.compactMap(\.start)
    }

    // MARK: - Daily series (the reported defect)

    @Test("a daily COUNT=5 Oslo series projects every day")
    func dailyCount5() {
        let start = Self.zoneDate(Self.oslo, "2026-10-16 09:00")
        let event = Self.master(
            startBasis: .zoned("Europe/Oslo"),
            start: start,
            end: Self.zoneDate(Self.oslo, "2026-10-16 10:00")
        )
        let projection = PIMOccurrenceProjector.project(
            [event],
            in: Self.interval("2026-10-16 00:00", "2026-10-23 00:00")
        )
        #expect(projection.incompleteSeries.isEmpty)
        let expected = (16 ... 20).map {
            Self.zoneDate(Self.oslo, "2026-10-\($0) 09:00")
        }
        #expect(Self.projectedStarts(projection) == expected)
        #expect(
            projection.occurrences.map(\.occurrenceIndex) == [0, 1, 2, 3, 4]
        )
        #expect(
            projection.occurrences[2].end
                == Self.zoneDate(Self.oslo, "2026-10-18 10:00")
        )
        #expect(projection.occurrences.allSatisfy { $0.event == event })
    }

    @Test("occurrence IDs are stable across projections and intervals")
    func occurrenceIDStability() {
        let event = Self.master(
            startBasis: .zoned("Europe/Oslo"),
            start: Self.zoneDate(Self.oslo, "2026-10-16 09:00")
        )
        let first = PIMOccurrenceProjector.project(
            [event],
            in: Self.interval("2026-10-16 00:00", "2026-10-23 00:00")
        )
        let second = PIMOccurrenceProjector.project(
            [event],
            in: Self.interval("2026-10-16 00:00", "2026-10-23 00:00")
        )
        #expect(
            first.occurrences.map(\.id) == second.occurrences.map(\.id)
        )
        // A narrower interval containing the same occurrence keeps the ID.
        let narrow = PIMOccurrenceProjector.project(
            [event],
            in: Self.interval("2026-10-18 00:00", "2026-10-19 00:00")
        )
        #expect(narrow.occurrences.count == 1)
        #expect(narrow.occurrences[0].id == first.occurrences[2].id)
        let ids = Set(first.occurrences.map(\.id))
        #expect(ids.count == 5)
        #expect(!ids.contains(event.id))
    }

    // MARK: - DST and wall-clock rules

    @Test("a weekly Oslo series keeps 09:00 local across the DST change")
    func weeklyAcrossDST() {
        // 2026-10-19 and 2026-10-26 straddle the Oct 25 fall-back.
        let event = Self.master(
            rrule: "FREQ=WEEKLY;COUNT=4",
            startBasis: .zoned("Europe/Oslo"),
            start: Self.zoneDate(Self.oslo, "2026-10-19 09:00")
        )
        let projection = PIMOccurrenceProjector.project(
            [event],
            in: Self.interval("2026-10-19 00:00", "2026-11-16 00:00")
        )
        #expect(projection.incompleteSeries.isEmpty)
        var osloCalendar = Calendar(identifier: .gregorian)
        osloCalendar.timeZone = Self.oslo
        #expect(
            projection.occurrences.allSatisfy {
                osloCalendar.component(.hour, from: $0.start!) == 9
                    && osloCalendar.component(.minute, from: $0.start!) == 0
            }
        )
        #expect(Self.projectedStarts(projection).count == 4)
    }

    @Test("a nonexistent local time is skipped without consuming COUNT")
    func nonexistentLocalTimeSkipped() {
        // Oslo springs forward 2026-03-29: 02:30 does not exist.
        let event = Self.master(
            rrule: "FREQ=DAILY;COUNT=3",
            startBasis: .zoned("Europe/Oslo"),
            start: Self.zoneDate(Self.oslo, "2026-03-28 02:30")
        )
        let projection = PIMOccurrenceProjector.project(
            [event],
            in: Self.interval("2026-03-28 00:00", "2026-04-02 00:00")
        )
        #expect(projection.incompleteSeries.isEmpty)
        #expect(
            Self.projectedStarts(projection) == [
                Self.zoneDate(Self.oslo, "2026-03-28 02:30"),
                Self.zoneDate(Self.oslo, "2026-03-30 02:30"),
                Self.zoneDate(Self.oslo, "2026-03-31 02:30"),
            ]
        )
    }

    @Test("an ambiguous local time resolves to the earlier instant")
    func ambiguousLocalTime() {
        // Oslo falls back 2026-10-25: 02:30 occurs twice; the first is
        // 00:30 UTC (still CEST).
        // The stored start is the first of the two ambiguous instants,
        // matching `repeatedTimePolicy: .first` resolution.
        let event = Self.master(
            rrule: "FREQ=DAILY;COUNT=1",
            startBasis: .zoned("Europe/Oslo"),
            start: Self.utc("2026-10-25 00:30")
        )
        let projection = PIMOccurrenceProjector.project(
            [event],
            in: Self.interval("2026-10-24 00:00", "2026-10-27 00:00")
        )
        #expect(projection.incompleteSeries.isEmpty)
        #expect(Self.projectedStarts(projection) == [Self.utc("2026-10-25 00:30")])
    }

    @Test("monthly from Jan 31 skips invalid days without consuming COUNT")
    func monthlySkipsInvalid() {
        let event = Self.master(
            rrule: "FREQ=MONTHLY;COUNT=4",
            startBasis: .utc,
            start: Self.utc("2026-01-31 09:00")
        )
        let projection = PIMOccurrenceProjector.project(
            [event],
            in: Self.interval("2026-01-01 00:00", "2026-12-31 00:00")
        )
        #expect(projection.incompleteSeries.isEmpty)
        #expect(
            Self.projectedStarts(projection) == [
                Self.utc("2026-01-31 09:00"),
                Self.utc("2026-03-31 09:00"),
                Self.utc("2026-05-31 09:00"),
                Self.utc("2026-07-31 09:00"),
            ]
        )
    }

    @Test("yearly Feb 29 skips non-leap years")
    func yearlyLeapDay() {
        let event = Self.master(
            rrule: "FREQ=YEARLY;COUNT=2",
            startBasis: .utc,
            start: Self.utc("2024-02-29 09:00")
        )
        // Each window stays inside the 366-day request bound; the
        // skipped 2025–2027 slots must not consume COUNT.
        let first = PIMOccurrenceProjector.project(
            [event],
            in: Self.interval("2024-01-01 00:00", "2024-12-31 00:00")
        )
        #expect(Self.projectedStarts(first) == [
            Self.utc("2024-02-29 09:00")
        ])
        let second = PIMOccurrenceProjector.project(
            [event],
            in: Self.interval("2028-01-01 00:00", "2029-01-01 00:00")
        )
        #expect(Self.projectedStarts(second) == [
            Self.utc("2028-02-29 09:00")
        ])
        // Indices are ordinal positions — skipped leap years don't count.
        #expect(second.occurrences[0].occurrenceIndex == 1)
    }

    @Test("date-only series keep UTC-midnight starts and the day span")
    func dateOnlySeries() {
        let event = Self.master(
            rrule: "FREQ=DAILY;COUNT=3",
            startBasis: .dateOnly,
            start: Self.utc("2026-10-16 00:00"),
            end: Self.utc("2026-10-17 00:00"),
            isAllDay: true
        )
        let projection = PIMOccurrenceProjector.project(
            [event],
            in: Self.interval("2026-10-16 00:00", "2026-10-23 00:00")
        )
        #expect(projection.incompleteSeries.isEmpty)
        #expect(
            Self.projectedStarts(projection) == [
                Self.utc("2026-10-16 00:00"),
                Self.utc("2026-10-17 00:00"),
                Self.utc("2026-10-18 00:00"),
            ]
        )
        #expect(
            projection.occurrences.map(\.end) == [
                Self.utc("2026-10-17 00:00"),
                Self.utc("2026-10-18 00:00"),
                Self.utc("2026-10-19 00:00"),
            ]
        )
    }

    @Test("UNTIL is inclusive of the matching occurrence")
    func untilInclusive() {
        let event = Self.master(
            rrule: "FREQ=DAILY;UNTIL=20261018T070000Z",
            startBasis: .zoned("Europe/Oslo"),
            start: Self.zoneDate(Self.oslo, "2026-10-16 09:00")
        )
        // 09:00 Oslo on Oct 18 is 07:00 UTC — the third occurrence.
        let projection = PIMOccurrenceProjector.project(
            [event],
            in: Self.interval("2026-10-16 00:00", "2026-10-30 00:00")
        )
        #expect(projection.incompleteSeries.isEmpty)
        #expect(Self.projectedStarts(projection).count == 3)
    }

    @Test("weekly INTERVAL=2 BYDAY=MO,WE anchored at WKST=MO")
    func weeklyIntervalByday() {
        // 2026-10-16 is a Friday — wait, spec test wants BYDAY=MO,WE.
        // DTSTART must be inside the BYDAY set: Monday 2026-10-12.
        let event = Self.master(
            rrule: "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;WKST=MO;COUNT=4",
            startBasis: .zoned("Europe/Oslo"),
            start: Self.zoneDate(Self.oslo, "2026-10-12 09:00")
        )
        let projection = PIMOccurrenceProjector.project(
            [event],
            in: Self.interval("2026-10-12 00:00", "2026-11-09 00:00")
        )
        #expect(projection.incompleteSeries.isEmpty)
        #expect(
            Self.projectedStarts(projection) == [
                Self.zoneDate(Self.oslo, "2026-10-12 09:00"),
                Self.zoneDate(Self.oslo, "2026-10-14 09:00"),
                Self.zoneDate(Self.oslo, "2026-10-26 09:00"),
                Self.zoneDate(Self.oslo, "2026-10-28 09:00"),
            ]
        )
    }

    // MARK: - Validator: every unsupported reason

    private static func reason(
        for event: PIMEvent
    ) -> PIMRecurrenceUnsupportedReason? {
        guard case .failure(let reason) = PIMRecurrenceValidator
            .validate(event)
        else { return nil }
        return reason
    }

    @Test("each unsupported shape fails with its specific reason")
    func unsupportedReasons() {
        let start = Self.zoneDate(Self.oslo, "2026-10-16 09:00")
        func event(
            _ rrule: String,
            basis: PIMRecurrenceDescriptor.StartBasis = .zoned(
                "Europe/Oslo"
            ),
            start: Date? = start,
            rdate: Bool = false,
            exdate: Bool = false,
            unrecognized: Bool = false,
            version: Int = PIMRecurrenceDescriptor.currentVersion
        ) -> PIMEvent {
            Self.master(
                rrule: rrule,
                startBasis: basis,
                start: start,
                rdate: rdate,
                exdate: exdate,
                unrecognized: unrecognized,
                version: version
            )
        }

        // Legacy cache record: summary rule only, no descriptor.
        let legacy = PIMEvent(
            id: "legacy",
            sourceID: "s1",
            collectionID: "c1",
            providerItemKey: "legacy",
            start: start,
            recurrenceRule: ICSParser.parseRecurrenceRule(
                "FREQ=DAILY;COUNT=5"
            )
        )
        #expect(Self.reason(for: legacy) == .missingDescriptor)

        #expect(
            Self.reason(for: event("FREQ=DAILY", version: 2))
                == .unsupportedDescriptorVersion(2)
        )
        #expect(
            Self.reason(for: event("FREQ=DAILY", rdate: true))
                == .rdatePresent
        )
        #expect(
            Self.reason(for: event("FREQ=DAILY", exdate: true))
                == .exdatePresent
        )
        #expect(
            Self.reason(for: event("FREQ=DAILY", unrecognized: true))
                == .unrecognizedRecurrenceEntries
        )
        var twoRules = event("FREQ=DAILY")
        twoRules.recurrenceDescriptor?.rrules = [
            "FREQ=DAILY", "FREQ=WEEKLY",
        ]
        #expect(Self.reason(for: twoRules) == .multipleRecurrenceRules)
        #expect(
            Self.reason(for: event("FREQ=DAILY;COUNT=2;COUNT=3"))
                == .duplicateRulePart("COUNT")
        )
        #expect(
            Self.reason(for: event("FREQ=DAILY;BYMONTHDAY=1"))
                == .unknownRulePart("BYMONTHDAY")
        )
        #expect(
            Self.reason(for: event("FREQ=DAILY;INTERVAL"))
                == .malformedRulePart("INTERVAL")
        )
        #expect(
            Self.reason(for: event("FREQ=HOURLY"))
                == .unsupportedFrequency("HOURLY")
        )
        #expect(
            Self.reason(for: event("FREQ=DAILY;INTERVAL=0"))
                == .invalidInterval("0")
        )
        #expect(
            Self.reason(for: event("FREQ=DAILY;COUNT=0"))
                == .invalidCount("0")
        )
        #expect(
            Self.reason(
                for: event(
                    "FREQ=DAILY;COUNT=3;UNTIL=20261020T070000Z"
                )
            ) == .countAndUntilCombined
        )
        #expect(
            Self.reason(for: event("FREQ=DAILY;UNTIL=2026-10-20"))
                == .untilFormMismatch
        )
        // Date-only basis requires the date-only UNTIL form.
        #expect(
            Self.reason(
                for: event(
                    "FREQ=DAILY;UNTIL=20261020T000000Z",
                    basis: .dateOnly,
                    start: Self.utc("2026-10-16 00:00")
                )
            ) == .untilFormMismatch
        )
        #expect(
            Self.reason(
                for: event(
                    "FREQ=DAILY;UNTIL=20261020",
                    basis: .dateOnly,
                    start: Self.utc("2026-10-16 00:00")
                )
            ) == nil
        )
        #expect(
            Self.reason(for: event("FREQ=DAILY;UNTIL=20261340T070000Z"))
                == .malformedUntil("20261340T070000Z")
        )
        #expect(
            Self.reason(for: event("FREQ=DAILY;BYDAY=MO"))
                == .byDayOutsideWeekly
        )
        #expect(
            Self.reason(for: event("FREQ=WEEKLY;BYDAY=2MO"))
                == .ordinalByDay("2MO")
        )
        #expect(
            Self.reason(for: event("FREQ=WEEKLY;BYDAY=XX"))
                == .malformedByDay("XX")
        )
        #expect(
            Self.reason(for: event("FREQ=WEEKLY;BYDAY=MO;WKST=ZZ"))
                == .malformedWkst("ZZ")
        )
        #expect(
            Self.reason(for: event("FREQ=DAILY", basis: .floating))
                == .unsupportedStartBasis
        )
        #expect(
            Self.reason(for: event("FREQ=DAILY", basis: .unknown))
                == .unsupportedStartBasis
        )
        #expect(
            Self.reason(
                for: event("FREQ=DAILY", basis: .zoned("Mars/Olympus"))
            ) == .unresolvableTimeZone("Mars/Olympus")
        )
        #expect(
            Self.reason(for: event("FREQ=DAILY", start: nil))
                == .missingStart
        )
        // DTSTART Friday does not fit a Monday-only pattern.
        #expect(
            Self.reason(for: event("FREQ=WEEKLY;BYDAY=WE"))
                == .startNotInPattern
        )
    }

    // MARK: - Defensive limits

    @Test("an interval beyond 366 days marks every series incomplete")
    func intervalLimit() {
        let event = Self.master(
            startBasis: .zoned("Europe/Oslo"),
            start: Self.zoneDate(Self.oslo, "2026-10-16 09:00")
        )
        let plain = Self.plainEvent(
            id: "plain",
            start: Self.utc("2026-11-01 10:00")
        )
        let other = Self.master(
            id: "m2",
            rrule: "FREQ=WEEKLY;COUNT=4",
            startBasis: .utc,
            start: Self.utc("2026-10-17 09:00")
        )
        let projection = PIMOccurrenceProjector.project(
            [event, other, plain],
            in: Self.interval("2026-10-01 00:00", "2027-11-01 00:00")
        )
        #expect(
            projection.incompleteSeries.map(\.reason)
                == [.limitReached, .limitReached]
        )
        // Masters render as raw rows; the plain event still renders.
        #expect(
            projection.occurrences.map(\.id) == ["m1", "m2", "plain"]
        )
        #expect(
            projection.occurrences.allSatisfy { $0.occurrenceIndex == nil }
        )
    }

    @Test("a COUNT beyond the candidate bound reports limitReached")
    func candidateLimit() {
        let event = Self.master(
            rrule: "FREQ=DAILY;COUNT=20000",
            startBasis: .utc,
            start: Self.utc("1990-01-01 09:00")
        )
        let projection = PIMOccurrenceProjector.project(
            [event],
            in: Self.interval("2026-10-01 00:00", "2026-11-01 00:00")
        )
        #expect(
            projection.incompleteSeries.map(\.reason) == [.limitReached]
        )
        // No partial generated rows; the 1990 master point does not
        // overlap the 2026 window, so no raw row is emitted either.
        #expect(projection.occurrences.isEmpty)
    }

    @Test("an open-ended series from 2000 completes via fast-forward")
    func openEndedFastForward() {
        let event = Self.master(
            rrule: "FREQ=DAILY",
            startBasis: .utc,
            start: Self.utc("2000-01-01 09:00")
        )
        let projection = PIMOccurrenceProjector.project(
            [event],
            in: Self.interval("2026-10-16 00:00", "2026-10-19 00:00")
        )
        #expect(projection.incompleteSeries.isEmpty)
        #expect(
            Self.projectedStarts(projection) == [
                Self.utc("2026-10-16 09:00"),
                Self.utc("2026-10-17 09:00"),
                Self.utc("2026-10-18 09:00"),
            ]
        )
    }

    // MARK: - Exceptions and cancelled markers

    @Test("a DAV exception record flags the series and renders raw rows")
    func davExceptionSeries() {
        let start = Self.zoneDate(Self.oslo, "2026-10-16 09:00")
        let event = Self.master(
            startBasis: .zoned("Europe/Oslo"),
            start: start
        )
        let exception = PIMEvent(
            id: "exc1",
            sourceID: "s1",
            collectionID: "c1",
            providerItemKey: "item-m1", // same href as the master
            uid: "uid-m1",
            summary: "Moved",
            start: Self.zoneDate(Self.oslo, "2026-10-17 15:00"),
            recurrenceID: Self.zoneDate(Self.oslo, "2026-10-17 09:00")
        )
        let projection = PIMOccurrenceProjector.project(
            [event, exception],
            in: Self.interval("2026-10-16 00:00", "2026-10-23 00:00")
        )
        #expect(
            projection.incompleteSeries.map(\.reason) == [.exceptions]
        )
        // Master raw row + exception raw row; no generated occurrences.
        #expect(
            projection.occurrences.map(\.id).sorted() == ["exc1", "m1"]
        )
        #expect(
            projection.occurrences.allSatisfy { !($0.isProjected) }
        )
    }

    @Test("a Google cancelled instance is a marker, never a row")
    func googleCancelledMarker() {
        let event = Self.master(
            startBasis: .zoned("Europe/Oslo"),
            start: Self.zoneDate(Self.oslo, "2026-10-16 09:00")
        )
        let marker = PIMEvent(
            id: "inst2",
            sourceID: "s1",
            collectionID: "c1",
            providerItemKey: "inst2",
            uid: "uid-m1",
            status: .cancelled,
            recurrenceID: Self.zoneDate(Self.oslo, "2026-10-18 09:00"),
            seriesMasterItemKey: "item-m1"
        )
        let projection = PIMOccurrenceProjector.project(
            [event, marker],
            in: Self.interval("2026-10-16 00:00", "2026-10-23 00:00")
        )
        #expect(
            projection.incompleteSeries.map(\.reason) == [.exceptions]
        )
        #expect(!projection.occurrences.contains { $0.id == "inst2" })
        #expect(projection.occurrences.map(\.id) == ["m1"])
    }

    @Test("a legacy record without a descriptor renders raw and reports")
    func legacyRecord() {
        let legacy = PIMEvent(
            id: "legacy",
            sourceID: "s1",
            collectionID: "c1",
            providerItemKey: "legacy",
            summary: "Legacy",
            start: Self.utc("2026-10-18 09:00"),
            recurrenceRule: ICSParser.parseRecurrenceRule(
                "FREQ=DAILY;COUNT=5"
            )
        )
        let projection = PIMOccurrenceProjector.project(
            [legacy],
            in: Self.interval("2026-10-16 00:00", "2026-10-23 00:00")
        )
        #expect(
            projection.incompleteSeries.map(\.reason)
                == [.missingDescriptor]
        )
        #expect(projection.occurrences.map(\.id) == ["legacy"])
    }

    @Test("pre-ADR-0089 cached JSON decodes without the new keys")
    func oldJSONDecodes() throws {
        let json = """
        {"id":"e1","sourceID":"s1","collectionID":"c1",
         "providerItemKey":"e1","isAllDay":false,"status":"confirmed",
         "attendees":[],"reminders":[],"attachments":[],
         "syncedAt":"2026-10-01T00:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(
            PIMEvent.self,
            from: Data(json.utf8)
        )
        #expect(event.recurrenceDescriptor == nil)
        #expect(event.seriesMasterItemKey == nil)
        #expect(event.id == "e1")
    }

    @Test("undated records always render, sorted last")
    func undatedRows() {
        let dated = Self.plainEvent(id: "dated", start: Self.utc("2026-10-17 09:00"))
        let undated = Self.plainEvent(id: "undated")
        let projection = PIMOccurrenceProjector.project(
            [undated, dated],
            in: Self.interval("2026-10-16 00:00", "2026-10-23 00:00")
        )
        #expect(projection.occurrences.map(\.id) == ["dated", "undated"])
    }

    @Test("a zero-length event at the interval start is included")
    func zeroLengthAtStart() {
        let event = Self.plainEvent(id: "point", start: Self.utc("2026-10-16 00:00"))
        let projection = PIMOccurrenceProjector.project(
            [event],
            in: Self.interval("2026-10-16 00:00", "2026-10-17 00:00")
        )
        #expect(projection.occurrences.map(\.id) == ["point"])
    }
}

extension PIMOccurrenceProjectionTests {
    @Test("weekly BYDAY starting mid-pattern keeps ordinal indices")
    func weeklyMidPatternIndices() {
        // DTSTART Wednesday 2026-10-14; BYDAY=MO,WE skips the Monday
        // slot in the first week, yet the master itself is index 0 —
        // otherwise gating would read the first date as a later one.
        let event = Self.master(
            rrule: "FREQ=WEEKLY;COUNT=4;BYDAY=MO,WE;WKST=MO",
            startBasis: .utc,
            start: Self.utc("2026-10-14 09:00"),
            end: Self.utc("2026-10-14 10:00")
        )
        let projection = PIMOccurrenceProjector.project(
            [event],
            in: Self.interval("2026-10-01 00:00", "2026-10-31 00:00")
        )
        #expect(projection.occurrences.count == 4)
        #expect(
            projection.occurrences.map(\.occurrenceIndex)
                == [0, 1, 2, 3]
        )
        #expect(projection.occurrences[0].start == event.start)
    }

    @Test("skipped monthly dates do not skew ordinal indices")
    func monthlySkippedIndices() {
        // Jan 31 + COUNT=3 skips invalid Feb 30 / Apr 31 dates; indices
        // stay ordinal 0,1,2 rather than period numbers.
        let event = Self.master(
            rrule: "FREQ=MONTHLY;COUNT=3",
            startBasis: .utc,
            start: Self.utc("2026-01-31 09:00"),
            end: Self.utc("2026-01-31 10:00")
        )
        let projection = PIMOccurrenceProjector.project(
            [event],
            in: Self.interval("2026-01-01 00:00", "2026-08-01 00:00")
        )
        #expect(
            Self.projectedStarts(projection) == [
                Self.utc("2026-01-31 09:00"),
                Self.utc("2026-03-31 09:00"),
                Self.utc("2026-05-31 09:00"),
            ]
        )
        #expect(
            projection.occurrences.map(\.occurrenceIndex) == [0, 1, 2]
        )
    }
}
