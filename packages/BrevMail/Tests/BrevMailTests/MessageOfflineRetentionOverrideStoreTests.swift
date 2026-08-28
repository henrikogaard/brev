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

@Suite("MessageOfflineRetentionOverrideStore")
struct MessageOfflineRetentionOverrideStoreTests {
    private func freshStore(_ name: String) -> MessageOfflineRetentionOverrideStore {
        let suite = "test.offlineRetention.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return MessageOfflineRetentionOverrideStore(defaults: defaults)
    }

    private func id(_ message: String, account: String = "a", mailbox: String = "a") -> SourceMessageID {
        SourceMessageID(
            sourceID: MailSourceID(accountID: account, mailboxID: mailbox),
            messageID: message
        )
    }

    @Test("pinning a message persists and clears")
    func pinPersistsAndClears() {
        let store = freshStore("pin")
        #expect(!store.isKeptOffline(id("INBOX:1")))
        store.setKeptOffline(true, for: id("INBOX:1"))
        #expect(store.isKeptOffline(id("INBOX:1")))
        store.setKeptOffline(false, for: id("INBOX:1"))
        #expect(!store.isKeptOffline(id("INBOX:1")))
    }

    @Test("kept IDs for a source are the bare message IDs, scoped by account+mailbox")
    func keptIDsScopedBySource() {
        let store = freshStore("scope")
        store.setKeptOffline(true, for: id("INBOX:1"))
        store.setKeptOffline(true, for: id("INBOX:2"))
        store.setKeptOffline(true, for: id("INBOX:9", account: "b", mailbox: "b"))
        #expect(
            store.keptOfflineMessageIDs(forSource: MailSourceID(accountID: "a", mailboxID: "a"))
                == ["INBOX:1", "INBOX:2"]
        )
        #expect(
            store.keptOfflineMessageIDs(forSource: MailSourceID(accountID: "b", mailboxID: "b"))
                == ["INBOX:9"]
        )
    }

    @Test("lookup matches by account, so a pin written under a different mailbox id is still found")
    func lookupMatchesByAccountAcrossMailboxes() {
        let store = freshStore("acct")
        // Pin written under the local-workflow fallback key (mailboxID == accountID),
        // as smart views do.
        store.setKeptOffline(true, for: id("INBOX:1", account: "acct-1", mailbox: "acct-1"))
        // The retention sweep keys this account's folder by its real mailboxID,
        // which differs from the fallback — the pin must still be found.
        #expect(
            store.keptOfflineMessageIDs(forSource: MailSourceID(accountID: "acct-1", mailboxID: "mbox-9"))
                == ["INBOX:1"]
        )
        // A different account does not pick it up.
        #expect(
            store.keptOfflineMessageIDs(forSource: MailSourceID(accountID: "other", mailboxID: "acct-1")).isEmpty
        )
    }
}
