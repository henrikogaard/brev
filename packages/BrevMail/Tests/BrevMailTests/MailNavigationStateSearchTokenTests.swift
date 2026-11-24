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
import Combine
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
        state.isCrossAccountSearchListActive = true

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
        state.isCrossAccountSearchListActive = false
        state.setSearchAllMailboxes(false)
        #expect(!state.searchAllMailboxes)
        #expect(state.selectedSourceID == sourceA)
        #expect(state.selectedFolderID == "work")
        #expect(state.searchOriginSourceFolderID == nil)
        #expect(state.selectedMessageID == nil)

        // Clearing search after selecting a result from the same origin folder preserves that open message.
        state.setSearchAllMailboxes(true)
        state.isCrossAccountSearchListActive = true
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
        state.isCrossAccountSearchListActive = false
        state.clearSearch()
        #expect(state.selectedSourceID == sourceA)
        #expect(state.selectedFolderID == "work")
        #expect(state.selectedMessageID == "msg-a")
        #expect(state.searchOriginSourceFolderID == nil)
        #expect(state.searchAllMailboxes)

        // Removing the result's source during cross-account search falls back cleanly to the surviving origin.
        state.searchText = "invoice"
        state.isCrossAccountSearchListActive = true
        state.selectMessage(headerB, in: sourceB, headers: [headerB])
        #expect(!MailCrossAccountSearchPolicy.shouldNavigateCompactOnFolderChange(
            searchOriginSourceFolderID: state.searchOriginSourceFolderID
        ))
        #expect(!MailCrossAccountSearchPolicy.shouldSyncSelectedFolder(
            isCrossAccountSearchActive: true,
            searchOriginSourceFolderID: state.searchOriginSourceFolderID
        ))
        state.reconcileReaderSources([sourceA])
        state.isCrossAccountSearchListActive = false
        #expect(state.selectedSourceID == sourceA)
        #expect(state.selectedFolderID == "work")
        #expect(state.selectedMessageID == nil)
        #expect(state.searchOriginSourceFolderID == nil)
        #expect(MailCrossAccountSearchPolicy.shouldNavigateCompactOnFolderChange(
            searchOriginSourceFolderID: state.searchOriginSourceFolderID
        ))
        #expect(MailCrossAccountSearchPolicy.shouldSyncSelectedFolder(
            isCrossAccountSearchActive: false,
            searchOriginSourceFolderID: state.searchOriginSourceFolderID
        ))
        // After leaving cross-account search, visible-folder sync falls back if the origin folder was hidden/deleted.
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        #expect(FolderSelectionPolicy.selectedFolderID(afterLoading: [inbox], currentID: state.selectedFolderID) == "inbox")
    }

    @Test("field scope persists across mailbox scope switches and resets on clear or folder change")
    func fieldScopePreservedAcrossMailboxScopeChanges() {
        let sourceA = MailSourceID(accountID: "acct-a", mailboxID: "primary")
        let state = MailNavigationState()
        state.selectFolder("inbox", in: sourceA)
        state.searchText = "maya"
        state.searchFieldScope = .from
        #expect(state.searchScope == .from)

        state.setSearchAllMailboxes(false)
        #expect(state.searchFieldScope == .from)
        #expect(state.searchScope == .from)

        state.setSearchAllMailboxes(true)
        #expect(state.searchFieldScope == .from)
        #expect(state.searchScope == .from)

        state.clearSearch()
        #expect(state.searchFieldScope == .all)
        #expect(state.searchScope == .all)

        state.searchFieldScope = .subject
        state.selectFolder("sent", in: sourceA)
        #expect(state.searchFieldScope == .all)
    }

    #if os(macOS)
    @Test("reader J/K shortcuts step by active surface for cross-account and narrowed folder search")
    func readerShortcutsStepAcrossAccountsDuringCrossAccountSearch() {
        let sourceA = MailSourceID(accountID: "acct-a", mailboxID: "primary")
        let sourceB = MailSourceID(accountID: "acct-b", mailboxID: "primary")
        let state = MailNavigationState()
        state.selectFolder("work", in: sourceA)
        state.searchText = "invoice"
        state.isCrossAccountSearchListActive = true
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

        var steps: [Bool] = []
        let cancellable = state.unifiedReaderStep.sink { steps.append($0) }
        defer { cancellable.cancel() }

        #expect(MailSingleKeyShortcut.next.performInReader(
            navigation: state,
            header: headerB,
            sourceID: sourceB,
            perform: { _, _ in false }
        ))
        #expect(MailSingleKeyShortcut.previous.performInReader(
            navigation: state,
            header: headerB,
            sourceID: sourceB,
            perform: { _, _ in false }
        ))
        #expect(steps == [true, false])

        // In a narrowed "This folder" search, restoring a moved message via undo keeps
        // single-mailbox J/K stepping instead of publishing to unifiedReaderStep.
        state.isCrossAccountSearchListActive = false
        state.setSearchAllMailboxes(false)
        let first = MessageHeader(
            id: "msg-1",
            threadID: "t-1",
            folderID: "work",
            from: Correspondent(email: "maya@example.org"),
            to: [],
            subject: "Invoice 1",
            snippet: "",
            date: Date(timeIntervalSince1970: 300)
        )
        let second = MessageHeader(
            id: "msg-2",
            threadID: "t-2",
            folderID: "work",
            from: Correspondent(email: "maya@example.org"),
            to: [],
            subject: "Invoice 2",
            snippet: "",
            date: Date(timeIntervalSince1970: 250)
        )
        state.restoreMovedSelection(first, in: sourceA, headers: [first, second])
        #expect(state.searchOriginSourceFolderID == nil)
        #expect(MailSingleKeyShortcut.next.performInReader(
            navigation: state,
            header: first,
            sourceID: sourceA,
            perform: { _, _ in false }
        ))
        #expect(state.selectedMessageID == "msg-2")
        #expect(steps == [true, false])
    }
    #endif

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
