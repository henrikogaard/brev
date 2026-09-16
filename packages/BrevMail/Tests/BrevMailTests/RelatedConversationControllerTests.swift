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

// Session consent grants are process-wide state, so this suite runs
// serialized — a grant from a parallel test would otherwise leak into
// consent assertions here.
@Suite("Related conversation controller", .serialized)
@MainActor
struct RelatedConversationControllerTests {
    @Test("cached snapshot merges a cross-folder member into the thread")
    func cachedSnapshotMergesCrossFolderMember() async throws {
        let store = try makeConsentStore()
        let controller = RelatedConversationController(consentStore: store.store)
        let backend = MockBackend(
            account: Self.account,
            extendedCapabilities: [.cachedConversations]
        )
        backend.cachedConversationHandler = { anchor, _ in
            try Self.snapshot(
                anchor: anchor,
                members: [
                    anchor,
                    Self.member(id: "sent-1", folderID: "Sent", day: 2)
                ]
            )
        }

        controller.updateAnchor(
            header: Self.header(id: "inbox-1", folderID: "INBOX"),
            sourceID: Self.source,
            backend: backend
        )
        await controller.awaitSettled()

        let merged = controller.mergedThreadHeaders(loaded: [
            Self.header(id: "inbox-1", folderID: "INBOX")
        ])
        #expect(merged.map(\.id) == ["inbox-1", "sent-1"])
        #expect(merged.last?.folderID == "Sent")
        #expect(controller.snapshot?.coverage == .cached)
        #expect(!controller.isLoadingRemote)
    }

    @Test("remote discovery never runs without consent, even when advertised")
    func remoteDiscoveryRequiresConsent() async throws {
        let store = try makeConsentStore()
        let controller = RelatedConversationController(consentStore: store.store)
        let remoteCalls = RemoteCallRecorder()
        let backend = MockBackend(
            account: Self.account,
            extendedCapabilities: [.cachedConversations, .relatedConversationLoading]
        )
        backend.cachedConversationHandler = { anchor, _ in
            try Self.snapshot(anchor: anchor, members: [anchor])
        }
        backend.relatedConversationHandler = { anchor, _, _, _ in
            await remoteCalls.record()
            return try Self.snapshot(anchor: anchor, members: [anchor], coverage: .completeForScope)
        }

        controller.updateAnchor(
            header: Self.header(id: "inbox-1", folderID: "INBOX"),
            sourceID: Self.source,
            backend: backend
        )
        await controller.awaitSettled()

        #expect(controller.canLoadRelated)
        #expect(await remoteCalls.count == 0)
        #expect(controller.snapshot?.coverage == .cached)
    }

    @Test("explicit action grants session consent and resolves remote members")
    func explicitActionLoadsRemoteMembers() async throws {
        let store = try makeConsentStore()
        let controller = RelatedConversationController(consentStore: store.store)
        let remoteCalls = RemoteCallRecorder()
        let backend = MockBackend(
            account: Self.account,
            extendedCapabilities: [.cachedConversations, .relatedConversationLoading]
        )
        backend.cachedConversationHandler = { anchor, _ in
            try Self.snapshot(anchor: anchor, members: [anchor])
        }
        backend.relatedConversationHandler = { anchor, includeSpam, _, onUpdate in
            await remoteCalls.record()
            let partial = try Self.snapshot(anchor: anchor, members: [
                anchor,
                Self.member(id: "sent-1", folderID: "Sent", day: 2)
            ], coverage: .partial, unavailableFolderIDs: ["Archive"])
            await onUpdate(partial)
            return try Self.snapshot(anchor: anchor, members: [
                anchor,
                Self.member(id: "sent-1", folderID: "Sent", day: 2),
                Self.member(id: "archive-1", folderID: "Archive", day: 3)
            ], coverage: .completeForScope)
        }

        controller.updateAnchor(
            header: Self.header(id: "inbox-1", folderID: "INBOX"),
            sourceID: Self.source,
            backend: backend
        )
        await controller.awaitSettled()
        #expect(await remoteCalls.count == 0)

        controller.loadRelatedMail()
        await controller.awaitSettled()

        #expect(await remoteCalls.count == 1)
        #expect(controller.snapshot?.coverage == .completeForScope)
        #expect(controller.snapshot?.members.map(\.header.id) == ["inbox-1", "sent-1", "archive-1"])
        // The session grant does not become a stored preference.
        #expect(!store.store.isAutoLoadEnabled(accountID: Self.account.id))
    }

    @Test("persistent consent auto-loads remote members on anchor change")
    func autoLoadConsentTriggersRemoteLookup() async throws {
        let store = try makeConsentStore()
        store.store.setAutoLoadEnabled(true, accountID: Self.account.id)
        let controller = RelatedConversationController(consentStore: store.store)
        let remoteCalls = RemoteCallRecorder()
        let backend = MockBackend(
            account: Self.account,
            extendedCapabilities: [.cachedConversations, .relatedConversationLoading]
        )
        backend.relatedConversationHandler = { anchor, _, _, _ in
            await remoteCalls.record()
            return try Self.snapshot(anchor: anchor, members: [anchor], coverage: .completeForScope)
        }

        controller.updateAnchor(
            header: Self.header(id: "inbox-1", folderID: "INBOX"),
            sourceID: Self.source,
            backend: backend
        )
        await controller.awaitSettled()

        #expect(await remoteCalls.count == 1)
        #expect(controller.snapshot?.coverage == .completeForScope)
    }

