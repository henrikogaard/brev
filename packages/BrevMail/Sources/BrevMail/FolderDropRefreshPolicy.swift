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

/// Converts successful folder-drop moves into backend-style events
/// so the root view can refresh the right panes without knowing how
/// the user initiated the move.
public enum FolderDropRefreshPolicy {
    public static func events(
        messageIDs: [MessageHeader.ID],
        from sourceFolder: Folder?,
        to destinationFolder: Folder
    ) -> [MailEvent] {
        guard let sourceFolder,
              !messageIDs.isEmpty,
              sourceFolder.id != destinationFolder.id
        else {
            return []
        }
        return [
            .messagesRemoved(folderID: sourceFolder.id, messageIDs: messageIDs),
            .messagesAdded(folderID: destinationFolder.id, messageIDs: messageIDs)
        ]
    }
}
