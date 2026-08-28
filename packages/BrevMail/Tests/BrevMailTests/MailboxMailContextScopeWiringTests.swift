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

@Suite("Mailbox mail context scope wiring")
struct MailboxMailContextScopeWiringTests {
    private let sourceID = MailSourceID(accountID: "account-1", mailboxID: "mailbox-1")
    private let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)

    @Test("root inspector wiring enables account chip when mailbox source is selected")
    func rootInspectorWiringEnablesAccountChipWhenMailboxSourceIsSelected() {
        let sections = [Self.workSection(sourceID: sourceID)]
        let actionSourceScope = MailboxMailContextScopeWiring.actionSourceScope(
            sourceID: sourceID,
            sourceSections: sections
        )
        let context = MailboxMailContextScopeWiring.chatScopeContext(
            mailboxChatScope: .account,
            sourceID: sourceID,
            focusedFolder: inbox,
            actionSourceScope: actionSourceScope
        )
        let chips = MailboxChatScopeChipPolicy.chips(context: context, selected: .account)

        #expect(actionSourceScope.sourceID == sourceID)
        #expect(actionSourceScope.accountName == "Work")
        #expect(context.isChipEnabled(.account))
        #expect(chips[2].isEnabled)
        #expect(chips[2].title == "All folders")
        #expect(chips[2].isSelected)
    }

    @Test("root inspector wiring keeps account chip disabled without selected source")
    func rootInspectorWiringKeepsAccountChipDisabledWithoutSelectedSource() {
        let sections = [Self.workSection(sourceID: sourceID)]
        let actionSourceScope = MailboxMailContextScopeWiring.actionSourceScope(
            sourceID: nil,
            sourceSections: sections
        )
        let context = MailboxMailContextScopeWiring.chatScopeContext(
            mailboxChatScope: .account,
            sourceID: nil,
            focusedFolder: inbox,
            actionSourceScope: actionSourceScope
        )
        let chips = MailboxChatScopeChipPolicy.chips(context: context, selected: .folder)

        #expect(!context.isChipEnabled(.account))
        #expect(!chips[2].isEnabled)
        #expect(chips[1].isEnabled)
    }

    @Test("display label alone does not enable account chip without source id")
    func displayLabelAloneDoesNotEnableAccountChipWithoutSourceID() {
        let labelOnlyScope = MailboxActionAgentSourceScope(
            sourceID: nil,
            accountName: "Work",
            mailboxName: "Primary",
            mailboxAddress: "me@example.com"
        )
        let context = MailboxMailContextScopeWiring.chatScopeContext(
            mailboxChatScope: .account,
            sourceID: nil,
            focusedFolder: nil,
            actionSourceScope: labelOnlyScope
        )

        #expect(!context.isChipEnabled(.account))
        #expect(context.scope(for: .account) == nil)
    }

    @Test("account chip stays enabled when section metadata is missing but source id is set")
    func accountChipStaysEnabledWhenSectionMetadataIsMissingButSourceIDIsSet() {
        let actionSourceScope = MailboxMailContextScopeWiring.actionSourceScope(
            sourceID: sourceID,
            sourceSections: []
        )
        let context = MailboxMailContextScopeWiring.chatScopeContext(
            mailboxChatScope: .account,
            sourceID: sourceID,
            focusedFolder: nil,
            actionSourceScope: actionSourceScope
        )
        let chips = MailboxChatScopeChipPolicy.chips(context: context, selected: .account)

        #expect(context.isChipEnabled(.account))
        #expect(chips[2].isEnabled)
        #expect(chips[2].title == "All folders")
    }

    @Test("sender selection still defaults account chip off when sender context is available")
    func senderSelectionStillDefaultsAccountChipOffWhenSenderContextIsAvailable() {
        let sections = [Self.workSection(sourceID: sourceID)]
        let actionSourceScope = MailboxMailContextScopeWiring.actionSourceScope(
            sourceID: sourceID,
            sourceSections: sections
        )
        let context = MailboxMailContextScopeWiring.chatScopeContext(
            mailboxChatScope: .sender(email: "ada@example.com"),
            sourceID: sourceID,
            focusedFolder: inbox,
            actionSourceScope: actionSourceScope
        )

        #expect(context.defaultChipKind == .sender)
        #expect(context.isChipEnabled(.account))
    }

    private static func workSection(sourceID: MailSourceID) -> MailSourceSection {
        MailSourceSection(
            id: sourceID,
            account: BrevAccount(
                id: sourceID.accountID,
                displayName: "Work",
                emailAddress: "me@example.com"
            ),
            mailbox: Mailbox(
                id: sourceID.mailboxID,
                email: "me@example.com",
                displayName: "Primary"
            ),
            folders: [Folder(id: "inbox", name: "Inbox", role: .inbox)]
        )
    }
}
