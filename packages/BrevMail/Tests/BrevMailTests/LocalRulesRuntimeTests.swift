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

import BrevBackend
@testable import BrevMail
import Foundation
import Testing

@Suite("LocalRulesRuntime")
struct LocalRulesRuntimeTests {
    @Test("automatic execution skips destructive actions")
    func automaticExecutionSkipsDestructiveActions() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let trash = Folder(id: "trash", name: "Trash", role: .trash)
        let header = Self.header(
            id: "m-1",
            folderID: inbox.id,
            isRead: false,
            isFlagged: false,
            date: Date(timeIntervalSince1970: 1_718_000_100)
        )
        let rule = ServerRule(
            id: "rule-1",
            name: "Delete unread",
            isEnabled: true,
            conditions: [.isUnread],
            actions: [.delete]
        )

        let plan = LocalRulesRuntime.plan(
            rules: [rule],
            headers: [header],
            folders: [inbox, trash],
            capabilities: [],
            archiveFolderID: nil,
            trashFolderID: trash.id,
            mode: .automatic
        )

        #expect(plan.deleteIDs.isEmpty)
        #expect(plan.executionResult.skippedActions.count == 1)
    }

    @Test("manual safe execution converts delete into recoverable move")
    func manualSafeExecutionConvertsDeleteIntoRecoverableMove() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let trash = Folder(id: "trash", name: "Trash", role: .trash)
        let header = Self.header(
            id: "m-1",
            folderID: inbox.id,
            isRead: false,
            isFlagged: false,
            date: Date(timeIntervalSince1970: 1_718_000_100)
        )
        let rule = ServerRule(
            id: "rule-1",
            name: "Delete unread",
            isEnabled: true,
            conditions: [.isUnread],
            actions: [.delete]
        )

        let plan = LocalRulesRuntime.plan(
            rules: [rule],
            headers: [header],
            folders: [inbox, trash],
            capabilities: [],
            archiveFolderID: nil,
            trashFolderID: trash.id,
            mode: .manualSafe
        )

        #expect(plan.deleteIDs.isEmpty)
        #expect(plan.moveBatches.count == 1)
        #expect(plan.moveBatches[0].folder.id == trash.id)
        #expect(plan.moveBatches[0].messageIDs == [header.id])
    }

    @Test("plan drops no-op actions and keeps deterministic order")
    func planDropsNoopActionsAndKeepsDeterministicOrder() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let older = Self.header(
            id: "m-1",
            folderID: inbox.id,
            isRead: true,
            isFlagged: false,
            date: Date(timeIntervalSince1970: 1_718_000_000)
        )
        let newer = Self.header(
            id: "m-2",
            folderID: inbox.id,
            isRead: false,
            isFlagged: false,
            date: Date(timeIntervalSince1970: 1_718_000_100)
        )
        let rules = [
            ServerRule(
                id: "rule-mark-read",
                name: "Mark unread read",
                isEnabled: true,
                conditions: [.isUnread],
                actions: [.markRead]
            ),
            ServerRule(
                id: "rule-archive",
                name: "Archive invoices",
                isEnabled: true,
                conditions: [.subjectContains("invoice")],
                actions: [.archive]
            )
        ]

        let plan = LocalRulesRuntime.plan(
            rules: rules,
            headers: [older, newer],
            folders: [inbox, archive],
            capabilities: [],
            archiveFolderID: archive.id,
            trashFolderID: nil,
            mode: .automatic
        )

        // `m-1` is already read and should not be included as a no-op.
        #expect(plan.readIDs == [newer.id])
        #expect(plan.moveBatches.count == 1)
        #expect(plan.moveBatches[0].messageIDs == [newer.id, older.id])
    }

    private static func header(
        id: String,
        folderID: Folder.ID,
        isRead: Bool,
        isFlagged: Bool,
        date: Date
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: folderID,
            from: Correspondent(name: "Alex", email: "alex@example.com"),
            to: [Correspondent(name: "Henrik", email: "henrik@example.com")],
            subject: "invoice \(id)",
            snippet: "snippet",
            date: date,
            isRead: isRead,
            isFlagged: isFlagged
        )
    }
}
