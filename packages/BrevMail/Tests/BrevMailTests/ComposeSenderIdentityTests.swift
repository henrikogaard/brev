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

    @Test("reply defaults From to the matched addressed mailbox instead of primary")
    func replyMatchesAddressedMailboxOverPrimary() {
        let account = Self.account(
            id: "preview-account",
            email: "henrik@ogard.example",
            name: "Henrik Øgård"
        )
        let privateSection = Self.section(
            account: account,
            mailboxID: "preview-account",
            email: "henrik@ogard.example",
            displayName: "Henrik Øgård (private)"
        )
        let workSection = Self.section(
            account: account,
            mailboxID: "preview-account-work",
            email: "henrik.work@ogard.example",
            displayName: "Henrik Øgård (work)"
        )
        let messageAddressedToWork = MessageHeader(
            id: "msg-work-1",
            threadID: "thread-work-1",
            folderID: "inbox",
            from: Correspondent(name: "Sigrid Solberg", email: "sigrid@harbour.example"),
            to: [Correspondent(name: "Henrik Øgård (work)", email: "HENRIK.WORK@ogard.example")],
            subject: "Stavanger terminal rollout",
            snippet: "Can you confirm the berth schedule?",
            date: Date(timeIntervalSince1970: 1_780_000_000)
        )

        let resolvedSourceID = ComposeSenderIdentity.replySourceID(
            for: messageAddressedToWork,
            in: [privateSection, workSection],
            selectedSourceID: nil,
            defaultSourceID: privateSection.id
        )
        #expect(resolvedSourceID == workSection.id)

        let resolution = ComposeSenderIdentity.resolution(
            from: [privateSection, workSection],
            fallbackAccount: account,
            selectedSourceID: privateSection.id,
            defaultSourceID: privateSection.id,
            replyingTo: messageAddressedToWork
        )
        #expect(resolution.sourceID == workSection.id)
        #expect(resolution.initialSender?.correspondent == Correspondent(
            name: "Henrik Øgård (work)",
            email: "henrik.work@ogard.example"
        ))
    }

    @Test("reply matches Cc recipient when To has no own identity and falls back when none match")
    func replyMatchesCcOrFallsBackToDefault() {
        let personalAccount = Self.account(
            id: "personal-acct",
            email: "henrik@personal.example",
            name: "Henrik"
        )
        let workAccount = Self.account(
            id: "work-acct",
            email: "henrik@work.example",
            name: "Henrik (work)"
        )
        let personal = Self.section(
            account: personalAccount,
            mailboxID: "personal-acct",
            email: "henrik@personal.example",
            displayName: "Henrik"
        )
        let work = Self.section(
            account: workAccount,
            mailboxID: "work-acct",
            email: "henrik@work.example",
            displayName: "Henrik (work)"
        )
        let ccWorkMessage = MessageHeader(
            id: "msg-cc-1",
            threadID: "thread-cc-1",
            folderID: "inbox",
            from: Correspondent(name: "Ada", email: "ada@partner.example"),
            to: [Correspondent(name: "Team", email: "team@partner.example")],
            cc: [Correspondent(name: "Henrik (work)", email: "henrik@work.example")],
            subject: "Partner sync",
            snippet: "Copying you for visibility.",
            date: Date(timeIntervalSince1970: 1_780_000_100)
        )
        let unmatchedMessage = MessageHeader(
            id: "msg-list-1",
            threadID: "thread-list-1",
            folderID: "inbox",
            from: Correspondent(name: "Digest", email: "digest@list.example"),
            to: [Correspondent(name: "Subscribers", email: "list@list.example")],
            subject: "Weekly digest",
            snippet: "Summary",
            date: Date(timeIntervalSince1970: 1_780_000_200)
        )

        #expect(ComposeSenderIdentity.replySourceID(
            for: ccWorkMessage,
            in: [personal, work],
            selectedSourceID: nil,
            defaultSourceID: personal.id
        ) == work.id)
        #expect(ComposeSenderIdentity.replySourceID(
            for: unmatchedMessage,
            in: [personal, work],
            selectedSourceID: nil,
            defaultSourceID: personal.id
        ) == personal.id)
    }

    @Test("cross-account reply switches sending identity to B while fetching quoted body from A")
    @MainActor
    func crossAccountReplyFetchesQuotedBodyFromOriginalAccountBackend() async {
        let personalAccount = Self.account(
            id: "personal-acct",
            email: "henrik@personal.example",
            name: "Henrik (personal)"
        )
        let workAccount = Self.account(
            id: "work-acct",
            email: "henrik@work.example",
            name: "Henrik (work)"
        )
        let personal = Self.section(
            account: personalAccount,
            mailboxID: "personal-acct",
            email: "henrik@personal.example",
            displayName: "Henrik (personal)"
        )
        let work = Self.section(
            account: workAccount,
            mailboxID: "work-acct",
            email: "henrik@work.example",
            displayName: "Henrik (work)"
        )
        // Colliding folder+UID message ID that exists in both accounts.
        let collidingID = "INBOX:42"
        let originalHeaderInPersonal = MessageHeader(
            id: collidingID,
            threadID: "thread-42",
            folderID: "INBOX",
            from: Correspondent(name: "Sigrid", email: "sigrid@partner.example"),
            to: [Correspondent(name: "Henrik (work)", email: "henrik@work.example")],
            subject: "Forwarded contract",
            snippet: "Short snippet",
            date: Date(timeIntervalSince1970: 1_780_000_500)
        )

        let matchedReplySourceID = ComposeSenderIdentity.replySourceID(
            for: originalHeaderInPersonal,
            in: [personal, work],
            selectedSourceID: personal.id,
            defaultSourceID: personal.id
        )
        #expect(matchedReplySourceID == work.id)

        let personalBackend = QuoteRecordingMailBackend(
            account: personalAccount,
            bodies: [collidingID: MessageBody(messageID: collidingID, plainText: "Original body from account A.")]
        )
        let workBackend = QuoteRecordingMailBackend(
            account: workAccount,
            bodies: [collidingID: MessageBody(messageID: collidingID, plainText: "UNRELATED secret body in account B!")]
        )

        let senderResolution = ComposeSenderIdentity.resolution(
            from: [work],
            fallbackAccount: workAccount,
            selectedSourceID: work.id,
            defaultSourceID: work.id,
            replyingTo: originalHeaderInPersonal
        )
        let composeView = ComposeView(
            backend: workBackend,
            sourceID: senderResolution.sourceID,
            quotedMessageBackend: personalBackend,
            quotedMessageSourceID: personal.id,
            from: senderResolution.initialSender?.correspondent
                ?? Correspondent(name: workAccount.displayName, email: workAccount.emailAddress),
            senderOptions: senderResolution.options,
            initialSenderOption: senderResolution.initialSender,
            backendForSenderSource: { sourceID in
                sourceID == personal.id ? personalBackend : workBackend
            },
            replyingTo: originalHeaderInPersonal
        )

        let loadedBody = await composeView.loadQuotedOriginalBody(for: originalHeaderInPersonal)

        #expect(loadedBody?.plainText == "Original body from account A.")
        #expect(personalBackend.bodyLookups.count == 1)
        #expect(personalBackend.bodyLookups.first?.messageID == collidingID)
        #expect(personalBackend.bodyLookups.first?.sourceID == personal.id)
        #expect(workBackend.bodyLookups.isEmpty)
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

private final class QuoteRecordingMailBackend: MailBackend, @unchecked Sendable {
    struct BodyLookup: Equatable {
        let messageID: String
        let sourceID: MailSourceID?
    }

    let account: BrevAccount
    let capabilities: BackendCapabilities = []
    private let bodies: [String: MessageBody]
    private(set) var bodyLookups: [BodyLookup] = []

    init(account: BrevAccount, bodies: [String: MessageBody]) {
        self.account = account
        self.bodies = bodies
    }

    func connect() async throws {}
    func disconnect() async {}
    func folders() async throws -> [Folder] { [] }
    func refresh(folder _: Folder) async throws {}
    func messages(in _: Folder, pageToken _: String?) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        ([], nil)
    }

    func body(for messageID: String) async throws -> MessageBody {
        bodyLookups.append(BodyLookup(messageID: messageID, sourceID: nil))
        guard let body = bodies[messageID] else { throw MailBackendError.notFound(id: messageID) }
        return body
    }

    func body(for messageID: String, sourceID: MailSourceID) async throws -> MessageBody {
        bodyLookups.append(BodyLookup(messageID: messageID, sourceID: sourceID))
        guard let body = bodies[messageID] else { throw MailBackendError.notFound(id: messageID) }
        return body
    }

    func setRead(_: Bool, for _: [String]) async throws {}
    func setFlagged(_: Bool, for _: [String]) async throws {}
    func move(messageIDs _: [String], to _: Folder) async throws {}
    func delete(messageIDs _: [String]) async throws {}
    func save(draft: Draft) async throws -> Draft { draft }
    func discard(draftID _: String) async throws {}
    func send(draft _: Draft) async throws -> SendResult { SendResult(sentMessageID: "sent") }
    func search(_: SearchQuery) async throws -> [MessageHeader] { [] }
    func calendarEvent(from attachmentID: String) async throws -> CalendarEvent {
        CalendarEvent(
            id: attachmentID,
            title: "Event",
            start: Date(),
            end: Date(),
            location: nil,
            organizer: nil,
            attendees: [],
            description: nil
        )
    }

    func replyToCalendarInvite(messageID _: String, response _: AttendeeState) async throws {}
    func subscribeToChanges() -> AsyncStream<MailEvent> { AsyncStream { $0.finish() } }
}
