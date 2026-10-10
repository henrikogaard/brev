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

/// Recent search text kept on this device only, shown as suggestions when the field is empty.
enum MailRecentSearches {
    static let limit = 8
    static let defaultsKey = "brev.search.recent"

    /// Puts `text` first, drops an earlier copy of it (ignoring case) and keeps at most `limit` entries.
    static func adding(_ text: String, to list: [String]) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return list }
        var updated = list.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        updated.insert(trimmed, at: 0)
        return Array(updated.prefix(limit))
    }

    static func load(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: defaultsKey) ?? []
    }

    static func save(_ list: [String], to defaults: UserDefaults = .standard) {
        if list.isEmpty {
            defaults.removeObject(forKey: defaultsKey)
        } else {
            defaults.set(list, forKey: defaultsKey)
        }
    }
}

/// A sender found in the headers already loaded on this device.
struct MailSearchSenderSuggestion: Equatable, Identifiable, Sendable {
    let email: String
    let name: String?
    var id: String { email.lowercased() }
    var displayName: String { name?.isEmpty == false ? name! : email }
    var token: MailSearchToken { .sender(email: email, name: name) }
}

/// What the search field offers before the user submits. Built only from data already on the device.
struct MailSearchSuggestionSet: Equatable, Sendable {
    var recents: [String] = []
    var quickFilters: [MailSearchToken] = []
    var senders: [MailSearchSenderSuggestion] = []
    var fieldTokens: [MailSearchToken] = []

    /// An empty set adds nothing, which keeps the live results visible instead of covering them.
    var isEmpty: Bool {
        recents.isEmpty && quickFilters.isEmpty && senders.isEmpty && fieldTokens.isEmpty
    }
}

enum MailSearchSuggestions {
    static let senderLimit = 3
    static let recentLimit = 5

    static func make(
        typedText: String,
        tokens: [MailSearchToken],
        headers: [MessageHeader],
        recents: [String],
        offersFieldTokens: Bool
    ) -> MailSearchSuggestionSet {
        let typed = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        var set = MailSearchSuggestionSet()
        let present = Set(tokens.map(\.id))

        if typed.isEmpty {
            set.recents = Array(recents.prefix(recentLimit))
            set.quickFilters = [MailSearchToken.unread, .flagged, .hasAttachment].filter { !present.contains($0.id) }
        } else {
            set.recents = Array(recents.filter { matches($0, typed) }.prefix(recentLimit))
            if offersFieldTokens, !tokens.contains(where: { if case .field = $0 { true } else { false } }) {
                set.fieldTokens = [.field(.from), .field(.subject)]
            }
        }
        set.senders = senders(matching: typed, in: headers).filter {
            !present.contains($0.token.id)
        }
        .prefix(senderLimit)
        .map { $0 }
        return set
    }

    /// Senders ordered by how many loaded messages they sent; `query` narrows by name or address.
    private static func senders(matching query: String, in headers: [MessageHeader]) -> [MailSearchSenderSuggestion] {
        var counts: [String: (count: Int, suggestion: MailSearchSenderSuggestion, firstIndex: Int)] = [:]
        for (index, header) in headers.enumerated() {
            let email = header.from.email
            guard !email.isEmpty else { continue }
            let key = email.lowercased()
            if let entry = counts[key] {
                counts[key] = (entry.count + 1, entry.suggestion, entry.firstIndex)
            } else {
                counts[key] = (1, MailSearchSenderSuggestion(email: email, name: header.from.name), index)
            }
        }
        return counts.values
            .filter { query.isEmpty || matches($0.suggestion.displayName, query) || matches($0.suggestion.email, query) }
            .sorted { $0.count == $1.count ? $0.firstIndex < $1.firstIndex : $0.count > $1.count }
            .map(\.suggestion)
    }

    private static func matches(_ candidate: String, _ query: String) -> Bool {
        candidate.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
