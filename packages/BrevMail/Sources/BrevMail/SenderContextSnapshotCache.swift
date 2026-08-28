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

#if os(macOS)
struct SenderContextCacheKey: Hashable, Sendable {
    let sourceID: MailSourceID
    let senderEmail: String

    init(sourceID: MailSourceID, senderEmail: String) {
        self.sourceID = sourceID
        self.senderEmail = senderEmail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

actor SenderContextSnapshotCache {
    static let shared = SenderContextSnapshotCache()

    private struct Entry: Sendable {
        let snapshot: SenderContextSnapshot
        let insertedAt: Date
    }

    private let capacity: Int
    private let timeToLive: TimeInterval
    private var entries: [SenderContextCacheKey: Entry] = [:]
    private var recency: [SenderContextCacheKey] = []

    init(capacity: Int = 64, timeToLive: TimeInterval = 30) {
        self.capacity = max(1, capacity)
        self.timeToLive = max(0, timeToLive)
    }

    func value(
        for key: SenderContextCacheKey,
        now: Date = Date()
    ) -> SenderContextSnapshot? {
        guard let entry = entries[key] else { return nil }
        guard now.timeIntervalSince(entry.insertedAt) <= timeToLive else {
            remove(key)
            return nil
        }
        touch(key)
        return entry.snapshot
    }

    func insert(
        _ snapshot: SenderContextSnapshot,
        for key: SenderContextCacheKey,
        now: Date = Date()
    ) {
        entries[key] = Entry(snapshot: snapshot, insertedAt: now)
        touch(key)
        while entries.count > capacity, let oldest = recency.first {
            remove(oldest)
        }
    }

    private func touch(_ key: SenderContextCacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private func remove(_ key: SenderContextCacheKey) {
        entries.removeValue(forKey: key)
        recency.removeAll { $0 == key }
    }
}

enum MailContextSenderLoadPolicy {
    /// Lets the reading pane's foreground body/render work win the selection frame.
    static let debounceNanoseconds: UInt64 = 200_000_000
}

extension SenderContextSnapshot {
    func replacingSelectedIdentity(_ header: MessageHeader) -> SenderContextSnapshot {
        var snapshot = self
        snapshot.identity.email = header.from.email
        snapshot.identity.displayName = header.from.displayName
        return snapshot
    }
}
#endif
