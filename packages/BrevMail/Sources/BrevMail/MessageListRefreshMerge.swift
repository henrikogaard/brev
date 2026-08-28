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

enum MessageListRefreshMerge {
    /// Merge a freshly fetched first page with the headers already loaded for a
    /// folder.
    ///
    /// - Parameters:
    ///   - refreshedFirstPage: the newly fetched first page of headers.
    ///   - previousLoadedHeaders: headers currently held in memory.
    ///   - previousFirstPageHeaderIDs: ids that made up the prior first page.
    ///   - isSameFolder: whether `previousLoadedHeaders` belong to the same
    ///     folder/account being refreshed. When `false` (a folder or account
    ///     switch) the previous headers are discarded entirely so one mailbox's
    ///     paged-in messages can never bleed into another.
    static func headers(
        refreshedFirstPage: [MessageHeader],
        previousLoadedHeaders: [MessageHeader],
        previousFirstPageHeaderIDs: Set<MessageHeader.ID>,
        isSameFolder: Bool
    ) -> [MessageHeader] {
        guard !refreshedFirstPage.isEmpty else { return [] }
        guard isSameFolder else { return refreshedFirstPage }
        var seenIDs = Set(refreshedFirstPage.map(\.id))
        var merged = refreshedFirstPage
        for header in previousLoadedHeaders
            where !previousFirstPageHeaderIDs.contains(header.id)
            && seenIDs.insert(header.id).inserted {
            merged.append(header)
        }
        return merged
    }
}
