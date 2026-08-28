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
import BrevSettings
import Foundation
import Testing

@MainActor
@Suite("MailNavigationState attachment + saved search")
struct MailNavigationStateAttachmentSavedSearchTests {
    @Test("smart mailbox value is visible to BrevMail")
    func smartMailboxVisibleToBrevMail() {
        let mailbox = SmartMailbox(
            id: "s1",
            name: "Invoices",
            kind: .attachmentSearch,
            query: SmartMailbox.SavedQuery(text: "invoice"),
            isEnabled: true
        )
        #expect(mailbox.name == "Invoices")
        #expect(mailbox.kind == .attachmentSearch)
    }

    @Test("selecting all attachments sets the smart view and clears selection")
    func selectAllAttachments() {
        let nav = MailNavigationState()
        nav.selectedMessageID = "m1"
        nav.selectAllAttachmentsSmartView()
        #expect(nav.isAllAttachmentsSelected)
        #expect(nav.selectedSourceID == nil)
        #expect(nav.selectedMessageID == nil)
        #expect(nav.isSmartViewSelected == false)
    }

    @Test("showing all mail from sender forces cache-only search")
    func showAllMailFromSenderForcesCacheOnlySearch() {
        let nav = MailNavigationState(
            searchText: "quarterly",
            presentedSheet: .compose,
            bulkSelection: ["m1", "m2"]
        )
        nav.searchExecution = .serverOnly
        nav.hasUserSelectedSearchExecution = false

        nav.showAllMailFromSender("ada@example.com")

        #expect(nav.searchText == "from: ada@example.com")
        #expect(nav.searchExecution == .cacheOnly)
        #expect(nav.hasUserSelectedSearchExecution)
        #expect(nav.presentedSheet == nil)
        #expect(nav.bulkSelection.isEmpty)
    }

    @Test("selecting a saved search records its id")
    func selectSavedSearch() {
        let nav = MailNavigationState()
        nav.selectSavedSearch(id: "s1")
        #expect(nav.selectedSavedSearchID == "s1")
        #expect(nav.isSavedSearchSelected(id: "s1"))
        #expect(nav.isSavedSearchSelected(id: "other") == false)
    }

    // The message-list pane routes on these flags in order; a selected saved
    // search must be distinguishable from the built-in smart views / unified
    // inbox so it reaches `savedSearchPane` rather than the folderless `else`.
    @Test("a selected saved search is neither a smart view nor the unified inbox")
    func savedSearchIsDistinctFromSmartViews() {
        let nav = MailNavigationState()
        nav.selectSavedSearch(id: "s1")
        #expect(nav.isSmartViewSelected == false)
        #expect(nav.isUnifiedInboxSelected == false)
        #expect(nav.isAllAttachmentsSelected == false)
    }

    @Test("selecting the unified inbox clears a previously selected saved search")
    func unifiedInboxClearsSavedSearch() {
        let nav = MailNavigationState()
        nav.selectSavedSearch(id: "s1")
        nav.selectUnifiedInbox()
        #expect(nav.selectedSavedSearchID == nil)
        #expect(nav.isUnifiedInboxSelected)
    }

    @Test("the persisted saved query maps to a backend search query the pane filters with")
    func savedQueryMapsToSearchQuery() {
        let saved = SmartMailbox.SavedQuery(
            text: "invoice",
            from: "billing@acme.test",
            isUnread: true
        )
        let query = saved.searchQuery
        #expect(query.text == "invoice")
        #expect(query.from == "billing@acme.test")
        #expect(query.isUnread == true)
    }
}
