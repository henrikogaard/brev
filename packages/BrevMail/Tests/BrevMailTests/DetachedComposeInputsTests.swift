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

@Suite("DetachedComposeInputs")
struct DetachedComposeInputsTests {
    private let sid = MailSourceID(accountID: "a1", mailboxID: "mbx")

    // MARK: messageID

    @Test("a new-message payload references no message")
    func newHasNoMessageID() {
        #expect(DetachedComposeInputs.messageID(for: .new(sourceID: nil)) == nil)
    }

    @Test("reply, reply-all, and forward payloads carry the referenced message id")
    func replyForwardCarryMessageID() {
        #expect(DetachedComposeInputs.messageID(for: .reply(messageID: "m1", sourceID: sid)) == "m1")
        #expect(DetachedComposeInputs.messageID(for: .replyAll(messageID: "m2", sourceID: sid)) == "m2")
        #expect(DetachedComposeInputs.messageID(for: .forward(messageID: "m3", sourceID: sid)) == "m3")
    }

    // MARK: sourceID

    @Test("a new-message payload carries its selected source mailbox (or nil)")
    func newCarriesSourceID() {
        #expect(DetachedComposeInputs.sourceID(for: .new(sourceID: nil)) == nil)
        #expect(DetachedComposeInputs.sourceID(for: .new(sourceID: sid)) == sid)
    }

    @Test("reply, reply-all, and forward payloads carry the source mailbox")
    func replyForwardCarrySourceID() {
        #expect(DetachedComposeInputs.sourceID(for: .reply(messageID: "m1", sourceID: sid)) == sid)
        #expect(DetachedComposeInputs.sourceID(for: .replyAll(messageID: "m2", sourceID: nil)) == nil)
        #expect(DetachedComposeInputs.sourceID(for: .forward(messageID: "m3", sourceID: sid)) == sid)
    }

    // MARK: restoresRecoverySnapshot

    @Test("only a new-message payload restores a saved recovery snapshot")
    func onlyNewRestoresRecovery() {
        #expect(DetachedComposeInputs.restoresRecoverySnapshot(for: .new(sourceID: nil)))
        #expect(!DetachedComposeInputs.restoresRecoverySnapshot(for: .reply(messageID: "m1", sourceID: sid)))
        #expect(!DetachedComposeInputs.restoresRecoverySnapshot(for: .replyAll(messageID: "m2", sourceID: sid)))
        #expect(!DetachedComposeInputs.restoresRecoverySnapshot(for: .forward(messageID: "m3", sourceID: sid)))
    }

    // MARK: quoteContext

    private func header(_ id: String) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: id,
            folderID: "inbox",
            from: Correspondent(email: "from@example.org"),
            subject: "Subject \(id)",
            snippet: "snippet",
            date: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("a new-message payload carries no quote")
    func newCarriesNoQuote() {
        let quote = DetachedComposeInputs.quoteContext(for: .new(sourceID: nil), header: header("m1"))
        #expect(quote == DetachedComposeQuoteContext(replyingTo: nil, replyMode: .sender, forwardingFrom: nil))
    }

    @Test("reply quotes the header in sender mode, reply-all in all mode")
    func replyAndReplyAllQuoteTheHeader() {
        let msg = header("m1")
        let reply = DetachedComposeInputs.quoteContext(for: .reply(messageID: "m1", sourceID: sid), header: msg)
        #expect(reply.replyingTo == msg)
        #expect(reply.replyMode == .sender)
        #expect(reply.forwardingFrom == nil)

        let replyAll = DetachedComposeInputs.quoteContext(for: .replyAll(messageID: "m1", sourceID: sid), header: msg)
        #expect(replyAll.replyingTo == msg)
        #expect(replyAll.replyMode == .all)
    }

    @Test("forward attaches the header as the forwarded message")
    func forwardAttachesHeader() {
        let msg = header("m1")
        let quote = DetachedComposeInputs.quoteContext(for: .forward(messageID: "m1", sourceID: sid), header: msg)
        #expect(quote.replyingTo == nil)
        #expect(quote.forwardingFrom == msg)
    }

    @Test("a missing cached header yields an empty quote even for reply/forward")
    func missingHeaderYieldsEmptyQuote() {
        #expect(DetachedComposeInputs.quoteContext(
            for: .reply(messageID: "m1", sourceID: sid),
            header: nil
        ).replyingTo == nil)
        #expect(DetachedComposeInputs.quoteContext(
            for: .forward(messageID: "m1", sourceID: sid),
            header: nil
        ).forwardingFrom == nil)
    }
}
