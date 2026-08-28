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

struct MailRootRefreshRequest: Equatable, Sendable {
    let id: Int
    let folderID: Folder.ID
    let mailboxID: Mailbox.ID?
}

enum MailRootRefreshStartPolicy {
    static func canStartRefresh(
        activeRequest: MailRootRefreshRequest?,
        activeFolderLoadRequest: MailRootFolderLoadRequest?,
        activeMailboxLoadRequest: MailRootMailboxLoadRequest?,
        activeCommandMutationRequest: MailRootCommandMutationRequest?,
        activeMailboxSwitchRequest: MailRootMailboxSwitchRequest?,
        activeComposeCompletionRequest: MailRootComposeCompletionRequest?,
        hasPresentedSheet: Bool = false
    ) -> Bool {
        activeRequest == nil
            && activeFolderLoadRequest == nil
            && activeMailboxLoadRequest == nil
            && activeCommandMutationRequest == nil
            && activeMailboxSwitchRequest == nil
            && activeComposeCompletionRequest == nil
            && !hasPresentedSheet
    }
}

enum MailRootRefreshResponsePolicy {
    static func canApplyResponse(
        request: MailRootRefreshRequest,
        activeRequest: MailRootRefreshRequest?,
        currentSelectedFolderID: Folder.ID?,
        currentMailboxID: Mailbox.ID?
    ) -> Bool {
        activeRequest == request
            && currentSelectedFolderID == request.folderID
            && (request.mailboxID == nil || currentMailboxID == request.mailboxID)
    }
}

enum MailRootForegroundRefreshPolicy {
    static func shouldRefresh(
        wasActive: Bool,
        isActive: Bool
    ) -> Bool {
        !wasActive && isActive
    }
}

enum MailRootVisibleRefreshTarget: Equatable, Sendable {
    case selectedFolder(Folder.ID)
    case unifiedInbox
}

enum MailRootVisibleRefreshPolicy {
    static func target(
        selectedFolderID: Folder.ID?,
        isUnifiedInbox: Bool
    ) -> MailRootVisibleRefreshTarget? {
        if isUnifiedInbox {
            return .unifiedInbox
        }
        return selectedFolderID.map(MailRootVisibleRefreshTarget.selectedFolder)
    }
}
