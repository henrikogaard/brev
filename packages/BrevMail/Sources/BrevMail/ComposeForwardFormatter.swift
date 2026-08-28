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

enum ComposeForwardFormatter {
    static func subject(for original: String) -> String {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("fwd:") { return trimmed }
        return "Fwd: \(displaySubject(trimmed))"
    }

    static func body(
        for header: MessageHeader,
        quoteText: String? = nil
    ) -> String {
        var lines = [
            "",
            "",
            "---------- Forwarded message ----------",
            "From: \(format(header.from))",
            "Date: \(format(header.date))",
            "Subject: \(displaySubject(header.subject))"
        ]

        append("To", recipients: header.to, to: &lines)
        append("Cc", recipients: header.cc, to: &lines)

        let snippet = (quoteText ?? header.snippet)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !snippet.isEmpty {
            lines.append("")
            lines.append(snippet)
        }

        return lines.joined(separator: "\n")
    }

    private static func append(
        _ label: String,
        recipients: [Correspondent],
        to lines: inout [String]
    ) {
        guard !recipients.isEmpty else { return }
        lines.append("\(label): \(recipients.map(format).joined(separator: ", "))")
    }

    private static func format(_ correspondent: Correspondent) -> String {
        let email = correspondent.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = correspondent.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != email else { return email }
        return "\(name) <\(email)>"
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "d MMM yyyy 'at' HH:mm 'UTC'"
        return formatter.string(from: date)
    }

    private static func displaySubject(_ subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(no subject)" : trimmed
    }
}
