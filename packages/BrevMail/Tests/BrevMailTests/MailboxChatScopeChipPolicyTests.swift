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

@Suite("Mailbox chat scope chips")
struct MailboxChatScopeChipPolicyTests {
    private let sourceID = MailSourceID(accountID: "account-1", mailboxID: "mailbox-1")

    @Test("sender scope enables all chips when context is available")
    func senderScopeEnablesAllChipsWhenContextIsAvailable() {
        let context = MailboxChatScopeContext(
            senderEmail: "ada@example.com",
            folder: Folder(id: "inbox", name: "Inbox", role: .inbox),
            accountLabel: "Work",
            sourceID: sourceID
        )
        let chips = MailboxChatScopeChipPolicy.chips(context: context, selected: .sender)

        #expect(chips.map(\.kind) == [.sender, .folder, .account])
        #expect(chips[0].title == "ada@example.com")
        #expect(chips[0].isEnabled)
        #expect(chips[0].isSelected)
        #expect(chips[1].isEnabled)
        #expect(chips[2].isEnabled)
        #expect(chips[2].title == "All folders")
        #expect(chips[2].accessibilityLabel == "All folders in Work")
    }

    @Test("context without sender enables only folder or account chips")
    func contextWithoutSenderEnablesOnlyFolderOrAccountChips() {
        let folderOnly = MailboxChatScopeContext(
            senderEmail: nil,
            folder: Folder(id: "inbox", name: "Inbox", role: .inbox),
            accountLabel: nil,
            sourceID: nil
        )
        let folderChips = MailboxChatScopeChipPolicy.chips(context: folderOnly, selected: .folder)
        #expect(folderChips[0].isEnabled == false)
        #expect(folderChips[1].isEnabled)
        #expect(folderChips[2].isEnabled == false)

        let accountOnly = MailboxChatScopeContext(
            senderEmail: nil,
            folder: nil,
            accountLabel: "Work",
            sourceID: sourceID
        )
        let accountChips = MailboxChatScopeChipPolicy.chips(context: accountOnly, selected: .account)
        #expect(accountChips[0].isEnabled == false)
        #expect(accountChips[1].isEnabled == false)
        #expect(accountChips[2].isEnabled)
        #expect(accountChips[2].title == "All folders")
        #expect(accountChips[2].accessibilityLabel == "All folders in Work")
    }
}
