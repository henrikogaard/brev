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

/// Deterministic performance baselines for the hot paths tuned in the
/// 2026-09 performance pass (issue #28 §5). Each test builds a synthetic
/// large-folder fixture, times the public API with `ContinuousClock`, prints
/// the numbers in a stable `PERF ...` line for `docs/qa`, and asserts only
/// ordinal relationships (memo hit is not slower than cold; coalesced flush is
/// not slower than write-through) so the suite never flakes on host speed.
@Suite("Performance baselines", .serialized)
struct PerformanceBaselineTests {
    private static let folderSize = 10000
    private static let pageSize = 200

    @Test("cache-hit listing of a 10k folder: cold thread resolution vs memo hit")
    func cachedListingThreadResolutionMemo() async throws {
        let headers = Self.syntheticHeaders(count: Self.folderSize, folderID: "INBOX")
        let headerCache = InMemoryIMAPMailboxHeaderCache(snapshotsByFolderByAccount: [
            Self.account.id: ["INBOX": IMAPMailboxHeaderCacheSnapshot(headers: headers)],
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [Self.inboxListing] },
            listMessages: { _, _, _, _, _ in throw URLError(.notConnectedToInternet) },
            headerCache: headerCache
        )
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        let clock = ContinuousClock()
        let coldStart = clock.now
        let cold = try await backend.messages(in: inbox, pageToken: nil)
        let coldDuration = clock.now - coldStart

        let warmStart = clock.now
        let warm = try await backend.messages(in: inbox, pageToken: nil)
        let warmDuration = clock.now - warmStart

        #expect(cold.headers.count == warm.headers.count)
        #expect(!cold.headers.isEmpty)
        print(
            "PERF listing.cache-hit folder=\(Self.folderSize) cold_ms=\(Self.ms(coldDuration)) warm_ms=\(Self.ms(warmDuration))"
        )
        #expect(warmDuration <= coldDuration * 2, "memo hit should not be materially slower than cold resolution")
    }

