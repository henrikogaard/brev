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

/// The reply docked under the reader (#302 slice 1). It keeps its own context
/// so it survives selection changes and other sheets closing.
@Suite("Navigation inline reply")
@MainActor
struct MailNavigationStateInlineReplyTests {
    private static func header(_ id: String) -> MessageHeader {
        MessageHeader(
            id: id, threadID: "t", folderID: "inbox",
            from: Correspondent(name: "Maya", email: "maya@example.com"),
            subject: "Plan", snippet: "", date: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("opening the inline reply keeps its own context and opens no sheet")
    func opens() {
        let state = MailNavigationState()
        let source = MailSourceID(accountID: "a", mailboxID: "m")
        state.presentInlineReply(to: Self.header("1"), sourceID: source, prefillBodyText: "Sure")

        #expect(state.presentedSheet == nil)
        #expect(state.composePresentationID == 1)
        #expect(state.inlineReply?.replyTo == Self.header("1"))
        #expect(state.inlineReply?.sourceID == source)
        #expect(state.inlineReply?.prefill == ComposePrefill(bodyText: "Sure"))
        #expect(state.inlineReply?.presentationID == 1)
        // The sheet's shared fields stay untouched.
        #expect(state.composeReplyTo == nil)
    }

    @Test("empty text opens without a prefill")
    func emptyPrefill() {
        let state = MailNavigationState()
        state.presentInlineReply(to: Self.header("1"), sourceID: nil, prefillBodyText: "")
        #expect(state.inlineReply != nil)
        #expect(state.inlineReply?.prefill == nil)
    }

    @Test("the reply stays docked when another message is selected")
    func survivesSelection() {
        let state = MailNavigationState()
        state.presentInlineReply(to: Self.header("1"), sourceID: nil, prefillBodyText: nil)
        state.selectedMessageID = "2"
        #expect(state.inlineReply?.replyTo.id == "1")
    }

    @Test("no other composer opens while the reply is docked")
    func blocksOtherCompose() {
        let state = MailNavigationState()
        state.presentInlineReply(to: Self.header("1"), sourceID: nil, prefillBodyText: nil)

        state.presentNewMessage()
        state.presentReply(to: Self.header("2"))
        state.presentInlineReply(to: Self.header("3"), sourceID: nil, prefillBodyText: nil)

        #expect(state.presentedSheet == nil)
        #expect(state.composeReplyTo == nil)
        #expect(state.inlineReply?.replyTo.id == "1")
        #expect(state.composePresentationID == 1)
    }

    @Test("an open compose sheet blocks the inline reply")
    func sheetBlocksInline() {
        let state = MailNavigationState()
        state.presentNewMessage()
        state.presentInlineReply(to: Self.header("1"), sourceID: nil, prefillBodyText: nil)
        #expect(state.inlineReply == nil)
    }

    @Test("closing the reply frees the composer again")
    func dismiss() {
        let state = MailNavigationState()
        state.presentInlineReply(to: Self.header("1"), sourceID: nil, prefillBodyText: nil)
        state.dismissInlineReply()
        #expect(state.inlineReply == nil)

        state.presentReply(to: Self.header("2"))
        #expect(state.presentedSheet == .compose)
    }
}
