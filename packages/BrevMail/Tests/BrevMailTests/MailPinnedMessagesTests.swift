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
@testable import BrevMail
import Testing

struct MailPinnedMessagesTests {
    @Test("the global pin limit reports failure without discarding pins in other mailboxes")
    func limitDoesNotDiscardPins() {
        let source = MailSourceID(accountID: "work", mailboxID: "work")
        let raw = (0 ..< 500).map { MailPinnedMessages.key(sourceID: source, messageID: "\($0)") }.joined(separator: "\n")
        #expect(throws: (any Error).self) {
            try MailPinnedMessages.toggling(sourceID: source, messageID: "new", in: raw)
        }
        #expect(raw.split(separator: "\n").count == 500)
    }

    @Test("colliding message IDs stay pinned independently and toggling one preserves other profiles")
    func pinsBelongToTheirSource() throws {
        let work = MailSourceID(accountID: "work", mailboxID: "inbox")
        let personal = MailSourceID(accountID: "personal", mailboxID: "inbox")
        let first = try MailPinnedMessages.toggling(sourceID: work, messageID: "INBOX:1", in: "")
        let both = try MailPinnedMessages.toggling(sourceID: personal, messageID: "INBOX:1", in: first)
        #expect(both.split(separator: "\n").count == 2)
        let remaining = try MailPinnedMessages.toggling(sourceID: work, messageID: "INBOX:1", in: both)
        #expect(remaining == MailPinnedMessages.key(sourceID: personal, messageID: "INBOX:1"))
        #expect(MailPinnedMessages.key(sourceID: work, messageID: "INBOX:1") != remaining)
    }

    @Test("decoding stored pins returns only the current source's message IDs")
    func decodesPinsForOneSource() throws {
        let work = MailSourceID(accountID: "work", mailboxID: "inbox")
        let personal = MailSourceID(accountID: "personal", mailboxID: "inbox")
        var raw = try MailPinnedMessages.toggling(sourceID: work, messageID: "INBOX:1", in: "")
        raw = try MailPinnedMessages.toggling(sourceID: work, messageID: "INBOX:2:with:colons", in: raw)
        raw = try MailPinnedMessages.toggling(sourceID: personal, messageID: "INBOX:1", in: raw)
        raw += "\nnot-base64!\n" + Data("3:abc".utf8).base64EncodedString()

        #expect(MailPinnedMessages.messageIDs(in: raw, sourceID: work) == ["INBOX:1", "INBOX:2:with:colons"])
        #expect(MailPinnedMessages.messageIDs(in: raw, sourceID: personal) == ["INBOX:1"])
        #expect(MailPinnedMessages.messageIDs(in: "", sourceID: work).isEmpty)
    }

    @Test("decoded pins match the per-header key check they replace")
    func decodingMatchesKeyCheck() throws {
        let source = MailSourceID(accountID: "ä-account", mailboxID: "box:1")
        let ids = (0 ..< 50).map { "INBOX:\($0)" }
        var raw = ""
        for id in ids where Int(id.dropFirst(6))! % 3 == 0 {
            raw = try MailPinnedMessages.toggling(sourceID: source, messageID: id, in: raw)
        }
        let keys = Set(raw.split(separator: "\n").map(String.init))
        let expected = Set(ids.filter { keys.contains(MailPinnedMessages.key(sourceID: source, messageID: $0)) })
        #expect(MailPinnedMessages.messageIDs(in: raw, sourceID: source) == expected)
    }
}
