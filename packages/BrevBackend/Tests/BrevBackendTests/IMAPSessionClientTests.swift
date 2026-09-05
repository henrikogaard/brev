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

@Suite("IMAP session client")
struct IMAPSessionClientTests {
    @Test("foreground IMAP work jumps ahead of queued background work while preserving FIFO ties")
    func foregroundWorkWinsQueuedSessionOrder() {
        let queued: [IMAPSessionOperationClass] = [
            .background,
            .standard,
            .foreground,
            .foreground,
        ]

        #expect(IMAPSessionOperationScheduling.nextIndex(in: queued) == 2)
        #expect(IMAPSessionOperationScheduling.nextIndex(in: [.background, .standard]) == 1)
    }

    @Test("task priorities map background refresh below normal and reader work")
    func taskPrioritiesMapToSessionClasses() {
        #expect(IMAPSessionOperationScheduling.operationClass(for: .background) == .background)
        #expect(IMAPSessionOperationScheduling.operationClass(for: .utility) == .background)
        #expect(IMAPSessionOperationScheduling.operationClass(for: .medium) == .standard)
        #expect(IMAPSessionOperationScheduling.operationClass(for: .userInitiated) == .foreground)
    }

    @Test("cache refresh grace period leaves the command session available to a message open")
    func cachedRefreshUsesShortGracePeriod() {
        #expect(IMAPBackgroundRefreshPolicy.graceNanoseconds > 0)
        #expect(IMAPBackgroundRefreshPolicy.graceNanoseconds <= 500_000_000)
    }

