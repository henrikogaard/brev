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

@Suite("LocalRulesEngine")
struct LocalRulesEngineTests {
    @Test("evaluation order is deterministic across messages and rules")
    func evaluationOrderIsDeterministic() {
        let newer = Self.makeHeader(
            id: "m-new",
            date: Date(timeIntervalSince1970: 20),
            isRead: false
        )
        let older = Self.makeHeader(
            id: "m-old",
            date: Date(timeIntervalSince1970: 10),
            isRead: false
        )
        let rules: [ServerRule] = [
            ServerRule(
                id: "rule-mark-read",
                name: "Mark boss mail read",
                isEnabled: true,
                conditions: [.senderContains("boss@example.com")],
                actions: [.markRead]
            ),
            ServerRule(
                id: "rule-flag-unread",
                name: "Flag unread",
                isEnabled: true,
                conditions: [.isUnread],
                actions: [.flag]
            )
        ]

        let result = LocalRulesEngine.execute(rules: rules, on: [older, newer])

        #expect(result.appliedActions.count == 2)
        #expect(result.appliedActions[0].ruleID == "rule-mark-read")
        #expect(result.appliedActions[0].messageID == "m-new")
        #expect(result.appliedActions[0].action == .markRead)
        #expect(result.appliedActions[1].ruleID == "rule-mark-read")
        #expect(result.appliedActions[1].messageID == "m-old")
        #expect(result.appliedActions[1].action == .markRead)
        #expect(result.headers.map(\.id) == ["m-new", "m-old"])
        #expect(result.headers.allSatisfy { $0.isRead })
        #expect(result.headers.allSatisfy { !$0.isFlagged })
    }

    // Regression: a buggy/hostile server can return two messages with the same
    // UID, so the input can carry two headers with the same id. The engine built
    // a state map with Dictionary(uniqueKeysWithValues:), which TRAPPED on the
    // duplicate. It must tolerate duplicate ids instead of crashing.
    @Test("duplicate-id headers do not crash the engine")
    func duplicateIDHeadersDoNotCrash() {
        let first = Self.makeHeader(id: "inbox:42", isRead: false)
        let duplicate = Self.makeHeader(id: "inbox:42", isRead: false)
        let rules: [ServerRule] = [
            ServerRule(
                id: "rule-mark-read",
                name: "Mark boss mail read",
                isEnabled: true,
                conditions: [.senderContains("boss@example.com")],
                actions: [.markRead]
            )
        ]

        let result = LocalRulesEngine.execute(rules: rules, on: [first, duplicate])

        // No crash, and the deduplicated message is processed.
        #expect(result.headers.contains { $0.id == "inbox:42" })
    }

    @Test("automatic mode skips destructive actions but continues non-destructive actions")
    func automaticModeSkipsDestructiveActions() {
        let header = Self.makeHeader(id: "m-1", isRead: false)
        let rules: [ServerRule] = [
            ServerRule(
                id: "rule-destructive",
                name: "Destructive",
                isEnabled: true,
                conditions: [.subjectContains("invoice")],
                actions: [.delete, .markRead]
            )
        ]

        let result = LocalRulesEngine.execute(
            rules: rules,
            on: [header],
            context: LocalRulesExecutionContext(
                capabilities: [],
                destructiveActionPolicy: .requireExplicitApproval
            )
        )

        #expect(result.skippedActions.count == 1)
        #expect(result.skippedActions[0].action == .delete)
        #expect(result.skippedActions[0].reason == .requiresExplicitDestructiveApproval)
        #expect(result.appliedActions.map(\.action) == [.markRead])
        #expect(result.headers.count == 1)
        #expect(result.headers[0].isRead)
    }

    @Test("manual safe mode converts delete to recoverable move and halts message execution")
    func manualSafeModeConvertsDeleteToRecoverableMove() {
        let header = Self.makeHeader(id: "m-1", isRead: false, folderID: "inbox")
        let rules: [ServerRule] = [
            ServerRule(
                id: "rule-delete",
                name: "Delete",
                isEnabled: true,
                conditions: [.subjectContains("invoice")],
                actions: [.delete, .markRead]
            )
        ]

        let result = LocalRulesEngine.execute(
            rules: rules,
            on: [header],
            context: LocalRulesExecutionContext(
                capabilities: [],
                destructiveActionPolicy: .recoverDelete(toFolderID: "trash")
            )
        )

        #expect(result.appliedActions.count == 1)
        #expect(result.appliedActions[0].action == .moveToFolder(id: "trash"))
        #expect(result.appliedActions[0].originalAction == .delete)
        #expect(result.headers.count == 1)
        #expect(result.headers[0].folderID == "trash")
        #expect(result.headers[0].isRead == false)
    }

    @Test("provider-only actions are capability-gated")
    func providerOnlyActionsAreCapabilityGated() {
        let header = Self.makeHeader(id: "m-1")
        let rules = [
            ServerRule(
                id: "rule-provider-action",
                name: "Provider action",
                isEnabled: true,
                conditions: [.subjectContains("invoice")],
                actions: [.providerAction("label:add:vip")]
            )
        ]

        let withoutCapability = LocalRulesEngine.execute(
            rules: rules,
            on: [header],
            context: LocalRulesExecutionContext(capabilities: [])
        )
        #expect(withoutCapability.appliedActions.isEmpty)
        #expect(withoutCapability.skippedActions.count == 1)
        #expect(withoutCapability.skippedActions[0].reason == .missingCapability(.providerAPI))

        let withCapability = LocalRulesEngine.execute(
            rules: rules,
            on: [header],
            context: LocalRulesExecutionContext(capabilities: [.providerAPI])
        )
        #expect(withCapability.skippedActions.isEmpty)
        #expect(withCapability.appliedActions.map(\.action) == [.providerAction("label:add:vip")])
    }

    private static func makeHeader(
        id: String,
        date: Date = Date(timeIntervalSince1970: 0),
        isRead: Bool = false,
        folderID: String = "inbox"
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "t-\(id)",
            folderID: folderID,
            from: Correspondent(name: "Boss", email: "boss@example.com"),
            to: [Correspondent(email: "me@example.com")],
            subject: "Invoice reminder",
            snippet: "Please file this invoice.",
            date: date,
            isRead: isRead,
            isFlagged: false,
            hasAttachments: false
        )
    }
}
