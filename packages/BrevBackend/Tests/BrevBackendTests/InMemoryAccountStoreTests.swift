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
import Testing

@Suite("InMemoryAccountStore")
struct InMemoryAccountStoreTests {
    @Test("Add and read back")
    func addAndRead() async {
        let store = InMemoryAccountStore()
        let account = BrevAccount(
            id: "a",
            displayName: "Aria",
            emailAddress: "aria@example.com"
        )
        await store.add(account)
        let accounts = await store.accounts
        #expect(accounts.map(\.id) == ["a"])
        let current = await store.current
        #expect(current?.id == "a")
    }

    @Test("Remove clears current")
    func removeClearsCurrent() async {
        let store = InMemoryAccountStore()
        await store.add(BrevAccount(id: "a", displayName: "A", emailAddress: "a@x"))
        await store.remove("a")
        let current = await store.current
        #expect(current == nil)
    }

    @Test("setCurrent ignores unknown ids")
    func ignoresUnknown() async {
        let store = InMemoryAccountStore()
        await store.add(BrevAccount(id: "a", displayName: "A", emailAddress: "a@x"))
        await store.setCurrent("missing")
        let current = await store.current
        #expect(current?.id == "a")
    }
}
