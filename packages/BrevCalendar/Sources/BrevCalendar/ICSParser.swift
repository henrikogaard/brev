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

/// Minimal RFC 5545 (iCalendar) parser sufficient to surface
/// invite metadata in the message viewer.
///
/// This is intentionally a narrow subset:
/// - `parseFirstEvent` reads the first `VEVENT`; `parseEvents` reads every
///   `VEVENT` so CalDAV resources carrying a master plus recurrence
///   exceptions map to one record per component.
/// - `VTIMEZONE` blocks are parsed to build a TZID→UTC-offset map;
///   DTSTART/DTEND with a matching TZID parameter are converted to UTC.
/// - `VALUE=DATE` on DTSTART/DTEND marks the event as all-day.
/// - `RRULE` is parsed into a `RecurrenceRule` value; recurrences are
///   not expanded — that is the caller's responsibility.
/// - Line folding (RFC 5545 §3.1) is unfolded before parsing.
/// - Escaped characters (`\n`, `\,`, `\;`, `\\`) are decoded in
///   text values.
public enum ICSParser {
    public struct ParsedEvent: Sendable, Hashable {
        public let uid: String?
        public let summary: String?
        public let description: String?
        public let location: String?
        public let start: Date?
        public let end: Date?
        public let isAllDay: Bool
        public let organizer: ParsedPerson?
        public let attendees: [ParsedPerson]
        /// Parsed recurrence rule, if the event contains an `RRULE` property.
        /// Recurrences are not expanded; use this to describe the pattern in UI.
        public let recurrenceRule: RecurrenceRule?
        /// Raw `STATUS` value (CONFIRMED / TENTATIVE / CANCELLED), when set.
        public let status: String?
        /// `RECURRENCE-ID` timestamp marking this component as an exception
        /// instance of the series identified by `uid`.
        public let recurrenceID: Date?
        /// `TZID` parameter on DTSTART, when the event carries a named zone.
        public let timeZoneIdentifier: String?
        /// `LAST-MODIFIED` timestamp, when present.
        public let lastModified: Date?
        /// Minutes-before-start values parsed from VALARM `TRIGGER`
        /// properties. Only relative trigger offsets are captured.
        public let reminderMinutes: [Int]
        /// First `CONFERENCE;VALUE=URI` or `X-GOOGLE-CONFERENCE` URI found.
        public let conferenceURL: String?

        /// Memberwise initialiser with a `nil` default for `recurrenceRule`
        /// so call-sites that construct `ParsedEvent` directly (e.g. in tests)
        /// do not need updating when the field is irrelevant to the test.
        public init(
            uid: String?,
            summary: String?,
            description: String?,
            location: String?,
            start: Date?,
            end: Date?,
            isAllDay: Bool,
            organizer: ParsedPerson?,
            attendees: [ParsedPerson],
            recurrenceRule: RecurrenceRule? = nil,
            status: String? = nil,
            recurrenceID: Date? = nil,
            timeZoneIdentifier: String? = nil,
            lastModified: Date? = nil,
            reminderMinutes: [Int] = [],
            conferenceURL: String? = nil
        ) {
            self.uid = uid
            self.summary = summary
            self.description = description
            self.location = location
            self.start = start
            self.end = end
            self.isAllDay = isAllDay
            self.organizer = organizer
            self.attendees = attendees
            self.recurrenceRule = recurrenceRule
            self.status = status
            self.recurrenceID = recurrenceID
            self.timeZoneIdentifier = timeZoneIdentifier
            self.lastModified = lastModified
            self.reminderMinutes = reminderMinutes
            self.conferenceURL = conferenceURL
        }
    }

    public struct ParsedPerson: Sendable, Hashable {
        public let name: String?
        public let email: String
        /// Raw `PARTSTAT` parameter (NEEDS-ACTION / ACCEPTED / DECLINED /
        /// TENTATIVE / DELEGATED), when the property carried one.
        public let participation: String?

        public init(
            name: String? = nil,
            email: String,
            participation: String? = nil
        ) {
            self.name = name
            self.email = email
            self.participation = participation
        }
    }

