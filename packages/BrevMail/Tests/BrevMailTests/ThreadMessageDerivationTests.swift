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

@Suite("ThreadMessageDerivation")
struct ThreadMessageDerivationTests {
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

    @Test("returns only headers matching the given threadID")
    func returnsOnlyHeadersMatchingThreadID() {
        let a1 = Self.makeHeader(id: "a1", threadID: "thread-a")
        let a2 = Self.makeHeader(id: "a2", threadID: "thread-a")
        let b1 = Self.makeHeader(id: "b1", threadID: "thread-b")

        let result = ThreadMessageDerivation.threadHeaders(
            from: [a1, a2, b1],
            threadID: "thread-a"
        )

        #expect(result.map(\.id) == ["a1", "a2"])
    }

    @Test("sorts results oldest to newest")
    func sortsOldestToNewest() {
        let newer = Self.makeHeader(id: "newer", threadID: "t", date: Self.epoch.addingTimeInterval(200))
        let older = Self.makeHeader(id: "older", threadID: "t", date: Self.epoch.addingTimeInterval(100))
        let oldest = Self.makeHeader(id: "oldest", threadID: "t", date: Self.epoch)

        let result = ThreadMessageDerivation.threadHeaders(
            from: [newer, oldest, older],
            threadID: "t"
        )

        #expect(result.map(\.id) == ["oldest", "older", "newer"])
    }

    @Test("returns empty array when no headers match")
    func returnsEmptyWhenNoMatch() {
        let a1 = Self.makeHeader(id: "a1", threadID: "thread-a")

        let result = ThreadMessageDerivation.threadHeaders(
            from: [a1],
            threadID: "thread-b"
        )

        #expect(result.isEmpty)
    }

    @Test("returns single-element array for a single-message thread")
    func returnsSingleElementForSingleMessageThread() {
        let only = Self.makeHeader(id: "only", threadID: "t")

        let result = ThreadMessageDerivation.threadHeaders(
            from: [only],
            threadID: "t"
        )

        #expect(result.map(\.id) == ["only"])
    }

    @Test("returns empty array for empty input")
    func returnsEmptyForEmptyInput() {
        let result = ThreadMessageDerivation.threadHeaders(
            from: [],
            threadID: "t"
        )

        #expect(result.isEmpty)
    }
}
