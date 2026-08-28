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

struct MessageDetailLoadRequest: Equatable, Sendable {
    let messageID: String
    let sourceID: MailSourceID?

    init(messageID: String, sourceID: MailSourceID? = nil) {
        self.messageID = messageID
        self.sourceID = sourceID
    }
}

enum MessageDetailLoadStartPolicy {
    static func canStartLoad(
        request: MessageDetailLoadRequest,
        activeRequest: MessageDetailLoadRequest?,
        isBlocked: Bool
    ) -> Bool {
        !isBlocked && activeRequest != request
    }
}

enum MessageDetailWorkResumePolicy {
    static func shouldReloadMessage(
        wasBlocked: Bool,
        isBlocked: Bool,
        hasPendingReload: Bool
    ) -> Bool {
        wasBlocked && !isBlocked && hasPendingReload
    }
}

enum MessageDetailLoadResponsePolicy {
    static func canApplyLoadResponse(
        request: MessageDetailLoadRequest,
        activeRequest: MessageDetailLoadRequest?,
        currentSourceID: MailSourceID? = nil,
        currentMessageID: String?
    ) -> Bool {
        activeRequest == request
            && currentSourceID == request.sourceID
            && currentMessageID == request.messageID
    }
}
