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
import BrevDesign
@testable import BrevMail
import BrevSettings
import BrevThemes
import BrevWidgets
import Foundation
import Testing

/// Lightweight `MailBackend` double exposing `BoundedCachedHeaderProviding` so
/// unit tests can assert bounded vs unbounded cache read counts without network
/// or SQLite setup.
private final class BoundedHeaderTrackingBackend: MailBackend, BoundedCachedHeaderProviding, @unchecked Sendable {
    let account: BrevAccount
    let capabilities: BackendCapabilities = []
    let extendedCapabilities: BackendExtendedCapabilities = [.cachedMessageHeaders]

    private let lock = NSLock()
    private var headersByFolderID: [Folder.ID: [MessageHeader]]
    private var unboundedCallCountStorage = 0
    private var boundedRequestsStorage: [(folderID: Folder.ID, limit: Int, since: Date?)] = []

    var unboundedCallCount: Int { lock.withLock { unboundedCallCountStorage } }
    var boundedRequests: [(folderID: Folder.ID, limit: Int, since: Date?)] { lock.withLock { boundedRequestsStorage } }

    init(account: BrevAccount, headersByFolderID: [Folder.ID: [MessageHeader]]) {
        self.account = account
        self.headersByFolderID = headersByFolderID
    }

    func connect() async throws {}
    func disconnect() async {}
    func mailboxes() async throws -> [Mailbox] {
        [Mailbox(id: account.id, email: account.emailAddress, displayName: account.displayName)]
    }

    func selectMailbox(id: Mailbox.ID) async throws {}
    func folders() async throws -> [Folder] { [] }
    func refresh(folder: Folder) async throws {}
    func messages(in folder: Folder, pageToken: String?) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        ([], nil)
    }

    func body(for messageID: String) async throws -> MessageBody {
        MessageBody(messageID: messageID, plainText: "Body")
    }

    func downloadAttachment(_ attachment: BrevBackend.Attachment) async throws -> Data { Data() }
    func setRead(_ isRead: Bool, for messageIDs: [String]) async throws {}
    func setFlagged(_ isFlagged: Bool, for messageIDs: [String]) async throws {}
    func setFlagColor(_ color: FlagColor?, for messageIDs: [String]) async throws {}
    func move(messageIDs: [String], to folder: Folder) async throws {}
    func delete(messageIDs: [String]) async throws {}
    func save(draft: Draft) async throws -> Draft { draft }
    func uploadAttachment(draftID: String, data: Data, filename: String, mimeType: String) async throws -> String { "" }
    func discard(draftID: String) async throws {}
    func send(draft: Draft) async throws -> SendResult { SendResult(sentMessageID: "sent") }
    func setJunk(_ isJunk: Bool, for messageIDs: [String]) async throws {}
    func blockSender(email: String) async throws {}
    func search(_ query: SearchQuery) async throws -> [MessageHeader] { [] }
    func calendarEvent(from attachmentID: String) async throws -> CalendarEvent {
        throw MailBackendError.notSupported(capabilities)
    }

    func replyToCalendarInvite(messageID: String, response: AttendeeState) async throws {}
    func subscribeToChanges() -> AsyncStream<MailEvent> { AsyncStream { $0.finish() } }
    func sourceID(for mailbox: Mailbox) -> MailSourceID { MailSourceID(accountID: account.id, mailboxID: mailbox.id) }
    func folders(in sourceID: MailSourceID) async throws -> [Folder] { [] }
    func refresh(folder: Folder, in sourceID: MailSourceID) async throws {}
    func applyRetention(folderID: Folder.ID, sourceID: MailSourceID, retentionDays: Int?, keepsBodies: Bool) async throws {}
    func createFolder(name: String, parentID: Folder.ID?, sourceID: MailSourceID) async throws -> Folder {
        throw MailBackendError.notSupported(capabilities)
    }

    func renameFolder(id: Folder.ID, name: String, sourceID: MailSourceID) async throws -> Folder {
        throw MailBackendError.notSupported(capabilities)
    }

    func deleteFolder(id: Folder.ID, sourceID: MailSourceID) async throws {}
    func flushFolder(id: Folder.ID, sourceID: MailSourceID) async throws {}
    func messages(
        in folder: Folder,
        sourceID: MailSourceID,
        pageToken: String?
    ) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        ([], nil)
    }

    func enumerateMessages(
        in folder: Folder,
        sourceID: MailSourceID,
        pageToken: String?
    ) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        ([], nil)
    }

    func body(for messageID: String, sourceID: MailSourceID) async throws -> MessageBody {
        MessageBody(messageID: messageID, plainText: "Body")
    }

    func rawSource(for messageID: String, sourceID: MailSourceID) async throws -> String { "" }
    func rawMessageData(for messageID: String, sourceID: MailSourceID) async throws -> Data { Data() }
    func downloadAttachment(_ attachment: BrevBackend.Attachment, sourceID: MailSourceID) async throws -> Data { Data() }
    func setRead(_ isRead: Bool, for messageIDs: [String], sourceID: MailSourceID) async throws {}
    func setFlagged(_ isFlagged: Bool, for messageIDs: [String], sourceID: MailSourceID) async throws {}
    func setFlagColor(_ color: FlagColor?, for messageIDs: [String], sourceID: MailSourceID) async throws {}
    func move(messageIDs: [String], to folder: Folder, sourceID: MailSourceID) async throws {}
    func copy(messageIDs: [String], to folder: Folder, sourceID: MailSourceID) async throws {}
    func delete(messageIDs: [String], sourceID: MailSourceID) async throws {}
    func save(draft: Draft, sourceID: MailSourceID) async throws -> Draft { draft }
    func uploadAttachment(
        draftID: String,
        data: Data,
        filename: String,
        mimeType: String,
        sourceID: MailSourceID
    ) async throws -> String { "" }

    func stageInlineAttachment(
        draftID: String,
        contentID: String,
        filename: String,
        mimeType: String,
        data: Data,
        sourceID: MailSourceID
    ) async throws -> String { "" }

    func discard(draftID: String, sourceID: MailSourceID) async throws {}
    func send(draft: Draft, sourceID: MailSourceID) async throws -> SendResult { SendResult(sentMessageID: "sent") }
    func setJunk(_ isJunk: Bool, for messageIDs: [String], sourceID: MailSourceID) async throws {}
    func blockSender(email: String, sourceID: MailSourceID) async throws {}
    func search(_ query: SearchQuery, sourceID: MailSourceID) async throws -> [MessageHeader] { [] }
    func calendarEvent(from attachmentID: String, sourceID: MailSourceID) async throws -> CalendarEvent {
        throw MailBackendError.notSupported(capabilities)
    }

    func replyToCalendarInvite(messageID: String, response: AttendeeState, sourceID: MailSourceID) async throws {}
    func setContactLookupProvider(_ provider: (any ContactLookupProviding)?) {}

    func extensionService<Service>(_ type: Service.Type) -> Service? {
        if ObjectIdentifier(type) == ObjectIdentifier(BoundedCachedHeaderProviding.self) {
            return self as? Service
        }
        return nil
    }

    func cachedMessageHeaders(in folder: Folder, sourceID: MailSourceID) async throws -> [MessageHeader] {
        lock.withLock {
            unboundedCallCountStorage += 1
            return headersByFolderID[folder.id] ?? []
        }
    }

    func cachedMessageHeaders(
        in folder: Folder,
        sourceID: MailSourceID,
        limit: Int,
        since: Date?
    ) async throws -> [MessageHeader] {
        lock.withLock {
            boundedRequestsStorage.append((folder.id, limit, since))
            let all = (headersByFolderID[folder.id] ?? [])
                .filter { since == nil || $0.date >= since! }
                .sorted { $0.date > $1.date }
            return Array(all.prefix(limit))
        }
    }
}

