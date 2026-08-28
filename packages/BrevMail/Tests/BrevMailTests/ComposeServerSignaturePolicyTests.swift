/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions.
 */

import BrevBackend
@testable import BrevMail
import Testing

@Suite("Compose server signature policy")
struct ComposeServerSignaturePolicyTests {
    @Test("selects the default signature for the active alias only")
    func selectsActiveAliasDefault() throws {
        let context = try #require(ComposeServerSignaturePolicy.context(
            from: [
                ServerSignature(id: "primary@example.com", name: "Primary", body: "Primary"),
                ServerSignature(id: "team@example.com", name: "Team", body: "Team", isDefault: true),
                ServerSignature(id: "other@example.com", name: "Other", body: "Other", isDefault: true)
            ],
            selectedAliasID: "team@example.com",
            senderEmail: "primary@example.com"
        ))

        #expect(context.selectedSignatureID == "team@example.com")
        #expect(context.options.map(\.id) == ["team@example.com"])
    }

    @Test("returns nil when no server signature belongs to the sender")
    func preservesLocalFallbackWhenAliasHasNoServerSignature() {
        let context = ComposeServerSignaturePolicy.context(
            from: [ServerSignature(id: "other@example.com", name: "Other", body: "Other")],
            selectedAliasID: "team@example.com",
            senderEmail: "primary@example.com"
        )
        #expect(context == nil)
    }

    @Test("falls back to the local context when an alias has no matching server signature")
    func fallsBackToLocalContextWhenAliasHasNoMatchingServerSignature() {
        let localContext = ComposeSignatureContext(
            selectedSignatureID: "local",
            options: [ComposeSignatureOption(id: "local", title: "Local", body: "Local")]
        )

        let context = ComposeServerSignaturePolicy.contextForReload(
            serverSignatures: [
                ServerSignature(id: "other@example.com", name: "Other", body: "Other")
            ],
            selectedAliasID: "team@example.com",
            senderEmail: "primary@example.com",
            localContext: localContext
        )

        #expect(context == localContext)
    }

    @Test("falls back to the local context when server signature fetching fails")
    func fallsBackToLocalContextWhenServerSignatureFetchingFails() {
        let localContext = ComposeSignatureContext(
            selectedSignatureID: "local",
            options: [ComposeSignatureOption(id: "local", title: "Local", body: "Local")]
        )

        let context = ComposeServerSignaturePolicy.contextForReload(
            serverSignatures: nil,
            selectedAliasID: "team@example.com",
            senderEmail: "primary@example.com",
            localContext: localContext
        )

        #expect(context == localContext)
    }
}
