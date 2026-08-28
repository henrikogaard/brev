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
import Testing

@Suite("Initial mailbox selection presentation")
struct InitialMailboxSelectionPresentationTests {
    private let primary = MailSourceID(accountID: "acct", mailboxID: "primary")
    private let alias = MailSourceID(accountID: "acct", mailboxID: "alias")
    private let shared = MailSourceID(accountID: "acct", mailboxID: "shared")

    @Test("guidance copy is provider neutral")
    func guidanceCopyIsProviderNeutral() {
        #expect(InitialMailboxSelectionPresentation.guidanceText.contains("mailboxes"))
    }

    @Test("initial state enables every source and prefers the primary mailbox")
    func initialStateEnablesEverySourceAndPrefersPrimaryMailbox() {
        let state = InitialMailboxSelectionPresentation.initialState(
            availableSourceIDs: [alias, primary, shared],
            preferredDefaultSourceID: primary,
            preferences: .defaults
        )

        #expect(state.selectedSourceIDs == [alias, primary, shared])
        #expect(state.defaultSourceID == primary)
    }

    @Test("disabling the default mailbox chooses the next selected source")
    func disablingDefaultMailboxChoosesNextSelectedSource() {
        let state = InitialMailboxSelectionPresentation.SelectionState(
            selectedSourceIDs: [primary, alias, shared],
            defaultSourceID: primary
        )

        let updated = InitialMailboxSelectionPresentation.setSource(
            primary,
            isEnabled: false,
            in: state,
            orderedSourceIDs: [primary, alias, shared]
        )

        #expect(updated.selectedSourceIDs == [alias, shared])
        #expect(updated.defaultSourceID == alias)
    }

    @Test("last enabled mailbox cannot be disabled")
    func lastEnabledMailboxCannotBeDisabled() {
        let state = InitialMailboxSelectionPresentation.SelectionState(
            selectedSourceIDs: [primary],
            defaultSourceID: primary
        )

        let updated = InitialMailboxSelectionPresentation.setSource(
            primary,
            isEnabled: false,
            in: state,
            orderedSourceIDs: [primary, alias]
        )

        #expect(updated == state)
    }

    @Test("making a disabled mailbox default enables it")
    func makingDisabledMailboxDefaultEnablesIt() {
        let state = InitialMailboxSelectionPresentation.SelectionState(
            selectedSourceIDs: [primary],
            defaultSourceID: primary
        )

        let updated = InitialMailboxSelectionPresentation.makeDefault(
            alias,
            in: state
        )

        #expect(updated.selectedSourceIDs == [primary, alias])
        #expect(updated.defaultSourceID == alias)
    }
}
