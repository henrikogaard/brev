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

struct RecipientAutocompleteSuggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let email: String
    let source: RecipientAutocompleteSource

    var sourceLabel: String { source.label }
}

enum RecipientAutocompleteSource: Equatable {
    case appleContacts
    case recentRecipients
    case cardDAV

    var label: String {
        switch self {
        case .appleContacts: return "Contacts"
        case .recentRecipients: return "Recent"
        case .cardDAV: return "CardDAV"
        }
    }
}

struct RecipientAutocompleteCandidate {
    let result: ContactLookupResult
    let source: RecipientAutocompleteSource
}

enum ComposeRecipientField: Hashable {
    case to
    case cc
    case bcc
}

enum ComposeRecipientAutocomplete {
    static let minimumQueryLength = 2
    static let maxSuggestions = 8

    static func shouldLookup(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumQueryLength
    }

    static func suggestions(
        from results: [ContactLookupResult],
        existingRecipients: [String],
        limit: Int = maxSuggestions
    ) -> [RecipientAutocompleteSuggestion] {
        suggestions(
            from: results.map {
                RecipientAutocompleteCandidate(result: $0, source: .cardDAV)
            },
            existingRecipients: existingRecipients,
            limit: limit
        )
    }

    static func suggestions(
        from candidates: [RecipientAutocompleteCandidate],
        existingRecipients: [String],
        limit: Int = maxSuggestions
    ) -> [RecipientAutocompleteSuggestion] {
        let existing = Set(existingRecipients.map { $0.lowercased() })
        var seen = Set<String>()
        let mapped = candidates.compactMap { candidate -> RecipientAutocompleteSuggestion? in
            let result = candidate.result
            let email = result.email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard RecipientAddressValidator.isLikelyEmailAddress(email) else { return nil }
            let normalized = email.lowercased()
            guard !existing.contains(normalized), !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            let name = result.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let name, !name.isEmpty {
                return RecipientAutocompleteSuggestion(
                    id: result.id,
                    title: name,
                    subtitle: email,
                    email: email,
                    source: candidate.source
                )
            }
            return RecipientAutocompleteSuggestion(
                id: result.id,
                title: email,
                subtitle: "Contact",
                email: email,
                source: candidate.source
            )
        }
        return Array(mapped.prefix(max(0, limit)))
    }

    /// Converts a provider lookup into optional suggestions without hiding local results on failure.
    @MainActor
    static func providerCandidates(
        _ load: () async throws -> [ContactLookupResult]
    ) async -> [RecipientAutocompleteCandidate] {
        do {
            let results = try await load()
            return results.map {
                RecipientAutocompleteCandidate(result: $0, source: .cardDAV)
            }
        } catch {
            return []
        }
    }

    static func query(
        text: String,
        sourceID: MailSourceID,
        limit: Int = maxSuggestions
    ) -> ContactLookupQuery? {
        guard shouldLookup(text) else { return nil }
        return ContactLookupQuery(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceID: sourceID,
            limit: limit
        )
    }
}