    @Test("client times out when IMAP server stops responding")
    func clientTimesOutWhenIMAPServerStopsResponding() async {
        let transport = ScriptedIMAPTransport(
            lines: [],
            suspendsWhenOutOfLines: true
        )
        let client = IMAPSessionClient(
            transport: transport,
            responseTimeoutNanoseconds: 1_000_000
        )

        await #expect(throws: IMAPClientError.transport("Timed out waiting for IMAP CONNECT response.")) {
            try await client.loginAndListFolders(
                configuration: Self.configuration(),
                credential: Self.credential()
            )
        }
    }

    @Test("client logs in and lists folders")
    func clientLogsInAndListsFolders() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "* LIST (\\HasNoChildren) \"/\" \"INBOX\"",
            "* LIST (\\HasNoChildren \\Sent) \"/\" \"Sent\"",
            "* LIST (\\HasNoChildren) \"/\" \"Projects/Alpha\"",
            "A0002 OK LIST completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let folders = try await client.loginAndListFolders(
            configuration: Self.configuration(),
            credential: Self.credential()
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 LIST \"\" \"*\"",
        ])
        #expect(folders.map(\.path) == ["INBOX", "Sent", "Projects/Alpha"])
        #expect(folders.map(\.role) == [.inbox, .sent, .custom])
    }

    @Test("client parses case-insensitive LIST folder responses")
    func clientParsesCaseInsensitiveLISTFolderResponses() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "* List (\\HasNoChildren) \"/\" \"INBOX\"",
            "* lIsT (\\HasNoChildren \\Sent) \"/\" \"Sent\"",
            "A0002 OK LIST completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let folders = try await client.loginAndListFolders(
            configuration: Self.configuration(),
            credential: Self.credential()
        )

        #expect(folders.map(\.path) == ["INBOX", "Sent"])
        #expect(folders.map(\.role) == [.inbox, .sent])
    }

    @Test("client decodes modified UTF-7 folder names")
    func clientDecodesModifiedUTF7FolderNames() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            #"* LIST (\HasNoChildren) "/" "Projects/F&APg-lder""#,
            #"* LIST (\HasNoChildren) "/" "Sent &- Archive""#,
            "A0002 OK LIST completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let folders = try await client.loginAndListFolders(
            configuration: Self.configuration(),
            credential: Self.credential()
        )

        #expect(folders.map(\.path) == ["Projects/Følder", "Sent & Archive"])
        #expect(folders.map(\.displayName) == ["Følder", "Sent & Archive"])
    }

    @Test("client fetches per-folder unread counts with STATUS when asked")
    func clientFetchesFolderUnreadCountsWithSTATUS() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "* LIST (\\HasNoChildren) \"/\" \"INBOX\"",
            "* LIST (\\Noselect \\HasChildren) \"/\" \"[Gmail]\"",
            "* LIST (\\HasNoChildren \\Sent) \"/\" \"Sent\"",
            "A0002 OK LIST completed",
            "* STATUS \"INBOX\" (MESSAGES 150 UNSEEN 28)",
            "A0003 OK STATUS completed",
            "* STATUS Sent (UNSEEN 0 MESSAGES 47)",
            "A0004 OK STATUS completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let folders = try await client.loginAndListFolders(
            configuration: Self.configuration(),
            credential: Self.credential(),
            includingUnreadCounts: true
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 LIST \"\" \"*\"",
            "A0003 STATUS \"INBOX\" (MESSAGES UNSEEN)",
            "A0004 STATUS \"Sent\" (MESSAGES UNSEEN)",
        ])
        #expect(folders.map(\.path) == ["INBOX", "[Gmail]", "Sent"])
        #expect(folders.map(\.unreadCount) == [28, 0, 0])
        #expect(folders.map(\.totalCount) == [150, 0, 47])
    }

    @Test("a refused STATUS leaves that folder's counts at zero without failing the listing")
    func refusedSTATUSLeavesCountsAtZeroWithoutFailingListing() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "* LIST (\\HasNoChildren) \"/\" \"INBOX\"",
            "* LIST (\\HasNoChildren \\Sent) \"/\" \"Sent\"",
            "A0002 OK LIST completed",
            "A0003 NO STATUS not allowed",
            "* STATUS \"Sent\" (MESSAGES 47 UNSEEN 2)",
            "A0004 OK STATUS completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let folders = try await client.loginAndListFolders(
            configuration: Self.configuration(),
            credential: Self.credential(),
            includingUnreadCounts: true
        )

        #expect(folders.map(\.unreadCount) == [0, 2])
        #expect(folders.map(\.totalCount) == [0, 47])
    }

    @Test("client creates renames and deletes folders")
    func clientCreatesRenamesAndDeletesFolders() async throws {
        let createTransport = ScriptedIMAPTransport(lines: [
            "* OK ready",
            "A0001 OK LOGIN completed",
            "A0002 OK CREATE completed",
        ])
        try await IMAPSessionClient(transport: createTransport).loginAndCreateFolder(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "Projects/Delta"
        )

        let renameTransport = ScriptedIMAPTransport(lines: [
            "* OK ready",
            "A0001 OK LOGIN completed",
            "A0002 OK RENAME completed",
        ])
        try await IMAPSessionClient(transport: renameTransport).loginAndRenameFolder(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "Projects/Delta",
            newFolderPath: "Projects/Archive Delta"
        )

        let deleteTransport = ScriptedIMAPTransport(lines: [
            "* OK ready",
            "A0001 OK LOGIN completed",
            "A0002 OK DELETE completed",
        ])
        try await IMAPSessionClient(transport: deleteTransport).loginAndDeleteFolder(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "Projects/Archive Delta"
        )

        #expect(await createTransport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 CREATE \"Projects/Delta\"",
        ])
        #expect(await renameTransport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 RENAME \"Projects/Delta\" \"Projects/Archive Delta\"",
        ])
        #expect(await deleteTransport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 DELETE \"Projects/Archive Delta\"",
        ])
    }

    @Test("client encodes modified UTF-7 folder names in commands")
    func clientEncodesModifiedUTF7FolderNamesInCommands() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed",
            "* SEARCH",
            "A0003 OK SEARCH completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        _ = try await client.loginAndListMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "Projects/Følder & Archive",
            limit: 10
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"Projects/F&APg-lder &- Archive\" (CONDSTORE)",
            "A0003 UID SEARCH ALL",
        ])
    }

    @Test("LOGIN credentials are quoted for IMAP")
    func loginCredentialsAreQuotedForIMAP() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK ready",
            "A0001 OK LOGIN completed",
            "A0002 OK LIST completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        _ = try await client.loginAndListFolders(
            configuration: Self.configuration(),
            credential: MailAccountCredential(
                incomingUsername: "person\"example@example.org",
                outgoingUsername: "person@example.org",
                secret: #"pa"\\ss"#,
                authentication: .password
            )
        )

        #expect(await transport.sentLines.first == #"A0001 LOGIN "person\"example@example.org" "pa\"\\\\ss""#)
    }

    @Test("LOGIN credentials reject CRLF before sending command")
    func loginCredentialsRejectCRLFBeforeSendingCommand() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK ready",
        ])
        let client = IMAPSessionClient(transport: transport)

        await #expect(throws: IMAPClientError.malformedResponse("IMAP quoted strings cannot contain line breaks.")) {
            _ = try await client.loginAndListFolders(
                configuration: Self.configuration(),
                credential: MailAccountCredential(
                    incomingUsername: "person@example.org\r\nA999 LOGOUT",
                    outgoingUsername: "person@example.org",
                    secret: "secret",
                    authentication: .password
                )
            )
        }
        #expect(await transport.sentLines.isEmpty)
    }

    @Test("LOGIN credentials reject NUL before IMAP connect")
    func loginCredentialsRejectNULBeforeIMAPConnect() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK ready",
        ])
        let client = IMAPSessionClient(transport: transport)

        await #expect(throws: IMAPClientError.malformedResponse("IMAP credentials cannot contain NUL characters.")) {
            _ = try await client.loginAndListFolders(
                configuration: Self.configuration(),
                credential: MailAccountCredential(
                    incomingUsername: "person@example.org",
                    outgoingUsername: "person@example.org",
                    secret: "sec\u{0}ret",
                    authentication: .password
                )
            )
        }
        #expect(await transport.connectedServer == nil)
        #expect(await transport.sentLines.isEmpty)
    }

    @Test("authentication failure maps to a stable client error")
    func authenticationFailureMapsToStableClientError() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK ready",
            "A0001 NO [AUTHENTICATIONFAILED] Invalid credentials",
        ])
        let client = IMAPSessionClient(transport: transport)

        await #expect(throws: IMAPClientError.authenticationFailed(
            "A0001 NO [AUTHENTICATIONFAILED] Invalid credentials"
        )) {
            try await client.loginAndListFolders(
                configuration: Self.configuration(),
                credential: Self.credential()
            )
        }
    }

    @Test("simultaneous connection limit maps to a distinct retryable client error")
    func simultaneousConnectionLimitMapsToDistinctRetryableClientError() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK Gimap ready for requests",
            "A0001 NO [ALERT] Too many simultaneous connections. (Failure)",
        ])
        let client = IMAPSessionClient(transport: transport)

        await #expect(throws: IMAPClientError.connectionLimitExceeded(
            "A0001 NO [ALERT] Too many simultaneous connections. (Failure)"
        )) {
            try await client.loginAndListFolders(
                configuration: Self.configuration(),
                credential: Self.credential()
            )
        }
    }

    @Test("connection limit classification is case-insensitive and not auth failure")
    func connectionLimitClassificationIsCaseInsensitive() {
        #expect(
            IMAPClientError.isConnectionLimitResponse(
                "a0001 no [alert] TOO MANY SIMULTANEOUS CONNECTIONS. (failure)"
            )
        )
        #expect(
            IMAPClientError.isConnectionLimitResponse(
                "A0001 NO [UNAVAILABLE] Too many open connections"
            )
        )
        #expect(
            IMAPClientError.isConnectionLimitResponse(
                "A0001 NO Maximum number of connections from user+IP exceeded"
            )
        )
        #expect(
            !IMAPClientError.isConnectionLimitResponse(
                "A0001 NO [AUTHENTICATIONFAILED] Invalid credentials"
            )
        )
        #expect(IMAPClientError.connectionLimitRetryCooldownNanoseconds == 45_000_000_000)
    }

    @Test("client logs in selects folder and fetches message listings")
    func clientLogsInSelectsFolderAndFetchesMessageListings() async throws {
        let firstSnippet = "First preview text from the message body."
        let secondSnippet = "Second preview text from the message body."
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "* 23 EXISTS",
            "* OK [UIDVALIDITY 987654321] UIDs valid",
            "A0002 OK [READ-WRITE] SELECT completed",
            "* SEARCH 41 42 43",
            "A0003 OK SEARCH completed",
            #"* 12 FETCH (UID 42 FLAGS (\Seen) ENVELOPE ("Fri, 05 Jun 2026 10:00:00 +0000" "First" (("Ada Lovelace" NIL "ada" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-42@example.org>") BODY[TEXT]<0> {\#(firstSnippet.utf8.count)}"#,
            ")",
            #"* 13 FETCH (UID 43 FLAGS (\Flagged \Answered) ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "Second" (("Grace Hopper" NIL "grace" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-43@example.org>") BODY[TEXT]<0> {\#(secondSnippet.utf8.count)}"#,
            ")",
            "A0004 OK FETCH completed",
        ], dataReads: [
            Data(firstSnippet.utf8),
            Data(secondSnippet.utf8),
        ])
        let client = IMAPSessionClient(transport: transport)

        let page = try await client.loginAndListMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            limit: 2
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID SEARCH ALL",
            "A0004 UID FETCH 42,43 (FLAGS ENVELOPE BODY.PEEK[TEXT]<0.1024>)",
        ])
        let messages = page.messages
        #expect(page.uidValidity == 987_654_321)
        #expect(page.nextPageToken == "before:42")
        #expect(messages.map(\.uid) == [43, 42])
        #expect(messages.map(\.subject) == ["Second", "First"])
        let firstMessage = try #require(messages.first)
        let firstMessageSnippet = Mirror(reflecting: firstMessage)
            .children
            .first { $0.label == "snippet" }?
            .value as? String
        #expect(firstMessageSnippet == secondSnippet)
        #expect(messages.first?.from == Correspondent(
            name: "Grace Hopper",
            email: "grace@example.org"
        ))
        #expect(messages.first?.to == [Correspondent(email: "person@example.org")])
        #expect(messages.first?.isRead == false)
        #expect(messages.first?.isFlagged == true)
        #expect(messages.first?.isAnswered == true)
        #expect(messages.first?.messageID == "<msg-43@example.org>")
    }

    @Test("listing snippets decode quoted-printable BODY TEXT peeks")
    func listingSnippetsDecodeQuotedPrintableBodyTextPeeks() async throws {
        let encodedSnippet = "=0A=0A=0A*|SUBJECT|* Hello from=20Porkbun"
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "* 1 EXISTS",
            "* OK [UIDVALIDITY 1] UIDs valid",
            "A0002 OK [READ-WRITE] SELECT completed",
            "* SEARCH 91",
            "A0003 OK SEARCH completed",
            #"* 1 FETCH (UID 91 FLAGS (\Seen) ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "Price change" (("Porkbun" NIL "support" "porkbun.com")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-91@example.org>") BODY[TEXT]<0> {\#(encodedSnippet.utf8.count)}"#,
            ")",
            "A0004 OK FETCH completed",
        ], dataReads: [
            Data(encodedSnippet.utf8),
        ])
        let client = IMAPSessionClient(transport: transport)

        let page = try await client.loginAndListMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            limit: 1
        )

        let snippet = try Mirror(reflecting: #require(page.messages.first))
            .children
            .first { $0.label == "snippet" }?
            .value as? String
        #expect(snippet == "Hello from Porkbun")
        #expect(snippet?.contains("=0A") != true)
    }

    @Test("listing snippets skip leading link-only and subject-echo lines")
    func listingSnippetsSkipLeadingLinkOnlyAndSubjectEchoLines() async throws {
        let body = [
            "Resend (https://resend.com)",
            "",
            "$20.00 payment to Resend was unsuccessful",
            "",
            "We weren't able to charge the credit card you provided.",
        ].joined(separator: "\r\n")
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "* 1 EXISTS",
            "* OK [UIDVALIDITY 1] UIDs valid",
            "A0002 OK [READ-WRITE] SELECT completed",
            "* SEARCH 95",
            "A0003 OK SEARCH completed",
            #"* 1 FETCH (UID 95 FLAGS (\Seen) ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "$20.00 payment to Resend was unsuccessful" (("Resend" NIL "billing" "resend.com")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-95@example.org>") BODY[TEXT]<0> {\#(body.utf8.count)}"#,
            ")",
            "A0004 OK FETCH completed",
        ], dataReads: [
            Data(body.utf8),
        ])
        let client = IMAPSessionClient(transport: transport)

        let page = try await client.loginAndListMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            limit: 1
        )

        let snippet = try Mirror(reflecting: #require(page.messages.first))
            .children
            .first { $0.label == "snippet" }?
            .value as? String
        #expect(snippet == "We weren't able to charge the credit card you provided.")
    }

    @Test("listing snippets skip leading markdown-link rows and reach the prose")
    func listingSnippetsSkipLeadingMarkdownLinkRows() async throws {
        let body = [
            "https://dbjourney.com/ [Shop](https://dbjourney.com/collections/all)",
            "",
            "Our late summer collection is here.",
        ].joined(separator: "\r\n")
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "* 1 EXISTS",
            "* OK [UIDVALIDITY 1] UIDs valid",
            "A0002 OK [READ-WRITE] SELECT completed",
            "* SEARCH 96",
            "A0003 OK SEARCH completed",
            #"* 1 FETCH (UID 96 FLAGS (\Seen) ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "New arrivals" (("Db" NIL "hello" "dbjourney.com")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-96@example.org>") BODY[TEXT]<0> {\#(body.utf8.count)}"#,
            ")",
            "A0004 OK FETCH completed",
        ], dataReads: [
            Data(body.utf8),
        ])
        let client = IMAPSessionClient(transport: transport)

        let page = try await client.loginAndListMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            limit: 1
        )

        let snippet = try Mirror(reflecting: #require(page.messages.first))
            .children
            .first { $0.label == "snippet" }?
            .value as? String
        #expect(snippet == "Our late summer collection is here.")
    }

    @Test("listing snippets drop MIME framing, folded headers, and the multipart preamble")
    func listingSnippetsDropMIMEFramingFoldedHeadersAndPreamble() async throws {
        let multipartBody = [
            "This is a multi-part message in MIME format.",
            "--boundary123",
            "Content-Type: text/plain;",
            " charset=UTF-8",
            "Content-Description: Payment failed notice",
            "Mime-Version: 1.0",
            "",
            "We weren't able to charge the credit card you provided.",
            "--boundary123",
        ].joined(separator: "\r\n")
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "* 1 EXISTS",
            "* OK [UIDVALIDITY 1] UIDs valid",
            "A0002 OK [READ-WRITE] SELECT completed",
            "* SEARCH 93",
            "A0003 OK SEARCH completed",
            #"* 1 FETCH (UID 93 FLAGS (\Seen) ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "Payment failed" (("Resend" NIL "billing" "resend.com")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-93@example.org>") BODY[TEXT]<0> {\#(multipartBody.utf8.count)}"#,
            ")",
            "A0004 OK FETCH completed",
        ], dataReads: [
            Data(multipartBody.utf8),
        ])
        let client = IMAPSessionClient(transport: transport)

        let page = try await client.loginAndListMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            limit: 1
        )

        let snippet = try Mirror(reflecting: #require(page.messages.first))
            .children
            .first { $0.label == "snippet" }?
            .value as? String
        #expect(snippet == "We weren't able to charge the credit card you provided.")
    }

    @Test("listing snippets drop style blocks and a tag truncated by the peek limit")
    func listingSnippetsDropStyleBlocksAndTruncatedTrailingTag() async throws {
        let htmlBody = "<html><head><title>Spark Mail</title>"
            + "<style type=\"text/css\">.slogan:before { content: \"\"; flex: 1 1; }</style>"
            + "</head><body><p>Your workspace is ready.</p><table><tr><td al"
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "* 1 EXISTS",
            "* OK [UIDVALIDITY 1] UIDs valid",
            "A0002 OK [READ-WRITE] SELECT completed",
            "* SEARCH 94",
            "A0003 OK SEARCH completed",
            #"* 1 FETCH (UID 94 FLAGS (\Seen) ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "Welcome" (("Spark" NIL "hello" "sparkmail.com")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-94@example.org>") BODY[TEXT]<0> {\#(htmlBody.utf8.count)}"#,
            ")",
            "A0004 OK FETCH completed",
        ], dataReads: [
            Data(htmlBody.utf8),
        ])
        let client = IMAPSessionClient(transport: transport)

        let page = try await client.loginAndListMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            limit: 1
        )

        let snippet = try Mirror(reflecting: #require(page.messages.first))
            .children
            .first { $0.label == "snippet" }?
            .value as? String
        #expect(snippet == "Spark Mail Your workspace is ready.")
    }

    @Test("listing snippets keep literal equals values that are not quoted-printable")
    func listingSnippetsKeepLiteralEqualsValuesThatAreNotQuotedPrintable() async throws {
        let plainSnippet = "Set code=10 and retry=20 before shipping."
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "* 1 EXISTS",
            "* OK [UIDVALIDITY 1] UIDs valid",
            "A0002 OK [READ-WRITE] SELECT completed",
            "* SEARCH 92",
            "A0003 OK SEARCH completed",
            #"* 1 FETCH (UID 92 FLAGS (\Seen) ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "Retry" (("Ada" NIL "ada" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-92@example.org>") BODY[TEXT]<0> {\#(plainSnippet.utf8.count)}"#,
            ")",
            "A0004 OK FETCH completed",
        ], dataReads: [
            Data(plainSnippet.utf8),
        ])
        let client = IMAPSessionClient(transport: transport)

        let page = try await client.loginAndListMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            limit: 1
        )

        let snippet = try Mirror(reflecting: #require(page.messages.first))
            .children
            .first { $0.label == "snippet" }?
            .value as? String
        #expect(snippet == plainSnippet)
    }

    @Test("client parses case-insensitive FETCH message attributes")
    func clientParsesCaseInsensitiveFETCHMessageAttributes() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed",
            "* SEARCH 42",
            "A0003 OK SEARCH completed",
            #"* 12 Fetch (Uid 42 Flags (\Seen \Answered) Envelope ("Fri, 05 Jun 2026 10:00:00 +0000" "Mixed case" (("Ada Lovelace" NIL "ada" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-42@example.org>"))"#,
            "A0004 OK FETCH completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let page = try await client.loginAndListMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            limit: 1
        )

        let message = try #require(page.messages.first)
        #expect(message.uid == 42)
        #expect(message.subject == "Mixed case")
        #expect(message.isRead == true)
        #expect(message.isAnswered == true)
        #expect(message.from == Correspondent(
            name: "Ada Lovelace",
            email: "ada@example.org"
        ))
    }

    @Test("client parses case-insensitive SEARCH response atoms")
    func clientParsesCaseInsensitiveSEARCHResponseAtoms() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed",
            "* Search 42",
            "A0003 OK SEARCH completed",
            #"* 12 FETCH (UID 42 FLAGS (\Seen) ENVELOPE ("Fri, 05 Jun 2026 10:00:00 +0000" "Mixed search" (("Ada Lovelace" NIL "ada" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-42@example.org>"))"#,
            "A0004 OK FETCH completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let page = try await client.loginAndListMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            limit: 1
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID SEARCH ALL",
            "A0004 UID FETCH 42 (FLAGS ENVELOPE BODY.PEEK[TEXT]<0.1024>)",
        ])
        #expect(page.messages.map(\.uid) == [42])
        #expect(page.messages.first?.subject == "Mixed search")
    }

    @Test("client lists older message page from page token")
    func clientListsOlderMessagePageFromPageToken() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed",
            "* SEARCH 41 42 43 44",
            "A0003 OK SEARCH completed",
            #"* 11 FETCH (UID 41 FLAGS () ENVELOPE ("Thu, 04 Jun 2026 10:00:00 +0000" "Older" ((NIL NIL "ada" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-41@example.org>"))"#,
            "A0004 OK FETCH completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let page = try await client.loginAndListMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            pageToken: "before:42",
            limit: 2
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID SEARCH ALL",
            "A0004 UID FETCH 41 (FLAGS ENVELOPE BODY.PEEK[TEXT]<0.1024>)",
        ])
        #expect(page.messages.map(\.uid) == [41])
        #expect(page.nextPageToken == nil)
    }

    @Test("client searches attachment candidates through bounded cursor pages")
    func clientSearchesAttachmentCandidatesThroughBoundedCursorPages() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed",
            "* SEARCH 10 20",
            "A0003 OK SEARCH completed",
            #"* 20 FETCH (UID 20 FLAGS () ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "Newest" ((NIL NIL "ada" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-20@example.org>"))"#,
            "A0004 OK FETCH completed",
            "* SEARCH 10 20",
            "A0005 OK SEARCH completed",
            #"* 10 FETCH (UID 10 FLAGS () ENVELOPE ("Fri, 05 Jun 2026 12:00:00 +0000" "Older" ((NIL NIL "ada" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-10@example.org>"))"#,
            "A0006 OK FETCH completed",
        ])
        let client = IMAPSessionClient(transport: transport, reusesAuthenticatedSession: true)

        let firstPage = try await client.loginAndSearchMessagePage(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            query: SearchQuery(subject: "receipt", execution: .serverOnly),
            limit: 1
        )
        let secondPage = try await client.loginAndSearchMessagePage(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            query: SearchQuery(subject: "receipt", execution: .serverOnly),
            pageToken: firstPage.nextPageToken,
            limit: 1
        )

        #expect(firstPage.messages.map(\.uid) == [20])
        #expect(firstPage.nextPageToken == "before:20")
        #expect(secondPage.messages.map(\.uid) == [10])
        #expect(secondPage.nextPageToken == nil)
        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID SEARCH SUBJECT \"receipt\"",
            "A0004 UID FETCH 20 (FLAGS ENVELOPE BODY.PEEK[TEXT]<0.1024>)",
            "A0005 UID SEARCH SUBJECT \"receipt\"",
            "A0006 UID FETCH 10 (FLAGS ENVELOPE BODY.PEEK[TEXT]<0.1024>)",
        ])
    }

    @Test("client searches selected folder with IMAP criteria")
    func clientSearchesSelectedFolderWithIMAPCriteria() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed",
            "* SEARCH 91",
            "A0003 OK SEARCH completed",
            #"* 9 FETCH (UID 91 FLAGS (\Seen) ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "CI receipt" (("GitHub" NIL "notifications" "github.com")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-91@example.org>"))"#,
            "A0004 OK FETCH completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let messages = try await client.loginAndSearchMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            query: SearchQuery(
                text: "receipt",
                from: "github.com",
                isUnread: false,
                subject: "CI",
                execution: .serverOnly
            ),
            limit: 25
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID SEARCH TEXT \"receipt\" FROM \"github.com\" SEEN SUBJECT \"CI\"",
            "A0004 UID FETCH 91 (FLAGS ENVELOPE BODY.PEEK[TEXT]<0.1024>)",
        ])
        #expect(messages.map(\.uid) == [91])
        #expect(messages.first?.subject == "CI receipt")
    }

    @Test("client sends multi-word text search as all-term IMAP criteria")
    func clientSendsMultiWordTextSearchAsAllTermIMAPCriteria() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed",
            "* SEARCH 91",
            "A0003 OK SEARCH completed",
            #"* 9 FETCH (UID 91 FLAGS (\Seen) ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "Quarterly budget" (("Finance" NIL "finance" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-91@example.org>"))"#,
            "A0004 OK FETCH completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let messages = try await client.loginAndSearchMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            query: SearchQuery(
                text: " quarterly   budget ",
                execution: .serverOnly
            ),
            limit: 25
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID SEARCH TEXT \"quarterly\" TEXT \"budget\"",
            "A0004 UID FETCH 91 (FLAGS ENVELOPE BODY.PEEK[TEXT]<0.1024>)",
        ])
        #expect(messages.map(\.uid) == [91])
    }

    @Test("client searches recipient filter across to cc and bcc")
    func clientSearchesRecipientFilterAcrossToCcAndBcc() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed",
            "* SEARCH",
            "A0003 OK SEARCH completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let messages = try await client.loginAndSearchMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            query: SearchQuery(
                to: "hidden@example.org",
                execution: .serverOnly
            ),
            limit: 25
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID SEARCH OR OR TO \"hidden@example.org\" CC \"hidden@example.org\" BCC \"hidden@example.org\"",
        ])
        #expect(messages.isEmpty)
    }

    // Regression: a non-ASCII SEARCH term (e.g. Norwegian "Møte") must be
    // sent as an RFC 3501 synchronizing literal under CHARSET UTF-8, not as
    // a quoted string of raw 8-bit octets — strict servers answer BAD or
    // mis-search the latter, which reads to the user as "search is broken".
    @Test("client sends non-ASCII search terms as UTF-8 literals")
    func clientSendsNonASCIISearchTermsAsLiterals() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed",
            "+ Ready for literal data",
            "* SEARCH 91",
            "A0003 OK SEARCH completed",
            #"* 9 FETCH (UID 91 FLAGS (\Seen) ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "Møte" (("Henrik" NIL "henrik" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-91@example.org>"))"#,
            "A0004 OK FETCH completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let messages = try await client.loginAndSearchMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            query: SearchQuery(
                text: "Møte",
                execution: .serverOnly
            ),
            limit: 25
        )

        // "Møte" is 5 UTF-8 octets (M, ø=2 bytes, t, e). The command is split
        // at the literal: the marker line, then the raw octets, then the
        // terminating CRLF (an empty writeLine), then FETCH.
        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID SEARCH CHARSET UTF-8 TEXT {5}",
            "",
            "A0004 UID FETCH 91 (FLAGS ENVELOPE BODY.PEEK[TEXT]<0.1024>)",
        ])
        #expect(await transport.sentData == [Data("Møte".utf8)])
        #expect(messages.map(\.uid) == [91])
    }

    @Test("client chains multiple non-ASCII search literals")
    func clientChainsMultipleNonASCIISearchLiterals() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed",
            "+ Ready for first literal",
            "+ Ready for second literal",
            "* SEARCH 92",
            "A0003 OK SEARCH completed",
            #"* 10 FETCH (UID 92 FLAGS (\Seen) ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "Årsrapport" (("Henrik" NIL "henrik" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-92@example.org>"))"#,
            "A0004 OK FETCH completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let messages = try await client.loginAndSearchMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            query: SearchQuery(
                text: "Møte årsrapport",
                execution: .serverOnly
            ),
            limit: 25
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID SEARCH CHARSET UTF-8 TEXT {5}",
            " TEXT {11}",
            "",
            "A0004 UID FETCH 92 (FLAGS ENVELOPE BODY.PEEK[TEXT]<0.1024>)",
        ])
        #expect(await transport.sentData == [
            Data("Møte".utf8),
            Data("årsrapport".utf8),
        ])
        #expect(messages.map(\.uid) == [92])
    }

    @Test("message listing decodes RFC 2047 subject and display names")
    func messageListingDecodesRFC2047SubjectAndDisplayNames() throws {
        let listing = try #require(IMAPMessageListing.parse(
            #"* 9 FETCH (UID 99 FLAGS () ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "=?UTF-8?Q?M=C3=B8te_om_prosjektet?=" (("=?UTF-8?Q?Henrik_=C3=98g=C3=A5rd?=" NIL "henrik" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-99@example.org>"))"#
        ))

        #expect(listing.subject == "Møte om prosjektet")
        #expect(listing.from == Correspondent(
            name: "Henrik Øgård",
            email: "henrik@example.org"
        ))
    }

    @Test("message listing ignores UID-looking text inside envelope strings")
    func messageListingIgnoresUIDLookingTextInsideEnvelopeStrings() throws {
        let listing = try #require(IMAPMessageListing.parse(
            #"* 9 FETCH (ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "UID 999 in subject" (("Sender UID 888" NIL "sender" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-42@example.org>") FLAGS (\Seen) UID 42)"#
        ))

        #expect(listing.uid == 42)
        #expect(listing.subject == "UID 999 in subject")
        #expect(listing.from == Correspondent(
            name: "Sender UID 888",
            email: "sender@example.org"
        ))
    }

    @Test("message listing accepts flexible FLAGS whitespace")
    func messageListingAcceptsFlexibleFLAGSWhitespace() throws {
        let listing = try #require(IMAPMessageListing.parse(
            #"* 9 FETCH (UID 42 FLAGS   (\Seen \Flagged) ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "Padded flags" (("Sender" NIL "sender" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-42@example.org>"))"#
        ))

        #expect(listing.uid == 42)
        #expect(listing.subject == "Padded flags")
        #expect(listing.isRead == true)
        #expect(listing.isFlagged == true)
    }

    @Test("message listing skips extension attributes that prefix known atoms")
    func messageListingSkipsExtensionAttributesThatPrefixKnownAtoms() throws {
        let listing = try #require(IMAPMessageListing.parse(
            #"* 9 FETCH (UIDNEXT 999 FLAGSX NIL UID   42 FLAGS (\Seen) ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "Extension atoms" (("Sender" NIL "sender" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-42@example.org>"))"#
        ))

        #expect(listing.uid == 42)
        #expect(listing.subject == "Extension atoms")
        #expect(listing.isRead == true)
    }

    @Test("message listing reads ENVELOPE subject literals")
    func messageListingReadsEnvelopeSubjectLiterals() async throws {
        let subject = "Møte med vedlegg"
        let transport = ScriptedIMAPTransport(
            lines: [
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "A0002 OK [READ-WRITE] SELECT completed",
                "* SEARCH 55",
                "A0003 OK SEARCH completed",
                #"* 9 FETCH (UID 55 FLAGS () ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" {\#(subject.utf8.count)}"#,
                #" (("Literal Sender" NIL "sender" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<literal-55@example.org>"))"#,
                "A0004 OK FETCH completed",
            ],
            dataReads: [Data(subject.utf8)]
        )
        let client = IMAPSessionClient(transport: transport)

        let page = try await client.loginAndListMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            limit: 1
        )

        let message = try #require(page.messages.first)
        #expect(message.uid == 55)
        #expect(message.subject == subject)
        #expect(message.from == Correspondent(
            name: "Literal Sender",
            email: "sender@example.org"
        ))
    }

    @Test("message listing unfolds multiline ENVELOPE subject literals")
    func messageListingUnfoldsMultilineEnvelopeSubjectLiterals() async throws {
        let subject = "Project update\r\n next steps"
        let transport = ScriptedIMAPTransport(
            lines: [
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "A0002 OK [READ-WRITE] SELECT completed",
                "* SEARCH 56",
                "A0003 OK SEARCH completed",
                #"* 9 FETCH (UID 56 FLAGS () ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" {\#(subject.utf8.count)}"#,
                #" (("Literal Sender" NIL "sender" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<literal-56@example.org>"))"#,
                "A0004 OK FETCH completed",
            ],
            dataReads: [Data(subject.utf8)]
        )
        let client = IMAPSessionClient(transport: transport)

        let page = try await client.loginAndListMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            limit: 1
        )

        let message = try #require(page.messages.first)
        #expect(message.uid == 56)
        #expect(message.subject == "Project update next steps")
    }

    @Test("client skips UID FETCH when folder search returns no messages")
    func clientSkipsUIDFetchWhenSearchReturnsNoMessages() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed",
            "* SEARCH",
            "A0003 OK SEARCH completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let page = try await client.loginAndListMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            limit: 25
        )

        #expect(page.messages.isEmpty)
        #expect(page.nextPageToken == nil)
        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID SEARCH ALL",
        ])
    }

    @Test("client logs in selects folder and fetches raw message source")
    func clientLogsInSelectsFolderAndFetchesRawMessageSource() async throws {
        let rawMessage = [
            "Subject: Test",
            "Content-Type: text/plain; charset=utf-8",
            "",
            "Hello from IMAP.",
        ].joined(separator: "\r\n")
        let transport = ScriptedIMAPTransport(
            lines: [
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "A0002 OK [READ-WRITE] SELECT completed",
                "* 14 FETCH (UID 43 BODY[] {\(rawMessage.utf8.count)}",
                ")",
                "A0003 OK FETCH completed",
            ],
            dataReads: [Data(rawMessage.utf8)]
        )
        let client = IMAPSessionClient(transport: transport)

        let source = try await client.loginAndFetchMessageSource(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            uid: 43
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID FETCH 43 (BODY.PEEK[])",
        ])
        #expect(source.uid == 43)
        #expect(source.rawMessage.contains("Subject: Test"))
        #expect(source.rawMessage.contains("Hello from IMAP."))
    }

    @Test("client fetches structured text parts without downloading attachment payloads")
    func clientFetchesStructuredBodyWithoutAttachmentPayloads() async throws {
        let headers = "Authentication-Results: mx.example; dmarc=pass\r\nDisposition-Notification-To: sender@example.org\r\n"
        let plain = "Hello=20plain."
        let html = "PHA+SGVsbG8gaHRtbC48L3A+"
        let bodyStructure = #"* 9 FETCH (UID 43 BODYSTRUCTURE ((("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "QUOTED-PRINTABLE" 14 1)("TEXT" "HTML" ("CHARSET" "UTF-8") NIL NIL "BASE64" 28 1) "ALTERNATIVE")("APPLICATION" "PDF" ("NAME" "report.pdf") NIL NIL "BASE64" 2048 NIL ("ATTACHMENT" ("FILENAME" "report.pdf"))) "MIXED"))"#
        let transport = ScriptedIMAPTransport(
            lines: [
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "A0002 OK [READ-WRITE] SELECT completed",
                bodyStructure,
                "A0003 OK FETCH completed",
                "* 9 FETCH (UID 43 BODY[HEADER] {\(headers.utf8.count)}",
                ")",
                "A0004 OK FETCH completed",
                "* 9 FETCH (UID 43 BODY[1.1] {\(plain.utf8.count)}",
                ")",
                "A0005 OK FETCH completed",
                "* 9 FETCH (UID 43 BODY[1.2] {\(html.utf8.count)}",
                ")",
                "A0006 OK FETCH completed",
            ],
            dataReads: [Data(headers.utf8), Data(plain.utf8), Data(html.utf8)]
        )
        let client = IMAPSessionClient(transport: transport)

        let body = try await client.loginAndFetchMessageBody(
            configuration: Self.configuration(),
            credential: Self.credential(),
            messageID: "INBOX:43",
            folderPath: "INBOX",
            uid: 43
        )

        #expect(body.plainText == "Hello plain.")
        #expect(body.html == "<p>Hello html.</p>")
        #expect(body.authenticationResults == "mx.example; dmarc=pass")
        #expect(body.readReceiptRequest == ReadReceiptRequest(notificationTo: "sender@example.org"))
        #expect(body.attachments.first?.name == "report.pdf")
        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID FETCH 43 (BODYSTRUCTURE)",
            "A0004 UID FETCH 43 (BODY.PEEK[HEADER])",
            "A0005 UID FETCH 43 (BODY.PEEK[1.1])",
            "A0006 UID FETCH 43 (BODY.PEEK[1.2])",
        ])
    }

    @Test("client downloads and decodes one deferred MIME part")
    func clientDownloadsDeferredMIMEPart() async throws {
        let encoded = "SGVsbG8="
        let transport = ScriptedIMAPTransport(
            lines: [
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "A0002 OK [READ-WRITE] SELECT completed",
                "* 9 FETCH (UID 43 BODY[2] {\(encoded.utf8.count)}",
                ")",
                "A0003 OK FETCH completed",
            ],
            dataReads: [Data(encoded.utf8)]
        )
        let client = IMAPSessionClient(transport: transport)

        let data = try await client.loginAndFetchMessagePart(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            uid: 43,
            section: "2",
            transferEncoding: "base64"
        )

        #expect(data == Data("Hello".utf8))
        #expect(await transport.sentLines.last == "A0003 UID FETCH 43 (BODY.PEEK[2])")
    }

    @Test("raw message source preserves body lines that look like fetch terminators")
    func rawMessageSourcePreservesBodyLinesThatLookLikeFetchTerminators() async throws {
        let rawMessage = [
            "Subject: Parenthesis",
            "Content-Type: text/plain; charset=utf-8",
            "",
            "Before",
            ")",
            "After",
        ].joined(separator: "\r\n")
        let transport = ScriptedIMAPTransport(
            lines: [
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "A0002 OK [READ-WRITE] SELECT completed",
                "* 14 FETCH (UID 43 BODY[] {\(rawMessage.utf8.count)}",
                ")",
                "A0003 OK FETCH completed",
            ],
            dataReads: [Data(rawMessage.utf8)]
        )
        let client = IMAPSessionClient(transport: transport)

        let source = try await client.loginAndFetchMessageSource(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            uid: 43
        )

        #expect(source.rawMessage.contains("Before\r\n)\r\nAfter"))
    }

    @Test("raw message source reads literal bytes without treating tagged body lines as completion")
    func rawMessageSourceReadsLiteralBytesWithoutTreatingTaggedBodyLinesAsCompletion() async throws {
        let rawMessage = [
            "Subject: Tagged body",
            "Content-Type: text/plain; charset=utf-8",
            "",
            "Before tagged-looking line",
            "A0003 OK this is part of the message body",
            "After tagged-looking line",
        ].joined(separator: "\r\n")
        let transport = ScriptedIMAPTransport(
            lines: [
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "A0002 OK [READ-WRITE] SELECT completed",
                "* 14 FETCH (UID 43 BODY[] {\(rawMessage.utf8.count)}",
                ")",
                "A0003 OK FETCH completed",
            ],
            dataReads: [Data(rawMessage.utf8)]
        )
        let client = IMAPSessionClient(transport: transport)

        let source = try await client.loginAndFetchMessageSource(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            uid: 43
        )

        #expect(source.rawMessage == rawMessage)
    }

    @Test("legacy source cache remains readable without claiming original-byte fidelity")
    func legacySourceCacheIsRenderingOnly() throws {
        let data = Data(#"{"uid":43,"rawMessage":"Subject: Legacy\r\n\r\nReadable"}"#.utf8)
        let source = try JSONDecoder().decode(IMAPMessageSource.self, from: data)
        #expect(source.uid == 43)
        #expect(source.rawMessage == "Subject: Legacy\r\n\r\nReadable")
        #expect(source.rawMessageData == nil)
    }

    @Test("raw MIME retrieval and cache encoding preserve original non-UTF8 bytes")
    func rawMIMEBytesSurviveFetchAndCache() async throws {
        let raw = Data(("MIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=mail\r\n"
                + "Subject: Original bytes\r\n\r\n--mail\r\nContent-Type: text/plain; charset=iso-8859-1\r\n"
                + "Content-Transfer-Encoding: 8bit\r\n\r\n").utf8)
            + Data([0xE5, 0xF8, 0xE6])
            + Data(("\r\n--mail\r\nContent-Type: application/octet-stream\r\n"
                    + "Content-Disposition: attachment; filename=bytes.bin\r\n"
                    + "Content-Transfer-Encoding: base64\r\n\r\nAAECAwQ=\r\n--mail--\r\n").utf8)
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready", "A0001 OK LOGIN completed", "A0002 OK [READ-WRITE] SELECT completed",
            "* 14 FETCH (UID 43 BODY[] {\(raw.count)}", ")", "A0003 OK FETCH completed"
        ], dataReads: [raw])
        let source = try await IMAPSessionClient(transport: transport).loginAndFetchMessageSource(
            configuration: Self.configuration(), credential: Self.credential(), folderPath: "INBOX", uid: 43
        )
        #expect(source.rawMessageData == raw)
        let cached = try JSONDecoder().decode(IMAPMessageSource.self, from: JSONEncoder().encode(source))
        #expect(cached.rawMessageData == raw)
    }

    @Test("raw message source accepts RFC822 literal labels")
    func rawMessageSourceAcceptsRFC822LiteralLabels() async throws {
        let rawMessage = [
            "Subject: RFC822 literal",
            "Content-Type: text/plain; charset=utf-8",
            "",
            "Hello from an RFC822-labeled literal.",
        ].joined(separator: "\r\n")
        let transport = ScriptedIMAPTransport(
            lines: [
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "A0002 OK [READ-WRITE] SELECT completed",
                "* 14 FETCH (UID 43 RFC822 {\(rawMessage.utf8.count)}",
                ")",
                "A0003 OK FETCH completed",
            ],
            dataReads: [Data(rawMessage.utf8)]
        )
        let client = IMAPSessionClient(transport: transport)

        let source = try await client.loginAndFetchMessageSource(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            uid: 43
        )

        #expect(source.rawMessage == rawMessage)
    }

    @Test("raw message source accepts BODY PEEK literal labels")
    func rawMessageSourceAcceptsBODYPEEKLiteralLabels() async throws {
        let rawMessage = [
            "Subject: BODY PEEK literal",
            "Content-Type: text/plain; charset=utf-8",
            "",
            "Hello from a BODY.PEEK[]-labeled literal.",
        ].joined(separator: "\r\n")
        let transport = ScriptedIMAPTransport(
            lines: [
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "A0002 OK [READ-WRITE] SELECT completed",
                "* 14 FETCH (UID 43 BODY.PEEK[] {\(rawMessage.utf8.count)}",
                ")",
                "A0003 OK FETCH completed",
            ],
            dataReads: [Data(rawMessage.utf8)]
        )
        let client = IMAPSessionClient(transport: transport)

        let source = try await client.loginAndFetchMessageSource(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            uid: 43
        )

        #expect(source.rawMessage == rawMessage)
    }

    @Test("raw message source accepts case-insensitive fetch literal metadata")
    func rawMessageSourceAcceptsCaseInsensitiveFetchLiteralMetadata() async throws {
        let rawMessage = [
            "Subject: Mixed fetch",
            "Content-Type: text/plain; charset=utf-8",
            "",
            "Hello from mixed-case FETCH metadata.",
        ].joined(separator: "\r\n")
        let transport = ScriptedIMAPTransport(
            lines: [
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "A0002 OK [READ-WRITE] SELECT completed",
                "* 14 Fetch (Uid 43 Body[] {\(rawMessage.utf8.count)}",
                ")",
                "A0003 OK FETCH completed",
            ],
            dataReads: [Data(rawMessage.utf8)]
        )
        let client = IMAPSessionClient(transport: transport)

        let source = try await client.loginAndFetchMessageSource(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            uid: 43
        )

        #expect(source.rawMessage == rawMessage)
    }

    @Test("raw message source rejects literal metadata for a prefixed UID")
    func rawMessageSourceRejectsLiteralMetadataForPrefixedUID() async throws {
        let rawMessage = [
            "Subject: Wrong UID",
            "Content-Type: text/plain; charset=utf-8",
            "",
            "This belongs to another UID.",
        ].joined(separator: "\r\n")
        let transport = ScriptedIMAPTransport(
            lines: [
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "A0002 OK [READ-WRITE] SELECT completed",
                "* 14 FETCH (UID 430 BODY[] {\(rawMessage.utf8.count)}",
                "A0003 OK FETCH completed",
            ],
            dataReads: [Data(rawMessage.utf8)]
        )
        let client = IMAPSessionClient(transport: transport)

        await #expect(throws: IMAPClientError.malformedResponse(
            "* 14 FETCH (UID 430 BODY[] {\(rawMessage.utf8.count)}"
        )) {
            try await client.loginAndFetchMessageSource(
                configuration: Self.configuration(),
                credential: Self.credential(),
                folderPath: "INBOX",
                uid: 43
            )
        }
    }

    @Test("raw message source parser accepts case-insensitive fetch metadata")
    func rawMessageSourceParserAcceptsCaseInsensitiveFetchMetadata() throws {
        let source = try #require(IMAPMessageSource.parse([
            "* 14 Fetch (Uid 43 Body[] {55}",
            "Subject: Mixed fetch parser",
            "",
            "Hello from collected response lines.",
            ")",
        ], uid: 43))

        #expect(source.rawMessage == "Subject: Mixed fetch parser\n\nHello from collected response lines.")
    }

    @Test("raw message source parser accepts RFC822 fetch metadata")
    func rawMessageSourceParserAcceptsRFC822FetchMetadata() throws {
        let source = try #require(IMAPMessageSource.parse([
            "* 14 FETCH (UID 43 RFC822 {57}",
            "Subject: RFC822 fetch parser",
            "",
            "Hello from collected RFC822 response lines.",
            ")",
        ], uid: 43))

        #expect(source.rawMessage == "Subject: RFC822 fetch parser\n\nHello from collected RFC822 response lines.")
    }

    @Test("raw message source parser rejects RFC822 size metadata")
    func rawMessageSourceParserRejectsRFC822SizeMetadata() {
        let source = IMAPMessageSource.parse([
            "* 14 FETCH (UID 43 RFC822.SIZE 1024",
            "Subject: Not a full message source",
            "",
            "This should not be treated as raw message source.",
            ")",
        ], uid: 43)

        #expect(source == nil)
    }

    @Test("raw message source decodes legacy eight bit literals")
    func rawMessageSourceDecodesLegacyEightBitLiterals() async throws {
        let rawMessage = [
            "Subject: Legacy receipt",
            "Content-Type: text/plain; charset=iso-8859-1",
            "Content-Transfer-Encoding: 8bit",
            "",
            "Kjære Henrik Øgård",
        ].joined(separator: "\r\n")
        let rawData = try #require(rawMessage.data(using: .isoLatin1))
        let transport = ScriptedIMAPTransport(
            lines: [
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "A0002 OK [READ-WRITE] SELECT completed",
                "* 14 FETCH (UID 43 BODY[] {\(rawData.count)}",
                ")",
                "A0003 OK FETCH completed",
            ],
            dataReads: [rawData]
        )
        let client = IMAPSessionClient(transport: transport)

        let source = try await client.loginAndFetchMessageSource(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            uid: 43
        )

        #expect(source.rawMessage.contains("Kjære Henrik Øgård"))
    }

    @Test("raw message source decodes declared Windows 1252 literals")
    func rawMessageSourceDecodesDeclaredWindows1252Literals() async throws {
        let rawMessage = [
            "Subject: Smart punctuation",
            "Content-Type: text/plain; charset=windows-1252",
            "Content-Transfer-Encoding: 8bit",
            "",
            "It’s ready “now”.",
        ].joined(separator: "\r\n")
        let rawData = try #require(rawMessage.data(using: .windowsCP1252))
        let transport = ScriptedIMAPTransport(
            lines: [
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "A0002 OK [READ-WRITE] SELECT completed",
                "* 14 FETCH (UID 43 BODY[] {\(rawData.count)}",
                ")",
                "A0003 OK FETCH completed",
            ],
            dataReads: [rawData]
        )
        let client = IMAPSessionClient(transport: transport)

        let source = try await client.loginAndFetchMessageSource(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            uid: 43
        )

        #expect(source.rawMessage.contains("It’s ready “now”."))
    }

    @Test("raw message source decodes declared Windows 1251 literals")
    func rawMessageSourceDecodesDeclaredWindows1251Literals() async throws {
        var rawData = Data([
            "Subject: Cyrillic body",
            "Content-Type: text/plain; charset=windows-1251",
            "Content-Transfer-Encoding: 8bit",
            "",
            "",
        ].joined(separator: "\r\n").utf8)
        rawData.append(contentsOf: [0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2])
        let transport = ScriptedIMAPTransport(
            lines: [
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "A0002 OK [READ-WRITE] SELECT completed",
                "* 14 FETCH (UID 43 BODY[] {\(rawData.count)}",
                ")",
                "A0003 OK FETCH completed",
            ],
            dataReads: [rawData]
        )
        let client = IMAPSessionClient(transport: transport)

        let source = try await client.loginAndFetchMessageSource(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            uid: 43
        )

        #expect(source.rawMessage.contains("Привет"))
    }

    @Test("client logs in selects folder and stores message flags")
    func clientLogsInSelectsFolderAndStoresMessageFlags() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed",
            "A0003 OK STORE completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        try await client.loginAndSetMessageFlag(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            uids: [43, 44],
            flag: .seen,
            isEnabled: true
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID STORE 43,44 +FLAGS.SILENT (\\Seen)",
        ])
    }

    @Test("client appends sent message data with seen flag")
    func clientAppendsSentMessageDataWithSeenFlag() async throws {
        let messageData = Data("Subject: Sent\r\n\r\nHello".utf8)
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "+ Ready for literal data",
            "A0002 OK APPEND completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        try await client.loginAndAppendMessage(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "Sent",
            messageData: messageData,
            flags: [.seen]
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 APPEND \"Sent\" (\\Seen) {\(messageData.count)}",
        ])
        #expect(await transport.sentData == [messageData, Data("\r\n".utf8)])
    }

    @Test("client normalizes bare LF line endings to CRLF in APPEND")
    func clientNormalizesBareLFToCRLFInAppend() async throws {
        let messageData = Data("Subject: Sent\n\nHello".utf8)
        let normalized = Data("Subject: Sent\r\n\r\nHello".utf8)
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "+ Ready for literal data",
            "A0002 OK APPEND completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        try await client.loginAndAppendMessage(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "Sent",
            messageData: messageData,
            flags: [.seen]
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 APPEND \"Sent\" (\\Seen) {\(normalized.count)}",
        ])
        #expect(await transport.sentData == [normalized, Data("\r\n".utf8)])
    }

    @Test("client appends draft message data and returns APPENDUID")
    func clientAppendsDraftMessageDataAndReturnsAppendUID() async throws {
        let messageData = Data("Subject: Draft\r\n\r\nHello".utf8)
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "+ Ready for literal data",
            "A0002 OK [APPENDUID 999 42] APPEND completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let result = try await client.loginAndAppendMessage(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "Drafts",
            messageData: messageData,
            flags: [.draft]
        )

        #expect(result == IMAPAppendResult(uidValidity: 999, uid: 42))
        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 APPEND \"Drafts\" (\\Draft) {\(messageData.count)}",
        ])
        #expect(await transport.sentData == [messageData, Data("\r\n".utf8)])
    }

    @Test("move retains COPYUID identities instead of guessing destination IDs")
    func moveRetainsDestinationUIDs() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "* OK [UIDVALIDITY 77] valid",
            "A0002 OK [READ-WRITE] SELECT completed",
            "A0003 OK [COPYUID 91 41:43 81:83] MOVE completed"
        ])
        let client = IMAPSessionClient(transport: transport)
        let result = try await client.loginAndMoveMessagesWithResult(
            configuration: Self.configuration(), credential: Self.credential(),
            sourceFolderPath: "INBOX", uids: [41, 42, 43], destinationFolderPath: "Archive"
        )
        #expect(result.uidValidity == 91)
        #expect(result.uidMappings == [41: 81, 42: 82, 43: 83])
    }

    @Test("a rejected MOVE is not repeated as COPY because it may have partially moved messages")
    func rejectedMoveDoesNotCopyAgain() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK [CAPABILITY IMAP4rev1 UIDPLUS] ready", "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed", "A0003 NO MOVE partially failed",
            "A0004 OK COPY completed", "A0005 OK STORE completed", "A0006 OK EXPUNGE completed"
        ])
        let client = IMAPSessionClient(transport: transport)
        await #expect(throws: IMAPClientError.self) {
            try await client.loginAndMoveMessagesWithResult(
                configuration: Self.configuration(), credential: Self.credential(),
                sourceFolderPath: "INBOX", uids: [43], destinationFolderPath: "Archive"
            )
        }
        #expect(await transport.sentLines.count == 3)
    }

    @Test("move accepts untagged COPYUID and normalizes reverse-written ranges")
    func moveReadsUntaggedMappings() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK ready", "A0001 OK LOGIN completed", "A0002 OK SELECT completed",
            "* OK [COPYUID 91 43:41 83:81] moved", "* 1 EXPUNGE", "A0003 OK MOVE completed"
        ])
        let result = try await IMAPSessionClient(transport: transport).loginAndMoveMessagesWithResult(
            configuration: Self.configuration(), credential: Self.credential(),
            sourceFolderPath: "INBOX", uids: [41, 42, 43], destinationFolderPath: "Archive"
        )
        #expect(result.uidMappings == [41: 81, 42: 82, 43: 83])
    }

    @Test("Undo rejects a replaced mailbox before issuing MOVE")
    func moveValidatesSourceUIDValidity() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK ready", "A0001 OK LOGIN completed", "* OK [UIDVALIDITY 92] valid",
            "A0002 OK SELECT completed", "A0003 OK MOVE completed"
        ])
        let client = IMAPSessionClient(transport: transport)
        await #expect(throws: MailBackendError.self) {
            try await client.loginAndMoveMessagesWithResult(
                configuration: Self.configuration(), credential: Self.credential(),
                sourceFolderPath: "Archive", uids: [81], destinationFolderPath: "INBOX", expectedSourceUIDValidity: 91
            )
        }
        #expect(await transport.sentLines.count == 2)
    }

    @Test("oversized or malformed COPYUID never creates guessed undo targets", arguments: [
        "91 1:4294967295 1:4294967295", "91 43 81:82", "91 99 81", "0 43 81", "91 43,43 81,82"
    ])
    func moveRejectsUnsafeMappings(_ mapping: String) async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK ready", "A0001 OK LOGIN completed", "A0002 OK SELECT completed",
            "A0003 OK [COPYUID \(mapping)] MOVE completed"
        ])
        let result = try await IMAPSessionClient(transport: transport).loginAndMoveMessagesWithResult(
            configuration: Self.configuration(), credential: Self.credential(),
            sourceFolderPath: "INBOX", uids: [43], destinationFolderPath: "Archive"
        )
        #expect(result.uidMappings.isEmpty)
        #expect(result.uidValidity == nil)
    }

    @Test("Undo refreshes UIDVALIDITY even when the source mailbox is already selected")
    func undoMoveReselectsMailbox() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK ready", "A0001 OK LOGIN completed", "* OK [UIDVALIDITY 91] valid",
            "A0002 OK SELECT completed", "A0003 OK MOVE completed",
            "* OK [UIDVALIDITY 92] replaced", "A0004 OK SELECT completed"
        ])
        let client = IMAPSessionClient(transport: transport, reusesAuthenticatedSession: true)
        try await client.loginAndMoveMessages(configuration: Self.configuration(), credential: Self.credential(),
                                              sourceFolderPath: "Archive", uids: [81], destinationFolderPath: "Other")
        await #expect(throws: MailBackendError.self) {
            try await client.loginAndMoveMessagesWithResult(configuration: Self.configuration(), credential: Self.credential(),
                                                            sourceFolderPath: "Archive", uids: [82],
                                                            destinationFolderPath: "INBOX",
                                                            expectedSourceUIDValidity: 91)
        }
        #expect(await transport.sentLines.last == "A0004 SELECT \"Archive\" (CONDSTORE)")
    }

    @Test("client moves messages with UID MOVE")
    func clientMovesMessagesWithUIDMove() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed",
            "A0003 OK MOVE completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        try await client.loginAndMoveMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            sourceFolderPath: "INBOX",
            uids: [43, 44],
            destinationFolderPath: "Archive"
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID MOVE 43,44 \"Archive\"",
        ])
    }

    @Test("client copies messages with UID COPY")
    func clientCopiesMessagesWithUIDCopy() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed",
            "A0003 OK COPY completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        try await client.loginAndCopyMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            sourceFolderPath: "INBOX",
            uids: [43, 44],
            destinationFolderPath: "Archive"
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID COPY 43,44 \"Archive\"",
        ])
    }

    @Test("client falls back to COPY STORE and UID EXPUNGE when UID MOVE is unsupported")
    func clientFallsBackToCopyStoreAndUIDExpungeWhenUIDMoveIsUnsupported() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK [CAPABILITY IMAP4rev1 UIDPLUS] IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed",
            "A0003 BAD UID MOVE unsupported",
            "A0004 OK COPY completed",
            "A0005 OK STORE completed",
            "A0006 OK UID EXPUNGE completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        try await client.loginAndMoveMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            sourceFolderPath: "INBOX",
            uids: [43],
            destinationFolderPath: "Archive"
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID MOVE 43 \"Archive\"",
            "A0004 UID COPY 43 \"Archive\"",
            "A0005 UID STORE 43 +FLAGS.SILENT (\\Deleted)",
            "A0006 UID EXPUNGE 43",
        ])
    }

    @Test("client permanently deletes messages with deleted flag and UID EXPUNGE")
    func clientPermanentlyDeletesMessagesWithDeletedFlagAndUIDExpunge() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK [CAPABILITY IMAP4rev1 UIDPLUS] IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed",
            "A0003 OK STORE completed",
            "A0004 OK UID EXPUNGE completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        try await client.loginAndPermanentlyDeleteMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "Trash",
            uids: [5]
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"Trash\" (CONDSTORE)",
            "A0003 UID STORE 5 +FLAGS.SILENT (\\Deleted)",
            "A0004 UID EXPUNGE 5",
        ])
    }

    @Test("permanent delete refuses servers without UIDPLUS before marking a message deleted")
    func permanentDeleteRefusesServersWithoutUIDPlus() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK [CAPABILITY IMAP4rev1] IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        await #expect(throws: IMAPClientError.commandNotSupported(
            command: "UID EXPUNGE",
            response: "Server did not advertise UIDPLUS."
        )) {
            try await client.loginAndPermanentlyDeleteMessages(
                configuration: Self.configuration(),
                credential: Self.credential(),
                folderPath: "Trash",
                uids: [5]
            )
        }

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"Trash\" (CONDSTORE)",
        ])
        #expect(await transport.sentLines.contains { $0 == "EXPUNGE" } == false)
    }

    @Test("UID EXPUNGE failures never fall back to unscoped EXPUNGE")
    func uidExpungeFailureNeverFallsBackToUnscopedExpunge() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK [CAPABILITY IMAP4rev1 UIDPLUS] IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "A0002 OK [READ-WRITE] SELECT completed",
            "A0003 OK STORE completed",
            "A0004 NO temporary UID EXPUNGE failure",
        ])
        let client = IMAPSessionClient(transport: transport)

        await #expect(throws: IMAPClientError.commandFailed(
            command: "UID EXPUNGE",
            response: "A0004 NO temporary UID EXPUNGE failure"
        )) {
            try await client.loginAndPermanentlyDeleteMessages(
                configuration: Self.configuration(),
                credential: Self.credential(),
                folderPath: "Trash",
                uids: [5]
            )
        }

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"Trash\" (CONDSTORE)",
            "A0003 UID STORE 5 +FLAGS.SILENT (\\Deleted)",
            "A0004 UID EXPUNGE 5",
        ])
        #expect(await transport.sentLines.contains { $0 == "EXPUNGE" } == false)
    }

    @Test("LIST parser handles escaped quoted mailbox names")
    func listParserHandlesEscapedQuotedMailboxNames() throws {
        let folder = try #require(IMAPFolderListing.parse(
            #"* LIST (\HasNoChildren) "/" "Projects/\"Quoted\"""#
        ))

        #expect(folder.path == #"Projects/"Quoted""#)
        #expect(folder.displayName == #""Quoted""#)
        #expect(folder.delimiter == "/")
        #expect(folder.role == .custom)
    }

    @Test("line buffer emits complete CRLF and LF terminated responses")
    func lineBufferEmitsCompleteResponses() throws {
        var buffer = IMAPLineBuffer()

        buffer.append(Data("A0001 O".utf8))
        #expect(buffer.takeLine() == nil)

        buffer.append(Data("K ready\r\n* LIST () \"/\" \"INBOX\"\n".utf8))

        let firstLine = buffer.takeLine()
        let secondLine = buffer.takeLine()

        #expect(firstLine == "A0001 OK ready")
        #expect(secondLine == "* LIST () \"/\" \"INBOX\"")
        #expect(buffer.takeLine() == nil)
    }

    @Test("client upgrades STARTTLS before IMAP login")
    func clientUpgradesSTARTTLSBeforeIMAPLogin() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "* CAPABILITY IMAP4rev1 STARTTLS LOGINDISABLED",
            "A0001 OK CAPABILITY completed",
            "A0002 OK Begin TLS negotiation now",
            "A0003 OK LOGIN completed",
            "* LIST (\\HasNoChildren) \"/\" \"INBOX\"",
            "A0004 OK LIST completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let incoming = MailServerSettings(
            kind: .imap,
            host: "imap.example.org",
            port: 143,
            tlsMode: .startTLS,
            authentication: .password
        )
        _ = try await client.loginAndListFolders(
            configuration: Self.configuration(incoming: incoming),
            credential: Self.credential()
        )

        #expect(await transport.upgradedServers == [incoming])
        #expect(await transport.sentLines == [
            "A0001 CAPABILITY",
            "A0002 STARTTLS",
            "A0003 LOGIN \"person@example.org\" \"secret\"",
            "A0004 LIST \"\" \"*\"",
        ])
    }

    @Test("persistent client reconnects once after transport loss")
    func persistentClientReconnectsOnceAfterTransportLoss() async throws {
        let transport = ScriptedIMAPTransport(
            lines: [
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "* LIST (\\HasNoChildren) \"/\" \"INBOX\"",
                "A0002 OK LIST completed",
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "A0002 OK [READ-WRITE] SELECT completed",
                "* SEARCH 91",
                "A0003 OK SEARCH completed",
                #"* 9 FETCH (UID 91 FLAGS (\Seen) ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" "Receipt" (("GitHub" NIL "noreply" "github.com")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-91@example.org>"))"#,
                "A0004 OK FETCH completed",
            ],
            readFailures: [5: .transport("Connection reset by peer.")]
        )
        let client = IMAPSessionClient(
            transport: transport,
            reusesAuthenticatedSession: true
        )

        _ = try await client.loginAndListFolders(
            configuration: Self.configuration(),
            credential: Self.credential()
        )
        let results = try await client.loginAndSearchMessages(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            query: SearchQuery(text: "receipt")
        )

        #expect(results.map(\.uid) == [91])
        #expect(await transport.connectCount == 2)
        #expect(await transport.disconnectCount == 1)
        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 LIST \"\" \"*\"",
            "A0003 SELECT \"INBOX\" (CONDSTORE)",
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID SEARCH TEXT \"receipt\"",
            "A0004 UID FETCH 91 (FLAGS ENVELOPE BODY.PEEK[TEXT]<0.1024>)",
        ])
    }

    @Test("cancelled command read invalidates the reused session so the next operation logs in again")
    func cancelledCommandReadInvalidatesReusedSession() async throws {
        let transport = ScriptedIMAPTransport(
            lines: [
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "A0002 OK [READ-WRITE] SELECT completed",
            ],
            suspendsWhenOutOfLines: true
        )
        let client = IMAPSessionClient(transport: transport, reusesAuthenticatedSession: true)

        let hungFetch = Task {
            try await client.loginAndFetchMessageBody(
                configuration: Self.configuration(),
                credential: Self.credential(),
                messageID: "INBOX:91",
                folderPath: "INBOX",
                uid: 91
            )
        }
        var sentFetch = false
        for _ in 0 ..< 500 where !sentFetch {
            sentFetch = await transport.sentLines.contains { $0.contains("UID FETCH") }
            if !sentFetch { try await Task.sleep(nanoseconds: 10_000_000) }
        }
        #expect(sentFetch)

        hungFetch.cancel()
        _ = try? await hungFetch.value

        // Cancellation tears the shared transport down out of band; wait for
        // the unstructured teardown task to land before the next operation.
        var disconnected = false
        for _ in 0 ..< 500 where !disconnected {
            disconnected = await transport.disconnectCount >= 1
            if !disconnected { try await Task.sleep(nanoseconds: 10_000_000) }
        }
        #expect(disconnected)

        // The next operation must not assume the authenticated session
        // survived the teardown: it has to reconnect and log in again
        // instead of issuing commands on presumed-live session state.
        await transport.appendLines([
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "* LIST (\\HasNoChildren) \"/\" \"INBOX\"",
            "A0002 OK LIST completed",
        ])
        _ = try await client.loginAndListFolders(
            configuration: Self.configuration(),
            credential: Self.credential()
        )

        #expect(await transport.connectCount == 2)
        let loginCount = await transport.sentLines.filter { $0.contains(" LOGIN ") }.count
        #expect(loginCount == 2)
    }

    @Test("persistent client reconnects when the OAuth secret rotates")
    func persistentClientReconnectsWhenOAuthSecretRotates() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "* LIST (\\HasNoChildren) \"/\" \"INBOX\"",
            "A0002 OK LIST completed",
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "* LIST (\\HasNoChildren) \"/\" \"INBOX\"",
            "A0002 OK LIST completed",
        ])
        let client = IMAPSessionClient(transport: transport, reusesAuthenticatedSession: true)

        _ = try await client.loginAndListFolders(
            configuration: Self.configuration(),
            credential: Self.credential()
        )
        let rotated = MailAccountCredential(
            incomingUsername: "person@example.org",
            outgoingUsername: "person@example.org",
            secret: "rotated-secret",
            authentication: .password
        )
        _ = try await client.loginAndListFolders(
            configuration: Self.configuration(),
            credential: rotated
        )

        #expect(await transport.connectCount == 2)
        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 LIST \"\" \"*\"",
            "A0001 LOGIN \"person@example.org\" \"rotated-secret\"",
            "A0002 LIST \"\" \"*\"",
        ])
    }

    @Test("persistent client does not replay an ambiguous copy after transport loss")
    func persistentClientDoesNotReplayAmbiguousCopy() async throws {
        let transport = ScriptedIMAPTransport(
            lines: [
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "A0002 OK [READ-WRITE] SELECT completed",
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "A0002 OK [READ-WRITE] SELECT completed",
                "A0003 OK COPY completed",
            ],
            readFailures: [4: .transport("Connection reset after COPY.")]
        )
        let client = IMAPSessionClient(
            transport: transport,
            reusesAuthenticatedSession: true
        )

        await #expect(throws: IMAPClientError.transport("Connection reset after COPY.")) {
            try await client.loginAndCopyMessages(
                configuration: Self.configuration(),
                credential: Self.credential(),
                sourceFolderPath: "INBOX",
                uids: [91],
                destinationFolderPath: "Archive"
            )
        }

        #expect(await transport.connectCount == 1)
        #expect(await transport.disconnectCount == 1)
        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID COPY 91 \"Archive\"",
        ])
    }

    @Test("client refuses STARTTLS when the server does not advertise it")
    func clientRefusesSTARTTLSWhenNotAdvertised() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "* CAPABILITY IMAP4rev1 LOGINDISABLED",
            "A0001 OK CAPABILITY completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let incoming = MailServerSettings(
            kind: .imap,
            host: "imap.example.org",
            port: 143,
            tlsMode: .startTLS,
            authentication: .password
        )

        await #expect(throws: IMAPClientError.unsupportedTLSMode(.startTLS)) {
            try await client.loginAndListFolders(
                configuration: Self.configuration(incoming: incoming),
                credential: Self.credential()
            )
        }
        // Must not have upgraded nor sent a LOGIN.
        #expect(await transport.upgradedServers.isEmpty)
        #expect(await transport.sentLines == ["A0001 CAPABILITY"])
    }

    @Test("client enters IDLE and leaves with DONE after bounded events")
    func clientEntersIDLEAndLeavesWithDONEAfterBoundedEvents() async throws {
        let transport = ScriptedIMAPTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "* 23 EXISTS",
            "A0002 OK [READ-WRITE] SELECT completed",
            "+ idling",
            "* 24 EXISTS",
            "* 2 EXPUNGE",
            "A0003 OK IDLE completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let stream = await client.loginAndIdleEvents(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX",
            stopAfterEventCount: 2
        )
        var iterator = stream.makeAsyncIterator()

        let first = try await iterator.next()
        let second = try await iterator.next()
        let end = try await iterator.next()

        #expect(first == .exists(count: 24))
        #expect(second == .expunged(sequenceNumber: 2))
        #expect(end == nil)
        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 IDLE",
            "DONE",
        ])
    }

    @Test("IDLE lifetime timeout closes the transport before the reader can leak")
    func idleLifetimeTimeoutClosesTransport() async throws {
        let transport = ScriptedIMAPTransport(
            lines: [
                "* OK IMAP4rev1 ready",
                "A0001 OK LOGIN completed",
                "* 23 EXISTS",
                "A0002 OK [READ-WRITE] SELECT completed",
                "+ idling",
            ],
            suspendsWhenOutOfLines: true
        )
        let client = IMAPSessionClient(
            transport: transport,
            responseTimeoutNanoseconds: 1_000_000_000,
            idleMaximumDurationNanoseconds: 1_000_000
        )

        let stream = await client.loginAndIdleEvents(
            configuration: Self.configuration(),
            credential: Self.credential(),
            folderPath: "INBOX"
        )
        var iterator = stream.makeAsyncIterator()

        await #expect(throws: IMAPClientError.transport("Timed out waiting for IMAP IDLE response.")) {
            _ = try await iterator.next()
        }
        #expect(await transport.disconnectCount >= 1)
    }

    @Test("IDLE parser recognizes mailbox count and flag changes")
    func idleParserRecognizesMailboxCountAndFlagChanges() throws {
        #expect(IMAPIdleEvent.parse("* 24 EXISTS") == .exists(count: 24))
        #expect(IMAPIdleEvent.parse("* 1 RECENT") == .recent(count: 1))
        #expect(IMAPIdleEvent.parse("* 2 EXPUNGE") == .expunged(sequenceNumber: 2))
        #expect(IMAPIdleEvent.parse("* 7 FETCH (FLAGS (\\Seen))") == .flagsChanged(sequenceNumber: 7))
        #expect(IMAPIdleEvent.parse("A0003 OK IDLE completed") == nil)
    }

    private static func configuration(
        incoming: MailServerSettings = MailServerSettings(
            kind: .imap,
            host: "imap.example.org",
            port: 993,
            tlsMode: .implicit,
            authentication: .password
        )
    ) -> IMAPAccountConfiguration {
        IMAPAccountConfiguration(
            accountID: "imap-smtp:person@example.org",
            emailAddress: "person@example.org",
            displayName: "Person",
            incoming: incoming,
            outgoing: MailServerSettings(
                kind: .smtp,
                host: "smtp.example.org",
                port: 587,
                tlsMode: .startTLS,
                authentication: .password
            ),
            credentialID: "imap-smtp:person@example.org"
        )
    }

    private static func credential() -> MailAccountCredential {
        MailAccountCredential(
            incomingUsername: "person@example.org",
            outgoingUsername: "person@example.org",
            secret: "secret",
            authentication: .password
        )
    }
}

