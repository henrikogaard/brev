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

@Suite("MessageDetailLoadResponsePolicy")
struct MessageDetailLoadResponsePolicyTests {
    @Test("message detail load can start when no body request is active")
    func messageDetailLoadCanStartWhenNoBodyRequestIsActive() {
        #expect(MessageDetailLoadStartPolicy.canStartLoad(
            request: MessageDetailLoadRequest(messageID: "message-1"),
            activeRequest: nil,
            isBlocked: false
        ))
    }

    @Test("message detail load cannot start while the same body request is active")
    func messageDetailLoadCannotStartWhileSameBodyRequestIsActive() {
        let request = MessageDetailLoadRequest(messageID: "message-1")

        #expect(!MessageDetailLoadStartPolicy.canStartLoad(
            request: request,
            activeRequest: request,
            isBlocked: false
        ))
    }

    @Test("message detail load cannot start while root work is active")
    func messageDetailLoadCannotStartWhileRootWorkIsActive() {
        #expect(!MessageDetailLoadStartPolicy.canStartLoad(
            request: MessageDetailLoadRequest(messageID: "message-1"),
            activeRequest: nil,
            isBlocked: true
        ))
    }

    @Test("message detail load can start when the selected message changes")
    func messageDetailLoadCanStartWhenSelectedMessageChanges() {
        #expect(MessageDetailLoadStartPolicy.canStartLoad(
            request: MessageDetailLoadRequest(messageID: "message-2"),
            activeRequest: MessageDetailLoadRequest(messageID: "message-1"),
            isBlocked: false
        ))
    }

    @Test("pending detail reload resumes when root work unblocks")
    func pendingDetailReloadResumesWhenRootWorkUnblocks() {
        #expect(MessageDetailWorkResumePolicy.shouldReloadMessage(
            wasBlocked: true,
            isBlocked: false,
            hasPendingReload: true
        ))
    }

    @Test("detail reload does not resume without a pending blocked start")
    func detailReloadDoesNotResumeWithoutPendingBlockedStart() {
        #expect(!MessageDetailWorkResumePolicy.shouldReloadMessage(
            wasBlocked: true,
            isBlocked: false,
            hasPendingReload: false
        ))
        #expect(!MessageDetailWorkResumePolicy.shouldReloadMessage(
            wasBlocked: true,
            isBlocked: true,
            hasPendingReload: true
        ))
        #expect(!MessageDetailWorkResumePolicy.shouldReloadMessage(
            wasBlocked: false,
            isBlocked: false,
            hasPendingReload: true
        ))
    }

    @Test("matching active message can apply a body response")
    func matchingActiveMessageCanApplyBodyResponse() {
        #expect(MessageDetailLoadResponsePolicy.canApplyLoadResponse(
            request: MessageDetailLoadRequest(messageID: "message-1"),
            activeRequest: MessageDetailLoadRequest(messageID: "message-1"),
            currentMessageID: "message-1"
        ))
    }

    @Test("message or request changes reject a stale body response")
    func messageOrRequestChangesRejectStaleBodyResponse() {
        let request = MessageDetailLoadRequest(messageID: "message-1")

        #expect(!MessageDetailLoadResponsePolicy.canApplyLoadResponse(
            request: request,
            activeRequest: MessageDetailLoadRequest(messageID: "message-2"),
            currentMessageID: "message-1"
        ))
        #expect(!MessageDetailLoadResponsePolicy.canApplyLoadResponse(
            request: request,
            activeRequest: request,
            currentMessageID: "message-2"
        ))
        #expect(!MessageDetailLoadResponsePolicy.canApplyLoadResponse(
            request: request,
            activeRequest: request,
            currentMessageID: nil
        ))
    }
}
