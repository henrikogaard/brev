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

@Suite("MailRootCommandMutationResponsePolicy")
struct MailRootCommandMutationResponsePolicyTests {
    @Test("matching active command request and source folder can apply response")
    func matchingActiveCommandRequestAndSourceFolderCanApplyResponse() {
        let request = MailRootCommandMutationRequest(
            id: 1,
            sourceFolderID: "inbox"
        )

        #expect(MailRootCommandMutationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentSelectedFolderID: "inbox"
        ))
    }

    @Test("changed or missing active command request rejects stale response")
    func changedOrMissingActiveCommandRequestRejectsStaleResponse() {
        let request = MailRootCommandMutationRequest(
            id: 1,
            sourceFolderID: "inbox"
        )

        #expect(!MailRootCommandMutationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: MailRootCommandMutationRequest(
                id: 2,
                sourceFolderID: "inbox"
            ),
            currentSelectedFolderID: "inbox"
        ))
        #expect(!MailRootCommandMutationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: nil,
            currentSelectedFolderID: "inbox"
        ))
    }

    @Test("folder changes reject stale command response")
    func folderChangesRejectStaleCommandResponse() {
        let request = MailRootCommandMutationRequest(
            id: 1,
            sourceFolderID: "inbox"
        )

        #expect(!MailRootCommandMutationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentSelectedFolderID: "archive"
        ))
    }

    @Test("command mutation can start when no mutation is active")
    func commandMutationCanStartWhenNoMutationIsActive() {
        #expect(MailRootCommandMutationStartPolicy.canStartMutation(
            activeRequest: nil,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("command mutation cannot start while another mutation is active")
    func commandMutationCannotStartWhileAnotherMutationIsActive() {
        #expect(!MailRootCommandMutationStartPolicy.canStartMutation(
            activeRequest: MailRootCommandMutationRequest(
                id: 1,
                sourceFolderID: "inbox"
            ),
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("command mutation cannot start while root folder load is active")
    func commandMutationCannotStartWhileRootFolderLoadIsActive() {
        #expect(!MailRootCommandMutationStartPolicy.canStartMutation(
            activeRequest: nil,
            activeFolderLoadRequest: MailRootFolderLoadRequest(id: 1),
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("command mutation cannot start while root mailbox load is active")
    func commandMutationCannotStartWhileRootMailboxLoadIsActive() {
        #expect(!MailRootCommandMutationStartPolicy.canStartMutation(
            activeRequest: nil,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: MailRootMailboxLoadRequest(id: 1),
            activeRefreshRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("command mutation cannot start while refresh is active")
    func commandMutationCannotStartWhileRefreshIsActive() {
        #expect(!MailRootCommandMutationStartPolicy.canStartMutation(
            activeRequest: nil,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: MailRootRefreshRequest(
                id: 1,
                folderID: "inbox",
                mailboxID: "mailbox-a"
            ),
            activeMailboxSwitchRequest: nil,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("command mutation cannot start while mailbox switch is active")
    func commandMutationCannotStartWhileMailboxSwitchIsActive() {
        #expect(!MailRootCommandMutationStartPolicy.canStartMutation(
            activeRequest: nil,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeMailboxSwitchRequest: MailRootMailboxSwitchRequest(
                id: 1,
                mailboxID: "mailbox-b"
            ),
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("command mutation cannot start while compose is active")
    func commandMutationCannotStartWhileComposeIsActive() {
        #expect(!MailRootCommandMutationStartPolicy.canStartMutation(
            activeRequest: nil,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeComposeCompletionRequest: MailRootComposeCompletionRequest(
                id: 1,
                composePresentationID: 1,
                mailboxID: "mailbox-a"
            )
        ))
    }

    @Test("command mutation cannot start while a sheet is presented")
    func commandMutationCannotStartWhileSheetIsPresented() {
        #expect(!MailRootCommandMutationStartPolicy.canStartMutation(
            activeRequest: nil,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeComposeCompletionRequest: nil,
            hasPresentedSheet: true
        ))
    }
}
