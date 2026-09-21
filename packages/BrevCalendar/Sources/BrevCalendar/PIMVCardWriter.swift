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

/// Serializes a PIMContact into a vCard blob for CardDAV writes
/// (ADR-0072 #9).
///
/// Two modes share one property emitter: a create produces a fresh
/// vCard 3.0 document (the broadest-interop version CardDAV servers
/// must accept), while an update merges the model's managed fields
/// into the contact's stored raw payload so properties Brev does not
/// understand — X-*, IMPP, social profiles, custom dates — survive the
/// round trip (the R4 unknown-field preservation rule).
public enum PIMVCardWriter {
    /// Properties the shared model owns; a merge regenerates them from
    /// the record and drops the raw copies. Everything else in the raw
    /// payload passes through verbatim.
    private static let managedProperties: Set<String> = [
        "FN", "N", "NICKNAME", "EMAIL", "TEL", "ADR", "ORG",
        "TITLE", "NOTE", "PHOTO", "CATEGORIES", "REV", "UID",
        "VERSION", "PRODID", "BEGIN", "END",
    ]

    /// A fresh vCard 3.0 document for a new contact.
    public static func vcard(
        for contact: PIMContact,
        revisedAt: Date
    ) -> String {
        var lines = [
            "BEGIN:VCARD",
            "VERSION:3.0",
            "PRODID:-//Brev//Brev Mail//EN",
        ]
        lines.append(contentsOf: managedLines(for: contact))
        lines.append(
            "REV:" + revFormatter.string(from: revisedAt)
        )
        lines.append("END:VCARD")
        return fold(lines.joined(separator: "\r\n") + "\r\n")
    }

    /// The merged vCard for an update: the raw payload with managed
    /// properties stripped and regenerated from the model. When the
    /// payload is missing or not parseable as vCard, a fresh document
    /// is produced — the update still carries every managed field.
    public static func mergedVCard(
        for contact: PIMContact,
        revisedAt: Date
    ) -> String {
        guard let raw = contact.rawPayload,
              raw.uppercased().contains("BEGIN:VCARD")
        else {
            return vcard(for: contact, revisedAt: revisedAt)
        }
        var kept: [String] = []
        var rawVersion: String?
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !trimmed.isEmpty else { continue }
            let name = propertyName(of: trimmed)
            if name == "VERSION" {
                rawVersion = String(
                    trimmed.split(separator: ":").last ?? ""
                )
            }
            if !managedProperties.contains(name) {
                kept.append(trimmed)
            }
        }
        var lines = ["BEGIN:VCARD"]
        // The stored VERSION stays authoritative — a vCard 4 source
        // keeps its version so the server parses what it wrote.
        lines.append("VERSION:" + (rawVersion ?? "3.0"))
        lines.append("PRODID:-//Brev//Brev Mail//EN")
        lines.append(contentsOf: managedLines(for: contact))
        lines.append(
            "REV:" + revFormatter.string(from: revisedAt)
        )
        lines.append(contentsOf: kept)
        lines.append("END:VCARD")
        return fold(lines.joined(separator: "\r\n") + "\r\n")
    }

    // MARK: - Managed properties

    /// The property lines the model owns, in stable order: identity
    /// first, then the repeated and structured fields.
    private static func managedLines(
        for contact: PIMContact
    ) -> [String] {
        var lines: [String] = []
        if let uid = contact.uid {
            lines.append("UID:" + escape(uid))
        }
        lines.append("FN:" + escape(contact.displayName))
        lines.append(
            "N:" + escapeComponent(contact.familyName ?? "") + ";"
                + escapeComponent(contact.givenName ?? "") + ";;;"
        )
        if let nickname = contact.nickname, !nickname.isEmpty {
            lines.append("NICKNAME:" + escape(nickname))
        }
        for field in contact.emails {
            lines.append(
                labeled("EMAIL", label: field.label) + escape(field.value)
            )
        }
        for field in contact.phones {
            lines.append(
                labeled("TEL", label: field.label) + escape(field.value)
            )
        }
        for address in contact.addresses where !address.isEmpty {
            let value =
                ";" + escapeComponent("")
                    + ";" + escapeComponent(address.street ?? "")
                    + ";" + escapeComponent(address.city ?? "")
                    + ";" + escapeComponent(address.region ?? "")
                    + ";" + escapeComponent(address.postalCode ?? "")
                    + ";" + escapeComponent(address.country ?? "")
            lines.append(
                labeled("ADR", label: address.label) + value
            )
        }
        if let organization = contact.organization,
           !organization.isEmpty {
            lines.append("ORG:" + escapeComponent(organization))
        }
        if let jobTitle = contact.jobTitle, !jobTitle.isEmpty {
            lines.append("TITLE:" + escape(jobTitle))
        }
        if let note = contact.note, !note.isEmpty {
            lines.append("NOTE:" + escape(note))
        }
        if let photoURL = contact.photoURL, !photoURL.isEmpty {
            lines.append("PHOTO;VALUE=URI:" + photoURL)
        }
        if !contact.groupKeys.isEmpty {
            lines.append(
                "CATEGORIES:"
                    + contact.groupKeys
                    .map(escapeComponent)
                    .joined(separator: ",")
            )
        }
        return lines
    }

    /// EMAIL;TYPE=work:value — the vCard3 spelling vCard4 servers also
    /// parse (TYPE is a parameter in both).
    private static func labeled(
        _ name: String,
        label: String?
    ) -> String {
        guard let label, !label.isEmpty else { return name + ":" }
        return name + ";TYPE=" + label + ":"
    }

    /// The property name of a raw line: up to the first ';' or ':',
    /// minus any vCard4 group prefix.
    private static func propertyName(of line: String) -> String {
        let lhs = line.split(
            separator: ";",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init) ?? line
        let head = lhs.split(
            separator: ":",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init) ?? lhs
        let ungrouped = head.split(
            separator: ".",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).last.map(String.init) ?? head
        return ungrouped.uppercased()
    }

    // MARK: - Escaping and folding

    /// RFC 6350 TEXT escaping: backslash, comma, semicolon, newline.
    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Structured-value (N/ADR/ORG/CATEGORIES) escaping — identical to
    /// TEXT escaping; components keep their separators.
    private static func escapeComponent(_ value: String) -> String {
        escape(value)
    }

    /// RFC 6350 75-octet folding that never splits a multi-byte UTF-8
    /// sequence — the continuation line starts at the lead byte.
    private static func fold(_ text: String) -> String {
        text.components(separatedBy: "\r\n")
            .map(foldLine)
            .joined(separator: "\r\n")
    }

    private static func foldLine(_ line: String) -> String {
        var bytes = Array(line.utf8)
        guard bytes.count > 75 else { return line }
        var folded = ""
        var first = true
        while !bytes.isEmpty {
            var take = min(first ? 75 : 74, bytes.count)
            // Back off to the lead byte when the cut lands inside a
            // multi-byte sequence (continuation bytes match 10xxxxxx).
            while take > 0,
                  take < bytes.count,
                  (bytes[take] & 0xC0) == 0x80 {
                take -= 1
            }
            let chunk = bytes.prefix(take)
            folded += String(decoding: chunk, as: UTF8.self)
            bytes = Array(bytes.dropFirst(take))
            if !bytes.isEmpty {
                folded += "\r\n "
            }
            first = false
        }
        return folded
    }

    private static let revFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
