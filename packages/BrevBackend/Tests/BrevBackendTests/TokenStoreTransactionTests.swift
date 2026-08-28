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

@Suite("TokenStore transactions")
struct TokenStoreTransactionTests {
    @Test("withTokenInstalled keeps the new token when the operation succeeds")
    func withTokenInstalledKeepsNewTokenOnSuccess() async throws {
        let store = InMemoryTransactionalTokenStore()
        let token = Token(accessToken: "fresh", refreshToken: "refresh", expiresAt: .distantFuture)

        let result = try await store.withTokenInstalled(token, for: "account") {
            #expect(await store.token(for: "account") == token)
            return "connected"
        }

        #expect(result == "connected")
        #expect(await store.token(for: "account") == token)
    }

    @Test("withTokenInstalled clears the new token when a fresh operation fails")
    func withTokenInstalledClearsFreshTokenOnFailure() async throws {
        let store = InMemoryTransactionalTokenStore()
        let token = Token(accessToken: "fresh", refreshToken: "refresh", expiresAt: .distantFuture)

        do {
            _ = try await store.withTokenInstalled(token, for: "account") {
                throw TestError.connectFailed
            } as String
            Issue.record("Expected token transaction to rethrow the connect failure.")
        } catch TestError.connectFailed {
            // Expected.
        } catch {
            Issue.record("Expected TestError.connectFailed, got \(error).")
        }

        #expect(await store.token(for: "account") == nil)
    }

    @Test("withTokenInstalled restores a previous token when replacement fails")
    func withTokenInstalledRestoresPreviousTokenOnFailure() async throws {
        let store = InMemoryTransactionalTokenStore()
        let previous = Token(accessToken: "old", refreshToken: "old-refresh", expiresAt: .distantFuture)
        let replacement = Token(accessToken: "fresh", refreshToken: "refresh", expiresAt: .distantFuture)
        await store.setToken(previous, for: "account")

        do {
            _ = try await store.withTokenInstalled(replacement, for: "account") {
                #expect(await store.token(for: "account") == replacement)
                throw TestError.connectFailed
            } as String
            Issue.record("Expected token transaction to rethrow the connect failure.")
        } catch TestError.connectFailed {
            // Expected.
        } catch {
            Issue.record("Expected TestError.connectFailed, got \(error).")
        }

        #expect(await store.token(for: "account") == previous)
    }
}

private enum TestError: Error {
    case connectFailed
}

private actor InMemoryTransactionalTokenStore: TokenStore {
    private var tokens: [String: Token] = [:]

    func token(for accountID: String) -> Token? {
        tokens[accountID]
    }

    func setToken(_ token: Token, for accountID: String) {
        tokens[accountID] = token
    }

    func clearToken(for accountID: String) {
        tokens[accountID] = nil
    }
}
