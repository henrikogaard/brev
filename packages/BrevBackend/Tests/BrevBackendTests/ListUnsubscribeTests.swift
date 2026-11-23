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

@Suite("List-Unsubscribe")
struct ListUnsubscribeTests {
    @Test("parser keeps HTTPS and mailto methods in header order")
    func parserKeepsHTTPSAndMailtoMethodsInHeaderOrder() throws {
        let options = ListUnsubscribeOptions.parse(
            listUnsubscribe: """
            <https://lists.example.org/unsubscribe?id=123>, \
            <mailto:unsubscribe@example.org?subject=unsubscribe>
            """,
            listUnsubscribePost: "List-Unsubscribe=One-Click"
        )

        #expect(options.methods == [
            .https(URL(string: "https://lists.example.org/unsubscribe?id=123")!, supportsOneClick: true),
            .mailto(URL(string: "mailto:unsubscribe@example.org?subject=unsubscribe")!)
        ])
        #expect(options.requiresExplicitConfirmation)
    }

    @Test("parser rejects unsafe schemes")
    func parserRejectsUnsafeSchemes() {
        let options = ListUnsubscribeOptions.parse(
            listUnsubscribe: "<javascript:alert(1)>, <ftp://example.org/unsubscribe>",
            listUnsubscribePost: nil
        )

        #expect(options.methods.isEmpty)
    }

    @Test("parser rejects suspicious HTTPS and malformed mailto methods")
    func parserRejectsSuspiciousHTTPSAndMalformedMailtoMethods() {
        let options = ListUnsubscribeOptions.parse(
            listUnsubscribe: "<https://user:token@example.org/unsubscribe>, <mailto:not-an-address>, <mailto:unsafe%20address@example.org>",
            listUnsubscribePost: nil
        )

        #expect(options.methods.isEmpty)
    }

    @Test("IMAP message parser extracts List-Unsubscribe and bulk precedence headers")
    func imapParserExtractsListUnsubscribeAndBulkPrecedence() {
        let raw = """
        From: Digest <digest@example.org>\r
        Subject: Weekly Dispatch\r
        Precedence: bulk\r
        List-Unsubscribe: <https://example.org/unsub>, <mailto:unsub@example.org>\r
        List-Unsubscribe-Post: List-Unsubscribe=One-Click\r
        \r
        Hello subscribers.
        """
        let parser = IMAPMessageBodyParser()
        let parsedBody = parser.parse(messageID: "INBOX:42", rawMessage: raw)
        #expect(parsedBody.listUnsubscribe?.methods.count == 2)
        #expect(parser.cachedListUnsubscribe(rawMessage: raw) == parsedBody.listUnsubscribe)
        #expect(parser.cachedIsBulkPrecedence(rawMessage: raw))
    }

    @Test("IMAPSMTPBackend exposes CachedListUnsubscribeProviding from cached source without network")
    func imapBackendExposesCachedListUnsubscribeService() async {
        let account = BrevAccount.preview
        let configuration = IMAPAccountConfiguration(
            accountID: account.id,
            emailAddress: "test@example.org",
            displayName: "Test",
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
            credentialID: "imap-smtp:test@example.org"
        )
        let credential = MailAccountCredential(
            incomingUsername: "test@example.org",
            outgoingUsername: "test@example.org",
            secret: "secret",
            authentication: .password
        )
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let raw = """
        From: Digest <digest@example.org>\r
        Subject: Weekly Dispatch\r
        Precedence: bulk\r
        List-Unsubscribe: <https://example.org/unsub>\r
        List-Unsubscribe-Post: List-Unsubscribe=One-Click\r
        \r
        Hello.
        """
        await sourceCache.setSource(
            IMAPMessageSource(uid: 42, rawMessageData: Data(raw.utf8)),
            accountID: account.id,
            messageID: "INBOX:42"
        )
        let backend = IMAPSMTPBackend(
            account: account,
            configuration: configuration,
            credential: credential,
            listFolders: { _, _ in Issue.record("Unexpected network call"); return [] },
            sourceCache: sourceCache
        )
        let service = backend.extensionService(CachedListUnsubscribeProviding.self)
        #expect(service != nil)
        let sourceID = MailSourceID(accountID: account.id, mailboxID: account.id)
        let cached = await service?.cachedListUnsubscribe(for: "INBOX:42", sourceID: sourceID)
        #expect(cached?.methods == [.https(URL(string: "https://example.org/unsub")!, supportsOneClick: true)])
        let isBulk = await service?.cachedIsBulkPrecedence(for: "INBOX:42", sourceID: sourceID)
        #expect(isBulk == true)
        let uncached = await service?.cachedListUnsubscribe(for: "INBOX:999", sourceID: sourceID)
        #expect(uncached == nil)
    }

    @Test("IMAP structuredBody preserves bulk precedence in parsed body cache without raw source")
    func structuredBodyPreservesBulkPrecedenceWithoutRawSource() async throws {
        let parser = IMAPMessageBodyParser()
        let structured = parser.structuredBody(
            messageID: "INBOX:77",
            headerBlock: "From: Notice <notice@example.org>\r\nSubject: Monthly notice\r\nPrecedence: bulk\r\n",
            plainText: "Hello",
            html: nil,
            attachments: [],
            readReceiptNotification: nil
        )
        #expect(structured.isBulkPrecedence == true)

        // Verify backward-compatible decoding of legacy cached MessageBody JSON without isBulkPrecedence.
        let legacyJSON = #"{"messageID":"INBOX:78","plainText":"Legacy","attachments":[]}"#
        let decodedLegacy = try JSONDecoder().decode(MessageBody.self, from: Data(legacyJSON.utf8))
        #expect(decodedLegacy.isBulkPrecedence == false)

        let account = BrevAccount(
            id: "imap-smtp:structured@example.org",
            displayName: "Structured",
            emailAddress: "structured@example.org",
            backendIdentifier: BrevAccount.imapSMTPBackendIdentifier
        )
        let configuration = IMAPAccountConfiguration(
            accountID: account.id,
            emailAddress: account.emailAddress,
            displayName: account.displayName,
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
            credentialID: account.id
        )
        let credential = MailAccountCredential(
            incomingUsername: "structured@example.org",
            outgoingUsername: "structured@example.org",
            secret: "secret",
            authentication: .password
        )
        let bodyCache = InMemoryIMAPMessageBodyCache()
        await bodyCache.setBody(structured, accountID: account.id, messageID: "INBOX:77")
        let backend = IMAPSMTPBackend(
            account: account,
            configuration: configuration,
            credential: credential,
            listFolders: { _, _ in Issue.record("Unexpected network call"); return [] },
            sourceCache: nil,
            bodyCache: bodyCache
        )
        let service = backend.extensionService(CachedListUnsubscribeProviding.self)
        let sourceID = MailSourceID(accountID: account.id, mailboxID: account.id)
        let isBulk = await service?.cachedIsBulkPrecedence(for: "INBOX:77", sourceID: sourceID)
        #expect(isBulk == true)
    }
}
