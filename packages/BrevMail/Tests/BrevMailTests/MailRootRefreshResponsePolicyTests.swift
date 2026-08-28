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

@Suite("MailRootRefreshResponsePolicy")
struct MailRootRefreshResponsePolicyTests {
    @Test("matching active refresh request, folder, and mailbox can apply response")
    func matchingActiveRefreshRequestFolderAndMailboxCanApplyResponse() {
        let request = MailRootRefreshRequest(
            id: 1,
            folderID: "inbox",
            mailboxID: "mailbox-a"
        )

        #expect(MailRootRefreshResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentSelectedFolderID: "inbox",
            currentMailboxID: "mailbox-a"
        ))
    }

    @Test("unknown request mailbox can apply when the folder still matches")
    func unknownRequestMailboxCanApplyWhenFolderStillMatches() {
        let request = MailRootRefreshRequest(
            id: 1,
            folderID: "inbox",
            mailboxID: nil
        )

        #expect(MailRootRefreshResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentSelectedFolderID: "inbox",
            currentMailboxID: "mailbox-a"
        ))
    }

    @Test("changed or missing active request rejects stale refresh response")
    func changedOrMissingActiveRequestRejectsStaleRefreshResponse() {
        let request = MailRootRefreshRequest(
            id: 1,
            folderID: "inbox",
            mailboxID: "mailbox-a"
        )

        #expect(!MailRootRefreshResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: MailRootRefreshRequest(
                id: 2,
                folderID: "inbox",
                mailboxID: "mailbox-a"
            ),
            currentSelectedFolderID: "inbox",
            currentMailboxID: "mailbox-a"
        ))
        #expect(!MailRootRefreshResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: nil,
            currentSelectedFolderID: "inbox",
            currentMailboxID: "mailbox-a"
        ))
    }

    @Test("folder or mailbox changes reject stale refresh response")
    func folderOrMailboxChangesRejectStaleRefreshResponse() {
        let request = MailRootRefreshRequest(
            id: 1,
            folderID: "inbox",
            mailboxID: "mailbox-a"
        )

        #expect(!MailRootRefreshResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentSelectedFolderID: "archive",
            currentMailboxID: "mailbox-a"
        ))
        #expect(!MailRootRefreshResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentSelectedFolderID: "inbox",
            currentMailboxID: "mailbox-b"
        ))
        #expect(!MailRootRefreshResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentSelectedFolderID: "inbox",
            currentMailboxID: nil
        ))
    }

    @Test("refresh can start when no refresh is active")
    func refreshCanStartWhenNoRefreshIsActive() {
        #expect(MailRootRefreshStartPolicy.canStartRefresh(
            activeRequest: nil,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeCommandMutationRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("refresh cannot start while another refresh is active")
    func refreshCannotStartWhileAnotherRefreshIsActive() {
        #expect(!MailRootRefreshStartPolicy.canStartRefresh(
            activeRequest: MailRootRefreshRequest(
                id: 1,
                folderID: "inbox",
                mailboxID: "mailbox-a"
            ),
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeCommandMutationRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("refresh cannot start while root folder load is active")
    func refreshCannotStartWhileRootFolderLoadIsActive() {
        #expect(!MailRootRefreshStartPolicy.canStartRefresh(
            activeRequest: nil,
            activeFolderLoadRequest: MailRootFolderLoadRequest(id: 1),
            activeMailboxLoadRequest: nil,
            activeCommandMutationRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("refresh cannot start while root mailbox load is active")
    func refreshCannotStartWhileRootMailboxLoadIsActive() {
        #expect(!MailRootRefreshStartPolicy.canStartRefresh(
            activeRequest: nil,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: MailRootMailboxLoadRequest(id: 1),
            activeCommandMutationRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("refresh cannot start while a command mutation is active")
    func refreshCannotStartWhileCommandMutationIsActive() {
        #expect(!MailRootRefreshStartPolicy.canStartRefresh(
            activeRequest: nil,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeCommandMutationRequest: MailRootCommandMutationRequest(
                id: 1,
                sourceFolderID: "inbox"
            ),
            activeMailboxSwitchRequest: nil,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("refresh cannot start while a mailbox switch is active")
    func refreshCannotStartWhileMailboxSwitchIsActive() {
        #expect(!MailRootRefreshStartPolicy.canStartRefresh(
            activeRequest: nil,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeCommandMutationRequest: nil,
            activeMailboxSwitchRequest: MailRootMailboxSwitchRequest(
                id: 1,
                mailboxID: "mailbox-b"
            ),
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("refresh cannot start while compose is active")
    func refreshCannotStartWhileComposeIsActive() {
        #expect(!MailRootRefreshStartPolicy.canStartRefresh(
            activeRequest: nil,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeCommandMutationRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeComposeCompletionRequest: MailRootComposeCompletionRequest(
                id: 1,
                composePresentationID: 1,
                mailboxID: "mailbox-a"
            )
        ))
    }

    @Test("refresh cannot start while a sheet is presented")
    func refreshCannotStartWhileSheetIsPresented() {
        #expect(!MailRootRefreshStartPolicy.canStartRefresh(
            activeRequest: nil,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeCommandMutationRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeComposeCompletionRequest: nil,
            hasPresentedSheet: true
        ))
    }

    @Test("foreground refresh runs only when transitioning into active")
    func foregroundRefreshRunsOnlyWhenTransitioningIntoActive() {
        #expect(MailRootForegroundRefreshPolicy.shouldRefresh(
            wasActive: false,
            isActive: true
        ))
        #expect(!MailRootForegroundRefreshPolicy.shouldRefresh(
            wasActive: true,
            isActive: true
        ))
        #expect(!MailRootForegroundRefreshPolicy.shouldRefresh(
            wasActive: true,
            isActive: false
        ))
        #expect(!MailRootForegroundRefreshPolicy.shouldRefresh(
            wasActive: false,
            isActive: false
        ))
    }

    @Test("visible refresh resolves Unified Inbox without a concrete folder")
    func visibleRefreshResolvesUnifiedInbox() {
        #expect(MailRootVisibleRefreshPolicy.target(
            selectedFolderID: nil,
            isUnifiedInbox: true
        ) == .unifiedInbox)
        #expect(MailRootVisibleRefreshPolicy.target(
            selectedFolderID: "inbox",
            isUnifiedInbox: false
        ) == .selectedFolder("inbox"))
        #expect(MailRootVisibleRefreshPolicy.target(
            selectedFolderID: nil,
            isUnifiedInbox: false
        ) == nil)
    }
}
