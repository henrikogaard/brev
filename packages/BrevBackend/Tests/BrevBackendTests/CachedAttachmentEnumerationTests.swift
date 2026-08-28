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

@Suite("Cached attachment enumeration seam")
struct CachedAttachmentEnumerationTests {
    private static let account = BrevAccount(
        id: "imap-smtp:person@example.org",
        displayName: "Person",
        emailAddress: "person@example.org"
    )

    private static let sourceID = MailSourceID(
        accountID: "imap-smtp:person@example.org",
        mailboxID: "imap-smtp:person@example.org"
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

    private static let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

    private static func header(id: String) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: id,
            folderID: "INBOX",
            from: Correspondent(email: "person@example.org"),
            to: [Correspondent(email: "me@example.org")],
            subject: "Subject \(id)",
            snippet: "Snippet",
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private static let attachmentRawMessage = """
    Content-Type: multipart/mixed; boundary="==boundary=="

    --==boundary==
    Content-Type: text/plain; charset=utf-8

    Here is the document.

    --==boundary==
    Content-Type: application/pdf; name="report.pdf"
    Content-Disposition: attachment; filename="report.pdf"
    Content-Transfer-Encoding: base64

    UERGIFN0dWZm

    --==boundary==--
    """

    private static let plainRawMessage = """
    Content-Type: text/plain; charset=utf-8

    No attachments here.
    """

    /// Builds a cache-injected backend. We never call `connect()`: the seam
    /// must read caches without a live connection.
    private static func backend(
        headerCache: InMemoryIMAPMailboxHeaderCache,
        sourceCache: InMemoryIMAPMessageSourceCache,
        bodyCache: InMemoryIMAPMessageBodyCache? = nil
    ) -> IMAPSMTPBackend {
        IMAPSMTPBackend(
            account: account,
            configuration: configuration,
            credential: credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            headerCache: headerCache,
            sourceCache: sourceCache,
            bodyCache: bodyCache
        )
    }

    @Test("prefers the parsed body cache over reparsing raw source")
    func prefersParsedBodyCache() async {
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let bodyCache = InMemoryIMAPMessageBodyCache()
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [Self.header(id: "INBOX:1")]),
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 1, rawMessage: "not a MIME message"),
            accountID: Self.account.id,
            messageID: "INBOX:1"
        )
        let cachedAttachment = Attachment(
            id: "cached-attachment",
            name: "cached.pdf",
            mimeType: "application/pdf",
            sizeBytes: 4
        )
        await bodyCache.setBody(
            MessageBody(
                messageID: "INBOX:1",
                attachments: [cachedAttachment]
            ),
            accountID: Self.account.id,
            messageID: "INBOX:1"
        )

        let messages = await Self.backend(
            headerCache: headerCache,
            sourceCache: sourceCache,
            bodyCache: bodyCache
        ).cachedAttachmentMessages(in: [Self.inbox])

        #expect(messages.map(\.body.attachments.first?.id) == ["cached-attachment"])
    }

    @Test("default MailBackend implementation returns no cached attachment messages")
    func defaultImplementationIsEmpty() async {
        let backend = MockBackend()
        let messages = await backend.cachedAttachmentMessages(in: MockBackend.previewFolders)
        #expect(messages.isEmpty)
    }

    @Test("enumerates attachment-bearing messages from the cache without connecting")
    func enumeratesCachedAttachmentMessages() async {
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [Self.header(id: "INBOX:1")]),
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 1, rawMessage: Self.attachmentRawMessage),
            accountID: Self.account.id,
            messageID: "INBOX:1"
        )

        let messages = await Self.backend(headerCache: headerCache, sourceCache: sourceCache)
            .cachedAttachmentMessages(in: [Self.inbox])

        #expect(messages.count == 1)
        #expect(messages.first?.folder == Self.inbox)
        #expect(messages.first?.header.id == "INBOX:1")
        #expect(messages.first?.body.attachments.count == 1)
        #expect(messages.first?.body.attachments.first?.name == "report.pdf")
        #expect(messages.first?.body.attachments.first?.isInline == false)
    }

    @Test("skips headers whose raw source is not cached")
    func skipsMessagesWithoutCachedSource() async {
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [
                Self.header(id: "INBOX:1"),
                Self.header(id: "INBOX:2"),
            ]),
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        // Only INBOX:1 has a cached source.
        await sourceCache.setSource(
            IMAPMessageSource(uid: 1, rawMessage: Self.attachmentRawMessage),
            accountID: Self.account.id,
            messageID: "INBOX:1"
        )

        let messages = await Self.backend(headerCache: headerCache, sourceCache: sourceCache)
            .cachedAttachmentMessages(in: [Self.inbox])

        #expect(messages.map(\.header.id) == ["INBOX:1"])
    }

    @Test("omits cached messages that carry no attachments")
    func omitsMessagesWithoutAttachments() async {
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [Self.header(id: "INBOX:1")]),
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 1, rawMessage: Self.plainRawMessage),
            accountID: Self.account.id,
            messageID: "INBOX:1"
        )

        let messages = await Self.backend(headerCache: headerCache, sourceCache: sourceCache)
            .cachedAttachmentMessages(in: [Self.inbox])

        #expect(messages.isEmpty)
    }

    @Test("source-scoped overload validates the source and reads the same cache")
    func sourceScopedOverloadValidatesSource() async {
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [Self.header(id: "INBOX:1")]),
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 1, rawMessage: Self.attachmentRawMessage),
            accountID: Self.account.id,
            messageID: "INBOX:1"
        )
        let backend = Self.backend(headerCache: headerCache, sourceCache: sourceCache)

        let matched = await backend.cachedAttachmentMessages(in: [Self.inbox], sourceID: Self.sourceID)
        #expect(matched.map(\.header.id) == ["INBOX:1"])

        let foreignSource = MailSourceID(accountID: "other", mailboxID: "other")
        let unmatched = await backend.cachedAttachmentMessages(in: [Self.inbox], sourceID: foreignSource)
        #expect(unmatched.isEmpty)
    }
}
