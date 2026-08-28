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

/// Groups unified-inbox items into threads the same way `MessageListView`
/// groups a single folder, with one difference: a unified list mixes
/// accounts, and `threadID` is only unique inside one source. Every lookup
/// here is therefore keyed by source *and* thread (ADR-0020, ADR-0017).
enum UnifiedInboxThreadGrouping {
    /// Thread identity for one item: account, mailbox, and thread.
    static func key(for item: UnifiedInboxItem) -> String {
        "\(item.sourceID.accountID):\(item.sourceID.mailboxID):\(item.header.threadID)"
    }

    /// Tallies messages per thread, skipping sources whose backend cannot
    /// expand a thread — those rows must keep single-message behaviour.
    ///
    /// - Parameters:
    ///   - items: Items in display order.
    ///   - isThreadedSource: Whether the source supports threading.
    static func counts(
        for items: [UnifiedInboxItem],
        isThreadedSource: (MailSourceID) -> Bool
    ) -> [String: Int] {
        var threadedSources: [MailSourceID: Bool] = [:]
        return items.reduce(into: [:]) { counts, item in
            let isThreaded = threadedSources[item.sourceID] ?? {
                let resolved = isThreadedSource(item.sourceID)
                threadedSources[item.sourceID] = resolved
                return resolved
            }()
            guard isThreaded else { return }
            counts[key(for: item), default: 0] += 1
        }
    }

    /// Collapses each multi-message thread to the first item that appears in
    /// `items`, preserving the incoming sort order for everything else.
    static func parents(
        from items: [UnifiedInboxItem],
        counts: [String: Int]
    ) -> [UnifiedInboxItem] {
        var seen = Set<String>()
        return items.filter { item in
            let key = key(for: item)
            guard counts[key, default: 1] > 1 else { return true }
            return seen.insert(key).inserted
        }
    }

    /// Returns the other messages in `key`'s thread, oldest → newest.
    static func children(
        for key: String,
        excludingParentID parentID: UnifiedInboxItem.ID,
        from items: [UnifiedInboxItem]
    ) -> [UnifiedInboxItem] {
        items
            .filter { Self.key(for: $0) == key && $0.id != parentID }
            .sorted { $0.header.date < $1.header.date }
    }
}
