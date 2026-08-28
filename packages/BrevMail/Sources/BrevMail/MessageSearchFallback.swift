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

enum MessageSearchFallback {
    /// Simple text-only local filter used when the backend does not
    /// support server-side search. Only matches against subject, snippet,
    /// and correspondent display names / email addresses.
    static func filteredHeaders(
        in headers: [MessageHeader],
        query: String
    ) -> [MessageHeader] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return headers }

        return headers.filter { header in
            header.subject.lowercased().contains(needle)
                || header.snippet.lowercased().contains(needle)
                || matches(header.from, needle: needle)
                || (header.to + header.cc + header.bcc).contains { matches($0, needle: needle) }
        }
    }

    /// Rich local filter that evaluates all predicates in a `SearchQuery`.
    ///
    /// Used by local-cache implementations and by the fallback path when
    /// the backend returns `.notSupported` for server-side search. Delegates
    /// the full predicate evaluation to `SearchQuery.matches(_:)`.
    static func filteredHeaders(
        in headers: [MessageHeader],
        searchQuery: SearchQuery
    ) -> [MessageHeader] {
        headers.filter { searchQuery.matches($0) }
    }

    private static func matches(_ correspondent: Correspondent, needle: String) -> Bool {
        correspondent.displayName.lowercased().contains(needle)
            || correspondent.email.lowercased().contains(needle)
    }
}
