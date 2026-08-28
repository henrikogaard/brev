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
@testable import BrevMail
import Foundation
import Testing

@Suite("MessageListRefreshMerge")
struct MessageListRefreshMergeTests {
    @Test("refreshed first page replaces matching headers and preserves loaded older headers")
    func refreshedFirstPagePreservesLoadedOlderHeaders() {
        let updatedNewest = Self.makeHeader(
            id: "newest",
            subject: "Updated newest",
            date: Date(timeIntervalSince1970: 300)
        )
        let newArrival = Self.makeHeader(
            id: "new-arrival",
            subject: "New arrival",
            date: Date(timeIntervalSince1970: 400)
        )
        let previous = [
            Self.makeHeader(
                id: "newest",
                subject: "Old newest",
                date: Date(timeIntervalSince1970: 300)
            ),
            Self.makeHeader(
                id: "middle",
                subject: "Middle",
                date: Date(timeIntervalSince1970: 200)
            ),
            Self.makeHeader(
                id: "oldest",
                subject: "Oldest",
                date: Date(timeIntervalSince1970: 100)
            ),
        ]

        let merged = MessageListRefreshMerge.headers(
            refreshedFirstPage: [newArrival, updatedNewest],
            previousLoadedHeaders: previous,
            previousFirstPageHeaderIDs: ["newest"],
            isSameFolder: true
        )

        #expect(merged.map(\.id) == ["new-arrival", "newest", "middle", "oldest"])
        #expect(merged.first { $0.id == "newest" }?.subject == "Updated newest")
    }

    @Test("refreshed first page drops stale headers from the previous first page")
    func refreshedFirstPageDropsStalePreviousFirstPageHeaders() {
        let previous = [
            Self.makeHeader(
                id: "kept-newest",
                subject: "Kept",
                date: Date(timeIntervalSince1970: 400)
            ),
            Self.makeHeader(
                id: "deleted-from-first-page",
                subject: "Deleted",
                date: Date(timeIntervalSince1970: 300)
            ),
            Self.makeHeader(
                id: "older-loaded-page",
                subject: "Older",
                date: Date(timeIntervalSince1970: 200)
            ),
        ]

        let merged = MessageListRefreshMerge.headers(
            refreshedFirstPage: [previous[0]],
            previousLoadedHeaders: previous,
            previousFirstPageHeaderIDs: [
                "kept-newest",
                "deleted-from-first-page",
            ],
            isSameFolder: true
        )

        #expect(merged.map(\.id) == ["kept-newest", "older-loaded-page"])
    }

    @Test("empty refresh result clears stale loaded headers")
    func emptyRefreshResultClearsStaleLoadedHeaders() {
        let previous = [
            Self.makeHeader(id: "old", subject: "Old", date: Date(timeIntervalSince1970: 100)),
        ]

        let merged = MessageListRefreshMerge.headers(
            refreshedFirstPage: [],
            previousLoadedHeaders: previous,
            previousFirstPageHeaderIDs: ["old"],
            isSameFolder: true
        )

        #expect(merged.isEmpty)
    }

    @Test("switching folders discards the previous folder's loaded headers")
    func switchingFoldersDiscardsPreviousFolderHeaders() {
        // Simulates switching from a heavily paged-in mailbox (e.g. ogard
        // Inbox) to a sparse one (e.g. a fresh Fastmail Inbox). The previous
        // mailbox's older, paged-in headers must NOT bleed into the new list.
        let previousMailbox = [
            Self.makeHeader(id: "ogard-1", subject: "GitHub", date: Date(timeIntervalSince1970: 500)),
            Self.makeHeader(id: "ogard-2", subject: "FINN", date: Date(timeIntervalSince1970: 400)),
            Self.makeHeader(id: "ogard-older-page", subject: "Domeneshop", date: Date(timeIntervalSince1970: 100)),
        ]
        let newMailbox = [
            Self.makeHeader(id: "fastmail-1", subject: "Welcome to Fastmail", date: Date(timeIntervalSince1970: 900)),
        ]

        let merged = MessageListRefreshMerge.headers(
            refreshedFirstPage: newMailbox,
            previousLoadedHeaders: previousMailbox,
            // Older-loaded-page id is intentionally absent here — under the old
            // behaviour it would have survived the merge and contaminated the
            // new mailbox.
            previousFirstPageHeaderIDs: ["ogard-1", "ogard-2"],
            isSameFolder: false
        )

        #expect(merged.map(\.id) == ["fastmail-1"])
    }

    private static func makeHeader(
        id: MessageHeader.ID,
        subject: String,
        date: Date
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: "inbox",
            from: Correspondent(name: "Ada Lovelace", email: "ada@example.com"),
            to: [Correspondent(name: "Brev", email: "hello@brev.test")],
            subject: subject,
            snippet: "Snippet",
            date: date,
            isRead: false,
            isFlagged: false
        )
    }
}
