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

/// Minimal vCard 3.0/4.0 parser for the PIM contact sync path
/// (ADR-0072). Reads the fields the shared contact model displays —
/// FN, N, NICKNAME, EMAIL, TEL, ADR, ORG, TITLE, NOTE, PHOTO,
/// URL, BDAY, ANNIVERSARY, X-ABDATE, CATEGORIES, REV, UID — and leaves
/// everything else to the record's `rawPayload` for round-trip
/// preservation.
///
/// Line folding (RFC 6350 §3.2) is unfolded first; groups
/// (`item1.EMAIL`) and quoted parameter values are tolerated.
enum PIMVCardParser {
    struct ParsedContact: Sendable, Hashable {
        var uid: String?
        var displayName: String?
        var givenName: String?
        var familyName: String?
        var nickname: String?
        var organization: String?
        var jobTitle: String?
        var note: String?
        var emails: [PIMContactField] = []
        var phones: [PIMContactField] = []
        var addresses: [PIMContactAddress] = []
        var dates: [PIMContactDate] = []
        var urls: [PIMContactField] = []
        var photoURL: String?
        var photoData: Data?
        var groupKeys: [String] = []
        var revisedAt: Date?
    }

    /// Parses one vCard text blob. Returns nil when the blob carries no
    /// usable identity (no FN and no N).
    static func parse(_ raw: String) -> ParsedContact? {
        var contact = ParsedContact()
        for line in unfold(raw) {
            guard let property = parseProperty(line) else { continue }
            apply(property, to: &contact)
        }
        if contact.displayName?.isEmpty != false,
           contact.givenName == nil, contact.familyName == nil {
            return nil
        }
        if contact.displayName?.isEmpty != false {
            contact.displayName = [contact.givenName, contact.familyName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        return contact.displayName?.isEmpty == false ? contact : nil
    }

    // MARK: - Property application

    private static func apply(
        _ property: Property,
        to contact: inout ParsedContact
    ) {
        let value = property.value.vCardUnescaped
        switch property.name {
        case "FN":
            contact.displayName = value
        case "N":
            // N:family;given;additional;prefix;suffix
            let parts = property.value.components(separatedBy: ";")
            contact.familyName = parts.first?.vCardUnescaped.nilIfEmpty
            if parts.count > 1 {
                contact.givenName = parts[1].vCardUnescaped.nilIfEmpty
            }
        case "NICKNAME":
            contact.nickname = value.components(separatedBy: ",").first?
                .trimmingCharacters(in: .whitespaces).nilIfEmpty ?? value
        case "EMAIL":
            if !value.isEmpty {
                contact.emails.append(
                    PIMContactField(
                        label: property.label,
                        value: value.lowercased()
                    )
                )
            }
        case "TEL":
            if !value.isEmpty {
                contact.phones.append(
                    PIMContactField(label: property.label, value: value)
                )
            }
        case "ADR":
            // ADR:po;ext;street;city;region;code;country
            let parts = property.value.components(separatedBy: ";")
            func part(_ index: Int) -> String? {
                guard parts.count > index else { return nil }
                return parts[index].vCardUnescaped.nilIfEmpty
            }
            let address = PIMContactAddress(
                label: property.label,
                street: part(2),
                city: part(3),
                region: part(4),
                postalCode: part(5),
                country: part(6)
            )
            if !address.isEmpty { contact.addresses.append(address) }
        case "ORG":
            // ORG:name;division — keep the first component.
            contact.organization = property.value
                .components(separatedBy: ";")
                .first?.vCardUnescaped.nilIfEmpty
        case "TITLE":
            contact.jobTitle = value.nilIfEmpty
        case "NOTE":
            contact.note = value.nilIfEmpty
        case "URL":
            if !value.isEmpty {
                contact.urls.append(
                    PIMContactField(label: property.label, value: value)
                )
            }
        case "BDAY":
            if let date = parseDate(property.value, label: "birthday") {
                contact.dates.append(date)
            }
        case "ANNIVERSARY":
            if let date = parseDate(property.value, label: "anniversary") {
                contact.dates.append(date)
            }
        case "X-ABDATE":
            // Apple's labeled-date extension; TYPE carries the label.
            if let date = parseDate(property.value, label: property.label) {
                contact.dates.append(date)
            }
        case "PHOTO":
            // URI references store the URL; inline ENCODING=b / data-URI
            // payloads decode into photoData so the editor can show and
            // re-emit them. Nothing is ever fetched.
            if property.params["VALUE"]?.uppercased() == "URI",
               value.lowercased().hasPrefix("https://") {
                contact.photoURL = value
            } else if let encoded = inlinePhotoPayload(property, value) {
                contact.photoData = Data(base64Encoded: encoded)
            }
        case "CATEGORIES":
            contact.groupKeys = property.value
                .components(separatedBy: ",")
                .map { $0.vCardUnescaped.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        case "REV":
            contact.revisedAt = parseRevision(property.value)
        case "UID":
            contact.uid = value.nilIfEmpty
        default:
            break
        }
    }

    // MARK: - Lines and properties

    private struct Property {
        let name: String
        let params: [String: String]
        let value: String

        /// The first TYPE/label parameter, normalized lowercase.
        var label: String? {
            (params["TYPE"] ?? params["LABEL"])?
                .lowercased()
                .nilIfEmpty
        }
    }

    /// RFC 6350 §3.2 unfolding plus quoted-printable soft breaks some
    /// servers still emit (`=\n` line continuations). A `=` join happens
    /// only when the next line is not itself a property — otherwise a
    /// base64 PHOTO payload's `=` padding would swallow the next field.
    private static func unfold(_ raw: String) -> [String] {
        let lines = raw
            .replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var joined: [String] = []
        for line in lines {
            if let last = joined.last,
               last.hasSuffix("="),
               parseProperty(line) == nil {
                joined[joined.count - 1] = String(last.dropLast()) + line
            } else {
                joined.append(line)
            }
        }
        return joined
    }

    private static func parseProperty(_ line: String) -> Property? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let lhs = line[..<colon]
        let value = String(line[line.index(after: colon)...])
        let parts = lhs.split(
            separator: ";",
            omittingEmptySubsequences: true
        )
        guard let first = parts.first else { return nil }
        // Strip a vCard4 group prefix ("item1.EMAIL").
        let rawName = String(first)
        let name = String(rawName.split(separator: ".").last ?? "")
            .uppercased()
        var params: [String: String] = [:]
        for piece in parts.dropFirst() {
            let kv = piece.split(
                separator: "=",
                maxSplits: 1,
                omittingEmptySubsequences: true
            )
            if kv.count == 2 {
                params[String(kv[0]).uppercased()] = String(kv[1])
                    .trimmingCharacters(
                        in: CharacterSet(charactersIn: "\"")
                    )
            } else if kv.count == 1 {
                // vCard3 bare type parameters: EMAIL;HOME:…
                params["TYPE"] = String(kv[0])
            }
        }
        return Property(name: name, params: params, value: value)
    }

    /// The base64 payload of an inline PHOTO, or nil when the property
    /// is not inline data. `data:` URIs are unwrapped; ENCODING=b/BASE64
    /// returns the value. Oversized payloads return nil — the bytes stay
    /// in rawPayload and the write path re-emits them verbatim.
    private static func inlinePhotoPayload(
        _ property: Property,
        _ value: String
    ) -> String? {
        let limit = 14_000_000
        let lowered = value.lowercased()
        if lowered.hasPrefix("data:"),
           let marker = lowered.range(of: ";base64,") {
            let payload = String(value[marker.upperBound...])
            return payload.count <= limit ? payload : nil
        }
        let encoding = property.params["ENCODING"]?.uppercased()
        if encoding == "B" || encoding == "BASE64" {
            return value.count <= limit ? value : nil
        }
        return nil
    }

    /// `YYYY-MM-DD`/`YYYYMMDD` with a year, `--MM-DD`/`--MMDD` without —
    /// the spellings BDAY, ANNIVERSARY, and X-ABDATE carry.
    private static func parseDate(
        _ raw: String,
        label: String?
    ) -> PIMContactDate? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        var year: Int?
        var monthDay = value
        if monthDay.hasPrefix("--") {
            monthDay = String(monthDay.dropFirst(2))
        } else {
            let head = monthDay.prefix(4)
            guard head.count == 4,
                  head.allSatisfy({ $0.isNumber }),
                  let parsedYear = Int(head)
            else { return nil }
            year = parsedYear
            monthDay = String(monthDay.dropFirst(4))
        }
        let digits = monthDay.filter { $0.isNumber }
        guard digits.count == 4,
              let month = Int(digits.prefix(2)),
              let day = Int(digits.suffix(2)),
              (1 ... 12).contains(month), (1 ... 31).contains(day)
        else { return nil }
        return PIMContactDate(
            label: label,
            year: year,
            month: month,
            day: day
        )
    }

    /// REV is an ISO timestamp — basic or extended, with or without Z.
    private static func parseRevision(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let date = Self.iso8601.date(from: trimmed) { return date }
        let digits = trimmed.filter { $0.isNumber }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = digits.count > 8
            ? "yyyyMMdd'T'HHmmss"
            : "yyyyMMdd"
        return formatter.date(from: trimmed)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension String {
    /// Decode the escape sequences vCard uses inside TEXT values.
    /// Single left-to-right pass so `\\n` stays backslash + n.
    var vCardUnescaped: String {
        var result = ""
        result.reserveCapacity(count)
        var iterator = makeIterator()
        while let character = iterator.next() {
            guard character == "\\", let escaped = iterator.next() else {
                result.append(character)
                continue
            }
            switch escaped {
            case "n", "N": result.append("\n")
            case ",": result.append(",")
            case ";": result.append(";")
            case "\\": result.append("\\")
            default:
                result.append("\\")
                result.append(escaped)
            }
        }
        return result
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
