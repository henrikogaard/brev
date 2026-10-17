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

import Foundation

/// Why a recurring series cannot be projected onto occurrence rows
/// (ADR-0089 §2).
///
/// Every unsupported path names the concrete obstacle so the detail
/// surface and diagnostics can distinguish "old cache without lossless
/// metadata" from "rule shape outside the supported subset" from
/// "defensive limits reached during generation".
public enum PIMRecurrenceUnsupportedReason: Error, Sendable, Hashable {
    /// The record has no `recurrenceDescriptor` — a pre-ADR-0089 cache
    /// entry or a record whose adapter captured no recurrence metadata.
    /// The validator never falls back to the lossy `recurrenceRule`.
    case missingDescriptor
    /// The descriptor's schema version differs from `currentVersion`.
    case unsupportedDescriptorVersion(Int)
    /// The descriptor lists zero or more than one RRULE value.
    case multipleRecurrenceRules
    /// An RRULE part key appears twice.
    case duplicateRulePart(String)
    /// An RRULE part key outside the supported subset
    /// (FREQ/INTERVAL/COUNT/UNTIL/BYDAY/WKST) is present.
    case unknownRulePart(String)
    /// An RRULE part lacks the `KEY=VALUE` shape or a required key is
    /// absent.
    case malformedRulePart(String)
    /// FREQ carries a value outside DAILY/WEEKLY/MONTHLY/YEARLY.
    case unsupportedFrequency(String)
    /// INTERVAL is missing a positive integer.
    case invalidInterval(String)
    /// COUNT is missing a positive integer.
    case invalidCount(String)
    /// COUNT and UNTIL appear together.
    case countAndUntilCombined
    /// UNTIL does not parse under its required form.
    case malformedUntil(String)
    /// UNTIL's form does not match the DTSTART basis: date-only series
    /// need `yyyyMMdd`; utc/zoned series need `yyyyMMdd'T'HHmmss'Z'`.
    case untilFormMismatch
    /// BYDAY appears on a non-WEEKLY rule.
    case byDayOutsideWeekly
    /// BYDAY carries an ordinal prefix (e.g. `2MO`), which is outside
    /// the supported subset.
    case ordinalByDay(String)
    /// BYDAY carries a token that is not a weekday code.
    case malformedByDay(String)
    /// WKST carries a token that is not a weekday code.
    case malformedWkst(String)
    /// The record carries RDATE entries.
    case rdatePresent
    /// The record carries EXDATE entries whose values were not captured
    /// (a cache written before exclusions were recorded).
    case exdatePresent
    /// An EXDATE value does not parse under the series' DTSTART basis.
    case malformedExDate(String)
    /// The provider listed recurrence entries other than
    /// RRULE/RDATE/EXDATE (Google `recurrence[]`).
    case unrecognizedRecurrenceEntries
    /// The DTSTART basis is floating or unknown — wall-clock generation
    /// needs an established zone or UTC.
    case unsupportedStartBasis
    /// The named zone cannot be resolved by `TimeZone(identifier:)`.
    case unresolvableTimeZone(String)
    /// The master record has no DTSTART.
    case missingStart
    /// DTSTART's weekday is not in the weekly BYDAY set — the pattern
    /// cannot be anchored faithfully.
    case startNotInPattern
    /// An exception record (moved/cancelled instance) names an original
    /// start that the master pattern never generates, so the series
    /// cannot be reconciled.
    case exceptions
    /// The requested interval or the per-series candidate bound was
    /// exceeded; coverage is intentionally incomplete.
    case limitReached
}

/// The validated, strictly-supported recurrence shape (ADR-0089 §2).
///
/// Only produced by `PIMRecurrenceValidator.validate` — every part was
/// checked against the raw RRULE string, so the projector can generate
/// occurrences without second-guessing dropped parts.
public struct PIMValidatedRecurrence: Sendable, Hashable {
    /// The supported frequency.
    public let frequency: ICSParser.Frequency
    /// Positive step between periods.
    public let interval: Int
    /// Total occurrence count bound, when the rule carries COUNT.
    public let count: Int?
    /// Inclusive last-occurrence bound, when the rule carries UNTIL.
    /// Date-only series hold a UTC-midnight instant; utc/zoned series
    /// hold the parsed UTC instant.
    public let until: Date?
    /// Validated weekly day codes, nil when the rule has no BYDAY.
    public let byDay: [ICSParser.Weekday]?
    /// Week start (WKST), defaulting to Monday.
    public let weekStart: ICSParser.Weekday
    /// The resolved DTSTART basis.
    public let startBasis: PIMRecurrenceDescriptor.StartBasis
    /// The wall-clock generation zone: the named zone for `zoned`,
    /// GMT for `utc` and `dateOnly`.
    public let timeZone: TimeZone
    /// Original-start instants excluded by EXDATE. Excluded slots still
    /// consume COUNT (RFC 5545 §3.8.5.1: exclusion applies after the
    /// rule generates the set).
    public let excludedStarts: Set<Date>

