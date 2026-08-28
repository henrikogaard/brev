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

@Suite("FolderSelectionPolicy")
struct FolderSelectionPolicyTests {
    @Test("preserves the selected folder when it is still loaded")
    func preservesCurrentFolderWhenLoaded() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let archive = Folder(id: "archive", name: "Archive", role: .archive)

        #expect(FolderSelectionPolicy.selectedFolderID(
            afterLoading: [inbox, archive],
            currentID: archive.id
        ) == archive.id)
    }

    @Test("selects Inbox when no folder is selected")
    func selectsInboxWhenNoFolderIsSelected() {
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)

        #expect(FolderSelectionPolicy.selectedFolderID(
            afterLoading: [archive, inbox],
            currentID: nil
        ) == inbox.id)
    }

    @Test("replaces a stale selected folder with Inbox")
    func replacesStaleSelectionWithInbox() {
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)

        #expect(FolderSelectionPolicy.selectedFolderID(
            afterLoading: [archive, inbox],
            currentID: "removed-folder"
        ) == inbox.id)
    }

    @Test("falls back to the first loaded folder when Inbox is unavailable")
    func fallsBackToFirstFolderWithoutInbox() {
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let sent = Folder(id: "sent", name: "Sent", role: .sent)

        #expect(FolderSelectionPolicy.selectedFolderID(
            afterLoading: [archive, sent],
            currentID: "removed-folder"
        ) == archive.id)
    }

    @Test("clears selection when no folders are loaded")
    func clearsSelectionWhenNoFoldersAreLoaded() {
        #expect(FolderSelectionPolicy.selectedFolderID(
            afterLoading: [],
            currentID: "removed-folder"
        ) == nil)
    }
}
