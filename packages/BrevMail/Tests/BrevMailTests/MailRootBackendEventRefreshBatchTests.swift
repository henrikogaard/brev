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

@Suite("MailRootBackendEventRefreshBatch")
struct MailRootBackendEventRefreshBatchTests {
    @Test("deduplicates a mailbox event burst by folder")
    func deduplicatesBurstByFolder() {
        var batch = MailRootBackendEventRefreshBatch()

        batch.record(.messagesAdded(folderID: "INBOX", messageIDs: ["INBOX:1"]))
        batch.record(.messagesUpdated(folderID: "INBOX", messageIDs: ["INBOX:1"]))
        batch.record(.folderRefreshed(folderID: "Archive"))

        #expect(batch.folderIDs == ["INBOX", "Archive"])
        #expect(batch.affectsVisibleFolder("INBOX"))
        #expect(!batch.affectsVisibleFolder("Drafts"))
    }

    @Test("ignores non-folder events")
    func ignoresNonFolderEvents() {
        var batch = MailRootBackendEventRefreshBatch()
        batch.record(.syncProgress(completed: 1, total: 2))
        batch.record(.accountConnected(accountID: "account"))

        #expect(batch.isEmpty)
    }

    @Test("message mutations can request one source-section refresh")
    func messageMutationsRequestSourceSectionRefresh() {
        var batch = MailRootBackendEventRefreshBatch()
        batch.record(
            .messagesRemoved(folderID: "INBOX", messageIDs: ["INBOX:1"]),
            requiresSourceSectionsRefresh: true
        )

        #expect(batch.requiresSourceSectionsRefresh)
        #expect(batch.affectsVisibleFolder("INBOX"))
    }
}
