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

@Suite("MailRootMailboxSwitchResponsePolicy")
struct MailRootMailboxSwitchResponsePolicyTests {
    @Test("matching active switch request and selected mailbox can apply response")
    func matchingActiveSwitchRequestAndSelectedMailboxCanApplyResponse() {
        let request = MailRootMailboxSwitchRequest(id: 1, mailboxID: "mbx-2")

        #expect(MailRootMailboxSwitchResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentMailboxID: "mbx-2"
        ))
    }

    @Test("changed or missing active request rejects stale switch response")
    func changedOrMissingActiveRequestRejectsStaleSwitchResponse() {
        let request = MailRootMailboxSwitchRequest(id: 1, mailboxID: "mbx-2")

        #expect(!MailRootMailboxSwitchResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: MailRootMailboxSwitchRequest(id: 2, mailboxID: "mbx-2"),
            currentMailboxID: "mbx-2"
        ))
        #expect(!MailRootMailboxSwitchResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: nil,
            currentMailboxID: "mbx-2"
        ))
    }

    @Test("changed mailbox rejects stale switch response")
    func changedMailboxRejectsStaleSwitchResponse() {
        let request = MailRootMailboxSwitchRequest(id: 1, mailboxID: "mbx-2")

        #expect(!MailRootMailboxSwitchResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentMailboxID: "mbx-3"
        ))
        #expect(!MailRootMailboxSwitchResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentMailboxID: nil
        ))
    }

    @Test("mailbox switch can start when target differs and no switch is active")
    func mailboxSwitchCanStartWhenTargetDiffersAndNoSwitchIsActive() {
        #expect(MailRootMailboxSwitchStartPolicy.canStartSwitch(
            requestedMailboxID: "mbx-2",
            activeMailboxID: "mbx-1",
            activeRequest: nil,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeCommandMutationRequest: nil,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("mailbox switch cannot start for current mailbox")
    func mailboxSwitchCannotStartForCurrentMailbox() {
        #expect(!MailRootMailboxSwitchStartPolicy.canStartSwitch(
            requestedMailboxID: "mbx-1",
            activeMailboxID: "mbx-1",
            activeRequest: nil,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeCommandMutationRequest: nil,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("mailbox switch cannot start while another switch is active")
    func mailboxSwitchCannotStartWhileAnotherSwitchIsActive() {
        #expect(!MailRootMailboxSwitchStartPolicy.canStartSwitch(
            requestedMailboxID: "mbx-3",
            activeMailboxID: "mbx-1",
            activeRequest: MailRootMailboxSwitchRequest(id: 1, mailboxID: "mbx-2"),
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeCommandMutationRequest: nil,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("mailbox switch cannot start while root folder load is active")
    func mailboxSwitchCannotStartWhileRootFolderLoadIsActive() {
        #expect(!MailRootMailboxSwitchStartPolicy.canStartSwitch(
            requestedMailboxID: "mbx-2",
            activeMailboxID: "mbx-1",
            activeRequest: nil,
            activeFolderLoadRequest: MailRootFolderLoadRequest(id: 1),
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeCommandMutationRequest: nil,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("mailbox switch cannot start while root mailbox load is active")
    func mailboxSwitchCannotStartWhileRootMailboxLoadIsActive() {
        #expect(!MailRootMailboxSwitchStartPolicy.canStartSwitch(
            requestedMailboxID: "mbx-2",
            activeMailboxID: "mbx-1",
            activeRequest: nil,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: MailRootMailboxLoadRequest(id: 1),
            activeRefreshRequest: nil,
            activeCommandMutationRequest: nil,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("mailbox switch cannot start while refresh is active")
    func mailboxSwitchCannotStartWhileRefreshIsActive() {
        #expect(!MailRootMailboxSwitchStartPolicy.canStartSwitch(
            requestedMailboxID: "mbx-2",
            activeMailboxID: "mbx-1",
            activeRequest: nil,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: MailRootRefreshRequest(
                id: 1,
                folderID: "inbox",
                mailboxID: "mailbox-a"
            ),
            activeCommandMutationRequest: nil,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("mailbox switch cannot start while command mutation is active")
    func mailboxSwitchCannotStartWhileCommandMutationIsActive() {
        #expect(!MailRootMailboxSwitchStartPolicy.canStartSwitch(
            requestedMailboxID: "mbx-2",
            activeMailboxID: "mbx-1",
            activeRequest: nil,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeCommandMutationRequest: MailRootCommandMutationRequest(
                id: 1,
                sourceFolderID: "inbox"
            ),
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("mailbox switch cannot start while compose is active")
    func mailboxSwitchCannotStartWhileComposeIsActive() {
        #expect(!MailRootMailboxSwitchStartPolicy.canStartSwitch(
            requestedMailboxID: "mbx-2",
            activeMailboxID: "mbx-1",
            activeRequest: nil,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeCommandMutationRequest: nil,
            activeComposeCompletionRequest: MailRootComposeCompletionRequest(
                id: 1,
                composePresentationID: 1,
                mailboxID: "mbx-1"
            )
        ))
    }

    @Test("mailbox changed event applies when a user switch is active")
    func mailboxChangedEventAppliesWhenUserSwitchIsActive() {
        #expect(MailRootMailboxChangedEventPolicy.shouldApplyEvent(
            mailboxID: "mbx-2",
            currentMailboxID: "mbx-2",
            activeMailboxSwitchRequest: MailRootMailboxSwitchRequest(id: 1, mailboxID: "mbx-2")
        ))
    }

    @Test("mailbox changed event applies when backend reports a different mailbox")
    func mailboxChangedEventAppliesWhenBackendReportsDifferentMailbox() {
        #expect(MailRootMailboxChangedEventPolicy.shouldApplyEvent(
            mailboxID: "mbx-3",
            currentMailboxID: "mbx-1",
            activeMailboxSwitchRequest: nil
        ))
    }

    @Test("mailbox changed event ignores duplicate current mailbox without active switch")
    func mailboxChangedEventIgnoresDuplicateCurrentMailboxWithoutActiveSwitch() {
        #expect(!MailRootMailboxChangedEventPolicy.shouldApplyEvent(
            mailboxID: "mbx-2",
            currentMailboxID: "mbx-2",
            activeMailboxSwitchRequest: nil
        ))
    }
}
