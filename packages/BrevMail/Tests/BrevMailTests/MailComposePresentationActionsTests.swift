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

@Suite("MailComposePresentationActions")
struct MailComposePresentationActionsTests {
    @Test("compose presentation actions invoke root-owned closures")
    @MainActor
    func composePresentationActionsInvokeRootOwnedClosures() {
        let header = Self.makeHeader()
        let sourceID = MailSourceID(accountID: "account-1", mailboxID: "mailbox-1")
        var invoked: [String] = []
        let actions = MailComposePresentationActions(
            newMessage: { invoked.append("new") },
            reply: { invoked.append("reply:\($0.id):\($1?.mailboxID ?? "none")") },
            replyAll: { invoked.append("replyAll:\($0.id):\($1?.mailboxID ?? "none")") },
            forward: { invoked.append("forward:\($0.id):\($1?.mailboxID ?? "none")") }
        )

        actions.newMessage()
        actions.reply(header, sourceID: sourceID)
        actions.replyAll(header, sourceID: sourceID)
        actions.forward(header, sourceID: sourceID)

        #expect(invoked == [
            "new",
            "reply:message-1:mailbox-1",
            "replyAll:message-1:mailbox-1",
            "forward:message-1:mailbox-1",
        ])
    }

    @Test("legacy compose presentation actions pass no source context")
    @MainActor
    func legacyComposePresentationActionsPassNoSourceContext() {
        let header = Self.makeHeader()
        var invoked: [String] = []
        let actions = MailComposePresentationActions(
            newMessage: {},
            reply: { invoked.append("reply:\($0.id):\($1?.mailboxID ?? "none")") },
            replyAll: { invoked.append("replyAll:\($0.id):\($1?.mailboxID ?? "none")") },
            forward: { invoked.append("forward:\($0.id):\($1?.mailboxID ?? "none")") }
        )

        actions.reply(header)
        actions.replyAll(header)
        actions.forward(header)

        #expect(invoked == [
            "reply:message-1:none",
            "replyAll:message-1:none",
            "forward:message-1:none",
        ])
    }

    @Test("compose presentation actions expose blocked state")
    @MainActor
    func composePresentationActionsExposeBlockedState() {
        let actions = MailComposePresentationActions(
            isBlocked: true,
            newMessage: {},
            reply: { _, _ in },
            replyAll: { _, _ in },
            forward: { _, _ in }
        )

        #expect(actions.isBlocked)
        #expect(!actions.isAvailable)
    }

    @Test("blocked compose presentation actions do not invoke closures")
    @MainActor
    func blockedComposePresentationActionsDoNotInvokeClosures() {
        let header = Self.makeHeader()
        var invoked: [String] = []
        let actions = MailComposePresentationActions(
            isBlocked: true,
            newMessage: { invoked.append("new") },
            reply: { invoked.append("reply:\($0.id):\($1?.mailboxID ?? "none")") },
            replyAll: { invoked.append("replyAll:\($0.id):\($1?.mailboxID ?? "none")") },
            forward: { invoked.append("forward:\($0.id):\($1?.mailboxID ?? "none")") }
        )

        actions.newMessage()
        actions.reply(header)
        actions.replyAll(header)
        actions.forward(header)

        #expect(invoked.isEmpty)
    }

    private static func makeHeader() -> MessageHeader {
        MessageHeader(
            id: "message-1",
            threadID: "thread-1",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            subject: "Hello",
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600)
        )
    }
}
