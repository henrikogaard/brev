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

struct UnifiedInboxItem: Identifiable, Equatable, Sendable {
    let sourceID: MailSourceID
    let folder: Folder
    var header: MessageHeader
    let sourceTitle: String
    let sourceSubtitle: String
    let archiveFolder: Folder?
    /// Cached memberships for label-backed messages shown once in a saved view.
    var folderMembershipIDs: Set<Folder.ID>?

    var id: String {
        "\(sourceID.accountID):\(sourceID.mailboxID):\(header.id)"
    }

    var pinID: String {
        MailPinnedMessages.key(sourceID: sourceID, messageID: header.id)
    }

    var sourceContext: String {
        sourceTitle.isEmpty ? sourceSubtitle : sourceTitle
    }

    var dragRepresentation: String {
        SourceMessageDragPayload(
            sourceID: sourceID,
            messageID: header.id
        ).encodedRepresentation
    }
}
