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

@Suite("MailNavigationState search tokens")
@MainActor
struct MailNavigationStateSearchTokenTests {
    @Test("searchText stays the one query string every list reads")
    func searchTextComposesTokensAndText() {
        let state = MailNavigationState(searchText: "invoices")
        #expect(state.searchText == "invoices")
        #expect(state.searchTokens.isEmpty)

        state.searchTokens = [.unread]
        #expect(state.searchText == "unread invoices")

        state.searchFreeText = ""
        #expect(state.searchText == "unread")
    }

    @Test("assigning searchText replaces the whole query, tokens included")
    func assigningSearchTextClearsTokens() {
        let state = MailNavigationState(searchText: "x")
        state.searchTokens = [.flagged, .field(.subject)]
        state.searchText = "from: ada@example.com"
        #expect(state.searchFreeText == "from: ada@example.com")
        #expect(state.searchTokens.isEmpty)

        state.searchText = ""
        #expect(state.searchText.isEmpty)
    }

    @Test("clearSearch drops text and tokens and restores default cross-account scope")
    func clearSearch() {
        let state = MailNavigationState(searchText: "x")
        #expect(state.searchAllMailboxes)
        state.searchTokens = [.unread]
        state.setSearchAllMailboxes(false)
        #expect(!state.searchAllMailboxes)
        state.clearSearch()
        #expect(state.searchText.isEmpty)
        #expect(state.searchTokens.isEmpty)
        #expect(state.searchAllMailboxes)
    }

    @Test("cross-account search routes reader per source and restores origin folder on narrow or clear")
    func crossAccountSearchOriginRoutingAndRestoration() {
        let sourceA = MailSourceID(accountID: "acct-a", mailboxID: "primary")
        let sourceB = MailSourceID(accountID: "acct-b", mailboxID: "primary")
        let state = MailNavigationState()
        state.selectFolder("work", in: sourceA)
        state.searchText = "invoice"

        let headerB = MessageHeader(
            id: "msg-b",
            threadID: "t-b",
            folderID: "archive",
            from: Correspondent(email: "maya@example.org"),
            to: [],
            subject: "Invoice B",
            snippet: "",
            date: Date(timeIntervalSince1970: 200)
        )
        state.selectMessage(headerB, in: sourceB, headers: [headerB])
        #expect(state.selectedSourceID == sourceB)
        #expect(state.selectedFolderID == "archive")
        #expect(state.selectedMessageID == "msg-b")
        #expect(state.searchOriginSourceFolderID == SourceFolderID(sourceID: sourceA, folderID: "work"))
        #expect(state.browsingSourceFolderID == SourceFolderID(sourceID: sourceA, folderID: "work"))

        // Narrowing to "This folder" restores the origin source/folder and drops the cross-account reader item.
        state.setSearchAllMailboxes(false)
        #expect(!state.searchAllMailboxes)
        #expect(state.selectedSourceID == sourceA)
        #expect(state.selectedFolderID == "work")
        #expect(state.searchOriginSourceFolderID == nil)
        #expect(state.selectedMessageID == nil)

        // Clearing search after selecting a result from the same origin folder preserves that open message.
        state.setSearchAllMailboxes(true)
        let headerA = MessageHeader(
            id: "msg-a",
            threadID: "t-a",
            folderID: "work",
            from: Correspondent(email: "maya@example.org"),
            to: [],
            subject: "Invoice A",
            snippet: "",
            date: Date(timeIntervalSince1970: 300)
        )
        state.selectMessage(headerA, in: sourceA, headers: [headerA])
        state.clearSearch()
        #expect(state.selectedSourceID == sourceA)
        #expect(state.selectedFolderID == "work")
        #expect(state.selectedMessageID == "msg-a")
        #expect(state.searchOriginSourceFolderID == nil)
        #expect(state.searchAllMailboxes)

        // Removing the result's source during cross-account search falls back cleanly to the surviving origin.
        state.searchText = "invoice"
        state.selectMessage(headerB, in: sourceB, headers: [headerB])
        state.reconcileReaderSources([sourceA])
        #expect(state.selectedSourceID == sourceA)
        #expect(state.selectedFolderID == "work")
        #expect(state.selectedMessageID == nil)
        #expect(state.searchOriginSourceFolderID == nil)
    }

    @Test("a field token drives the list's search scope")
    func fieldTokenDrivesScope() {
        let state = MailNavigationState()
        #expect(state.searchScope == .all)
        state.searchTokens = [.field(.from)]
        #expect(state.searchScope == .from)
    }

    @Test("submitting converts typed predicates into tokens")
    func commitSearchConvertsPredicates() {
        let state = MailNavigationState(searchText: "unread invoices")
        state.commitSearch()
        #expect(state.searchTokens == [.unread])
        #expect(state.searchFreeText == "invoices")
        #expect(state.searchText == "unread invoices")
    }

    @Test("submitting under a field token leaves the typed text alone")
    func commitSearchRespectsFieldToken() {
        let state = MailNavigationState(searchText: "unread")
        state.searchTokens = [.field(.subject)]
        state.commitSearch()
        #expect(state.searchTokens == [.field(.subject)])
        #expect(state.searchFreeText == "unread")
    }
}
