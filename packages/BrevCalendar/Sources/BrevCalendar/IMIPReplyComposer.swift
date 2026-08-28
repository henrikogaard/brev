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

/// Builds local iMIP `METHOD:REPLY` payloads for backends that expose
/// SMTP sending but no server-side calendar reply endpoint.
public enum IMIPReplyComposer {
    public enum ComposeError: Error, Equatable, Sendable {
        case missingUID
    }

    public enum ReplyStatus: Sendable, Hashable {
        case accepted
        case tentative
        case declined

        fileprivate var partstat: String {
            switch self {
            case .accepted: "ACCEPTED"
            case .tentative: "TENTATIVE"
            case .declined: "DECLINED"
            }
        }

        fileprivate var subjectPrefix: String {
            switch self {
            case .accepted: "Accepted"
            case .tentative: "Maybe"
            case .declined: "Declined"
            }
        }

        fileprivate var bodyVerb: String {
            switch self {
            case .accepted: "accepted"
            case .tentative: "tentatively accepted"
            case .declined: "declined"
            }
        }
    }

    public struct Reply: Sendable, Hashable {
        public let subject: String
        public let plainTextBody: String
        public let ics: String
    }

    public static func compose(
        event: ICSParser.ParsedEvent,
        attendee: ICSParser.ParsedPerson,
        status: ReplyStatus,
        now: Date = Date(),
        productIdentifier: String = "-//Brev//BrevCalendar//EN"
    ) throws -> Reply {
        let uid = event.uid?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uid, !uid.isEmpty else {
            throw ComposeError.missingUID
        }

        let title = event.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = title?.isEmpty == false ? title! : "Calendar invite"
        let subject = "\(status.subjectPrefix): \(safeTitle)"

        var lines = [
            "BEGIN:VCALENDAR",
            "PRODID:\(escapeText(productIdentifier))",
            "VERSION:2.0",
            "METHOD:REPLY",
            "BEGIN:VEVENT",
            "UID:\(escapeText(uid))",
            "DTSTAMP:\(utcDateFormatter.string(from: now))"
        ]

        if let start = event.start {
            lines.append(formattedDateLine(name: "DTSTART", date: start, isAllDay: event.isAllDay))
        }
        if let end = event.end {
            lines.append(formattedDateLine(name: "DTEND", date: end, isAllDay: event.isAllDay))
        }

        lines.append("SUMMARY:\(escapeText(safeTitle))")

        if let organizer = event.organizer {
            lines.append(personLine(name: "ORGANIZER", person: organizer, extraParameters: []))
        }

        lines.append(personLine(
            name: "ATTENDEE",
            person: attendee,
            extraParameters: [
                "PARTSTAT=\(status.partstat)",
                "RSVP=FALSE"
            ]
        ))

        lines.append("END:VEVENT")
        lines.append("END:VCALENDAR")

        let ics = lines.joined(separator: "\r\n") + "\r\n"
        return Reply(
            subject: subject,
            plainTextBody: "This attendee has \(status.bodyVerb) \(safeTitle).",
            ics: ics
        )
    }

    private static func formattedDateLine(name: String, date: Date, isAllDay: Bool) -> String {
        if isAllDay {
            "\(name);VALUE=DATE:\(dateOnlyFormatter.string(from: date))"
        } else {
            "\(name):\(utcDateFormatter.string(from: date))"
        }
    }

    private static func personLine(
        name: String,
        person: ICSParser.ParsedPerson,
        extraParameters: [String]
    ) -> String {
        var parameters: [String] = []
        if let displayName = person.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            parameters.append("CN=\"\(escapeParameter(displayName))\"")
        }
        parameters.append(contentsOf: extraParameters)
        let parameterText = parameters.isEmpty ? "" : ";\(parameters.joined(separator: ";"))"
        return "\(name)\(parameterText):mailto:\(sanitizeEmail(person.email))"
    }

    /// Strips characters from an address that would break the ICS line structure
    /// or inject new properties (CR/LF, the `;`/`:`/`,` separators, control
    /// chars). A legitimate address contains none of these; the value is
    /// otherwise inserted unescaped after `mailto:`.
    private static func sanitizeEmail(_ raw: String) -> String {
        let disallowed = CharacterSet(charactersIn: ";:,\"\r\n").union(.controlCharacters)
        return raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: disallowed)
            .joined()
    }

    private static func escapeText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
    }

    private static func escapeParameter(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static let utcDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}
