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

@Suite("MailRootFolderLoadResponsePolicy")
struct MailRootFolderLoadResponsePolicyTests {
    @Test("folder load can start when no folder load is active")
    func folderLoadCanStartWhenNoFolderLoadIsActive() {
        #expect(MailRootFolderLoadStartPolicy.canStartLoad(
            activeRequest: nil,
            activeMailboxSwitchRequest: nil
        ))
    }

    @Test("folder load cannot start while another folder load is active")
    func folderLoadCannotStartWhileAnotherFolderLoadIsActive() {
        #expect(!MailRootFolderLoadStartPolicy.canStartLoad(
            activeRequest: MailRootFolderLoadRequest(id: 1),
            activeMailboxSwitchRequest: nil
        ))
    }

    @Test("refresh recovery can supersede an event-driven folder load")
    func refreshRecoveryCanSupersedeActiveFolderLoad() {
        #expect(MailRootFolderLoadStartPolicy.canStartLoad(
            activeRequest: MailRootFolderLoadRequest(id: 1),
            activeMailboxSwitchRequest: nil,
            supersedingActiveRequest: true
        ))
    }

    @Test("folder load cannot start while mailbox switch is active")
    func folderLoadCannotStartWhileMailboxSwitchIsActive() {
        #expect(!MailRootFolderLoadStartPolicy.canStartLoad(
            activeRequest: nil,
            activeMailboxSwitchRequest: MailRootMailboxSwitchRequest(
                id: 1,
                mailboxID: "mailbox-b"
            )
        ))
    }

    @Test("matching active folder load request can apply a response")
    func matchingActiveFolderLoadRequestCanApplyResponse() {
        #expect(MailRootFolderLoadResponsePolicy.canApplyResponse(
            request: MailRootFolderLoadRequest(id: 1),
            activeRequest: MailRootFolderLoadRequest(id: 1)
        ))
    }

    @Test("changed or missing active request rejects stale folder load responses")
    func changedOrMissingActiveRequestRejectsStaleFolderLoadResponses() {
        let request = MailRootFolderLoadRequest(id: 1)

        #expect(!MailRootFolderLoadResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: MailRootFolderLoadRequest(id: 2)
        ))
        #expect(!MailRootFolderLoadResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: nil
        ))
    }
}
