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

@testable import BrevMail
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

    @Test("clearSearch drops text, tokens and the mailbox scope")
    func clearSearch() {
        let state = MailNavigationState(searchText: "x")
        state.searchTokens = [.unread]
        state.searchAllMailboxes = true
        state.clearSearch()
        #expect(state.searchText.isEmpty)
        #expect(state.searchTokens.isEmpty)
        #expect(!state.searchAllMailboxes)
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