private actor ScriptedIMAPTransport: IMAPSessionTransport {
    private var lines: [String]
    private var dataReads: [Data]
    private var readFailures: [Int: IMAPClientError]
    private var readCount = 0
    private var writes: [String] = []
    private var dataWrites: [Data] = []
    private var server: MailServerSettings?
    private var tlsUpgrades: [MailServerSettings] = []
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
    private let suspendsWhenOutOfLines: Bool

    init(
        lines: [String],
        dataReads: [Data] = [],
        readFailures: [Int: IMAPClientError] = [:],
        suspendsWhenOutOfLines: Bool = false
    ) {
        self.lines = lines
        self.dataReads = dataReads
        self.readFailures = readFailures
        self.suspendsWhenOutOfLines = suspendsWhenOutOfLines
    }

    var sentLines: [String] {
        writes
    }

    var sentData: [Data] {
        dataWrites
    }

    var connectedServer: MailServerSettings? {
        server
    }

    var upgradedServers: [MailServerSettings] {
        tlsUpgrades
    }

    func connect(to server: MailServerSettings) async throws {
        self.server = server
        connectCount += 1
        #expect(server.host == "imap.example.org")
    }

    func readLine() async throws -> String {
        readCount += 1
        if let failure = readFailures.removeValue(forKey: readCount) {
            throw failure
        }
        if lines.isEmpty, suspendsWhenOutOfLines {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
        guard !lines.isEmpty else {
            throw IMAPClientError.malformedResponse("No scripted IMAP response.")
        }
        return lines.removeFirst()
    }

    func readData(maxLength: Int) async throws -> Data {
        _ = maxLength
        guard !dataReads.isEmpty else {
            throw IMAPClientError.malformedResponse("No scripted IMAP data response.")
        }
        return dataReads.removeFirst()
    }

    func writeLine(_ line: String) async throws {
        writes.append(line)
    }

    func writeData(_ data: Data) async throws {
        dataWrites.append(data)
    }

    func upgradeToTLS(server: MailServerSettings) async throws {
        tlsUpgrades.append(server)
    }

    func disconnect() async {
        disconnectCount += 1
    }

    /// Extends the script after the fact — for tests that interrupt one
    /// operation mid-read and then drive a follow-up operation.
    func appendLines(_ newLines: [String]) {
        lines.append(contentsOf: newLines)
    }
}
