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

@Suite("Outbound message security policy")
struct OutboundMessageSecurityPolicyTests {
    @Test("encrypt plan includes sender and hidden recipients")
    func encryptPlanIncludesSenderAndHiddenRecipients() throws {
        let plan = try OutboundMessageSecurityPolicy.prepare(
            request: OutboundMessageSecurityRequest(
                senderEmail: "Alice <alice@example.org>",
                to: ["bob@example.org"],
                cc: ["Carol <carol@example.org>"],
                bcc: ["hidden@example.org"],
                mode: .encrypt
            ),
            availability: OutboundSecurityAvailability(
                hasTrustedSigningIdentity: false,
                trustedEncryptionRecipients: [
                    "alice@example.org",
                    "bob@example.org",
                    "carol@example.org",
                    "hidden@example.org"
                ]
            )
        )

        #expect(plan.requiresSigning == false)
        #expect(plan.requiresEncryption)
        #expect(plan.encryptionRecipients == [
            "alice@example.org",
            "bob@example.org",
            "carol@example.org",
            "hidden@example.org"
        ])
    }

    @Test("signing fails closed when sender identity is missing")
    func signingFailsClosedWhenIdentityMissing() {
        #expect(throws: OutboundMessageSecurityError.missingSigningIdentity(senderEmail: "alice@example.org")) {
            try OutboundMessageSecurityPolicy.prepare(
                request: OutboundMessageSecurityRequest(
                    senderEmail: "alice@example.org",
                    to: ["bob@example.org"],
                    mode: .sign
                ),
                availability: OutboundSecurityAvailability(
                    hasTrustedSigningIdentity: false,
                    trustedEncryptionRecipients: []
                )
            )
        }
    }

    @Test("encryption fails closed when any recipient material is missing")
    func encryptionFailsClosedWhenAnyRecipientMaterialMissing() {
        #expect(throws: OutboundMessageSecurityError.missingEncryptionRecipients([
            "alice@example.org",
            "carol@example.org"
        ])) {
            try OutboundMessageSecurityPolicy.prepare(
                request: OutboundMessageSecurityRequest(
                    senderEmail: "alice@example.org",
                    to: ["Bob <bob@example.org>"],
                    cc: ["carol@example.org"],
                    mode: .signAndEncrypt
                ),
                availability: OutboundSecurityAvailability(
                    hasTrustedSigningIdentity: true,
                    trustedEncryptionRecipients: ["bob@example.org"]
                )
            )
        }
    }
}
