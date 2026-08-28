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

@Suite("MessageSecurityState")
struct MessageSecurityStateTests {
    @Test("none state is not secure and has no warning")
    func noneStateProperties() {
        #expect(!MessageSecurityState.none.isSecure)
        #expect(!MessageSecurityState.none.hasWarning)
        #expect(MessageSecurityState.none.summary.isEmpty)
    }

    @Test("encrypted state is not secure and has a warning")
    func encryptedStateProperties() {
        #expect(!MessageSecurityState.encrypted.isSecure)
        #expect(MessageSecurityState.encrypted.hasWarning)
        #expect(!MessageSecurityState.encrypted.summary.isEmpty)
    }

    @Test("decrypted+verified is secure and has no warning")
    func decryptedVerifiedIsSecure() {
        let state = MessageSecurityState.decrypted(signatureState: .verified(signer: "Alice <alice@example.com>"))
        #expect(state.isSecure)
        #expect(!state.hasWarning)
        #expect(state.summary.contains("Verified"))
    }

    @Test("decrypted+unverified is not secure and has a warning")
    func decryptedUnverifiedHasWarning() {
        let state = MessageSecurityState.decrypted(signatureState: .unverified(reason: "Key not trusted"))
        #expect(!state.isSecure)
        #expect(state.hasWarning)
    }

    @Test("decryptionFailed has warning and descriptive summary")
    func decryptionFailedHasWarning() {
        let state = MessageSecurityState.decryptionFailed(reason: "No matching private key")
        #expect(state.hasWarning)
        #expect(state.summary.contains("No matching"))
    }

    @Test("signed+verified state is secure")
    func signedVerifiedIsSecure() {
        let state = MessageSecurityState.signed(state: .verified(signer: "Bob"))
        #expect(state.isSecure)
        #expect(!state.hasWarning)
    }
}
