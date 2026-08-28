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

@Suite("MessageListMutationResponsePolicy")
struct MessageListMutationResponsePolicyTests {
    @Test("message list mutation can start when no mutation is active")
    func messageListMutationCanStartWhenNoMutationIsActive() {
        #expect(MessageListMutationStartPolicy.canStartMutation(
            activeRequest: nil,
            isBlocked: false
        ))
    }

    @Test("message list mutation cannot start while another mutation is active")
    func messageListMutationCannotStartWhileAnotherMutationIsActive() {
        #expect(!MessageListMutationStartPolicy.canStartMutation(
            activeRequest: MessageListMutationRequest(
                id: 1,
                folderID: "inbox",
                reloadRequestID: 2,
                searchText: ""
            ),
            isBlocked: false
        ))
    }

    @Test("message list mutation cannot start while root work is active")
    func messageListMutationCannotStartWhileRootWorkIsActive() {
        #expect(!MessageListMutationStartPolicy.canStartMutation(
            activeRequest: nil,
            isBlocked: true
        ))
    }

    @Test("matching active mutation request and list context can apply response")
    func matchingActiveMutationRequestAndListContextCanApplyResponse() {
        let request = MessageListMutationRequest(
            id: 1,
            folderID: "inbox",
            reloadRequestID: 2,
            searchText: ""
        )

        #expect(MessageListMutationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentFolderID: "inbox",
            currentReloadRequestID: 2,
            currentSearchText: ""
        ))
    }

    @Test("changed or missing active mutation request rejects stale response")
    func changedOrMissingActiveMutationRequestRejectsStaleResponse() {
        let request = MessageListMutationRequest(
            id: 1,
            folderID: "inbox",
            reloadRequestID: 2,
            searchText: ""
        )

        #expect(!MessageListMutationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: MessageListMutationRequest(
                id: 2,
                folderID: "inbox",
                reloadRequestID: 2,
                searchText: ""
            ),
            currentFolderID: "inbox",
            currentReloadRequestID: 2,
            currentSearchText: ""
        ))
        #expect(!MessageListMutationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: nil,
            currentFolderID: "inbox",
            currentReloadRequestID: 2,
            currentSearchText: ""
        ))
    }

    @Test("changed list context rejects stale mutation response")
    func changedListContextRejectsStaleMutationResponse() {
        let request = MessageListMutationRequest(
            id: 1,
            folderID: "inbox",
            reloadRequestID: 2,
            searchText: ""
        )

        #expect(!MessageListMutationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentFolderID: "archive",
            currentReloadRequestID: 2,
            currentSearchText: ""
        ))
        #expect(!MessageListMutationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentFolderID: "inbox",
            currentReloadRequestID: 3,
            currentSearchText: ""
        ))
        #expect(!MessageListMutationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentFolderID: "inbox",
            currentReloadRequestID: 2,
            currentSearchText: "receipt"
        ))
    }
}