    // MARK: - RecurrenceRule support types

    /// Recurrence frequency values, directly mapping RFC 5545 FREQ tokens.
    public enum Frequency: String, Sendable, Hashable, Codable {
        case daily = "DAILY"
        case weekly = "WEEKLY"
        case monthly = "MONTHLY"
        case yearly = "YEARLY"
    }

    /// Days of the week, directly mapping RFC 5545 two-letter BYDAY codes.
    public enum Weekday: String, Sendable, Hashable, Codable, CaseIterable {
        case monday = "MO"
        case tuesday = "TU"
        case wednesday = "WE"
        case thursday = "TH"
        case friday = "FR"
        case saturday = "SA"
        case sunday = "SU"
    }

    // MARK: - RecurrenceRule

    /// Structured representation of an RFC 5545 `RRULE` property value.
    ///
    /// Only the parts relevant to displaying a human-readable repeat
    /// description are captured here.  Full iCalendar expansion (e.g.
    /// generating all occurrence dates) is out of scope for this parser.
    public struct RecurrenceRule: Sendable, Hashable, Codable {
        /// How often the event repeats.
        public let frequency: Frequency
        /// Interval between recurrences (default 1).
        public let interval: Int
        /// Maximum number of occurrences, or `nil` for an open-ended rule.
        public let count: Int?
        /// Last occurrence date, or `nil` when `count` or neither bound is set.
        public let until: Date?
        /// Weekdays on which the event repeats, applicable to `.weekly` rules.
        public let byDay: [Weekday]?

        public init(
            frequency: Frequency,
            interval: Int = 1,
            count: Int? = nil,
            until: Date? = nil,
            byDay: [Weekday]? = nil
        ) {
            self.frequency = frequency
            self.interval = interval
            self.count = count
            self.until = until
            self.byDay = byDay
        }
    }

    // MARK: - Parsing entry point

    /// Parse the supplied ICS payload. Returns `nil` if no
    /// `VEVENT` block is found or required fields are missing.
    public static func parseFirstEvent(from raw: String) -> ParsedEvent? {
        parseEvents(from: raw).first
    }

    /// Parse every `VEVENT` in the payload, in file order. CalDAV resources
    /// commonly carry a master component followed by `RECURRENCE-ID`
    /// exceptions; each becomes its own `ParsedEvent`.
    public static func parseEvents(from raw: String) -> [ParsedEvent] {
        let unfolded = unfold(raw)
        let lines = unfolded.components(separatedBy: .newlines).filter { !$0.isEmpty }

        // ── Step 1: build TZID → UTC-offset map from VTIMEZONE blocks ────────
        let tzOffsets = parseTimezoneOffsets(from: lines)

        // ── Step 2: collect each VEVENT block's properties ───────────────────
        var blocks: [[Property]] = []
        var inEvent = false
        var props: [Property] = []
        for line in lines {
            if line == "BEGIN:VEVENT" {
                inEvent = true
                props.removeAll()
                continue
            }
            if line == "END:VEVENT" {
                if inEvent, !props.isEmpty {
                    blocks.append(props)
                }
                inEvent = false
                continue
            }
            if inEvent, let parsed = parseProperty(line) {
                props.append(parsed)
            }
        }

        return blocks.map { makeEvent(from: $0, tzOffsets: tzOffsets) }
    }

