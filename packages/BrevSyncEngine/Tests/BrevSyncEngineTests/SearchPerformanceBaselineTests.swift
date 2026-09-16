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
@testable import BrevSyncEngine
import Foundation
import Testing

/// Baseline for the all-folders local search path (issue #28 §5). Compares
/// one folder-scoped query (`SearchQuery.folderIDs`) with the pre-2026-09
/// shape of one query per folder over the same SQLite index. Prints a stable
/// `PERF ...` line and asserts only that the single query is not slower.
@Suite("Search performance baseline", .serialized)
struct SearchPerformanceBaselineTests {
    private static let folderCount = 20
    private static let headersPerFolder = 500

    @Test("all-folders local search: one scoped query vs one query per folder")
    func scopedQueryVersusPerFolder() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-search-perf-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let account = BrevAccount(id: "perf", displayName: "Perf", emailAddress: "perf@example.org")
        let engine = try BrevSyncEngine(databaseURL: url)
        let folderIDs = (0 ..< Self.folderCount).map { "Folder-\($0)" }
        for folderID in folderIDs {
            await engine.storeHeaders(Self.headers(in: folderID), account: account)
        }

        let clock = ContinuousClock()
        // Warm SQLite's page cache once so both shapes are measured warm.
        _ = await engine.search(SearchQuery(text: "invoice", execution: .cacheOnly), account: account, limit: 10000)

        let scopedStart = clock.now
        let scoped = await engine.search(
            SearchQuery(text: "invoice", folderIDs: Set(folderIDs), execution: .cacheOnly),
            account: account,
            limit: 10000
        )
        let scopedDuration = clock.now - scopedStart

        let perFolderStart = clock.now
        var perFolder: [MessageHeader] = []
        for folderID in folderIDs {
            perFolder += await engine.search(
                SearchQuery(text: "invoice", folderID: folderID, execution: .cacheOnly),
                account: account,
                limit: 10000
            )
        }
        let perFolderDuration = clock.now - perFolderStart

        print(
            "PERF search.all-folders folders=\(Self.folderCount) rows=\(Self.folderCount * Self.headersPerFolder) matches=\(scoped.count) scoped_ms=\(Self.ms(scopedDuration)) per_folder_ms=\(Self.ms(perFolderDuration))"
        )
        #expect(Set(scoped.map(\.id)) == Set(perFolder.map(\.id)), "both shapes must return the same rows")
        #expect(!scoped.isEmpty)
        #expect(scopedDuration <= perFolderDuration)
    }

    private static func headers(in folderID: String) -> [MessageHeader] {
        (0 ..< headersPerFolder).map { index in
            let uid = index + 1
            return MessageHeader(
                id: "\(folderID):\(uid)",
                threadID: "<\(folderID)-\(uid)@example.org>",
                folderID: folderID,
                from: Correspondent(email: "sender\(uid % 41)@example.org"),
                to: [Correspondent(email: "perf@example.org")],
                subject: uid % 10 == 0 ? "Invoice \(uid)" : "Update \(uid)",
                snippet: "Body text \(uid)",
                date: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + uid * 60)),
                messageID: "<\(folderID)-\(uid)@example.org>"
            )
        }
    }

    private static func ms(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return String(format: "%.2f", Double(seconds) * 1000 + Double(attoseconds) / 1e15)
    }
}
