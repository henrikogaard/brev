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

struct MessageListPageRequest: Equatable, Sendable {
    let folderID: String
    let sourceID: MailSourceID?
    let pageToken: String

    init(
        folderID: String,
        sourceID: MailSourceID? = nil,
        pageToken: String
    ) {
        self.folderID = folderID
        self.sourceID = sourceID
        self.pageToken = pageToken
    }
}

enum MessageListPageStartPolicy {
    static func canStartPageLoad(
        request: MessageListPageRequest,
        activeRequest: MessageListPageRequest?,
        isBlocked: Bool
    ) -> Bool {
        !isBlocked && activeRequest != request
    }
}

enum MessageListPageResponsePolicy {
    static func canApplyPageResponse(
        request: MessageListPageRequest,
        activeRequest: MessageListPageRequest?,
        currentSourceID: MailSourceID? = nil,
        currentFolderID: String?,
        currentSearchText: String
    ) -> Bool {
        activeRequest == request
            && currentSourceID == request.sourceID
            && currentFolderID == request.folderID
            && MessageListReloadPolicy.operation(forSearchText: currentSearchText) == .folder
    }
}
