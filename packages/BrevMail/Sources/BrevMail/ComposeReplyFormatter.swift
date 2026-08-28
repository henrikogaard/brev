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

enum ComposeReplyQuotePlacement: String, Sendable {
    case belowReply
    case aboveReply

    static let storageKey = "compose.quotePlacement"

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let value = defaults.string(forKey: storageKey),
              let placement = Self(rawValue: value) else {
            return .belowReply
        }
        return placement
    }
}

enum ComposeReplyFormatter {
    static func subject(for original: String) -> String {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("re:") { return trimmed }
        return "Re: \(displaySubject(trimmed))"
    }

    static func body(
        for header: MessageHeader,
        quoteText: String? = nil,
        placement: ComposeReplyQuotePlacement = .belowReply
    ) -> String {
        let quoteHeader = "On \(format(header.date)), \(format(header.from)) wrote:"
        let quotedSnippet = quoteLines(from: quoteText ?? header.snippet)

        switch placement {
        case .belowReply:
            var lines = ["", "", quoteHeader]
            lines.append(contentsOf: quotedSnippet)
            return lines.joined(separator: "\n")
        case .aboveReply:
            var lines = [quoteHeader]
            lines.append(contentsOf: quotedSnippet)
            lines.append(contentsOf: ["", ""])
            return lines.joined(separator: "\n")
        }
    }

    private static func quoteLines(from snippet: String) -> [String] {
        let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return trimmed
            .components(separatedBy: .newlines)
            .map { "> \($0)" }
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