    @Test("a new anchor rejects stale remote updates")
    func staleUpdatesRejectedAfterAnchorChange() async throws {
        let store = try makeConsentStore()
        store.store.setAutoLoadEnabled(true, accountID: Self.account.id)
        let controller = RelatedConversationController(consentStore: store.store)
        let gate = RemoteCallGate()
        let calls = RemoteCallRecorder()
        let backend = MockBackend(
            account: Self.account,
            extendedCapabilities: [.relatedConversationLoading]
        )
        backend.relatedConversationHandler = { anchor, _, _, _ in
            let call = await calls.record()
            if call == 1 {
                await gate.waitForRelease()
                return try Self.snapshot(anchor: anchor, members: [
                    anchor,
                    Self.member(id: "stale-1", folderID: "Sent", day: 2)
                ], coverage: .completeForScope)
            }
            return try Self.snapshot(anchor: anchor, members: [
                anchor,
                Self.member(id: "other-2", folderID: "Sent", day: 5)
            ], coverage: .completeForScope)
        }

        controller.updateAnchor(
            header: Self.header(id: "inbox-1", folderID: "INBOX"),
            sourceID: Self.source,
            backend: backend
        )
        await gate.waitForStart()
        controller.updateAnchor(
            header: Self.header(id: "other-1", folderID: "INBOX", day: 4),
            sourceID: Self.source,
            backend: backend
        )
        await gate.release()
        await controller.awaitSettled()

        #expect(controller.snapshot?.members.map(\.header.id).contains("stale-1") != true)
        #expect(controller.snapshot?.anchor.messageID == "other-1")
    }

    @Test("include Spam and Trash refetches with the wider scope")
    func includeSpamAndTrashRefetches() async throws {
        let store = try makeConsentStore()
        let controller = RelatedConversationController(consentStore: store.store)
        let scopes = ScopeRecorder()
        let backend = MockBackend(
            account: Self.account,
            extendedCapabilities: [.cachedConversations]
        )
        backend.cachedConversationHandler = { anchor, includeSpam in
            await scopes.record(includeSpam)
            return try Self.snapshot(
                anchor: anchor,
                members: [anchor],
                excludedFolderIDs: includeSpam ? [] : ["Junk"]
            )
        }

        controller.updateAnchor(
            header: Self.header(id: "inbox-1", folderID: "INBOX"),
            sourceID: Self.source,
            backend: backend
        )
        await controller.awaitSettled()
        #expect(controller.snapshot?.excludedFolderIDs == ["Junk"])

        controller.includeSpamAndTrash()
        await controller.awaitSettled()

        #expect(controller.includesSpamAndTrash)
        #expect(await scopes.values == [false, true])
        #expect(controller.snapshot?.excludedFolderIDs.isEmpty == true)
    }

    @Test("a failed remote lookup reports failure and retries cleanly")
    func failedLookupReportsAndRetries() async throws {
        let store = try makeConsentStore()
        let controller = RelatedConversationController(consentStore: store.store)
        let remoteCalls = RemoteCallRecorder()
        let backend = MockBackend(
            account: Self.account,
            extendedCapabilities: [.relatedConversationLoading]
        )
        backend.relatedConversationHandler = { anchor, _, _, _ in
            let call = await remoteCalls.record()
            if call == 1 { throw ConversationLookupError.invalidSnapshot }
            return try Self.snapshot(anchor: anchor, members: [anchor], coverage: .completeForScope)
        }

        controller.updateAnchor(
            header: Self.header(id: "inbox-1", folderID: "INBOX"),
            sourceID: Self.source,
            backend: backend
        )
        await controller.awaitSettled()

        controller.loadRelatedMail()
        await controller.awaitSettled()
        #expect(controller.remoteLoadDidFail)

        controller.retry()
        await controller.awaitSettled()
        #expect(!controller.remoteLoadDidFail)
        #expect(controller.snapshot?.coverage == .completeForScope)
        #expect(await remoteCalls.count == 2)
    }

    // MARK: - Fixtures

    private static let account = BrevAccount(
        id: "account-1",
        displayName: "Personal",
        emailAddress: "me@example.org"
    )
    private static let source = MailSourceID(accountID: account.id, mailboxID: "mailbox-1")

    private nonisolated static func header(id: String, folderID: String, day: Int = 1) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-1",
            folderID: folderID,
            from: Correspondent(email: "sender@example.org"),
            to: [],
            subject: "Topic",
            snippet: "",
            date: Date(timeIntervalSince1970: TimeInterval(day * 86400))
        )
    }

    private nonisolated static func member(id: String, folderID: String, day: Int) -> ConversationMember {
        ConversationMember(sourceID: source, header: header(id: id, folderID: folderID, day: day))
    }

    private nonisolated static func snapshot(
        anchor: ConversationMember,
        members: [ConversationMember],
        coverage: ConversationCoverage = .cached,
        excludedFolderIDs: [Folder.ID] = [],
        unavailableFolderIDs: [Folder.ID] = []
    ) throws -> ConversationSnapshot {
        try ConversationSnapshot(
            anchor: anchor.location,
            members: members,
            coverage: coverage,
            excludedFolderIDs: excludedFolderIDs,
            unavailableFolderIDs: unavailableFolderIDs
        )
    }

    private struct ConsentFixture {
        let store: RelatedConversationConsentStore
    }

    private func makeConsentStore() throws -> ConsentFixture {
        let name = "RelatedConversationControllerTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return ConsentFixture(store: RelatedConversationConsentStore(defaults: defaults))
    }
}

private actor RemoteCallRecorder {
    private(set) var count = 0
    @discardableResult
    func record() -> Int {
        count += 1
        return count
    }
}

private actor ScopeRecorder {
    private(set) var values: [Bool] = []
    func record(_ value: Bool) {
        values.append(value)
    }
}

private actor RemoteCallGate {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var released = false

    func waitForRelease() async {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        guard !released else { return }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitForStart() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() async {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
