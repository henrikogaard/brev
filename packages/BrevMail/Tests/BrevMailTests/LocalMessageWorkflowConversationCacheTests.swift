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

    @Test("local folder headers feed the conversation snooze cache scan")
    func localFolderHeadersFeedConversationScan() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-snooze-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = LocalMailBackend(store: LocalMaildirStore(rootURL: root))
        try await backend.connect()
        let inboxFolder = try await backend.createFolder(name: "Inbox", parentID: nil)
        let archiveFolder = try await backend.createFolder(name: "Archive", parentID: nil)
        let anchorID = try await backend.importRaw(Data("""
        From: sender@example.org
        Subject: Reply
        Message-ID: <reply@example.org>
        In-Reply-To: <parent@example.org>

        Reply body
        """.utf8), into: inboxFolder)
        let parentID = try await backend.importRaw(Data("""
        From: sender@example.org
        Subject: Original
        Message-ID: <parent@example.org>

        Original body
        """.utf8), into: archiveFolder)
        let anchor = try #require(try await backend.messages(in: inboxFolder, pageToken: nil).headers.first)
        let source = MailSourceID(accountID: backend.account.id, mailboxID: LocalMailBackend.accountID)

        let candidates = try await LocalMessageWorkflowConversationCache.candidates(
            backend: backend,
            sourceID: source,
            folders: [inboxFolder, archiveFolder],
            anchors: [anchor],
            isCurrent: { true }
        )

        #expect(anchor.id == anchorID)
        #expect(candidates.contains { $0.header.id == parentID && $0.sourceID == source })
    }

    @Test("an uncached anchor with a duplicate provider ID in another folder is retained")
    func uncachedAnchorUsesFolderAwareIdentity() async throws {
        let source = MailSourceID(accountID: account.id, mailboxID: "personal")
        let cached = Self.header(id: "duplicate", folder: inbox.id, rfcID: "cached@example.org")
        let anchor = Self.header(id: "duplicate", folder: archive.id, rfcID: "anchor@example.org")
        let backend = makeBackend(source: source, inboxHeaders: [cached], archiveHeaders: [])

        let candidates = try await LocalMessageWorkflowConversationCache.candidates(
            backend: backend, sourceID: source, folders: [inbox, archive], anchors: [anchor], isCurrent: { true }
        )

        #expect(Set(candidates.map(\.header.folderID)) == Set([inbox.id, archive.id]))
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

    @Test("a replaced backend is rejected after a cache read suspends")
    func replacementBackendDuringSuspendedCacheReadIsRejected() async {
        let source = MailSourceID(accountID: account.id, mailboxID: "personal")
        let original = makeBackend(source: source, inboxHeaders: [], archiveHeaders: [])
        let replacement = makeBackend(source: source, inboxHeaders: [], archiveHeaders: [])
        let provider = CurrentBackendProvider([original])
        let gate = CacheReadSuspender()
        original.cachedMessageHeadersHandler = { _, _ in
            await gate.suspend()
            return []
        }
        let originalIdentity = ObjectIdentifier(original)

        let task = Task { @MainActor in
            do {
                _ = try await LocalMessageWorkflowConversationCache.candidates(
                    backend: original,
                    sourceID: source,
                    folders: [inbox],
                    anchors: [],
                    isCurrent: {
                        LocalMessageWorkflowSnoozeOwnership.isCurrentBackend(
                            backendIdentity: originalIdentity,
                            sourceID: source,
                            in: provider.backends
                        )
                    }
                )
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }

        await gate.waitUntilSuspended()
        provider.backends = [replacement]
        await gate.resume()

        #expect(await task.value)
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

@MainActor
private final class CurrentBackendProvider {
    var backends: [any MailBackend]

    init(_ backends: [any MailBackend]) {
        self.backends = backends
    }
}

private actor CacheReadSuspender {
    private var isSuspended = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        isSuspended = true
        startedContinuation?.resume()
        startedContinuation = nil
        await withCheckedContinuation { resumeContinuation = $0 }
    }

    func waitUntilSuspended() async {
        guard !isSuspended else { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}
