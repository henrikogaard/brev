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
import BrevMail
import Foundation
import Testing

@Suite("MailNavigationState adjacent headers")
@MainActor
struct MailNavigationAdjacentHeaderTests {
    @Test("the middle message has both neighbours")
    func middleMessage() {
        let state = Self.state(ids: ["a", "b", "c"], selected: "b")
        #expect(state.previousHeaderID == "a")
        #expect(state.nextHeaderID == "c")
    }

    @Test("the first message has no previous neighbour")
    func firstMessage() {
        let state = Self.state(ids: ["a", "b"], selected: "a")
        #expect(state.previousHeaderID == nil)
        #expect(state.nextHeaderID == "b")
    }

    @Test("the last message has no next neighbour")
    func lastMessage() {
        let state = Self.state(ids: ["a", "b"], selected: "b")
        #expect(state.previousHeaderID == "a")
        #expect(state.nextHeaderID == nil)
    }

    @Test("nothing selected or an unknown selection has no neighbours")
    func noSelection() {
        #expect(Self.state(ids: ["a", "b"], selected: nil).nextHeaderID == nil)
        #expect(Self.state(ids: ["a", "b"], selected: "zzz").previousHeaderID == nil)
        #expect(Self.state(ids: [], selected: "a").nextHeaderID == nil)
    }

    private static func state(ids: [String], selected: String?) -> MailNavigationState {
        let state = MailNavigationState(
            selectedFolderID: "inbox",
            currentFolderHeaders: ids.map(makeHeader)
        )
        state.selectedMessageID = selected
        return state
    }

    private static func makeHeader(id: MessageHeader.ID) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: "inbox",
            from: Correspondent(name: "Ada Lovelace", email: "ada@example.com"),
            to: [Correspondent(name: "Brev", email: "hello@brev.test")],
            subject: "Subject \(id)",
            snippet: "Snippet",
            date: Date(timeIntervalSince1970: 1_735_689_600)
        )
    }
}
