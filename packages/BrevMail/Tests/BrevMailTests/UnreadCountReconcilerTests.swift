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

@Suite("UnreadCountReconciler")
struct UnreadCountReconcilerTests {
    private func makeFolder(id: String = "inbox", unread: Int = 5, role: FolderRole = .inbox) -> Folder {
        Folder(
            id: id,
            name: "Inbox",
            role: role,
            parentID: nil,
            unreadCount: unread,
            totalCount: 10
        )
    }

    @Test("mark-read bulk subtracts from the source folder")
    func markReadBulkSubtracts() {
        let reconciler = UnreadCountReconciler()
        let inbox = makeFolder(unread: 10)
        let updated = reconciler.adjust(folder: inbox, delta: -3)
        #expect(updated.unreadCount == 7)
    }

    @Test("mark-unread bulk adds to the source folder")
    func markUnreadBulkAdds() {
        let reconciler = UnreadCountReconciler()
        let inbox = makeFolder(unread: 4)
        let updated = reconciler.adjust(folder: inbox, delta: 5)
        #expect(updated.unreadCount == 9)
    }

    @Test("negative result is clamped to zero")
    func negativeResultClampedToZero() {
        let reconciler = UnreadCountReconciler()
        let inbox = makeFolder(unread: 2)
        let updated = reconciler.adjust(folder: inbox, delta: -10)
        #expect(updated.unreadCount == 0)
    }

    @Test("zero delta is a no-op that returns the original folder")
    func zeroDeltaIsNoOp() {
        let reconciler = UnreadCountReconciler()
        let inbox = makeFolder(unread: 7)
        let updated = reconciler.adjust(folder: inbox, delta: 0)
        #expect(updated == inbox)
    }

    @Test("apply updates only the matching folder in the list")
    func applyUpdatesOnlyMatchingFolder() {
        let reconciler = UnreadCountReconciler()
        let inbox = makeFolder(id: "inbox", unread: 5)
        let sent = makeFolder(id: "sent", unread: 3, role: .sent)
        let result = reconciler.apply(folderID: "inbox", delta: -2, to: [inbox, sent])
        #expect(result.count == 2)
        #expect(result[0].unreadCount == 3)
        #expect(result[1] == sent)
    }

    @Test("apply returns the list unchanged when the folder is missing")
    func applyReturnsListUnchangedForMissingFolder() {
        let reconciler = UnreadCountReconciler()
        let inbox = makeFolder(unread: 5)
        let result = reconciler.apply(folderID: "ghost", delta: -2, to: [inbox])
        #expect(result == [inbox])
    }

    @Test("bulk-move from Inbox to Sent: source loses, destination gains")
    func bulkMoveSourceAndDestinationAdjustment() {
        let reconciler = UnreadCountReconciler()
        let inbox = makeFolder(id: "inbox", unread: 5, role: .inbox)
        let sent = makeFolder(id: "sent", unread: 0, role: .sent)
        let afterSource = reconciler.apply(folderID: "inbox", delta: -2, to: [inbox, sent])
        let afterDestination = reconciler.apply(folderID: "sent", delta: 2, to: afterSource)
        #expect(afterDestination[0].unreadCount == 3)
        #expect(afterDestination[1].unreadCount == 2)
    }

    @Test("adjust by folderID returns a Folder when found, nil otherwise")
    func adjustByFolderIDReturnsNilWhenMissing() {
        let reconciler = UnreadCountReconciler()
        let inbox = makeFolder(unread: 5)
        let result = reconciler.adjust(folderID: "ghost", delta: -1, in: [inbox])
        #expect(result == nil)
        let hit = reconciler.adjust(folderID: "inbox", delta: -1, in: [inbox])
        #expect(hit?.unreadCount == 4)
    }
}
