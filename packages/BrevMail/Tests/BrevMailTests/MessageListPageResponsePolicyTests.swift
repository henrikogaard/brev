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

@Suite("MessageListPageResponsePolicy")
struct MessageListPageResponsePolicyTests {
    @Test("page load can start when no page request is active")
    func pageLoadCanStartWhenNoPageRequestIsActive() {
        #expect(MessageListPageStartPolicy.canStartPageLoad(
            request: MessageListPageRequest(folderID: "inbox", pageToken: "p2"),
            activeRequest: nil,
            isBlocked: false
        ))
    }

    @Test("page load cannot start while the same page request is active")
    func pageLoadCannotStartWhileSamePageRequestIsActive() {
        let request = MessageListPageRequest(folderID: "inbox", pageToken: "p2")

        #expect(!MessageListPageStartPolicy.canStartPageLoad(
            request: request,
            activeRequest: request,
            isBlocked: false
        ))
    }

    @Test("page load cannot start while root work is active")
    func pageLoadCannotStartWhileRootWorkIsActive() {
        #expect(!MessageListPageStartPolicy.canStartPageLoad(
            request: MessageListPageRequest(folderID: "inbox", pageToken: "p2"),
            activeRequest: nil,
            isBlocked: true
        ))
    }

    @Test("page load can start when folder or token changes")
    func pageLoadCanStartWhenFolderOrTokenChanges() {
        let activeRequest = MessageListPageRequest(folderID: "inbox", pageToken: "p2")

        #expect(MessageListPageStartPolicy.canStartPageLoad(
            request: MessageListPageRequest(folderID: "inbox", pageToken: "p3"),
            activeRequest: activeRequest,
            isBlocked: false
        ))
        #expect(MessageListPageStartPolicy.canStartPageLoad(
            request: MessageListPageRequest(folderID: "archive", pageToken: "p2"),
            activeRequest: activeRequest,
            isBlocked: false
        ))
    }

    @Test("matching folder token and blank search can apply a page response")
    func matchingFolderTokenAndBlankSearchCanApplyPageResponse() {
        #expect(MessageListPageResponsePolicy.canApplyPageResponse(
            request: MessageListPageRequest(folderID: "inbox", pageToken: "p2"),
            activeRequest: MessageListPageRequest(folderID: "inbox", pageToken: "p2"),
            currentFolderID: "inbox",
            currentSearchText: " \n\t "
        ))
    }

    @Test("folder token or search changes reject a stale page response")
    func folderTokenOrSearchChangesRejectStalePageResponse() {
        let request = MessageListPageRequest(folderID: "inbox", pageToken: "p2")

        #expect(!MessageListPageResponsePolicy.canApplyPageResponse(
            request: request,
            activeRequest: request,
            currentFolderID: "archive",
            currentSearchText: ""
        ))
        #expect(!MessageListPageResponsePolicy.canApplyPageResponse(
            request: request,
            activeRequest: MessageListPageRequest(folderID: "inbox", pageToken: "p3"),
            currentFolderID: "inbox",
            currentSearchText: ""
        ))
        #expect(!MessageListPageResponsePolicy.canApplyPageResponse(
            request: request,
            activeRequest: request,
            currentFolderID: "inbox",
            currentSearchText: "budget"
        ))
    }
}
