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

@Suite("Gmail labels (X-GM-EXT-1)")
struct GmailLabelsTests {
    // MARK: - Capability detection

    @Test("server capabilities parse from greeting, tagged OK, and untagged CAPABILITY lines")
    func serverCapabilitiesParseFromResponseLines() {
        let greeting = IMAPServerCapabilities.parse(
            responseLine: "* OK [CAPABILITY IMAP4rev1 IDLE X-GM-EXT-1] Gimap ready"
        )
        #expect(greeting?.supportsGmailExtensions == true)
        #expect(greeting?.contains("idle") == true)

        let taggedOK = IMAPServerCapabilities.parse(
            responseLine: "A0001 OK [CAPABILITY IMAP4rev1 UNSELECT IDLE NAMESPACE QUOTA ID XLIST CHILDREN "
                + "X-GM-EXT-1 UIDPLUS ENABLE MOVE CONDSTORE ESEARCH UTF8=ACCEPT] person@example.org authenticated (Success)"
        )
        #expect(taggedOK?.supportsGmailExtensions == true)
        #expect(taggedOK?.contains("CONDSTORE") == true)
        #expect(taggedOK?.supportsUIDPlus == true)

        let untagged = IMAPServerCapabilities.parse(
            responseLine: "* CAPABILITY IMAP4rev1 STARTTLS AUTH=PLAIN"
        )
        #expect(untagged?.supportsGmailExtensions == false)
        #expect(untagged?.supportsUIDPlus == false)
        #expect(untagged?.contains("STARTTLS") == true)

        #expect(IMAPServerCapabilities.parse(responseLine: "A0001 OK LOGIN completed") == nil)
        #expect(IMAPServerCapabilities.parse(responseLine: "* 12 FETCH (UID 42 FLAGS (\\Seen))") == nil)
    }

