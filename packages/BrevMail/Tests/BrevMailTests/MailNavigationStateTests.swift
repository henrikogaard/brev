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
import BrevThemes
import Foundation
import Testing

@Suite("MailNavigationState")
@MainActor
struct MailNavigationStateTests {
    @Test("a row selection repairs cleared reader headers without changing folder scope")
    func rowSelectionRestoresReaderContext() {
        let source = MailSourceID(accountID: "work", mailboxID: "work")
        let state = MailNavigationState(selectedSourceID: source, selectedFolderID: "search-folder")
        let header = Self.makeHeader(id: "message")
        state.selectMessage(header, from: [header])
        #expect(state.selectedHeader == header)
        #expect(state.selectedSourceID == source)
        #expect(state.selectedFolderID == "search-folder")
    }

    @Test("excluding the reader account preserves the collection and clears its private content")
    func excludedReaderIsCleared() {
        let state = MailNavigationState()
        let source = MailSourceID(accountID: "work", mailboxID: "work")
        let header = Self.makeHeader(id: "message")
        state.selectUnifiedInbox()
        state.selectMessage(header, in: source, headers: [header])
        state.reconcileReaderSources([])
        #expect(state.isUnifiedInboxSelected)
        #expect(state.selectedSourceID == nil)
        #expect(state.selectedHeader == nil)
        #expect(state.currentFolderHeaders.isEmpty)
    }

    @Test("reading a unified message preserves the collection and routes the reader to its owner")
    func readingUnifiedMessagePreservesCollection() {
        let state = MailNavigationState()
        let source = MailSourceID(accountID: "work", mailboxID: "work")
        let header = Self.makeHeader(id: "message")
        state.selectUnifiedInbox()
        state.selectMessage(header, in: source, headers: [header])
        #expect(state.isUnifiedInboxSelected)
        #expect(state.selectedSourceID == source)
        #expect(state.selectedHeader == header)
        state.selectFolder("sent", in: source)
        #expect(!state.isUnifiedInboxSelected)
    }

    @Test("reading a saved search result preserves the saved search")
    func readingSavedSearchPreservesCollection() {
        let state = MailNavigationState()
        let source = MailSourceID(accountID: "work", mailboxID: "work")
        let header = Self.makeHeader(id: "message")
        state.selectSavedSearch(id: "invoices")
        state.selectMessage(header, in: source, headers: [header])
        #expect(state.selectedSavedSearchID == "invoices")
        state.selectFlaggedSmartView()
        state.selectMessage(header, in: source, headers: [header])
        #expect(state.isFlaggedSmartViewSelected)
    }

    @Test("selectedHeader returns nil when no selection is set")
    func selectedHeaderNilWithoutSelection() {
        let state = MailNavigationState()
        #expect(state.selectedHeader == nil)
    }

    @Test("selectedHeader resolves against currentFolderHeaders")
    func selectedHeaderResolvesAgainstLoadedHeaders() async throws {
        let backend = MockBackend()
        let folders = try await backend.folders()
        let inbox = try #require(folders.first { $0.role == .inbox })
        let page = try await backend.messages(in: inbox, pageToken: nil)
        let target = try #require(page.headers.first)

        let state = MailNavigationState(
            selectedFolderID: inbox.id,
            selectedMessageID: target.id,
            currentFolderHeaders: page.headers
        )

        #expect(state.selectedHeader?.id == target.id)
    }

    @Test("requestReload increments the reload request id")
    func requestReloadIncrementsReloadRequestID() {
        let state = MailNavigationState()
        let first = state.reloadRequestID

        state.requestReload()

        #expect(state.reloadRequestID == first + 1)
    }

    @Test("visible folder change events request a reload")
    func visibleFolderEventsRequestReload() {
        let state = MailNavigationState(selectedFolderID: "sent")
        let first = state.reloadRequestID

        state.requestReloadIfVisibleFolderChanged(
            .messagesAdded(folderID: "sent", messageIDs: ["m1"])
        )

        #expect(state.reloadRequestID == first + 1)
    }

    @Test("unrelated folder change events do not request a reload")
    func unrelatedFolderEventsDoNotRequestReload() {
        let state = MailNavigationState(selectedFolderID: "inbox")
        let first = state.reloadRequestID

        state.requestReloadIfVisibleFolderChanged(
            .messagesAdded(folderID: "sent", messageIDs: ["m1"])
        )

        #expect(state.reloadRequestID == first)
    }

