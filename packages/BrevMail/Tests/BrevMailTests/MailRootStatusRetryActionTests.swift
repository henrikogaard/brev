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

@testable import BrevMail
import Testing

@Suite("MailRootStatusRetryAction")
struct MailRootStatusRetryActionTests {
    @Test("mailbox switch retry takes priority over mailbox load retry")
    func mailboxSwitchRetryTakesPriority() {
        #expect(MailRootStatusRetryAction.next(
            mailboxSwitchRetryID: "mailbox-2",
            shouldRetryMailboxLoad: true,
            shouldRetryFolderLoad: true,
            isUnifiedInbox: true
        ) == .switchMailbox("mailbox-2"))
    }

    @Test("mailbox load errors retry mailbox metadata")
    func mailboxLoadErrorsRetryMailboxMetadata() {
        #expect(MailRootStatusRetryAction.next(
            mailboxSwitchRetryID: nil,
            shouldRetryMailboxLoad: true,
            shouldRetryFolderLoad: true,
            isUnifiedInbox: true
        ) == .loadMailboxes)
    }

    @Test("folder load errors retry folder metadata")
    func folderLoadErrorsRetryFolderMetadata() {
        #expect(MailRootStatusRetryAction.next(
            mailboxSwitchRetryID: nil,
            shouldRetryMailboxLoad: false,
            shouldRetryFolderLoad: true,
            isUnifiedInbox: true
        ) == .loadFolders)
    }

    @Test("other root errors retry selected folder refresh")
    func otherRootErrorsRetrySelectedFolderRefresh() {
        #expect(MailRootStatusRetryAction.next(
            mailboxSwitchRetryID: nil,
            shouldRetryMailboxLoad: false,
            shouldRetryFolderLoad: false,
            isUnifiedInbox: false
        ) == .refreshSelectedFolder)
    }

    @Test("Unified Inbox refresh errors retry the visible multi-source target")
    func unifiedInboxErrorsRetryVisibleMail() {
        #expect(MailRootStatusRetryAction.next(
            mailboxSwitchRetryID: nil,
            shouldRetryMailboxLoad: false,
            shouldRetryFolderLoad: false,
            isUnifiedInbox: true
        ) == .refreshVisibleMail)
    }
}
