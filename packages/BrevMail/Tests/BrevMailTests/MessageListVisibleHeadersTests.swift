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

@Suite("MessageListVisibleHeaders")
struct MessageListVisibleHeadersTests {
    @Test("ungrouped lists keep every header")
    func ungroupedListsKeepEveryHeader() {
        let first = Self.makeHeader(id: "first", threadID: "thread")
        let second = Self.makeHeader(id: "second", threadID: "thread")

        #expect(MessageListVisibleHeaders.headers(
            from: [first, second],
            groupByThread: false
        ).map(\.id) == [first.id, second.id])
    }

    @Test("grouped lists keep the first header for each thread")
    func groupedListsKeepFirstHeaderForEachThread() {
        let first = Self.makeHeader(id: "first", threadID: "thread-a")
        let hiddenDuplicate = Self.makeHeader(id: "duplicate", threadID: "thread-a")
        let secondThread = Self.makeHeader(id: "second-thread", threadID: "thread-b")

        #expect(MessageListVisibleHeaders.headers(
            from: [first, hiddenDuplicate, secondThread],
            groupByThread: true
        ).map(\.id) == [first.id, secondThread.id])
    }

    @Test("grouping happens after filtering so matches remain visible")
    func groupingAfterFilteringKeepsThreadMatchesVisible() {
        let oldest = Self.makeHeader(id: "oldest", threadID: "thread-z", isRead: true)
        let latest = Self.makeHeader(id: "latest", threadID: "thread-z", isRead: false)
        let separate = Self.makeHeader(id: "separate", threadID: "thread-x", isRead: false)

        let filteredHeaders = MessageListSortPolicy.filtered(
            [oldest, latest, separate],
            by: MailboxFilterQuery(activeFilters: [.unread], senderEmail: nil)
        )

        #expect(MessageListVisibleHeaders.headers(
            from: filteredHeaders,
            groupByThread: true
        ).map(\.id) == [latest.id, separate.id])
    }

    @Test("pinned headers are promoted before unpinned headers")
    func pinnedHeadersArePromotedBeforeUnpinnedHeaders() {
        let first = Self.makeHeader(id: "first", threadID: "thread-a")
        let second = Self.makeHeader(id: "second", threadID: "thread-b")
        let third = Self.makeHeader(id: "third", threadID: "thread-c")

        #expect(MessageListVisibleHeaders.headers(
            from: [first, second, third],
            groupByThread: false,
            pinnedIDs: [third.id, first.id]
        ).map(\.id) == [first.id, third.id, second.id])
    }

    @Test("navigation headers keep every loaded message while the list groups threads")
    func navigationHeadersKeepEveryLoadedMessageWhileListGroupsThreads() {
        let parent = Self.makeHeader(id: "parent", threadID: "thread-a")
        let child = Self.makeHeader(id: "child", threadID: "thread-a")
        let separate = Self.makeHeader(id: "separate", threadID: "thread-b")

        #expect(MessageListNavigationHeaders.headers(
            from: [parent, child, separate],
            pinnedIDs: []
        ).map(\.id) == [parent.id, child.id, separate.id])
    }

    private static func makeHeader(
        id: String,
        threadID: String,
        isRead: Bool = false
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: threadID,
            folderID: "inbox",
            from: Correspondent(name: "Ada", email: "ada@example.org"),
            subject: id,
            snippet: "",
            date: Date(timeIntervalSince1970: 0),
            isRead: isRead
        )
    }
}
