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
import Foundation

/// Coalesces a burst of mailbox-change events into one root refresh pass.
struct MailRootBackendEventRefreshBatch: Equatable {
    private(set) var folderIDs: Set<Folder.ID> = []
    private(set) var requiresSourceSectionsRefresh = false

    var isEmpty: Bool { folderIDs.isEmpty && !requiresSourceSectionsRefresh }

    mutating func record(
        _ event: MailEvent,
        requiresSourceSectionsRefresh: Bool = false
    ) {
        self.requiresSourceSectionsRefresh = self.requiresSourceSectionsRefresh
            || requiresSourceSectionsRefresh
        switch event {
        case .folderRefreshed(let folderID),
             .messagesAdded(let folderID, _),
             .messagesRemoved(let folderID, _),
             .messagesUpdated(let folderID, _):
            folderIDs.insert(folderID)
        case .accountConnected, .accountDisconnected, .mailboxChanged, .syncProgress, .outboxChanged:
            break
        }
    }

    func affectsVisibleFolder(_ folderID: Folder.ID?) -> Bool {
        guard let folderID else { return false }
        return folderIDs.contains(folderID)
    }
}
