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

@Suite("Server rules")
struct ServerRuleTests {
    @Test("non-destructive server rules do not require confirmation")
    func nonDestructiveServerRulesDoNotRequireConfirmation() {
        let rule = ServerRule(
            id: "rule-1",
            name: "Receipts",
            isEnabled: true,
            conditions: [.senderContains("receipts@example.org")],
            actions: [.moveToFolder(id: "receipts"), .markRead]
        )

        #expect(rule.requiresDestructiveConfirmation == false)
    }

    @Test("destructive server rules require confirmation")
    func destructiveServerRulesRequireConfirmation() {
        let rule = ServerRule(
            id: "rule-2",
            name: "Drop noisy mail",
            isEnabled: true,
            conditions: [.subjectContains("[noise]")],
            actions: [.delete]
        )

        #expect(rule.requiresDestructiveConfirmation)
    }
}
