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

@Suite("KeychainTokenStore", .serialized)
struct KeychainTokenStoreTests {
    @Test("tokens round trip, update, and clear from an isolated keychain service")
    func tokensRoundTripUpdateAndClear() async throws {
        let accountID = "account-\(UUID().uuidString)"
        let store = KeychainTokenStore(service: "app.brev.tests.tokens.\(UUID().uuidString)")
        let first = Token(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let updated = Token(
            accessToken: "access-2",
            refreshToken: "refresh-2",
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
        )

        try await store.setToken(first, for: accountID)
        #expect(await store.token(for: accountID) == first)

        try await store.setToken(updated, for: accountID)
        #expect(await store.token(for: accountID) == updated)

        await store.clearToken(for: accountID)
        #expect(await store.token(for: accountID) == nil)
    }

    @Test("tokens are isolated by account id")
    func tokensAreIsolatedByAccountID() async throws {
        let service = "app.brev.tests.tokens.\(UUID().uuidString)"
        let firstStore = KeychainTokenStore(service: service)
        let secondStore = KeychainTokenStore(service: service)
        let first = Token(
            accessToken: "first-access",
            refreshToken: "first-refresh",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let second = Token(
            accessToken: "second-access",
            refreshToken: "second-refresh",
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
        )

        try await firstStore.setToken(first, for: "first")
        try await secondStore.setToken(second, for: "second")

        #expect(await firstStore.token(for: "first") == first)
        #expect(await firstStore.token(for: "second") == second)
        #expect(await secondStore.token(for: "first") == first)
        #expect(await secondStore.token(for: "second") == second)

        await firstStore.clearToken(for: "first")
        #expect(await firstStore.token(for: "first") == nil)
        #expect(await firstStore.token(for: "second") == second)

        await secondStore.clearToken(for: "second")
        #expect(await secondStore.token(for: "second") == nil)
    }
}