    public init(
        frequency: ICSParser.Frequency,
        interval: Int,
        count: Int?,
        until: Date?,
        byDay: [ICSParser.Weekday]?,
        weekStart: ICSParser.Weekday,
        startBasis: PIMRecurrenceDescriptor.StartBasis,
        timeZone: TimeZone,
        excludedStarts: Set<Date> = []
    ) {
        self.frequency = frequency
        self.interval = interval
        self.count = count
        self.until = until
        self.byDay = byDay
        self.weekStart = weekStart
        self.startBasis = startBasis
        self.timeZone = timeZone
        self.excludedStarts = excludedStarts
    }
}

/// Strict eligibility check for bounded occurrence generation
/// (ADR-0089 §2).
///
/// Reads only `PIMEvent.recurrenceDescriptor` — never the descriptive
/// `recurrenceRule`, so nothing is silently inferred from lossy data.
public enum PIMRecurrenceValidator {
    /// Validates one record's recurrence metadata. Masters, exceptions
    /// and plain events are all valid inputs; only a record with a
    /// descriptor can succeed.
    public static func validate(
        _ event: PIMEvent
    ) -> Result<PIMValidatedRecurrence, PIMRecurrenceUnsupportedReason> {
        guard let descriptor = event.recurrenceDescriptor else {
            return .failure(.missingDescriptor)
        }
        guard descriptor.version
            == PIMRecurrenceDescriptor.currentVersion
        else {
            return .failure(
                .unsupportedDescriptorVersion(descriptor.version)
            )
        }
        if descriptor.hasUnrecognizedEntries {
            return .failure(.unrecognizedRecurrenceEntries)
        }
        if descriptor.hasRDate {
            return .failure(.rdatePresent)
        }
        if descriptor.hasExDate, descriptor.exdates.isEmpty {
            return .failure(.exdatePresent)
        }
        guard descriptor.rrules.count == 1 else {
            return .failure(.multipleRecurrenceRules)
        }

        // Resolve the generation zone before reading the rule: UNTIL's
        // required form depends on the DTSTART basis.
        let zone: TimeZone
        switch descriptor.startBasis {
        case .dateOnly, .utc:
            zone = TimeZone(identifier: "GMT") ?? .gmt
        case .zoned(let identifier):
            guard let resolved = TimeZone(identifier: identifier)
            else {
                return .failure(.unresolvableTimeZone(identifier))
            }
            zone = resolved
        case .floating, .unknown:
            return .failure(.unsupportedStartBasis)
        }
        guard event.start != nil else {
            return .failure(.missingStart)
        }
        var excludedStarts: Set<Date> = []
        for exdate in descriptor.exdates {
            switch parseExDate(exdate, basis: descriptor.startBasis) {
            case .success(let dates):
                excludedStarts.formUnion(dates)
            case .failure(let reason):
                return .failure(reason)
            }
        }

        var frequency: ICSParser.Frequency?
        var interval = 1
        var count: Int?
        var until: Date?
        var byDay: [ICSParser.Weekday]?
        var weekStart = ICSParser.Weekday.monday
        var seen: Set<String> = []

        for part in descriptor.rrules[0].split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else {
                return .failure(.malformedRulePart(String(part)))
            }
            let key = String(pair[0]).uppercased()
            let value = String(pair[1])
            guard seen.insert(key).inserted else {
                return .failure(.duplicateRulePart(key))
            }
            switch key {
            case "FREQ":
                guard let parsed = ICSParser.Frequency(
                    rawValue: value.uppercased()
                ) else {
                    return .failure(.unsupportedFrequency(value))
                }
                frequency = parsed
            case "INTERVAL":
                guard let parsed = Int(value), parsed > 0 else {
                    return .failure(.invalidInterval(value))
                }
                interval = parsed
            case "COUNT":
                guard let parsed = Int(value), parsed > 0 else {
                    return .failure(.invalidCount(value))
                }
                count = parsed
            case "UNTIL":
                switch parseUntil(value, basis: descriptor.startBasis) {
                case .success(let date):
                    until = date
                case .failure(let reason):
                    return .failure(reason)
                }
            case "BYDAY":
                let tokens = value.split(separator: ",")
                guard !tokens.isEmpty else {
                    return .failure(.malformedByDay(value))
                }
                var days: [ICSParser.Weekday] = []
                for token in tokens {
                    let token = String(token)
                    if token.contains(where: { $0.isNumber || "+-".contains($0) }) {
                        return .failure(.ordinalByDay(token))
                    }
                    guard let day = ICSParser.Weekday(
                        rawValue: token.uppercased()
                    ) else {
                        return .failure(.malformedByDay(token))
                    }
                    days.append(day)
                }
                byDay = days
            case "WKST":
                guard let day = ICSParser.Weekday(
                    rawValue: value.uppercased()
                ) else {
                    return .failure(.malformedWkst(value))
                }
                weekStart = day
            default:
                return .failure(.unknownRulePart(key))
            }
        }

