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

@Suite("LocalMessageWorkflowConversationCache")
@MainActor
struct LocalMessageWorkflowConversationCacheTests {
    private let account = BrevAccount(id: "acct-1", displayName: "Test", emailAddress: "user@example.org")
    private let inbox = Folder(id: "Inbox", name: "Inbox", role: .inbox)
    private let archive = Folder(id: "Archive", name: "Archive", role: .archive)

    @Test("cache scan includes selected uncached anchor and unloaded cross-folder parent")
    func scanIncludesUncachedAnchorAndUnloadedParent() async throws {
        let source = MailSourceID(accountID: account.id, mailboxID: "personal")
        let anchor = Self.header(id: "anchor", folder: inbox.id, rfcID: "anchor@example.org")
        let parent = Self.header(id: "archive-parent", folder: archive.id, rfcID: "parent@example.org")
        let backend = makeBackend(source: source, inboxHeaders: [], archiveHeaders: [parent])

        let candidates = try await LocalMessageWorkflowConversationCache.candidates(
            backend: backend,
            sourceID: source,
            folders: [inbox, archive],
            anchors: [anchor],
            isCurrent: { true }
        )

        #expect(candidates.map(\.header.id).sorted() == ["anchor", "archive-parent"])
        #expect(candidates.allSatisfy { $0.sourceID == source })
    }

    @Test("cache scan rejects a failed mailbox read without returning a partial graph")
    func failedCacheReadThrows() async {
        let source = MailSourceID(accountID: account.id, mailboxID: "missing-mailbox")
        let backend = makeBackend(
            source: .init(accountID: account.id, mailboxID: "personal"),
            inboxHeaders: [],
            archiveHeaders: []
        )
        var failed = false

        do {
            _ = try await LocalMessageWorkflowConversationCache.candidates(
                backend: backend,
                sourceID: source,
                folders: [inbox, archive],
                anchors: [],
                isCurrent: { true }
            )
        } catch {
            failed = true
        }

        #expect(failed)
    }

    @Test("a source lifetime change after a cache await rejects the response")
    func staleCacheResponseIsRejected() async {
        let source = MailSourceID(accountID: account.id, mailboxID: "personal")
        let backend = makeBackend(source: source, inboxHeaders: [], archiveHeaders: [])
        var currentChecks = 0
        var cancelled = false

        do {
            _ = try await LocalMessageWorkflowConversationCache.candidates(
                backend: backend,
                sourceID: source,
                folders: [inbox],
                anchors: [],
                isCurrent: {
                    currentChecks += 1
                    return currentChecks == 1
                }
            )
        } catch is CancellationError {
            cancelled = true
        } catch {}

        #expect(cancelled)
        #expect(currentChecks == 2)
    }

    private func makeBackend(
        source: MailSourceID,
        inboxHeaders: [MessageHeader],
        archiveHeaders: [MessageHeader]
    ) -> MockBackend {
        let mailbox = Mailbox(id: source.mailboxID, email: account.emailAddress, displayName: "Test", isPrimary: true)
        return MockBackend(
            account: account,
            folders: [inbox, archive],
            messagesByFolder: [inbox.id: inboxHeaders, archive.id: archiveHeaders],
            mailboxes: [mailbox]
        )
    }

    private static func header(id: String, folder: String, rfcID: String) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "same-provider-thread",
            folderID: folder,
            from: Correspondent(email: "sender@example.org"),
            subject: "Same subject",
            snippet: "",
            date: Date(timeIntervalSince1970: 100),
            messageID: rfcID
        )
    }
}
