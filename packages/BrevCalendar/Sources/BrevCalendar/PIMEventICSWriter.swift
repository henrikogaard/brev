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

/// Serializes a `PIMEvent` into an RFC 5545 `VCALENDAR` payload for
/// CardDAV PUT and as the interchange form for edits (ADR-0072 #7).
///
/// The writer emits the fields the shared model owns: UID, DTSTAMP,
/// DTSTART/DTEND (VALUE=DATE with an exclusive end for all-day events,
/// TZID for timed events whose zone is known), SUMMARY, LOCATION,
/// DESCRIPTION, STATUS, RRULE, ORGANIZER, ATTENDEE, VALARM reminders,
/// and the conference URL as URL. Provider payload fields the model does
/// not read are preserved separately via `PIMEvent.rawPayload` — the
/// write path merges them where the provider requires it, but this
/// writer emits a clean canonical VEVENT.
public enum PIMEventICSWriter {
    /// The product identifier emitted in PRODID.
    public static let productID = "-//Brev//Brev Calendar//EN"

    /// Serializes one event as a complete VCALENDAR document with CRLF
    /// line endings and 75-octet folding.
    ///
    /// - Parameters:
    ///   - event: The event to serialize. `uid` falls back to the
    ///     provider item key when absent; both must exist for a stable
    ///     resource name.
    ///   - dtstamp: The DTSTAMP value — injectable for tests.
    public static func vcalendar(
        for event: PIMEvent,
        dtstamp: Date = Date()
    ) -> String {
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:\(productID)",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "BEGIN:VEVENT",
        ]
        lines.append(
            "UID:" + (event.uid ?? event.providerItemKey)
        )
        lines.append("DTSTAMP:" + utcStamp(dtstamp))
        lines.append(contentsOf: dateLines(for: event))
        if let summary = event.summary, !summary.isEmpty {
            lines.append("SUMMARY:" + escape(summary))
        }
        if let location = event.location, !location.isEmpty {
            lines.append("LOCATION:" + escape(location))
        }
        if let description = event.eventDescription, !description.isEmpty {
            lines.append("DESCRIPTION:" + escape(description))
        }
        if event.status != .confirmed {
            lines.append("STATUS:" + statusText(event.status))
        }
        if let rule = event.recurrenceRule {
            lines.append("RRULE:" + recurrenceText(rule))
        }
        if let recurrenceID = event.recurrenceID {
            lines.append(
                "RECURRENCE-ID" + dateValueSuffix(
                    recurrenceID,
                    isAllDay: event.isAllDay,
                    timeZoneIdentifier: event.timeZoneIdentifier
                )
            )
        }
        if let organizer = event.organizer {
            lines.append(personLine("ORGANIZER", organizer))
        }
        for attendee in event.attendees {
            lines.append(personLine("ATTENDEE", attendee))
        }
        for reminder in event.reminders {
            lines.append(contentsOf: alarmLines(reminder))
        }
        if let conferenceURL = event.conferenceURL, !conferenceURL.isEmpty {
            lines.append("URL:" + conferenceURL)
        }
        lines.append("END:VEVENT")
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    // MARK: - Dates

    /// DTSTART/DTEND lines. All-day events emit VALUE=DATE with the
    /// exclusive end the provider stored; timed events emit TZID when
    /// the event carries one, else UTC.
    private static func dateLines(for event: PIMEvent) -> [String] {
        var lines: [String] = []
        if let start = event.start {
            lines.append(
                "DTSTART" + dateValueSuffix(
                    start,
                    isAllDay: event.isAllDay,
                    timeZoneIdentifier: event.timeZoneIdentifier
                )
            )
        }
        if let end = event.end {
            lines.append(
                "DTEND" + dateValueSuffix(
                    end,
                    isAllDay: event.isAllDay,
                    timeZoneIdentifier: event.timeZoneIdentifier
                )
            )
        }
        return lines
    }

    /// The parameter + value suffix for a date property:
    /// ";VALUE=DATE:20260921", ";TZID=Europe/Oslo:20260921T090000", or
    /// ":20260921T090000Z".
    private static func dateValueSuffix(
        _ date: Date,
        isAllDay: Bool,
        timeZoneIdentifier: String?
    ) -> String {
        if isAllDay {
            return ";VALUE=DATE:" + utcDayStamp(date)
        }
        if let tzid = timeZoneIdentifier,
           let zone = TimeZone(identifier: tzid) {
            return ";TZID=" + tzid + ":" + zonedStamp(date, in: zone)
        }
        return ":" + utcStamp(date)
    }

