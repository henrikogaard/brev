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

@Suite("MessageListInlineExpansion")
struct MessageListInlineExpansionTests {
    private static let epoch = Date(timeIntervalSince1970: 0)

    private static func makeHeader(
        id: String,
        threadID: String,
        date: Date = epoch
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: threadID,
            folderID: "inbox",
            from: Correspondent(name: "Ada", email: "ada@example.org"),
            subject: "Subject",
            snippet: "",
            date: date,
            isRead: false
        )
    }

    @Test("toggling an unexpanded thread inserts it into the set")
    func togglingUnexpandedThreadInsertsIt() {
        var expandedIDs: Set<String> = []
        MessageListInlineExpansion.toggle(threadID: "t1", in: &expandedIDs)
        #expect(expandedIDs == ["t1"])
    }

    @Test("toggling an already expanded thread removes it")
    func togglingExpandedThreadRemovesIt() {
        var expandedIDs: Set<String> = ["t1"]
        MessageListInlineExpansion.toggle(threadID: "t1", in: &expandedIDs)
        #expect(expandedIDs.isEmpty)
    }

    @Test("toggling one thread does not affect others")
    func togglingOneThreadDoesNotAffectOthers() {
        var expandedIDs: Set<String> = ["t2"]
        MessageListInlineExpansion.toggle(threadID: "t1", in: &expandedIDs)
        #expect(expandedIDs == ["t1", "t2"])
    }

    @Test("selecting a collapsed threaded parent expands it")
    func selectingCollapsedThreadedParentExpandsIt() {
        var expandedIDs: Set<String> = []

        MessageListInlineExpansion.expandIfNeeded(
            threadID: "t1",
            threadCount: 3,
            isThreadingEnabled: true,
            in: &expandedIDs
        )

        #expect(expandedIDs == ["t1"])
    }

    @Test("selecting an expanded threaded parent keeps it expanded")
    func selectingExpandedThreadedParentKeepsItExpanded() {
        var expandedIDs: Set<String> = ["t1"]

        MessageListInlineExpansion.expandIfNeeded(
            threadID: "t1",
            threadCount: 3,
            isThreadingEnabled: true,
            in: &expandedIDs
        )

        #expect(expandedIDs == ["t1"])
    }

    @Test("selecting a single message or unsupported thread does not expand")
    func selectingSingleMessageOrUnsupportedThreadDoesNotExpand() {
        var expandedIDs: Set<String> = []

        MessageListInlineExpansion.expandIfNeeded(
            threadID: "single",
            threadCount: 1,
            isThreadingEnabled: true,
            in: &expandedIDs
        )
        MessageListInlineExpansion.expandIfNeeded(
            threadID: "unsupported",
            threadCount: 3,
            isThreadingEnabled: false,
            in: &expandedIDs
        )

        #expect(expandedIDs.isEmpty)
    }

    @Test("child headers for a thread exclude the parent and are sorted oldest to newest")
    func childHeadersSortedOldestToNewest() {
        let newer = Self.makeHeader(id: "newer", threadID: "t", date: Self.epoch.addingTimeInterval(100))
        let older = Self.makeHeader(id: "older", threadID: "t", date: Self.epoch)
        let other = Self.makeHeader(id: "other", threadID: "other-thread")

        let result = MessageListInlineExpansion.childHeaders(
            for: "t",
            excludingParentID: newer.id,
            from: [newer, other, older]
        )
        #expect(result.map(\.id) == ["older"])
    }

    @Test("child headers excludes messages from other threads")
    func childHeadersExcludesOtherThreads() {
        let mine = Self.makeHeader(id: "mine", threadID: "t")
        let theirs = Self.makeHeader(id: "theirs", threadID: "other")

        let result = MessageListInlineExpansion.childHeaders(
            for: "t",
            excludingParentID: mine.id,
            from: [mine, theirs]
        )
        #expect(result.isEmpty)
    }
}
