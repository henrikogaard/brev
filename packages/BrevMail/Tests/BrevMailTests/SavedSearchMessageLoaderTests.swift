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
import BrevSettings
import Foundation
import Testing

@Suite("Saved search cached folders")
struct SavedSearchMessageLoaderTests {
    @Test("searches cached folders with mailbox ownership and honors sent/trash exclusions")
    func cacheScope() async throws {
        let account = BrevAccount(id: "account", displayName: "Account", emailAddress: "test@example.com")
        let folders = [Folder(id: "inbox", name: "Inbox", role: .inbox),
                       Folder(id: "archive", name: "Archive", role: .archive),
                       Folder(id: "sent", name: "Sent", role: .sent),
                       Folder(id: "trash", name: "Trash", role: .trash)]
        let backend = StubSearchBackend(account: account)
        for mailboxID in ["work", "private"] {
            let mailbox = Mailbox(id: mailboxID, email: "test@example.com", displayName: mailboxID, isPrimary: true)
            let section = MailSourceSection(id: .init(accountID: account.id, mailboxID: mailboxID),
                                            account: account, mailbox: mailbox, folders: folders)
            let query = SmartMailbox.SavedQuery(text: "invoice", includeTrash: false, includeSent: false)
            let items = try await SavedSearchMessageLoader.load(section: section, backend: backend, query: query)
            #expect(items.map(\.folder.id) == ["inbox", "archive"])
            #expect(items.map(\.header.id) == [mailboxID + ":inbox", mailboxID + ":archive"])
            #expect(items.allSatisfy { $0.sourceID == section.id })
        }
    }

    @Test("label aliases keep one message and retain the folder that matches the rule")
    func duplicateFolderMembership() async throws {
        let account = BrevAccount(id: "account", displayName: "Account", emailAddress: "test@example.com")
        let mailbox = Mailbox(id: "work", email: "test@example.com", displayName: "Work", isPrimary: true)
        let source = MailSourceID(accountID: account.id, mailboxID: mailbox.id)
        let section = MailSourceSection(id: source, account: account, mailbox: mailbox,
                                        folders: [Folder(id: "inbox", name: "Inbox", role: .inbox),
                                                  Folder(id: "archive", name: "Archive", role: .archive)])
        let query = SmartMailbox.SavedQuery(text: "", conditions: [
            .init(field: .folder, comparison: .equals, value: "archive", sourceID: source)
        ])
        let items = try await SavedSearchMessageLoader.load(section: section,
                                                            backend: StubSearchBackend(account: account, duplicateIDs: true),
                                                            query: query)
        #expect(items.count == 1)
        #expect(items.first?.folder.id == "archive")
        #expect(items.first.map { query.matches($0.header, sourceID: $0.sourceID) } == true)
    }
}

private final class StubSearchBackend: MailBackend, @unchecked Sendable {
    let account: BrevAccount
    let capabilities: BackendCapabilities = []
    let duplicateIDs: Bool
    init(account: BrevAccount, duplicateIDs: Bool = false) {
        self.account = account
        self.duplicateIDs = duplicateIDs
    }

    func connect() async throws {}
    func disconnect() async {}
    func folders() async throws -> [Folder] { [] }
    func refresh(folder _: Folder) async throws {}
    func messages(in _: Folder, pageToken _: String?) async throws -> (
        headers: [MessageHeader],
        nextPageToken: String?
    ) {
        Issue.record("Saved views must not use provider-backed message loading")
        return ([], nil)
    }

    func messages(in folder: Folder, sourceID: MailSourceID, pageToken: String?) async throws -> (
        headers: [MessageHeader], nextPageToken: String?
    ) {
        let headers = try await search(SearchQuery(folderID: folder.id, execution: .cacheOnly), sourceID: sourceID)
        return (headers, nil)
    }

    func body(for messageID: String) async throws -> MessageBody { MessageBody(messageID: messageID) }
    func setRead(_: Bool, for _: [String]) async throws {}
    func setFlagged(_: Bool, for _: [String]) async throws {}
    func move(messageIDs _: [String], to _: Folder) async throws {}
    func delete(messageIDs _: [String]) async throws {}
    func save(draft: Draft) async throws -> Draft { draft }
    func discard(draftID _: String) async throws {}
    func send(draft _: Draft) async throws -> SendResult { SendResult(sentMessageID: "sent") }
    func search(_: SearchQuery) async throws -> [MessageHeader] {
        Issue.record("Saved view lost mailbox ownership")
        return []
    }

    func search(_ query: SearchQuery, sourceID: MailSourceID) async throws -> [MessageHeader] {
        #expect(query.execution == .cacheOnly)
        let folder = try #require(query.folderID)
        return [MessageHeader(
            id: duplicateIDs ? "shared" : sourceID.mailboxID + ":" + folder,
            threadID: "thread",
            folderID: folder,
            from: .init(email: "test@example.com"),
            subject: "Invoice",
            snippet: "",
            date: Date(timeIntervalSince1970: 0)
        )]
    }

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