    // MARK: - Recurrence

    private static func recurrenceText(
        _ rule: ICSParser.RecurrenceRule
    ) -> String {
        var parts = ["FREQ=" + rule.frequency.rawValue]
        if rule.interval > 1 {
            parts.append("INTERVAL=\(rule.interval)")
        }
        if let count = rule.count {
            parts.append("COUNT=\(count)")
        }
        if let until = rule.until {
            parts.append("UNTIL=" + utcStamp(until))
        }
        if let byDay = rule.byDay, !byDay.isEmpty {
            parts.append(
                "BYDAY=" + byDay.map(\.rawValue).joined(separator: ",")
            )
        }
        return parts.joined(separator: ";")
    }

    // MARK: - People

    private static func personLine(
        _ property: String,
        _ person: PIMEventPerson
    ) -> String {
        var line = property
        if let name = person.name, !name.isEmpty {
            line += ";CN=" + escapeParam(name)
        }
        if person.rsvp != .unknown {
            line += ";PARTSTAT=" + partstat(person.rsvp)
        }
        return line + ":mailto:" + person.email
    }

    private static func partstat(_ rsvp: PIMEventPerson.RSVP) -> String {
        switch rsvp {
        case .accepted: "ACCEPTED"
        case .declined: "DECLINED"
        case .tentative: "TENTATIVE"
        case .needsAction, .unknown: "NEEDS-ACTION"
        case .delegated: "DELEGATED"
        }
    }

    // MARK: - Reminders

    private static func alarmLines(_ reminder: PIMEventReminder) -> [String] {
        guard let minutes = reminder.minutesBefore else {
            // Provider-default reminders have no portable trigger —
            // emit nothing rather than inventing one.
            return []
        }
        return [
            "BEGIN:VALARM",
            "ACTION:DISPLAY",
            "TRIGGER:-PT\(minutes)M",
            "END:VALARM",
        ]
    }

    // MARK: - Status

    private static func statusText(_ status: PIMEventStatus) -> String {
        switch status {
        case .confirmed: "CONFIRMED"
        case .tentative: "TENTATIVE"
        case .cancelled: "CANCELLED"
        }
    }

    // MARK: - Escaping and folding

    /// RFC 5545 TEXT escaping: backslash first, then semicolon, comma,
    /// and newline.
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Parameter values escape double quotes and the TEXT specials.
    private static func escapeParam(_ text: String) -> String {
        escape(text).replacingOccurrences(of: "\"", with: "'")
    }

    /// Folds a content line at 75 octets per RFC 5545 §3.1 — continuation
    /// lines open with a single space.
    private static func fold(_ line: String) -> String {
        var bytes = Array(line.utf8)
        guard bytes.count > 75 else { return line }
        var folded = ""
        var first = true
        while !bytes.isEmpty {
            let limit = first ? 75 : 74
            let chunk = bytes.prefix(limit)
            // Never split inside a multi-byte UTF-8 sequence — back off
            // to the last scalar boundary.
            var take = chunk.count
            // A continuation byte (10xxxxxx) right after the cut means
            // the character straddles the boundary — back off to its
            // lead byte. Checking bytes[take] (first byte of the next
            // chunk) rather than bytes[take - 1] keeps a complete
            // trailing sequence intact.
            while take > 0, take < bytes.count,
                  (bytes[take] & 0b1100_0000) == 0b1000_0000 {
                take -= 1
            }
            if take == 0 { take = chunk.count }
            let piece = bytes.prefix(take)
            folded += (first ? "" : "\r\n ")
                + String(decoding: piece, as: UTF8.self)
            bytes = Array(bytes.dropFirst(take))
            first = false
        }
        return folded
    }

    // MARK: - Date stamps

    /// "yyyyMMddTHHmmssZ" in UTC — the DTSTAMP and floating-free fallback.
    private static func utcStamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return String(
            format: "%04d%02d%02dT%02d%02d%02dZ",
            c.year ?? 0, c.month ?? 0, c.day ?? 0,
            c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
    }

    /// "yyyyMMdd" in UTC — the VALUE=DATE form for all-day events.
    private static func utcDayStamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return String(
            format: "%04d%02d%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0
        )
    }

    /// "yyyyMMddTHHmmss" in the named zone — the TZID form.
    private static func zonedStamp(_ date: Date, in zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return String(
            format: "%04d%02d%02dT%02d%02d%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0,
            c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
    }
}
