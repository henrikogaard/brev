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

@Suite("MessageListMutationRefreshPolicy")
struct MessageListMutationRefreshPolicyTests {
    @Test("read and flag mutations refresh visible messages as updates")
    func readAndFlagMutationsRefreshVisibleMessagesAsUpdates() {
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)

        #expect(MessageListMutationRefreshPolicy.updated(
            messageIDs: ["m1", "m2"],
            in: folder
        ) == .messagesUpdated(folderID: "inbox", messageIDs: ["m1", "m2"]))
    }

    @Test("archive and delete mutations refresh visible messages as removals")
    func archiveAndDeleteMutationsRefreshVisibleMessagesAsRemovals() {
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)

        #expect(MessageListMutationRefreshPolicy.removed(
            messageIDs: ["m3"],
            from: folder
        ) == .messagesRemoved(folderID: "inbox", messageIDs: ["m3"]))
    }

    @Test("empty or missing folders do not request refresh work")
    func emptyOrMissingFoldersDoNotRequestRefreshWork() {
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)

        #expect(MessageListMutationRefreshPolicy.updated(messageIDs: [], in: folder) == nil)
        #expect(MessageListMutationRefreshPolicy.removed(messageIDs: ["m1"], from: nil) == nil)
    }
}
