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

/// The message field a typed query is matched against once a field token is active.
enum MailSearchTextField: String, Hashable, Sendable {
    case from
    case subject

    /// The list's field scope that applies this token to the typed text.
    var searchScope: SearchScope {
        switch self {
        case .from: .from
        case .subject: .subject
        }
    }

    var title: String {
        switch self {
        case .from: String(localized: "From", bundle: .module)
        case .subject: String(localized: "Subject", bundle: .module)
        }
    }
}

/// The relative date ranges the natural-language planner understands.
enum MailSearchDatePreset: String, CaseIterable, Hashable, Sendable {
    case today
    case yesterday
    case lastWeek
    case thisMonth
    case lastMonth

    /// The phrase `NaturalLanguageSearchPlanner` turns into a date range.
    var phrase: String {
        switch self {
        case .today: "today"
        case .yesterday: "yesterday"
        case .lastWeek: "last week"
        case .thisMonth: "this month"
        case .lastMonth: "last month"
        }
    }

    init?(phrase: String) {
        guard let preset = Self.allCases.first(where: { $0.phrase == phrase.lowercased() }) else { return nil }
        self = preset
    }

    var title: String {
        switch self {
        case .today: String(localized: "Today", bundle: .module)
        case .yesterday: String(localized: "Yesterday", bundle: .module)
        case .lastWeek: String(localized: "Last week", bundle: .module)
        case .thisMonth: String(localized: "This month", bundle: .module)
        case .lastMonth: String(localized: "Last month", bundle: .module)
        }
    }
}

/// A search predicate shown as a token in the iOS search field (audit Q2).
///
/// Predicate tokens compose into the phrases the natural-language planner already parses, so
/// every list, the debounce, the cache key and the saved-search path keep reading one query
/// string. A field token adds no phrase; it scopes the typed text to one message field.
enum MailSearchToken: Hashable, Identifiable, Sendable {
    case field(MailSearchTextField)
    case sender(email: String, name: String?)
    case unread
    case flagged
    case hasAttachment
    case date(MailSearchDatePreset)

    var id: String {
        switch self {
        case .field(let field): "field:\(field.rawValue)"
        case .sender(let email, _): "sender:\(email.lowercased())"
        case .unread: "unread"
        case .flagged: "flagged"
        case .hasAttachment: "attachment"
        case .date(let preset): "date:\(preset.rawValue)"
        }
    }

    /// The text shown in the token and read by VoiceOver.
    var title: String {
        switch self {
        case .field(let field):
            field.title
        case .sender(let email, let name):
            String(format: String(localized: "From: %@", bundle: .module), name?.isEmpty == false ? name! : email)
        case .unread:
            String(localized: "Unread", bundle: .module)
        case .flagged:
            String(localized: "Flagged", bundle: .module)
        case .hasAttachment:
            String(localized: "Has attachments", bundle: .module)
        case .date(let preset):
            preset.title
        }
    }

    var symbolName: String {
        switch self {
        case .field(.from), .sender: "person"
        case .field(.subject): "text.alignleft"
        case .unread: "envelope.badge"
        case .flagged: "flag"
        case .hasAttachment: "paperclip"
        case .date: "calendar"
        }
    }

    /// What the planner reads for this token; nil for a field token.
    fileprivate var queryPhrase: String? {
        switch self {
        case .field: nil
        case .sender(let email, _): "from \(email)"
        case .unread: "unread"
        case .flagged: "flagged"
        case .hasAttachment: "has attachments"
        case .date(let preset): preset.phrase
        }
    }
}

/// Whether a mailbox list searches only the open folder or every mailbox.
enum MailSearchMailboxScope: Hashable, Sendable {
    case currentMailbox
    case allMailboxes

    init(searchesAllFolders: Bool) {
        self = searchesAllFolders ? .allMailboxes : .currentMailbox
    }

    var searchesAllFolders: Bool { self == .allMailboxes }
}

enum MailSearchTokens {
    /// The single query string the lists search with: token phrases first, then the typed text.
    static func composedText(freeText: String, tokens: [MailSearchToken]) -> String {
        let phrases = tokens.compactMap(\.queryPhrase)
        let typed = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (phrases + (typed.isEmpty ? [] : [typed])).joined(separator: " ")
    }

    /// The list scope an active field token applies to the typed text.
    static func searchScope(for tokens: [MailSearchToken]) -> SearchScope {
        for case .field(let field) in tokens {
            return field.searchScope
        }
        return .all
    }

    /// Adds a token unless it is already present; a new field token replaces the old one.
    static func add(_ token: MailSearchToken, to tokens: inout [MailSearchToken]) {
        if case .field = token {
            tokens.removeAll { if case .field = $0 { true } else { false } }
        }
        guard !tokens.contains(where: { $0.id == token.id }) else { return }
        tokens.append(token)
    }

    /// Splits predicates the user typed ("unread from ada@example.com last week") into tokens, leaving the keywords.
    static func extract(
        from text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (tokens: [MailSearchToken], remainingText: String) {
        let plan = NaturalLanguageSearchPlanner.plan(for: text, execution: .cacheOnly, now: now, calendar: calendar)
        var tokens: [MailSearchToken] = []
        for chip in plan.chips {
            switch chip.kind {
            case .keyword, .subject: break
            case .sender: tokens.append(.sender(email: chip.value, name: nil))
            case .date: MailSearchDatePreset(phrase: chip.value).map { tokens.append(.date($0)) }
            case .unread: tokens.append(.unread)
            case .attachment: tokens.append(.hasAttachment)
            case .flagged: tokens.append(.flagged)
            }
        }
        return (tokens, plan.query.text)
    }
}

/// Decides whether a search shows a status footnote under the results.
///
/// A complete local search says nothing. Status appears only while there is something the
/// user should know: cached matches waiting on the server, an attachment-content scan that may
/// download data, or a search that actually failed or could not be verified.
enum MailSearchFooterPolicy {
    static func shouldShow(
        progress: MailSearchProgressState,
        execution: SearchExecution,
        checksAttachments: Bool
    ) -> Bool {
        guard progress.sourceCount > 0 else { return false }
        if progress.isSearching {
            return checksAttachments || progress.hasFailure || progress.cachedSourceCount > 0
        }
        if progress.hasFailure { return true }
        return execution == .serverOnly && progress.unverifiedSourceCount > 0
    }
}
