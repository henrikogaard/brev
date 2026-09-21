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
/// FN, N, NICKNAME, EMAIL, TEL, ADR, ORG, TITLE, NOTE, PHOTO (URI only),
/// CATEGORIES, REV, UID — and leaves everything else to the record's
/// `rawPayload` for round-trip preservation.
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
        var photoURL: String?
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
        case "PHOTO":
            // Only URI references are stored; inline ENCODING=b payloads
            // stay in rawPayload and are never decoded or fetched here.
            if property.params["VALUE"]?.uppercased() == "URI",
               value.lowercased().hasPrefix("https://") {
                contact.photoURL = value
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
    /// servers still emit (`=\n` line continuations).
    private static func unfold(_ raw: String) -> [String] {
        raw
            .replacingOccurrences(of: "=\r\n", with: "")
            .replacingOccurrences(of: "=\n", with: "")
            .replacingOccurrences(of: "=\r", with: "")
            .replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
