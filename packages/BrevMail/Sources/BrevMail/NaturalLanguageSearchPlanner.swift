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
    fileprivate static let senderPrefix = #"\b(?:from|fra)(?:\s*:\s*|\s+)"#
    fileprivate static let unreadPattern = #"\b(is unread|unread|uleste?)\b"#
    fileprivate static let attachmentPattern = #"\b((?:with|has) attachments?|(?:med|har) vedlegg)\b"#
    fileprivate static let flaggedPattern = #"\b(is flagged|flagged|starred|flagget|stjernemerket)\b"#

    fileprivate static func datePattern(_ phrase: String) -> String {
        #"\b(?:(?:from|fra)\s+)?"# + NSRegularExpression.escapedPattern(for: phrase) + #"\b"#
    }

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
            workingText = removingPattern(datePattern(dateParse.matchedText), from: workingText)
            parsedChips.append(.init(
                kind: .date,
                label: String(format: String(localized: "Date: %@", bundle: .module), dateParse.matchedText),
                value: dateParse.matchedText
            ))
        }

        if let senderParse = sender(in: workingText) {
            query.from = senderParse.value
            workingText = senderParse.remainingText
            parsedChips.append(.init(
                kind: .sender,
                label: String(format: String(localized: "From: %@", bundle: .module), senderParse.value),
                value: senderParse.value
            ))
        }

        if workingText.range(of: unreadPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            query.isUnread = true
            workingText = removingPattern(unreadPattern, from: workingText)
            parsedChips.append(.init(
                kind: .unread,
                label: String(localized: "Unread", bundle: .module),
                value: "true"
            ))
        }

        if workingText.range(of: attachmentPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            query.hasAttachments = true
            workingText = removingPattern(attachmentPattern, from: workingText)
            parsedChips.append(.init(
                kind: .attachment,
                label: String(localized: "Has attachments", bundle: .module),
                value: "true"
            ))
        }

        if workingText.range(of: flaggedPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            query.isFlagged = true
            workingText = removingPattern(flaggedPattern, from: workingText)
            parsedChips.append(.init(
                kind: .flagged,
                label: String(localized: "Flagged", bundle: .module),
                value: "true"
            ))
        }

        query.text = cleanedKeywordText(workingText)

        var chips: [NaturalLanguageSearchChip] = []
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
    ) -> (range: ClosedRange<Date>, matchedText: String)? {
        for preset in MailSearchDatePreset.allCases {
            for phrase in preset.phrases where text.range(
                of: datePattern(phrase),
                options: [.regularExpression, .caseInsensitive]
            ) != nil {
                if let interval = preset.interval(at: now, calendar: calendar) {
                    return (interval.start ... interval.end.addingTimeInterval(-0.001), phrase)
                }
            }
        }
        return nil
    }

    private static func sender(in text: String) -> (value: String, remainingText: String)? {
        guard let expression = try? NSRegularExpression(
            pattern: senderPrefix + "(" + emailPattern + #"|[\p{L}][\p{L}\p{M}'’-]*)(?=\s|$)"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text),
              let fullRange = Range(match.range(at: 0), in: text)
        else {
            return nil
        }
        let value = String(text[valueRange])
        var remaining = text
        remaining.removeSubrange(fullRange)
        return (value.contains("@") ? value.lowercased() : value, cleanedKeywordText(remaining))
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

/// Memoizes `MessageListSearchQueryPolicy.plan(...).chips` per list body.
/// Chip detection runs regexes over the search text and is read several
/// times per body evaluation, so the result is cached on the inputs that
/// can change it — including the calendar day, since relative-date phrases
/// resolve against "today".
final class MessageListSearchChipsCache {
    private struct Input: Equatable {
        let text: String
        let folderID: Folder.ID?
        let execution: SearchExecution
        let searchScope: SearchScope
        let dayStart: Date
    }

    private var lastInput: Input?
    private var lastChips: [NaturalLanguageSearchChip] = []

    func chips(
        text: String,
        folderID: Folder.ID?,
        execution: SearchExecution,
        searchScope: SearchScope,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [NaturalLanguageSearchChip] {
        let input = Input(
            text: text,
            folderID: folderID,
            execution: execution,
            searchScope: searchScope,
            dayStart: calendar.startOfDay(for: now)
        )
        if input != lastInput {
            lastInput = input
            lastChips = MessageListSearchQueryPolicy.plan(
                text: text,
                folderID: folderID,
                execution: execution,
                searchScope: searchScope,
                now: now,
                calendar: calendar
            ).chips
        }
        return lastChips
    }
}

/// Memoizes unified-inbox search-chip detection per body. The chip set is
/// read several times per body evaluation; it only depends on the trimmed
/// text, the search mode (saved search vs. live), the inbox folder, the
/// execution, and "today" for relative-date phrases.
final class UnifiedInboxSearchChipsCache {
    private struct Input: Equatable {
        let text: String
        let isSavedSearch: Bool
        let inboxFolderID: Folder.ID?
        let execution: SearchExecution
        let dayStart: Date
    }

    private var lastInput: Input?
    private var lastChips: [NaturalLanguageSearchChip] = []

    func chips(
        text: String,
        isSavedSearch: Bool,
        inboxFolderID: Folder.ID?,
        execution: SearchExecution,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [NaturalLanguageSearchChip] {
        let input = Input(
            text: text,
            isSavedSearch: isSavedSearch,
            inboxFolderID: inboxFolderID,
            execution: execution,
            dayStart: calendar.startOfDay(for: now)
        )
        if input != lastInput {
            lastInput = input
            if isSavedSearch {
                lastChips = NaturalLanguageSearchPlanner.plan(
                    for: text,
                    execution: .cacheOnly,
                    now: now,
                    calendar: calendar
                ).chips
            } else {
                guard let inboxFolderID else {
                    lastChips = []
                    return lastChips
                }
                lastChips = UnifiedInboxSearchPolicy.searchPlan(
                    text: text,
                    inboxFolderID: inboxFolderID,
                    execution: execution,
                    now: now,
                    calendar: calendar
                ).chips
            }
        }
        return lastChips
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
                chips.insert(
                    .init(kind: .sender, label: String(format: String(localized: "From: %@", bundle: .module), sender),
                          value: sender),
                    at: 0
                )
            }
        case .subject:
            let subject = query.text
            query.subject = subject
            query.text = ""
            chips.removeAll { $0.kind == .keyword || $0.kind == .subject }
            if !subject.isEmpty {
                chips.insert(
                    .init(kind: .subject, label: String(format: String(localized: "Subject: %@", bundle: .module), subject),
                          value: subject),
                    at: 0
                )
            }
        case .hasAttachment:
            query.hasAttachments = true
            if !chips.contains(where: { $0.kind == .attachment }) {
                chips.append(.init(
                    kind: .attachment,
                    label: String(localized: "Has attachments", bundle: .module),
                    value: "true"
                ))
            }
        case .unread:
            query.isUnread = true
            if !chips.contains(where: { $0.kind == .unread }) {
                chips.append(.init(kind: .unread, label: String(localized: "Unread", bundle: .module), value: "true"))
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
            return removingPattern(
                NaturalLanguageSearchPlanner.senderPrefix + NSRegularExpression.escapedPattern(for: chip.value) + #"(?=\s|$)"#,
                from: text
            )
        case .date:
            return removingPattern(NaturalLanguageSearchPlanner.datePattern(chip.value), from: text)
        case .unread:
            return removingPattern(NaturalLanguageSearchPlanner.unreadPattern, from: text)
        case .attachment:
            return removingPattern(NaturalLanguageSearchPlanner.attachmentPattern, from: text)
        case .flagged:
            return removingPattern(NaturalLanguageSearchPlanner.flaggedPattern, from: text)
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

    private static func cleaned(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
