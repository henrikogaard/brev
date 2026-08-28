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

@Suite("Sieve script renderer")
struct SieveScriptRendererTests {
    @Test("renders conservative Brev-owned rules to a Sieve script")
    func rendersConservativeBrevOwnedRules() {
        let plan = SieveScriptRenderer.renderBrevOwnedScript(rules: [
            ServerRule(
                id: "receipts",
                name: "Receipts",
                isEnabled: true,
                conditions: [
                    .senderContains("receipts@example.org"),
                    .subjectContains("\"Paid\"")
                ],
                actions: [
                    .moveToFolder(id: "Receipts"),
                    .markRead,
                    .flag
                ]
            )
        ])

        #expect(plan.requiredExtensions == ["fileinto", "imap4flags"])
        #expect(plan.unsupportedRules.isEmpty)
        #expect(plan.script.contains("require [\"fileinto\", \"imap4flags\"];"))
        #expect(plan.script.contains(
            "if allof (header :contains \"From\" \"receipts@example.org\", "
                + "header :contains \"Subject\" \"\\\"Paid\\\"\") {"
        ))
        #expect(plan.script.contains("    fileinto \"Receipts\";"))
        #expect(plan.script.contains("    addflag \"\\\\Seen\";"))
        #expect(plan.script.contains("    addflag \"\\\\Flagged\";"))
        #expect(plan.script.contains("}"))
    }

    @Test("a rule name with newlines cannot inject Sieve script lines")
    func ruleNameCannotInjectSieveLines() {
        let plan = SieveScriptRenderer.renderBrevOwnedScript(rules: [
            ServerRule(
                id: "evil",
                name: "Innocent\r\nif true { discard; }",
                isEnabled: false,
                conditions: [],
                actions: []
            )
        ])

        // The CR/LF in the name is flattened to spaces, so the injected
        // `discard` stays inside the single `#` comment line — no new executable
        // Sieve statement is emitted.
        #expect(!plan.script.contains("\nif true"))
        #expect(!plan.script.contains("\ndiscard"))
        #expect(plan.script.contains("# Disabled rule: Innocent"))
    }

    @Test("omits unsupported rules and records why they need local fallback")
    func omitsUnsupportedRules() {
        let plan = SieveScriptRenderer.renderBrevOwnedScript(rules: [
            ServerRule(
                id: "local-only",
                name: "Unread attachments",
                isEnabled: true,
                conditions: [.hasAttachment, .isUnread],
                actions: [.archive, .providerAction("native-label")]
            )
        ])

        #expect(plan.script.contains("# Unsupported rule omitted: Unread attachments"))
        #expect(plan.unsupportedRules == [
            SieveUnsupportedRule(
                ruleID: "local-only",
                reasons: [
                    "Attachment tests require provider-specific Sieve extensions.",
                    "Unread state is not available to portable delivery-time Sieve.",
                    "Archive needs a provider-specific destination folder.",
                    "Provider-specific actions cannot be rendered to portable Sieve."
                ]
            )
        ])
    }
}
