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

struct MailRootCommandMutationRequest: Equatable, Sendable {
    let id: Int
    let sourceFolderID: Folder.ID?
}

enum MailRootCommandMutationStartPolicy {
    static func canStartMutation(
        activeRequest: MailRootCommandMutationRequest?,
        activeFolderLoadRequest: MailRootFolderLoadRequest?,
        activeMailboxLoadRequest: MailRootMailboxLoadRequest?,
        activeRefreshRequest: MailRootRefreshRequest?,
        activeMailboxSwitchRequest: MailRootMailboxSwitchRequest?,
        activeComposeCompletionRequest: MailRootComposeCompletionRequest?,
        hasPresentedSheet: Bool = false
    ) -> Bool {
        activeRequest == nil
            && activeFolderLoadRequest == nil
            && activeMailboxLoadRequest == nil
            && activeRefreshRequest == nil
            && activeMailboxSwitchRequest == nil
            && activeComposeCompletionRequest == nil
            && !hasPresentedSheet
    }
}

enum MailRootCommandMutationResponsePolicy {
    static func canApplyResponse(
        request: MailRootCommandMutationRequest,
        activeRequest: MailRootCommandMutationRequest?,
        currentSelectedFolderID: Folder.ID?
    ) -> Bool {
        activeRequest == request && currentSelectedFolderID == request.sourceFolderID
    }
}