    @Test("listing page reports Gmail label support and adds X-GM-LABELS to FETCH when advertised")
    func listingFetchesLabelsWhenServerAdvertisesGmailExtension() async throws {
        let transport = ScriptedGmailTransport(lines: [
            "* OK Gimap ready for requests",
            "A0001 OK [CAPABILITY IMAP4rev1 UNSELECT IDLE NAMESPACE X-GM-EXT-1 UIDPLUS MOVE CONDSTORE] authenticated (Success)",
            "* 23 EXISTS",
            "* OK [UIDVALIDITY 987654321] UIDs valid",
            "A0002 OK [READ-WRITE] SELECT completed",
            "* SEARCH 42",
            "A0003 OK SEARCH completed",
            #"* 12 FETCH (UID 42 X-GM-LABELS ("\\Inbox" "\\Important" Work "Foo Bar" "&AOk-t&AOk-") FLAGS (\Seen) ENVELOPE ("Fri, 05 Jun 2026 10:00:00 +0000" "First" (("Ada Lovelace" NIL "ada" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-42@example.org>") BODY[TEXT]<0> {5}"#,
            ")",
            "A0004 OK FETCH completed",
        ], dataReads: [Data("Hello".utf8)])
        let client = IMAPSessionClient(transport: transport)

        let page = try await client.loginAndListMessages(
            configuration: Self.configuration,
            credential: Self.credential,
            folderPath: "INBOX",
            limit: 2
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            "A0003 UID SEARCH ALL",
            "A0004 UID FETCH 42 (FLAGS ENVELOPE X-GM-LABELS BODY.PEEK[TEXT]<0.1024>)",
        ])
        #expect(page.supportsGmailLabels)
        #expect(page.messages.first?.labels == ["\\Inbox", "\\Important", "Work", "Foo Bar", "été"])
    }

    @Test("listing keeps the plain FETCH attribute set without X-GM-EXT-1")
    func listingKeepsPlainFetchWithoutGmailExtension() async throws {
        let transport = ScriptedGmailTransport(lines: [
            "* OK IMAP4rev1 ready",
            "A0001 OK LOGIN completed",
            "* 23 EXISTS",
            "A0002 OK [READ-WRITE] SELECT completed",
            "* SEARCH",
            "A0003 OK SEARCH completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        let page = try await client.loginAndListMessages(
            configuration: Self.configuration,
            credential: Self.credential,
            folderPath: "INBOX",
            limit: 2
        )

        #expect(!page.supportsGmailLabels)
        #expect(await transport.sentLines.count == 3)
    }

    // MARK: - X-GM-LABELS parsing

    @Test("message listing parses X-GM-LABELS system and user labels")
    func messageListingParsesLabels() throws {
        let line = #"* 5 FETCH (UID 7 FLAGS (\Seen) X-GM-LABELS (\Inbox "\\Starred" "Receipts/2026" Personal) "#
            + #"ENVELOPE ("Fri, 05 Jun 2026 10:00:00 +0000" "Subject" (("Ada" NIL "ada" "example.org")) NIL NIL "#
            + #"((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-7@example.org>"))"#
        let listing = try #require(IMAPMessageListing.parse(line))
        #expect(listing.labels == ["\\Inbox", "\\Starred", "Receipts/2026", "Personal"])
        #expect(listing.isRead)
    }

    @Test("message listing without X-GM-LABELS has no labels")
    func messageListingWithoutLabelsIsEmpty() throws {
        let line = #"* 5 FETCH (UID 7 FLAGS (\Seen) ENVELOPE ("Fri, 05 Jun 2026 10:00:00 +0000" "Subject" "#
            + #"(("Ada" NIL "ada" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-7@example.org>"))"#
        let listing = try #require(IMAPMessageListing.parse(line))
        #expect(listing.labels.isEmpty)
    }

    @Test("empty X-GM-LABELS list parses as no labels")
    func emptyLabelListParses() throws {
        let line = #"* 5 FETCH (UID 7 X-GM-LABELS () FLAGS (\Seen) ENVELOPE ("Fri, 05 Jun 2026 10:00:00 +0000" "Subject" "#
            + #"(("Ada" NIL "ada" "example.org")) NIL NIL ((NIL NIL "person" "example.org")) NIL NIL NIL "<msg-7@example.org>"))"#
        let listing = try #require(IMAPMessageListing.parse(line))
        #expect(listing.labels.isEmpty)
    }

    // MARK: - STORE rendering

    @Test("label STORE command renders system labels as atoms and user labels as quoted modified UTF-7")
    func labelStoreCommandRenders() throws {
        let add = try IMAPSessionClient.storeLabelsCommand(
            uids: [43, 44],
            labels: ["\\Starred", "Work", "Foo Bar", "été"],
            isEnabled: true
        )
        #expect(add == #"UID STORE 43,44 +X-GM-LABELS (\Starred "Work" "Foo Bar" "&AOk-t&AOk-")"#)

        let remove = try IMAPSessionClient.storeLabelsCommand(
            uids: [43],
            labels: ["Work"],
            isEnabled: false
        )
        #expect(remove == #"UID STORE 43 -X-GM-LABELS ("Work")"#)
    }

    @Test("client stores Gmail labels with UID STORE")
    func clientStoresGmailLabels() async throws {
        let transport = ScriptedGmailTransport(lines: [
            "* OK Gimap ready",
            "A0001 OK [CAPABILITY IMAP4rev1 X-GM-EXT-1] authenticated",
            "A0002 OK [READ-WRITE] SELECT completed",
            "A0003 OK STORE completed",
        ])
        let client = IMAPSessionClient(transport: transport)

        try await client.loginAndSetMessageLabels(
            configuration: Self.configuration,
            credential: Self.credential,
            folderPath: "INBOX",
            uids: [43],
            labels: ["Work"],
            isEnabled: true
        )

        #expect(await transport.sentLines == [
            "A0001 LOGIN \"person@example.org\" \"secret\"",
            "A0002 SELECT \"INBOX\" (CONDSTORE)",
            #"A0003 UID STORE 43 +X-GM-LABELS ("Work")"#,
        ])
    }

    // MARK: - Domain model

    @Test("message header decodes without labels and round-trips labels")
    func messageHeaderLabelsCodable() throws {
        let legacy = """
        {"id":"INBOX:1","threadID":"<m@x>","folderID":"INBOX","from":{"email":"a@x"},"to":[],"cc":[],"bcc":[],
        "subject":"S","snippet":"","date":0,"isRead":false,"isFlagged":false,"isAnswered":false,"isForwarded":false,
        "hasAttachments":false}
        """
        let decoded = try JSONDecoder().decode(MessageHeader.self, from: Data(legacy.utf8))
        #expect(decoded.labels.isEmpty)

        let header = MessageHeader(
            id: "INBOX:2",
            threadID: "<m2@x>",
            folderID: "INBOX",
            from: Correspondent(email: "a@x"),
            subject: "S",
            snippet: "",
            date: Date(timeIntervalSince1970: 1),
            labels: ["\\Inbox", "Work"]
        )
        let data = try JSONEncoder().encode(header)
        let roundTripped = try JSONDecoder().decode(MessageHeader.self, from: data)
        #expect(roundTripped.labels == ["\\Inbox", "Work"])
        #expect(roundTripped == header)
    }

    @Test("folder cache snapshot decodes without Gmail label support flag")
    func folderSnapshotDecodesWithoutLabelFlag() throws {
        let legacy = #"{"folders":[],"folderDelimitersByID":{}}"#
        let snapshot = try JSONDecoder().decode(IMAPFolderCacheSnapshot.self, from: Data(legacy.utf8))
        #expect(!snapshot.supportsGmailLabels)

        let flagged = IMAPFolderCacheSnapshot(folders: [], supportsGmailLabels: true)
        let data = try JSONEncoder().encode(flagged)
        #expect(try JSONDecoder().decode(IMAPFolderCacheSnapshot.self, from: data).supportsGmailLabels)
    }

    @Test("pending label mutation describes itself and dedups per label set")
    func pendingLabelMutationDescription() {
        let add = PendingMutation(kind: .setLabels(["Work"], isEnabled: true), messageIDs: ["INBOX:1"])
        let remove = PendingMutation(kind: .setLabels(["Work"], isEnabled: false), messageIDs: ["INBOX:1"])
        #expect(add.kind.operationDescription == "Add label Work")
        #expect(remove.kind.operationDescription == "Remove label Work")
        #expect(add.dedupKey == remove.dedupKey)
    }

    // MARK: - Backend

    @Test("backend advertises labels after a listing reports X-GM-EXT-1 and maps labels into headers")
    func backendAdvertisesLabelsAfterListing() async throws {
        let folderCache = InMemoryIMAPFolderSnapshotCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [Self.inboxListing] },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(
                    messages: [Self.listing(uid: 42, labels: ["\\Inbox", "Work"])],
                    supportsGmailLabels: true
                )
            },
            folderCache: folderCache
        )
        #expect(!backend.capabilities.contains(.labels))

        try await backend.connect()
        let folder = try #require(try await backend.folders().first)
        let page = try await backend.messages(in: folder, pageToken: nil)

        #expect(backend.capabilities.contains(.labels))
        #expect(page.headers.first?.labels == ["\\Inbox", "Work"])
        #expect(await folderCache.snapshot(accountID: Self.account.id)?.supportsGmailLabels == true)
    }

    @Test("backend restores label capability from the persisted folder snapshot")
    func backendRestoresLabelCapabilityFromFolderSnapshot() async throws {
        let folderCache = InMemoryIMAPFolderSnapshotCache(snapshotsByAccount: [
            Self.account.id: IMAPFolderCacheSnapshot(
                folders: [Folder(id: "INBOX", name: "INBOX", role: .inbox)],
                supportsGmailLabels: true
            ),
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [Self.inboxListing] },
            folderCache: folderCache
        )

        try await backend.connect()

        #expect(backend.capabilities.contains(.labels))
        #expect(await folderCache.snapshot(accountID: Self.account.id)?.supportsGmailLabels == true)
    }

    @Test("label service stores labels through the IMAP operation and updates cached headers")
    func labelServiceStoresLabelsAndUpdatesCache() async throws {
        let recorder = LabelOperationRecorder()
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [Self.inboxListing] },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(
                    messages: [Self.listing(uid: 42, labels: ["\\Inbox"])],
                    supportsGmailLabels: true
                )
            },
            setMessageLabels: { _, _, folderID, uids, labels, isEnabled in
                await recorder.record(folderID: folderID, uids: uids, labels: labels, isEnabled: isEnabled)
            },
            headerCache: headerCache
        )
        try await backend.connect()
        let folder = try #require(try await backend.folders().first)
        _ = try await backend.messages(in: folder, pageToken: nil)

        let service = try #require(backend.extensionService(MessageLabelManaging.self))
        try await service.setLabels(["Work"], isEnabled: true, for: ["INBOX:42"], sourceID: nil)

        #expect(await recorder.calls == [LabelCall(folderID: "INBOX", uids: [42], labels: ["Work"], isEnabled: true)])
        let cached = try #require(await headerCache.snapshot(accountID: Self.account.id, folderID: "INBOX"))
        #expect(cached.headers.first?.labels == ["\\Inbox", "Work"])

        try await service.setLabels(["\\Inbox"], isEnabled: false, for: ["INBOX:42"], sourceID: nil)
        let afterRemoval = try #require(await headerCache.snapshot(accountID: Self.account.id, folderID: "INBOX"))
        #expect(afterRemoval.headers.first?.labels == ["Work"])
    }

    @Test("label mutation refreshes an expired XOAUTH2 credential and retries once")
    func labelMutationRefreshesExpiredOAuthCredential() async throws {
        let expiredCredential = MailAccountCredential(
            incomingUsername: Self.account.emailAddress,
            outgoingUsername: Self.account.emailAddress,
            secret: "expired-access-token",
            authentication: .xoauth2
        )
        let refreshedCredential = MailAccountCredential(
            incomingUsername: Self.account.emailAddress,
            outgoingUsername: Self.account.emailAddress,
            secret: "fresh-access-token",
            authentication: .xoauth2
        )
        let recorder = OAuthMutationRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: expiredCredential,
            listFolders: { _, _ in [Self.inboxListing] },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(
                    messages: [Self.listing(uid: 42, labels: ["\\Inbox"])],
                    supportsGmailLabels: true
                )
            },
            setMessageLabels: { _, credential, _, _, _, _ in
                await recorder.record(credential)
                if credential == expiredCredential {
                    throw IMAPClientError.authenticationFailed("expired token")
                }
            },
            refreshOAuthCredential: { _, _, credential in
                await recorder.recordRefresh(credential)
                return refreshedCredential
            }
        )
        try await backend.connect()
        let folder = try #require(try await backend.folders().first)
        _ = try await backend.messages(in: folder, pageToken: nil)

        let service = try #require(backend.extensionService(MessageLabelManaging.self))
        try await service.setLabels(["Work"], isEnabled: true, for: ["INBOX:42"], sourceID: nil)

        #expect(await recorder.credentials == [expiredCredential, refreshedCredential])
        #expect(await recorder.refreshCount == 1)
        #expect(await recorder.refreshInputs == [expiredCredential])
    }

    @Test("read and flag mutations preserve cached Gmail labels")
    func readAndFlagMutationsPreserveCachedLabels() async throws {
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [Self.inboxListing] },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(
                    messages: [Self.listing(uid: 42, labels: ["\\Inbox", "Work"])],
                    supportsGmailLabels: true
                )
            },
            setMessageFlag: { _, _, _, _, _, _ in },
            headerCache: headerCache
        )

        try await backend.connect()
        let folder = try #require(try await backend.folders().first)
        _ = try await backend.messages(in: folder, pageToken: nil)

        try await backend.setRead(true, for: ["INBOX:42"])
        try await backend.setFlagged(true, for: ["INBOX:42"])

        let cached = try #require(await headerCache.snapshot(accountID: Self.account.id, folderID: "INBOX"))
        #expect(cached.headers.first?.isRead == true)
        #expect(cached.headers.first?.isFlagged == true)
        #expect(cached.headers.first?.labels == ["\\Inbox", "Work"])
    }

    @Test("label service is unavailable without a label operation")
    func labelServiceUnavailableWithoutOperation() {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] }
        )
        #expect(backend.extensionService(MessageLabelManaging.self) == nil)
    }

    // MARK: - Fixtures

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

    private static let inboxListing = IMAPFolderListing(
        path: "INBOX",
        displayName: "INBOX",
        delimiter: "/",
        flags: [],
        role: .inbox
    )

    private static func listing(uid: Int, labels: [String]) -> IMAPMessageListing {
        IMAPMessageListing(
            uid: uid,
            messageID: "<msg-\(uid)@example.org>",
            subject: "Subject \(uid)",
            from: Correspondent(email: "ada@example.org"),
            to: [Correspondent(email: "person@example.org")],
            cc: [],
            bcc: [],
            date: Date(timeIntervalSince1970: TimeInterval(uid)),
            isRead: false,
            isFlagged: false,
            isAnswered: false,
            labels: labels
        )
    }
}

