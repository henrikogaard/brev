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
    let backendIdentity: ObjectIdentifier?
    let sourceRevision: Int?
    let reloadRequestID: Int

    init(
        folderID: String,
        sourceID: MailSourceID? = nil,
        backendIdentity: ObjectIdentifier? = nil,
        sourceRevision: Int? = nil,
        reloadRequestID: Int
    ) {
        self.folderID = folderID
        self.sourceID = sourceID
        self.backendIdentity = backendIdentity
        self.sourceRevision = sourceRevision
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
    static func currentBackendIdentity(
        currentSourceID: MailSourceID?,
        viewBackendAccountID: String,
        backends: [(accountID: String, identity: ObjectIdentifier)]
    ) -> ObjectIdentifier? {
        let accountID = currentSourceID?.accountID ?? viewBackendAccountID
        return backends.first(where: { $0.accountID == accountID })?.identity
    }

    static func canApplyFolderLoadResponse(
        request: MessageListFolderLoadRequest,
        activeRequest: MessageListFolderLoadRequest?,
        currentSourceID: MailSourceID? = nil,
        currentFolderID: String?,
        currentReloadRequestID: Int,
        currentSearchText: String,
        currentBackendIdentity: ObjectIdentifier? = nil,
        currentSourceRevision: Int? = nil
    ) -> Bool {
        activeRequest == request
            && currentSourceID == request.sourceID
            && currentFolderID == request.folderID
            && currentReloadRequestID == request.reloadRequestID
            && (request.backendIdentity == nil || request.backendIdentity == currentBackendIdentity)
            && (request.sourceRevision == nil || request.sourceRevision == currentSourceRevision)
            && MessageListReloadPolicy.operation(forSearchText: currentSearchText) == .folder
    }

    /// Returns `true` when an otherwise-current folder load was rejected solely because
    /// the global `sourceSectionsRevision` advanced while the request was in flight
    /// (for example when another account refreshed). Callers should clear `activeRequest`
    /// and schedule a replacement reload instead of leaving the list stuck loading.
    static func shouldRestartFolderLoadForSourceRevisionChange(
        request: MessageListFolderLoadRequest,
        activeRequest: MessageListFolderLoadRequest?,
        currentSourceID: MailSourceID? = nil,
        currentFolderID: String?,
        currentReloadRequestID: Int,
        currentSearchText: String,
        currentBackendIdentity: ObjectIdentifier? = nil,
        currentSourceRevision: Int? = nil
    ) -> Bool {
        guard let requestRevision = request.sourceRevision,
              requestRevision != currentSourceRevision else {
            return false
        }
        return activeRequest == request
            && currentSourceID == request.sourceID
            && currentFolderID == request.folderID
            && currentReloadRequestID == request.reloadRequestID
            && (request.backendIdentity == nil || request.backendIdentity == currentBackendIdentity)
            && MessageListReloadPolicy.operation(forSearchText: currentSearchText) == .folder
    }

    static func ownsSourceAndBackend(
        sourceID: MailSourceID,
        currentSourceID: MailSourceID?,
        backendIdentity: ObjectIdentifier,
        currentBackendIdentity: ObjectIdentifier?
    ) -> Bool {
        sourceID == currentSourceID && backendIdentity == currentBackendIdentity
    }
}
