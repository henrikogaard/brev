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

@testable import BrevCalendar
import Foundation
import Testing

@Suite("CalDAVKeychainCredentialStore", .serialized)
struct CalDAVCredentialStoreTests {
    private func makeStore() -> CalDAVKeychainCredentialStore {
        CalDAVKeychainCredentialStore(service: "app.brev.tests.caldav.\(UUID().uuidString)")
    }

    @Test("bearer credential round-trips through the Keychain")
    func bearerRoundTrip() async throws {
        let store = makeStore()
        let account = "acct-\(UUID().uuidString)"
        try await store.setCredential(.bearer(token: "tok-abc"), for: account)
        defer { Task { try? await store.deleteCredential(for: account) } }

        let loaded = try await store.credential(for: account)
        #expect(loaded == .bearer(token: "tok-abc"))
    }

    @Test("basic credential round-trips through the Keychain")
    func basicRoundTrip() async throws {
        let store = makeStore()
        let account = "acct-\(UUID().uuidString)"
        try await store.setCredential(.basic(username: "u", password: "p"), for: account)
        defer { Task { try? await store.deleteCredential(for: account) } }

        let loaded = try await store.credential(for: account)
        #expect(loaded == .basic(username: "u", password: "p"))
    }

    @Test("setting a credential replaces the previous one")
    func overwriteCredential() async throws {
        let store = makeStore()
        let account = "acct-\(UUID().uuidString)"
        try await store.setCredential(.bearer(token: "old"), for: account)
        try await store.setCredential(.bearer(token: "new"), for: account)
        defer { Task { try? await store.deleteCredential(for: account) } }

        #expect(try await store.credential(for: account) == .bearer(token: "new"))
    }

    @Test("missing account returns nil")
    func missingAccountReturnsNil() async throws {
        let store = makeStore()
        #expect(try await store.credential(for: "never-set") == nil)
    }

    @Test("deleting a credential removes it")
    func deleteRemoves() async throws {
        let store = makeStore()
        let account = "acct-\(UUID().uuidString)"
        try await store.setCredential(.bearer(token: "x"), for: account)
        try await store.deleteCredential(for: account)
        #expect(try await store.credential(for: account) == nil)
    }
}
