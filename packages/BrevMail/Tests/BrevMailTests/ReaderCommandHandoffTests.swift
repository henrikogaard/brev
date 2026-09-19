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

@Suite("Reader command handoff")
@MainActor
struct ReaderCommandHandoffTests {
    @Test("source folders replace another account before a reader mutation can run")
    func sourceContextPrecedesMutation() {
        let navigation = MailNavigationState()
        let source = MailSourceID(accountID: "a", mailboxID: "a")
        let other = MailSourceID(accountID: "b", mailboxID: "b")
        navigation.selectFolder("b-inbox", in: other)
        let inbox = Folder(id: "a-inbox", name: "Inbox", role: .inbox)
        let trash = Folder(id: "a-trash", name: "Trash", role: .trash)
        let section = MailSourceSection(id: source,
                                        account: BrevAccount(id: "a", displayName: "A", emailAddress: "a@example.org"),
                                        mailbox: Mailbox(id: "a", email: "a@example.org", displayName: "A", isPrimary: true),
                                        folders: [inbox, trash])
        let header = MessageHeader(id: "message", threadID: "thread", folderID: inbox.id,
                                   from: Correspondent(email: "fixture@example.org"),
                                   subject: "Subject", snippet: "Preview", date: .distantPast)
        var ownerFolders = [Folder(id: "b-inbox", name: "Inbox", role: .inbox)]
        let prepared = ReaderCommandSourceHandoff.prepare(
            .init(command: .delete, header: header, sourceID: source),
            navigation: navigation, sections: [section], applySection: { ownerFolders = $0.folders }
        )
        #expect(prepared)
        #expect(navigation.selectedSourceID == source)
        #expect(navigation.selectedFolderID == inbox.id)
        #expect(ownerFolders.first { $0.role == .trash }?.id == "a-trash")
        #expect(!MailUndoableDelete.isPermanentDelete(from: inbox, folders: ownerFolders))

        let missingSource = MailSourceID(accountID: "missing", mailboxID: "missing")
        #expect(!ReaderCommandSourceHandoff.prepare(
            .init(command: .delete, header: header, sourceID: missingSource),
            navigation: navigation, sections: [section], applySection: { ownerFolders = $0.folders }
        ))
        #expect(navigation.selectedSourceID == source)
        #expect(ownerFolders == section.folders)
    }

    @Test("two window handoffs keep their source and command separate and execute once")
    func independentWindows() throws {
        let header = MessageHeader(id: "same-id", threadID: "thread", folderID: "inbox",
                                   from: Correspondent(email: "fixture@example.org"),
                                   subject: "Private subject", snippet: "Private preview", date: .distantPast)
        let firstSource = MailSourceID(accountID: "first", mailboxID: "personal")
        let secondSource = MailSourceID(accountID: "second", mailboxID: "work")
        let first = ReaderCommandHandoff.enqueue(.init(command: .delete, header: header, sourceID: firstSource))
        let second = ReaderCommandHandoff.enqueue(.init(command: .move, header: header, sourceID: secondSource))
        let data = try JSONEncoder().encode(first)
        let encoded = try #require(String(data: data, encoding: .utf8))
        #expect(!encoded.contains("Private"))
        #expect(!encoded.contains("same-id"))
        let restored = try JSONDecoder().decode(ReaderCommandWindowPayload.self, from: data)
        let firstRequest = try #require(ReaderCommandHandoff.take(restored))
        #expect(firstRequest.command == .delete)
        #expect(firstRequest.sourceID == firstSource)
        #expect(ReaderCommandHandoff.take(first) == nil)
        let secondRequest = try #require(ReaderCommandHandoff.take(second))
        #expect(secondRequest.command == .move)
        #expect(secondRequest.sourceID == secondSource)
        #expect(ReaderCommandHandoff.take(second) == nil)
    }
}
