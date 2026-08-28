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

import BrevAI
import BrevBackend
@testable import BrevMail
import Testing

@Suite("AIBackendAccountRouter")
struct AIBackendAccountRouterTests {
    @Test("router returns the provider assigned to the selected account")
    func routerReturnsProviderAssignedToSelectedAccount() {
        let accountA = BrevAccount(id: "a", displayName: "A", emailAddress: "a@example.org")
        let accountB = BrevAccount(id: "b", displayName: "B", emailAddress: "b@example.org")
        let backendA = StubAccountAIBackend(identifier: "provider-a")
        let backendB = StubAccountAIBackend(identifier: "provider-b")
        let router = AIBackendAccountRouter(backendsByAccountID: [
            accountA.id: backendA,
            accountB.id: backendB
        ])

        #expect(router.backend(for: accountB)?.identifier == "provider-b")
        #expect(router.backend(for: accountA)?.identifier == "provider-a")
    }

    @Test("router does not silently fall back when no account provider exists")
    func routerDoesNotSilentlyFallbackWhenNoAccountProviderExists() {
        let account = BrevAccount(id: "imap", displayName: "IMAP", emailAddress: "imap@example.org")
        let router = AIBackendAccountRouter(backendsByAccountID: [:])

        #expect(router.backend(for: account) == nil)
    }

    @Test("router can keep a legacy fallback for single-account callers")
    func routerCanKeepLegacyFallbackForSingleAccountCallers() {
        let account = BrevAccount(id: "single", displayName: "Single", emailAddress: "single@example.org")
        let fallback = StubAccountAIBackend(identifier: "fallback")
        let router = AIBackendAccountRouter(backendsByAccountID: [:], fallback: fallback)

        #expect(router.backend(for: account)?.identifier == "fallback")
    }
}

private struct StubAccountAIBackend: AIBackend {
    let identifier: String
    let displayName = "Stub"
    let transparencyLabel = "Sent to: Stub"

    func generateReply(to _: [AIMessage], instruction _: String?) async throws -> AIResponse {
        AIResponse(text: "")
    }

    func shortcut(_: AIShortcutAction, on text: String) async throws -> AIResponse {
        AIResponse(text: text)
    }
}
