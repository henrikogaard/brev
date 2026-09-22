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

/// Serializes a `PIMTask` into an RFC 5545 `VCALENDAR`/`VTODO`
/// payload for CalDAV PUT and as the interchange form for edits
/// (ADR-0072 #12).
///
/// The writer emits the fields the shared model owns: UID, DTSTAMP,
/// SUMMARY, DESCRIPTION, DUE (UTC timestamp — the model carries no
/// all-day flag), COMPLETED, STATUS, X-APPLE-SORT-ORDER,
/// RELATED-TO;RELTYPE=PARENT, URL, and LAST-MODIFIED. Provider payload
/// fields the model does not read are preserved separately via
/// `PIMTask.rawPayload`; this writer emits a clean canonical VTODO.
public enum PIMTaskICSWriter {
    /// Serializes one task as a complete VCALENDAR document with CRLF
    /// line endings and 75-octet folding.
    ///
    /// - Parameters:
    ///   - task: The task to serialize. `uid` falls back to the
    ///     provider item key when absent.
    ///   - dtstamp: The DTSTAMP value — injectable for tests.
    public static func vcalendar(
        for task: PIMTask,
        dtstamp: Date = Date()
    ) -> String {
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:\(PIMEventICSWriter.productID)",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "BEGIN:VTODO",
        ]
        lines.append("UID:" + (task.uid ?? task.providerItemKey))
        lines.append("DTSTAMP:" + utcStamp(dtstamp))
        if let summary = task.title, !summary.isEmpty {
            lines.append("SUMMARY:" + escape(summary))
        }
        if let notes = task.notes, !notes.isEmpty {
            lines.append("DESCRIPTION:" + escape(notes))
        }
        if let due = task.due {
            lines.append("DUE:" + utcStamp(due))
        }
        if let completedAt = task.completedAt {
            lines.append("COMPLETED:" + utcStamp(completedAt))
        }
        lines.append("STATUS:" + statusText(task.status))
        if task.status == .completed {
            // PERCENT-COMPLETE is implied by STATUS:COMPLETED; emit it
            // so clients that filter on percent see the task as done.
            lines.append("PERCENT-COMPLETE:100")
        }
        if let position = task.position, !position.isEmpty {
            lines.append("X-APPLE-SORT-ORDER:" + position)
        }
        if let parentKey = task.parentKey, !parentKey.isEmpty {
            lines.append("RELATED-TO;RELTYPE=PARENT:" + parentKey)
        }
        for link in task.links where !link.isEmpty {
            lines.append("URL:" + link)
        }
        if let updated = task.providerUpdatedAt {
            lines.append("LAST-MODIFIED:" + utcStamp(updated))
        }
        lines.append("END:VTODO")
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    // MARK: - Status

    private static func statusText(_ status: PIMTaskStatus) -> String {
        switch status {
        case .needsAction: "NEEDS-ACTION"
        case .inProcess: "IN-PROCESS"
        case .completed: "COMPLETED"
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

    /// "yyyyMMddTHHmmssZ" in UTC — DUE/COMPLETED/DTSTAMP/LAST-MODIFIED.
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
}
