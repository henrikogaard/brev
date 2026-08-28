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

// MARK: - Helpers

/// A minimal `MailBackend` spy that records which folder IDs were passed
/// to `refresh(folder:)`. All other protocol requirements are stubs.
private class RefreshSpyBackend: MailBackend, @unchecked Sendable {
    let account: BrevAccount
    let capabilities: BackendCapabilities = []

    /// Folders this backend reports.
    private let stubbedFolders: [Folder]
    /// Accumulated folder IDs from `refresh(folder:)` calls.
    private(set) var refreshedFolderIDs: [String] = []
    /// Accumulated source IDs from source-scoped refresh calls.
    private(set) var refreshedSourceIDs: [MailSourceID] = []
    /// When `true`, `folders()` throws instead of returning data.
    private let failFolderFetch: Bool

    init(
        account: BrevAccount = BrevAccount(id: "spy", displayName: "Spy", emailAddress: "spy@example.com"),
        folders: [Folder],
        failFolderFetch: Bool = false
    ) {
        self.account = account
        stubbedFolders = folders
        self.failFolderFetch = failFolderFetch
    }

    func connect() async throws {}
    func disconnect() async {}

    func folders() async throws -> [Folder] {
        if failFolderFetch { throw MailBackendError.network(underlying: "stubbed failure") }
        return stubbedFolders
    }

    func refresh(folder: Folder) async throws {
        refreshedFolderIDs.append(folder.id)
    }

    func refresh(folder: Folder, in sourceID: MailSourceID) async throws {
        refreshedSourceIDs.append(sourceID)
        refreshedFolderIDs.append(folder.id)
    }

    // Remaining required-but-untested stubs ---

    func currentMailbox() async throws -> Mailbox {
        Mailbox(id: account.id, email: account.emailAddress, displayName: account.displayName, isPrimary: true)
    }

    func switchMailbox(id: String) async throws {}

    func messages(in folder: Folder, pageToken: String?) async throws
        -> (headers: [MessageHeader], nextPageToken: String?) { ([], nil) }

    func body(for messageID: String) async throws -> MessageBody {
        MessageBody(messageID: messageID)
    }

    func setRead(_ isRead: Bool, for messageIDs: [String]) async throws {}
    func setFlagged(_ isFlagged: Bool, for messageIDs: [String]) async throws {}
    func move(messageIDs: [String], to folder: Folder) async throws {}
    func delete(messageIDs: [String]) async throws {}
    func save(draft: Draft) async throws -> Draft { draft }
    func discard(draftID: String) async throws {}

    func send(draft: Draft) async throws -> SendResult {
        SendResult()
    }

    func search(_ query: SearchQuery) async throws -> [MessageHeader] { [] }
    func calendarEvent(from attachmentID: String) async throws -> CalendarEvent {
        throw MailBackendError.notSupported(capabilities)
    }

    func replyToCalendarInvite(messageID: String, response: AttendeeState) async throws {}
    func subscribeToChanges() -> AsyncStream<MailEvent> { AsyncStream { $0.finish() } }
    func sourceID(for mailbox: Mailbox) -> MailSourceID {
        MailSourceID(accountID: account.id, mailboxID: mailbox.id)
    }

    func extensionService<Service>(_ type: Service.Type) -> Service? {
        _ = type
        return nil
    }
}

private final class BackgroundRefreshingSpyBackend: RefreshSpyBackend, MailboxBackgroundRefreshing, @unchecked Sendable {
    private(set) var refreshedMailboxSourceIDs: [MailSourceID] = []

    func refreshMailbox(for sourceID: MailSourceID) async throws {
        refreshedMailboxSourceIDs.append(sourceID)
    }

    override func extensionService<Service>(_ type: Service.Type) -> Service? {
        if ObjectIdentifier(type) == ObjectIdentifier(MailboxBackgroundRefreshing.self) {
            return self as? Service
        }
        return super.extensionService(type)
    }
}

private final class ScheduledSendSpyBackend: RefreshSpyBackend, ScheduledSendManaging, @unchecked Sendable {
    private(set) var deliverDueCallCount = 0

    func pendingScheduledSends() -> [PendingScheduledSend] { [] }

    func deliverDueScheduledSends() async {
        deliverDueCallCount += 1
    }

    override func extensionService<Service>(_ type: Service.Type) -> Service? {
        if ObjectIdentifier(type) == ObjectIdentifier(ScheduledSendManaging.self) {
            return self as? Service
        }
        return super.extensionService(type)
    }
}

private final class FailingSourceRefreshBackend: RefreshSpyBackend, @unchecked Sendable {
    override func refresh(folder _: Folder, in _: MailSourceID) async throws {
        throw MailBackendError.network(underlying: "stubbed source refresh failure")
    }
}

// MARK: - Tests

