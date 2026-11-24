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

/// Thread-safe spy `MailBackend` recording every network call made by `BackgroundRecentIndexingCoordinator`.
private final class IndexingSpyBackend: MailBackend, CachedMessageBodyProviding, LocalAttachmentTextIndexing,
    BackgroundBodyIndexing, @unchecked Sendable {
    struct IndexedAttachmentRecord: Equatable, Sendable {
        let messageID: String
        let folderID: String
        let attachmentID: String
        let name: String
        let text: String
    }

    let account: BrevAccount
    var capabilities: BackendCapabilities { [] }
    var extendedCapabilities: BackendExtendedCapabilities { [.cachedMessageHeaders, .localAttachmentIndex] }

    private let lock = NSLock()
    private let configuredFolders: [Folder]
    private var headersByFolder: [Folder.ID: [MessageHeader]]
    private var bodiesByID: [String: MessageBody]
    private var cachedBodyIDs: Set<String>
    private let cacheBodyAfterFetch: Bool
    private let attachmentPayloads: [String: Data]
    private var indexedAttachmentIDsByMessage: [String: Set<String>]
    private let supportsBackgroundBodyIndexing: Bool

    var onBodyFetch: (@Sendable (String) async throws -> Void)?
    var onDownloadAttachment: (@Sendable (String) async throws -> Void)?
    var onIndexAttachmentText: (@Sendable (String) async throws -> Void)?
    var onBackgroundBodyIndex: (@Sendable (String, Int) async throws -> MessageBody?)?

    private(set) var foldersCalls = 0
    private(set) var cachedHeadersCalls = 0
    private(set) var bodyFetchIDs: [String] = []
    private(set) var backgroundBodyFetchIDs: [String] = []
    private(set) var downloadedAttachmentIDs: [String] = []
    private(set) var setReadCalls = 0
    private(set) var indexedAttachments: [IndexedAttachmentRecord] = []

    init(
        account: BrevAccount = BrevAccount(
            id: "imap-smtp:ada@example.org",
            displayName: "Ada",
            emailAddress: "ada@example.org"
        ),
        folders: [Folder],
        headersByFolder: [Folder.ID: [MessageHeader]],
        bodiesByID: [String: MessageBody],
        preCachedBodyIDs: Set<String> = [],
        cacheBodyAfterFetch: Bool = false,
        attachmentPayloads: [String: Data] = [:],
        preIndexedAttachmentIDsByMessage: [String: Set<String>] = [:],
        supportsBackgroundBodyIndexing: Bool = false
    ) {
        self.account = account
        configuredFolders = folders
        self.headersByFolder = headersByFolder
        self.bodiesByID = bodiesByID
        cachedBodyIDs = preCachedBodyIDs
        self.cacheBodyAfterFetch = cacheBodyAfterFetch
        self.attachmentPayloads = attachmentPayloads
        indexedAttachmentIDsByMessage = preIndexedAttachmentIDsByMessage
        self.supportsBackgroundBodyIndexing = supportsBackgroundBodyIndexing
    }

    func addMessage(_ header: MessageHeader, body: MessageBody, toFolder folderID: Folder.ID) {
        lock.withLock {
            headersByFolder[folderID, default: []].append(header)
            bodiesByID[header.id] = body
        }
    }

    func clearLiveAttachmentIndex() {
        lock.withLock {
            indexedAttachmentIDsByMessage.removeAll()
            indexedAttachments.removeAll()
        }
    }

    func connect() async throws {}
    func disconnect() async {}

    func folders() async throws -> [Folder] {
        lock.withLock { foldersCalls += 1 }
        return configuredFolders
    }

    func folders(in _: MailSourceID) async throws -> [Folder] {
        try await folders()
    }

    func refresh(folder _: Folder) async throws {}

    func messages(in _: Folder, pageToken _: String?) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        ([], nil)
    }

    func cachedMessageHeaders(in folder: Folder, sourceID _: MailSourceID) async throws -> [MessageHeader] {
        lock.withLock {
            cachedHeadersCalls += 1
            return headersByFolder[folder.id] ?? []
        }
    }

    func cachedBody(for messageID: MessageHeader.ID, sourceID _: MailSourceID?) async -> MessageBody? {
        lock.withLock {
            guard cachedBodyIDs.contains(messageID) else { return nil }
            return bodiesByID[messageID]
        }
    }

    func body(for messageID: String) async throws -> MessageBody {
        if let hook = lock.withLock({ onBodyFetch }) {
            try await hook(messageID)
        }
        let body: MessageBody? = lock.withLock {
            bodyFetchIDs.append(messageID)
            if cacheBodyAfterFetch {
                cachedBodyIDs.insert(messageID)
            }
            return bodiesByID[messageID]
        }
        guard let body else {
            throw MailBackendError.notFound(id: messageID)
        }
        return body
    }

    func body(for messageID: String, sourceID _: MailSourceID) async throws -> MessageBody {
        try await body(for: messageID)
    }

    func indexBackgroundBody(
        for messageID: MessageHeader.ID,
        sourceID _: MailSourceID,
        maxFallbackSourceBytes: Int
    ) async throws -> MessageBody? {
        lock.withLock { backgroundBodyFetchIDs.append(messageID) }
        if let hook = lock.withLock({ onBackgroundBodyIndex }) {
            let result = try await hook(messageID, maxFallbackSourceBytes)
            if result != nil, cacheBodyAfterFetch {
                lock.withLock { _ = cachedBodyIDs.insert(messageID) }
            }
            return result
        }
        return lock.withLock {
            if cacheBodyAfterFetch {
                cachedBodyIDs.insert(messageID)
            }
            return bodiesByID[messageID]
        }
    }

    func downloadAttachment(_ attachment: BrevBackend.Attachment) async throws -> Data {
        if let hook = lock.withLock({ onDownloadAttachment }) {
            try await hook(attachment.id)
        }
        lock.withLock { downloadedAttachmentIDs.append(attachment.id) }
        guard let data = attachmentPayloads[attachment.id] else {
            throw MailBackendError.notFound(id: attachment.id)
        }
        return data
    }

    func downloadAttachment(_ attachment: BrevBackend.Attachment, sourceID _: MailSourceID) async throws -> Data {
        try await downloadAttachment(attachment)
    }

    func setRead(_: Bool, for _: [String]) async throws {
        lock.withLock { setReadCalls += 1 }
    }

    func setFlagged(_: Bool, for _: [String]) async throws {}
    func move(messageIDs _: [String], to _: Folder) async throws {}
    func delete(messageIDs _: [String]) async throws {}
    func save(draft: Draft) async throws -> Draft { draft }
    func discard(draftID _: String) async throws {}
    func send(draft _: Draft) async throws -> SendResult { SendResult(sentMessageID: "sent") }
    func search(_: SearchQuery) async throws -> [MessageHeader] { [] }
    func calendarEvent(from _: String) async throws -> CalendarEvent {
        throw MailBackendError.notSupported(capabilities)
    }

    func replyToCalendarInvite(messageID _: String, response _: AttendeeState) async throws {}
    func subscribeToChanges() -> AsyncStream<MailEvent> { AsyncStream { $0.finish() } }

    func extensionService<Service>(_ type: Service.Type) -> Service? {
        switch ObjectIdentifier(type) {
        case ObjectIdentifier(CachedMessageBodyProviding.self),
             ObjectIdentifier(LocalAttachmentTextIndexing.self):
            return self as? Service
        case ObjectIdentifier(BackgroundBodyIndexing.self) where supportsBackgroundBodyIndexing:
            return self as? Service
        default:
            return nil
        }
    }

    func indexAttachmentText(
        messageID: MessageHeader.ID,
        folderID: Folder.ID,
        attachmentID: String,
        name: String,
        text: String
    ) async throws {
        if let hook = lock.withLock({ onIndexAttachmentText }) {
            try await hook(attachmentID)
        }
        lock.withLock {
            indexedAttachments.append(IndexedAttachmentRecord(
                messageID: messageID,
                folderID: folderID,
                attachmentID: attachmentID,
                name: name,
                text: text
            ))
            indexedAttachmentIDsByMessage[messageID, default: []].insert(attachmentID)
        }
    }

    func indexedAttachmentMessageIDs() async -> Set<MessageHeader.ID> {
        lock.withLock { Set(indexedAttachmentIDsByMessage.keys) }
    }

    func indexedAttachmentIDs() async -> [MessageHeader.ID: Set<String>] {
        lock.withLock { indexedAttachmentIDsByMessage }
    }
}

