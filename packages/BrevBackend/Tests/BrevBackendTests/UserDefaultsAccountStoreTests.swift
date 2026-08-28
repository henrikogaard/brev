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

@Suite("UserDefaultsAccountStore")
struct UserDefaultsAccountStoreTests {
    @Test("accounts and current selection survive a new store instance")
    func accountsAndCurrentSelectionPersist() async throws {
        let defaults = try Self.makeDefaults()
        let account = BrevAccount(
            id: "mbx-1",
            displayName: "Ada",
            emailAddress: "ada@example.org"
        )
        let store = UserDefaultsAccountStore(userDefaults: defaults, key: "accounts")

        await store.add(account)
        await store.setCurrent(account.id)

        let restored = UserDefaultsAccountStore(userDefaults: defaults, key: "accounts")
        #expect(await restored.accounts == [account])
        #expect(await restored.current == account)
    }

    @Test("remove persists the updated account list and current selection")
    func removePersistsUpdatedState() async throws {
        let defaults = try Self.makeDefaults()
        let first = BrevAccount(id: "a", displayName: "A", emailAddress: "a@example.org")
        let second = BrevAccount(id: "b", displayName: "B", emailAddress: "b@example.org")
        let store = UserDefaultsAccountStore(userDefaults: defaults, key: "accounts")

        await store.add(first)
        await store.add(second)
        await store.setCurrent(second.id)
        await store.remove(second.id)

        let restored = UserDefaultsAccountStore(userDefaults: defaults, key: "accounts")
        #expect(await restored.accounts == [first])
        #expect(await restored.current == first)
    }

    @Test("adding an existing account replaces its persisted identity")
    func addExistingAccountReplacesPersistedIdentity() async throws {
        let defaults = try Self.makeDefaults()
        let fallback = BrevAccount(
            id: "opaque-user",
            displayName: "Legacy user",
            emailAddress: "unknown@example.org"
        )
        let refined = BrevAccount(
            id: fallback.id,
            displayName: "primary@example.test",
            emailAddress: "primary@example.test"
        )
        let store = UserDefaultsAccountStore(userDefaults: defaults, key: "accounts")

        await store.add(fallback)
        await store.setCurrent(fallback.id)
        await store.add(refined)

        let restored = UserDefaultsAccountStore(userDefaults: defaults, key: "accounts")
        #expect(await restored.accounts == [refined])
        #expect(await restored.current == refined)
    }

    @Test("stale persisted current selection falls back to the first saved account")
    func stalePersistedCurrentSelectionFallsBack() async throws {
        let defaults = try Self.makeDefaults()
        let first = BrevAccount(id: "a", displayName: "A", emailAddress: "a@example.org")
        let second = BrevAccount(id: "b", displayName: "B", emailAddress: "b@example.org")
        let staleSnapshot = PersistedAccountSnapshot(
            accounts: [first, second],
            currentID: "missing"
        )
        let data = try JSONEncoder().encode(staleSnapshot)
        defaults.set(data, forKey: "accounts")

        let store = UserDefaultsAccountStore(userDefaults: defaults, key: "accounts")

        #expect(await store.accounts == [first, second])
        #expect(await store.current == first)
        let persistedData = try #require(defaults.data(forKey: "accounts"))
        let persistedSnapshot = try JSONDecoder().decode(
            PersistedAccountSnapshot.self,
            from: persistedData
        )
        #expect(persistedSnapshot.currentID == first.id)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "app.brev.tests.account-store.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct PersistedAccountSnapshot: Codable {
    var accounts: [BrevAccount]
    var currentID: String?
}
