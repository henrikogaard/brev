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
@testable import BrevMail
import Testing

@Suite("FolderDropRefreshPolicy")
struct FolderDropRefreshPolicyTests {
    @Test("cross-folder drops refresh source removals and destination additions")
    func crossFolderDropsRefreshSourceAndDestination() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let archive = Folder(id: "archive", name: "Archive", role: .archive)

        #expect(FolderDropRefreshPolicy.events(
            messageIDs: ["m1", "m2"],
            from: inbox,
            to: archive
        ) == [
            .messagesRemoved(folderID: "inbox", messageIDs: ["m1", "m2"]),
            .messagesAdded(folderID: "archive", messageIDs: ["m1", "m2"])
        ])
    }

    @Test("empty source or same-folder drops do not request refresh work")
    func emptySourceOrSameFolderDropsDoNotRefresh() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)

        #expect(FolderDropRefreshPolicy.events(messageIDs: [], from: inbox, to: inbox).isEmpty)
        #expect(FolderDropRefreshPolicy.events(messageIDs: ["m1"], from: nil, to: inbox).isEmpty)
        #expect(FolderDropRefreshPolicy.events(messageIDs: ["m1"], from: inbox, to: inbox).isEmpty)
    }
}
