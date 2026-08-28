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

/// Client-side threading for standards IMAP accounts (ADR-0052).
@Suite("IMAP threading")
struct IMAPThreadingTests {
    @Test("ENVELOPE in-reply-to is parsed from a FETCH line")
    func envelopeInReplyToIsParsed() {
        let listing = IMAPMessageListing.parse(
            #"* 2 FETCH (FLAGS (\Seen) UID 101 ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "Re: Standup" (("Ada" NIL "ada" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL "<root@example.org>" "<reply@example.org>"))"#
        )

        #expect(listing?.inReplyTo == "<root@example.org>")
        #expect(listing?.messageID == "<reply@example.org>")
    }

    @Test("ENVELOPE reply-to is parsed and propagated to message headers")
    func envelopeReplyToIsPropagated() async throws {
        let listing = try #require(IMAPMessageListing.parse(
            #"* 2 FETCH (FLAGS (\Seen) UID 101 ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "Re: Standup" (("List Sender" NIL "bounce" "lists.example.org")) NIL (("Reply Desk" NIL "reply" "example.org")) ((NIL NIL "person" "example.org")) NIL NIL "<root@example.org>" "<reply@example.org>"))"#
        ))

        #expect(listing.replyTo == [Correspondent(name: "Reply Desk", email: "reply@example.org")])

        let backend = Self.backend(messages: [listing])
        try await backend.connect()
        let page = try await backend.messages(in: Self.inbox, pageToken: nil)

        #expect(page.headers.first?.replyTo == [
            Correspondent(name: "Reply Desk", email: "reply@example.org"),
        ])
    }

    @Test("a message with no in-reply-to parses as unlinked")
    func envelopeWithoutInReplyTo() {
        let listing = IMAPMessageListing.parse(
            #"* 1 FETCH (FLAGS () UID 100 ENVELOPE ("Sat, 06 Jun 2026 11:00:00 +0000" "Standup" (("Ada" NIL "ada" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<root@example.org>"))"#
        )

        #expect(listing?.inReplyTo == nil)
        #expect(listing?.messageID == "<root@example.org>")
    }

    @Test("a listed reply shares its parent's thread id")
    func listedReplySharesParentThreadID() async throws {
        let backend = Self.backend(messages: [
            Self.listing(uid: 2, messageID: "<reply@example.org>", inReplyTo: "<root@example.org>", minutes: 10),
            Self.listing(uid: 1, messageID: "<root@example.org>", minutes: 0)
        ])
        try await backend.connect()

        let page = try await backend.messages(in: Self.inbox, pageToken: nil)

        #expect(page.headers.count == 2)
        #expect(Set(page.headers.map(\.threadID)) == ["<root@example.org>"])
    }

    @Test("unrelated listed messages keep their own thread ids")
    func unrelatedListedMessagesStaySeparate() async throws {
        let backend = Self.backend(messages: [
            Self.listing(uid: 2, messageID: "<b@example.org>", minutes: 10),
            Self.listing(uid: 1, messageID: "<a@example.org>", minutes: 0)
        ])
        try await backend.connect()

        let page = try await backend.messages(in: Self.inbox, pageToken: nil)

        #expect(Set(page.headers.map(\.threadID)) == ["<a@example.org>", "<b@example.org>"])
    }

    @Test("a listed reply still reports its own Message-ID for outgoing replies")
    func listedReplyKeepsItsOwnMessageID() async throws {
        let backend = Self.backend(messages: [
            Self.listing(uid: 2, messageID: "<reply@example.org>", inReplyTo: "<root@example.org>", minutes: 10),
            Self.listing(uid: 1, messageID: "<root@example.org>", minutes: 0)
        ])
        try await backend.connect()

        let page = try await backend.messages(in: Self.inbox, pageToken: nil)
        let reply = try #require(page.headers.first { $0.id.hasSuffix(":2") })

        #expect(reply.rfcMessageID == "<reply@example.org>")
    }

    @Test("the IMAP backend advertises client-side threading")
    func backendAdvertisesClientSideThreading() {
        let backend = Self.backend(messages: [])

        #expect(backend.extendedCapabilities.contains(.clientSideThreading))
        #expect(backend.groupsMessagesIntoThreads)
    }

    // MARK: - Fixtures

    private static let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

    private static let account = BrevAccount(
        id: "imap-smtp:person@example.org",
        displayName: "Person",
        emailAddress: "person@example.org"
    )

    private static let configuration = IMAPAccountConfiguration(
        accountID: "imap-smtp:person@example.org",
        emailAddress: "person@example.org",
        displayName: "Person",
        incoming: MailServerSettings(
            kind: .imap,
            host: "imap.example.org",
            port: 993,
            tlsMode: .implicit,
            authentication: .password
        ),
        outgoing: MailServerSettings(
            kind: .smtp,
            host: "smtp.example.org",
            port: 587,
            tlsMode: .startTLS,
            authentication: .password
        ),
        credentialID: "imap-smtp:person@example.org"
    )

    private static let credential = MailAccountCredential(
        incomingUsername: "person@example.org",
        outgoingUsername: "person@example.org",
        secret: "secret",
        authentication: .password
    )

    private static func backend(messages: [IMAPMessageListing]) -> IMAPSMTPBackend {
        IMAPSMTPBackend(
            account: account,
            configuration: configuration,
            credential: credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: ["inbox"],
                    role: .inbox
                ),
            ] },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(messages: messages, nextPageToken: nil)
            }
        )
    }

    private static func listing(
        uid: Int,
        messageID: String,
        inReplyTo: String? = nil,
        replyTo: [Correspondent] = [],
        minutes: Int
    ) -> IMAPMessageListing {
        IMAPMessageListing(
            uid: uid,
            messageID: messageID,
            inReplyTo: inReplyTo,
            replyTo: replyTo,
            subject: "Standup",
            from: Correspondent(email: "ada@example.org"),
            to: [Correspondent(email: "person@example.org")],
            cc: [],
            bcc: [],
            date: Date(timeIntervalSince1970: TimeInterval(minutes * 60)),
            isRead: false,
            isFlagged: false,
            isAnswered: false
        )
    }
}
