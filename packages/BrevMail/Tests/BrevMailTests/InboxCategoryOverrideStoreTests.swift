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
import BrevDesign
@testable import BrevMail
import Foundation
import Testing

@Suite("InboxCategoryOverrideStore")
struct InboxCategoryOverrideStoreTests {
    @Test("manual overrides are scoped by source identity and message id")
    func overridesAreScopedBySourceIdentityAndMessageID() throws {
        let defaults = try Self.makeDefaults()
        let store = InboxCategoryOverrideStore(defaults: defaults)
        let accountA = MailSourceID(accountID: "account-a", mailboxID: "mailbox-a")
        let accountB = MailSourceID(accountID: "account-b", mailboxID: "mailbox-b")
        let messageA = SourceMessageID(sourceID: accountA, messageID: "same-id")
        let messageB = SourceMessageID(sourceID: accountB, messageID: "same-id")

        store.set(.transactions, for: messageA)

        #expect(store.category(for: messageA) == .transactions)
        #expect(store.category(for: messageB) == nil)
    }

    @Test("clearing an override removes only that scoped message")
    func clearingOverrideRemovesOnlyThatScopedMessage() throws {
        let defaults = try Self.makeDefaults()
        let store = InboxCategoryOverrideStore(defaults: defaults)
        let source = MailSourceID(accountID: "account-a", mailboxID: "mailbox-a")
        let first = SourceMessageID(sourceID: source, messageID: "first")
        let second = SourceMessageID(sourceID: source, messageID: "second")
        store.set(.promotions, for: first)
        store.set(.updates, for: second)

        store.clear(first)

        #expect(store.category(for: first) == nil)
        #expect(store.category(for: second) == .updates)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "InboxCategoryOverrideStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
