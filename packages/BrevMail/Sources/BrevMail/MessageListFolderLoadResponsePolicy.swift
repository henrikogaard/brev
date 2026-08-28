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

struct MessageListFolderLoadRequest: Equatable, Sendable {
    let folderID: String
    let sourceID: MailSourceID?
    let reloadRequestID: Int

    init(
        folderID: String,
        sourceID: MailSourceID? = nil,
        reloadRequestID: Int
    ) {
        self.folderID = folderID
        self.sourceID = sourceID
        self.reloadRequestID = reloadRequestID
    }

    /// Stable identity of the folder/account this load targets, independent of
    /// the reload request id. Equal identities mean a same-folder refresh;
    /// differing identities mean a folder or account switch.
    var identityKey: String {
        let sourceKey = sourceID.map { "\($0.accountID):\($0.mailboxID)" } ?? "none"
        return "\(sourceKey):\(folderID)"
    }
}

enum MessageListFolderLoadStartPolicy {
    static func canStartFolderLoad(
        request: MessageListFolderLoadRequest,
        activeRequest: MessageListFolderLoadRequest?,
        isBlocked: Bool
    ) -> Bool {
        !isBlocked && activeRequest != request
    }
}

enum MessageListFolderLoadResponsePolicy {
    static func canApplyFolderLoadResponse(
        request: MessageListFolderLoadRequest,
        activeRequest: MessageListFolderLoadRequest?,
        currentSourceID: MailSourceID? = nil,
        currentFolderID: String?,
        currentReloadRequestID: Int,
        currentSearchText: String
    ) -> Bool {
        activeRequest == request
            && currentSourceID == request.sourceID
            && currentFolderID == request.folderID
            && currentReloadRequestID == request.reloadRequestID
            && MessageListReloadPolicy.operation(forSearchText: currentSearchText) == .folder
    }
}
