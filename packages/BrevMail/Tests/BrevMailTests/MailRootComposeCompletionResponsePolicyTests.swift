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

@Suite("MailRootComposeCompletionResponsePolicy")
struct MailRootComposeCompletionResponsePolicyTests {
    @Test("captured compose request wins over active fallback")
    func capturedComposeRequestWinsOverActiveFallback() {
        let captured = MailRootComposeCompletionRequest(
            id: 1,
            composePresentationID: 2,
            mailboxID: "mailbox-a"
        )
        let active = MailRootComposeCompletionRequest(
            id: 2,
            composePresentationID: 2,
            mailboxID: "mailbox-a"
        )

        #expect(MailRootComposeCompletionResponsePolicy.requestForCompletion(
            capturedRequest: captured,
            activeRequest: active,
            capturedComposePresentationID: 2
        ) == captured)
    }

    @Test("matching active request can recover missing captured request")
    func matchingActiveRequestCanRecoverMissingCapturedRequest() {
        let active = MailRootComposeCompletionRequest(
            id: 1,
            composePresentationID: 2,
            mailboxID: "mailbox-a"
        )

        #expect(MailRootComposeCompletionResponsePolicy.requestForCompletion(
            capturedRequest: nil,
            activeRequest: active,
            capturedComposePresentationID: 2
        ) == active)
        #expect(MailRootComposeCompletionResponsePolicy.requestForCompletion(
            capturedRequest: nil,
            activeRequest: active,
            capturedComposePresentationID: 3
        ) == nil)
        #expect(MailRootComposeCompletionResponsePolicy.requestForCompletion(
            capturedRequest: nil,
            activeRequest: nil,
            capturedComposePresentationID: 2
        ) == nil)
    }

    @Test("matching active compose request and mailbox can apply completion")
    func matchingActiveComposeRequestAndMailboxCanApplyCompletion() {
        let request = MailRootComposeCompletionRequest(
            id: 1,
            composePresentationID: 2,
            mailboxID: "mailbox-a"
        )

        #expect(MailRootComposeCompletionResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentComposePresentationID: 2,
            currentMailboxID: "mailbox-a"
        ))
    }

    @Test("unknown request mailbox can apply when compose presentation still matches")
    func unknownRequestMailboxCanApplyWhenComposePresentationStillMatches() {
        let request = MailRootComposeCompletionRequest(
            id: 1,
            composePresentationID: 2,
            mailboxID: nil
        )

        #expect(MailRootComposeCompletionResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentComposePresentationID: 2,
            currentMailboxID: "mailbox-a"
        ))
    }

    @Test("changed or missing active compose request rejects stale completion")
    func changedOrMissingActiveComposeRequestRejectsStaleCompletion() {
        let request = MailRootComposeCompletionRequest(
            id: 1,
            composePresentationID: 2,
            mailboxID: "mailbox-a"
        )

        #expect(!MailRootComposeCompletionResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: MailRootComposeCompletionRequest(
                id: 2,
                composePresentationID: 2,
                mailboxID: "mailbox-a"
            ),
            currentComposePresentationID: 2,
            currentMailboxID: "mailbox-a"
        ))
        #expect(!MailRootComposeCompletionResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: nil,
            currentComposePresentationID: 2,
            currentMailboxID: "mailbox-a"
        ))
    }

    @Test("changed compose presentation or mailbox rejects stale completion")
    func changedComposePresentationOrMailboxRejectsStaleCompletion() {
        let request = MailRootComposeCompletionRequest(
            id: 1,
            composePresentationID: 2,
            mailboxID: "mailbox-a"
        )

        #expect(!MailRootComposeCompletionResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentComposePresentationID: 3,
            currentMailboxID: "mailbox-a"
        ))
        #expect(!MailRootComposeCompletionResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentComposePresentationID: 2,
            currentMailboxID: "mailbox-b"
        ))
        #expect(!MailRootComposeCompletionResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentComposePresentationID: 2,
            currentMailboxID: nil
        ))
    }
}