    /// Builds one `ParsedEvent` from a single VEVENT's property list.
    private static func makeEvent(
        from props: [Property],
        tzOffsets: [String: Int]
    ) -> ParsedEvent {

        func first(_ name: String) -> Property? {
            props.first { $0.name == name }
        }

        let summary = first("SUMMARY")?.value.icsUnescaped
        let description = first("DESCRIPTION")?.value.icsUnescaped
        let location = first("LOCATION")?.value.icsUnescaped
        let uid = first("UID")?.value

        let dtstart = first("DTSTART")
        let dtend = first("DTEND")
        let isAllDay = dtstart?.params["VALUE"]?.uppercased() == "DATE"
        let start = dtstart.flatMap { parseDate($0.value, isAllDay: isAllDay, tzid: $0.params["TZID"], tzOffsets: tzOffsets) }
        let end = dtend.flatMap { parseDate($0.value, isAllDay: isAllDay, tzid: $0.params["TZID"], tzOffsets: tzOffsets) }

        let organizer = first("ORGANIZER").flatMap { parsePerson(params: $0.params, value: $0.value) }
        let attendees = props
            .filter { $0.name == "ATTENDEE" }
            .compactMap { parsePerson(params: $0.params, value: $0.value) }

        let recurrenceRule = first("RRULE").flatMap { parseRRule($0.value) }

        let status = first("STATUS")?.value.uppercased()
        let recurrenceIDProperty = first("RECURRENCE-ID")
        let recurrenceID = recurrenceIDProperty.flatMap {
            parseDate(
                $0.value,
                isAllDay: $0.params["VALUE"]?.uppercased() == "DATE",
                tzid: $0.params["TZID"],
                tzOffsets: tzOffsets
            )
        }
        let lastModified = first("LAST-MODIFIED").flatMap {
            parseDate($0.value, isAllDay: false, tzid: $0.params["TZID"], tzOffsets: tzOffsets)
        }
        let reminderMinutes = props
            .filter { $0.name == "TRIGGER" }
            .compactMap { parseTriggerMinutes($0.value) }
        let conferenceURL = props
            .first {
                ($0.name == "CONFERENCE" && $0.params["VALUE"]?.uppercased() == "URI")
                    || $0.name == "X-GOOGLE-CONFERENCE"
            }?
            .value
            .trimmingCharacters(in: .whitespaces)

        return ParsedEvent(
            uid: uid,
            summary: summary,
            description: description,
            location: location,
            start: start,
            end: end,
            isAllDay: isAllDay,
            organizer: organizer,
            attendees: attendees,
            recurrenceRule: recurrenceRule,
            status: status,
            recurrenceID: recurrenceID,
            timeZoneIdentifier: dtstart?.params["TZID"],
            lastModified: lastModified,
            reminderMinutes: reminderMinutes,
            conferenceURL: conferenceURL
        )
    }

    /// Parse an RFC 5545 `RRULE` value (without the `RRULE:` prefix) into a
    /// `RecurrenceRule`. Exposed for adapters whose providers ship bare rule
    /// strings, e.g. Google Calendar's `recurrence` array entries.
    public static func parseRecurrenceRule(_ raw: String) -> RecurrenceRule? {
        parseRRule(raw)
    }

    // MARK: - Private helpers

    private struct Property {
        let name: String
        let params: [String: String]
        let value: String
    }

    private static func unfold(_ raw: String) -> String {
        // RFC 5545 §3.1: a CRLF followed by a single space/tab is a
        // continuation of the previous line.
        raw
            .replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
            .replacingOccurrences(of: "\r ", with: "")
            .replacingOccurrences(of: "\r\t", with: "")
    }