@Suite("BackgroundRecentIndexingCoordinator")
@MainActor
struct BackgroundRecentIndexingCoordinatorTests {
    private let fixedNow = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeStore(_ suffix: String) throws -> (BackgroundIndexingProgressStore, UserDefaults, String) {
        let suite = "BackgroundIndexingCoordinatorTests-\(suffix)-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (BackgroundIndexingProgressStore(defaults: defaults), defaults, suite)
    }

    private func header(
        id: String,
        folderID: String = "INBOX",
        daysAgo: Double,
        isRead: Bool = false,
        hasAttachments: Bool = false
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "t-\(id)",
            folderID: folderID,
            from: Correspondent(name: "Sender", email: "sender@example.org"),
            subject: "Subject \(id)",
            snippet: "Snippet \(id)",
            date: fixedNow.addingTimeInterval(-daysAgo * 86400),
            isRead: isRead,
            hasAttachments: hasAttachments
        )
    }

    private func body(id: String, attachments: [BrevBackend.Attachment] = []) -> MessageBody {
        MessageBody(
            messageID: id,
            html: nil,
            plainText: "Body text for \(id)",
            attachments: attachments
        )
    }

    @Test("zero work and zero network calls occur while disabled")
    func zeroNetworkWhenDisabled() async throws {
        let (store, defaults, suite) = try makeStore("disabled")
        defer { defaults.removePersistentDomain(forName: suite) }

        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let msg = header(id: "m1", daysAgo: 2, hasAttachments: true)
        let att = BrevBackend.Attachment(id: "a1", name: "notes.txt", mimeType: "text/plain", sizeBytes: 120)
        let spy = IndexingSpyBackend(
            folders: [inbox],
            headersByFolder: ["INBOX": [msg]],
            bodiesByID: ["m1": body(id: "m1", attachments: [att])],
            attachmentPayloads: ["a1": Data("hello world".utf8)]
        )

        let coordinator = BackgroundRecentIndexingCoordinator(
            backendsProvider: { [spy] },
            settingsProvider: { BackgroundIndexingSettings.defaults },
            environmentProvider: { BackgroundIndexingEnvironmentSnapshot() },
            progressStore: store,
            now: { fixedNow },
            pacingDelay: .zero
        )

        coordinator.reconcile()
        await coordinator.runPassNow()

        #expect(spy.foldersCalls == 0)
        #expect(spy.cachedHeadersCalls == 0)
        #expect(spy.bodyFetchIDs.isEmpty)
        #expect(spy.downloadedAttachmentIDs.isEmpty)
        #expect(spy.setReadCalls == 0)
        #expect(coordinator.state == BackgroundIndexingState.idle)
    }

    @Test("indexes only messages inside window, excludes Trash and Spam, preserves unread, skips already indexed")
    func windowFilteringAndExclusions() async throws {
        let (store, defaults, suite) = try makeStore("window")
        defer { defaults.removePersistentDomain(forName: suite) }

        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let trash = Folder(id: "TRASH", name: "Trash", role: .trash)
        let spam = Folder(id: "SPAM", name: "Spam", role: .spam)

        let recentNewest = header(id: "m-new", folderID: "INBOX", daysAgo: 1, isRead: false)
        let recentOlder = header(id: "m-mid", folderID: "INBOX", daysAgo: 20, isRead: false)
        let tooOld = header(id: "m-old", folderID: "INBOX", daysAgo: 45, isRead: false)
        let trashed = header(id: "m-trash", folderID: "TRASH", daysAgo: 2, isRead: false)
        let spammed = header(id: "m-spam", folderID: "SPAM", daysAgo: 2, isRead: false)

        let spy = IndexingSpyBackend(
            folders: [inbox, trash, spam],
            headersByFolder: [
                "INBOX": [recentOlder, tooOld, recentNewest],
                "TRASH": [trashed],
                "SPAM": [spammed]
            ],
            bodiesByID: [
                "m-new": body(id: "m-new"),
                "m-mid": body(id: "m-mid"),
                "m-old": body(id: "m-old"),
                "m-trash": body(id: "m-trash"),
                "m-spam": body(id: "m-spam")
            ]
        )

        let settings = BackgroundIndexingSettings(
            isEnabled: true,
            windowDays: .days30,
            indexAttachments: false,
            requireUnmeteredNetworkAndPower: true
        )

        let coordinator = BackgroundRecentIndexingCoordinator(
            backendsProvider: { [spy] },
            settingsProvider: { settings },
            environmentProvider: { BackgroundIndexingEnvironmentSnapshot() },
            progressStore: store,
            now: { fixedNow },
            pacingDelay: .zero
        )

        await coordinator.runPassNow()

        // Newest-first inside 30-day window; Trash, Spam, and 45-day-old skipped.
        #expect(spy.bodyFetchIDs == ["m-new", "m-mid"])
        #expect(spy.setReadCalls == 0)
        #expect(coordinator.state == BackgroundIndexingState.completed)
        #expect(coordinator.indexedMessagesCount == 2)
        #expect(coordinator.pendingCount == 0)
        #expect(coordinator.lastIndexedAt == fixedNow)

        // Second pass skips already-indexed messages.
        await coordinator.runPassNow()
        #expect(spy.bodyFetchIDs == ["m-new", "m-mid"])
    }

    @Test("pauses on metered network or Low Power Mode and resumes when conditions clear")
    func networkAndPowerGating() async throws {
        let (store, defaults, suite) = try makeStore("gating")
        defer { defaults.removePersistentDomain(forName: suite) }

        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let msg = header(id: "m1", daysAgo: 1)
        let spy = IndexingSpyBackend(
            folders: [inbox],
            headersByFolder: ["INBOX": [msg]],
            bodiesByID: ["m1": body(id: "m1")]
        )

        var currentEnv = BackgroundIndexingEnvironmentSnapshot(
            isOnline: true,
            isExpensiveNetwork: true,
            isConstrainedNetwork: false,
            isLowPowerModeEnabled: false
        )
        let settings = BackgroundIndexingSettings(
            isEnabled: true,
            windowDays: .days90,
            indexAttachments: true,
            requireUnmeteredNetworkAndPower: true
        )

        let coordinator = BackgroundRecentIndexingCoordinator(
            backendsProvider: { [spy] },
            settingsProvider: { settings },
            environmentProvider: { currentEnv },
            progressStore: store,
            now: { fixedNow },
            pacingDelay: .zero
        )

        await coordinator.runPassNow()
        #expect(coordinator.state == BackgroundIndexingState.paused(.meteredNetwork))
        #expect(spy.bodyFetchIDs.isEmpty)

        // Switch to Low Power Mode on Wi-Fi -> still paused.
        currentEnv = BackgroundIndexingEnvironmentSnapshot(
            isOnline: true,
            isExpensiveNetwork: false,
            isConstrainedNetwork: false,
            isLowPowerModeEnabled: true
        )
        coordinator.handleEnvironmentChanged()
        #expect(coordinator.state == BackgroundIndexingState.paused(.lowPowerMode))
        #expect(spy.bodyFetchIDs.isEmpty)

        // Clear Low Power Mode -> resumes and completes.
        currentEnv = BackgroundIndexingEnvironmentSnapshot(
            isOnline: true,
            isExpensiveNetwork: false,
            isConstrainedNetwork: false,
            isLowPowerModeEnabled: false
        )
        coordinator.handleEnvironmentChanged()
        // Wait briefly for the resumed task to complete.
        for _ in 0 ..< 40 where coordinator.state != BackgroundIndexingState.completed {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(coordinator.state == BackgroundIndexingState.completed)
        #expect(spy.bodyFetchIDs == ["m1"])
    }

    @Test("downloads and indexes eligible attachments under size cap while skipping oversized, inline, and unsupported binaries")
    func attachmentCapAndTypeFiltering() async throws {
        let (store, defaults, suite) = try makeStore("attachments")
        defer { defaults.removePersistentDomain(forName: suite) }

        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let msg = header(id: "m1", daysAgo: 3, hasAttachments: true)

        let eligibleText = BrevBackend.Attachment(id: "att-txt", name: "invoice.txt", mimeType: "text/plain", sizeBytes: 512)
        let eligibleHTML = BrevBackend.Attachment(id: "att-html", name: "summary.html", mimeType: "text/html", sizeBytes: 256)
        let oversizedText = BrevBackend.Attachment(id: "att-big", name: "dump.txt", mimeType: "text/plain", sizeBytes: 2048)
        let inlineImage = BrevBackend.Attachment(
            id: "att-inline",
            name: "logo.txt",
            mimeType: "text/plain",
            sizeBytes: 64,
            isInline: true
        )
        let binaryZip = BrevBackend.Attachment(id: "att-zip", name: "archive.zip", mimeType: "application/zip", sizeBytes: 128)
        let officeDocx = BrevBackend.Attachment(
            id: "att-docx",
            name: "report.docx",
            mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            sizeBytes: 128
        )

        let spy = IndexingSpyBackend(
            folders: [inbox],
            headersByFolder: ["INBOX": [msg]],
            bodiesByID: [
                "m1": body(
                    id: "m1",
                    attachments: [eligibleText, eligibleHTML, oversizedText, inlineImage, binaryZip, officeDocx]
                )
            ],
            attachmentPayloads: [
                "att-txt": Data("Quarterly invoice total 4200 NOK".utf8),
                "att-html": Data("<p>Project milestone <b>approved</b></p>".utf8),
                "att-big": Data(repeating: 0x41, count: 2048),
                "att-inline": Data("inline".utf8),
                "att-zip": Data([0x50, 0x4B, 0x03, 0x04]),
                "att-docx": Data([0x50, 0x4B, 0x03, 0x04])
            ]
        )

        let settings = BackgroundIndexingSettings(
            isEnabled: true,
            windowDays: .days90,
            indexAttachments: true,
            requireUnmeteredNetworkAndPower: true
        )

        let coordinator = BackgroundRecentIndexingCoordinator(
            backendsProvider: { [spy] },
            settingsProvider: { settings },
            environmentProvider: { BackgroundIndexingEnvironmentSnapshot() },
            progressStore: store,
            now: { fixedNow },
            maxAttachmentBytes: 1024,
            pacingDelay: .zero
        )

        await coordinator.runPassNow()

        #expect(spy.downloadedAttachmentIDs == ["att-txt", "att-html"])
        #expect(spy.indexedAttachments.count == 2)
        #expect(spy.indexedAttachments.contains {
            $0.attachmentID == "att-txt" && $0.text.contains("4200 NOK")
        })
        #expect(spy.indexedAttachments.contains {
            $0.attachmentID == "att-html" && $0.text.contains("Project milestone")
        })
        #expect(coordinator.indexedAttachmentsCount == 2)
        #expect(coordinator.state == BackgroundIndexingState.completed)
    }

    @Test("opting out mid-flight cancels remaining fetches cleanly without errors")
    func optOutCancelsInFlightWorkCleanly() async throws {
        let (store, defaults, suite) = try makeStore("cancel")
        defer { defaults.removePersistentDomain(forName: suite) }

        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let m1 = header(id: "m1", daysAgo: 1)
        let m2 = header(id: "m2", daysAgo: 2)
        let m3 = header(id: "m3", daysAgo: 3)

        let spy = IndexingSpyBackend(
            folders: [inbox],
            headersByFolder: ["INBOX": [m1, m2, m3]],
            bodiesByID: [
                "m1": body(id: "m1"),
                "m2": body(id: "m2"),
                "m3": body(id: "m3")
            ]
        )

        var settings = BackgroundIndexingSettings(
            isEnabled: true,
            windowDays: .days90,
            indexAttachments: false,
            requireUnmeteredNetworkAndPower: true
        )

        var coordinatorRef: BackgroundRecentIndexingCoordinator?
        let coordinator = BackgroundRecentIndexingCoordinator(
            backendsProvider: { [spy] },
            settingsProvider: { settings },
            environmentProvider: { BackgroundIndexingEnvironmentSnapshot() },
            progressStore: store,
            now: { fixedNow },
            pacingDelay: .milliseconds(25),
            sleep: { _ in
                // Opt out right after the first message completes, before m2 starts.
                await MainActor.run {
                    settings.isEnabled = false
                    coordinatorRef?.reconcile()
                }
                try Task.checkCancellation()
            }
        )
        coordinatorRef = coordinator

        await coordinator.runPassNow()

        #expect(spy.bodyFetchIDs == ["m1"])
        #expect(coordinator.state == BackgroundIndexingState.idle)
        #expect(coordinator.pendingCount == 0)
    }

    @Test("resetIndexState clears persisted progress and cancelAccount wipes removed account progress")
    func resetAndAccountRemovalClearProgress() async throws {
        let (store, defaults, suite) = try makeStore("reset")
        defer { defaults.removePersistentDomain(forName: suite) }

        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let m1 = header(id: "m1", daysAgo: 1)
        let spy = IndexingSpyBackend(
            folders: [inbox],
            headersByFolder: ["INBOX": [m1]],
            bodiesByID: ["m1": body(id: "m1")]
        )

        var settings = BackgroundIndexingSettings(
            isEnabled: true,
            windowDays: .days90,
            indexAttachments: false,
            requireUnmeteredNetworkAndPower: true
        )

        let coordinator = BackgroundRecentIndexingCoordinator(
            backendsProvider: { [spy] },
            settingsProvider: { settings },
            environmentProvider: { BackgroundIndexingEnvironmentSnapshot() },
            progressStore: store,
            now: { fixedNow },
            pacingDelay: .zero
        )

        await coordinator.runPassNow()
        #expect(spy.bodyFetchIDs == ["m1"])
        #expect(store.load(accountID: spy.account.id).indexedBodyMessageIDs.contains("m1"))

        await coordinator.resetIndexState()
        // Reset wiped progress and re-ran because settings.isEnabled == true.
        #expect(spy.bodyFetchIDs == ["m1", "m1"])

        settings.isEnabled = false
        coordinator.cancelAccount(spy.account.id, clearProgress: true)
        #expect(store.load(accountID: spy.account.id) == .empty)
        #expect(coordinator.state == BackgroundIndexingState.idle)
    }

    @Test("drains backlogs larger than maxBatchSize across throttled batches and wakes on newly arrived headers")
    func multiBatchBacklogAndForegroundArrivalWake() async throws {
        let (store, defaults, suite) = try makeStore("backlog-wake")
        defer { defaults.removePersistentDomain(forName: suite) }

        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let headers = (1 ... 5).map { header(id: "m\($0)", daysAgo: Double($0)) }
        let bodies = Dictionary(uniqueKeysWithValues: headers.map { ($0.id, body(id: $0.id)) })

        let spy = IndexingSpyBackend(
            folders: [inbox],
            headersByFolder: ["INBOX": headers],
            bodiesByID: bodies
        )
        let settings = BackgroundIndexingSettings(
            isEnabled: true,
            windowDays: .days90,
            indexAttachments: false,
            requireUnmeteredNetworkAndPower: true
        )

        let coordinator = BackgroundRecentIndexingCoordinator(
            backendsProvider: { [spy] },
            settingsProvider: { settings },
            environmentProvider: { BackgroundIndexingEnvironmentSnapshot() },
            progressStore: store,
            now: { fixedNow },
            maxBatchSize: 2,
            pacingDelay: .zero,
            batchInterval: .zero
        )

        await coordinator.runPassNow()
        // All 5 messages drained across 3 consecutive throttled batches of size 2.
        #expect(spy.bodyFetchIDs == ["m1", "m2", "m3", "m4", "m5"])
        #expect(coordinator.state == BackgroundIndexingState.completed)
        #expect(coordinator.pendingCount == 0)

        // Foreground sync brings in a brand-new header after the backlog drained.
        let freshHeader = header(id: "m0-fresh", daysAgo: 0.1)
        spy.addMessage(freshHeader, body: body(id: "m0-fresh"), toFolder: "INBOX")
        coordinator.notifyNewHeadersAvailable()
        for _ in 0 ..< 50 where !spy.bodyFetchIDs.contains("m0-fresh") {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(spy.bodyFetchIDs.contains("m0-fresh"))
        #expect(coordinator.state == BackgroundIndexingState.completed)
    }

    @Test("enabling attachment indexing after body-only pass inspects cached body even when IMAP header hasAttachments is false")
    func attachmentOptInAfterBodyOnlyPassWithIMAPStyleHeader() async throws {
        let (store, defaults, suite) = try makeStore("body-then-att")
        defer { defaults.removePersistentDomain(forName: suite) }

        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        // IMAP listings default hasAttachments = false until body is parsed.
        let msg = header(id: "INBOX:1", daysAgo: 1, hasAttachments: false)
        let pdfLike = BrevBackend.Attachment(id: "att-1", name: "notes.txt", mimeType: "text/plain", sizeBytes: 120)
        let spy = IndexingSpyBackend(
            folders: [inbox],
            headersByFolder: ["INBOX": [msg]],
            bodiesByID: ["INBOX:1": body(id: "INBOX:1", attachments: [pdfLike])],
            cacheBodyAfterFetch: true,
            attachmentPayloads: ["att-1": Data("important follow-up attachment".utf8)]
        )

        var settings = BackgroundIndexingSettings(
            isEnabled: true,
            windowDays: .days90,
            indexAttachments: false,
            requireUnmeteredNetworkAndPower: true
        )

        let coordinator = BackgroundRecentIndexingCoordinator(
            backendsProvider: { [spy] },
            settingsProvider: { settings },
            environmentProvider: { BackgroundIndexingEnvironmentSnapshot() },
            progressStore: store,
            now: { fixedNow },
            pacingDelay: .zero,
            batchInterval: .zero
        )

        // First pass: body-only.
        await coordinator.runPassNow()
        #expect(spy.bodyFetchIDs == ["INBOX:1"])
        #expect(spy.downloadedAttachmentIDs.isEmpty)

        // User later turns on attachment indexing.
        settings.indexAttachments = true
        await coordinator.runPassNow()

        // Cached body revealed att-1 even though header.hasAttachments == false; body was not re-fetched.
        #expect(spy.bodyFetchIDs == ["INBOX:1"])
        #expect(spy.downloadedAttachmentIDs == ["att-1"])
        #expect(spy.indexedAttachments.map(\.attachmentID) == ["att-1"])
    }

    @Test("mid-message pause preserves first attachment and resumes second; transient download and FTS failures retry cleanly")
    func perAttachmentTrackingPauseAndTransientRetries() async throws {
        let (store, defaults, suite) = try makeStore("per-att-retry")
        defer { defaults.removePersistentDomain(forName: suite) }

        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let msg = header(id: "m1", daysAgo: 1, hasAttachments: true)
        let att1 = BrevBackend.Attachment(id: "att-1", name: "first.txt", mimeType: "text/plain", sizeBytes: 64)
        let att2 = BrevBackend.Attachment(id: "att-2", name: "second.txt", mimeType: "text/plain", sizeBytes: 64)
        let att3 = BrevBackend.Attachment(id: "att-3", name: "third.txt", mimeType: "text/plain", sizeBytes: 64)

        let spy = IndexingSpyBackend(
            folders: [inbox],
            headersByFolder: ["INBOX": [msg]],
            bodiesByID: ["m1": body(id: "m1", attachments: [att1, att2, att3])],
            cacheBodyAfterFetch: true,
            attachmentPayloads: [
                "att-1": Data("first document".utf8),
                "att-2": Data("second document".utf8),
                "att-3": Data("third document".utf8)
            ]
        )

        let settings = BackgroundIndexingSettings(
            isEnabled: true,
            windowDays: .days90,
            indexAttachments: true,
            requireUnmeteredNetworkAndPower: true
        )

        var coordinatorRef: BackgroundRecentIndexingCoordinator?
        var shouldPauseOnAtt2 = true
        var shouldFailDownloadAtt2 = true
        var shouldFailFTSAtt3 = true

        spy.onDownloadAttachment = { attachmentID in
            if attachmentID == "att-2", await MainActor.run(body: { shouldPauseOnAtt2 }) {
                await MainActor.run {
                    shouldPauseOnAtt2 = false
                    coordinatorRef?.pause()
                }
                throw CancellationError()
            }
            if attachmentID == "att-2", await MainActor.run(body: { shouldFailDownloadAtt2 }) {
                await MainActor.run { shouldFailDownloadAtt2 = false }
                throw MailBackendError.network(underlying: "temporary disconnect")
            }
        }
        spy.onIndexAttachmentText = { attachmentID in
            if attachmentID == "att-3", await MainActor.run(body: { shouldFailFTSAtt3 }) {
                await MainActor.run { shouldFailFTSAtt3 = false }
                throw MailBackendError.backendSpecific(message: "sqlite busy")
            }
        }

        let coordinator = BackgroundRecentIndexingCoordinator(
            backendsProvider: { [spy] },
            settingsProvider: { settings },
            environmentProvider: { BackgroundIndexingEnvironmentSnapshot() },
            progressStore: store,
            now: { fixedNow },
            pacingDelay: .zero,
            batchInterval: .zero
        )
        coordinatorRef = coordinator

        // Pass 1: att-1 indexes, then pauses cleanly before att-2.
        await coordinator.runPassNow()
        #expect(coordinator.state == BackgroundIndexingState.paused(.userPaused))
        #expect(spy.indexedAttachments.map(\.attachmentID) == ["att-1"])
        #expect(!store.load(accountID: spy.account.id).indexedAttachmentMessageIDs.contains("m1"))

        // Pass 2: att-1 is NOT re-downloaded; att-2 fails download transiently, att-3 fails FTS write transiently.
        await coordinator.runPassNow()
        #expect(spy.downloadedAttachmentIDs.filter { $0 == "att-1" }.count == 1)
        #expect(!store.load(accountID: spy.account.id).indexedAttachmentMessageIDs.contains("m1"))

        // Pass 3: both att-2 and att-3 succeed on retry, message is now marked attachment-complete.
        await coordinator.runPassNow()
        #expect(Set(spy.indexedAttachments.map(\.attachmentID)) == ["att-1", "att-2", "att-3"])
        #expect(store.load(accountID: spy.account.id).indexedAttachmentMessageIDs.contains("m1"))
    }

    @Test("removing the attachment index reconciles progress so Index now re-indexes attachments")
    func attachmentIndexRemovalInvalidatesProgress() async throws {
        let (store, defaults, suite) = try makeStore("invalidate-att")
        defer { defaults.removePersistentDomain(forName: suite) }

        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let msg = header(id: "m1", daysAgo: 1, hasAttachments: true)
        let att = BrevBackend.Attachment(id: "att-1", name: "brief.txt", mimeType: "text/plain", sizeBytes: 64)
        let spy = IndexingSpyBackend(
            folders: [inbox],
            headersByFolder: ["INBOX": [msg]],
            bodiesByID: ["m1": body(id: "m1", attachments: [att])],
            cacheBodyAfterFetch: true,
            attachmentPayloads: ["att-1": Data("brief contents".utf8)]
        )

        let settings = BackgroundIndexingSettings(
            isEnabled: true,
            windowDays: .days90,
            indexAttachments: true,
            requireUnmeteredNetworkAndPower: true
        )
        let coordinator = BackgroundRecentIndexingCoordinator(
            backendsProvider: { [spy] },
            settingsProvider: { settings },
            environmentProvider: { BackgroundIndexingEnvironmentSnapshot() },
            progressStore: store,
            now: { fixedNow },
            pacingDelay: .zero,
            batchInterval: .zero
        )

        await coordinator.runPassNow()
        #expect(spy.downloadedAttachmentIDs == ["att-1"])

        // Simulate Mail Storage "Remove" wiping the live FTS attachment index.
        spy.clearLiveAttachmentIndex()
        await coordinator.runPassNow()

        // Reconciling against empty live FTS re-indexed att-1 without re-fetching body.
        #expect(spy.bodyFetchIDs == ["m1"])
        #expect(spy.downloadedAttachmentIDs == ["att-1", "att-1"])
        #expect(spy.indexedAttachments.map(\.attachmentID) == ["att-1"])
    }

    @Test("excludes Gmail multi-label messages carrying Trash or Spam alongside a custom label")
    func excludesDualLabeledTrashAndSpamMessages() async throws {
        let (store, defaults, suite) = try makeStore("gmail-dual-label")
        defer { defaults.removePersistentDomain(forName: suite) }

        let custom = Folder(id: "Label_Work", name: "Work", role: .custom)
        let trash = Folder(id: "TRASH", name: "Trash", role: .trash)
        let spam = Folder(id: "SPAM", name: "Spam", role: .spam)

        let clean = MessageHeader(
            id: "m-clean",
            threadID: "t-clean",
            folderID: "Label_Work",
            from: Correspondent(name: "A", email: "a@example.org"),
            subject: "Clean work mail",
            snippet: "ok",
            date: fixedNow.addingTimeInterval(-3600),
            labels: ["Label_Work"]
        )
        let trashedAlsoWork = MessageHeader(
            id: "m-trashed-work",
            threadID: "t-trash",
            folderID: "Label_Work",
            from: Correspondent(name: "B", email: "b@example.org"),
            subject: "Trashed work mail",
            snippet: "deleted",
            date: fixedNow.addingTimeInterval(-1800),
            labels: ["Label_Work", "TRASH"]
        )
        let spammedAlsoWork = MessageHeader(
            id: "m-spammed-work",
            threadID: "t-spam",
            folderID: "Label_Work",
            from: Correspondent(name: "C", email: "c@example.org"),
            subject: "Spammed work mail",
            snippet: "junk",
            date: fixedNow.addingTimeInterval(-900),
            labels: ["Label_Work"]
        )

        let spy = IndexingSpyBackend(
            folders: [custom, trash, spam],
            headersByFolder: [
                "Label_Work": [clean, trashedAlsoWork, spammedAlsoWork],
                "TRASH": [trashedAlsoWork],
                "SPAM": [spammedAlsoWork]
            ],
            bodiesByID: [
                "m-clean": body(id: "m-clean"),
                "m-trashed-work": body(id: "m-trashed-work"),
                "m-spammed-work": body(id: "m-spammed-work")
            ]
        )

        let settings = BackgroundIndexingSettings(
            isEnabled: true,
            windowDays: .days90,
            indexAttachments: false,
            requireUnmeteredNetworkAndPower: true
        )
        let coordinator = BackgroundRecentIndexingCoordinator(
            backendsProvider: { [spy] },
            settingsProvider: { settings },
            environmentProvider: { BackgroundIndexingEnvironmentSnapshot() },
            progressStore: store,
            now: { fixedNow },
            pacingDelay: .zero,
            batchInterval: .zero
        )

        await coordinator.runPassNow()
        #expect(spy.bodyFetchIDs == ["m-clean"])
    }

    @Test("uses low-priority BackgroundBodyIndexing seam and does not mark skipped fallback as indexed")
    func usesBackgroundBodyIndexingSeam() async throws {
        let (store, defaults, suite) = try makeStore("bg-body-seam")
        defer { defaults.removePersistentDomain(forName: suite) }

        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let okMsg = header(id: "m-ok", daysAgo: 1)
        let skippedMsg = header(id: "m-skip", daysAgo: 2)
        let spy = IndexingSpyBackend(
            folders: [inbox],
            headersByFolder: ["INBOX": [okMsg, skippedMsg]],
            bodiesByID: ["m-ok": body(id: "m-ok")],
            supportsBackgroundBodyIndexing: true
        )
        spy.onBackgroundBodyIndex = { messageID, _ in
            messageID == "m-ok" ? MessageBody(messageID: "m-ok", html: nil, plainText: "indexed body", attachments: []) : nil
        }

        let settings = BackgroundIndexingSettings(
            isEnabled: true,
            windowDays: .days90,
            indexAttachments: false,
            requireUnmeteredNetworkAndPower: true
        )
        let coordinator = BackgroundRecentIndexingCoordinator(
            backendsProvider: { [spy] },
            settingsProvider: { settings },
            environmentProvider: { BackgroundIndexingEnvironmentSnapshot() },
            progressStore: store,
            now: { fixedNow },
            pacingDelay: .zero,
            batchInterval: .zero
        )

        await coordinator.runPassNow()
        #expect(spy.bodyFetchIDs.isEmpty)
        #expect(spy.backgroundBodyFetchIDs == ["m-ok", "m-skip"])
        let saved = store.load(accountID: spy.account.id)
        #expect(saved.indexedBodyMessageIDs == ["m-ok"])
        #expect(!saved.indexedBodyMessageIDs.contains("m-skip"))
    }
}
