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

@Suite("MailRootMailboxLoadResponsePolicy")
struct MailRootMailboxLoadResponsePolicyTests {
    @Test("mailbox load can start when no mailbox load is active")
    func mailboxLoadCanStartWhenNoMailboxLoadIsActive() {
        #expect(MailRootMailboxLoadStartPolicy.canStartLoad(
            activeRequest: nil,
            activeMailboxSwitchRequest: nil
        ))
    }

    @Test("mailbox load cannot start while another mailbox load is active")
    func mailboxLoadCannotStartWhileAnotherMailboxLoadIsActive() {
        #expect(!MailRootMailboxLoadStartPolicy.canStartLoad(
            activeRequest: MailRootMailboxLoadRequest(id: 1),
            activeMailboxSwitchRequest: nil
        ))
    }

    @Test("refresh recovery can supersede an event-driven mailbox load")
    func refreshRecoveryCanSupersedeActiveMailboxLoad() {
        #expect(MailRootMailboxLoadStartPolicy.canStartLoad(
            activeRequest: MailRootMailboxLoadRequest(id: 1),
            activeMailboxSwitchRequest: nil,
            supersedingActiveRequest: true
        ))
    }

    @Test("mailbox load cannot start while mailbox switch is active")
    func mailboxLoadCannotStartWhileMailboxSwitchIsActive() {
        #expect(!MailRootMailboxLoadStartPolicy.canStartLoad(
            activeRequest: nil,
            activeMailboxSwitchRequest: MailRootMailboxSwitchRequest(
                id: 1,
                mailboxID: "mailbox-b"
            )
        ))
    }

    @Test("matching active mailbox load request can apply a response")
    func matchingActiveMailboxLoadRequestCanApplyResponse() {
        #expect(MailRootMailboxLoadResponsePolicy.canApplyResponse(
            request: MailRootMailboxLoadRequest(id: 1),
            activeRequest: MailRootMailboxLoadRequest(id: 1)
        ))
    }

    @Test("changed or missing active request rejects stale mailbox load responses")
    func changedOrMissingActiveRequestRejectsStaleMailboxLoadResponses() {
        let request = MailRootMailboxLoadRequest(id: 1)

        #expect(!MailRootMailboxLoadResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: MailRootMailboxLoadRequest(id: 2)
        ))
        #expect(!MailRootMailboxLoadResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: nil
        ))
    }
}