private struct LabelCall: Equatable {
    let folderID: String
    let uids: [Int]
    let labels: [String]
    let isEnabled: Bool
}

private actor LabelOperationRecorder {
    private(set) var calls: [LabelCall] = []

    func record(folderID: String, uids: [Int], labels: [String], isEnabled: Bool) {
        calls.append(LabelCall(folderID: folderID, uids: uids, labels: labels, isEnabled: isEnabled))
    }
}

private actor OAuthMutationRecorder {
    private(set) var credentials: [MailAccountCredential] = []
    private(set) var refreshInputs: [MailAccountCredential] = []
    private(set) var refreshCount = 0

    func record(_ credential: MailAccountCredential) {
        credentials.append(credential)
    }

    func recordRefresh(_ credential: MailAccountCredential) {
        refreshInputs.append(credential)
        refreshCount += 1
    }
}

private actor ScriptedGmailTransport: IMAPSessionTransport {
    private var lines: [String]
    private var dataReads: [Data]
    private var writes: [String] = []

    init(lines: [String], dataReads: [Data] = []) {
        self.lines = lines
        self.dataReads = dataReads
    }

    var sentLines: [String] { writes }

    func connect(to server: MailServerSettings) async throws {
        _ = server
    }

    func readLine() async throws -> String {
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
        _ = data
    }

    func upgradeToTLS(server: MailServerSettings) async throws {
        _ = server
    }

    func disconnect() async {}
}
