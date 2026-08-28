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
import BrevSyncEngine
import XCTest

// Helper: a BrevAccount with test defaults.
private func testAccount(id: String = "acc") -> BrevAccount {
    BrevAccount(
        id: id,
        displayName: "Test Account",
        emailAddress: "test@example.com"
    )
}

final class SyncSchedulerTests: XCTestCase {
    func testNextReturnsNilWhenQueueIsEmpty() async {
        let scheduler = SyncScheduler(maximumFoldersPerActivation: 12)
        let entry = await scheduler.next()
        XCTAssertNil(entry)
    }

    func testNextRespectsActivationCap() async {
        let scheduler = SyncScheduler(maximumFoldersPerActivation: 2)
        await scheduler.beginActivation()

        let account = testAccount()
        let entries = (0 ..< 5).map { i in
            SyncQueueEntry(
                account: account,
                folder: Folder(id: "folder-\(i)", name: "Folder \(i)", role: .custom, parentID: nil),
                priority: .background
            )
        }
        await scheduler.enqueue(entries)

        let first = await scheduler.next()
        let second = await scheduler.next()
        let third = await scheduler.next()

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNil(third, "next() should return nil after the activation cap is reached")
    }

    func testInboxPriorityIsHigherThanBackground() async {
        let scheduler = SyncScheduler(maximumFoldersPerActivation: 12)
        await scheduler.beginActivation()

        let account = testAccount()
        let backgroundFolder = Folder(id: "Archive", name: "Archive", role: .custom, parentID: nil)
        let inboxFolder = Folder(id: "INBOX", name: "Inbox", role: .inbox, parentID: nil)

        await scheduler.enqueue([
            SyncQueueEntry(account: account, folder: backgroundFolder, priority: .background),
            SyncQueueEntry(account: account, folder: inboxFolder, priority: .inbox)
        ])

        let first = await scheduler.next()
        XCTAssertEqual(first?.folder.id, "INBOX", "Inbox must be vended before background folders")
    }

    func testDuplicateEntriesAreSkipped() async {
        let scheduler = SyncScheduler(maximumFoldersPerActivation: 12)
        await scheduler.beginActivation()

        let account = testAccount()
        let folder = Folder(id: "INBOX", name: "Inbox", role: .inbox, parentID: nil)
        let entry = SyncQueueEntry(account: account, folder: folder, priority: .inbox)

        await scheduler.enqueue([entry, entry])

        let count = await scheduler.pendingCount
        XCTAssertEqual(count, 1, "Duplicate entries must not be added to the queue")
    }

    func testBeginActivationResetsCounter() async {
        let scheduler = SyncScheduler(maximumFoldersPerActivation: 1)
        await scheduler.beginActivation()

        let account = testAccount()
        let entries = (0 ..< 4).map { i in
            SyncQueueEntry(
                account: account,
                folder: Folder(id: "f-\(i)", name: "F\(i)", role: .custom, parentID: nil),
                priority: .background
            )
        }
        await scheduler.enqueue(entries)

        let firstResult = await scheduler.next()
        let capHit = await scheduler.next()
        XCTAssertNotNil(firstResult)
        XCTAssertNil(capHit, "Should hit cap after 1 folder")

        await scheduler.beginActivation()
        let afterReset = await scheduler.next()
        XCTAssertNotNil(afterReset, "New activation should allow vending again")
    }
}
