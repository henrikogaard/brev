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
import Foundation
import Testing

@Suite("MessageListMutationRollback")
@MainActor
struct MessageListMutationRollbackTests {
    @Test("rollback restores displayed headers, loaded folder headers, and navigation state")
    func rollbackRestoresDisplayedHeadersLoadedFolderHeadersAndNavigationState() {
        let first = Self.makeHeader(id: "first")
        let folderOnly = Self.makeHeader(id: "folder-only")
        let second = Self.makeHeader(id: "second")
        let navigation = MailNavigationState(
            selectedMessageID: second.id,
            currentFolderHeaders: [first, second],
            bulkSelection: [first.id, second.id]
        )
        let rollback = MessageListMutationRollback(
            visibleHeaders: [first, second],
            loadedFolderHeaders: [first, folderOnly, second],
            navigation: navigation
        )

        navigation.removeHeaders(ids: [second.id])
        navigation.bulkSelection.removeAll()
        let restored = rollback.restore(navigation: navigation)

        #expect(restored.headers == [first, second])
        #expect(restored.loadedFolderHeaders == [first, folderOnly, second])
        #expect(navigation.currentFolderHeaders == [first, second])
        #expect(navigation.selectedMessageID == second.id)
        #expect(navigation.bulkSelection == [first.id, second.id])
    }

    @Test("unified rollback restores items, item selection, and navigation headers")
    func unifiedRollbackRestoresItemsSelectionAndNavigationHeaders() {
        let sourceID = MailSourceID(accountID: "account", mailboxID: "mailbox")
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let original = Self.makeUnifiedItem(
            sourceID: sourceID,
            folder: folder,
            header: Self.makeHeader(id: "message", isFlagged: false)
        )
        var flagged = original
        flagged.header.isFlagged = true
        let navigation = MailNavigationState(
            selectedSourceID: sourceID,
            selectedFolderID: folder.id,
            selectedMessageID: original.header.id,
            currentFolderHeaders: [original.header],
            bulkSelection: [original.header.id]
        )
        let rollback = UnifiedInboxMutationRollback(
            items: [original],
            selectedItemIDs: [original.id],
            navigation: navigation
        )

        navigation.updateHeader(id: flagged.header.id) { $0 = flagged.header }
        navigation.bulkSelection.removeAll()
        let restored = rollback.restore(navigation: navigation)

        #expect(restored.items == [original])
        #expect(restored.selectedItemIDs == [original.id])
        #expect(navigation.currentFolderHeaders == [original.header])
        #expect(navigation.selectedMessageID == original.header.id)
        #expect(navigation.bulkSelection == [original.header.id])
    }

    private static func makeUnifiedItem(
        sourceID: MailSourceID,
        folder: Folder,
        header: MessageHeader
    ) -> UnifiedInboxItem {
        UnifiedInboxItem(
            sourceID: sourceID,
            folder: folder,
            header: header,
            sourceTitle: "Mailbox",
            sourceSubtitle: "mailbox@example.org",
            archiveFolder: nil
        )
    }

    private static func makeHeader(
        id: MessageHeader.ID,
        isFlagged: Bool = false
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: "inbox",
            from: Correspondent(name: "Ada Lovelace", email: "ada@example.com"),
            to: [Correspondent(name: "Brev", email: "hello@brev.test")],
            subject: "Subject \(id)",
            snippet: "Snippet",
            date: Date(timeIntervalSince1970: 1_735_689_600),
            isFlagged: isFlagged
        )
    }
}
