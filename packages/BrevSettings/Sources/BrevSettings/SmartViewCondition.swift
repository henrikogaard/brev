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

/// How a Smart View combines its conditions.
public enum SmartViewMatchMode: String, Codable, CaseIterable, Sendable {
    case all, any
}

/// One editable condition evaluated against locally available message headers.
public struct SmartViewCondition: Codable, Equatable, Sendable, Identifiable {
    /// Header fields supported by the local Smart View evaluator.
    public enum Field: String, Codable, CaseIterable, Sendable {
        case text, from, recipients, subject, received, isRead, isFlagged, isAnswered, hasAttachments, mailbox, folder
    }

    /// Comparisons supported by each condition field.
    public enum Comparison: String, Codable, CaseIterable, Sendable {
        case contains, doesNotContain, beginsWith, endsWith, equals, notEquals
        case isTrue, isFalse, before, after, onDate, inLastDays
    }

    public var id: String
    public var field: Field
    public var comparison: Comparison
    public var value: String
    public var date: Date
    public var sourceID: MailSourceID?

    /// Creates a condition; mailbox and folder conditions retain source ownership.
    public init(id: String = UUID().uuidString, field: Field = .from,
                comparison: Comparison = .contains, value: String = "",
                date: Date = Date(), sourceID: MailSourceID? = nil) {
        self.id = id
        self.field = field
        self.comparison = comparison
        self.value = value
        self.date = date
        self.sourceID = sourceID
    }

    /// Whether the condition can be evaluated without guessing a missing input.
    public var isValid: Bool {
        guard field.comparisons.contains(comparison) else { return false }
        switch field {
        case .isRead, .isFlagged, .isAnswered, .hasAttachments: return true
        case .received:
            return comparison != .inLastDays || (Int(value).map { (1 ... 36500).contains($0) } ?? false)
        case .mailbox: return sourceID != nil
        case .folder: return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Evaluates this condition using only cached header metadata.
    public func matches(_ header: MessageHeader, sourceID: MailSourceID? = nil,
                        folderIDs: Set<String>? = nil, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isValid else { return false }
        switch field {
        case .isRead: return header.isRead == (comparison == .isTrue)
        case .isFlagged: return header.isFlagged == (comparison == .isTrue)
        case .isAnswered: return header.isAnswered == (comparison == .isTrue)
        case .hasAttachments: return header.hasAttachments == (comparison == .isTrue)
        case .mailbox:
            let matches = self.sourceID == sourceID
            return comparison == .notEquals ? !matches : matches
        case .folder:
            let inFolder = folderIDs?.contains(value) ?? (header.folderID == value)
            let matches = inFolder && (self.sourceID == nil || self.sourceID == sourceID)
            return comparison == .notEquals ? !matches : matches
        case .received:
            let day = calendar.startOfDay(for: header.date)
            let target = calendar.startOfDay(for: date)
            switch comparison {
            case .before: return day < target
            case .after: return day > target
            case .onDate: return day == target
            case .inLastDays:
                guard let days = Int(value),
                      let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))
                else { return false }
                return header.date >= start && header.date <= now
            default: return false
            }
        default:
            return matchesText(in: textValues(header))
        }
    }

    private func textValues(_ header: MessageHeader) -> [String] {
        switch field {
        case .from: return [header.from.email, header.from.name ?? ""]
        case .recipients:
            return (header.to + header.cc + header.bcc).flatMap { [$0.email, $0.name ?? ""] }
        case .subject: return [header.subject]
        default:
            return [header.subject, header.snippet, header.from.email, header.from.name ?? ""]
                + (header.to + header.cc + header.bcc).flatMap { [$0.email, $0.name ?? ""] }
        }
    }

    private func matchesText(in values: [String]) -> Bool {
        let locale = Locale(identifier: "en_US_POSIX")
        let needle = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
        let matched = values.contains { text in
            let text = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            switch comparison {
            case .equals, .notEquals: return text == needle
            case .beginsWith: return text.hasPrefix(needle)
            case .endsWith: return text.hasSuffix(needle)
            default: return text.contains(needle)
            }
        }
        return comparison == .doesNotContain || comparison == .notEquals ? !matched : matched
    }
}

public extension SmartViewCondition.Field {
    /// Comparisons that make sense for this field.
    var comparisons: [SmartViewCondition.Comparison] {
        switch self {
        case .isRead, .isFlagged, .isAnswered, .hasAttachments: return [.isTrue, .isFalse]
        case .received: return [.inLastDays, .before, .after, .onDate]
        case .mailbox, .folder: return [.equals, .notEquals]
        default: return [.contains, .doesNotContain, .beginsWith, .endsWith, .equals, .notEquals]
        }
    }
}

public extension SmartMailbox.SavedQuery {
    /// Evaluates current condition groups or a legacy saved search without server calls.
    func matches(_ header: MessageHeader, sourceID: MailSourceID? = nil,
                 folderRole: FolderRole? = nil, folderIDs: Set<String>? = nil, now: Date = Date(),
                 calendar: Calendar = .current) -> Bool {
        if includeTrash == false, folderRole == .trash || header.labels.contains("\\Trash") { return false }
        if includeSent == false, folderRole == .sent || header.labels.contains("\\Sent") { return false }
        guard let conditions else { return searchQuery.matches(header) }
        guard !conditions.isEmpty, conditions.allSatisfy(\.isValid) else { return false }
        let matches: (SmartViewCondition) -> Bool = {
            $0.matches(header, sourceID: sourceID, folderIDs: folderIDs, now: now, calendar: calendar)
        }
        return matchMode == .any ? conditions.contains(where: matches) : conditions.allSatisfy(matches)
    }

    /// Converts legacy predicates into editable conditions without losing false values or folder scope.
    var editableConditions: [SmartViewCondition] {
        if let conditions { return conditions }
        var result: [SmartViewCondition] = []
        if !text.isEmpty { result.append(.init(field: .text, value: text)) }
        if let from { result.append(.init(field: .from, value: from)) }
        if let to { result.append(.init(field: .recipients, value: to)) }
        if let folderID { result.append(.init(field: .folder, comparison: .equals, value: folderID)) }
        if let hasAttachment { result.append(.init(field: .hasAttachments, comparison: hasAttachment ? .isTrue : .isFalse)) }
        if let isUnread { result.append(.init(field: .isRead, comparison: isUnread ? .isFalse : .isTrue)) }
        if let isStarred { result.append(.init(field: .isFlagged, comparison: isStarred ? .isTrue : .isFalse)) }
        return result
    }
}
