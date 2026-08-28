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

@testable import BrevBackend
import Foundation
import Testing

@Suite("ScheduledSendStore purge (#167)")
struct ScheduledSendStorePurgeTests {
    @Test("purge removes an account's scheduled sends so none linger after removal")
    func purgeClearsEntries() {
        let store = ScheduledSendStore()
        let accountID = "imap-smtp:purge-\(UUID().uuidString)@example.org"
        store.add(
            entry: ScheduledDraftEntry(draftID: "d1", scheduledFor: Date(timeIntervalSince1970: 1000)),
            accountID: accountID
        )
        #expect(!store.entries(accountID: accountID).isEmpty)

        ScheduledSendStore.purge(accountID: accountID)

        // A fresh store reads from persistence — the entries are gone.
        #expect(ScheduledSendStore().entries(accountID: accountID).isEmpty)
    }

    @Test("one store keeps each account's schedule cache separate")
    func cacheIsScopedByAccount() {
        let store = ScheduledSendStore()
        let firstAccount = "imap-smtp:first-\(UUID().uuidString)@example.org"
        let secondAccount = "imap-smtp:second-\(UUID().uuidString)@example.org"
        store.add(
            entry: ScheduledDraftEntry(draftID: "first-draft", scheduledFor: Date(timeIntervalSince1970: 1000)),
            accountID: firstAccount
        )
        store.add(
            entry: ScheduledDraftEntry(draftID: "second-draft", scheduledFor: Date(timeIntervalSince1970: 1000)),
            accountID: secondAccount
        )

        #expect(store.entries(accountID: firstAccount).map(\.draftID) == ["first-draft"])
        #expect(store.entries(accountID: secondAccount).map(\.draftID) == ["second-draft"])
    }
}