    @Test("mailbox switch reset clears mailbox-scoped navigation")
    func mailboxSwitchResetClearsMailboxScopedNavigation() {
        let first = Self.makeHeader(id: "first")
        let second = Self.makeHeader(id: "second")
        let sourceID = MailSourceID(accountID: "account-1", mailboxID: "mailbox-1")
        let state = MailNavigationState(
            selectedSourceID: sourceID,
            selectedFolderID: "inbox",
            selectedMessageID: first.id,
            searchText: "invoice",
            presentedSheet: .profiles,
            currentFolderHeaders: [first, second],
            bulkSelection: [first.id, second.id],
            reloadRequestID: 4
        )

        state.resetForMailboxSwitch()

        #expect(state.selectedSourceID == nil)
        #expect(state.selectedFolderID == nil)
        #expect(state.selectedMessageID == nil)
        #expect(state.currentFolderHeaders.isEmpty)
        #expect(state.bulkSelection.isEmpty)
        #expect(state.searchText == "invoice")
        #expect(state.presentedSheet == .profiles)
        #expect(state.reloadRequestID == 4)
    }

    @Test("selecting a source folder clears message-scoped state")
    func selectingSourceFolderClearsMessageScopedState() {
        let oldHeader = Self.makeHeader(id: "old")
        let sourceID = MailSourceID(accountID: "account-1", mailboxID: "mailbox-1")
        let state = MailNavigationState(
            selectedMessageID: oldHeader.id,
            currentFolderHeaders: [oldHeader],
            bulkSelection: [oldHeader.id]
        )

        state.selectFolder("inbox", in: sourceID)

        #expect(state.selectedSourceID == sourceID)
        #expect(state.selectedFolderID == "inbox")
        #expect(state.selectedMessageID == nil)
        #expect(state.currentFolderHeaders.isEmpty)
        #expect(state.bulkSelection.isEmpty)
    }

    @Test("removing the selected header selects the next visible header")
    func removeSelectedHeaderSelectsNextVisibleHeader() {
        let first = Self.makeHeader(id: "first")
        let second = Self.makeHeader(id: "second")
        let third = Self.makeHeader(id: "third")
        let state = MailNavigationState(
            selectedMessageID: second.id,
            currentFolderHeaders: [first, second, third]
        )

        state.removeHeaders(ids: [second.id])

        #expect(state.selectedMessageID == third.id)
        #expect(state.currentFolderHeaders.map(\.id) == [first.id, third.id])
    }

    @Test("removing the last selected header selects the previous visible header")
    func removeLastSelectedHeaderSelectsPreviousVisibleHeader() {
        let first = Self.makeHeader(id: "first")
        let second = Self.makeHeader(id: "second")
        let state = MailNavigationState(
            selectedMessageID: second.id,
            currentFolderHeaders: [first, second]
        )

        state.removeHeaders(ids: [second.id])

        #expect(state.selectedMessageID == first.id)
        #expect(state.currentFolderHeaders.map(\.id) == [first.id])
    }

    @Test("removing the selection plus an earlier row selects the next survivor, not past it")
    func removeSelectionWithEarlierRowSelectsNextSurvivor() {
        let first = Self.makeHeader(id: "first")
        let second = Self.makeHeader(id: "second")
        let third = Self.makeHeader(id: "third")
        let fourth = Self.makeHeader(id: "fourth")
        let fifth = Self.makeHeader(id: "fifth")
        let state = MailNavigationState(
            selectedMessageID: third.id,
            currentFolderHeaders: [first, second, third, fourth, fifth]
        )

        // Removing an earlier row in the same batch used to shift the saved
        // index, so the selection jumped past `fourth` to `fifth`.
        state.removeHeaders(ids: [first.id, third.id])

        #expect(state.selectedMessageID == fourth.id)
        #expect(state.currentFolderHeaders.map(\.id) == [second.id, fourth.id, fifth.id])
    }

    @Test("removing the selection and every later row falls back to the last survivor")
    func removeSelectionAndTailFallsBackToLastSurvivor() {
        let first = Self.makeHeader(id: "first")
        let second = Self.makeHeader(id: "second")
        let third = Self.makeHeader(id: "third")
        let state = MailNavigationState(
            selectedMessageID: second.id,
            currentFolderHeaders: [first, second, third]
        )

        state.removeHeaders(ids: [second.id, third.id])

        #expect(state.selectedMessageID == first.id)
        #expect(state.currentFolderHeaders.map(\.id) == [first.id])
    }

    @Test("removing the only selected header clears selection")
    func removeOnlySelectedHeaderClearsSelection() {
        let only = Self.makeHeader(id: "only")
        let state = MailNavigationState(
            selectedMessageID: only.id,
            currentFolderHeaders: [only]
        )

        state.removeHeaders(ids: [only.id])

        #expect(state.selectedMessageID == nil)
        #expect(state.currentFolderHeaders.isEmpty)
    }

