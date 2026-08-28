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

struct NaturalLanguageSearchChip: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable {
        case keyword
        case sender
        case subject
        case date
        case unread
        case attachment
        case flagged
    }

    let kind: Kind
    let label: String
    let value: String

    var id: String { "\(kind.rawValue):\(value)" }
}

struct NaturalLanguageSearchPlan: Equatable, Sendable {
    let originalText: String
    let query: SearchQuery
    let chips: [NaturalLanguageSearchChip]
    let requiresAI: Bool
}

enum NaturalLanguageSearchPlanner {
    private static let emailPattern = #"[A-Z0-9._%+\-']+@[A-Z0-9.\-]+\.[A-Z]{2,}"#

    static func plan(
        for text: String,
        folderID: Folder.ID? = nil,
        execution: SearchExecution,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> NaturalLanguageSearchPlan {
        let originalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var workingText = originalText
        var query = SearchQuery(folderID: folderID, execution: execution)
        var parsedChips: [NaturalLanguageSearchChip] = []

        if let dateParse = dateRange(in: workingText, now: now, calendar: calendar) {
            query.dateRange = dateParse.range
            workingText = removing(dateParse.matchedText, from: workingText)
            parsedChips.append(.init(
                kind: .date,
                label: "Date: \(dateParse.label)",
                value: dateParse.label
            ))
        }

        if let senderParse = sender(in: workingText) {
            query.from = senderParse.email
            workingText = senderParse.remainingText
            parsedChips.append(.init(
                kind: .sender,
                label: "From: \(senderParse.email)",
                value: senderParse.email
            ))
        }

        if containsPhrase(in: workingText, patterns: [
            #"\bis unread\b"#,
            #"\bunread\b"#,
        ]) {
            query.isUnread = true
            workingText = removingPattern(#"\b(is unread|unread)\b"#, from: workingText)
            parsedChips.append(.init(
                kind: .unread,
                label: "Unread",
                value: "true"
            ))
        }

        if containsPhrase(in: workingText, patterns: [
            #"\bwith attachments?\b"#,
            #"\bhas attachments?\b"#,
        ]) {
            query.hasAttachments = true
            workingText = removingPattern(#"\b(with|has) attachments?\b"#, from: workingText)
            parsedChips.append(.init(
                kind: .attachment,
                label: "Has attachments",
                value: "true"
            ))
        }

        if containsPhrase(in: workingText, patterns: [
            #"\bis flagged\b"#,
            #"\bflagged\b"#,
            #"\bstarred\b"#,
        ]) {
            query.isFlagged = true
            workingText = removingPattern(#"\b(is flagged|flagged|starred)\b"#, from: workingText)
            parsedChips.append(.init(
                kind: .flagged,
                label: "Flagged",
                value: "true"
            ))
        }

        query.text = cleanedKeywordText(workingText)

        var chips: [NaturalLanguageSearchChip] = []
        if !query.text.isEmpty {
            chips.append(.init(
                kind: .keyword,
                label: "Keyword: \(query.text)",
                value: query.text
            ))
        }
        chips.append(contentsOf: parsedChips)

        return NaturalLanguageSearchPlan(
            originalText: originalText,
            query: query,
            chips: chips,
            requiresAI: false
        )
    }

    static func inferredSender(
        from text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let plan = plan(for: text, execution: .cacheOnly, now: now, calendar: calendar)
        return plan.query.from ?? plan.query.text
    }

    private static func dateRange(
        in text: String,
        now: Date,
        calendar: Calendar
    ) -> (range: ClosedRange<Date>, matchedText: String, label: String)? {
        let normalized = text.lowercased()
        if normalized.range(of: #"\blast month\b"#, options: .regularExpression) != nil,
           let currentMonth = calendar.dateInterval(of: .month, for: now),
           let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: currentMonth.start),
           let previousMonth = calendar.dateInterval(of: .month, for: previousMonthStart) {
            return (
                previousMonth.start ... previousMonth.end.addingTimeInterval(-0.001),
                "last month",
                "last month"
            )
        }
        if normalized.range(of: #"\bthis month\b"#, options: .regularExpression) != nil,
           let currentMonth = calendar.dateInterval(of: .month, for: now) {
            return (
                currentMonth.start ... currentMonth.end.addingTimeInterval(-0.001),
                "this month",
                "this month"
            )
        }
        if normalized.range(of: #"\btoday\b"#, options: .regularExpression) != nil,
           let today = calendar.dateInterval(of: .day, for: now) {
            return (
                today.start ... today.end.addingTimeInterval(-0.001),
                "today",
                "today"
            )
        }
        if normalized.range(of: #"\byesterday\b"#, options: .regularExpression) != nil,
           let today = calendar.dateInterval(of: .day, for: now),
           let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: today.start),
           let yesterday = calendar.dateInterval(of: .day, for: yesterdayStart) {
            return (
                yesterday.start ... yesterday.end.addingTimeInterval(-0.001),
                "yesterday",
                "yesterday"
            )
        }
        if normalized.range(of: #"\blast week\b"#, options: .regularExpression) != nil,
           let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now),
           let previousWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeek.start),
           let previousWeek = calendar.dateInterval(of: .weekOfYear, for: previousWeekStart) {
            return (
                previousWeek.start ... previousWeek.end.addingTimeInterval(-0.001),
                "last week",
                "last week"
            )
        }
        return nil
    }

    private static func sender(in text: String) -> (email: String, remainingText: String)? {
        guard let expression = try? NSRegularExpression(
            pattern: #"\bfrom(?:\s*:\s*|\s+)("# + emailPattern + #")\b"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let emailRange = Range(match.range(at: 1), in: text),
              let fullRange = Range(match.range(at: 0), in: text)
        else {
            return nil
        }
        let email = String(text[emailRange]).lowercased()
        var remaining = text
        remaining.removeSubrange(fullRange)
        return (email, cleanedKeywordText(remaining))
    }

    private static func removing(_ phrase: String, from text: String) -> String {
        removingPattern(#"\b"# + NSRegularExpression.escapedPattern(for: phrase) + #"\b"#, from: text)
    }

    private static func removingPattern(_ pattern: String, from text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: " "
        )
    }

    private static func containsPhrase(in text: String, patterns: [String]) -> Bool {
        patterns.contains { pattern in
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private static func cleanedKeywordText(_ text: String) -> String {
        var words = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while let trailing = words.split(separator: " ").last,
              ["from", "in", "during", "on", "with", "to"].contains(trailing.lowercased()) {
            words = words
                .dropLast(trailing.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return words
    }
}

enum MessageListSearchQueryPolicy {
    static func plan(
        text: String,
        folderID: Folder.ID?,
        execution: SearchExecution,
        searchScope: SearchScope,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> NaturalLanguageSearchPlan {
        let parsedPlan = NaturalLanguageSearchPlanner.plan(
            for: text,
            folderID: folderID,
            execution: execution,
            now: now,
            calendar: calendar
        )
        var query = parsedPlan.query
        var chips = parsedPlan.chips

        switch searchScope {
        case .all:
            break
        case .from:
            let sender = query.from ?? NaturalLanguageSearchPlanner.inferredSender(
                from: text,
                now: now,
                calendar: calendar
            )
            query.from = sender
            query.text = ""
            chips.removeAll { $0.kind == .keyword || $0.kind == .sender }
            if !sender.isEmpty {
                chips.insert(.init(kind: .sender, label: "From: \(sender)", value: sender), at: 0)
            }
        case .subject:
            let subject = query.text
            query.subject = subject
            query.text = ""
            chips.removeAll { $0.kind == .keyword || $0.kind == .subject }
            if !subject.isEmpty {
                chips.insert(.init(kind: .subject, label: "Subject: \(subject)", value: subject), at: 0)
            }
        case .hasAttachment:
            query.hasAttachments = true
            if !chips.contains(where: { $0.kind == .attachment }) {
                chips.append(.init(kind: .attachment, label: "Has attachments", value: "true"))
            }
        case .unread:
            query.isUnread = true
            if !chips.contains(where: { $0.kind == .unread }) {
                chips.append(.init(kind: .unread, label: "Unread", value: "true"))
            }
        }

        return NaturalLanguageSearchPlan(
            originalText: parsedPlan.originalText,
            query: query,
            chips: chips,
            requiresAI: parsedPlan.requiresAI
        )
    }

    static func query(
        text: String,
        folderID: Folder.ID?,
        execution: SearchExecution,
        searchScope: SearchScope,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SearchQuery {
        plan(
            text: text,
            folderID: folderID,
            execution: execution,
            searchScope: searchScope,
            now: now,
            calendar: calendar
        ).query
    }
}

extension UnifiedInboxSearchPolicy {
    static func searchPlan(
        text: String,
        inboxFolderID: Folder.ID,
        execution: SearchExecution,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> NaturalLanguageSearchPlan {
        NaturalLanguageSearchPlanner.plan(
            for: text,
            folderID: inboxFolderID,
            execution: execution,
            now: now,
            calendar: calendar
        )
    }
}

enum NaturalLanguageSearchChipEditing {
    static func removing(
        _ chip: NaturalLanguageSearchChip,
        from text: String
    ) -> String {
        switch chip.kind {
        case .keyword, .subject:
            return removingLiteral(chip.value, from: text)
        case .sender:
            return removingPattern(#"\bfrom\s+"# + emailPattern(for: chip.value) + #"\b"#, from: text)
        case .date:
            return removingLiteral(chip.value, from: text)
        case .unread:
            return removingPattern(#"\b(is unread|unread)\b"#, from: text)
        case .attachment:
            return removingPattern(#"\b(with|has) attachments?\b"#, from: text)
        case .flagged:
            return removingPattern(#"\b(is flagged|flagged|starred)\b"#, from: text)
        }
    }

    private static func removingLiteral(_ literal: String, from text: String) -> String {
        guard !literal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return cleaned(text)
        }
        return removingPattern(NSRegularExpression.escapedPattern(for: literal), from: text)
    }

    private static func removingPattern(_ pattern: String, from text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return cleaned(text)
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        let edited = expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: " "
        )
        return cleaned(edited)
    }

    private static func emailPattern(for email: String) -> String {
        NSRegularExpression.escapedPattern(for: email)
    }

    private static func cleaned(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
