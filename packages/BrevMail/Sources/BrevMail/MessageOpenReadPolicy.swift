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

enum MessageOpenReadPolicy {
    enum Operation: Equatable, Sendable {
        case markRead(messageID: MessageHeader.ID, folderID: Folder.ID)
        case none
    }

    static func operation(for header: MessageHeader) -> Operation {
        header.isRead
            ? .none
            : .markRead(messageID: header.id, folderID: header.folderID)
    }
}

struct MessageOpenReadRequest: Equatable, Sendable {
    let messageID: MessageHeader.ID
    let sourceID: MailSourceID?
    let folderID: Folder.ID

    init(
        messageID: MessageHeader.ID,
        sourceID: MailSourceID? = nil,
        folderID: Folder.ID
    ) {
        self.messageID = messageID
        self.sourceID = sourceID
        self.folderID = folderID
    }
}

enum MessageOpenReadStartPolicy {
    static func canStartOpenRead(
        request: MessageOpenReadRequest,
        activeRequest: MessageOpenReadRequest?,
        isBlocked: Bool
    ) -> Bool {
        !isBlocked && activeRequest != request
    }
}

enum MessageOpenReadResponsePolicy {
    static func canApplyResponse(
        request: MessageOpenReadRequest,
        activeRequest: MessageOpenReadRequest?,
        currentSourceID: MailSourceID? = nil,
        currentMessageID: MessageHeader.ID?
    ) -> Bool {
        activeRequest == request
            && currentSourceID == request.sourceID
            && currentMessageID == request.messageID
    }
}