    @Test("replacing headers preserves an existing selected header")
    func replaceHeadersPreservesExistingSelectedHeader() {
        let first = Self.makeHeader(id: "first")
        let second = Self.makeHeader(id: "second")
        let state = MailNavigationState(
            selectedMessageID: second.id,
            currentFolderHeaders: [first, second]
        )

        state.replaceCurrentFolderHeaders([second, first])

        #expect(state.selectedMessageID == second.id)
        #expect(state.currentFolderHeaders.map(\.id) == [second.id, first.id])
    }

    @Test("replacing headers can select the first header when no message is selected")
    func replaceHeadersCanSelectFirstHeaderWhenNoMessageIsSelected() {
        let first = Self.makeHeader(id: "first")
        let second = Self.makeHeader(id: "second")
        let state = MailNavigationState(selectedMessageID: nil)

        state.replaceCurrentFolderHeaders([first, second], selectFirstIfNeeded: true)

        #expect(state.selectedMessageID == first.id)
        #expect(state.currentFolderHeaders.map(\.id) == [first.id, second.id])
    }

    @Test("replacing headers keeps nil selection by default")
    func replaceHeadersKeepsNilSelectionByDefault() {
        let first = Self.makeHeader(id: "first")
        let state = MailNavigationState(selectedMessageID: nil)

        state.replaceCurrentFolderHeaders([first])

        #expect(state.selectedMessageID == nil)
        #expect(state.currentFolderHeaders.map(\.id) == [first.id])
    }

    @Test("replacing headers advances stale selection to the next loaded header")
    func replaceHeadersAdvancesStaleSelectionToNextLoadedHeader() {
        let first = Self.makeHeader(id: "first")
        let second = Self.makeHeader(id: "second")
        let third = Self.makeHeader(id: "third")
        let state = MailNavigationState(
            selectedMessageID: second.id,
            currentFolderHeaders: [first, second, third]
        )

        state.replaceCurrentFolderHeaders([first, third])

        #expect(state.selectedMessageID == third.id)
        #expect(state.currentFolderHeaders.map(\.id) == [first.id, third.id])
    }

    @Test("replacing headers falls back to previous header when stale selection was last")
    func replaceHeadersFallsBackToPreviousWhenStaleSelectionWasLast() {
        let first = Self.makeHeader(id: "first")
        let second = Self.makeHeader(id: "second")
        let state = MailNavigationState(
            selectedMessageID: second.id,
            currentFolderHeaders: [first, second]
        )

        state.replaceCurrentFolderHeaders([first])

        #expect(state.selectedMessageID == first.id)
    }

    @Test("replacing headers clears stale selection when no headers remain")
    func replaceHeadersClearsStaleSelectionWhenNoHeadersRemain() {
        let only = Self.makeHeader(id: "only")
        let state = MailNavigationState(
            selectedMessageID: only.id,
            currentFolderHeaders: [only]
        )

        state.replaceCurrentFolderHeaders([])

        #expect(state.selectedMessageID == nil)
    }

    @Test("selecting next header advances within the loaded folder")
    func selectNextHeaderAdvancesWithinLoadedFolder() {
        let first = Self.makeHeader(id: "first")
        let second = Self.makeHeader(id: "second")
        let third = Self.makeHeader(id: "third")
        let state = MailNavigationState(
            selectedMessageID: first.id,
            currentFolderHeaders: [first, second, third]
        )

        state.selectNextHeader()

        #expect(state.selectedMessageID == second.id)
    }

    @Test("selecting previous header moves backward within the loaded folder")
    func selectPreviousHeaderMovesBackwardWithinLoadedFolder() {
        let first = Self.makeHeader(id: "first")
        let second = Self.makeHeader(id: "second")
        let third = Self.makeHeader(id: "third")
        let state = MailNavigationState(
            selectedMessageID: third.id,
            currentFolderHeaders: [first, second, third]
        )

        state.selectPreviousHeader()

        #expect(state.selectedMessageID == second.id)
    }

    @Test("adjacent selection stays put at list boundaries")
    func adjacentSelectionStaysPutAtListBoundaries() {
        let first = Self.makeHeader(id: "first")
        let second = Self.makeHeader(id: "second")
        let state = MailNavigationState(
            selectedMessageID: first.id,
            currentFolderHeaders: [first, second]
        )

        state.selectPreviousHeader()
        #expect(state.selectedMessageID == first.id)

        state.selectedMessageID = second.id
        state.selectNextHeader()
        #expect(state.selectedMessageID == second.id)
    }

