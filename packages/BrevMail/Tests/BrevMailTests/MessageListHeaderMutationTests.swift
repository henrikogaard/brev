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

@Suite("MessageListHeaderMutation")
struct MessageListHeaderMutationTests {
    @Test("updating headers mutates matching ids and preserves order")
    func updatingHeadersMutatesMatchingIDsAndPreservesOrder() {
        let first = Self.makeHeader(id: "first", isRead: false, isFlagged: false)
        let second = Self.makeHeader(id: "second", isRead: false, isFlagged: false)

        let updated = MessageListHeaderMutation.updating([first, second], ids: [second.id]) {
            $0.isRead = true
            $0.isFlagged = true
        }

        #expect(updated.map(\.id) == [first.id, second.id])
        #expect(updated[0].isRead == false)
        #expect(updated[0].isFlagged == false)
        #expect(updated[1].isRead == true)
        #expect(updated[1].isFlagged == true)
    }

    @Test("removing headers drops matching ids and preserves remaining order")
    func removingHeadersDropsMatchingIDsAndPreservesRemainingOrder() {
        let first = Self.makeHeader(id: "first")
        let second = Self.makeHeader(id: "second")
        let third = Self.makeHeader(id: "third")

        let remaining = MessageListHeaderMutation.removing(
            [first, second, third],
            ids: [first.id, third.id]
        )

        #expect(remaining.map(\.id) == [second.id])
    }

    private static func makeHeader(
        id: MessageHeader.ID,
        isRead: Bool = false,
        isFlagged: Bool = false
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: "inbox",
            from: Correspondent(name: "Ada Lovelace", email: "ada@example.com"),
            to: [Correspondent(name: "Brev", email: "hello@brev.test")],
            subject: "Subject \(id)",
            snippet: "Snippet",
            date: Date(timeIntervalSince1970: 1_735_689_600),
            isRead: isRead,
            isFlagged: isFlagged
        )
    }
}
