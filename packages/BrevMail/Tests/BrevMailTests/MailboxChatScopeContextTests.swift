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

@Suite("Mailbox chat scope context")
struct MailboxChatScopeContextTests {
    private let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
    private let sourceID = MailSourceID(accountID: "account-1", mailboxID: "mailbox-1")

    @Test("context defaults to sender when available")
    func contextDefaultsToSenderWhenAvailable() {
        let context = MailboxChatScopeContext(
            senderEmail: "ada@example.com",
            folder: inbox,
            accountLabel: "Work",
            sourceID: sourceID
        )

        #expect(context.defaultChipKind == .sender)
        #expect(context.isChipEnabled(.sender))
        #expect(context.isChipEnabled(.folder))
        #expect(context.isChipEnabled(.account))
        #expect(context.scope(for: .folder) == .folder)
        #expect(context.scope(for: .account) == .account)
        #expect(context.chipTitle(for: .account) == "All folders")
        #expect(context.chipAccessibilityLabel(for: .account) == "All folders in Work")
    }

    @Test("account chip requires source id not display label alone")
    func accountChipRequiresSourceIDNotDisplayLabelAlone() {
        let labelOnly = MailboxChatScopeContext(
            senderEmail: nil,
            folder: nil,
            accountLabel: "Work",
            sourceID: nil
        )
        #expect(!labelOnly.isChipEnabled(.account))
        #expect(labelOnly.scope(for: .account) == nil)

        let sourceOnly = MailboxChatScopeContext(
            senderEmail: nil,
            folder: nil,
            accountLabel: nil,
            sourceID: sourceID
        )
        #expect(sourceOnly.isChipEnabled(.account))
        #expect(sourceOnly.defaultChipKind == .account)
    }

    @Test("search policy builds cache-only queries per scope")
    func searchPolicyBuildsCacheOnlyQueriesPerScope() {
        #expect(
            MailboxChatScopeSearchPolicy.answerSearchQuery(
                question: "Any invoices?",
                scope: .sender(email: "ada@example.com"),
                folderID: nil
            ) == SearchQuery(text: "Any invoices?", from: "ada@example.com", execution: .cacheOnly)
        )
        #expect(
            MailboxChatScopeSearchPolicy.answerSearchQuery(
                question: "Any invoices?",
                scope: .folder,
                folderID: "inbox"
            ) == SearchQuery(text: "Any invoices?", folderID: "inbox", execution: .cacheOnly)
        )
        #expect(
            MailboxChatScopeSearchPolicy.answerSearchQuery(
                question: "Any invoices?",
                scope: .account,
                folderID: nil
            ) == SearchQuery(text: "Any invoices?", execution: .cacheOnly)
        )
    }

    @Test("chip policy marks the selected chip")
    func chipPolicyMarksSelectedChip() {
        let context = MailboxChatScopeContext(
            senderEmail: "ada@example.com",
            folder: inbox,
            accountLabel: "Work",
            sourceID: sourceID
        )

        let chips = MailboxChatScopeChipPolicy.chips(context: context, selected: .folder)

        #expect(chips[1].isSelected)
        #expect(!chips[0].isSelected)
        #expect(chips[1].title == "Inbox")
    }

    @Test("sender chip carries the local part and keeps the address for VoiceOver")
    func senderChipCarriesLocalPartAndKeepsAddressForVoiceOver() {
        let context = MailboxChatScopeContext(
            senderEmail: "ada@example.com",
            folder: nil,
            accountLabel: nil,
            sourceID: nil
        )

        let chips = MailboxChatScopeChipPolicy.chips(context: context, selected: .sender)

        #expect(chips[0].title == "ada")
        #expect(chips[0].accessibilityLabel == "ada@example.com")
    }

    @Test("every disabled chip explains what unlocks it")
    func everyDisabledChipExplainsWhatUnlocksIt() {
        let context = MailboxChatScopeContext(
            senderEmail: nil,
            folder: nil,
            accountLabel: nil,
            sourceID: nil
        )

        for kind in [MailboxChatScopeChipKind.sender, .folder, .account] {
            #expect(!context.isChipEnabled(kind))
            #expect(!context.chipDisabledHelp(for: kind).isEmpty)
        }
    }
}