    @Test("adjacent selection chooses the first header when nothing is selected")
    func adjacentSelectionChoosesFirstHeaderWhenNothingIsSelected() {
        let first = Self.makeHeader(id: "first")
        let second = Self.makeHeader(id: "second")
        let state = MailNavigationState(
            selectedMessageID: nil,
            currentFolderHeaders: [first, second]
        )

        state.selectNextHeader()
        #expect(state.selectedMessageID == first.id)

        state.selectedMessageID = nil
        state.selectPreviousHeader()
        #expect(state.selectedMessageID == first.id)
    }

    @Test("presentNewMessage clears reply and forward state")
    func presentNewMessageClearsComposeContext() {
        let replyHeader = Self.makeHeader(id: "reply")
        let forwardHeader = Self.makeHeader(id: "forward")
        let state = MailNavigationState()
        state.composeReplyTo = replyHeader
        state.composeForwardOf = forwardHeader

        state.presentNewMessage()

        #expect(state.presentedSheet == .compose)
        #expect(state.composePresentationID == 1)
        #expect(state.composeReplyTo == nil)
        #expect(state.composeForwardOf == nil)
    }

    @Test("compose presentations do not replace an active sheet")
    func composePresentationsDoNotReplaceActiveSheet() {
        let replyHeader = Self.makeHeader(id: "reply")
        let state = MailNavigationState(presentedSheet: .profiles)
        state.composeForwardOf = Self.makeHeader(id: "stale-forward")

        state.presentReply(to: replyHeader)

        #expect(state.presentedSheet == .profiles)
        #expect(state.composePresentationID == 0)
        #expect(state.composeReplyTo == nil)
        #expect(state.composeForwardOf?.id == "stale-forward")
    }

    @Test("select flagged smart view clears folder and message context")
    func selectFlaggedSmartViewClearsFolderAndMessageContext() {
        let state = MailNavigationState(
            selectedSourceID: MailSourceID(accountID: "account-a", mailboxID: "mailbox-a"),
            selectedFolderID: "inbox",
            selectedMessageID: "message-1",
            currentFolderHeaders: [Self.makeHeader(id: "message-1")]
        )
        state.bulkSelection = ["message-1"]

        state.selectFlaggedSmartView()

        #expect(state.isFlaggedSmartViewSelected)
        #expect(state.selectedSourceID == nil)
        #expect(state.selectedFolderID == MailNavigationState.flaggedSmartViewFolderID)
        #expect(state.selectedMessageID == nil)
        #expect(state.currentFolderHeaders.isEmpty)
        #expect(state.bulkSelection.isEmpty)
    }

    @Test("selecting snoozed and done smart views clears folder and message context")
    func selectingWorkflowSmartViewsClearsFolderAndMessageContext() {
        let state = MailNavigationState(
            selectedSourceID: MailSourceID(accountID: "account-a", mailboxID: "mailbox-a"),
            selectedFolderID: "inbox",
            selectedMessageID: "message-1",
            currentFolderHeaders: [Self.makeHeader(id: "message-1")],
            bulkSelection: ["message-1"]
        )

        state.selectSnoozedSmartView()

        #expect(state.isSnoozedSmartViewSelected)
        #expect(state.isSmartViewSelected)
        #expect(state.selectedSourceID == nil)
        #expect(state.selectedFolderID == MailNavigationState.snoozedSmartViewFolderID)
        #expect(state.selectedMessageID == nil)
        #expect(state.currentFolderHeaders.isEmpty)
        #expect(state.bulkSelection.isEmpty)

        state.selectedSourceID = MailSourceID(accountID: "account-a", mailboxID: "mailbox-a")
        state.selectedFolderID = "inbox"
        state.selectedMessageID = "message-2"
        state.currentFolderHeaders = [Self.makeHeader(id: "message-2")]
        state.bulkSelection = ["message-2"]

        state.selectDoneSmartView()

        #expect(state.isDoneSmartViewSelected)
        #expect(state.isSmartViewSelected)
        #expect(state.selectedSourceID == nil)
        #expect(state.selectedFolderID == MailNavigationState.doneSmartViewFolderID)
        #expect(state.selectedMessageID == nil)
        #expect(state.currentFolderHeaders.isEmpty)
        #expect(state.bulkSelection.isEmpty)
    }