    private static func parseProperty(_ line: String) -> Property? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let lhs = line[..<colon]
        let value = String(line[line.index(after: colon)...])
        let parts = lhs.split(separator: ";", omittingEmptySubsequences: true)
        guard let first = parts.first else { return nil }
        let name = String(first).uppercased()
        var params: [String: String] = [:]
        for piece in parts.dropFirst() {
            let kv = piece.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            if kv.count == 2 {
                params[String(kv[0]).uppercased()] = String(kv[1])
            }
        }
        return Property(name: name, params: params, value: value)
    }

    private static func parsePerson(
        params: [String: String],
        value: String
    ) -> ParsedPerson? {
        // Value is typically "mailto:email@example.com"
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let scheme = trimmed.range(of: "mailto:", options: .caseInsensitive) else {
            return nil
        }
        let email = String(trimmed[scheme.upperBound...])
        let cn = params["CN"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return ParsedPerson(
            name: cn?.isEmpty == false ? cn : nil,
            email: email,
            participation: params["PARTSTAT"]?.uppercased()
        )
    }

    /// Parses an RFC 5545 duration trigger such as `-PT15M` or `-P1D` into
    /// minutes before the event. Returns `nil` for absolute-time triggers
    /// and unparseable values; positive (after-start) triggers keep their
    /// sign by returning a negative minute count.
    private static func parseTriggerMinutes(_ raw: String) -> Int? {
        var value = raw.trimmingCharacters(in: .whitespaces)
        var sign = 1
        if value.hasPrefix("-") {
            value.removeFirst()
        } else if value.hasPrefix("+") {
            value.removeFirst()
            sign = -1
        } else {
            // TRIGGER without a leading sign is a positive offset or an
            // absolute DATE-TIME — only relative before-start triggers map.
            guard value.hasPrefix("P") else { return nil }
            sign = -1
        }
        guard value.hasPrefix("P") else { return nil }
        value.removeFirst()

        var weeks = 0, days = 0, hours = 0, minutes = 0
        var inTime = false
        var number = ""
        for char in value {
            if char == "T" { inTime = true; continue }
            if char.isNumber {
                number.append(char)
                continue
            }
            guard let n = Int(number) else { return nil }
            number = ""
            switch char {
            case "W": weeks = n
            case "D": days = n
            case "H" where inTime: hours = n
            case "M" where inTime: minutes = n
            default: return nil
            }
        }
        guard number.isEmpty else { return nil }
        let total = weeks * 7 * 24 * 60 + days * 24 * 60 + hours * 60 + minutes
        return total * sign
    }

    // MARK: - VTIMEZONE parsing

    /// Scan all `VTIMEZONE` blocks and return a map of TZID → UTC offset
    /// in seconds.  Only the `TZOFFSETTO` value from the first `STANDARD`
    /// sub-component is used; DST complexity is deferred until we need it.
    private static func parseTimezoneOffsets(from lines: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        var inVTZ = false
        var inStandard = false
        var currentTZID: String?
        var standardOffset: Int?

        for line in lines {
            if line == "BEGIN:VTIMEZONE" {
                inVTZ = true
                currentTZID = nil
                standardOffset = nil
                continue
            }
            if line == "END:VTIMEZONE" {
                if let tzid = currentTZID, let offset = standardOffset {
                    result[tzid] = offset
                }
                inVTZ = false
                inStandard = false
                continue
            }
            guard inVTZ else { continue }

            if line == "BEGIN:STANDARD" {
                inStandard = true
                continue
            }
            if line == "END:STANDARD" {
                inStandard = false
                continue
            }
            if line == "BEGIN:DAYLIGHT" || line == "END:DAYLIGHT" {
                // Ignore DAYLIGHT sub-component for now.
                continue
            }

            if let prop = parseProperty(line) {
                if prop.name == "TZID" {
                    currentTZID = prop.value
                } else if inStandard, prop.name == "TZOFFSETTO" {
                    standardOffset = parseUTCOffset(prop.value)
                }
            }
        }

        return result
    }

    /// Convert an RFC 5545 UTC-offset token (e.g. `+0200`, `-0530`) to
    /// a total number of seconds east of UTC.
    private static func parseUTCOffset(_ raw: String) -> Int? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        let sign: Int
        if s.hasPrefix("+") {
            sign = 1
            s = String(s.dropFirst())
        } else if s.hasPrefix("-") {
            sign = -1
            s = String(s.dropFirst())
        } else {
            sign = 1
        }

        // Accept both `HHMM` and `HHMMSS` (RFC 5545 allows both).
        let digits = s.filter { $0.isNumber }
        guard digits.count >= 4 else { return nil }
        let hh = Int(digits.prefix(2)) ?? 0
        let mm = Int(digits.dropFirst(2).prefix(2)) ?? 0
        let ss = digits.count >= 6 ? (Int(digits.dropFirst(4).prefix(2)) ?? 0) : 0
        return sign * (hh * 3600 + mm * 60 + ss)
    }

    // MARK: - Date parsing

    private static func parseDate(
        _ raw: String,
        isAllDay: Bool,
        tzid: String?,
        tzOffsets: [String: Int]
    ) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        if isAllDay {
            return dateOnlyFormatter.date(from: trimmed)
        }

        // UTC suffix → parse directly as UTC.
        if trimmed.hasSuffix("Z") {
            return utcFormatter.date(from: trimmed)
        }

        // TZID present → look it up in the parsed VTIMEZONE map, then
        // fall back to the named TimeZone identifier (covers IANA names
        // that appear in the file but were not accompanied by a
        // VTIMEZONE block), and finally fall back to TimeZone.current.
        if let tzid {
            // Interpret in the named IANA zone when possible so the offset is
            // correct for the event's own date (DST). Using a single fixed
            // offset from `secondsFromGMT()` would apply today's offset to an
            // event in a different DST state (off by an hour). Brev's VTIMEZONE
            // parsing captures only the STANDARD offset, so it is a fallback for
            // custom (non-IANA) TZIDs.
            if let zone = TimeZone(identifier: tzid) {
                return makeZoneFormatter(zone).date(from: trimmed)
            }
            if let offsetSeconds = tzOffsets[tzid],
               let zone = TimeZone(secondsFromGMT: offsetSeconds) {
                return makeZoneFormatter(zone).date(from: trimmed)
            }
            return floatingFormatter.date(from: trimmed)
        }

        // Floating time — treat as local.
        return floatingFormatter.date(from: trimmed)
    }

    /// A `yyyyMMdd'T'HHmmss` formatter that interprets the value in `zone`,
    /// applying the zone's own DST rules for the parsed date.
    private static func makeZoneFormatter(_ zone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = zone
        return formatter
    }

    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    private static let floatingFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    // MARK: - RRULE parsing

    /// Parse an RFC 5545 `RRULE` property value into a `RecurrenceRule`.
    ///
    /// Unrecognised parts (e.g. `BYMONTHDAY`, `BYSETPOS`) are silently
    /// ignored.  Returns `nil` when `FREQ` is absent or unrecognised.
    private static func parseRRule(_ raw: String) -> RecurrenceRule? {
        var frequency: Frequency?
        var interval = 1
        var count: Int?
        var until: Date?
        var byDay: [Weekday]?

        for part in raw.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let key = String(kv[0]).uppercased()
            let val = String(kv[1])

            switch key {
            case "FREQ":
                frequency = Frequency(rawValue: val.uppercased())
            case "INTERVAL":
                interval = Int(val) ?? 1
            case "COUNT":
                count = Int(val)
            case "UNTIL":
                // UNTIL can be a DATE or a DATETIME (with or without Z suffix).
                if val.hasSuffix("Z") {
                    until = utcFormatter.date(from: val)
                } else if val.contains("T") {
                    until = floatingFormatter.date(from: val)
                } else {
                    until = dateOnlyFormatter.date(from: val)
                }
            case "BYDAY":
                byDay = val.split(separator: ",").compactMap { token in
                    // BYDAY values may carry an ordinal prefix (e.g. `2MO`);
                    // strip leading digits and sign characters before matching.
                    let code = token.drop { $0.isNumber || $0 == "+" || $0 == "-" }
                    return Weekday(rawValue: String(code).uppercased())
                }
            default:
                break
            }
        }

        guard let frequency else { return nil }
        return RecurrenceRule(
            frequency: frequency,
            interval: interval,
            count: count,
            until: until,
            byDay: byDay?.isEmpty == false ? byDay : nil
        )
    }
}

private extension String {
    /// Decode the small set of escape sequences ICS uses inside
    /// TEXT-typed values.
    var icsUnescaped: String {
        var result = ""
        result.reserveCapacity(count)
        var iterator = unicodeScalars.makeIterator()
        while let scalar = iterator.next() {
            if scalar == "\\", let next = iterator.next() {
                switch next {
                case "n", "N": result.append("\n")
                case "t", "T": result.append("\t")
                case ",", ";", "\\": result.unicodeScalars.append(next)
                default:
                    result.append("\\")
                    result.unicodeScalars.append(next)
                }
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
