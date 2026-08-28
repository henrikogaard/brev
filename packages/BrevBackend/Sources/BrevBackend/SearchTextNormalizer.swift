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

import Foundation

/// Canonical search-text normalization shared by the in-memory `SearchQuery`
/// fallback and the SQLite/FTS search index.
///
/// Both the local cache fallback (`SearchQuery.matches`) and the persisted FTS
/// `normalized_search` column **must** normalize identically — otherwise a query
/// matched in one path silently misses in the other. This type is the single
/// source of truth so the two cannot drift.
///
/// Norwegian letters are transliterated explicitly (`ø→o`, `æ→ae`, `å→a`) before
/// Unicode folding, because `.diacriticInsensitive` treats them as distinct
/// letters rather than accented Latin and would otherwise leave them unmatched
/// for Norwegian users.
public enum SearchTextNormalizer {
    /// The locale-folded, transliterated form of `value`.
    ///
    /// - Note: Folding uses `.current` locale. This is intentional and must not
    ///   be changed to a fixed/`nil` locale without bumping the search-index
    ///   schema version to force a rebuild — the persisted `normalized_search`
    ///   column is computed with this function, so changing the folding rule
    ///   would desynchronize already-indexed rows from new queries.
    public static func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "Æ", with: "ae")
            .replacingOccurrences(of: "ø", with: "o")
            .replacingOccurrences(of: "Ø", with: "o")
            .replacingOccurrences(of: "å", with: "a")
            .replacingOccurrences(of: "Å", with: "a")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
    }
}
