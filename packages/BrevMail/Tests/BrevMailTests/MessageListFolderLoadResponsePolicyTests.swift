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

@Suite("MessageListFolderLoadResponsePolicy")
struct MessageListFolderLoadResponsePolicyTests {
    @Test("folder load can start when no first-page request is active")
    func folderLoadCanStartWhenNoFirstPageRequestIsActive() {
        #expect(MessageListFolderLoadStartPolicy.canStartFolderLoad(
            request: MessageListFolderLoadRequest(folderID: "inbox", reloadRequestID: 2),
            activeRequest: nil,
            isBlocked: false
        ))
    }

    @Test("folder load cannot start while the same first-page request is active")
    func folderLoadCannotStartWhileSameFirstPageRequestIsActive() {
        let request = MessageListFolderLoadRequest(folderID: "inbox", reloadRequestID: 2)

        #expect(!MessageListFolderLoadStartPolicy.canStartFolderLoad(
            request: request,
            activeRequest: request,
            isBlocked: false
        ))
    }

    @Test("folder load cannot start while root work is active")
    func folderLoadCannotStartWhileRootWorkIsActive() {
        #expect(!MessageListFolderLoadStartPolicy.canStartFolderLoad(
            request: MessageListFolderLoadRequest(folderID: "inbox", reloadRequestID: 2),
            activeRequest: nil,
            isBlocked: true
        ))
    }

    @Test("folder load can start when the reload context changes")
    func folderLoadCanStartWhenReloadContextChanges() {
        #expect(MessageListFolderLoadStartPolicy.canStartFolderLoad(
            request: MessageListFolderLoadRequest(folderID: "inbox", reloadRequestID: 3),
            activeRequest: MessageListFolderLoadRequest(folderID: "inbox", reloadRequestID: 2),
            isBlocked: false
        ))
        #expect(MessageListFolderLoadStartPolicy.canStartFolderLoad(
            request: MessageListFolderLoadRequest(folderID: "archive", reloadRequestID: 2),
            activeRequest: MessageListFolderLoadRequest(folderID: "inbox", reloadRequestID: 2),
            isBlocked: false
        ))
    }

    @Test("matching folder reload and blank search can apply first page")
    func matchingFolderReloadAndBlankSearchCanApplyFirstPage() {
        #expect(MessageListFolderLoadResponsePolicy.canApplyFolderLoadResponse(
            request: MessageListFolderLoadRequest(folderID: "inbox", reloadRequestID: 2),
            activeRequest: MessageListFolderLoadRequest(folderID: "inbox", reloadRequestID: 2),
            currentFolderID: "inbox",
            currentReloadRequestID: 2,
            currentSearchText: " \n\t "
        ))
    }

    @Test("folder reload or search changes reject a stale first page")
    func folderReloadOrSearchChangesRejectStaleFirstPage() {
        let request = MessageListFolderLoadRequest(folderID: "inbox", reloadRequestID: 2)

        #expect(!MessageListFolderLoadResponsePolicy.canApplyFolderLoadResponse(
            request: request,
            activeRequest: request,
            currentFolderID: "archive",
            currentReloadRequestID: 2,
            currentSearchText: ""
        ))
        #expect(!MessageListFolderLoadResponsePolicy.canApplyFolderLoadResponse(
            request: request,
            activeRequest: MessageListFolderLoadRequest(folderID: "inbox", reloadRequestID: 3),
            currentFolderID: "inbox",
            currentReloadRequestID: 2,
            currentSearchText: ""
        ))
        #expect(!MessageListFolderLoadResponsePolicy.canApplyFolderLoadResponse(
            request: request,
            activeRequest: request,
            currentFolderID: "inbox",
            currentReloadRequestID: 3,
            currentSearchText: ""
        ))
        #expect(!MessageListFolderLoadResponsePolicy.canApplyFolderLoadResponse(
            request: request,
            activeRequest: request,
            currentFolderID: "inbox",
            currentReloadRequestID: 2,
            currentSearchText: "budget"
        ))
    }
}
