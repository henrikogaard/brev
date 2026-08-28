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

struct MailRootMailboxSwitchRequest: Equatable, Sendable {
    let id: Int
    let mailboxID: Mailbox.ID
}

enum MailRootMailboxSwitchStartPolicy {
    static func canStartSwitch(
        requestedMailboxID: Mailbox.ID,
        activeMailboxID: Mailbox.ID?,
        activeRequest: MailRootMailboxSwitchRequest?,
        activeFolderLoadRequest: MailRootFolderLoadRequest?,
        activeMailboxLoadRequest: MailRootMailboxLoadRequest?,
        activeRefreshRequest: MailRootRefreshRequest?,
        activeCommandMutationRequest: MailRootCommandMutationRequest?,
        activeComposeCompletionRequest: MailRootComposeCompletionRequest?
    ) -> Bool {
        activeRequest == nil
            && activeFolderLoadRequest == nil
            && activeMailboxLoadRequest == nil
            && activeRefreshRequest == nil
            && activeCommandMutationRequest == nil
            && activeComposeCompletionRequest == nil
            && requestedMailboxID != activeMailboxID
    }
}

enum MailRootMailboxSwitchResponsePolicy {
    static func canApplyResponse(
        request: MailRootMailboxSwitchRequest,
        activeRequest: MailRootMailboxSwitchRequest?,
        currentMailboxID: Mailbox.ID?
    ) -> Bool {
        activeRequest == request && currentMailboxID == request.mailboxID
    }
}

enum MailRootMailboxChangedEventPolicy {
    static func shouldApplyEvent(
        mailboxID: Mailbox.ID,
        currentMailboxID: Mailbox.ID?,
        activeMailboxSwitchRequest: MailRootMailboxSwitchRequest?
    ) -> Bool {
        activeMailboxSwitchRequest != nil || mailboxID != currentMailboxID
    }
}
