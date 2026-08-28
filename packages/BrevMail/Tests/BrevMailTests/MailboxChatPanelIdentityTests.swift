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
import Testing

@Suite("Mailbox chat panel identity")
struct MailboxChatPanelIdentityTests {
    @Test("controller configuration identity changes when planner context changes")
    func controllerConfigurationIdentityChangesWhenPlannerContextChanges() {
        let sourceID = MailSourceID(accountID: "account-1", mailboxID: "mailbox-1")
        let baseFolders = [Folder(id: "inbox", name: "Inbox", role: .inbox)]
        let archiveFolders = [Folder(id: "archive", name: "Archive", role: .archive)]
        let baseScope = MailboxActionAgentSourceScope(
            sourceID: sourceID,
            accountName: "Work",
            mailboxName: "Primary",
            mailboxAddress: "me@example.com"
        )
        let alternateScope = MailboxActionAgentSourceScope(
            sourceID: sourceID,
            accountName: "Work",
            mailboxName: "Receipts",
            mailboxAddress: "me@example.com"
        )

        let baseline = MailboxChatPanel.controllerConfigurationID(
            selectedChipKind: .sender,
            scopeTitle: "ada@example.com",
            sourceID: sourceID,
            aiBackendIdentifier: "test-ai",
            actionFolders: baseFolders,
            focusedFolder: nil,
            actionSourceScope: baseScope
        )

        let folderIdentity = MailboxChatPanel.controllerConfigurationID(
            selectedChipKind: .sender,
            scopeTitle: "ada@example.com",
            sourceID: sourceID,
            aiBackendIdentifier: "test-ai",
            actionFolders: archiveFolders,
            focusedFolder: nil,
            actionSourceScope: baseScope
        )
        let focusedFolderIdentity = MailboxChatPanel.controllerConfigurationID(
            selectedChipKind: .sender,
            scopeTitle: "ada@example.com",
            sourceID: sourceID,
            aiBackendIdentifier: "test-ai",
            actionFolders: baseFolders,
            focusedFolder: Folder(id: "archive", name: "Archive", role: .archive),
            actionSourceScope: baseScope
        )
        let sourceScopeIdentity = MailboxChatPanel.controllerConfigurationID(
            selectedChipKind: .sender,
            scopeTitle: "ada@example.com",
            sourceID: sourceID,
            aiBackendIdentifier: "test-ai",
            actionFolders: baseFolders,
            focusedFolder: nil,
            actionSourceScope: alternateScope
        )

        #expect(folderIdentity != baseline)
        #expect(focusedFolderIdentity != baseline)
        #expect(sourceScopeIdentity != baseline)

        let folderChipIdentity = MailboxChatPanel.controllerConfigurationID(
            selectedChipKind: .folder,
            scopeTitle: "Inbox",
            sourceID: sourceID,
            aiBackendIdentifier: "test-ai",
            actionFolders: baseFolders,
            focusedFolder: Folder(id: "inbox", name: "Inbox", role: .inbox),
            actionSourceScope: baseScope
        )
        #expect(folderChipIdentity != baseline)
    }
}