        guard let frequency else {
            return .failure(.malformedRulePart("FREQ"))
        }
        if count != nil && until != nil {
            return .failure(.countAndUntilCombined)
        }
        if byDay != nil && frequency != .weekly {
            return .failure(.byDayOutsideWeekly)
        }
        if let byDay, let start = event.start {
            // The pattern must pass through DTSTART: if the master's own
            // weekday is absent from BYDAY the generated series would not
            // contain its stated start.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let weekday = calendar.component(.weekday, from: start)
            guard byDay.contains(Self.weekday(for: weekday)) else {
                return .failure(.startNotInPattern)
            }
        }

        return .success(
            PIMValidatedRecurrence(
                frequency: frequency,
                interval: interval,
                count: count,
                until: until,
                byDay: byDay,
                weekStart: weekStart,
                startBasis: descriptor.startBasis,
                timeZone: zone,
                excludedStarts: excludedStarts
            )
        )
    }

    /// Parses one EXDATE body (`<params>:<values>`) into instants. The
    /// value form must match the series basis: date-only series take
    /// `VALUE=DATE` days; timed series take `Z` instants or a resolvable
    /// `TZID`. Floating values and anything else are malformed.
    private static func parseExDate(
        _ body: String,
        basis: PIMRecurrenceDescriptor.StartBasis
    ) -> Result<Set<Date>, PIMRecurrenceUnsupportedReason> {
        guard let colon = body.firstIndex(of: ":") else {
            return .failure(.malformedExDate(body))
        }
        var params: [String: String] = [:]
        for param in body[..<colon].split(separator: ";") {
            let pair = param.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { return .failure(.malformedExDate(body)) }
            params[String(pair[0]).uppercased()] = String(pair[1])
        }
        let values = body[body.index(after: colon)...].split(separator: ",")
        guard !values.isEmpty else { return .failure(.malformedExDate(body)) }
        let isDateValue = params["VALUE"]?.uppercased() == "DATE"
        var dates: Set<Date> = []
        for raw in values.map(String.init) {
            switch basis {
            case .dateOnly:
                guard isDateValue, raw.count == 8, raw.allSatisfy(\.isNumber),
                      let date = untilDateOnly.date(from: raw)
                else { return .failure(.malformedExDate(body)) }
                dates.insert(date)
            case .utc, .zoned:
                guard !isDateValue else { return .failure(.malformedExDate(body)) }
                if raw.hasSuffix("Z") {
                    guard let date = untilUTC.date(from: raw)
                    else { return .failure(.malformedExDate(body)) }
                    dates.insert(date)
                } else if let tzid = params["TZID"],
                          let zone = TimeZone(identifier: tzid) {
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = zone
                    formatter.dateFormat = "yyyyMMdd'T'HHmmss"
                    guard let date = formatter.date(from: raw)
                    else { return .failure(.malformedExDate(body)) }
                    dates.insert(date)
                } else {
                    return .failure(.malformedExDate(body))
                }
            case .floating, .unknown:
                return .failure(.malformedExDate(body))
            }
        }
        return .success(dates)
    }

    /// Maps a Foundation weekday index (Sunday = 1) onto the RFC 5545
    /// day code.
    static func weekday(for index: Int) -> ICSParser.Weekday {
        switch index {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        default: .saturday
        }
    }

    /// The Foundation weekday index (Sunday = 1) for a day code.
    static func weekdayIndex(_ day: ICSParser.Weekday) -> Int {
        switch day {
        case .sunday: 1
        case .monday: 2
        case .tuesday: 3
        case .wednesday: 4
        case .thursday: 5
        case .friday: 6
        case .saturday: 7
        }
    }

    /// UNTIL is parsed only under the form the DTSTART basis requires:
    /// date-only series take `yyyyMMdd`; utc/zoned series take a UTC
    /// instant. Any other form is a mismatch, never a guess.
    private static func parseUntil(
        _ raw: String,
        basis: PIMRecurrenceDescriptor.StartBasis
    ) -> Result<Date, PIMRecurrenceUnsupportedReason> {
        switch basis {
        case .dateOnly:
            guard raw.count == 8, raw.allSatisfy(\.isNumber) else {
                return .failure(.untilFormMismatch)
            }
            guard let date = untilDateOnly.date(from: raw) else {
                return .failure(.malformedUntil(raw))
            }
            return .success(date)
        case .utc, .zoned:
            // Required shape: 8 digits, a literal T, 6 digits, a Z.
            let body = raw.hasSuffix("Z") ? String(raw.dropLast()) : raw
            guard raw.hasSuffix("Z"),
                  body.count == 15,
                  body[body.index(body.startIndex, offsetBy: 8)] == "T",
                  body.filter(\.isNumber).count == 14
            else {
                return .failure(.untilFormMismatch)
            }
            guard let date = Self.untilUTC.date(from: raw) else {
                return .failure(.malformedUntil(raw))
            }
            return .success(date)
        case .floating, .unknown:
            // The basis check already rejects these before UNTIL is read.
            return .failure(.untilFormMismatch)
        }
    }

    private static let untilDateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    private static let untilUTC: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()
}
