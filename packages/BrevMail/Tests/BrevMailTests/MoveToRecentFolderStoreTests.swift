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

@Suite("MoveToRecentFolderStore")
struct MoveToRecentFolderStoreTests {
    @Test("recent folders are scoped by source")
    func recentFoldersAreScopedBySource() {
        let defaults = Self.makeDefaults()
        let store = MoveToRecentFolderStore(defaults: defaults)
        let sourceA = MailSourceID(accountID: "acct-a", mailboxID: "box-a")
        let sourceB = MailSourceID(accountID: "acct-a", mailboxID: "box-b")

        store.record(folderID: "archive", sourceID: sourceA)
        store.record(folderID: "receipts", sourceID: sourceB)

        #expect(store.recentFolderIDs(for: sourceA) == ["archive"])
        #expect(store.recentFolderIDs(for: sourceB) == ["receipts"])
    }

    @Test("recording a folder moves it to the front and caps stored values")
    func recordingMovesToFrontAndCapsValues() {
        let defaults = Self.makeDefaults()
        let store = MoveToRecentFolderStore(defaults: defaults)
        let sourceID = MailSourceID(accountID: "acct", mailboxID: "box")

        for id in ["a", "b", "c", "d", "e", "f"] {
            store.record(folderID: id, sourceID: sourceID)
        }
        store.record(folderID: "c", sourceID: sourceID)

        #expect(store.recentFolderIDs(for: sourceID) == ["c", "f", "e", "d", "b"])
    }

    @Test("recent candidates are ordered first and invalid targets are omitted")
    func recentCandidatesAreOrderedFirstAndInvalidTargetsOmitted() {
        let folders = [
            Folder(id: "inbox", name: "Inbox", role: .inbox),
            Folder(id: "archive", name: "Archive", role: .archive),
            Folder(id: "starred", name: "Starred", role: .starred),
            Folder(id: "receipts", name: "Receipts", role: .custom),
            Folder(id: "trash", name: "Trash", role: .trash),
        ]

        let sorted = MoveToRecentFolderStore.sortedMoveCandidates(
            from: folders,
            currentFolderID: "inbox",
            recentFolderIDs: ["missing", "receipts", "starred", "archive"]
        )

        #expect(sorted.map(\.id) == ["receipts", "archive", "trash"])
    }

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "MoveToRecentFolderStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