@Suite("Navigation and reader hot paths")
@MainActor
struct NavigationReaderHotPathTests {
    @Test("WidgetSnapshotPublisher uses bounded header fetch instead of full-folder scan")
    func widgetSnapshotPublisherUsesBoundedFetch() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("brev-widget-bounded-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WidgetSnapshotStore(directory: dir)
        let publisher = WidgetSnapshotPublisher(store: store)

        let account = BrevAccount(id: "acct-1", displayName: "Work", emailAddress: "me@example.org")
        let sourceID = MailSourceID(accountID: account.id, mailboxID: account.id)
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox, unreadCount: 4, totalCount: 100)
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let headers = (1 ... 40).map { index in
            MessageHeader(
                id: "INBOX:\(index)",
                threadID: "t-\(index)",
                folderID: "INBOX",
                from: Correspondent(name: "Person \(index)", email: "p\(index)@example.org"),
                subject: "Subject \(index)",
                snippet: "Preview",
                date: baseDate.addingTimeInterval(TimeInterval(index * 60)),
                isRead: false
            )
        }
        let backend = BoundedHeaderTrackingBackend(account: account, headersByFolderID: ["INBOX": headers])
        let section = MailSourceSection(
            id: sourceID,
            account: account,
            mailbox: Mailbox(id: account.id, email: account.emailAddress, displayName: account.displayName),
            folders: [inbox]
        )

        var settings = NotificationSettings.defaults
        settings.showPreviews = true
        await publisher.publish(
            folders: [inbox],
            sourceSections: [section],
            backends: [backend],
            settings: settings
        )

        #expect(backend.unboundedCallCount == 0)
        #expect(backend.boundedRequests.count == 1)
        #expect(backend.boundedRequests.first?.limit == WidgetSnapshotPublisher.headerFetchLimit)

