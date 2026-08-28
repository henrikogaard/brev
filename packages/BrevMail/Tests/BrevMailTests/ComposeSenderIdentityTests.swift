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

@Suite("ComposeSenderIdentity")
struct ComposeSenderIdentityTests {
    @Test("active mailbox identity wins over account identity")
    func activeMailboxIdentityWinsOverAccountIdentity() {
        let account = BrevAccount(
            id: "account-1",
            displayName: "Henrik",
            emailAddress: "henrik@example.org",
            backendIdentifier: "demo",
            backendDisplayName: "Demo"
        )
        let sender = ComposeSenderIdentity.sender(
            account: account,
            mailboxes: [
                Mailbox(
                    id: "account-1",
                    email: "henrik@example.org",
                    displayName: "Henrik",
                    isPrimary: true
                ),
                Mailbox(
                    id: "account-1-work",
                    email: "henrik+work@example.org",
                    displayName: "Henrik Work"
                )
            ],
            activeMailboxID: "account-1-work"
        )

        #expect(sender == Correspondent(name: "Henrik Work", email: "henrik+work@example.org"))
    }

    @Test("missing active mailbox falls back to account identity")
    func missingActiveMailboxFallsBackToAccountIdentity() {
        let account = BrevAccount(
            id: "account-1",
            displayName: "Henrik",
            emailAddress: "henrik@example.org",
            backendIdentifier: "demo",
            backendDisplayName: "Demo"
        )
        let sender = ComposeSenderIdentity.sender(
            account: account,
            mailboxes: [],
            activeMailboxID: nil
        )

        #expect(sender == Correspondent(name: "Henrik", email: "henrik@example.org"))
    }

