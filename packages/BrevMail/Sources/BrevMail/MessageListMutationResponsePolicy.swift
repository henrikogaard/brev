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

import BrevBackend

struct MessageListMutationRequest: Equatable, Sendable {
    let id: Int
    let sourceID: MailSourceID?
    let folderID: Folder.ID?
    let reloadRequestID: Int
    let searchText: String

    init(
        id: Int,
        sourceID: MailSourceID? = nil,
        folderID: Folder.ID?,
        reloadRequestID: Int,
        searchText: String
    ) {
        self.id = id
        self.sourceID = sourceID
        self.folderID = folderID
        self.reloadRequestID = reloadRequestID
        self.searchText = searchText
    }
}

enum MessageListMutationStartPolicy {
    static func canStartMutation(
        activeRequest: MessageListMutationRequest?,
        isBlocked: Bool
    ) -> Bool {
        !isBlocked && activeRequest == nil
    }
}

enum MessageListMutationResponsePolicy {
    static func canApplyResponse(
        request: MessageListMutationRequest,
        activeRequest: MessageListMutationRequest?,
        currentSourceID: MailSourceID? = nil,
        currentFolderID: Folder.ID?,
        currentReloadRequestID: Int,
        currentSearchText: String
    ) -> Bool {
        activeRequest == request
            && currentSourceID == request.sourceID
            && currentFolderID == request.folderID
            && currentReloadRequestID == request.reloadRequestID
            && currentSearchText == request.searchText
    }
}