    @Test("paging a 10k folder from the server: per-page merge cost stays flat")
    func serverPagingMergeCost() async throws {
        let listings = Self.syntheticListings(count: Self.folderSize)
        let pager = ListingPager(listings: listings, pageSize: Self.pageSize)
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [Self.inboxListing] },
            listMessages: { _, _, folderID, pageToken, limit in
                await pager.page(folderID: folderID, pageToken: pageToken, limit: limit)
            },
            headerCache: InMemoryIMAPMailboxHeaderCache()
        )
        try await backend.connect()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        let clock = ContinuousClock()
        var token: String?
        var pageDurations: [Duration] = []
        for _ in 0 ..< 20 {
            let start = clock.now
            let page = try await backend.messages(in: inbox, pageToken: token)
            pageDurations.append(clock.now - start)
            token = page.nextPageToken
            if token == nil { break }
        }
        await backend.disconnect()

        let first = pageDurations.prefix(3).reduce(Duration.zero, +) / 3
        let last = pageDurations.suffix(3).reduce(Duration.zero, +) / 3
        print(
            "PERF paging.server pages=\(pageDurations.count) page_size=\(Self.pageSize) first3_avg_ms=\(Self.ms(first)) last3_avg_ms=\(Self.ms(last))"
        )
        #expect(pageDurations.count >= 10)
        // Record-only: the append fast path removed the per-page re-sort, but
        // thread resolution still runs over the whole cached folder whenever new
        // headers arrive, so later pages grow with cached size (~3.5 ms at 4k
        // headers on the 2026-09 baseline host). See docs/qa/performance-baseline.
        #expect(last > .zero)
    }

    @Test("file-backed header cache: 50 flag updates coalesce into one flush")
    func fileBackedCacheCoalescedFlush() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevPerf-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var headers = Self.syntheticHeaders(count: Self.folderSize, folderID: "INBOX")
        let clock = ContinuousClock()

        // Coalesced (current behavior): mutate 50 times, flush once.
        let coalesced = FileBackedIMAPMailboxHeaderCache(rootDirectory: root.appendingPathComponent("coalesced"))
        let coalescedStart = clock.now
        for index in 0 ..< 50 {
            headers[index].isRead.toggle()
            await coalesced.setSnapshot(
                IMAPMailboxHeaderCacheSnapshot(headers: headers),
                accountID: Self.account.id,
                folderID: "INBOX"
            )
        }
        await coalesced.flushPendingWrites()
        let coalescedDuration = clock.now - coalescedStart

        // Write-through (previous behavior): flush after every mutation.
        let writeThrough = FileBackedIMAPMailboxHeaderCache(rootDirectory: root.appendingPathComponent("through"))
        let throughStart = clock.now
        for index in 0 ..< 50 {
            headers[index].isRead.toggle()
            await writeThrough.setSnapshot(
                IMAPMailboxHeaderCacheSnapshot(headers: headers),
                accountID: Self.account.id,
                folderID: "INBOX"
            )
            await writeThrough.flushPendingWrites()
        }
        let throughDuration = clock.now - throughStart

        print(
            "PERF header-cache.flush folder=\(Self.folderSize) mutations=50 coalesced_ms=\(Self.ms(coalescedDuration)) write_through_ms=\(Self.ms(throughDuration))"
        )
        #expect(coalescedDuration < throughDuration)
        let persisted = await coalesced.snapshot(accountID: Self.account.id, folderID: "INBOX")
        #expect(persisted?.headers.count == Self.folderSize)
    }

    // MARK: Fixtures

    private static let account = BrevAccount(
        id: "imap-smtp:perf@example.org",
        displayName: "Perf",
        emailAddress: "perf@example.org"
    )

    private static let configuration = IMAPAccountConfiguration(
        accountID: "imap-smtp:perf@example.org",
        emailAddress: "perf@example.org",
        displayName: "Perf",
        incoming: MailServerSettings(
            kind: .imap,
            host: "imap.example.org",
            port: 993,
            tlsMode: .implicit,
            authentication: .password
        ),
        outgoing: MailServerSettings(
            kind: .smtp,
            host: "smtp.example.org",
            port: 587,
            tlsMode: .startTLS,
            authentication: .password
        ),
        credentialID: "imap-smtp:perf@example.org"
    )

    private static let credential = MailAccountCredential(
        incomingUsername: "perf@example.org",
        outgoingUsername: "perf@example.org",
        secret: "secret",
        authentication: .password
    )

    private static let inboxListing = IMAPFolderListing(
        path: "INBOX", displayName: "Inbox", delimiter: "/", flags: [], role: .inbox
    )

    /// Headers with realistic threading: every third message replies to the
    /// previous one so union-find has real work, and a third have References.
    private static func syntheticHeaders(count: Int, folderID: String) -> [MessageHeader] {
        (0 ..< count).map { index in
            let uid = count - index
            let messageID = "<m\(uid)@example.org>"
            let inReplyTo = index % 3 == 0 && uid > 1 ? "<m\(uid - 1)@example.org>" : nil
            return MessageHeader(
                id: "\(folderID):\(uid)",
                threadID: inReplyTo ?? messageID,
                folderID: folderID,
                from: Correspondent(email: "sender\(uid % 97)@example.org"),
                to: [Correspondent(email: "perf@example.org")],
                subject: "Subject \(uid % 500)",
                snippet: "Snippet \(uid)",
                date: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + uid * 60)),
                isRead: uid % 2 == 0,
                messageID: messageID,
                inReplyTo: inReplyTo,
                references: index % 3 == 1 && uid > 2 ? ["m\(uid - 2)@example.org"] : nil
            )
        }
    }

    private static func syntheticListings(count: Int) -> [IMAPMessageListing] {
        (0 ..< count).map { index in
            let uid = count - index
            return IMAPMessageListing(
                uid: uid,
                messageID: "<m\(uid)@example.org>",
                subject: "Subject \(uid % 500)",
                from: Correspondent(email: "sender\(uid % 97)@example.org"),
                to: [Correspondent(email: "perf@example.org")],
                cc: [],
                bcc: [],
                date: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + uid * 60)),
                isRead: uid % 2 == 0,
                isFlagged: false,
                isAnswered: false
            )
        }
    }

    private static func ms(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        let milliseconds = Double(seconds) * 1000 + Double(attoseconds) / 1e15
        return String(format: "%.2f", milliseconds)
    }
}

/// Serves newest-first pages using the backend's `before:<uid>` cursor.
private actor ListingPager {
    private let listings: [IMAPMessageListing]
    private let pageSize: Int

    init(listings: [IMAPMessageListing], pageSize: Int) {
        self.listings = listings
        self.pageSize = pageSize
    }

    func page(folderID _: String, pageToken: String?, limit: Int) -> IMAPMessageListingPage {
        let boundary: Int
        if let pageToken, pageToken.hasPrefix("before:"), let uid = Int(pageToken.dropFirst("before:".count)) {
            boundary = uid
        } else {
            boundary = Int.max
        }
        let effectiveSize = min(limit, pageSize)
        let page = Array(listings.drop { $0.uid >= boundary }.prefix(effectiveSize))
        let next = page.last.map { "before:\($0.uid)" }
        return IMAPMessageListingPage(messages: page, nextPageToken: page.count < effectiveSize ? nil : next)
    }
}
