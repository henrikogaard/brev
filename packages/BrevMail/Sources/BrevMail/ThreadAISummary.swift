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

import BrevAI
import BrevBackend
import Foundation

struct ThreadAISummaryAvailabilityState: Equatable, Sendable {
    let settings: AIWriterSettings
    let hasProviderBackend: Bool
    let isBusy: Bool
    let hasActiveRequest: Bool
    let messageCount: Int
}

enum ThreadAISummaryDisabledReason: Equatable, Sendable {
    case missingBackend
    case notEnabled
    case consentRequired
    case busy
    case requestInFlight
    case messageRequired

    var title: String {
        switch self {
        case .missingBackend:
            "Thread summaries need an AI provider for this account."
        case .notEnabled:
            "AI is turned off."
        case .consentRequired:
            "AI needs consent before sending message text."
        case .busy:
            "Finish the current mail action first."
        case .requestInFlight:
            "A thread summary is already running."
        case .messageRequired:
            "Open a thread before summarizing."
        }
    }
}

enum ThreadAISummaryAvailability {
    static func disabledReason(
        in state: ThreadAISummaryAvailabilityState
    ) -> ThreadAISummaryDisabledReason? {
        if !state.hasProviderBackend { return .missingBackend }
        if !state.settings.isEnabled { return .notEnabled }
        if !state.settings.consentGiven { return .consentRequired }
        if state.isBusy { return .busy }
        if state.hasActiveRequest { return .requestInFlight }
        if state.messageCount <= 0 { return .messageRequired }
        return nil
    }
}

struct ThreadAISummaryContext: Equatable, Sendable {
    let messages: [AIMessage]
    let instruction: String
    let includedMessageCount: Int
    let totalMessageCount: Int
    let wasTruncated: Bool
}

enum ThreadAISummaryContextBuilder {
    static let defaultMaxMessages = AISafetyPolicy.maxSourceMessages
    static let defaultMaxCharacters = AISafetyPolicy.maxTotalContextBytes

    static func includedHeaders(
        from headers: [MessageHeader],
        maxMessages: Int = defaultMaxMessages
    ) -> [MessageHeader] {
        guard maxMessages > 0, headers.count > maxMessages else {
            return headers
        }
        return Array(headers.suffix(maxMessages))
    }

    static func context(
        headers: [MessageHeader],
        bodies: [MessageHeader.ID: MessageBody],
        maxMessages: Int = defaultMaxMessages,
        maxCharacters: Int = defaultMaxCharacters
    ) -> ThreadAISummaryContext? {
        let includedHeaders = includedHeaders(from: headers, maxMessages: maxMessages)
        guard !includedHeaders.isEmpty else { return nil }

        let omittedCount = max(0, headers.count - includedHeaders.count)
        var parts: [String] = []
        if omittedCount > 0 {
            parts.append("\(omittedCount) older messages omitted from this bounded summary window.")
        }
        for (offset, header) in includedHeaders.enumerated() {
            parts.append(messageContext(
                index: offset + 1,
                header: header,
                body: bodies[header.id]
            ))
        }

        let content = truncated(parts.joined(separator: "\n\n"), maxCharacters: maxCharacters)
        return ThreadAISummaryContext(
            messages: [AIMessage(role: .user, content: content)],
            instruction: [
                "Summarize the provided email thread for the user.",
                "Return a concise 'Summary' section with bullets and a separate 'Next actions' section.",
                "If there are no clear next actions, write 'None' under Next actions.",
                "Do not invent facts or commitments."
            ].joined(separator: " "),
            includedMessageCount: includedHeaders.count,
            totalMessageCount: headers.count,
            wasTruncated: omittedCount > 0 || content.hasSuffix("...")
        )
    }

    private static func messageContext(
        index: Int,
        header: MessageHeader,
        body: MessageBody?
    ) -> String {
        [
            "Message \(index)",
            "From: \(displayString(header.from))",
            "Date: \(ISO8601DateFormatter().string(from: header.date))",
            "Subject: \(cleaned(header.subject))",
            "Body: \(bodyText(body, fallback: header.snippet))"
        ]
        .filter { !$0.hasSuffix(": ") }
        .joined(separator: "\n")
    }

    private static func bodyText(_ body: MessageBody?, fallback: String) -> String {
        let plainText = cleaned(body?.plainText)
        if !plainText.isEmpty {
            return plainText
        }
        let html = cleaned(body?.html)
        if !html.isEmpty {
            return html
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned(fallback)
    }

    private static func displayString(_ correspondent: Correspondent) -> String {
        let name = cleaned(correspondent.name)
        guard !name.isEmpty else {
            return correspondent.email
        }
        return "\(name) <\(correspondent.email)>"
    }

    private static func truncated(_ text: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0, text.count > maxCharacters else {
            return text
        }
        let endIndex = text.index(text.startIndex, offsetBy: max(0, maxCharacters - 3))
        return String(text[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func cleaned(_ text: String?) -> String {
        text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct ThreadAISummaryPresentation: Equatable, Sendable {
    let summaryBullets: [String]
    let nextActions: [String]
    let providerLabel: String
    let contextNote: String?

    static func make(
        responseText: String,
        providerLabel: String,
        wasTruncated: Bool
    ) -> ThreadAISummaryPresentation {
        let sections = SummarySectionParser.sections(from: responseText)
        let summary = sections.summary.isEmpty
            ? SummarySectionParser.bullets(from: responseText)
            : sections.summary
        return ThreadAISummaryPresentation(
            summaryBullets: summary,
            nextActions: sections.nextActions,
            providerLabel: providerLabel,
            contextNote: wasTruncated ? "Summarized a bounded thread window." : nil
        )
    }
}

private enum SummarySectionParser {
    static func sections(from text: String) -> (summary: [String], nextActions: [String]) {
        enum Section {
            case summary
            case nextActions
        }

        var current: Section = .summary
        var summary: [String] = []
        var nextActions: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let normalizedHeading = line
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            if normalizedHeading == "summary" {
                current = .summary
                continue
            }
            if ["next actions", "action items", "actions"].contains(normalizedHeading) {
                current = .nextActions
                continue
            }

            let bullet = cleanedBullet(line)
            switch current {
            case .summary:
                summary.append(bullet)
            case .nextActions:
                if bullet.lowercased() != "none" {
                    nextActions.append(bullet)
                }
            }
        }

        return (summary, nextActions)
    }

    static func bullets(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { cleanedBullet($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }

    private static func cleanedBullet(_ line: String) -> String {
        line.replacingOccurrences(
            of: #"^[-*•]\s*"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ThreadAISummaryRequest: Equatable, Sendable {
    let threadID: String?
    let messageIDs: [MessageHeader.ID]
}

enum ThreadAISummaryState: Equatable, Sendable {
    case loading(providerLabel: String)
    case success(ThreadAISummaryPresentation)
    case failure(message: String, providerLabel: String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

enum ThreadAISummaryErrorPresentation {
    static func message(for error: any Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Couldn't summarize this thread." : "Couldn't summarize this thread: \(message)"
    }
}