@Suite("MailFetchScheduler background refresh")
struct MailFetchSchedulerBackgroundTests {
    /// Helper: a minimal folder set with an inbox.
    private static func foldersWithInbox(inboxID: String = "inbox") -> [Folder] {
        [
            Folder(id: inboxID, name: "Inbox", role: .inbox),
            Folder(id: "sent", name: "Sent", role: .sent)
        ]
    }

    @Test("refreshes the inbox folder for a connected backend")
    func refreshesInboxForConnectedBackend() async {
        let backend = RefreshSpyBackend(folders: Self.foldersWithInbox())
        await MailFetchScheduler.performBackgroundRefresh(backends: [backend])
        #expect(backend.refreshedFolderIDs == ["inbox"])
    }

    @Test("prefers mailbox background refresh service when available")
    func prefersMailboxBackgroundRefreshServiceWhenAvailable() async {
        let backend = BackgroundRefreshingSpyBackend(folders: Self.foldersWithInbox())

        await MailFetchScheduler.performBackgroundRefresh(backends: [backend])

        #expect(backend.refreshedMailboxSourceIDs == [
            MailSourceID(accountID: "spy", mailboxID: "spy"),
        ])
        #expect(backend.refreshedFolderIDs.isEmpty)
    }

    @Test("refreshes inbox across multiple backends concurrently")
    func refreshesInboxAcrossMultipleBackends() async {
        let backendA = RefreshSpyBackend(
            account: BrevAccount(id: "a", displayName: "A", emailAddress: "a@example.com"),
            folders: Self.foldersWithInbox(inboxID: "inbox-a")
        )
        let backendB = RefreshSpyBackend(
            account: BrevAccount(id: "b", displayName: "B", emailAddress: "b@example.com"),
            folders: Self.foldersWithInbox(inboxID: "inbox-b")
        )
        await MailFetchScheduler.performBackgroundRefresh(backends: [backendA, backendB])
        #expect(backendA.refreshedFolderIDs == ["inbox-a"])
        #expect(backendB.refreshedFolderIDs == ["inbox-b"])
    }

    @Test("does not crash when no backends are connected")
    func doesNotCrashWithNoBackends() async {
        // Must complete without throwing or crashing.
        await MailFetchScheduler.performBackgroundRefresh(backends: [])
    }

    @Test("skips a backend whose folder fetch fails without crashing")
    func skipsFolderFetchFailureGracefully() async {
        let failingBackend = RefreshSpyBackend(
            folders: Self.foldersWithInbox(),
            failFolderFetch: true
        )
        await MailFetchScheduler.performBackgroundRefresh(backends: [failingBackend])
        // Nothing was refreshed because the folder list could not be fetched.
        #expect(failingBackend.refreshedFolderIDs.isEmpty)
    }

    @Test("skips a backend that exposes no inbox folder")
    func skipsMissingInboxGracefully() async {
        let noInboxBackend = RefreshSpyBackend(folders: [
            Folder(id: "sent", name: "Sent", role: .sent)
        ])
        await MailFetchScheduler.performBackgroundRefresh(backends: [noInboxBackend])
        #expect(noInboxBackend.refreshedFolderIDs.isEmpty)
    }

    @Test("delivers overdue scheduled sends during a background refresh")
    func deliversOverdueScheduledSendsDuringBackgroundRefresh() async {
        let backend = ScheduledSendSpyBackend(folders: Self.foldersWithInbox())
        await MailFetchScheduler.performBackgroundRefresh(backends: [backend])
        #expect(backend.deliverDueCallCount == 1)
        #expect(backend.refreshedFolderIDs == ["inbox"])
    }

    @Test("refreshes only inbox, not other folders")
    func refreshesOnlyInbox() async {
        let backend = RefreshSpyBackend(folders: [
            Folder(id: "inbox", name: "Inbox", role: .inbox),
            Folder(id: "sent", name: "Sent", role: .sent),
            Folder(id: "trash", name: "Trash", role: .trash)
        ])
        await MailFetchScheduler.performBackgroundRefresh(backends: [backend])
        #expect(backend.refreshedFolderIDs == ["inbox"])
    }

    @Test("visible Unified Inbox refresh targets each enabled source inbox")
    func refreshesVisibleUnifiedInboxSources() async {
        let accountA = BrevAccount(id: "a", displayName: "A", emailAddress: "a@example.com")
        let accountB = BrevAccount(id: "b", displayName: "B", emailAddress: "b@example.com")
        let backendA = RefreshSpyBackend(account: accountA, folders: Self.foldersWithInbox(inboxID: "inbox-a"))
        let backendB = RefreshSpyBackend(account: accountB, folders: Self.foldersWithInbox(inboxID: "inbox-b"))
        let sourceA = MailSourceID(accountID: "a", mailboxID: "mailbox-a")
        let sourceB = MailSourceID(accountID: "b", mailboxID: "mailbox-b")
        let sections = [
            MailSourceSection(
                id: sourceA,
                account: accountA,
                mailbox: Mailbox(id: "mailbox-a", email: accountA.emailAddress, displayName: "A", isPrimary: true),
                folders: Self.foldersWithInbox(inboxID: "inbox-a")
            ),
            MailSourceSection(
                id: sourceB,
                account: accountB,
                mailbox: Mailbox(id: "mailbox-b", email: accountB.emailAddress, displayName: "B", isPrimary: true),
                folders: Self.foldersWithInbox(inboxID: "inbox-b")
            ),
        ]

        let failure = await MailFetchScheduler.performVisibleInboxRefresh(
            backends: [backendA, backendB],
            sourceSections: sections
        )

        #expect(failure == nil)
        #expect(backendA.refreshedFolderIDs == ["inbox-a"])
        #expect(backendA.refreshedSourceIDs == [sourceA])
        #expect(backendB.refreshedFolderIDs == ["inbox-b"])
        #expect(backendB.refreshedSourceIDs == [sourceB])
    }

    @Test("visible Unified Inbox refresh keeps successful sources when one fails")
    func visibleUnifiedInboxRefreshKeepsPartialSuccess() async {
        let accountA = BrevAccount(id: "a", displayName: "A", emailAddress: "a@example.com")
        let accountB = BrevAccount(id: "b", displayName: "B", emailAddress: "b@example.com")
        let failingBackend = FailingSourceRefreshBackend(account: accountA, folders: Self.foldersWithInbox())
        let successfulBackend = RefreshSpyBackend(account: accountB, folders: Self.foldersWithInbox())
        let sourceA = MailSourceID(accountID: "a", mailboxID: "mailbox-a")
        let sourceB = MailSourceID(accountID: "b", mailboxID: "mailbox-b")
        let sections = [
            MailSourceSection(
                id: sourceA,
                account: accountA,
                mailbox: Mailbox(id: "mailbox-a", email: accountA.emailAddress, displayName: "A", isPrimary: true),
                folders: Self.foldersWithInbox()
            ),
            MailSourceSection(
                id: sourceB,
                account: accountB,
                mailbox: Mailbox(id: "mailbox-b", email: accountB.emailAddress, displayName: "B", isPrimary: true),
                folders: Self.foldersWithInbox()
            ),
        ]

        let failure = await MailFetchScheduler.performVisibleInboxRefresh(
            backends: [failingBackend, successfulBackend],
            sourceSections: sections
        )

        #expect(failure?.contains("stubbed source refresh failure") == true)
        #expect(successfulBackend.refreshedFolderIDs == ["inbox"])
        #expect(successfulBackend.refreshedSourceIDs == [sourceB])
    }

    @Test("visible Unified Inbox refresh recovers missing cached folder metadata")
    func visibleUnifiedInboxRefreshRecoversFolderMetadata() async {
        let account = BrevAccount(id: "a", displayName: "A", emailAddress: "a@example.com")
        let backend = RefreshSpyBackend(
            account: account,
            folders: Self.foldersWithInbox(inboxID: "recovered-inbox")
        )
        let sourceID = MailSourceID(accountID: "a", mailboxID: "mailbox-a")
        let section = MailSourceSection(
            id: sourceID,
            account: account,
            mailbox: Mailbox(id: "mailbox-a", email: account.emailAddress, displayName: "A", isPrimary: true),
            folders: [],
            loadError: FolderLoadError(message: "Folder metadata unavailable", isNetworkError: true)
        )

        let failure = await MailFetchScheduler.performVisibleInboxRefresh(
            backends: [backend],
            sourceSections: [section]
        )

        #expect(failure == nil)
        #expect(backend.refreshedFolderIDs == ["recovered-inbox"])
        #expect(backend.refreshedSourceIDs == [sourceID])
    }

    @Test("visible Unified Inbox refresh reports missing backend or Inbox metadata")
    func visibleUnifiedInboxRefreshReportsMissingTargets() async {
        let account = BrevAccount(id: "a", displayName: "A", emailAddress: "a@example.com")
        let sourceID = MailSourceID(accountID: "a", mailboxID: "mailbox-a")
        let section = MailSourceSection(
            id: sourceID,
            account: account,
            mailbox: Mailbox(id: "mailbox-a", email: account.emailAddress, displayName: "A", isPrimary: true),
            folders: []
        )

        let missingBackendFailure = await MailFetchScheduler.performVisibleInboxRefresh(
            backends: [],
            sourceSections: [section]
        )
        let noInboxBackend = RefreshSpyBackend(
            account: account,
            folders: [Folder(id: "sent", name: "Sent", role: .sent)]
        )
        let missingInboxFailure = await MailFetchScheduler.performVisibleInboxRefresh(
            backends: [noInboxBackend],
            sourceSections: [section]
        )

        #expect(missingBackendFailure != nil)
        #expect(missingInboxFailure != nil)
        #expect(noInboxBackend.refreshedFolderIDs.isEmpty)
    }
}
