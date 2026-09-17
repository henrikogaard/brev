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

@testable import BrevBackend
import Foundation
import Testing

@Suite("Incremental thread resolver")
struct IncrementalThreadResolverTests {
    /// Deterministic PRNG so a failure reproduces exactly.
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private func header(
        _ id: String,
        messageID: String? = nil,
        inReplyTo: String? = nil,
        threadID: String? = nil,
        date: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> MessageHeader {
        MessageHeader(
            id: "INBOX:\(id)",
            threadID: threadID ?? messageID ?? "brev-header-id:INBOX:\(id)",
            folderID: "INBOX",
            from: Correspondent(email: "a@example.org"),
            to: [],
            subject: "s",
            snippet: "s",
            date: date,
            isRead: false,
            messageID: messageID,
            inReplyTo: inReplyTo
        )
    }

    @Test("Incremental updates match the batch resolver on random paging orders")
    func matchesBatchResolverOnRandomFeeds() {
        var rng = SplitMix64(seed: 0xBEE5_0076)
        for round in 0 ..< 30 {
            let count = 200 + Int(rng.next() % 401)
            var headers: [MessageHeader] = []
            for index in 0 ..< count {
                let messageID = "<m\(index)@example.org>"
                // ~40% replies; some point at absent parents (indices beyond
                // the set or to ids never created).
                let inReplyTo: String? = rng.next() % 10 < 4
                    ? "<m\(Int(rng.next() % UInt64(count + 40)))@example.org>"
                    : nil
                // Random dates with deliberate ties (60-second buckets).
                let date = Date(
                    timeIntervalSince1970: 1_700_000_000 + Double(rng.next() % 2000) * 60
                )
                headers.append(header(
                    "\(index)",
                    messageID: messageID,
                    inReplyTo: inReplyTo,
                    threadID: inReplyTo ?? messageID,
                    date: date
                ))
            }

            // Feed in random page order.
            let pageSize = 50 + Int(rng.next() % 100)
            let pages = headers.shuffled(using: &rng).chunked(into: pageSize)
            var resolver = IncrementalThreadResolver()
            var seen: [MessageHeader] = []
            for page in pages {
                seen += page
                _ = resolver.update(with: seen)
                let expected = MessageThreadResolver.threadIDsByHeaderID(for: seen)
                #expect(resolver.threadIDs() == expected, "round \(round), \(seen.count) headers")
            }
        }
    }

    @Test("Flag-only churn reports unchanged")
    func flagOnlyChangeIsUnchanged() {
        let a = header("1", messageID: "<a@example.org>")
        let b = header("2", messageID: "<b@example.org>", inReplyTo: "<a@example.org>")
        var resolver = IncrementalThreadResolver()
        _ = resolver.update(with: [a, b])
        var flagged = b
        flagged.isRead = true
        flagged.isFlagged = true
        #expect(resolver.update(with: [a, flagged]) == .unchanged)
    }

    @Test("A changed thread key rebuilds; a removal rebuilds")
    func changeAndRemovalRebuild() {
        let a = header("1", messageID: "<a@example.org>")
        let b = header("2", messageID: "<b@example.org>", inReplyTo: "<a@example.org>")
        var resolver = IncrementalThreadResolver()
        _ = resolver.update(with: [a, b])

        let moved = header(
            "2", messageID: "<b@example.org>", inReplyTo: "<a@example.org>",
            date: a.date.addingTimeInterval(-3600)
        )
        #expect(resolver.update(with: [a, moved]) == .rebuilt(reason: "changed"))
        #expect(resolver.update(with: [moved]) == .rebuilt(reason: "removed"))
        #expect(resolver.update(with: []) == .rebuilt(reason: "empty"))
        #expect(resolver.update(with: []) == .unchanged)
    }

    @Test("Pure additions report incremental with the added count")
    func additionsAreIncremental() {
        let a = header("1", messageID: "<a@example.org>")
        var resolver = IncrementalThreadResolver()
        _ = resolver.update(with: [a])
        let b = header("2", messageID: "<b@example.org>", inReplyTo: "<a@example.org>")
        let c = header("3", messageID: "<c@example.org>")
        #expect(resolver.update(with: [a, b, c]) == .incremental(added: 2))
    }

    @Test("A later bridge message merges two named threads under the older name")
    func bridgeMergesThreadNames() {
        // Thread 1: root + reply. Thread 2: a reply to the not-yet-fetched
        // message <bridge@…>, so its absent-parent node already exists.
        let oldRoot = header(
            "1", messageID: "<old@example.org>", threadID: "thread-old",
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let oldReply = header(
            "2", messageID: "<old-r@example.org>", inReplyTo: "<old@example.org>",
            date: Date(timeIntervalSince1970: 1_700_010_000)
        )
        let orphanReply = header(
            "3", messageID: "<new-r@example.org>", inReplyTo: "<bridge@example.org>",
            threadID: "thread-new",
            date: Date(timeIntervalSince1970: 1_700_050_000)
        )
        var resolver = IncrementalThreadResolver()
        #expect(resolver.update(with: [oldRoot, oldReply, orphanReply]) == .incremental(added: 3))
        #expect(resolver.threadID(for: orphanReply.id) == "thread-new")

        // The bridge message itself arrives: its node was already unioned
        // with thread 2, and it replies into thread 1 — merging both named
        // roots. The merged conversation takes the older name.
        let bridge = header(
            "4", messageID: "<bridge@example.org>", inReplyTo: "<old@example.org>",
            threadID: "bridge-own",
            date: Date(timeIntervalSince1970: 1_700_080_000)
        )
        #expect(resolver.update(with: [oldRoot, oldReply, orphanReply, bridge])
            == .incremental(added: 1))
        #expect(resolver.threadID(for: bridge.id) == "thread-old")
        #expect(resolver.threadID(for: orphanReply.id) == "thread-old")
        #expect(resolver.threadID(for: oldReply.id) == "thread-old")
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
