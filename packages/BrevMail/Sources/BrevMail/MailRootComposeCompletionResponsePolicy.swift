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

struct MailRootComposeCompletionRequest: Equatable, Sendable {
    let id: Int
    let composePresentationID: Int
    let mailboxID: Mailbox.ID?
}

enum MailRootComposeCompletionResponsePolicy {
    static func requestForCompletion(
        capturedRequest: MailRootComposeCompletionRequest?,
        activeRequest: MailRootComposeCompletionRequest?,
        capturedComposePresentationID: Int
    ) -> MailRootComposeCompletionRequest? {
        if let capturedRequest {
            return capturedRequest
        }
        guard activeRequest?.composePresentationID == capturedComposePresentationID else {
            return nil
        }
        return activeRequest
    }

    static func canApplyResponse(
        request: MailRootComposeCompletionRequest,
        activeRequest: MailRootComposeCompletionRequest?,
        currentComposePresentationID: Int,
        currentMailboxID: Mailbox.ID?
    ) -> Bool {
        activeRequest == request
            && currentComposePresentationID == request.composePresentationID
            && (request.mailboxID == nil || currentMailboxID == request.mailboxID)
    }
}
