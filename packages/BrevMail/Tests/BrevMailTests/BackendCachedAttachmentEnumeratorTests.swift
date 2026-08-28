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

@Suite("BackendCachedAttachmentEnumerator")
struct BackendCachedAttachmentEnumeratorTests {
    private static func account(_ id: String) -> BrevAccount {
        BrevAccount(id: id, displayName: id, emailAddress: "\(id)@example.org")
    }

    private static func source(_ accountID: String, folders: [Folder]) -> MailSourceSection {
        let account = account(accountID)
        let mailbox = Mailbox(
            id: accountID,
            email: account.emailAddress,
            displayName: account.displayName,
            isPrimary: true
        )
        return MailSourceSection(
            id: MailSourceID(accountID: accountID, mailboxID: accountID),
            account: account,
            mailbox: mailbox,
            folders: folders
        )
    }

    private static func attachmentMessage(
        folder: Folder,
        headerID: String
    ) -> CachedAttachmentMessage {
        let header = MessageHeader(
            id: headerID,
            threadID: headerID,
            folderID: folder.id,
            from: Correspondent(email: "sender@example.org"),
            to: [Correspondent(email: "me@example.org")],
            subject: "Subject \(headerID)",
            snippet: "Snippet",
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let body = MessageBody(
            messageID: headerID,
            attachments: [
                Attachment(id: "\(headerID)-a1", name: "report.pdf", mimeType: "application/pdf", sizeBytes: 10),
            ]
        )
        return CachedAttachmentMessage(folder: folder, header: header, body: body)
    }

    @Test("maps each backend's cached messages into sources with folder name and id")
    func mapsCachedMessages() async {
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let archive = Folder(id: "ARCHIVE", name: "Archive", role: .archive)
        let sectionA = Self.source("a", folders: [inbox])
        let sectionB = Self.source("b", folders: [archive])

        let backendA = StubAttachmentBackend(
            account: sectionA.account,
            messages: [Self.attachmentMessage(folder: inbox, headerID: "INBOX:1")]
        )
        let backendB = StubAttachmentBackend(account: sectionB.account, messages: [])

        let enumerator = BackendCachedAttachmentEnumerator(
            backends: [backendA, backendB],
            sourceSections: [sectionA, sectionB]
        )

        let sources = await enumerator.cachedMessagesWithBodies()

        #expect(sources.count == 1)
        #expect(sources.first?.sourceID == sectionA.id)
        #expect(sources.first?.folderName == "Inbox")
        #expect(sources.first?.header.id == "INBOX:1")
        #expect(sources.first?.body.attachments.first?.name == "report.pdf")
        // The backend is asked for exactly the section's folders.
        #expect(backendA.requestedFolderIDs == [["INBOX"]])
    }

    @Test("skips source sections that have no matching backend")
    func skipsSectionsWithoutBackend() async {
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let orphan = Self.source("missing", folders: [inbox])

        let enumerator = BackendCachedAttachmentEnumerator(
            backends: [],
            sourceSections: [orphan]
        )

        let sources = await enumerator.cachedMessagesWithBodies()
        #expect(sources.isEmpty)
    }
}

/// Minimal `MailBackend` test double returning canned cached attachment
/// messages. Only the required protocol surface is implemented; the rest is
/// supplied by `MailBackend`'s default implementations.
private final class StubAttachmentBackend: MailBackend, @unchecked Sendable {
    let account: BrevAccount
    let capabilities: BackendCapabilities = []
    private let messages: [CachedAttachmentMessage]
    private let lock = NSLock()
    private var _requestedFolderIDs: [[Folder.ID]] = []

    init(account: BrevAccount, messages: [CachedAttachmentMessage]) {
        self.account = account
        self.messages = messages
    }

    var requestedFolderIDs: [[Folder.ID]] {
        lock.withLock { _requestedFolderIDs }
    }

    func cachedAttachmentMessages(in folders: [Folder]) async -> [CachedAttachmentMessage] {
        lock.withLock {
            _requestedFolderIDs.append(folders.map(\.id))
        }
        return messages
    }

    func connect() async throws {}
    func disconnect() async {}
    func folders() async throws -> [Folder] { [] }
    func refresh(folder _: Folder) async throws {}
    func messages(in _: Folder, pageToken _: String?) async throws -> (
        headers: [MessageHeader],
        nextPageToken: String?
    ) { ([], nil) }
    func body(for messageID: String) async throws -> MessageBody { MessageBody(messageID: messageID) }
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
