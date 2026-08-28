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

@Suite("DetachedWindowResolver")
struct DetachedWindowResolverTests {
    // MARK: Fixtures

    private func account(_ id: String) -> BrevAccount {
        BrevAccount(id: id, displayName: id, emailAddress: "\(id)@example.org")
    }

    private func sourceID(account: String, mailbox: String = "mbx") -> MailSourceID {
        MailSourceID(accountID: account, mailboxID: mailbox)
    }

    private func folder(_ id: String) -> Folder {
        Folder(id: id, name: id, role: .custom)
    }

    private func header(_ id: String, folderID: String) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: id,
            folderID: folderID,
            from: Correspondent(email: "from@example.org"),
            subject: "Subject \(id)",
            snippet: "snippet",
            date: Date(timeIntervalSince1970: 0)
        )
    }

    /// A `CachedMessageHeaderProviding` whose per-folder cache is seeded at
    /// construction. Returns `nil` for any (messageID, folderID) not seeded.
    private struct StubHeaderProvider: CachedMessageHeaderProviding {
        let headersByFolder: [Folder.ID: [MessageHeader.ID: MessageHeader]]

        func cachedMessageHeader(messageID: MessageHeader.ID, folderID: Folder.ID) async -> MessageHeader? {
            headersByFolder[folderID]?[messageID]
        }
    }

    // MARK: resolveBackend

    @Test("matches the backend whose account id equals the source's account id")
    func matchesBySourceAccountID() {
        let backends: [any MailBackend] = [
            MockBackend(account: account("a1")),
            MockBackend(account: account("a2"))
        ]
        let resolved = DetachedWindowResolver.resolveBackend(
            sourceID: sourceID(account: "a2"),
            in: backends
        )
        #expect(resolved?.account.id == "a2")
    }

    @Test("falls back to the first backend when the source id is nil")
    func nilSourceFallsBackToFirst() {
        let backends: [any MailBackend] = [
            MockBackend(account: account("a1")),
            MockBackend(account: account("a2"))
        ]
        #expect(DetachedWindowResolver.resolveBackend(sourceID: nil, in: backends)?.account.id == "a1")
    }

    @Test("falls back to the first backend when no account matches the source id")
    func unmatchedSourceFallsBackToFirst() {
        let backends: [any MailBackend] = [
            MockBackend(account: account("a1")),
            MockBackend(account: account("a2"))
        ]
        let resolved = DetachedWindowResolver.resolveBackend(
            sourceID: sourceID(account: "absent"),
            in: backends
        )
        #expect(resolved?.account.id == "a1")
    }

    @Test("returns nil when there are no backends")
    func emptyBackendsReturnsNil() {
        #expect(DetachedWindowResolver.resolveBackend(sourceID: nil, in: []) == nil)
    }

    // MARK: resolveHeader(using:)

    @Test("returns the cached header from the folder that holds it")
    func headerFoundInFolder() async {
        let target = header("m1", folderID: "inbox")
        let provider = StubHeaderProvider(headersByFolder: ["inbox": ["m1": target]])
        let resolved = await DetachedWindowResolver.resolveHeader(
            messageID: "m1",
            using: provider,
            folders: [folder("inbox")]
        )
        #expect(resolved == target)
    }

    @Test("keeps scanning past folders that miss and finds a later folder's header")
    func headerFoundInLaterFolder() async {
        let target = header("m1", folderID: "archive")
        let provider = StubHeaderProvider(headersByFolder: ["archive": ["m1": target]])
        let resolved = await DetachedWindowResolver.resolveHeader(
            messageID: "m1",
            using: provider,
            folders: [folder("inbox"), folder("archive")]
        )
        #expect(resolved == target)
    }

    @Test("returns the first folder's header when the message exists in several folders")
    func firstFolderWins() async {
        let inboxCopy = header("m1", folderID: "inbox")
        let archiveCopy = header("m1", folderID: "archive")
        let provider = StubHeaderProvider(headersByFolder: [
            "inbox": ["m1": inboxCopy],
            "archive": ["m1": archiveCopy]
        ])
        let resolved = await DetachedWindowResolver.resolveHeader(
            messageID: "m1",
            using: provider,
            folders: [folder("inbox"), folder("archive")]
        )
        #expect(resolved == inboxCopy)
    }

    @Test("returns nil when no folder holds the message")
    func headerNotInAnyFolder() async {
        let provider = StubHeaderProvider(headersByFolder: ["inbox": ["other": header("other", folderID: "inbox")]])
        let resolved = await DetachedWindowResolver.resolveHeader(
            messageID: "m1",
            using: provider,
            folders: [folder("inbox"), folder("archive")]
        )
        #expect(resolved == nil)
    }

    @Test("returns nil when the backend has no cached-header provider")
    func nilProviderReturnsNil() async {
        let resolved = await DetachedWindowResolver.resolveHeader(
            messageID: "m1",
            using: nil,
            folders: [folder("inbox")]
        )
        #expect(resolved == nil)
    }

    // MARK: resolveHeader(in:) — backend convenience

    @Test("the backend convenience returns nil when the backend vends no provider")
    func backendWithoutProviderReturnsNil() async {
        let backend = MockBackend(account: account("a1"))
        let resolved = await DetachedWindowResolver.resolveHeader(
            messageID: "m1",
            in: backend,
            folders: [folder("inbox")]
        )
        #expect(resolved == nil)
    }

    // MARK: resolveSenderSections

    @Test("builds one sender section per mailbox, scoped to the backend's account")
    func senderSectionsPerMailbox() async {
        let acct = account("a1")
        let backend = MockBackend(
            account: acct,
            mailboxes: [
                Mailbox(id: "primary", email: "a1@example.org", displayName: "A One", isPrimary: true),
                Mailbox(id: "alias", email: "alias@example.org", displayName: "Alias")
            ]
        )

        let sections = await DetachedWindowResolver.resolveSenderSections(in: backend)

        #expect(sections.map(\.id) == [
            MailSourceID(accountID: "a1", mailboxID: "primary"),
            MailSourceID(accountID: "a1", mailboxID: "alias")
        ])
        #expect(sections.allSatisfy { $0.account.id == "a1" })
        #expect(sections.map(\.mailbox.email) == ["a1@example.org", "alias@example.org"])
    }
}