        let saved = store.load()
        #expect(saved?.previews.count == WidgetSnapshotPublisher.previewLimit)
        #expect(saved?.previews.first?.subject == "Subject 40")
    }

    @Test("SenderWarningHistoryCache hits memory across opens and invalidates when Sent count changes")
    func senderWarningHistoryCacheHitsAndInvalidates() async {
        let account = BrevAccount(id: "acct-sender", displayName: "Me", emailAddress: "me@example.org")
        let sourceID = MailSourceID(accountID: account.id, mailboxID: account.id)
        let sentFolder = Folder(id: "Sent", name: "Sent", role: .sent, unreadCount: 0, totalCount: 10)
        let sentHeader = MessageHeader(
            id: "Sent:1",
            threadID: "t-1",
            folderID: "Sent",
            from: Correspondent(name: "Me", email: "me@example.org"),
            to: [Correspondent(name: "Friend", email: "friend@partner.example")],
            subject: "Hi",
            snippet: "",
            date: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let backend = BoundedHeaderTrackingBackend(account: account, headersByFolderID: ["Sent": [sentHeader]])
        let cache = SenderWarningHistoryCache(capacity: 4)

        let key1 = SenderWarningHistoryCache.Key(
            backendID: ObjectIdentifier(backend),
            sourceID: sourceID,
            sentFolders: [.init(id: sentFolder.id, totalCount: sentFolder.totalCount)],
            ownAddresses: ["me@example.org"],
            writtenRevision: 0
        )

        let first = await cache.load(key: key1, backend: backend, sent: [sentFolder])
        let second = await cache.load(key: key1, backend: backend, sent: [sentFolder])

        #expect(first.written.contains("friend@partner.example"))
        #expect(second == first)
        #expect(cache.coldLoadCount == 1)
        #expect(backend.unboundedCallCount == 0)
        #expect(backend.boundedRequests.count == 1)
        #expect(backend.boundedRequests.first?.limit == SenderWarningHistory.sentHeaderScanLimit)

        // Increasing Sent totalCount invalidates the cache key cleanly.
        let updatedSent = Folder(id: "Sent", name: "Sent", role: .sent, unreadCount: 0, totalCount: 11)
        let key2 = SenderWarningHistoryCache.Key(
            backendID: ObjectIdentifier(backend),
            sourceID: sourceID,
            sentFolders: [.init(id: updatedSent.id, totalCount: updatedSent.totalCount)],
            ownAddresses: ["me@example.org"],
            writtenRevision: 0
        )
        _ = await cache.load(key: key2, backend: backend, sent: [updatedSent])
        #expect(cache.coldLoadCount == 2)
    }

    @Test("local read mutation updates unread delta and suppresses echo without bumping reloadRequestID")
    func localReadMutationSuppressesEchoWithoutReloadStorm() {
        let navigation = MailNavigationState(
            selectedSourceID: MailSourceID(accountID: "acct", mailboxID: "acct"),
            selectedFolderID: "INBOX",
            selectedMessageID: "INBOX:1"
        )
        let initialReloadID = navigation.reloadRequestID
        let now = ContinuousClock.now

        navigation.recordLocalReadChange(
            folderID: "INBOX",
            sourceID: navigation.selectedSourceID,
            messageIDs: ["INBOX:1"],
            unreadDelta: -1,
            now: now
        )

        #expect(navigation.reloadRequestID == initialReloadID)
        #expect(navigation.lastLocalUnreadCountDelta?.folderID == "INBOX")
        #expect(navigation.lastLocalUnreadCountDelta?.delta == -1)

        // Matching backend `.messagesUpdated` echo is consumed once.
        #expect(navigation.consumeMatchingLocalReadEcho(
            for: .messagesUpdated(folderID: "INBOX", messageIDs: ["INBOX:1"]),
            now: now + .milliseconds(200)
        ))
        // A second event for the same message is NOT suppressed.
        #expect(!navigation.consumeMatchingLocalReadEcho(
            for: .messagesUpdated(folderID: "INBOX", messageIDs: ["INBOX:1"]),
            now: now + .milliseconds(300)
        ))
        // Non-update events are never suppressed.
        navigation.recordLocalReadChange(
            folderID: "INBOX",
            sourceID: navigation.selectedSourceID,
            messageIDs: ["INBOX:2"],
            unreadDelta: -1,
            now: now
        )
        #expect(!navigation.consumeMatchingLocalReadEcho(
            for: .messagesAdded(folderID: "INBOX", messageIDs: ["INBOX:2"]),
            now: now + .milliseconds(100)
        ))
        // Expired echoes are not suppressed.
        #expect(!navigation.consumeMatchingLocalReadEcho(
            for: .messagesUpdated(folderID: "INBOX", messageIDs: ["INBOX:2"]),
            now: now + .seconds(10)
        ))
    }

    @Test("folder switch awaits headers until list reconciles while explicit Today stays immediate")
    func folderSwitchAwaitingHeadersLifecycle() {
        let navigation = MailNavigationState()
        let source = MailSourceID(accountID: "acct", mailboxID: "acct")

        navigation.selectFolder("Work", in: source)
        #expect(navigation.isAwaitingFolderHeaders)

        // Once the folder finishes loading (even if empty), Today may appear.
        navigation.replaceCurrentFolderHeaders([], selectFirstIfNeeded: true)
        #expect(!navigation.isAwaitingFolderHeaders)

        // Explicit Today smart view does not wait for folder headers.
        navigation.selectTodaySmartView()
        #expect(!navigation.isAwaitingFolderHeaders)

        // Switching to Unified Inbox awaits headers until populated.
        navigation.selectUnifiedInbox()
        #expect(navigation.isAwaitingFolderHeaders)
        let header = MessageHeader(
            id: "INBOX:1",
            threadID: "t-1",
            folderID: "INBOX",
            from: Correspondent(email: "a@example.org"),
            subject: "Hi",
            snippet: "",
            date: Date()
        )
        navigation.replaceCurrentFolderHeaders([header], selectFirstIfNeeded: true)
        #expect(!navigation.isAwaitingFolderHeaders)
        #expect(navigation.selectedMessageID == "INBOX:1")
    }

    @Test("ThreadWebViewStoreRecycler reuses warm stores across thread switches")
    func threadWebViewStoreRecyclerReusesWarmStore() {
        let recycler = ThreadWebViewStoreRecycler(capacity: 2)
        let storeA = recycler.checkout(for: "threadA-1")
        _ = storeA.webView
        #expect(storeA.isWebViewCreated)
        #expect(storeA.isDetached)

        recycler.recycleAllExcept(["threadB-1"])
        #expect(recycler.activeStoreCount == 0)
        #expect(recycler.reusableStoreCount == 1)

        let storeB = recycler.checkout(for: "threadB-1")
        #expect(storeB === storeA)
        #expect(recycler.reuseHitCount == 1)
    }

    @Test("HTMLBodyReloadPolicy skips full-string compare when content identity matches")
    func htmlBodyReloadPolicySkipsReloadForMatchingIdentity() {
        let style = MessageBodyStyle.resolve(
            theme: .brevMonoDark,
            fontFamily: .system,
            textSize: .medium,
            renderingMode: .original,
            bodyInsetPoints: 0,
            bodyScale: 1
        )
        let id1 = HTMLBodyContentIdentity(messageID: "m1", revision: 1, utf8Count: 12)
        let id2 = HTMLBodyContentIdentity(messageID: "m1", revision: 2, utf8Count: 12)

        // Matching identity skips reload even when raw lastHTML was not retained.
        #expect(!HTMLBodyReloadPolicy.shouldReload(
            hasLoadedContent: true,
            lastContentIdentity: id1,
            contentIdentity: id1,
            lastHTMLUTF8Count: 12,
            lastHTML: nil,
            html: "<p>Hello!</p>",
            lastAllowRemote: false,
            allowRemoteContent: false,
            lastStripTrackingPixels: true,
            stripTrackingPixels: true,
            lastStyle: style,
            style: style
        ))

        // Bumped revision triggers reload.
        #expect(HTMLBodyReloadPolicy.shouldReload(
            hasLoadedContent: true,
            lastContentIdentity: id1,
            contentIdentity: id2,
            lastHTMLUTF8Count: 12,
            lastHTML: nil,
            html: "<p>Hello!</p>",
            lastAllowRemote: false,
            allowRemoteContent: false,
            lastStripTrackingPixels: true,
            stripTrackingPixels: true,
            lastStyle: style,
            style: style
        ))

        // Fallback without identity checks length first and string equality second.
        #expect(!HTMLBodyReloadPolicy.shouldReload(
            hasLoadedContent: true,
            lastContentIdentity: nil,
            contentIdentity: nil,
            lastHTMLUTF8Count: 13,
            lastHTML: "<p>Hello!</p>",
            html: "<p>Hello!</p>",
            lastAllowRemote: false,
            allowRemoteContent: false,
            lastStripTrackingPixels: true,
            stripTrackingPixels: true,
            lastStyle: style,
            style: style
        ))
        #expect(HTMLBodyReloadPolicy.shouldReload(
            hasLoadedContent: true,
            lastContentIdentity: nil,
            contentIdentity: nil,
            lastHTMLUTF8Count: 13,
            lastHTML: "<p>Hello!</p>",
            html: "<p>World!</p>",
            lastAllowRemote: false,
            allowRemoteContent: false,
            lastStripTrackingPixels: true,
            stripTrackingPixels: true,
            lastStyle: style,
            style: style
        ))
    }
}
