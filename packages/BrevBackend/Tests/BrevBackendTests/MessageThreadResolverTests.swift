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

@Suite("MessageThreadResolver")
struct MessageThreadResolverTests {
    @Test("a reply joins the message it answers")
    func replyJoinsItsParent() {
        let root = Self.header(uid: 1, messageID: "<root@example.org>", minutes: 0)
        let reply = Self.header(uid: 2, messageID: "<reply@example.org>", inReplyTo: "<root@example.org>", minutes: 10)

        let resolved = MessageThreadResolver.resolved([reply, root])

        #expect(Set(resolved.map(\.threadID)) == ["<root@example.org>"])
    }

    @Test("a chain of replies stays one conversation")
    func replyChainStaysOneConversation() {
        let root = Self.header(uid: 1, messageID: "<a@example.org>", minutes: 0)
        let second = Self.header(uid: 2, messageID: "<b@example.org>", inReplyTo: "<a@example.org>", minutes: 5)
        let third = Self.header(uid: 3, messageID: "<c@example.org>", inReplyTo: "<b@example.org>", minutes: 9)

        let resolved = MessageThreadResolver.resolved([third, second, root])

        #expect(Set(resolved.map(\.threadID)) == ["<a@example.org>"])
    }

    @Test("siblings group even when the message they answer was never fetched")
    func siblingsGroupWithoutTheirParent() {
        let first = Self.header(uid: 2, messageID: "<b@example.org>", inReplyTo: "<missing@example.org>", minutes: 5)
        let second = Self.header(uid: 3, messageID: "<c@example.org>", inReplyTo: "<missing@example.org>", minutes: 8)

        let resolved = MessageThreadResolver.resolved([second, first])

        #expect(resolved.count == 2)
        #expect(Set(resolved.map(\.threadID)).count == 1)
        // Named after the oldest message present, never after the absent parent.
        #expect(resolved[0].threadID == "<b@example.org>")
    }

    @Test("unrelated messages keep separate conversations")
    func unrelatedMessagesStaySeparate() {
        let first = Self.header(uid: 1, messageID: "<a@example.org>", minutes: 0)
        let second = Self.header(uid: 2, messageID: "<b@example.org>", minutes: 5)

        let resolved = MessageThreadResolver.resolved([first, second])

        #expect(resolved.map(\.threadID) == ["<a@example.org>", "<b@example.org>"])
    }

    @Test("resolution is idempotent")
    func resolutionIsIdempotent() {
        let root = Self.header(uid: 1, messageID: "<a@example.org>", minutes: 0)
        let reply = Self.header(uid: 2, messageID: "<b@example.org>", inReplyTo: "<a@example.org>", minutes: 5)

        let once = MessageThreadResolver.resolved([reply, root])
        let twice = MessageThreadResolver.resolved(once)

        #expect(once == twice)
    }

    @Test("a message without a Message-ID is never merged into another thread")
    func messagesWithoutMessageIDStayAlone() {
        let anonymous = MessageHeader(
            id: "inbox:9",
            threadID: "inbox:9",
            folderID: "inbox",
            from: Correspondent(email: "ada@example.org"),
            subject: "No id",
            snippet: "",
            date: Date(timeIntervalSince1970: 0)
        )
        let other = Self.header(uid: 1, messageID: "<a@example.org>", minutes: 5)

        let resolved = MessageThreadResolver.resolved([anonymous, other])

        #expect(resolved[0].threadID == "inbox:9")
        #expect(resolved[1].threadID == "<a@example.org>")
    }

    @Test("resolution never rewrites the message's own Message-ID")
    func resolutionKeepsRFCMessageID() {
        let root = Self.header(uid: 1, messageID: "<a@example.org>", minutes: 0)
        let reply = Self.header(uid: 2, messageID: "<b@example.org>", inReplyTo: "<a@example.org>", minutes: 5)

        let resolved = MessageThreadResolver.resolved([reply, root])

        // A reply built from this header must reference <b@…>, not the thread.
        #expect(resolved[0].rfcMessageID == "<b@example.org>")
        #expect(resolved[0].threadID == "<a@example.org>")
    }

    @Test("blank reply links are ignored")
    func blankReplyLinksAreIgnored() {
        let first = Self.header(uid: 1, messageID: "<a@example.org>", inReplyTo: "  ", minutes: 0)
        let second = Self.header(uid: 2, messageID: "<b@example.org>", inReplyTo: "", minutes: 5)

        let resolved = MessageThreadResolver.resolved([first, second])

        #expect(resolved.map(\.threadID) == ["<a@example.org>", "<b@example.org>"])
    }

    private static func header(
        uid: Int,
        messageID: String,
        inReplyTo: String? = nil,
        minutes: Int
    ) -> MessageHeader {
        MessageHeader(
            id: "inbox:\(uid)",
            threadID: messageID,
            folderID: "inbox",
            from: Correspondent(email: "ada@example.org"),
            subject: "Subject",
            snippet: "",
            date: Date(timeIntervalSince1970: TimeInterval(minutes * 60)),
            messageID: messageID,
            inReplyTo: inReplyTo
        )
    }
}