    @Test("visible source sections become sender options")
    func visibleSourceSectionsBecomeSenderOptions() {
        let account = Self.account()
        let personal = Self.section(
            account: account,
            mailboxID: "personal",
            email: "henrik@example.org",
            displayName: "Henrik"
        )
        let contact = Self.section(
            account: account,
            mailboxID: "contact",
            email: "contact@example.org",
            displayName: "Contact"
        )

        let options = ComposeSenderIdentity.senderOptions(
            from: [personal, contact],
            fallbackAccount: account
        )

        #expect(options.map(\.sourceID) == [personal.id, contact.id])
        #expect(options.map(\.correspondent) == [
            Correspondent(name: "Henrik", email: "henrik@example.org"),
            Correspondent(name: "Contact", email: "contact@example.org")
        ])
    }

    @Test("selected source wins when choosing initial sender")
    func selectedSourceWinsWhenChoosingInitialSender() {
        let account = Self.account()
        let personal = Self.section(
            account: account,
            mailboxID: "personal",
            email: "henrik@example.org",
            displayName: "Henrik"
        )
        let contact = Self.section(
            account: account,
            mailboxID: "contact",
            email: "contact@example.org",
            displayName: "Contact"
        )
        let options = ComposeSenderIdentity.senderOptions(
            from: [personal, contact],
            fallbackAccount: account
        )

        let sender = ComposeSenderIdentity.preferredSender(
            from: options,
            selectedSourceID: contact.id,
            defaultSourceID: personal.id
        )

        #expect(sender?.sourceID == contact.id)
        #expect(sender?.correspondent == Correspondent(name: "Contact", email: "contact@example.org"))
    }

    @Test("default source is used when no source is selected")
    func defaultSourceIsUsedWhenNoSourceIsSelected() {
        let account = Self.account()
        let personal = Self.section(
            account: account,
            mailboxID: "personal",
            email: "henrik@example.org",
            displayName: "Henrik"
        )
        let contact = Self.section(
            account: account,
            mailboxID: "contact",
            email: "contact@example.org",
            displayName: "Contact"
        )
        let options = ComposeSenderIdentity.senderOptions(
            from: [personal, contact],
            fallbackAccount: account
        )

        let sender = ComposeSenderIdentity.preferredSender(
            from: options,
            selectedSourceID: nil,
            defaultSourceID: contact.id
        )

        #expect(sender?.sourceID == contact.id)
        #expect(sender?.correspondent == Correspondent(name: "Contact", email: "contact@example.org"))
    }

    @Test("sender sections follow default source account when no source is selected")
    func senderSectionsFollowDefaultSourceAccountWhenNoSourceIsSelected() {
        let personalAccount = Self.account(
            id: "personal-account",
            email: "henrik@example.org",
            name: "Henrik"
        )
        let workAccount = Self.account(
            id: "work-account",
            email: "henrik@work.example.org",
            name: "Henrik Work"
        )
        let personal = Self.section(
            account: personalAccount,
            mailboxID: "personal",
            email: "henrik@example.org",
            displayName: "Henrik"
        )
        let work = Self.section(
            account: workAccount,
            mailboxID: "work",
            email: "henrik@work.example.org",
            displayName: "Henrik Work"
        )

        let sections = ComposeSenderIdentity.senderSections(
            from: [personal, work],
            selectedSourceID: nil,
            defaultSourceID: work.id,
            fallbackAccountID: personalAccount.id
        )

        #expect(sections.map(\.id) == [work.id])
    }

    @Test("sender options fall back to account identity when no source sections are available")
    func senderOptionsFallBackToAccountIdentityWhenNoSourceSectionsAreAvailable() {
        let account = Self.account()

        let options = ComposeSenderIdentity.senderOptions(
            from: [],
            fallbackAccount: account
        )

        #expect(options == [
            ComposeSenderOption(
                sourceID: nil,
                accountID: "account-1",
                displayName: "Henrik",
                email: "henrik@example.org",
                subtitle: "Demo"
            )
        ])
    }

    // MARK: resolution

    @Test("resolution selects the selected source and reports it as the effective source id")
    func resolutionPrefersSelectedSource() {
        let account = Self.account()
        let personal = Self.section(
            account: account,
            mailboxID: "personal",
            email: "henrik@example.org",
            displayName: "Henrik"
        )
        let contact = Self.section(
            account: account,
            mailboxID: "contact",
            email: "contact@example.org",
            displayName: "Contact"
        )

        let resolution = ComposeSenderIdentity.resolution(
            from: [personal, contact],
            fallbackAccount: account,
            selectedSourceID: contact.id,
            defaultSourceID: personal.id
        )

        #expect(resolution.options.map(\.sourceID) == [personal.id, contact.id])
        #expect(resolution.initialSender?.sourceID == contact.id)
        #expect(resolution.sourceID == contact.id)
    }

    @Test("resolution falls back to the default source when none is selected")
    func resolutionUsesDefaultSourceWhenNoneSelected() {
        let account = Self.account()
        let personal = Self.section(
            account: account,
            mailboxID: "personal",
            email: "henrik@example.org",
            displayName: "Henrik"
        )
        let contact = Self.section(
            account: account,
            mailboxID: "contact",
            email: "contact@example.org",
            displayName: "Contact"
        )

        let resolution = ComposeSenderIdentity.resolution(
            from: [personal, contact],
            fallbackAccount: account,
            selectedSourceID: nil,
            defaultSourceID: contact.id
        )

        #expect(resolution.initialSender?.sourceID == contact.id)
        #expect(resolution.sourceID == contact.id)
    }

    @Test("resolution falls back to the account identity when there are no sections")
    func resolutionFallsBackToAccountIdentity() {
        let account = Self.account()

        let resolution = ComposeSenderIdentity.resolution(
            from: [],
            fallbackAccount: account,
            selectedSourceID: nil,
            defaultSourceID: nil
        )

        #expect(resolution.options == [
            ComposeSenderOption(
                sourceID: nil,
                accountID: "account-1",
                displayName: "Henrik",
                email: "henrik@example.org",
                subtitle: "Demo"
            )
        ])
        #expect(resolution.initialSender?.sourceID == nil)
        #expect(resolution.sourceID == nil)
    }

    private static func account(
        id: BrevAccount.ID = "account-1",
        email: String = "henrik@example.org",
        name: String = "Henrik"
    ) -> BrevAccount {
        BrevAccount(
            id: id,
            displayName: name,
            emailAddress: email,
            backendIdentifier: "demo",
            backendDisplayName: "Demo"
        )
    }

    private static func section(
        account: BrevAccount,
        mailboxID: Mailbox.ID,
        email: String,
        displayName: String
    ) -> MailSourceSection {
        let sourceID = MailSourceID(accountID: account.id, mailboxID: mailboxID)
        return MailSourceSection(
            id: sourceID,
            account: account,
            mailbox: Mailbox(
                id: mailboxID,
                email: email,
                displayName: displayName,
                isPrimary: mailboxID == account.id
            ),
            folders: []
        )
    }
}