    @Test("move sheet carries source and current folder context")
    func moveSheetCarriesSourceAndCurrentFolderContext() {
        let sourceID = MailSourceID(accountID: "account-a", mailboxID: "mailbox-a")
        let state = MailNavigationState()

        state.presentedSheet = .moveTo(
            messageIDs: ["message-1"],
            sourceID: sourceID,
            currentFolderID: "inbox"
        )

        #expect(state.presentedSheet == .moveTo(
            messageIDs: ["message-1"],
            sourceID: sourceID,
            currentFolderID: "inbox"
        ))
    }

    @Test("copy sheet carries source and current folder context")
    func copySheetCarriesSourceAndCurrentFolderContext() {
        let sourceID = MailSourceID(accountID: "account-a", mailboxID: "mailbox-a")
        let state = MailNavigationState()

        state.presentedSheet = .copyTo(
            messageIDs: ["message-1"],
            sourceID: sourceID,
            currentFolderID: "inbox"
        )

        #expect(state.presentedSheet == .copyTo(
            messageIDs: ["message-1"],
            sourceID: sourceID,
            currentFolderID: "inbox"
        ))
    }

    @Test("presentReply opens compose with only reply context")
    func presentReplySetsReplyContext() {
        let replyHeader = Self.makeHeader(id: "reply")
        let staleForwardHeader = Self.makeHeader(id: "forward")
        let sourceID = MailSourceID(accountID: "account-1", mailboxID: "mailbox-1")
        let state = MailNavigationState()
        state.composeForwardOf = staleForwardHeader
        state.composePrefill = ComposePrefill(bodyText: "Shared")

        state.presentReply(to: replyHeader, sourceID: sourceID)

        #expect(state.presentedSheet == .compose)
        #expect(state.composePresentationID == 1)
        #expect(state.composeReplyTo == replyHeader)
        #expect(state.composeForwardOf == nil)
        #expect(state.composePrefill == nil)
        #expect(state.composeSourceID == sourceID)
    }

    @Test("presentReplyAll opens compose with reply-all context")
    func presentReplyAllSetsReplyAllContext() {
        let replyHeader = Self.makeHeader(id: "reply-all")
        let staleForwardHeader = Self.makeHeader(id: "forward")
        let sourceID = MailSourceID(accountID: "account-1", mailboxID: "mailbox-1")
        let state = MailNavigationState()
        state.composeForwardOf = staleForwardHeader

        state.presentReplyAll(to: replyHeader, sourceID: sourceID)

        #expect(state.presentedSheet == .compose)
        #expect(state.composePresentationID == 1)
        #expect(state.composeReplyTo == replyHeader)
        #expect(state.composeReplyMode == .all)
        #expect(state.composeForwardOf == nil)
        #expect(state.composeSourceID == sourceID)
    }

    @Test("presentForward opens compose with only forward context")
    func presentForwardSetsForwardContext() {
        let forwardHeader = Self.makeHeader(id: "forward")
        let staleReplyHeader = Self.makeHeader(id: "reply")
        let sourceID = MailSourceID(accountID: "account-1", mailboxID: "mailbox-1")
        let state = MailNavigationState()
        state.composeReplyTo = staleReplyHeader
        state.composePrefill = ComposePrefill(bodyText: "Shared")

        state.presentForward(of: forwardHeader, sourceID: sourceID)

        #expect(state.presentedSheet == .compose)
        #expect(state.composePresentationID == 1)
        #expect(state.composeReplyTo == nil)
        #expect(state.composeReplyMode == .sender)
        #expect(state.composeForwardOf == forwardHeader)
        #expect(state.composePrefill == nil)
        #expect(state.composeSourceID == sourceID)
    }

    @Test("presentNewMessage with prefill opens compose with shared context")
    func presentNewMessageWithPrefillSetsSharedContext() {
        let state = MailNavigationState()
        let prefill = ComposePrefill(subject: "Shared", bodyText: "Shared body")

        state.presentNewMessage(prefill: prefill)

        #expect(state.presentedSheet == .compose)
        #expect(state.composePresentationID == 1)
        #expect(state.composeReplyTo == nil)
        #expect(state.composeForwardOf == nil)
        #expect(state.composePrefill == prefill)
    }

    @Test("compose presentation id increments for repeated compose presentations")
    func composePresentationIDIncrementsForSequentialComposePresentations() {
        let state = MailNavigationState()

        state.presentNewMessage()
        state.presentedSheet = nil
        state.presentNewMessage()

        #expect(state.composePresentationID == 2)
    }

    @Test("compose presentation id does not increment while compose is already active")
    func composePresentationIDDoesNotIncrementWhileComposeIsAlreadyActive() {
        let state = MailNavigationState()

        state.presentNewMessage()
        state.presentNewMessage()

        #expect(state.presentedSheet == .compose)
        #expect(state.composePresentationID == 1)
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
