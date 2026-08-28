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

import BrevBackend
import Foundation

/// A single labeled field shown in the message Properties sheet.
struct MessagePropertyRow: Equatable, Identifiable, Sendable {
    let label: String
    let value: String

    var id: String { label }
}

/// Builds the read-only metadata rows shown when the user picks
/// "Properties…" from a message context menu. All data comes from the
/// already-loaded `MessageHeader`; no backend fetch is required, so the
/// sheet works offline and in demo mode.
enum MessagePropertiesPresentation {
    /// Formats one correspondent as `Name <email>`, or just the address
    /// when no display name is available.
    static func formatted(_ correspondent: Correspondent) -> String {
        let name = correspondent.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return correspondent.email }
        return "\(name) <\(correspondent.email)>"
    }

    /// Joins a recipient list into a single comma-separated value.
    static func formatted(_ correspondents: [Correspondent]) -> String {
        correspondents.map(formatted).joined(separator: ", ")
    }

    /// The default localized date string used for the Date row.
    static func dateText(for date: Date) -> String {
        date.formatted(date: .long, time: .shortened)
    }

    /// Builds the ordered rows. Empty recipient lists and absent
    /// attachments are omitted so the sheet shows only meaningful fields.
    /// - Parameter dateText: the localized date string (injected so the
    ///   row layout stays deterministic and unit-testable).
    static func rows(for header: MessageHeader, dateText: String) -> [MessagePropertyRow] {
        var rows: [MessagePropertyRow] = [
            MessagePropertyRow(label: "From", value: formatted(header.from))
        ]
        if !header.to.isEmpty {
            rows.append(MessagePropertyRow(label: "To", value: formatted(header.to)))
        }
        if !header.cc.isEmpty {
            rows.append(MessagePropertyRow(label: "Cc", value: formatted(header.cc)))
        }
        if !header.bcc.isEmpty {
            rows.append(MessagePropertyRow(label: "Bcc", value: formatted(header.bcc)))
        }
        rows.append(MessagePropertyRow(label: "Date", value: dateText))
        let subject = header.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        rows.append(MessagePropertyRow(label: "Subject", value: subject.isEmpty ? "(No subject)" : subject))
        if header.hasAttachments {
            rows.append(MessagePropertyRow(label: "Attachments", value: "Yes"))
        }
        return rows
    }
}
