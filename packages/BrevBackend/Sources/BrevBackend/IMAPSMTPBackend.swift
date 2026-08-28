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

import Foundation
import OSLog

enum IMAPBackgroundRefreshPolicy {
    /// Cached pages are already usable. Briefly yield the sole command session so
    /// a foreground message open can start before stale-while-revalidate work.
    static let graceNanoseconds: UInt64 = 200_000_000
}

public final class IMAPSMTPBackend: DeferredStartupWorking, MailBackend, MutationApplying, CachedMessageHeaderProviding,
    SyncHealthReporting, SyncConflictReviewing, SyncHealthRepairing, MailboxBackgroundRefreshing,
    OutboxManaging, ScheduledSendManaging, CardDAVContactSyncSupporting, MessageLabelManaging, @unchecked Sendable {
    private static let bodyFetchLogger = Logger(
        subsystem: "eu.brevmail.brev",
        category: "IMAPBodyFetch"
    )
    private static let initialIDLEResubscribeDelayNanoseconds: UInt64 = 100_000_000
    private static let maximumIDLEResubscribeDelayNanoseconds: UInt64 = 30_000_000_000
    private static let idlePollIntervalNanoseconds: UInt64 = 60_000_000_000
    private static let maximumBackgroundRefreshFolderCount = 12
    private static let searchResultLimit = 50
    private static let defaultServerSearchCandidateLimit = 200
    private static let attachmentSearchPageSize = 50
    private static let cachedMessagePageSize = 50

    public typealias FolderListingOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential) async throws
            -> [IMAPFolderListing]
    public typealias FolderCreateOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID) async throws
            -> Void
    public typealias FolderRenameOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID, Folder.ID) async throws
            -> Void
    public typealias FolderDeleteOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID) async throws
            -> Void
    public typealias MessageListingOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID, String?, Int) async throws
            -> IMAPMessageListingPage
    public typealias MessageSearchOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID, SearchQuery, Int) async throws
            -> [IMAPMessageListing]
    /// Returns one bounded server-search page and a cursor for older matches.
    public typealias MessageSearchPageOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID, SearchQuery, String?, Int) async throws
            -> IMAPMessageListingPage
    public typealias MessageSourceFetchOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID, Int) async throws
            -> IMAPMessageSource
    public typealias MessageBodyFetchOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID, Int) async throws
            -> MessageBody
    public typealias MessagePartFetchOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID, Int, String, String) async throws
            -> Data
    public typealias MessageFlagOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID, [Int], IMAPSystemFlag, Bool) async throws
            -> Void
    public typealias MessageKeywordOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID, [Int], IMAPMessageKeyword, Bool) async throws
            -> Void
    /// Adds (`true`) or removes (`false`) the given Gmail labels on the UIDs.
    public typealias MessageLabelOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID, [Int], [String], Bool) async throws
            -> Void
    public typealias MessageMoveOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID, [Int], Folder.ID) async throws
            -> Void
    public typealias MessageCopyOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID, [Int], Folder.ID) async throws
            -> Void
    public typealias MessagePermanentDeleteOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID, [Int]) async throws
            -> Void
    public typealias MessageSendOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, SMTPMessageSubmission) async throws
            -> SendResult
    /// Refreshes an expired XOAUTH2 credential for one bounded retry.
    public typealias OAuthCredentialRefreshOperation =
        @Sendable (BrevAccount.ID, IMAPAccountConfiguration, MailAccountCredential) async throws
            -> MailAccountCredential
    public typealias MessageAppendOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID, Data, Set<IMAPSystemFlag>) async throws
            -> Int?
    public typealias DraftAppendOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID, Data, Set<IMAPSystemFlag>) async throws
            -> Int
    public typealias IdleEventOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID)
            async -> AsyncThrowingStream<IMAPIdleEvent, any Error>
    /// CONDSTORE delta-sync: given an optional prior `HIGHESTMODSEQ`, returns the
    /// new modseq and any (uid, flags) pairs that changed since the watermark.
    /// Returns `(nil, [])` when the server does not support CONDSTORE.
    /// Returns `(modseq, [])` when `sinceModSeq` equals the current value
    /// (nothing changed).
    public typealias CONDSTORESyncOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, Folder.ID, UInt64?) async throws
            -> (highestModSeq: UInt64?, uidValidity: Int?, changes: [(uid: Int, flags: [String])])
    public typealias ManageSieveRuleSyncOperation =
        @Sendable (IMAPAccountConfiguration, MailAccountCredential, [ServerRule], String) async throws
            -> SieveScriptPlan
    public typealias SessionDisconnectOperation =
        @Sendable (IMAPAccountConfiguration) async -> Void

    public let account: BrevAccount
    /// Capabilities fixed at construction from the injected operations, plus
    /// `.labels` once the server has advertised `X-GM-EXT-1` (detected from a
    /// listing or restored from the folder snapshot).
    public var capabilities: BackendCapabilities {
        var capabilities = staticCapabilities
        if gmailLabelsLock.withLock({ gmailLabelsDetected }) {
            capabilities.insert(.labels)
        }
        return capabilities
    }

    public let extendedCapabilities: BackendExtendedCapabilities
    private let staticCapabilities: BackendCapabilities
    private let gmailLabelsLock = NSLock()
    private var gmailLabelsDetected = false

    private let configuration: IMAPAccountConfiguration
    private let credentialLock = NSLock()
    private var storedCredential: MailAccountCredential
    private var credential: MailAccountCredential {
        credentialLock.withLock { storedCredential }
    }

    private let listFoldersOperation: FolderListingOperation
    private let createFolderOperation: FolderCreateOperation?
    private let renameFolderOperation: FolderRenameOperation?
    private let deleteFolderOperation: FolderDeleteOperation?
    private let listMessagesOperation: MessageListingOperation?
    private let searchMessagesOperation: MessageSearchOperation?
    private let searchMessagePageOperation: MessageSearchPageOperation?
    private let fetchMessageSourceOperation: MessageSourceFetchOperation?
    private let fetchMessageBodyOperation: MessageBodyFetchOperation?
    private let fetchMessagePartOperation: MessagePartFetchOperation?
    private let setMessageFlagOperation: MessageFlagOperation?
    private let setMessageKeywordOperation: MessageKeywordOperation?
    private let setMessageLabelsOperation: MessageLabelOperation?
    private let moveMessagesOperation: MessageMoveOperation?
    private let copyMessagesOperation: MessageCopyOperation?
    private let permanentlyDeleteMessagesOperation: MessagePermanentDeleteOperation?
    private let sendMessageOperation: MessageSendOperation?
    private let refreshOAuthCredentialOperation: OAuthCredentialRefreshOperation?
    /// Shares one expired-token refresh across concurrent authenticated IMAP
    /// mutations. The first failed command performs the refresh; waiters reuse
    /// the persisted replacement before retrying their own command once.
    private let oauthCredentialRefreshCoordinator = IMAPOAuthCredentialRefreshCoordinator()
    private let appendSentMessageOperation: MessageAppendOperation?
    private let appendDraftMessageOperation: DraftAppendOperation?
    private let idleEventsOperation: IdleEventOperation?
    private let condstoreSyncOperation: CONDSTORESyncOperation?
    private let manageSieveRuleSyncOperation: ManageSieveRuleSyncOperation?
    private let disconnectSessionOperation: SessionDisconnectOperation?
    private let folderCache: (any IMAPFolderSnapshotCache)?
    private let headerCache: (any IMAPMailboxHeaderCache)?
    private let sourceCache: (any IMAPMessageSourceCache)?
    private let bodyCache: (any IMAPMessageBodyCache)?
    private let localSearchIndex: (any MailLocalSearchIndex)?
    private let draftStagingStore: (any IMAPDraftStagingStore)?
    private let offlineMutationQueue: (any OfflineMutationQueue)?
    private let offlineMutationConflictStore: (any OfflineMutationConflictStore)?
    /// Optional outbound signing/encryption engine (ADR-0021). When a draft
    /// requests security but this is nil, the send fails closed.
    private let outboundMessagePreparer: (any OutboundMessagePreparing)?
    private let state = IMAPSMTPBackendState()
    /// Injectable contact lookup service. Set by BrevMail after backend creation
    /// when a CardDAV addressbook is available for the account.
    private let contactLookupProviderLock = NSLock()
    private var _contactLookupProvider: (any ContactLookupProviding)?

    // MARK: - Scheduled send

    /// Persisted list of (draftID, scheduledFor) entries.
    private let scheduledSendStore = ScheduledSendStore()
    /// Persisted ledger of confirmed-sent draft IDs, used to skip a re-send of a
    /// draft that already went out (#14). Optional/opt-in: wired in production,
    /// left nil (a no-op) by default so it doesn't add shared state to tests.
    private let sentMessageLedger: SentMessageLedger?
    /// Cancellation-aware polling loop for delivering due scheduled drafts.
    /// Guarded by `scheduledSendTaskLock`: `connect()` (start) and `disconnect()`
    /// (stop) run on the cooperative pool and can race, so this reference must be
    /// swapped atomically like the other Task fields on this `@unchecked Sendable`
    /// class.
    private var scheduledSendTask: Task<Void, Never>?
    private let scheduledSendTaskLock = NSLock()
    /// Serializes scheduled-draft delivery so overlapping triggers (connect, the
    /// 30s poller, and `refresh(folder:)`) can't read the same due entry and
    /// send it twice.
    private let scheduledDeliveryLock = NSLock()
    private var scheduledDeliveryInFlight = false

    /// Poll interval for the scheduled-send loop, and the claim-lease / backoff
    /// bounds used to keep failing sends from re-attempting on every tick.
    private static let scheduledSendPollInterval: UInt64 = 30_000_000_000 // 30s
    private static let scheduledSendClaimLease: TimeInterval = 120 // 2 min
    private static let scheduledSendBackoffBase: TimeInterval = 60 // 1 min
    private static let scheduledSendBackoffMax: TimeInterval = 3600 // 1 hour

    /// Fire-and-forget tasks spawned by `connect()` (remote-draft load, one-shot
    /// delivery). Tracked so `disconnect()` can cancel them rather than leaving
    /// work running against a torn-down session.
    private let backgroundWorkLock = NSLock()
    private var backgroundWorkTasks: [UUID: Task<Void, Never>] = [:]
    /// Remote draft discovery yields while a foreground body read owns the
    /// command session, then resumes once the final foreground read finishes.
    private let remoteDraftDiscoveryLock = NSLock()
    private var remoteDraftDiscoveryTask: (id: UUID, task: Task<Void, Never>)?
    private var hasPendingRemoteDraftDiscoveryRetry = false
    private var foregroundIMAPReadCount = 0
    /// Sync-health polling runs every few seconds while an account is visible.
    /// Keep directory-size walks off that path so a large cache cannot occupy
    /// the same cache actor needed by a foreground message open.
    private let cacheSizeMetricsLock = NSLock()
    private var cachedMessageCacheSizeBytes = 0
    private var cacheSizeMetricsRefreshInFlight = false
    private var lastCacheSizeMetricsRefreshAt: Date?
    private static let cacheSizeMetricsRefreshInterval: TimeInterval = 60
    private let deferredStartupLock = NSLock()
    private var didStartDeferredStartupWork = false

    public var contactLookupProvider: (any ContactLookupProviding)? {
        get { contactLookupProviderLock.withLock { _contactLookupProvider } }
        set { contactLookupProviderLock.withLock { _contactLookupProvider = newValue } }
    }

    public init(
        account: BrevAccount,
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        listFolders: @escaping FolderListingOperation,
        createFolder: FolderCreateOperation? = nil,
        renameFolder: FolderRenameOperation? = nil,
        deleteFolder: FolderDeleteOperation? = nil,
        listMessages: MessageListingOperation? = nil,
        searchMessages: MessageSearchOperation? = nil,
        searchMessagePage: MessageSearchPageOperation? = nil,
        fetchMessageSource: MessageSourceFetchOperation? = nil,
        fetchMessageBody: MessageBodyFetchOperation? = nil,
        fetchMessagePart: MessagePartFetchOperation? = nil,
        setMessageFlag: MessageFlagOperation? = nil,
        setMessageKeyword: MessageKeywordOperation? = nil,
        setMessageLabels: MessageLabelOperation? = nil,
        moveMessages: MessageMoveOperation? = nil,
        copyMessages: MessageCopyOperation? = nil,
        permanentlyDeleteMessages: MessagePermanentDeleteOperation? = nil,
        sendMessage: MessageSendOperation? = nil,
        refreshOAuthCredential: OAuthCredentialRefreshOperation? = nil,
        appendSentMessage: MessageAppendOperation? = nil,
        appendDraftMessage: DraftAppendOperation? = nil,
        idleEvents: IdleEventOperation? = nil,
        condstoreSync: CONDSTORESyncOperation? = nil,
        manageSieveRuleSync: ManageSieveRuleSyncOperation? = nil,
        disconnectSession: SessionDisconnectOperation? = nil,
        folderCache: (any IMAPFolderSnapshotCache)? = nil,
        headerCache: (any IMAPMailboxHeaderCache)? = nil,
        sourceCache: (any IMAPMessageSourceCache)? = nil,
        bodyCache: (any IMAPMessageBodyCache)? = nil,
        localSearchIndex: (any MailLocalSearchIndex)? = nil,
        draftStagingStore: (any IMAPDraftStagingStore)? = nil,
        offlineMutationQueue: (any OfflineMutationQueue)? = nil,
        offlineMutationConflictStore: (any OfflineMutationConflictStore)? = nil,
        outboundMessagePreparer: (any OutboundMessagePreparing)? = nil,
        sentMessageLedger: SentMessageLedger? = nil
    ) {
        self.account = account
        self.configuration = configuration
        storedCredential = credential
        listFoldersOperation = listFolders
        createFolderOperation = createFolder
        renameFolderOperation = renameFolder
        deleteFolderOperation = deleteFolder
        listMessagesOperation = listMessages
        searchMessagesOperation = searchMessages
        searchMessagePageOperation = searchMessagePage
        fetchMessageSourceOperation = fetchMessageSource
        fetchMessageBodyOperation = fetchMessageBody
        fetchMessagePartOperation = fetchMessagePart
        setMessageFlagOperation = setMessageFlag
        setMessageKeywordOperation = setMessageKeyword
        setMessageLabelsOperation = setMessageLabels
        moveMessagesOperation = moveMessages
        copyMessagesOperation = copyMessages
        permanentlyDeleteMessagesOperation = permanentlyDeleteMessages
        sendMessageOperation = sendMessage
        refreshOAuthCredentialOperation = refreshOAuthCredential
        appendSentMessageOperation = appendSentMessage
        appendDraftMessageOperation = appendDraftMessage
        idleEventsOperation = idleEvents
        condstoreSyncOperation = condstoreSync
        manageSieveRuleSyncOperation = manageSieveRuleSync
        disconnectSessionOperation = disconnectSession
        self.folderCache = folderCache
        self.headerCache = headerCache
        self.sourceCache = sourceCache
        self.bodyCache = bodyCache
        self.localSearchIndex = localSearchIndex
        self.draftStagingStore = draftStagingStore
        self.offlineMutationQueue = offlineMutationQueue
        self.offlineMutationConflictStore = offlineMutationConflictStore
        self.outboundMessagePreparer = outboundMessagePreparer
        self.sentMessageLedger = sentMessageLedger
        var advertisedCapabilities: BackendCapabilities = [.providerSyncHealth]
        if createFolder != nil {
            advertisedCapabilities.insert(.folderCreate)
        }
        if renameFolder != nil {
            advertisedCapabilities.insert(.folderRename)
        }
        if deleteFolder != nil {
            advertisedCapabilities.insert(.folderDelete)
        }
        if listMessages != nil, permanentlyDeleteMessages != nil {
            advertisedCapabilities.insert(.folderFlush)
        }
        if searchMessages != nil || searchMessagePage != nil {
            advertisedCapabilities.insert(.serverSideSearch)
        }
        if sendMessage != nil {
            advertisedCapabilities.insert(.smtpOAuth)
        }
        if idleEvents != nil {
            advertisedCapabilities.insert(.idleSync)
        }
        if setMessageKeyword != nil {
            advertisedCapabilities.insert(.junkAPI)
        }
        if configuration.manageSieve != nil, manageSieveRuleSync != nil {
            advertisedCapabilities.insert(.manageSieve)
        }
        staticCapabilities = advertisedCapabilities

        // Conversations are derived locally from RFC 5322 reply links, which
        // every listing carries — no server thread extension required
        // (ADR-0052).
        var advertisedExtendedCapabilities: BackendExtendedCapabilities = [
            .clientSideThreading,
            .cachedMessageHeaders,
        ]
        if copyMessages != nil {
            advertisedExtendedCapabilities.insert(.messageCopy)
        }
        if fetchMessageSource != nil {
            advertisedExtendedCapabilities.insert(.rawMessageSource)
        }
        extendedCapabilities = advertisedExtendedCapabilities
    }

    public func connect() async throws {
        try await connect(retryOAuthCredential: true)
    }

    private func connect(retryOAuthCredential: Bool) async throws {
        do {
            try Task.checkCancellation()
            let listings = try await listFoldersOperation(configuration, credential)
            try Task.checkCancellation()
            let folders = Self.folders(from: listings)
            let folderDelimitersByID = Self.folderDelimiters(from: listings)
            let previousFolderSnapshot = await folderCache?.snapshot(accountID: account.id)
            await state.install(
                folders: folders,
                folderDelimitersByID: folderDelimitersByID
            )
            await reconcileRemovedCachedFolders(
                previousFolders: previousFolderSnapshot?.folders ?? [],
                currentFolders: folders
            )
            if previousFolderSnapshot?.supportsGmailLabels == true {
                noteGmailLabelSupport()
            }
            await folderCache?.setSnapshot(
                IMAPFolderCacheSnapshot(
                    folders: folders,
                    folderDelimitersByID: folderDelimitersByID,
                    supportsGmailLabels: gmailLabelsLock.withLock { gmailLabelsDetected }
                ),
                accountID: account.id
            )
            // Keep connect on the critical path for folder install + first paint.
            // The root explicitly starts pollers, draft hydration, and due-send
            // delivery after the first usable content frame.
        } catch {
            if error is CancellationError {
                throw error
            }
            if retryOAuthCredential,
               credential.authentication == .xoauth2,
               Self.isAuthenticationFailure(error),
               let refreshOAuthCredentialOperation {
                let refreshedCredential = try await refreshOAuthCredentialOperation(
                    account.id,
                    configuration,
                    credential
                )
                replaceCredentialForReconnect(refreshedCredential)
                try await connect(retryOAuthCredential: false)
                return
            }
            if Self.shouldUseCacheFallback(for: error),
               let cachedSnapshot = await folderCache?.snapshot(accountID: account.id),
               !cachedSnapshot.folders.isEmpty {
                if cachedSnapshot.supportsGmailLabels {
                    noteGmailLabelSupport()
                }
                await state.installCached(
                    folders: cachedSnapshot.folders,
                    folderDelimitersByID: cachedSnapshot.folderDelimitersByID,
                    errorDescription: Self.userFacingDescription(for: error)
                )
                return
            }
            // Cache-first startup may already have made the mailbox readable.
            // Preserve that state if remote reconciliation fails (including an
            // expired OAuth token) so the caller can recover without blanking
            // the inbox.
            if await state.hasUsableFolders() {
                await state.recordBackgroundSyncFailure(Self.userFacingDescription(for: error))
                throw error
            }
            await state.recordSyncFailure(Self.userFacingDescription(for: error))
            throw error
        }
    }

    /// Installs a persisted, non-empty folder snapshot for immediate local
    /// startup while the connector validates the IMAP session in background.
    /// Returns false for fresh accounts and empty or unavailable snapshots.
    func restoreCachedFoldersForStartup() async -> Bool {
        guard let snapshot = await folderCache?.snapshot(accountID: account.id),
              !snapshot.folders.isEmpty
        else {
            return false
        }
        if snapshot.supportsGmailLabels {
            noteGmailLabelSupport()
        }
        await state.installStartupCache(
            folders: snapshot.folders,
            folderDelimitersByID: snapshot.folderDelimitersByID
        )
        return true
    }

    /// Replaces an expiring OAuth credential before retrying the same backend.
    /// The lock keeps the backend's concurrent IMAP operations on one coherent
    /// credential snapshot.
    func replaceCredentialForReconnect(_ credential: MailAccountCredential) {
        credentialLock.withLock { storedCredential = credential }
    }

    private func reconcileRemovedCachedFolders(
        previousFolders: [Folder],
        currentFolders: [Folder]
    ) async {
        let currentFolderIDs = Set(currentFolders.map(\.id))
        let removedFolderIDs = previousFolders
            .map(\.id)
            .filter { !currentFolderIDs.contains($0) }
        guard !removedFolderIDs.isEmpty else { return }

        for folderID in removedFolderIDs {
            if let snapshot = await cachedHeaderSnapshot(folderID: folderID) {
                await sourceCache?.removeSources(
                    messageIDs: snapshot.headers.map(\.id),
                    accountID: account.id
                )
            }
            await bodyCache?.removeBodies(inFolder: folderID, accountID: account.id)
            await headerCache?.clear(accountID: account.id, folderID: folderID)
            await localSearchIndex?.clearFolder(folderID: folderID, account: account)
        }
    }

    public func disconnect() async {
        stopScheduledSendPoller()
        cancelBackgroundWork()
        cancelRemoteDraftDiscovery()
        deferredStartupLock.withLock { didStartDeferredStartupWork = false }
        cancelBackgroundRefreshTasks()
        cancelBackgroundDateRepairTasks()
        await disconnectSessionOperation?(configuration)
        await state.disconnect()
    }

    /// Spawns a tracked fire-and-forget task that is cancelled on `disconnect()`.
    func trackBackgroundWork(_ work: @escaping @Sendable () async -> Void) {
        let id = UUID()
        let task = Task(priority: .utility) { [weak self] in
            await Task.yield()
            await work()
            self?.finishBackgroundWork(id: id)
        }
        backgroundWorkLock.withLock { backgroundWorkTasks[id] = task }
    }

    private func finishBackgroundWork(id: UUID) {
        _ = backgroundWorkLock.withLock {
            backgroundWorkTasks.removeValue(forKey: id)
        }
    }

    private func cachedMessageCacheSizeBytesForSyncHealth() -> Int {
        scheduleMessageCacheSizeRefreshIfNeeded()
        return cacheSizeMetricsLock.withLock { cachedMessageCacheSizeBytes }
    }

    private func scheduleMessageCacheSizeRefreshIfNeeded() {
        let shouldRefresh = cacheSizeMetricsLock.withLock { () -> Bool in
            guard !cacheSizeMetricsRefreshInFlight else { return false }
            if let lastCacheSizeMetricsRefreshAt,
               Date().timeIntervalSince(lastCacheSizeMetricsRefreshAt) < Self.cacheSizeMetricsRefreshInterval {
                return false
            }
            cacheSizeMetricsRefreshInFlight = true
            return true
        }
        guard shouldRefresh else { return }

        let accountID = account.id
        let sourceCache = sourceCache
        let bodyCache = bodyCache
        Task(priority: .utility) { [weak self] in
            let sourceCacheBytes = await sourceCache?.sizeBytes(accountID: accountID) ?? 0
            let bodyCacheBytes = await bodyCache?.sizeBytes(accountID: accountID) ?? 0
            guard !Task.isCancelled, let self else { return }
            cacheSizeMetricsLock.withLock {
                self.cachedMessageCacheSizeBytes = sourceCacheBytes + bodyCacheBytes
                self.lastCacheSizeMetricsRefreshAt = Date()
                self.cacheSizeMetricsRefreshInFlight = false
            }
        }
    }

    private func cancelBackgroundWork() {
        let tasks = backgroundWorkLock.withLock {
            let snapshot = Array(backgroundWorkTasks.values)
            backgroundWorkTasks.removeAll()
            return snapshot
        }
        for task in tasks {
            task.cancel()
        }
    }

    public func replayOfflineMutations() async {
        _ = try? await replayPendingMutations()
    }

    public func replayOfflineMutations(processSends: Bool) async {
        _ = try? await replayPendingMutations(processSends: processSends)
    }

    public func folders() async throws -> [Folder] {
        try await state.requireConnectedFolders()
    }

    public func folders(in sourceID: MailSourceID) async throws -> [Folder] {
        try validateSourceID(sourceID)
        return try await folders()
    }

    public func refresh(folder: Folder) async throws {
        await state.recordActiveMessageFolder(folder.id)
        try await connect()
        try await refreshConnectedFolderFirstPage(folder)
    }

    public func refresh(folder: Folder, in sourceID: MailSourceID) async throws {
        try validateSourceID(sourceID)
        try await refresh(folder: folder)
    }

    private func refreshConnectedFolderFirstPage(_ folder: Folder) async throws {
        guard listMessagesOperation != nil else { return }
        try Task.checkCancellation()

        // CONDSTORE delta-sync: if we have a modseq watermark and a delta-sync
        // operation, check whether anything changed before doing a full fetch.
        if condstoreSyncOperation != nil,
           let cachedModSeq = await cachedHeaderSnapshot(folderID: folder.id)?.highestModSeq {
            if let result = try? await condstoreSyncWithAuthenticatedOAuthRetry(
                folderID: folder.id,
                sinceModSeq: cachedModSeq
            ) {
                // A changed UIDVALIDITY (mailbox recreated/renumbered) invalidates
                // the cache even when HIGHESTMODSEQ coincidentally matches. Reconcile
                // it first and never take the "nothing changed" early-return when it
                // changed — fall through to a full refetch instead.
                let uidValidityChanged = await reconcileUIDValidity(result.uidValidity, folderID: folder.id)
                if !uidValidityChanged, let newModSeq = result.highestModSeq, newModSeq == cachedModSeq {
                    // Nothing changed — skip the full header fetch entirely.
                    await state.clearBackgroundSyncFailure()
                    return
                }
                // Apply flag changes for messages already in cache.
                if !result.changes.isEmpty {
                    await applyCONDSTOREFlagChanges(result.changes, folderID: folder.id, newHighestModSeq: result.highestModSeq)
                } else if let newModSeq = result.highestModSeq {
                    await updateCachedHighestModSeq(newModSeq, folderID: folder.id)
                }
                // Fall through to full fetch so new messages are picked up.
            }
        }

        let page = try await listMessagesWithAuthenticatedOAuthRetry(
            folderID: folder.id,
            pageToken: nil,
            limit: 50
        )
        try Task.checkCancellation()
        await recordGmailLabelSupport(from: page)
        let headers = page.messages.map { Self.header(from: $0, folderID: folder.id) }
        await reconcileUIDValidity(page.uidValidity, folderID: folder.id)
        let headerChangeEvents = await reconcileFirstPageHeaderChanges(
            headers,
            folderID: folder.id,
            removesMissingHeaders: page.nextPageToken == nil
        )
        await cacheHeaders(
            headers,
            folderID: folder.id,
            uidValidity: page.uidValidity,
            highestModSeq: page.highestModSeq,
            nextPageToken: page.nextPageToken
        )
        await emit(headerChangeEvents)
        await state.recordListedMessageIDs(
            headers.map(\.id),
            folderID: folder.id,
            isCompleteFolderWindow: page.nextPageToken == nil
        )
        await state.clearBackgroundSyncFailure()
    }

    public func createFolder(name: String, parentID: Folder.ID?) async throws -> Folder {
        try await state.requireConnected()
        guard let createFolderOperation else {
            throw MailBackendError.notSupported(.folderCreate)
        }
        let folderID = await folderID(name: name, parentID: parentID)
        try await withAuthenticatedOAuthRetry { credential in
            try await createFolderOperation(self.configuration, credential, folderID)
        }
        try await connect()
        return await state.folder(id: folderID) ?? Folder(
            id: folderID,
            name: name,
            role: .custom,
            parentID: parentID
        )
    }

    public func createFolder(
        name: String,
        parentID: Folder.ID?,
        sourceID: MailSourceID
    ) async throws -> Folder {
        try validateSourceID(sourceID)
        return try await createFolder(name: name, parentID: parentID)
    }

    public func renameFolder(id: Folder.ID, name: String) async throws -> Folder {
        try await state.requireConnected()
        guard let renameFolderOperation else {
            throw MailBackendError.notSupported(.folderRename)
        }
        let currentFolder = await state.folder(id: id)
        let parentID = currentFolder?.parentID ?? Self.parentFolderID(from: id)
        let newFolderID = await folderID(name: name, parentID: parentID)
        try await withAuthenticatedOAuthRetry { credential in
            try await renameFolderOperation(self.configuration, credential, id, newFolderID)
        }
        await clearLocalCaches()
        try await connect()
        return await state.folder(id: newFolderID) ?? Folder(
            id: newFolderID,
            name: name,
            role: currentFolder?.role ?? .custom,
            parentID: parentID
        )
    }

    public func renameFolder(
        id: Folder.ID,
        name: String,
        sourceID: MailSourceID
    ) async throws -> Folder {
        try validateSourceID(sourceID)
        return try await renameFolder(id: id, name: name)
    }

    public func deleteFolder(id: Folder.ID) async throws {
        try await state.requireConnected()
        guard let deleteFolderOperation else {
            throw MailBackendError.notSupported(.folderDelete)
        }
        try await withAuthenticatedOAuthRetry { credential in
            try await deleteFolderOperation(self.configuration, credential, id)
        }
        await clearLocalCaches()
        try await connect()
    }

    public func deleteFolder(id: Folder.ID, sourceID: MailSourceID) async throws {
        try validateSourceID(sourceID)
        try await deleteFolder(id: id)
    }

    public func flushFolder(id: Folder.ID) async throws {
        try await state.requireConnected()
        guard listMessagesOperation != nil,
              let permanentlyDeleteMessagesOperation
        else {
            throw MailBackendError.notSupported(.folderFlush)
        }

        var pageToken: String?
        var visitedPageTokens = Set<String>()
        while true {
            if let pageToken,
               !visitedPageTokens.insert(pageToken).inserted {
                throw MailBackendError.backendSpecific(
                    message: "IMAP folder flush did not advance the page cursor."
                )
            }
            let page = try await listMessagesWithAuthenticatedOAuthRetry(
                folderID: id,
                pageToken: pageToken,
                limit: 100
            )
            let uids = page.messages.map(\.uid)
            if !uids.isEmpty {
                try await withAuthenticatedOAuthRetry { credential in
                    try await permanentlyDeleteMessagesOperation(
                        self.configuration,
                        credential,
                        id,
                        uids
                    )
                }
            }
            guard let nextPageToken = page.nextPageToken else { break }
            pageToken = nextPageToken
        }
        await clearLocalCaches()
    }

    public func flushFolder(id: Folder.ID, sourceID: MailSourceID) async throws {
        try validateSourceID(sourceID)
        try await flushFolder(id: id)
    }

    public func messages(
        in folder: Folder,
        pageToken: String?
    ) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        try await messages(in: folder, pageToken: pageToken, recordsActiveFolder: true)
    }

    public func enumerateMessages(
        in folder: Folder,
        pageToken: String?
    ) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        try await messages(in: folder, pageToken: pageToken, recordsActiveFolder: false)
    }

    public func enumerateMessages(
        in folder: Folder,
        sourceID: MailSourceID,
        pageToken: String?
    ) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        try validateSourceID(sourceID)
        return try await messages(in: folder, pageToken: pageToken, recordsActiveFolder: false)
    }

    /// Every listing path — live FETCH, header cache, search index, offline
    /// fallback — funnels through here, so conversations are resolved exactly
    /// once, against everything currently known about the folder (ADR-0052).
    private func messages(
        in folder: Folder,
        pageToken: String?,
        recordsActiveFolder: Bool
    ) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        let page = try await unthreadedMessages(
            in: folder,
            pageToken: pageToken,
            recordsActiveFolder: recordsActiveFolder
        )
        return await (
            headers: threadedHeaders(page.headers, folderID: folder.id),
            nextPageToken: page.nextPageToken
        )
    }

    /// Resolves conversations for `headers` against the folder's cached
    /// headers, so a reply that arrives on page 2 still joins the message it
    /// answers on page 1. Resolution is pure and idempotent: it reads
    /// `messageID`/`inReplyTo` and never its own output.
    private func threadedHeaders(
        _ headers: [MessageHeader],
        folderID: Folder.ID
    ) async -> [MessageHeader] {
        guard headers.contains(where: { $0.inReplyTo != nil }) || headers.count > 1 else {
            return headers
        }
        let cached = await cachedHeaderSnapshot(folderID: folderID)?.headers ?? []
        guard !cached.isEmpty else {
            return MessageThreadResolver.resolved(headers)
        }
        let headerIDs = Set(headers.map(\.id))
        let known = headers + cached.filter { !headerIDs.contains($0.id) }
        let threadIDs = MessageThreadResolver.threadIDsByHeaderID(for: known)
        return headers.map { header in
            guard let threadID = threadIDs[header.id],
                  threadID != header.threadID
            else {
                return header
            }
            return header.withThreadID(threadID)
        }
    }

    private func unthreadedMessages(
        in folder: Folder,
        pageToken: String?,
        recordsActiveFolder: Bool
    ) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        let interval = MailPerformanceDiagnostics.beginInterval("IMAP Messages Page")
        defer { MailPerformanceDiagnostics.endInterval(interval) }
        let pageTokenPresent = pageToken != nil
        func durationMilliseconds() -> Int {
            MailPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
        }
        func logFinished(
            path: MailPerformanceDiagnostics.MessagePagePath,
            headers: [MessageHeader],
            nextPageToken: String?
        ) {
            MailPerformanceDiagnostics.logMessagePageFinished(
                path: path,
                pageTokenPresent: pageTokenPresent,
                resultCount: headers.count,
                hasNextPage: nextPageToken != nil,
                durationMilliseconds: durationMilliseconds()
            )
        }

        if pageToken == nil, recordsActiveFolder {
            await state.recordActiveMessageFolder(folder.id)
        }
        if let cachedPage = await cachedMessagePage(in: folder, pageToken: pageToken) {
            await state.recordListedMessageIDs(
                cachedPage.headers.map(\.id),
                folderID: folder.id,
                isCompleteFolderWindow: cachedPage.nextPageToken == nil
            )
            if pageToken == nil {
                scheduleFirstPageRefreshAfterCachedReturn(folder)
            }
            logFinished(
                path: .cacheHit,
                headers: cachedPage.headers,
                nextPageToken: cachedPage.nextPageToken
            )
            return cachedPage
        }

        do {
            try await state.requireConnected()
        } catch {
            if let indexedPage = await localSearchIndex?.cachedHeaders(
                for: folder,
                account: account,
                pageToken: pageToken
            ) {
                await state.recordListedMessageIDs(
                    indexedPage.headers.map(\.id),
                    folderID: folder.id,
                    isCompleteFolderWindow: indexedPage.nextPageToken == nil
                )
                logFinished(
                    path: .cacheHit,
                    headers: indexedPage.headers,
                    nextPageToken: indexedPage.nextPageToken
                )
                return indexedPage
            }
            // Offline while paginating a cache-served folder: the first page
            // already returned every cached header, so there's nothing more to
            // serve offline. End pagination gracefully rather than surfacing a
            // notConnected error in the flow this branch makes cache-first.
            if pageToken != nil, Self.shouldUseCacheFallback(for: error) {
                logFinished(path: .offlinePaginationEnd, headers: [], nextPageToken: nil)
                return (headers: [], nextPageToken: nil)
            }
            MailPerformanceDiagnostics.logMessagePageFailed(
                pageTokenPresent: pageTokenPresent,
                error: error,
                durationMilliseconds: durationMilliseconds()
            )
            throw error
        }
        guard listMessagesOperation != nil else {
            if pageToken == nil,
               let cachedSnapshot = await cachedHeaderSnapshot(folderID: folder.id) {
                let repairedSnapshot = await repairedCachedHeaderSnapshotIfNeeded(
                    cachedSnapshot,
                    folderID: folder.id
                )
                await state.recordListedMessageIDs(
                    repairedSnapshot.headers.map(\.id),
                    folderID: folder.id
                )
                logFinished(
                    path: .cacheFallback,
                    headers: repairedSnapshot.headers,
                    nextPageToken: repairedSnapshot.nextPageToken
                )
                return (
                    headers: repairedSnapshot.headers,
                    nextPageToken: repairedSnapshot.nextPageToken
                )
            }
            let error = MailBackendError.notSupported(capabilities)
            MailPerformanceDiagnostics.logMessagePageFailed(
                pageTokenPresent: pageTokenPresent,
                error: error,
                durationMilliseconds: durationMilliseconds()
            )
            throw error
        }
        do {
            let page = try await listMessagesWithAuthenticatedOAuthRetry(
                folderID: folder.id,
                pageToken: pageToken,
                limit: 50
            )
            await recordGmailLabelSupport(from: page)
            let headers = page.messages.map { Self.header(from: $0, folderID: folder.id) }
            if pageToken == nil {
                await reconcileUIDValidity(page.uidValidity, folderID: folder.id)
                let headerChangeEvents = await reconcileFirstPageHeaderChanges(
                    headers,
                    folderID: folder.id,
                    removesMissingHeaders: page.nextPageToken == nil
                )
                await cacheHeaders(
                    headers,
                    folderID: folder.id,
                    uidValidity: page.uidValidity,
                    highestModSeq: page.highestModSeq,
                    nextPageToken: page.nextPageToken
                )
                await emit(headerChangeEvents)
                await state.recordListedMessageIDs(
                    headers.map(\.id),
                    folderID: folder.id,
                    isCompleteFolderWindow: page.nextPageToken == nil
                )
            } else {
                var headerChangeEvents: [MailEvent] = []
                if let updateEvent = await cachedHeaderUpdateEvent(
                    headers,
                    folderID: folder.id
                ) {
                    headerChangeEvents.append(updateEvent)
                }
                if let removalEvent = await reconcileCachedPageRemovals(
                    headers,
                    folderID: folder.id,
                    pageToken: pageToken
                ) {
                    headerChangeEvents.append(removalEvent)
                }
                await cacheHeaders(
                    headers,
                    folderID: folder.id,
                    nextPageToken: page.nextPageToken,
                    mergingWithExisting: true,
                    loadedPageToken: pageToken
                )
                await emit(headerChangeEvents)
            }
            logFinished(path: .server, headers: headers, nextPageToken: page.nextPageToken)
            return (
                headers: headers,
                nextPageToken: page.nextPageToken
            )
        } catch {
            if pageToken == nil,
               Self.shouldUseCacheFallback(for: error),
               let cachedSnapshot = await cachedHeaderSnapshot(folderID: folder.id) {
                let repairedSnapshot = await repairedCachedHeaderSnapshotIfNeeded(
                    cachedSnapshot,
                    folderID: folder.id
                )
                await state.recordListedMessageIDs(
                    repairedSnapshot.headers.map(\.id),
                    folderID: folder.id,
                    isCompleteFolderWindow: repairedSnapshot.nextPageToken == nil
                )
                logFinished(
                    path: .cacheFallback,
                    headers: repairedSnapshot.headers,
                    nextPageToken: repairedSnapshot.nextPageToken
                )
                return (
                    headers: repairedSnapshot.headers,
                    nextPageToken: repairedSnapshot.nextPageToken
                )
            }
            // Connection lost mid-pagination — stop gracefully rather than
            // throwing, leaving the already-shown cached headers in place.
            if pageToken != nil, Self.shouldUseCacheFallback(for: error) {
                logFinished(path: .offlinePaginationEnd, headers: [], nextPageToken: nil)
                return (headers: [], nextPageToken: nil)
            }
            MailPerformanceDiagnostics.logMessagePageFailed(
                pageTokenPresent: pageTokenPresent,
                error: error,
                durationMilliseconds: durationMilliseconds()
            )
            throw error
        }
    }

    /// Internal pagination tokens keep local cache offsets separate from
    /// provider-owned IMAP cursors, which are opaque and must never be passed
    /// to the SQLite index.
    private enum CachedMessagePageToken {
        private static let indexPrefix = "__brev_cache_index__:"
        private static let snapshotPrefix = "__brev_cache_snapshot__:"

        case index(offset: Int, indexPageToken: String)
        case snapshot(offset: Int)

        init?(rawValue: String) {
            if rawValue.hasPrefix(Self.indexPrefix) {
                let payload = rawValue.dropFirst(Self.indexPrefix.count)
                let parts = payload.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2,
                      let offset = Int(parts[0]), offset >= 0,
                      let data = Data(base64Encoded: String(parts[1])),
                      let indexPageToken = String(data: data, encoding: .utf8)
                else {
                    return nil
                }
                self = .index(offset: offset, indexPageToken: indexPageToken)
                return
            }
            guard rawValue.hasPrefix(Self.snapshotPrefix),
                  let offset = Int(rawValue.dropFirst(Self.snapshotPrefix.count)), offset >= 0
            else {
                return nil
            }
            self = .snapshot(offset: offset)
        }

        static func index(offset: Int, indexPageToken: String) -> String {
            "\(indexPrefix)\(offset):\(Data(indexPageToken.utf8).base64EncodedString())"
        }

        static func snapshot(offset: Int) -> String {
            "\(snapshotPrefix)\(offset)"
        }
    }

    /// Returns a bounded locally cached page when one exists. The SQLite index
    /// is authoritative because it pages a large mailbox without decoding or
    /// handing every cached header to SwiftUI. The file snapshot remains a
    /// migration/offline fallback until its rows have reached the index.
    private func cachedMessagePage(
        in folder: Folder,
        pageToken: String?
    ) async -> (headers: [MessageHeader], nextPageToken: String?)? {
        if let pageToken,
           let cachedToken = CachedMessagePageToken(rawValue: pageToken) {
            switch cachedToken {
            case .index(let offset, let indexPageToken):
                return await cachedLocalIndexPage(
                    in: folder,
                    indexPageToken: indexPageToken,
                    offset: offset
                )
            case .snapshot(let offset):
                return await cachedHeaderSnapshotPage(in: folder, offset: offset)
            }
        }

        guard pageToken == nil else { return nil }
        if let indexedPage = await cachedLocalIndexPage(
            in: folder,
            indexPageToken: nil,
            offset: 0
        ) {
            return indexedPage
        }
        return await cachedHeaderSnapshotPage(in: folder, offset: 0)
    }

    private func cachedLocalIndexPage(
        in folder: Folder,
        indexPageToken: String?,
        offset: Int
    ) async -> (headers: [MessageHeader], nextPageToken: String?)? {
        guard let indexedPage = await localSearchIndex?.cachedHeaders(
            for: folder,
            account: account,
            pageToken: indexPageToken
        ) else {
            return nil
        }

        let nextPageToken: String?
        if let nextIndexPageToken = indexedPage.nextPageToken {
            nextPageToken = CachedMessagePageToken.index(
                offset: offset + indexedPage.headers.count,
                indexPageToken: nextIndexPageToken
            )
        } else if let snapshot = await cachedHeaderSnapshot(folderID: folder.id),
                  snapshot.headers.count > offset + indexedPage.headers.count {
            nextPageToken = CachedMessagePageToken.snapshot(
                offset: offset + indexedPage.headers.count
            )
        } else {
            nextPageToken = await cachedHeaderSnapshot(folderID: folder.id)?.nextPageToken
        }

        return (headers: indexedPage.headers, nextPageToken: nextPageToken)
    }

    private func cachedHeaderSnapshotPage(
        in folder: Folder,
        offset: Int
    ) async -> (headers: [MessageHeader], nextPageToken: String?)? {
        guard let snapshot = await cachedHeaderSnapshot(folderID: folder.id) else {
            return nil
        }
        let repairedSnapshot = await repairedCachedHeaderSnapshotIfNeeded(
            snapshot,
            folderID: folder.id
        )
        let start = min(offset, repairedSnapshot.headers.count)
        let end = min(start + Self.cachedMessagePageSize, repairedSnapshot.headers.count)
        let nextPageToken = end < repairedSnapshot.headers.count
            ? CachedMessagePageToken.snapshot(offset: end)
            : repairedSnapshot.nextPageToken
        return (
            headers: Array(repairedSnapshot.headers[start ..< end]),
            nextPageToken: nextPageToken
        )
    }

    /// Most recent background first-page refresh task per folder, spawned after
    /// serving a cached page. Keyed by folder so a new request cancels the prior
    /// in-flight one (N rapid reloads → 1 fetch) and `disconnect()` can cancel
    /// them all rather than leaving fetches running against a closed session.
    private let backgroundRefreshLock = NSLock()
    private var backgroundRefreshTasks: [Folder.ID: Task<Void, Never>] = [:]

    private func scheduleFirstPageRefreshAfterCachedReturn(_ folder: Folder) {
        guard listMessagesOperation != nil else { return }
        let task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: IMAPBackgroundRefreshPolicy.graceNanoseconds)
                try Task.checkCancellation()
                try await refreshConnectedFolderFirstPage(folder)
            } catch is CancellationError {
                // A newer refresh cancelled this one — not a user-facing failure.
            } catch {
                await state.recordBackgroundSyncFailure(Self.userFacingDescription(for: error))
            }
        }
        let previous: Task<Void, Never>? = backgroundRefreshLock.withLock {
            let existing = backgroundRefreshTasks[folder.id]
            backgroundRefreshTasks[folder.id] = task
            return existing
        }
        previous?.cancel()
    }

    private func cancelBackgroundRefreshTasks() {
        let tasks = backgroundRefreshLock.withLock {
            let snapshot = Array(backgroundRefreshTasks.values)
            backgroundRefreshTasks.removeAll()
            return snapshot
        }
        for task in tasks {
            task.cancel()
        }
    }

    /// Lets foreground body reads take the IMAP command session before stale
    /// refreshes and draft discovery. Draft discovery resumes after the final
    /// concurrent foreground read rather than being dropped for this connection.
    private func beginForegroundIMAPRead() {
        cancelBackgroundRefreshTasks()
        let task = remoteDraftDiscoveryLock.withLock { () -> Task<Void, Never>? in
            foregroundIMAPReadCount += 1
            guard let remoteDraftDiscoveryTask else { return nil }
            self.remoteDraftDiscoveryTask = nil
            hasPendingRemoteDraftDiscoveryRetry = true
            return remoteDraftDiscoveryTask.task
        }
        task?.cancel()
    }

    private func endForegroundIMAPRead() {
        let shouldResume = remoteDraftDiscoveryLock.withLock { () -> Bool in
            foregroundIMAPReadCount = max(0, foregroundIMAPReadCount - 1)
            guard foregroundIMAPReadCount == 0, hasPendingRemoteDraftDiscoveryRetry else {
                return false
            }
            hasPendingRemoteDraftDiscoveryRetry = false
            return true
        }
        if shouldResume {
            scheduleRemoteDraftDiscovery()
        }
    }

    public func messages(
        in folder: Folder,
        sourceID: MailSourceID,
        pageToken: String?
    ) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        try validateSourceID(sourceID)
        return try await messages(in: folder, pageToken: pageToken)
    }

    public func body(for messageID: String) async throws -> MessageBody {
        try await messageBody(for: messageID, prioritizesForegroundIMAPRead: true)
    }

    private func messageBody(
        for messageID: String,
        prioritizesForegroundIMAPRead: Bool
    ) async throws -> MessageBody {
        let interval = MailPerformanceDiagnostics.beginInterval("IMAP Body Fetch")
        defer { MailPerformanceDiagnostics.endInterval(interval) }
        let reference = try Self.messageReference(from: messageID)
        if prioritizesForegroundIMAPRead {
            beginForegroundIMAPRead()
        }
        defer {
            if prioritizesForegroundIMAPRead {
                endForegroundIMAPRead()
            }
        }
        if let cached = await bodyCache?.body(accountID: account.id, messageID: messageID) {
            return cached
        }
        if let source = await cachedMessageSource(messageID: messageID) {
            let body = IMAPMessageBodyParser().parse(
                messageID: messageID,
                rawMessage: source.rawMessage
            )
            await bodyCache?.setBody(body, accountID: account.id, messageID: messageID)
            return body
        }

        if fetchMessageBodyOperation != nil {
            do {
                try await state.requireConnected()
                let body = try await fetchMessageBodyWithAuthenticatedOAuthRetry(
                    folderID: reference.folderID,
                    uid: reference.uid
                )
                await bodyCache?.setBody(body, accountID: account.id, messageID: messageID)
                return body
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // BODYSTRUCTURE is optional in practice: malformed or unusual
                // signed/encrypted MIME intentionally falls back to the proven
                // full-source parser so compatibility is never traded for speed.
                // The swallowed reason must still reach the log — transport and
                // auth failures land here too, and silently retrying them as a
                // full-source fetch hid every live body-load failure.
                Self.bodyFetchLogger.error(
                    "Structured body fetch failed; falling back to full source: \(String(describing: error), privacy: .private)"
                )
            }
        }

        let source = try await loadMessageSource(
            messageID: messageID,
            folderID: reference.folderID,
            uid: reference.uid
        )
        let body = IMAPMessageBodyParser().parse(
            messageID: messageID,
            rawMessage: source.rawMessage
        )
        await bodyCache?.setBody(body, accountID: account.id, messageID: messageID)
        return body
    }

    public func body(for messageID: String, sourceID: MailSourceID) async throws -> MessageBody {
        try validateSourceID(sourceID)
        return try await body(for: messageID)
    }

    public func rawSource(for messageID: String) async throws -> String {
        let source = try await loadMessageSource(messageID: messageID)
        return source.rawMessage
    }

    public func rawSource(for messageID: String, sourceID: MailSourceID) async throws -> String {
        try validateSourceID(sourceID)
        return try await rawSource(for: messageID)
    }

    /// Read-only enumeration of attachment-bearing messages already in the
    /// local cache (ADR-0044). Reads the injected header + source caches and
    /// parses with the pure `IMAPMessageBodyParser`. It never calls
    /// `requireConnected()` and never fetches or downloads: headers without a
    /// cached source, and messages without attachments, are simply skipped.
    public func cachedAttachmentMessages(in folders: [Folder]) async -> [CachedAttachmentMessage] {
        // Enumerate from the header cache, or fall back to the local search index
        // when no header cache is wired — either can supply the cached headers.
        guard headerCache != nil || localSearchIndex != nil else { return [] }
        let parser = IMAPMessageBodyParser()
        var results: [CachedAttachmentMessage] = []
        for folder in folders {
            let headers = await cachedHeadersForEnumeration(folder: folder)
            for header in headers {
                // Prefer the structured body cache: it is already parsed and
                // avoids reparsing the complete raw source for every
                // attachment-enumeration pass. Keep the source-cache fallback
                // for older stores/accounts that predate the body cache.
                let body: MessageBody?
                if let cachedBody = await bodyCache?.body(
                    accountID: account.id,
                    messageID: header.id
                ) {
                    body = cachedBody
                } else if let source = await cachedMessageSource(messageID: header.id) {
                    body = parser.parse(messageID: header.id, rawMessage: source.rawMessage)
                } else {
                    body = nil
                }
                guard let body else { continue }
                guard !body.attachments.isEmpty else { continue }
                results.append(CachedAttachmentMessage(folder: folder, header: header, body: body))
            }
        }
        return results
    }

    /// Cached headers for read-only enumeration, preferring the header cache and
    /// falling back to the local search index when the cache is absent.
    private func cachedHeadersForEnumeration(folder: Folder) async -> [MessageHeader] {
        if let snapshot = await headerCache?.snapshot(accountID: account.id, folderID: folder.id) {
            return snapshot.headers
        }
        return await allIndexedHeaders(folder: folder) ?? []
    }

    public func cachedAttachmentMessages(
        in folders: [Folder],
        sourceID: MailSourceID
    ) async -> [CachedAttachmentMessage] {
        guard (try? validateSourceID(sourceID)) != nil else { return [] }
        return await cachedAttachmentMessages(in: folders)
    }

    public func downloadAttachment(_ attachment: Attachment) async throws -> Data {
        if let resource = attachment.resource,
           resource.hasPrefix("imap-part:") {
            let part = try IMAPMessagePartReference(resource: resource)
            let messageReference = try Self.messageReference(from: part.messageID)
            guard fetchMessagePartOperation != nil else {
                throw MailBackendError.notFound(id: attachment.id)
            }
            try await state.requireConnected()
            return try await fetchMessagePartWithAuthenticatedOAuthRetry(
                folderID: messageReference.folderID,
                uid: messageReference.uid,
                section: part.section,
                transferEncoding: part.transferEncoding
            )
        }
        let reference = try Self.attachmentReference(from: attachment)
        let source = try await loadMessageSource(
            messageID: reference.messageID,
            folderID: reference.folderID,
            uid: reference.uid
        )
        guard let data = IMAPMessageBodyParser().attachmentData(
            attachmentIndex: reference.attachmentIndex,
            rawMessage: source.rawMessage
        ) else {
            throw MailBackendError.notFound(id: attachment.id)
        }
        return data
    }

    public func downloadAttachment(
        _ attachment: Attachment,
        sourceID: MailSourceID
    ) async throws -> Data {
        try validateSourceID(sourceID)
        return try await downloadAttachment(attachment)
    }

    public func setRead(_ isRead: Bool, for messageIDs: [String]) async throws {
        try await setRead(isRead, for: messageIDs, sourceID: nil)
    }

    public func setRead(
        _ isRead: Bool,
        for messageIDs: [String],
        sourceID: MailSourceID
    ) async throws {
        try validateSourceID(sourceID)
        try await setRead(isRead, for: messageIDs, sourceID: Optional(sourceID))
    }

    private func setRead(
        _ isRead: Bool,
        for messageIDs: [String],
        sourceID: MailSourceID?
    ) async throws {
        do {
            try await setSystemFlag(.seen, isEnabled: isRead, for: messageIDs)
        } catch {
            if try await enqueueOfflineMutation(
                PendingMutation(
                    kind: .setRead(isRead),
                    sourceID: sourceID,
                    messageIDs: messageIDs
                ),
                for: error
            ) {
                return
            }
            throw error
        }
    }

    public func setFlagged(_ isFlagged: Bool, for messageIDs: [String]) async throws {
        try await setFlagged(isFlagged, for: messageIDs, sourceID: nil)
    }

    public func setFlagged(
        _ isFlagged: Bool,
        for messageIDs: [String],
        sourceID: MailSourceID
    ) async throws {
        try validateSourceID(sourceID)
        try await setFlagged(isFlagged, for: messageIDs, sourceID: Optional(sourceID))
    }

    private func setFlagged(
        _ isFlagged: Bool,
        for messageIDs: [String],
        sourceID: MailSourceID?
    ) async throws {
        do {
            try await setSystemFlag(.flagged, isEnabled: isFlagged, for: messageIDs)
        } catch {
            if try await enqueueOfflineMutation(
                PendingMutation(
                    kind: .setFlagged(isFlagged),
                    sourceID: sourceID,
                    messageIDs: messageIDs
                ),
                for: error
            ) {
                return
            }
            throw error
        }
    }

    public func setJunk(_ isJunk: Bool, for messageIDs: [String]) async throws {
        try await setJunk(isJunk, for: messageIDs, sourceID: nil)
    }

    public func setJunk(
        _ isJunk: Bool,
        for messageIDs: [String],
        sourceID: MailSourceID
    ) async throws {
        try validateSourceID(sourceID)
        try await setJunk(isJunk, for: messageIDs, sourceID: Optional(sourceID))
    }

    private func setJunk(
        _ isJunk: Bool,
        for messageIDs: [String],
        sourceID: MailSourceID?
    ) async throws {
        do {
            try await performSetJunk(isJunk, for: messageIDs)
        } catch {
            if try await enqueueOfflineMutation(
                PendingMutation(
                    kind: .setJunk(isJunk),
                    sourceID: sourceID,
                    messageIDs: messageIDs
                ),
                for: error
            ) {
                return
            }
            throw error
        }
    }

    public func move(messageIDs: [String], to folder: Folder) async throws {
        try await move(messageIDs: messageIDs, to: folder, sourceID: nil)
    }

    public func move(
        messageIDs: [String],
        to folder: Folder,
        sourceID: MailSourceID
    ) async throws {
        try validateSourceID(sourceID)
        try await move(messageIDs: messageIDs, to: folder, sourceID: Optional(sourceID))
    }

    private func move(
        messageIDs: [String],
        to folder: Folder,
        sourceID: MailSourceID?
    ) async throws {
        do {
            try await performMove(messageIDs: messageIDs, toFolderID: folder.id)
        } catch {
            if try await enqueueOfflineMutation(
                PendingMutation(
                    kind: .move(folderID: folder.id),
                    sourceID: sourceID,
                    messageIDs: messageIDs
                ),
                for: error
            ) {
                return
            }
            throw error
        }
    }

    private func performMove(messageIDs: [String], toFolderID folderID: Folder.ID) async throws {
        try await state.requireConnected()
        guard !messageIDs.isEmpty else { return }
        guard let moveMessagesOperation else {
            throw MailBackendError.notSupported(capabilities)
        }

        for group in try Self.messageReferencesByFolder(from: messageIDs)
            where group.folderID != folderID {
            try await withAuthenticatedOAuthRetry { credential in
                try await moveMessagesOperation(
                    self.configuration,
                    credential,
                    group.folderID,
                    group.uids,
                    folderID
                )
            }
            await removeCachedMessageSources(folderID: group.folderID, uids: group.uids)
            await removeCachedHeaders(folderID: group.folderID, uids: group.uids)
            await state.emit(.messagesRemoved(
                folderID: group.folderID,
                messageIDs: Self.messageIDs(from: group)
            ))
            await state.emit(.folderRefreshed(folderID: folderID))
        }
    }

    public func copy(messageIDs: [String], to folder: Folder) async throws {
        try await copy(messageIDs: messageIDs, to: folder, sourceID: nil)
    }

    public func copy(
        messageIDs: [String],
        to folder: Folder,
        sourceID: MailSourceID
    ) async throws {
        try validateSourceID(sourceID)
        try await copy(messageIDs: messageIDs, to: folder, sourceID: Optional(sourceID))
    }

    private func copy(
        messageIDs: [String],
        to folder: Folder,
        sourceID: MailSourceID?
    ) async throws {
        do {
            try await performCopy(messageIDs: messageIDs, toFolderID: folder.id)
        } catch {
            if try await enqueueOfflineMutation(
                PendingMutation(
                    kind: .copy(folderID: folder.id),
                    sourceID: sourceID,
                    messageIDs: messageIDs
                ),
                for: error
            ) {
                return
            }
            throw error
        }
    }

    /// Copy leaves the originals in place, so — unlike `performMove` — it must
    /// not invalidate the source folder's caches or emit `.messagesRemoved`.
    /// It only refreshes the destination. See ADR-0045.
    private func performCopy(messageIDs: [String], toFolderID folderID: Folder.ID) async throws {
        try await state.requireConnected()
        guard !messageIDs.isEmpty else { return }
        guard let copyMessagesOperation else {
            throw MailBackendError.notSupported(capabilities)
        }

        var didCopy = false
        for group in try Self.messageReferencesByFolder(from: messageIDs)
            where group.folderID != folderID {
            try await withAuthenticatedOAuthRetry { credential in
                try await copyMessagesOperation(
                    self.configuration,
                    credential,
                    group.folderID,
                    group.uids,
                    folderID
                )
            }
            didCopy = true
        }
        // Refresh the destination once, even when the copy spanned several
        // source folders (the refresh is idempotent for that one folder).
        if didCopy {
            await state.emit(.folderRefreshed(folderID: folderID))
        }
    }

    public func delete(messageIDs: [String]) async throws {
        try await delete(messageIDs: messageIDs, sourceID: nil)
    }

    public func delete(messageIDs: [String], sourceID: MailSourceID) async throws {
        try validateSourceID(sourceID)
        try await delete(messageIDs: messageIDs, sourceID: Optional(sourceID))
    }

    private func delete(
        messageIDs: [String],
        sourceID: MailSourceID?
    ) async throws {
        do {
            try await performDelete(messageIDs: messageIDs)
        } catch {
            if try await enqueueOfflineMutation(
                PendingMutation(
                    kind: .delete,
                    sourceID: sourceID,
                    messageIDs: messageIDs
                ),
                for: error
            ) {
                return
            }
            throw error
        }
    }

    private func performDelete(messageIDs: [String]) async throws {
        let folders = try await state.requireConnectedFolders()
        guard !messageIDs.isEmpty else { return }

        let trashFolder = folders.first { $0.role == .trash }
        let groups = try Self.messageReferencesByFolder(from: messageIDs)

        for group in groups {
            if let trashFolder, group.folderID != trashFolder.id {
                guard let moveMessagesOperation else {
                    throw MailBackendError.notSupported(capabilities)
                }
                try await withAuthenticatedOAuthRetry { credential in
                    try await moveMessagesOperation(
                        self.configuration,
                        credential,
                        group.folderID,
                        group.uids,
                        trashFolder.id
                    )
                }
                await removeCachedMessageSources(folderID: group.folderID, uids: group.uids)
                await removeCachedHeaders(folderID: group.folderID, uids: group.uids)
                await state.emit(.messagesRemoved(
                    folderID: group.folderID,
                    messageIDs: Self.messageIDs(from: group)
                ))
                await state.emit(.folderRefreshed(folderID: trashFolder.id))
            } else {
                guard let permanentlyDeleteMessagesOperation else {
                    throw MailBackendError.notSupported(capabilities)
                }
                try await withAuthenticatedOAuthRetry { credential in
                    try await permanentlyDeleteMessagesOperation(
                        self.configuration,
                        credential,
                        group.folderID,
                        group.uids
                    )
                }
                await removeCachedMessageSources(folderID: group.folderID, uids: group.uids)
                await removeCachedHeaders(folderID: group.folderID, uids: group.uids)
                await state.emit(.messagesRemoved(
                    folderID: group.folderID,
                    messageIDs: Self.messageIDs(from: group)
                ))
                await state.emit(.folderRefreshed(folderID: group.folderID))
            }
        }
    }

    public func save(draft: Draft) async throws -> Draft {
        try await state.requireConnected()
        if let appendDraftMessageOperation,
           let draftsFolder = try await state.draftsFolder() {
            let attachments = try await stagedAttachments(for: draft.attachmentIDs)
            let from = Correspondent(
                name: configuration.displayName,
                email: configuration.emailAddress
            )
            let messageData = MIMEMessageBuilder(
                draft: draft,
                from: from,
                attachments: attachments
            ).build()
            let uid = try await withAuthenticatedOAuthRetry { credential in
                try await appendDraftMessageOperation(
                    self.configuration,
                    credential,
                    draftsFolder.id,
                    messageData,
                    [.draft]
                )
            }
            var saved = draft
            saved.remoteID = "\(draftsFolder.id):\(uid)"
            let staged = await state.stageDraft(saved)
            await draftStagingStore?.setDraft(staged, accountID: account.id)
            if draft.remoteID != staged.remoteID {
                _ = await deleteRemoteDraftIfPossible(draft.remoteID)
            }
            let fingerprint = DraftContentFingerprint.fingerprint(for: staged)
            await state.markDraftSynced(staged, fingerprint: fingerprint)
            return staged
        }
        let saved = await state.stageDraft(draft)
        await draftStagingStore?.setDraft(saved, accountID: account.id)
        await state.markDraftDirty(saved)
        return saved
    }

    public func save(draft: Draft, sourceID: MailSourceID) async throws -> Draft {
        try validateSourceID(sourceID)
        return try await save(draft: draft)
    }

    public func uploadAttachment(
        draftID: String,
        data: Data,
        filename: String,
        mimeType: String
    ) async throws -> String {
        try await state.requireConnected()
        let attachment = await state.stageAttachment(
            draftID: draftID,
            data: data,
            filename: filename,
            mimeType: mimeType
        )
        await draftStagingStore?.setAttachment(
            IMAPDraftStagedAttachment(
                id: attachment.id,
                draftID: attachment.draftID,
                filename: attachment.filename,
                mimeType: attachment.mimeType,
                data: attachment.data,
                isInline: attachment.isInline,
                contentID: attachment.contentID
            ),
            accountID: account.id
        )
        return attachment.id
    }

    public func uploadAttachment(
        draftID: String,
        data: Data,
        filename: String,
        mimeType: String,
        sourceID: MailSourceID
    ) async throws -> String {
        try validateSourceID(sourceID)
        return try await uploadAttachment(
            draftID: draftID,
            data: data,
            filename: filename,
            mimeType: mimeType
        )
    }

    public func stageInlineAttachment(
        draftID: String,
        contentID: String,
        filename: String,
        mimeType: String,
        data: Data
    ) async throws -> String {
        try await state.requireConnected()
        let attachment = await state.stageAttachment(
            draftID: draftID,
            data: data,
            filename: filename,
            mimeType: mimeType,
            isInline: true,
            contentID: contentID
        )
        await draftStagingStore?.setAttachment(
            IMAPDraftStagedAttachment(
                id: attachment.id,
                draftID: attachment.draftID,
                filename: attachment.filename,
                mimeType: attachment.mimeType,
                data: attachment.data,
                isInline: attachment.isInline,
                contentID: attachment.contentID
            ),
            accountID: account.id
        )
        return attachment.id
    }

    public func stageInlineAttachment(
        draftID: String,
        contentID: String,
        filename: String,
        mimeType: String,
        data: Data,
        sourceID: MailSourceID
    ) async throws -> String {
        try validateSourceID(sourceID)
        return try await stageInlineAttachment(
            draftID: draftID,
            contentID: contentID,
            filename: filename,
            mimeType: mimeType,
            data: data
        )
    }

    public func discard(draftID: String) async throws {
        try await state.requireConnected()
        try await deleteRemoteDraft(draftID)
        await state.discardDraft(draftID: draftID)
        await draftStagingStore?.removeDraft(accountID: account.id, draftID: draftID)
    }

    public func discard(draftID: String, sourceID: MailSourceID) async throws {
        try validateSourceID(sourceID)
        try await discard(draftID: draftID)
    }

    public func send(draft: Draft) async throws -> SendResult {
        do {
            guard !Self.recipientEmails(from: draft).isEmpty else {
                throw DraftValidationError.missingRecipients
            }
            if draft.scheduledFor != nil {
                return try await scheduleSend(draft: draft)
            }
            return try await performImmediateSend(draft: draft)
        } catch {
            // Keep the full draft in the existing local staging store. The
            // offline mutation queue stores only its stable ID, never message
            // content or recipients in UserDefaults.
            await draftStagingStore?.setDraft(draft, accountID: account.id)
            if try await enqueueOfflineMutation(
                PendingMutation(kind: .send(draft: draft), messageIDs: []),
                for: error
            ) {
                return SendResult(
                    sentMessageID: nil,
                    scheduledFor: draft.scheduledFor,
                    warnings: [.queuedForRetry]
                )
            }
            throw error
        }
    }

    public func send(draft: Draft, sourceID: MailSourceID) async throws -> SendResult {
        try validateSourceID(sourceID)
        return try await send(draft: draft)
    }

    private func performImmediateSend(draft: Draft) async throws -> SendResult {
        // De-duplicate at-least-once delivery: if this draft's SMTP send was
        // already confirmed on a prior attempt (the queue/schedule entry just
        // wasn't cleared due to a crash/race), don't deliver a second copy — only
        // finish the local cleanup. This only skips a *confirmed*-sent draft, so
        // it can never drop a real send.
        if let sentMessageLedger, sentMessageLedger.contains(draftID: draft.id, accountID: account.id) {
            await state.clearDraftAndAttachments(for: draft)
            await removePersistedDraft(draft)
            return SendResult(sentMessageID: nil, scheduledFor: nil)
        }

        try await state.requireConnected()
        guard let sendMessageOperation else {
            throw MailBackendError.notSupported(capabilities)
        }
        let attachments = try await stagedAttachments(for: draft.attachmentIDs)
        let recipientEmails = Self.recipientEmails(from: draft)
        guard !recipientEmails.isEmpty else {
            throw DraftValidationError.missingRecipients
        }
        let from = Correspondent(
            name: configuration.displayName,
            email: configuration.emailAddress
        )
        let messageData = MIMEMessageBuilder(
            draft: draft,
            from: from,
            attachments: attachments
        ).build()
        // Apply outbound signing/encryption once (ADR-0021). The prepared bytes
        // are reused for both the SMTP DATA and the Sent-copy APPEND below, so
        // the delivered message and the saved copy can never disagree
        // (decision #7). Fails closed when no engine is wired (decision #4).
        let outgoingData = try await preparedOutboundData(
            messageData,
            draft: draft,
            recipientEmails: recipientEmails
        )
        let submission = SMTPMessageSubmission(
            messageData: outgoingData,
            senderEmail: configuration.emailAddress,
            recipientEmails: recipientEmails
        )
        let result: SendResult
        do {
            result = try await sendMessageOperation(configuration, credential, submission)
        } catch {
            guard credential.authentication == .xoauth2,
                  Self.isAuthenticationFailure(error),
                  let refreshOAuthCredentialOperation
            else {
                throw error
            }
            let refreshedCredential = try await refreshOAuthCredentialOperation(
                account.id,
                configuration,
                credential
            )
            replaceCredentialForReconnect(refreshedCredential)
            result = try await sendMessageOperation(
                configuration,
                refreshedCredential,
                submission
            )
        }
        // The server accepted the message; record it so a later replay of the
        // same draft (e.g. the entry wasn't cleared before a crash) is skipped.
        sentMessageLedger?.record(draftID: draft.id, accountID: account.id)
        let (sentCopyUID, sentCopyWarning) = await appendSentCopyIfPossible(outgoingData)
        let draftCleanupWarning = await deleteRemoteDraftIfPossible(draft.remoteID)
        await state.clearDraftAndAttachments(for: draft)
        await removePersistedDraft(draft)
        let sentMessageID = sentCopyUID.map { "\($0)" } ?? result.sentMessageID
        return SendResult(
            sentMessageID: sentMessageID,
            scheduledFor: result.scheduledFor,
            warnings: result.warnings + [sentCopyWarning, draftCleanupWarning].compactMap { $0 }
        )
    }

    /// Returns the MIME bytes to submit: the plaintext `messageData` unchanged
    /// for `.none`, or the signed/encrypted form from the injected preparer.
    /// Throws `OutboundCryptoEngineUnavailableError` if security is requested
    /// but no engine is wired — never a silent plaintext fallback (ADR-0021 #4).
    private func preparedOutboundData(
        _ messageData: Data,
        draft: Draft,
        recipientEmails: [String]
    ) async throws -> Data {
        guard draft.securityMode != .none else { return messageData }
        guard let outboundMessagePreparer else {
            throw OutboundCryptoEngineUnavailableError(mode: draft.securityMode)
        }
        let request = OutboundMessageSecurityRequest(
            senderEmail: configuration.emailAddress,
            to: draft.to.map(\.email),
            cc: draft.cc.map(\.email),
            bcc: draft.bcc.map(\.email),
            mode: draft.securityMode
        )
        return try await outboundMessagePreparer.prepare(mimeData: messageData, request: request)
    }

    private func scheduleSend(draft: Draft) async throws -> SendResult {
        try await state.requireConnected()
        guard let scheduledFor = draft.scheduledFor else {
            throw MailBackendError.backendSpecific(message: "Cannot schedule a draft without a scheduledFor date.")
        }

        // Persist the draft and register the schedule entry.
        await draftStagingStore?.setDraft(draft, accountID: account.id)
        scheduledSendStore.add(entry: ScheduledDraftEntry(draftID: draft.id, scheduledFor: scheduledFor), accountID: account.id)

        return SendResult(sentMessageID: nil, scheduledFor: scheduledFor)
    }

    private func deliverDueScheduledDrafts(forceRetry: Bool = false) async {
        // In-flight guard: only one delivery pass runs at a time, so overlapping
        // triggers (connect, poller, refresh) can't claim and send the same draft.
        let acquired = scheduledDeliveryLock.withLock { () -> Bool in
            guard !scheduledDeliveryInFlight else { return false }
            scheduledDeliveryInFlight = true
            return true
        }
        guard acquired else { return }
        defer { scheduledDeliveryLock.withLock { scheduledDeliveryInFlight = false } }

        let due = scheduledSendStore.claimDueEntries(
            accountID: account.id,
            before: Date(),
            lease: Self.scheduledSendClaimLease,
            force: forceRetry
        )

        for entry in due {
            // Refresh from the stored draft — the polled entry is a snapshot.
            // A missing draft or a draft no longer scheduled can never succeed,
            // so prune the orphaned entry instead of re-reading it forever.
            guard let draft = await draftStagingStore?.draft(accountID: account.id, draftID: entry.draftID),
                  draft.scheduledFor != nil else {
                scheduledSendStore.remove(draftID: entry.draftID, accountID: account.id)
                continue
            }

            do {
                _ = try await performImmediateSend(draft: draft)
                scheduledSendStore.remove(draftID: draft.id, accountID: account.id)
            } catch {
                if case SMTPClientError.deliveryOutcomeUnknown = error {
                    // DATA may already have been accepted. Remove the
                    // scheduled trigger so the poller/reconnect path cannot
                    // duplicate the message, but keep the staged draft and
                    // surface a recoverable conflict for an explicit choice.
                    scheduledSendStore.remove(draftID: draft.id, accountID: account.id)
                    let mutation = PendingMutation(
                        kind: .sendStagedDraft(stagedDraftID: draft.id),
                        messageIDs: []
                    )
                    let conflict = MutationConflict(
                        mutation: mutation,
                        reason: .retriesExhausted,
                        message: error.localizedDescription
                    )
                    if let offlineMutationConflictStore {
                        let alreadySurfaced = await (try? offlineMutationConflictStore.conflicts())?.contains {
                            guard case .sendStagedDraft(let stagedDraftID) = $0.mutation.kind else {
                                return false
                            }
                            return stagedDraftID == draft.id
                        } == true
                        if !alreadySurfaced {
                            try? await offlineMutationConflictStore.append([conflict])
                        }
                    }
                    continue
                }
                // Keep the entry but push the next retry out with backoff so a
                // permanently-failing send doesn't re-attempt on every tick.
                scheduledSendStore.recordSendFailure(
                    draftID: entry.draftID,
                    accountID: account.id,
                    now: Date(),
                    baseInterval: Self.scheduledSendBackoffBase,
                    maxInterval: Self.scheduledSendBackoffMax
                )
            }
        }
    }

    // MARK: ScheduledSendManaging

    public func pendingScheduledSends() -> [PendingScheduledSend] {
        scheduledSendStore.entries(accountID: account.id).map {
            PendingScheduledSend(draftID: $0.draftID, scheduledFor: $0.scheduledFor)
        }
    }

    public func deliverDueScheduledSends() async {
        // Forced: an explicit request (background refresh, pre-quit flush) should
        // not be throttled by the in-session backoff or a stale claim lease.
        await deliverDueScheduledDrafts(forceRetry: true)
    }

    private func startScheduledSendPoller() {
        let newTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.scheduledSendPollInterval)
                guard !Task.isCancelled, let self else { return }
                await deliverDueScheduledDrafts()
            }
        }
        let previous: Task<Void, Never>? = scheduledSendTaskLock.withLock {
            let old = scheduledSendTask
            scheduledSendTask = newTask
            return old
        }
        previous?.cancel()
    }

    private func stopScheduledSendPoller() {
        let previous: Task<Void, Never>? = scheduledSendTaskLock.withLock {
            let old = scheduledSendTask
            scheduledSendTask = nil
            return old
        }
        previous?.cancel()
    }

    private func validateSourceID(_ sourceID: MailSourceID) throws {
        guard sourceID.accountID == account.id else {
            throw MailBackendError.notFound(id: sourceID.accountID)
        }
        guard sourceID.mailboxID == account.id else {
            throw MailBackendError.notFound(id: sourceID.mailboxID)
        }
    }

    public func search(_ query: SearchQuery) async throws -> [MessageHeader] {
        let interval = MailPerformanceDiagnostics.beginInterval("IMAP Search")
        defer { MailPerformanceDiagnostics.endInterval(interval) }
        func durationMilliseconds() -> Int {
            MailPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
        }

        let folders: [Folder]
        do {
            folders = try await state.requireConnectedFolders()
        } catch {
            if query.execution != .serverOnly {
                let cachedFolders = await folderCache?.snapshot(accountID: account.id)?.folders ?? []
                let cachedResults = await cachedSearchResults(for: query, folders: cachedFolders)
                if query.execution == .cacheOnly || !cachedResults.isEmpty {
                    MailPerformanceDiagnostics.logSearchFinished(
                        snapshot: MailPerformanceDiagnostics.searchSnapshot(
                            for: query,
                            searchedFolderCount: query.folderID == nil ? cachedFolders.count : 1
                        ),
                        path: query.execution == .cacheOnly ? .cacheOnly : .cacheFallback,
                        resultCount: cachedResults.count,
                        durationMilliseconds: durationMilliseconds()
                    )
                    return cachedResults
                }
            }
            MailPerformanceDiagnostics.logSearchFailed(
                snapshot: MailPerformanceDiagnostics.searchSnapshot(for: query, searchedFolderCount: 0),
                error: error,
                durationMilliseconds: durationMilliseconds()
            )
            throw error
        }
        let searchedFolderCount = query.folderID == nil ? folders.count : 1
        let snapshot = MailPerformanceDiagnostics.searchSnapshot(
            for: query,
            searchedFolderCount: searchedFolderCount
        )
        let cachedResults = query.execution == .serverOnly
            ? []
            : await cachedSearchResults(for: query, folders: folders)
        if query.execution == .cacheOnly {
            MailPerformanceDiagnostics.logSearchFinished(
                snapshot: snapshot,
                path: .cacheOnly,
                resultCount: cachedResults.count,
                durationMilliseconds: durationMilliseconds()
            )
            return cachedResults
        }
        // Cache-first for ordinary queries; attachment predicates must continue to
        // the paginated server path so cached hits do not hide older matches.
        if query.execution == .cacheThenServer,
           query.hasAttachments == nil,
           !cachedResults.isEmpty {
            MailPerformanceDiagnostics.logSearchFinished(
                snapshot: snapshot,
                path: .cacheThenServerHit,
                resultCount: cachedResults.count,
                durationMilliseconds: durationMilliseconds()
            )
            return cachedResults
        }
        guard searchMessagesOperation != nil || searchMessagePageOperation != nil else {
            if query.execution == .cacheThenServer, !cachedResults.isEmpty {
                MailPerformanceDiagnostics.logSearchFinished(
                    snapshot: snapshot,
                    path: .cacheFallback,
                    resultCount: cachedResults.count,
                    durationMilliseconds: durationMilliseconds()
                )
                return cachedResults
            }
            let error = MailBackendError.notSupported(capabilities)
            MailPerformanceDiagnostics.logSearchFailed(
                snapshot: snapshot,
                error: error,
                durationMilliseconds: durationMilliseconds()
            )
            throw error
        }
        if query.hasAttachments != nil, fetchMessageSourceOperation == nil {
            let error = MailBackendError.notSupported(capabilities)
            MailPerformanceDiagnostics.logSearchFailed(
                snapshot: snapshot,
                error: error,
                durationMilliseconds: durationMilliseconds()
            )
            throw error
        }
        let folderIDs: [Folder.ID]
        if let folderID = query.folderID {
            folderIDs = [folderID]
        } else {
            folderIDs = folders.map(\.id)
        }
        guard !folderIDs.isEmpty else {
            MailPerformanceDiagnostics.logSearchFinished(
                snapshot: snapshot,
                path: .server,
                resultCount: 0,
                durationMilliseconds: durationMilliseconds()
            )
            return []
        }

        do {
            var headers: [MessageHeader] = []
            for folderID in folderIDs {
                try Task.checkCancellation()
                if query.hasAttachments != nil,
                   let searchMessagePageOperation {
                    try await headers.append(contentsOf: searchAttachmentHeaders(
                        folderID: folderID,
                        query: query,
                        operation: searchMessagePageOperation
                    ))
                } else {
                    let listings = try await searchMessagesWithAuthenticatedOAuthRetry(
                        folderID: folderID,
                        query: Self.serverSearchQuery(from: query),
                        limit: Self.serverSearchCandidateLimit(for: query)
                    )
                    try await headers.append(contentsOf: searchHeaders(
                        from: listings,
                        folderID: folderID,
                        attachmentFilter: query.hasAttachments
                    ))
                }
            }

            let results = Self.sortedSearchResults(headers)
            MailPerformanceDiagnostics.logSearchFinished(
                snapshot: snapshot,
                path: .server,
                resultCount: results.count,
                durationMilliseconds: durationMilliseconds()
            )
            return results
        } catch {
            if query.execution == .cacheThenServer,
               !cachedResults.isEmpty,
               Self.shouldUseCacheFallback(for: error) {
                MailPerformanceDiagnostics.logSearchFinished(
                    snapshot: snapshot,
                    path: .cacheFallback,
                    resultCount: cachedResults.count,
                    durationMilliseconds: durationMilliseconds()
                )
                return cachedResults
            }
            MailPerformanceDiagnostics.logSearchFailed(
                snapshot: snapshot,
                error: error,
                durationMilliseconds: durationMilliseconds()
            )
            throw error
        }
    }

    public func search(_ query: SearchQuery, sourceID: MailSourceID) async throws -> [MessageHeader] {
        try validateSourceID(sourceID)
        return try await search(query)
    }

    public func replayPendingMutations(processSends: Bool = true) async throws -> MutationProcessingResult {
        guard let offlineMutationQueue else { return MutationProcessingResult() }
        // Serialize replay: overlapping triggers (reconnect, network-online,
        // restore) would otherwise each process the same pending snapshot and
        // double-apply mutations — including re-sending a queued message.
        guard await state.beginReplayIfIdle() else { return MutationProcessingResult() }
        do {
            try await migrateLegacyQueuedDrafts(in: offlineMutationQueue)
            let processor = OfflineMutationProcessor(queue: offlineMutationQueue, applier: self)
            let result = try await processor.process(processSends: processSends)
            try await offlineMutationConflictStore?.append(result.conflicts)
            await state.recordMutationProcessingResult(result)
            await state.endReplay()
            return result
        } catch {
            await state.endReplay()
            throw error
        }
    }

    private func migrateLegacyQueuedDrafts(in queue: any OfflineMutationQueue) async throws {
        guard draftStagingStore != nil else { return }
        for mutation in try await queue.pending() {
            guard case .send(draft: let draft) = mutation.kind else { continue }
            await draftStagingStore?.setDraft(draft, accountID: account.id)
            try await queue.update(PendingMutation(
                id: mutation.id,
                kind: .sendStagedDraft(stagedDraftID: draft.id),
                sourceID: mutation.sourceID,
                messageIDs: mutation.messageIDs,
                createdAt: mutation.createdAt,
                attempt: mutation.attempt
            ))
        }
    }

    public func syncHealth(for sourceID: MailSourceID) async -> AccountSyncHealth {
        let snapshot = await state.syncHealthSnapshot()
        let pendingStatus = await pendingMutationCount()
        let conflictStatus = await mutationConflictStatus()
        let indexMetrics = await localSearchIndex?.metrics(for: account)
        let cacheSizeBytes = cachedMessageCacheSizeBytesForSyncHealth()
            + Int(indexMetrics?.databaseBytes ?? 0)
        let sourceError: String?
        do {
            try validateSourceID(sourceID)
            sourceError = nil
        } catch MailBackendError.notFound(let id) {
            sourceError = "Sync health was requested for an unknown IMAP mailbox source (\(id))."
        } catch {
            sourceError = error.localizedDescription
        }
        let sanitizedSourceError = Self.sanitizedSyncErrorDescription(sourceError)
        let sanitizedPendingError = Self.sanitizedSyncErrorDescription(pendingStatus.errorDescription)
        let sanitizedConflictError = Self.sanitizedSyncErrorDescription(conflictStatus.errorDescription)
        let sanitizedReplayError = Self.sanitizedSyncErrorDescription(snapshot.lastReplayConflictDescription)
        let sanitizedBackgroundError = Self.sanitizedSyncErrorDescription(snapshot.lastErrorDescription)
        let lastErrorDescription = sanitizedSourceError
            ?? sanitizedPendingError
            ?? sanitizedConflictError
            ?? sanitizedReplayError
            ?? sanitizedBackgroundError
        let replayConflictCount = conflictStatus.count > 0
            ? conflictStatus.count
            : snapshot.lastReplayConflictCount
        let healthState: SyncHealthState
        if sanitizedSourceError != nil || sanitizedPendingError != nil {
            healthState = .providerError
        } else if sanitizedConflictError != nil {
            healthState = .degraded
        } else if sanitizedReplayError != nil {
            healthState = .degraded
        } else if case .rebuilding = snapshot.indexStatus {
            healthState = .indexing
        } else if snapshot.isConnected {
            healthState = pendingStatus.count > 0 || lastErrorDescription != nil ? .degraded : .healthy
        } else {
            healthState = .offline
        }

        return AccountSyncHealth(
            sourceID: sourceID,
            state: healthState,
            lastSuccessfulSyncAt: snapshot.lastSuccessfulSyncAt,
            lastErrorDescription: lastErrorDescription,
            indexStatus: snapshot.indexStatus,
            cacheSizeBytes: cacheSizeBytes,
            localSearchIndexMetrics: indexMetrics,
            pendingMutationCount: pendingStatus.count,
            replayConflictCount: replayConflictCount,
            backgroundRefreshSnapshot: snapshot.lastBackgroundRefreshSnapshot,
            searchIndexProgress: snapshot.searchIndexProgress
        )
    }

    public func syncConflicts(for sourceID: MailSourceID) async throws -> [MutationConflict] {
        try validateSourceID(sourceID)
        return try await offlineMutationConflictStore?.conflicts() ?? []
    }

    // MARK: OutboxManaging

    public func pendingMutations() async -> [PendingMutation] {
        await (try? offlineMutationQueue?.pending()) ?? []
    }

    public func discardMutation(id: UUID) async {
        try? await offlineMutationQueue?.remove(id: id)
    }

    public func discardAllMutations() async {
        try? await offlineMutationQueue?.removeAll()
    }

    // MARK: CardDAVContactSyncSupporting

    public var emailAddressForCardDAV: String {
        account.emailAddress
    }

    public var bearerTokenForCardDAV: String? {
        credential.authentication == .xoauth2 ? credential.secret : nil
    }

    public func retrySync(for sourceID: MailSourceID) async throws {
        try validateSourceID(sourceID)
        try await connect()
        _ = try await replayPendingMutations()
        _ = try await refreshConnectedMailboxFirstPages(limit: nil)
    }

    public func refreshMailbox(for sourceID: MailSourceID) async throws {
        try validateSourceID(sourceID)
        try await connect()
        let summary = try await refreshConnectedMailboxFirstPages(
            limit: Self.maximumBackgroundRefreshFolderCount
        )
        await state.recordBackgroundRefreshSummary(summary)
    }

    private func refreshConnectedMailboxFirstPages(limit: Int?) async throws -> BackgroundRefreshSnapshot? {
        guard listMessagesOperation != nil else { return nil }
        let folders = try await state.requireConnectedFolders()
        let refreshFolders = Self.prioritizedBackgroundRefreshFolders(folders, limit: limit)
        let total = refreshFolders.count
        // Surface a determinate download indicator while the refresh runs.
        // Emit progress in both the success and failure branches so a
        // per-folder error can never strand the bar short of `total`.
        if total > 1 {
            await state.emit(.syncProgress(completed: 0, total: total))
        }
        for (index, folder) in refreshFolders.enumerated() {
            do {
                try await refreshConnectedFolderFirstPage(folder)
                await state.emit(.folderRefreshed(folderID: folder.id))
            } catch {
                await state.emit(.folderRefreshed(folderID: folder.id))
            }
            if total > 1 {
                await state.emit(.syncProgress(completed: index + 1, total: total))
            }
        }
        guard limit != nil else { return nil }
        return BackgroundRefreshSnapshot(
            refreshedFolderCount: refreshFolders.count,
            deferredFolderCount: max(0, folders.count - refreshFolders.count),
            refreshedAt: Date()
        )
    }

    private struct SearchIndexRebuildSummary: Sendable {
        var indexedMessageCount = 0
        var cachedBodyMessageIDs: [MessageHeader.ID] = []
        var bodyBackfillFailureCount = 0
        var validationHeader: MessageHeader?
    }

    private struct SearchIndexBodyBackfillSummary: Sendable {
        var cachedBodyMessageIDs: [MessageHeader.ID] = []
        var failureCount = 0
    }

    private func rebuildConnectedSearchIndex() async throws -> SearchIndexRebuildSummary {
        guard listMessagesOperation != nil else {
            throw MailBackendError.notSupported(capabilities)
        }
        let folders = try await state.requireConnectedFolders()
        let total = folders.count
        if total > 1 {
            await state.emit(.syncProgress(completed: 0, total: total))
        }
        await state.recordIndexingProgress(
            0,
            snapshot: SearchIndexProgressSnapshot(
                completedFolderCount: 0,
                totalFolderCount: total,
                indexedMessageCount: 0
            )
        )

        var summary = SearchIndexRebuildSummary()
        var indexedMessageIDs = Set<MessageHeader.ID>()
        for (index, folder) in folders.enumerated() {
            var pageToken: String?
            var visitedPageTokens = Set<String>()
            while true {
                if let pageToken,
                   !visitedPageTokens.insert(pageToken).inserted {
                    throw MailBackendError.backendSpecific(
                        message: "IMAP index rebuild did not advance the page cursor."
                    )
                }

                let page = try await listMessagesWithAuthenticatedOAuthRetry(
                    folderID: folder.id,
                    pageToken: pageToken,
                    limit: 50
                )
                await recordGmailLabelSupport(from: page)
                let headers = page.messages.map { Self.header(from: $0, folderID: folder.id) }
                if pageToken == nil {
                    await reconcileUIDValidity(page.uidValidity, folderID: folder.id)
                    let headerChangeEvents = await reconcileFirstPageHeaderChanges(
                        headers,
                        folderID: folder.id,
                        removesMissingHeaders: page.nextPageToken == nil
                    )
                    await cacheHeaders(
                        headers,
                        folderID: folder.id,
                        uidValidity: page.uidValidity,
                        highestModSeq: page.highestModSeq,
                        nextPageToken: page.nextPageToken
                    )
                    await emit(headerChangeEvents)
                } else {
                    var headerChangeEvents: [MailEvent] = []
                    if let updateEvent = await cachedHeaderUpdateEvent(
                        headers,
                        folderID: folder.id
                    ) {
                        headerChangeEvents.append(updateEvent)
                    }
                    if let removalEvent = await reconcileCachedPageRemovals(
                        headers,
                        folderID: folder.id,
                        pageToken: pageToken
                    ) {
                        headerChangeEvents.append(removalEvent)
                    }
                    await cacheHeaders(
                        headers,
                        folderID: folder.id,
                        nextPageToken: page.nextPageToken,
                        mergingWithExisting: true,
                        loadedPageToken: pageToken
                    )
                    await emit(headerChangeEvents)
                }
                await state.recordListedMessageIDs(
                    headers.map(\.id),
                    folderID: folder.id,
                    isCompleteFolderWindow: page.nextPageToken == nil
                )
                var newlyIndexedHeaders: [MessageHeader] = []
                for header in headers {
                    if indexedMessageIDs.insert(header.id).inserted {
                        summary.indexedMessageCount += 1
                        newlyIndexedHeaders.append(header)
                        if summary.validationHeader == nil,
                           Self.searchIndexValidationQuery(for: header) != nil {
                            summary.validationHeader = header
                        }
                    }
                }
                let backfillSummary = try await backfillMessageSources(newlyIndexedHeaders)
                summary.cachedBodyMessageIDs.append(contentsOf: backfillSummary.cachedBodyMessageIDs)
                summary.bodyBackfillFailureCount += backfillSummary.failureCount
                if total > 0 {
                    await state.recordIndexingProgress(
                        Double(index) / Double(total),
                        snapshot: SearchIndexProgressSnapshot(
                            completedFolderCount: index,
                            totalFolderCount: total,
                            indexedMessageCount: summary.indexedMessageCount,
                            bodyBackfillFailureCount: summary.bodyBackfillFailureCount
                        )
                    )
                }

                guard let nextPageToken = page.nextPageToken else { break }
                pageToken = nextPageToken
            }

            await state.emit(.folderRefreshed(folderID: folder.id))
            if total > 1 {
                await state.emit(.syncProgress(completed: index + 1, total: total))
            }
            if total > 0 {
                let progress = Double(index + 1) / Double(total)
                await state.recordIndexingProgress(
                    progress,
                    snapshot: SearchIndexProgressSnapshot(
                        completedFolderCount: index + 1,
                        totalFolderCount: total,
                        indexedMessageCount: summary.indexedMessageCount,
                        bodyBackfillFailureCount: summary.bodyBackfillFailureCount
                    )
                )
            }
        }
        return summary
    }

    private func backfillMessageSources(_ headers: [MessageHeader]) async throws -> SearchIndexBodyBackfillSummary {
        guard sourceCache != nil || localSearchIndex != nil,
              fetchMessageSourceOperation != nil
        else { return SearchIndexBodyBackfillSummary() }
        var summary = SearchIndexBodyBackfillSummary()
        for header in headers {
            do {
                _ = try await loadMessageSource(messageID: header.id)
                summary.cachedBodyMessageIDs.append(header.id)
            } catch {
                if error is CancellationError { throw error }
                summary.failureCount += 1
            }
        }
        return summary
    }

    private static func prioritizedBackgroundRefreshFolders(
        _ folders: [Folder],
        limit: Int?
    ) -> [Folder] {
        let orderedFolders = folders.enumerated().sorted { first, second in
            let firstPriority = backgroundRefreshPriority(for: first.element.role)
            let secondPriority = backgroundRefreshPriority(for: second.element.role)
            if firstPriority != secondPriority {
                return firstPriority < secondPriority
            }
            return first.offset < second.offset
        }.map(\.element)
        guard let limit else { return orderedFolders }
        return Array(orderedFolders.prefix(limit))
    }

    private static func backgroundRefreshPriority(for role: FolderRole) -> Int {
        switch role {
        case .inbox: return 0
        case .custom: return 1
        case .archive: return 2
        case .starred: return 3
        case .sent: return 4
        case .drafts: return 5
        case .allMail: return 6
        case .spam: return 7
        case .trash: return 8
        case .scheduled: return 9
        case .snoozed: return 10
        }
    }

    public func rebuildSearchIndex(for sourceID: MailSourceID) async throws {
        try validateSourceID(sourceID)
        guard listMessagesOperation != nil else {
            throw MailBackendError.notSupported(capabilities)
        }
        guard localSearchIndex != nil else {
            let message = "Local search index storage is unavailable."
            await state.recordIndexingFailed(message)
            throw MailBackendError.backendSpecific(message: message)
        }
        guard await state.beginIndexingIfIdle() else {
            throw MailBackendError.backendSpecific(message: "Mail download is already running.")
        }
        do {
            try await connect()
            let summary = try await rebuildConnectedSearchIndex()
            try await validateSearchIndexRebuild(summary)
            if summary.bodyBackfillFailureCount > 0 {
                await state.recordIndexingCompletedWithBodyFailures(
                    messageCount: summary.indexedMessageCount,
                    failureCount: summary.bodyBackfillFailureCount
                )
            } else {
                await state.recordIndexingCompleted(messageCount: summary.indexedMessageCount)
            }
        } catch {
            await state.recordIndexingFailed(Self.userFacingDescription(for: error))
            throw error
        }
    }

    private func validateSearchIndexRebuild(_ summary: SearchIndexRebuildSummary) async throws {
        guard summary.indexedMessageCount > 0,
              let metrics = await localSearchIndex?.metrics(for: account)
        else { return }
        guard metrics.indexedHeaderCount >= summary.indexedMessageCount,
              metrics.searchDocumentCount >= summary.indexedMessageCount
        else {
            throw MailBackendError.backendSpecific(
                message: "Local search index rebuild did not persist all indexed messages."
            )
        }
        guard metrics.cachedBodyCount >= summary.cachedBodyMessageIDs.count else {
            throw MailBackendError.backendSpecific(
                message: "Local search index rebuild did not persist all cached message bodies."
            )
        }
        for messageID in summary.cachedBodyMessageIDs {
            guard await localSearchIndex?.cachedRawMessage(
                for: messageID,
                account: account
            ) != nil else {
                throw MailBackendError.backendSpecific(
                    message: "Local search index rebuild did not persist all cached message bodies."
                )
            }
        }
        guard let validationHeader = summary.validationHeader,
              let validationQuery = Self.searchIndexValidationQuery(for: validationHeader)
        else { return }
        let results = await localSearchIndex?.search(
            validationQuery,
            account: account,
            limit: Self.defaultServerSearchCandidateLimit
        ) ?? []
        guard results.contains(where: { $0.id == validationHeader.id }) else {
            throw MailBackendError.backendSpecific(
                message: "Local search index rebuild did not make indexed messages searchable."
            )
        }
    }

    private static func searchIndexValidationQuery(for header: MessageHeader) -> SearchQuery? {
        let subject = header.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subject.isEmpty {
            return SearchQuery(
                folderID: header.folderID,
                dateRange: header.date ... header.date,
                subject: subject,
                execution: .cacheOnly
            )
        }

        let senderEmail = header.from.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !senderEmail.isEmpty {
            return SearchQuery(
                folderID: header.folderID,
                from: senderEmail,
                dateRange: header.date ... header.date,
                execution: .cacheOnly
            )
        }

        let recipientEmail = header.to
            .lazy
            .map { $0.email.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        if let recipientEmail {
            return SearchQuery(
                folderID: header.folderID,
                to: recipientEmail,
                dateRange: header.date ... header.date,
                execution: .cacheOnly
            )
        }

        return nil
    }

    public func resetLocalCacheAndIndex(for sourceID: MailSourceID) async throws {
        try validateSourceID(sourceID)
        guard await state.beginLocalResetIfIdle() else {
            throw MailBackendError.backendSpecific(message: "Mail download is already running.")
        }
        await clearLocalCaches()
        await draftStagingStore?.clear(accountID: account.id)
        try? await offlineMutationQueue?.removeAll()
        try? await offlineMutationConflictStore?.removeAll()
        await state.clearReplayConflictDescription()
        await state.resetIndexStatus()
        await state.endLocalReset()
    }

    public func clearSyncConflicts(for sourceID: MailSourceID) async throws {
        try validateSourceID(sourceID)
        try await offlineMutationConflictStore?.removeAll()
        await state.clearReplayConflictDescription()
    }

    public func retryConflict(id: UUID, sourceID: MailSourceID) async throws {
        try validateSourceID(sourceID)
        guard let store = offlineMutationConflictStore,
              let queue = offlineMutationQueue
        else { return }
        let conflicts = try await store.conflicts()
        guard let conflict = conflicts.first(where: { $0.id == id }) else { return }

        try await store.remove(id: id)

        var retryMutation = conflict.mutation
        if case .send(draft: let draft) = retryMutation.kind {
            await draftStagingStore?.setDraft(draft, accountID: account.id)
            retryMutation = PendingMutation(
                id: retryMutation.id,
                kind: .sendStagedDraft(stagedDraftID: draft.id),
                sourceID: retryMutation.sourceID,
                messageIDs: retryMutation.messageIDs,
                createdAt: retryMutation.createdAt,
                attempt: 0
            )
        } else {
            retryMutation.attempt = 0
        }
        try await queue.enqueue(retryMutation)
    }

    public func apply(_ mutation: PendingMutation) async throws {
        try validateMutationSource(mutation.sourceID)
        switch mutation.kind {
        case .setRead(let isRead):
            try await setSystemFlag(.seen, isEnabled: isRead, for: mutation.messageIDs)
        case .setFlagged(let isFlagged):
            try await setSystemFlag(.flagged, isEnabled: isFlagged, for: mutation.messageIDs)
        case .setFlagColor:
            // IMAP flag colors are not replayable until keyword persistence is
            // implemented. Surface this queued intent as a conflict instead
            // of silently acknowledging and dropping the user's change.
            throw MailBackendError.notSupported(.flagColors)
        case .move(let folderID):
            try await performMove(messageIDs: mutation.messageIDs, toFolderID: folderID)
        case .copy(let folderID):
            try await performCopy(messageIDs: mutation.messageIDs, toFolderID: folderID)
        case .delete:
            try await performDelete(messageIDs: mutation.messageIDs)
        case .setJunk(let isJunk):
            try await performSetJunk(isJunk, for: mutation.messageIDs)
        case .setLabels(let labels, let isEnabled):
            try await performSetLabels(labels, isEnabled: isEnabled, for: mutation.messageIDs)
        case .send(draft: let draft):
            try await replaySendDraft(draft)
        case .sendStagedDraft(let stagedDraftID):
            guard let draft = await draftStagingStore?.draft(
                accountID: account.id,
                draftID: stagedDraftID
            ) else {
                throw MailBackendError.notFound(id: stagedDraftID)
            }
            try await replaySendDraft(draft)
        }
    }

    private func replaySendDraft(_ draft: Draft) async throws {
        // A scheduled send composed while offline is queued here with its
        // future delivery time intact (scheduleSend threw at requireConnected
        // before it could register the schedule). Replaying it on reconnect
        // must NOT deliver immediately — re-register the schedule so it fires
        // at the intended time. Only an overdue (past-due) schedule, or an
        // unscheduled send, goes out now.
        if let scheduledFor = draft.scheduledFor, scheduledFor > Date() {
            _ = try await scheduleSend(draft: draft)
        } else {
            _ = try await performImmediateSend(draft: draft)
        }
    }

    public func calendarEvent(from attachmentID: String) async throws -> CalendarEvent {
        _ = attachmentID
        try await state.requireConnected()
        throw MailBackendError.notSupported(capabilities)
    }

    public func replyToCalendarInvite(
        messageID: String,
        response: AttendeeState
    ) async throws {
        _ = messageID
        _ = response
        try await state.requireConnected()
        throw MailBackendError.notSupported(capabilities)
    }

    public func subscribeToChanges() -> AsyncStream<MailEvent> {
        let baseStream = state.eventStream()
        guard let idleEventsOperation,
              listMessagesOperation != nil
        else {
            return baseStream
        }

        return AsyncStream { continuation in
            let forwardingTask = Task {
                for await event in baseStream {
                    continuation.yield(event)
                }
            }
            let idleTask = Task {
                for await remoteAvailable in state.remoteAvailabilityStream() {
                    guard !Task.isCancelled else { return }
                    guard remoteAvailable else { continue }
                    await watchInboxAndActiveFolderForIdleEvents(using: idleEventsOperation)
                    return
                }
            }

            continuation.onTermination = { _ in
                forwardingTask.cancel()
                idleTask.cancel()
            }
        }
    }

    public func extensionService<Service>(_ type: Service.Type) -> Service? {
        switch ObjectIdentifier(type) {
        case ObjectIdentifier(CachedMessageHeaderProviding.self):
            return self as? Service
        case ObjectIdentifier(SyncHealthReporting.self),
             ObjectIdentifier(SyncConflictReviewing.self),
             ObjectIdentifier(SyncHealthRepairing.self):
            return self as? Service
        case ObjectIdentifier(MailboxBackgroundRefreshing.self):
            return self as? Service
        case ObjectIdentifier(OutboxManaging.self):
            return self as? Service
        case ObjectIdentifier(MessageLabelManaging.self):
            guard setMessageLabelsOperation != nil else { return nil }
            return self as? Service
        case ObjectIdentifier(ScheduledSendManaging.self):
            return self as? Service
        case ObjectIdentifier(ContactLookupProviding.self):
            return contactLookupProvider as? Service
        case ObjectIdentifier(ManageSieveRuleSyncing.self):
            guard let manageSieveRuleSyncOperation,
                  configuration.manageSieve != nil else {
                return nil
            }
            return IMAPManageSieveRuleSyncService(
                accountID: account.id,
                configuration: configuration,
                credential: credential,
                syncOperation: manageSieveRuleSyncOperation
            ) as? Service
        default:
            return nil
        }
    }

    public func setContactLookupProvider(_ provider: (any ContactLookupProviding)?) {
        contactLookupProvider = provider
    }

    public func cachedMessageHeader(
        messageID: MessageHeader.ID,
        folderID: Folder.ID
    ) async -> MessageHeader? {
        await cachedHeaders(folderID: folderID)?.first { $0.id == messageID }
    }

    /// Apply an offline-retention window to one folder by evicting cached
    /// message *bodies* that fall outside it. Headers stay (they are cheap
    /// and power the list/search); only the heavy body bytes are dropped,
    /// matching the "Headers only" semantics.
    ///
    /// Bodies carry no date, so the cutoff is computed from cached
    /// `MessageHeader.date` values. With no warm local-index or header-cache
    /// headers for the folder we have no dates and must not guess — the call
    /// no-ops.
    ///
    /// - Parameters:
    ///   - retentionDays: age cutoff in days; `nil` means no age limit.
    ///   - keepsBodies: `false` evicts every body in the folder
    ///     (Headers-only); `true` keeps bodies subject to `retentionDays`.
    public func applyRetention(
        folderID: Folder.ID,
        retentionDays: Int?,
        keepsBodies: Bool
    ) async {
        await applyRetention(
            folderID: folderID,
            retentionDays: retentionDays,
            keepsBodies: keepsBodies,
            keepingMessageIDs: []
        )
    }

    /// Pin-aware retention (#268): identical to the standard sweep except a body
    /// whose message ID is in `keepingMessageIDs` is never evicted. With an empty
    /// set this is byte-identical to the previous behaviour.
    public func applyRetention(
        folderID: Folder.ID,
        retentionDays: Int?,
        keepsBodies: Bool,
        keepingMessageIDs: Set<MessageHeader.ID>
    ) async {
        // keepAll: bodies kept, no age window — nothing to prune.
        if keepsBodies, retentionDays == nil { return }
        guard sourceCache != nil || bodyCache != nil || localSearchIndex != nil else { return }
        // Evict all folder bodies up front, keeping pinned IDs. The except-based
        // variant also reclaims orphan bodies (bodies with no surviving header)
        // that the per-header loop below cannot enumerate.
        if !keepsBodies {
            await sourceCache?.removeSources(
                inFolder: folderID,
                accountID: account.id,
                exceptMessageIDs: keepingMessageIDs
            )
            await bodyCache?.removeBodies(
                inFolder: folderID,
                accountID: account.id,
                exceptMessageIDs: keepingMessageIDs
            )
            await localSearchIndex?.deleteRawMessages(
                inFolder: folderID,
                except: keepingMessageIDs,
                account: account
            )
        }
        guard let headers = await retentionHeaders(folderID: folderID),
              !headers.isEmpty
        else { return }

        let evictIDs: [MessageHeader.ID]
        if !keepsBodies {
            evictIDs = headers.map(\.id).filter { !keepingMessageIDs.contains($0) }
        } else if let retentionDays {
            let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
            evictIDs = headers
                .filter { $0.date < cutoff && !keepingMessageIDs.contains($0.id) }
                .map(\.id)
        } else {
            return
        }

        guard !evictIDs.isEmpty else { return }
        await sourceCache?.removeSources(messageIDs: evictIDs, accountID: account.id)
        await bodyCache?.removeBodies(messageIDs: evictIDs, accountID: account.id)
        if keepsBodies || !keepingMessageIDs.isEmpty {
            await localSearchIndex?.deleteRawMessages(evictIDs, account: account)
        }
    }

    private func retentionHeaders(folderID: Folder.ID) async -> [MessageHeader]? {
        var headers: [MessageHeader] = []
        if let indexedHeaders = await retentionIndexedHeaders(folderID: folderID) {
            headers.append(contentsOf: indexedHeaders)
        }
        if let cached = await cachedHeaders(folderID: folderID) {
            headers.append(contentsOf: cached)
        }
        let deduplicated = Self.deduplicatedByID(headers)
        return deduplicated.isEmpty ? nil : deduplicated
    }

    private func retentionIndexedHeaders(folderID: Folder.ID) async -> [MessageHeader]? {
        guard let folder = await retentionFolder(id: folderID) else { return nil }
        return await allIndexedHeaders(folder: folder)
    }

    /// All cached headers for a folder, paged out of the local search index.
    /// `nil` when no index is wired or it holds nothing for the folder.
    private func allIndexedHeaders(folder: Folder) async -> [MessageHeader]? {
        guard let localSearchIndex else { return nil }
        var allHeaders: [MessageHeader] = []
        var pageToken: String?
        var visitedPageTokens = Set<String>()
        while true {
            guard let page = await localSearchIndex.cachedHeaders(
                for: folder,
                account: account,
                pageToken: pageToken
            ) else {
                return allHeaders.isEmpty ? nil : allHeaders
            }
            allHeaders.append(contentsOf: page.headers)

            guard let nextPageToken = page.nextPageToken else { break }
            guard visitedPageTokens.insert(nextPageToken).inserted else { break }
            pageToken = nextPageToken
        }
        return allHeaders
    }

    private func retentionFolder(id folderID: Folder.ID) async -> Folder? {
        if let folder = await state.folder(id: folderID) {
            return folder
        }
        return await folderCache?.snapshot(accountID: account.id)?
            .folders
            .first { $0.id == folderID }
    }

    private static func folders(from listings: [IMAPFolderListing]) -> [Folder] {
        let knownPaths = Set(listings.map(\.path))
        // IMAP \Noselect parents (notably Gmail's "[Gmail]" container) cannot be
        // SELECT-ed. Keep them out of the selectable folder set so all-folder
        // server search and other SELECT-based operations do not fail on them.
        // Parent IDs still resolve via knownPaths from the full LIST response.
        return listings
            .filter(isSelectableMailbox)
            .map { listing in
                Folder(
                    id: listing.path,
                    name: listing.displayName,
                    role: listing.role,
                    parentID: parentID(for: listing, knownPaths: knownPaths),
                    unreadCount: listing.unreadCount,
                    totalCount: listing.totalCount
                )
            }
    }

    private static func isSelectableMailbox(_ listing: IMAPFolderListing) -> Bool {
        !listing.flags.contains("noselect")
    }

    private static func folderDelimiters(from listings: [IMAPFolderListing]) -> [Folder.ID: String] {
        // A server can list the same mailbox path twice; keep the first rather
        // than trapping on the duplicate key.
        Dictionary(
            listings.map { listing in
                (listing.path, listing.delimiter.isEmpty ? "/" : listing.delimiter)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func parentID(
        for listing: IMAPFolderListing,
        knownPaths: Set<String>
    ) -> Folder.ID? {
        guard !listing.delimiter.isEmpty,
              let range = listing.path.range(
                  of: listing.delimiter,
                  options: .backwards
              )
        else {
            return nil
        }
        let parentPath = String(listing.path[..<range.lowerBound])
        return knownPaths.contains(parentPath) ? parentPath : nil
    }

    private func folderID(name: String, parentID: Folder.ID?) async -> Folder.ID {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parentID, !parentID.isEmpty else {
            return trimmedName
        }
        let delimiter = await state.hierarchyDelimiter(for: parentID) ?? "/"
        return "\(parentID)\(delimiter)\(trimmedName)"
    }

    private static func parentFolderID(from folderID: Folder.ID) -> Folder.ID? {
        guard let separator = folderID.lastIndex(of: "/") else { return nil }
        let parentID = String(folderID[..<separator])
        return parentID.isEmpty ? nil : parentID
    }

    private static func header(
        from listing: IMAPMessageListing,
        folderID: Folder.ID,
        hasAttachments: Bool = false
    ) -> MessageHeader {
        let id = "\(folderID):\(listing.uid)"
        return MessageHeader(
            id: id,
            threadID: listing.messageID.isEmpty ? id : listing.messageID,
            folderID: folderID,
            from: listing.from,
            replyTo: listing.replyTo,
            to: listing.to,
            cc: listing.cc,
            bcc: listing.bcc,
            subject: listing.subject,
            snippet: listing.snippet,
            date: listing.date,
            isRead: listing.isRead,
            isFlagged: listing.isFlagged,
            isAnswered: listing.isAnswered,
            hasAttachments: hasAttachments,
            messageID: listing.messageID.isEmpty ? nil : listing.messageID,
            inReplyTo: listing.inReplyTo,
            labels: listing.labels
        )
    }

    private static func updatedHeader(
        _ header: MessageHeader,
        date: Date? = nil,
        isRead: Bool? = nil,
        isFlagged: Bool? = nil
    ) -> MessageHeader {
        MessageHeader(
            id: header.id,
            threadID: header.threadID,
            folderID: header.folderID,
            from: header.from,
            replyTo: header.replyTo,
            to: header.to,
            cc: header.cc,
            bcc: header.bcc,
            subject: header.subject,
            snippet: header.snippet,
            date: date ?? header.date,
            isRead: isRead ?? header.isRead,
            isFlagged: isFlagged ?? header.isFlagged,
            isAnswered: header.isAnswered,
            isForwarded: header.isForwarded,
            hasAttachments: header.hasAttachments,
            flagColor: isFlagged == false ? nil : header.flagColor,
            messageID: header.messageID,
            inReplyTo: header.inReplyTo,
            labels: header.labels
        )
    }

    private static func serverSearchQuery(from query: SearchQuery) -> SearchQuery {
        guard query.hasAttachments != nil else { return query }
        var serverQuery = query
        serverQuery.hasAttachments = nil
        return serverQuery
    }

    private static func serverSearchCandidateLimit(for query: SearchQuery) -> Int {
        query.hasAttachments == nil ? defaultServerSearchCandidateLimit : Int.max
    }

    private static func sortedSearchResults(_ headers: [MessageHeader]) -> [MessageHeader] {
        Array(sortedHeaders(headers).prefix(searchResultLimit))
    }

    private static func sortedHeaders(_ headers: [MessageHeader]) -> [MessageHeader] {
        headers.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.id > rhs.id
            }
            return lhs.date > rhs.date
        }
    }

    /// Drops headers whose id already appeared (a server may return two FETCH
    /// lines for one UID), keeping the first occurrence and preserving order, so
    /// duplicate-id headers never enter the cache.
    private static func deduplicatedByID(_ headers: [MessageHeader]) -> [MessageHeader] {
        var seen = Set<MessageHeader.ID>()
        return headers.filter { seen.insert($0.id).inserted }
    }

    private func cacheHeaders(
        _ headers: [MessageHeader],
        folderID: Folder.ID,
        uidValidity: Int? = nil,
        highestModSeq: UInt64? = nil,
        nextPageToken: String? = nil,
        mergingWithExisting: Bool = false,
        loadedPageToken: String? = nil
    ) async {
        await localSearchIndex?.storeHeaders(Self.deduplicatedByID(headers), account: account)
        let firstPageHeaderIDs = Set(headers.map(\.id))
        if let cachedSnapshot = await cachedHeaderSnapshot(folderID: folderID) {
            if !mergingWithExisting,
               let previousFirstPageHeaderIDs = cachedSnapshot.firstPageHeaderIDs {
                let retainedHeaders = nextPageToken == nil
                    ? []
                    : cachedSnapshot.headers.filter {
                        !previousFirstPageHeaderIDs.contains($0.id)
                    }
                var headersByID = Dictionary(retainedHeaders.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
                for header in headers {
                    headersByID[header.id] = header
                }
                await headerCache?.setSnapshot(
                    IMAPMailboxHeaderCacheSnapshot(
                        headers: Self.sortedHeaders(Array(headersByID.values)),
                        uidValidity: uidValidity ?? cachedSnapshot.uidValidity,
                        highestModSeq: highestModSeq ?? cachedSnapshot.highestModSeq,
                        nextPageToken: nextPageToken,
                        firstPageHeaderIDs: firstPageHeaderIDs,
                        pageHeaderIDsByToken: cachedSnapshot.pageHeaderIDsByToken
                    ),
                    accountID: account.id,
                    folderID: folderID
                )
                return
            }

            if mergingWithExisting {
                var headersByID = Dictionary(cachedSnapshot.headers.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
                for header in headers {
                    headersByID[header.id] = header
                }
                var pageHeaderIDsByToken = cachedSnapshot.pageHeaderIDsByToken
                if let loadedPageToken {
                    pageHeaderIDsByToken[loadedPageToken] = Set(headers.map(\.id))
                }
                await headerCache?.setSnapshot(
                    IMAPMailboxHeaderCacheSnapshot(
                        headers: Self.sortedHeaders(Array(headersByID.values)),
                        uidValidity: cachedSnapshot.uidValidity,
                        highestModSeq: highestModSeq ?? cachedSnapshot.highestModSeq,
                        nextPageToken: nextPageToken,
                        firstPageHeaderIDs: cachedSnapshot.firstPageHeaderIDs,
                        pageHeaderIDsByToken: pageHeaderIDsByToken
                    ),
                    accountID: account.id,
                    folderID: folderID
                )
                return
            }
        }
        await headerCache?.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(
                headers: Self.deduplicatedByID(headers),
                uidValidity: uidValidity,
                highestModSeq: highestModSeq,
                nextPageToken: nextPageToken,
                firstPageHeaderIDs: mergingWithExisting ? nil : firstPageHeaderIDs,
                pageHeaderIDsByToken: loadedPageToken.map {
                    [$0: firstPageHeaderIDs]
                } ?? [:]
            ),
            accountID: account.id,
            folderID: folderID
        )
    }

    /// Reconciles the server's reported UIDVALIDITY for a folder against the
    /// cache, clearing local caches and evicting folder-scoped pending mutations
    /// when it changed. Returns `true` when the UIDVALIDITY changed (so callers
    /// can force a full refetch even if other change signals look unchanged).
    @discardableResult
    private func reconcileUIDValidity(_ uidValidity: Int?, folderID: Folder.ID) async -> Bool {
        guard let uidValidity else { return false }
        let cachedUIDValidity = await cachedHeaderSnapshot(folderID: folderID)?.uidValidity
        let didCachedUIDValidityChange = cachedUIDValidity.map { $0 != uidValidity } ?? false
        let didRecordedUIDValidityChange = await state.recordUIDValidity(uidValidity, folderID: folderID)
        guard didRecordedUIDValidityChange || didCachedUIDValidityChange else { return false }
        await clearLocalCaches()
        _ = await state.recordUIDValidity(uidValidity, folderID: folderID)
        // The folder's UIDs were reassigned, so any queued offline mutation
        // that targets a message there now points at a *different* message.
        // Evict those as recoverable conflicts instead of letting replay act
        // on the wrong message.
        await invalidatePendingMutations(targetingFolderID: folderID)
        return true
    }

    /// Removes queued mutations whose target messages live in `folderID` and
    /// surfaces them as `targetMissing` conflicts. Called when a UIDVALIDITY
    /// change invalidates that folder's UIDs (#13). `send` mutations have no
    /// folder-scoped target and are left untouched.
    ///
    /// Internal (not private) so it can be unit-tested directly.
    func invalidatePendingMutations(targetingFolderID folderID: Folder.ID) async {
        guard let queue = offlineMutationQueue,
              let pending = try? await queue.pending(),
              !pending.isEmpty
        else {
            return
        }

        var conflicts: [MutationConflict] = []
        for mutation in pending where !mutation.messageIDs.isEmpty {
            let targetsFolder = (try? Self.messageReferencesByFolder(from: mutation.messageIDs))?
                .contains { $0.folderID == folderID } ?? false
            guard targetsFolder else { continue }
            try? await queue.remove(id: mutation.id)
            conflicts.append(MutationConflict(
                mutation: mutation,
                reason: .targetMissing,
                message: "“\(mutation.kind.operationDescription)” could not be applied: the folder was "
                    + "resynced (its message IDs changed), so the original messages can no longer be located."
            ))
        }

        guard !conflicts.isEmpty else { return }
        try? await offlineMutationConflictStore?.append(conflicts)
        await state.recordReplayConflictDescription(conflicts[0].message, count: conflicts.count)
    }

    private func reconcileFirstPageHeaderChanges(
        _ headers: [MessageHeader],
        folderID: Folder.ID,
        removesMissingHeaders: Bool
    ) async -> [MailEvent] {
        guard let cachedSnapshot = await cachedHeaderSnapshot(folderID: folderID),
              let previousFirstPageHeaderIDs = cachedSnapshot.firstPageHeaderIDs
        else {
            return []
        }

        var events: [MailEvent] = []
        if let updateEvent = cachedHeaderUpdateEvent(
            headers,
            cachedSnapshot: cachedSnapshot,
            folderID: folderID
        ) {
            events.append(updateEvent)
        }

        guard removesMissingHeaders else { return events }
        let currentIDs = Set(headers.map(\.id))
        let removalCandidateIDs = removesMissingHeaders
            ? Set(cachedSnapshot.headers.map(\.id))
            : previousFirstPageHeaderIDs
        let removedIDSet = removalCandidateIDs.subtracting(currentIDs)
        guard !removedIDSet.isEmpty else { return events }
        let removedIDs = cachedSnapshot.headers
            .map(\.id)
            .filter { removedIDSet.contains($0) }
        if let groups = try? Self.messageReferencesByFolder(from: removedIDs) {
            for group in groups {
                await removeCachedMessageSources(folderID: group.folderID, uids: group.uids)
            }
        }
        await localSearchIndex?.deleteMessages(removedIDs, account: account)
        events.append(.messagesRemoved(
            folderID: folderID,
            messageIDs: removedIDs
        ))
        return events
    }

    private func cachedHeaderUpdateEvent(
        _ headers: [MessageHeader],
        folderID: Folder.ID
    ) async -> MailEvent? {
        guard let cachedSnapshot = await cachedHeaderSnapshot(folderID: folderID) else {
            return nil
        }
        return cachedHeaderUpdateEvent(
            headers,
            cachedSnapshot: cachedSnapshot,
            folderID: folderID
        )
    }

    private func reconcileCachedPageRemovals(
        _ headers: [MessageHeader],
        folderID: Folder.ID,
        pageToken: String?
    ) async -> MailEvent? {
        guard let pageToken,
              let cachedSnapshot = await cachedHeaderSnapshot(folderID: folderID),
              let previousPageHeaderIDs = cachedSnapshot.pageHeaderIDsByToken[pageToken]
        else {
            return nil
        }

        let currentIDs = Set(headers.map(\.id))
        let removedIDSet = previousPageHeaderIDs.subtracting(currentIDs)
        guard !removedIDSet.isEmpty else { return nil }
        let removedIDs = cachedSnapshot.headers
            .map(\.id)
            .filter { removedIDSet.contains($0) }
        if let groups = try? Self.messageReferencesByFolder(from: removedIDs) {
            for group in groups {
                await removeCachedMessageSources(folderID: group.folderID, uids: group.uids)
                await removeCachedHeaders(folderID: group.folderID, uids: group.uids)
            }
        }
        return .messagesRemoved(
            folderID: folderID,
            messageIDs: removedIDs
        )
    }

    private func cachedHeaderUpdateEvent(
        _ headers: [MessageHeader],
        cachedSnapshot: IMAPMailboxHeaderCacheSnapshot,
        folderID: Folder.ID
    ) -> MailEvent? {
        // Use the failable-merge initializer, not Dictionary(uniqueKeysWithValues:),
        // for the same reason as the sibling sites: a buggy/hostile server can emit
        // two FETCH lines for one UID, which produces two headers with the same id
        // in the cached snapshot. The trapping initializer would crash the refresh.
        let previousHeadersByID = Dictionary(
            cachedSnapshot.headers.map { ($0.id, $0) },
            uniquingKeysWith: { _, newer in newer }
        )
        let updatedIDs = headers.compactMap { header -> MessageHeader.ID? in
            guard let previous = previousHeadersByID[header.id],
                  previous != header
            else {
                return nil
            }
            return header.id
        }
        guard !updatedIDs.isEmpty else { return nil }
        return .messagesUpdated(
            folderID: folderID,
            messageIDs: updatedIDs
        )
    }

    private func emit(_ events: [MailEvent]) async {
        for event in events {
            await state.emit(event)
        }
    }

    private func cachedHeaders(folderID: Folder.ID) async -> [MessageHeader]? {
        await cachedHeaderSnapshot(folderID: folderID)?.headers
    }

    /// Message IDs whose date couldn't be repaired (no cached source, or a
    /// source with no parseable date). Memoized so the repair pass doesn't
    /// re-read and re-decode the same unrepairable messages from disk on every
    /// first-page cache hit. Invalidated for an ID when its source is (re)cached.
    private let unrepairableDateHeaderLock = NSLock()
    private var unrepairableDateHeaderIDs: Set<MessageHeader.ID> = []

    private func isKnownUnrepairableDate(_ messageID: MessageHeader.ID) -> Bool {
        unrepairableDateHeaderLock.withLock { unrepairableDateHeaderIDs.contains(messageID) }
    }

    private func markUnrepairableDate(_ messageID: MessageHeader.ID) {
        unrepairableDateHeaderLock.withLock { _ = unrepairableDateHeaderIDs.insert(messageID) }
    }

    private func clearUnrepairableDate(_ messageID: MessageHeader.ID) {
        unrepairableDateHeaderLock.withLock { _ = unrepairableDateHeaderIDs.remove(messageID) }
    }

    /// Returns the cached snapshot immediately, scheduling any needed date
    /// repair in the background. This keeps the cache-hit path fast — the
    /// caller gets headers on the first frame even if some have legacy
    /// `Date.distantPast` values that need repair from cached raw message
    /// sources. The background repair writes the fixed dates back to the
    /// cache and emits `.messagesUpdated` events so the UI refreshes.
    private func repairedCachedHeaderSnapshotIfNeeded(
        _ snapshot: IMAPMailboxHeaderCacheSnapshot,
        folderID: Folder.ID
    ) async -> IMAPMailboxHeaderCacheSnapshot {
        guard sourceCache != nil,
              snapshot.headers.contains(where: {
                  Self.needsDateRepair($0.date) && !isKnownUnrepairableDate($0.id)
              })
        else {
            return snapshot
        }

        // Return the original snapshot immediately so the caller can render
        // the first frame without waiting for disk reads. Schedule the actual
        // repair in the background — it will update the cache and emit events.
        scheduleBackgroundDateRepair(snapshot, folderID: folderID)
        return snapshot
    }

    /// Background date-repair task per folder. Keyed by folder so a new
    /// request cancels the prior in-flight repair (N rapid reloads → 1
    /// repair pass). Separate from `backgroundRefreshTasks` so a network
    /// refresh doesn't cancel an in-flight repair and vice versa.
    private let backgroundDateRepairLock = NSLock()
    private var backgroundDateRepairTasks: [Folder.ID: Task<Void, Never>] = [:]

    private func scheduleBackgroundDateRepair(
        _ snapshot: IMAPMailboxHeaderCacheSnapshot,
        folderID: Folder.ID
    ) {
        let task = Task { [weak self] in
            guard let self else { return }
            await performDateRepair(snapshot, folderID: folderID)
        }
        let previous: Task<Void, Never>? = backgroundDateRepairLock.withLock {
            let existing = backgroundDateRepairTasks[folderID]
            backgroundDateRepairTasks[folderID] = task
            return existing
        }
        previous?.cancel()
    }

    private func cancelBackgroundDateRepairTasks() {
        let tasks = backgroundDateRepairLock.withLock {
            let snapshot = Array(backgroundDateRepairTasks.values)
            backgroundDateRepairTasks.removeAll()
            return snapshot
        }
        for task in tasks {
            task.cancel()
        }
    }

    private func performDateRepair(
        _ snapshot: IMAPMailboxHeaderCacheSnapshot,
        folderID: Folder.ID
    ) async {
        // Collect date patches only — never rewrite the folder from the
        // schedule-time snapshot. A concurrent first-page refresh or flag
        // update may have advanced the live cache while we were reading
        // raw sources.
        var repairedDates: [MessageHeader.ID: Date] = [:]
        repairedDates.reserveCapacity(snapshot.headers.count)

        for header in snapshot.headers {
            guard !Task.isCancelled else { return }
            guard Self.needsDateRepair(header.date),
                  !isKnownUnrepairableDate(header.id)
            else {
                continue
            }
            guard let source = await cachedMessageSource(messageID: header.id),
                  let repairedDate = IMAPDateParser.dateHeader(from: source.rawMessage)
            else {
                // Source missing or has no parseable date — remember it so we
                // don't re-read it next time. Cleared if the source is recached.
                markUnrepairableDate(header.id)
                continue
            }

            repairedDates[header.id] = repairedDate
        }

        guard !Task.isCancelled, !repairedDates.isEmpty else { return }

        guard var current = await cachedHeaderSnapshot(folderID: folderID) else { return }
        var appliedIDs: [MessageHeader.ID] = []
        appliedIDs.reserveCapacity(repairedDates.count)
        current.headers = current.headers.map { header in
            guard let repairedDate = repairedDates[header.id],
                  Self.needsDateRepair(header.date)
            else {
                return header
            }
            appliedIDs.append(header.id)
            return Self.updatedHeader(header, date: repairedDate)
        }

        guard !Task.isCancelled, !appliedIDs.isEmpty else { return }

        current.headers = Self.sortedHeaders(current.headers)
        await headerCache?.setSnapshot(
            current,
            accountID: account.id,
            folderID: folderID
        )
        let appliedHeaders = current.headers.filter { appliedIDs.contains($0.id) }
        await localSearchIndex?.storeHeaders(appliedHeaders, account: account)
        guard !Task.isCancelled else { return }
        // Emit update events so the UI refreshes with the corrected dates.
        await emit([.messagesUpdated(folderID: folderID, messageIDs: appliedIDs)])
    }

    private static func needsDateRepair(_ date: Date) -> Bool {
        date == Date.distantPast
    }

    private func cachedHeaderSnapshot(folderID: Folder.ID) async -> IMAPMailboxHeaderCacheSnapshot? {
        await headerCache?.snapshot(accountID: account.id, folderID: folderID)
    }

    private func updateCachedHeaders(
        folderID: Folder.ID,
        uids: [Int],
        flag: IMAPSystemFlag,
        isEnabled: Bool
    ) async {
        guard var snapshot = await cachedHeaderSnapshot(folderID: folderID) else { return }
        let targetIDs = Set(Self.messageIDs(folderID: folderID, uids: uids))
        snapshot.headers = snapshot.headers.map { header in
            guard targetIDs.contains(header.id) else { return header }
            switch flag {
            case .seen:
                return Self.updatedHeader(header, isRead: isEnabled)
            case .flagged:
                return Self.updatedHeader(header, isFlagged: isEnabled)
            default:
                return header
            }
        }
        await headerCache?.setSnapshot(snapshot, accountID: account.id, folderID: folderID)
        await localSearchIndex?.storeHeaders(
            snapshot.headers.filter { targetIDs.contains($0.id) },
            account: account
        )
    }

    private func removeCachedHeaders(folderID: Folder.ID, uids: [Int]) async {
        let targetIDs = Set(Self.messageIDs(folderID: folderID, uids: uids))
        await localSearchIndex?.deleteMessages(Array(targetIDs), account: account)
        guard var snapshot = await cachedHeaderSnapshot(folderID: folderID) else { return }
        snapshot.headers.removeAll { targetIDs.contains($0.id) }
        if var firstPageHeaderIDs = snapshot.firstPageHeaderIDs {
            firstPageHeaderIDs.subtract(targetIDs)
            snapshot.firstPageHeaderIDs = firstPageHeaderIDs
        }
        snapshot.pageHeaderIDsByToken = snapshot.pageHeaderIDsByToken.mapValues { ids in
            ids.subtracting(targetIDs)
        }
        await headerCache?.setSnapshot(snapshot, accountID: account.id, folderID: folderID)
    }

    private func applyCONDSTOREFlagChanges(
        _ changes: [(uid: Int, flags: [String])],
        folderID: Folder.ID,
        newHighestModSeq: UInt64?
    ) async {
        guard var snapshot = await cachedHeaderSnapshot(folderID: folderID) else { return }
        // A server may emit more than one FETCH line for the same UID within one
        // response (RFC 3501 §7.4.1 unsolicited updates / a flag change racing the
        // CHANGEDSINCE fetch). `Dictionary(uniqueKeysWithValues:)` would TRAP on
        // the duplicate; keep the last (newest modseq-ordered) flags instead.
        let changesByUID = Dictionary(changes.map { ($0.uid, $0.flags) }, uniquingKeysWith: { _, newer in newer })
        snapshot.headers = snapshot.headers.map { header in
            guard let ref = try? Self.messageReference(from: header.id),
                  let newFlags = changesByUID[ref.uid] else { return header }
            let rawFlagsLowered = newFlags.map { $0.lowercased() }
            var updated = header
            updated = Self.updatedHeader(updated, isRead: rawFlagsLowered.contains("\\seen"))
            updated = Self.updatedHeader(updated, isFlagged: rawFlagsLowered.contains("\\flagged"))
            return updated
        }
        if let newModSeq = newHighestModSeq {
            snapshot.highestModSeq = newModSeq
        }
        await headerCache?.setSnapshot(snapshot, accountID: account.id, folderID: folderID)
        await localSearchIndex?.storeHeaders(snapshot.headers, account: account)
    }

    private func updateCachedHighestModSeq(_ newModSeq: UInt64, folderID: Folder.ID) async {
        guard var snapshot = await cachedHeaderSnapshot(folderID: folderID) else { return }
        snapshot.highestModSeq = newModSeq
        await headerCache?.setSnapshot(snapshot, accountID: account.id, folderID: folderID)
    }

    private func cachedSearchResults(
        for query: SearchQuery,
        folders: [Folder]
    ) async -> [MessageHeader] {
        let interval = MailPerformanceDiagnostics.beginInterval("IMAP Search Cache Read")
        defer { MailPerformanceDiagnostics.endInterval(interval) }
        let searchedFolderCount = query.folderID == nil ? folders.count : 1
        let snapshot = MailPerformanceDiagnostics.searchSnapshot(
            for: query,
            searchedFolderCount: searchedFolderCount
        )
        func logResult(_ headers: [MessageHeader]) {
            MailPerformanceDiagnostics.logSearchCacheRead(
                snapshot: snapshot,
                resultCount: headers.count,
                durationMilliseconds: MailPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
        }

        var headers: [MessageHeader] = []
        for localIndexQuery in Self.localIndexQueries(for: query, folders: folders) {
            if let indexedResults = await localSearchIndex?.search(
                localIndexQuery,
                account: account,
                limit: Self.searchResultLimit
            ), !indexedResults.isEmpty {
                headers.append(contentsOf: Self.scopedIndexedSearchResults(
                    indexedResults,
                    query: localIndexQuery,
                    folders: folders
                ))
            }
        }

        guard headerCache != nil else {
            let results = Self.sortedSearchResults(headers)
            logResult(results)
            return results
        }
        let folderIDs: [Folder.ID]
        if let folderID = query.folderID {
            folderIDs = [folderID]
        } else {
            folderIDs = folders.map(\.id)
        }

        for folderID in folderIDs {
            if let cached = await cachedHeaders(folderID: folderID) {
                headers.append(contentsOf: cached.filter { query.matches($0) })
            }
        }
        let results = Self.sortedSearchResults(Self.deduplicatedByID(headers))
        logResult(results)
        return results
    }

    private static func localIndexQueries(
        for query: SearchQuery,
        folders: [Folder]
    ) -> [SearchQuery] {
        guard query.folderID == nil, !folders.isEmpty else {
            return [query]
        }
        return folders.map { folder in
            var folderQuery = query
            folderQuery.folderID = folder.id
            return folderQuery
        }
    }

    private static func scopedIndexedSearchResults(
        _ headers: [MessageHeader],
        query: SearchQuery,
        folders: [Folder]
    ) -> [MessageHeader] {
        guard query.folderID == nil, !folders.isEmpty else { return headers }
        let currentFolderIDs = Set(folders.map(\.id))
        return headers.filter { currentFolderIDs.contains($0.folderID) }
    }

    private func loadMessageSource(messageID: MessageHeader.ID) async throws -> IMAPMessageSource {
        let reference = try Self.messageReference(from: messageID)
        return try await loadMessageSource(
            messageID: messageID,
            folderID: reference.folderID,
            uid: reference.uid
        )
    }

    private func loadMessageSource(
        messageID: MessageHeader.ID,
        folderID: Folder.ID,
        uid: Int
    ) async throws -> IMAPMessageSource {
        let interval = MailPerformanceDiagnostics.beginInterval("IMAP Message Source")
        defer { MailPerformanceDiagnostics.endInterval(interval) }
        func durationMilliseconds() -> Int {
            MailPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
        }

        if let cached = await cachedMessageSource(messageID: messageID) {
            MailPerformanceDiagnostics.logBodySourceFinished(
                path: .cacheHit,
                durationMilliseconds: durationMilliseconds()
            )
            return cached
        }

        guard fetchMessageSourceOperation != nil else {
            let error = MailBackendError.notSupported(capabilities)
            MailPerformanceDiagnostics.logBodySourceFailed(
                error: error,
                durationMilliseconds: durationMilliseconds()
            )
            throw error
        }

        do {
            try await state.requireConnected()
            let source = try await fetchMessageSourceWithAuthenticatedOAuthRetry(
                folderID: folderID,
                uid: uid
            )
            await cacheMessageSource(source, messageID: messageID)
            MailPerformanceDiagnostics.logBodySourceFinished(
                path: .server,
                durationMilliseconds: durationMilliseconds()
            )
            return source
        } catch {
            if Self.shouldUseCacheFallback(for: error),
               let cached = await cachedMessageSource(messageID: messageID) {
                MailPerformanceDiagnostics.logBodySourceFinished(
                    path: .cacheFallback,
                    durationMilliseconds: durationMilliseconds()
                )
                return cached
            }
            MailPerformanceDiagnostics.logBodySourceFailed(
                error: error,
                durationMilliseconds: durationMilliseconds()
            )
            throw error
        }
    }

    private func cacheMessageSource(
        _ source: IMAPMessageSource,
        messageID: MessageHeader.ID
    ) async {
        await sourceCache?.setSource(
            source,
            accountID: account.id,
            messageID: messageID
        )
        await localSearchIndex?.storeRawMessage(
            Data(source.rawMessage.utf8),
            for: messageID,
            account: account
        )
        // A freshly cached source may now carry a parseable date, so allow the
        // repair pass to re-attempt this message.
        clearUnrepairableDate(messageID)
    }

    private func cachedMessageSource(messageID: MessageHeader.ID) async -> IMAPMessageSource? {
        let interval = MailPerformanceDiagnostics.beginInterval("IMAP Body Cache Read")
        defer { MailPerformanceDiagnostics.endInterval(interval) }
        let source: IMAPMessageSource?
        if let cached = await sourceCache?.source(accountID: account.id, messageID: messageID) {
            source = cached
        } else if let rawData = await localSearchIndex?.cachedRawMessage(
            for: messageID,
            account: account
        ), let reference = try? Self.messageReference(from: messageID) {
            source = IMAPMessageSource(
                uid: reference.uid,
                rawMessage: IMAPMessageBodyParser().rawMessageString(from: rawData)
            )
        } else {
            source = nil
        }
        MailPerformanceDiagnostics.logBodyCacheRead(
            hit: source != nil,
            durationMilliseconds: MailPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
        )
        return source
    }

    private func removeCachedMessageSources(folderID: Folder.ID, uids: [Int]) async {
        let messageIDs = Self.messageIDs(folderID: folderID, uids: uids)
        await localSearchIndex?.deleteRawMessages(messageIDs, account: account)
        await bodyCache?.removeBodies(messageIDs: messageIDs, accountID: account.id)
        guard let sourceCache else { return }
        for uid in uids {
            await sourceCache.removeSource(
                accountID: account.id,
                messageID: "\(folderID):\(uid)"
            )
        }
    }

    private func clearLocalCaches() async {
        await folderCache?.clear(accountID: account.id)
        await headerCache?.clear(accountID: account.id)
        await sourceCache?.clear(accountID: account.id)
        await bodyCache?.clear(accountID: account.id)
        await localSearchIndex?.clearAccount(account)
    }

    private func pendingMutationCount() async -> (count: Int, errorDescription: String?) {
        guard let offlineMutationQueue else { return (0, nil) }
        do {
            let pending = try await offlineMutationQueue.pending()
            return (pending.count, nil)
        } catch {
            return (
                0,
                String(
                    localized: "Couldn't read pending mail changes: \(Self.userFacingDescription(for: error))",
                    bundle: .module
                )
            )
        }
    }

    private func mutationConflictStatus() async -> (count: Int, errorDescription: String?) {
        guard let offlineMutationConflictStore else { return (0, nil) }
        do {
            let conflicts = try await offlineMutationConflictStore.conflicts()
            guard !conflicts.isEmpty else { return (0, nil) }
            return (conflicts.count, Self.mutationConflictDescription(for: conflicts))
        } catch {
            return (
                0,
                String(
                    localized: "Couldn't read pending mail conflict records: \(Self.userFacingDescription(for: error))",
                    bundle: .module
                )
            )
        }
    }

    private func validateMutationSource(_ sourceID: MailSourceID?) throws {
        guard let sourceID else { return }
        try validateSourceID(sourceID)
    }

    private func enqueueOfflineMutation(
        _ mutation: PendingMutation,
        for error: any Error
    ) async throws -> Bool {
        guard let offlineMutationQueue,
              Self.shouldQueueOfflineMutation(for: error)
        else {
            return false
        }
        try await offlineMutationQueue.enqueue(mutation)
        return true
    }

    static func shouldQueueOfflineMutation(for error: any Error) -> Bool {
        // Outbound security failures are permanent, not transient: a draft that
        // requests signing/encryption must fail closed and surface immediately,
        // never sit in the retry queue (ADR-0021 #4). The offline queue exists
        // for network/connectivity errors only.
        if error is OutboundCryptoEngineUnavailableError
            || error is OutboundMessageSecurityError
            || error is DraftValidationError {
            return false
        }
        if let refreshError = error as? OAuthRefreshError {
            return !refreshError.isPermanent
        }
        if let mailError = error as? MailBackendError {
            switch mailError {
            case .notConnected, .rateLimited, .network, .credentialStoreUnavailable:
                return true
            case .authenticationRequired, .notSupported, .notFound, .permissionDenied, .quotaExceeded:
                return false
            case .backendSpecific:
                return false
            }
        }
        if let smtpError = error as? SMTPClientError {
            switch smtpError {
            case .transport, .connectionRejected:
                return true
            case .invalidServerKind, .unsupportedTLSMode, .unsupportedAuthentication,
                 .authenticationUnavailable, .authenticationFailed, .commandFailed,
                 .malformedResponse, .deliveryOutcomeUnknown:
                return false
            }
        }
        return shouldUseCacheFallback(for: error)
    }

    private static func isAuthenticationFailure(_ error: any Error) -> Bool {
        if let imapError = error as? IMAPClientError,
           case .authenticationFailed = imapError {
            return true
        }
        if let smtpError = error as? SMTPClientError,
           case .authenticationFailed = smtpError {
            return true
        }
        if case MailBackendError.authenticationRequired = error {
            return true
        }
        return false
    }

    /// Runs one authenticated IMAP command and retries it exactly once when
    /// an expired XOAUTH2 credential is rejected. Concurrent commands share a
    /// single refresh exchange and then each retry with the persisted token.
    private func withAuthenticatedOAuthRetry<Result: Sendable>(
        _ operation: @escaping @Sendable (MailAccountCredential) async throws -> Result
    ) async throws -> Result {
        let attemptedCredential = credential
        do {
            return try await operation(attemptedCredential)
        } catch {
            guard attemptedCredential.authentication == .xoauth2,
                  Self.isAuthenticationFailure(error),
                  let refreshOAuthCredentialOperation
            else {
                throw error
            }

            let retryCredential = try await oauthCredentialRefreshCoordinator.run {
                let latestCredential = self.credential
                guard latestCredential == attemptedCredential else {
                    return latestCredential
                }
                let refreshedCredential = try await refreshOAuthCredentialOperation(
                    self.account.id,
                    self.configuration,
                    latestCredential
                )
                self.replaceCredentialForReconnect(refreshedCredential)
                return refreshedCredential
            }
            return try await operation(retryCredential)
        }
    }

    private func listMessagesWithAuthenticatedOAuthRetry(
        folderID: Folder.ID,
        pageToken: String?,
        limit: Int
    ) async throws -> IMAPMessageListingPage {
        guard let operation = listMessagesOperation else {
            throw MailBackendError.notSupported(capabilities)
        }
        return try await withAuthenticatedOAuthRetry { credential in
            try await operation(self.configuration, credential, folderID, pageToken, limit)
        }
    }

    private func searchMessagesWithAuthenticatedOAuthRetry(
        folderID: Folder.ID,
        query: SearchQuery,
        limit: Int
    ) async throws -> [IMAPMessageListing] {
        guard let operation = searchMessagesOperation else {
            throw MailBackendError.notSupported(capabilities)
        }
        return try await withAuthenticatedOAuthRetry { credential in
            try await operation(self.configuration, credential, folderID, query, limit)
        }
    }

    private func searchMessagePageWithAuthenticatedOAuthRetry(
        _ operation: @escaping MessageSearchPageOperation,
        folderID: Folder.ID,
        query: SearchQuery,
        pageToken: String?,
        limit: Int
    ) async throws -> IMAPMessageListingPage {
        try await withAuthenticatedOAuthRetry { credential in
            try await operation(self.configuration, credential, folderID, query, pageToken, limit)
        }
    }

    private func fetchMessageBodyWithAuthenticatedOAuthRetry(
        folderID: Folder.ID,
        uid: Int
    ) async throws -> MessageBody {
        guard let operation = fetchMessageBodyOperation else {
            throw MailBackendError.notSupported(capabilities)
        }
        return try await withAuthenticatedOAuthRetry { credential in
            try await operation(self.configuration, credential, folderID, uid)
        }
    }

    private func fetchMessageSourceWithAuthenticatedOAuthRetry(
        folderID: Folder.ID,
        uid: Int
    ) async throws -> IMAPMessageSource {
        guard let operation = fetchMessageSourceOperation else {
            throw MailBackendError.notSupported(capabilities)
        }
        return try await withAuthenticatedOAuthRetry { credential in
            try await operation(self.configuration, credential, folderID, uid)
        }
    }

    private func fetchMessagePartWithAuthenticatedOAuthRetry(
        folderID: Folder.ID,
        uid: Int,
        section: String,
        transferEncoding: String
    ) async throws -> Data {
        guard let operation = fetchMessagePartOperation else {
            throw MailBackendError.notSupported(capabilities)
        }
        return try await withAuthenticatedOAuthRetry { credential in
            try await operation(
                self.configuration,
                credential,
                folderID,
                uid,
                section,
                transferEncoding
            )
        }
    }

    private func condstoreSyncWithAuthenticatedOAuthRetry(
        folderID: Folder.ID,
        sinceModSeq: UInt64?
    ) async throws -> (
        highestModSeq: UInt64?,
        uidValidity: Int?,
        changes: [(uid: Int, flags: [String])]
    ) {
        guard let operation = condstoreSyncOperation else {
            throw MailBackendError.notSupported(capabilities)
        }
        return try await withAuthenticatedOAuthRetry { credential in
            try await operation(self.configuration, credential, folderID, sinceModSeq)
        }
    }

    static func shouldUseCacheFallback(for error: any Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if case MailBackendError.authenticationRequired = error {
            return false
        }
        if let refreshError = error as? OAuthRefreshError {
            return !refreshError.isPermanent
        }
        if case MailBackendError.backendSpecific = error {
            return false
        }
        if let imapError = error as? IMAPClientError {
            switch imapError {
            case .authenticationFailed, .invalidServerKind:
                return false
            case .connectionLimitExceeded,
                 .unsupportedTLSMode,
                 .unsupportedSearchCriterion,
                 .connectionRejected,
                 .commandNotSupported,
                 .commandFailed,
                 .malformedResponse,
                 .transport,
                 .serverBye,
                 .idleNotSupported:
                return true
            }
        }
        if let smtpError = error as? SMTPClientError {
            switch smtpError {
            case .authenticationFailed, .authenticationUnavailable,
                 .invalidServerKind, .unsupportedAuthentication,
                 .deliveryOutcomeUnknown:
                return false
            case .unsupportedTLSMode, .connectionRejected, .commandFailed,
                 .malformedResponse, .transport:
                return true
            }
        }
        return true
    }

    /// Drops cancellation noise so superseded refreshes don't mark sync degraded.
    private static func sanitizedSyncErrorDescription(_ description: String?) -> String? {
        guard let description else { return nil }
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let compact = trimmed.lowercased()
        if compact.contains("cancellationerror") || compact == "sync was cancelled." {
            return nil
        }
        return trimmed
    }

    private static func userFacingDescription(for error: any Error) -> String {
        if error is CancellationError {
            return "Sync was cancelled."
        }
        if let backendError = error as? MailBackendError {
            if case .network(let underlying) = backendError {
                return underlying
            }
            return backendError.localizedDescription
        }
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        let description = error.localizedDescription
        return description.isEmpty ? String(localized: "Unknown error.", bundle: .module) : description
    }

    private static func mutationConflictDescription(
        for conflicts: [MutationConflict]
    ) -> String {
        let sorted = conflicts.sorted { $0.detectedAt > $1.detectedAt }
        let firstMessage = sorted.first?.message
            ?? String(localized: "Review the queued mail action.", bundle: .module)
        if conflicts.count == 1 {
            return String(
                localized: "1 queued mail change needs review: \(firstMessage)",
                bundle: .module
            )
        }
        return String(
            localized: "\(conflicts.count) queued mail changes needs review: \(firstMessage)",
            bundle: .module
        )
    }

    private static func idleUnsupportedKey(accountID: String) -> String {
        "brev.imap.idle-unsupported.\(accountID)"
    }

    /// Watches one mailbox at a time to stay within provider connection budgets.
    /// Preference order: currently viewed folder, otherwise INBOX. Switching
    /// folders cancels the previous watcher before starting the next one so
    /// IDLE never holds two simultaneous IMAP sessions for one account.
    private func watchInboxAndActiveFolderForIdleEvents(
        using idleEventsOperation: @escaping IdleEventOperation
    ) async {
        await refreshActiveFolderForIdleEvents(using: idleEventsOperation)
    }

    private func refreshActiveFolderForIdleEvents(
        using idleEventsOperation: @escaping IdleEventOperation
    ) async {
        var currentFolderID: Folder.ID?
        var worker: Task<Void, Never>?
        let inboxFolder = try? await state.inboxFolder()

        func watch(_ folder: Folder) {
            worker?.cancel()
            currentFolderID = folder.id
            worker = Task {
                await refreshFolderForIdleEvents(folder, using: idleEventsOperation)
            }
        }

        if let folder = try? await state.idleFolder() {
            watch(folder)
        } else if let inboxFolder {
            watch(inboxFolder)
        }

        for await folderID in state.idleFolderStream() {
            guard !Task.isCancelled else { break }
            guard folderID != currentFolderID else { continue }
            if let folder = await state.folder(id: folderID) {
                watch(folder)
                continue
            }
            if let inboxFolder, currentFolderID != inboxFolder.id {
                watch(inboxFolder)
            }
        }

        worker?.cancel()
    }

    private func refreshFolderForIdleEvents(
        _ folder: Folder,
        using idleEventsOperation: @escaping IdleEventOperation
    ) async {
        var retryDelayNanoseconds = Self.initialIDLEResubscribeDelayNanoseconds
        // Persist across restarts so servers that don't support IDLE skip
        // the initial retry delay on every app launch.
        var usePolling = UserDefaults.standard.bool(
            forKey: Self.idleUnsupportedKey(accountID: account.id)
        )
        // A rejected XOAUTH2 token may require one refresh before the IDLE
        // lease is recreated. Keep this guard set until a healthy stream has
        // delivered an event so a failing refresh cannot turn into a tight
        // reconnect loop.
        var didRefreshOAuthCredentialSinceHealthyStream = false

        idleLoop: while !Task.isCancelled {
            if usePolling {
                try? await Task.sleep(nanoseconds: Self.idlePollIntervalNanoseconds)
                guard !Task.isCancelled else { return }
                _ = try? await refreshConnectedFolderFirstPage(folder)
                continue
            }

            let attemptedCredential = credential
            let stream = await idleEventsOperation(configuration, attemptedCredential, folder.id)
            var receivedEvent = false
            var streamFailed = false
            do {
                for try await event in stream {
                    guard !Task.isCancelled else { return }
                    receivedEvent = true
                    // The refreshed credential has proven usable. Permit a
                    // later expiry to perform one more bounded refresh.
                    didRefreshOAuthCredentialSinceHealthyStream = false
                    switch event {
                    case .exists, .recent:
                        try await refreshConnectedFolderFirstPage(folder)
                    case .expunged, .flagsChanged:
                        try await refreshConnectedFolderFirstPage(folder)
                    }
                }
            } catch let imapError as IMAPClientError {
                guard !Task.isCancelled else { return }
                if case .authenticationFailed = imapError,
                   attemptedCredential.authentication == .xoauth2,
                   !didRefreshOAuthCredentialSinceHealthyStream,
                   let refreshOAuthCredentialOperation {
                    didRefreshOAuthCredentialSinceHealthyStream = true
                    do {
                        let refreshedCredential = try await oauthCredentialRefreshCoordinator.run {
                            let latestCredential = self.credential
                            guard latestCredential == attemptedCredential else {
                                return latestCredential
                            }
                            let refreshedCredential = try await refreshOAuthCredentialOperation(
                                self.account.id,
                                self.configuration,
                                latestCredential
                            )
                            self.replaceCredentialForReconnect(refreshedCredential)
                            return refreshedCredential
                        }
                        self.replaceCredentialForReconnect(refreshedCredential)
                        // Restart IDLE immediately with the persisted token.
                        // The next authentication failure follows the normal
                        // bounded backoff path because the guard above stays
                        // set until a healthy stream emits an event.
                        retryDelayNanoseconds = Self.initialIDLEResubscribeDelayNanoseconds
                        continue idleLoop
                    } catch {
                        streamFailed = true
                        await state.recordBackgroundSyncFailure(Self.userFacingDescription(for: error))
                    }
                }
                if case .idleNotSupported = imapError {
                    // Server rejected IDLE — persist so the next launch skips
                    // the retry delay and falls back to polling immediately.
                    UserDefaults.standard.set(
                        true,
                        forKey: Self.idleUnsupportedKey(accountID: account.id)
                    )
                    usePolling = true
                    continue
                }
                streamFailed = true
                await state.recordBackgroundSyncFailure(Self.userFacingDescription(for: imapError))
            } catch {
                guard !Task.isCancelled else { return }
                streamFailed = true
                await state.recordBackgroundSyncFailure(Self.userFacingDescription(for: error))
            }
            if !receivedEvent, !streamFailed, !Task.isCancelled {
                await state.recordBackgroundSyncFailure(
                    "IMAP IDLE stream ended before receiving mailbox changes."
                )
            }
            let currentDelayNanoseconds = receivedEvent
                ? Self.initialIDLEResubscribeDelayNanoseconds
                : retryDelayNanoseconds
            retryDelayNanoseconds = receivedEvent
                ? Self.initialIDLEResubscribeDelayNanoseconds
                : Self.nextIDLERetryDelay(after: retryDelayNanoseconds)
            try? await Task.sleep(nanoseconds: currentDelayNanoseconds)
        }
    }

    private static func nextIDLERetryDelay(after delayNanoseconds: UInt64) -> UInt64 {
        if delayNanoseconds >= maximumIDLEResubscribeDelayNanoseconds / 2 {
            return maximumIDLEResubscribeDelayNanoseconds
        }
        return min(
            delayNanoseconds * 2,
            maximumIDLEResubscribeDelayNanoseconds
        )
    }

    private func searchHeaders(
        from listings: [IMAPMessageListing],
        folderID: Folder.ID,
        attachmentFilter: Bool?
    ) async throws -> [MessageHeader] {
        guard let attachmentFilter else {
            return listings.map { Self.header(from: $0, folderID: folderID) }
        }

        var headers: [MessageHeader] = []
        for listing in listings {
            try Task.checkCancellation()
            let messageID = "\(folderID):\(listing.uid)"
            let source = try await loadMessageSource(
                messageID: messageID,
                folderID: folderID,
                uid: listing.uid
            )
            let hasAttachments = !IMAPMessageBodyParser().parse(
                messageID: messageID,
                rawMessage: source.rawMessage
            ).attachments.isEmpty
            if hasAttachments == attachmentFilter {
                headers.append(Self.header(
                    from: listing,
                    folderID: folderID,
                    hasAttachments: hasAttachments
                ))
            }
        }
        return headers
    }

    private func searchAttachmentHeaders(
        folderID: Folder.ID,
        query: SearchQuery,
        operation: @escaping MessageSearchPageOperation
    ) async throws -> [MessageHeader] {
        guard let attachmentFilter = query.hasAttachments else { return [] }

        var pageToken: String?
        var visitedPageTokens = Set<String>()
        var headers: [MessageHeader] = []
        while true {
            try Task.checkCancellation()
            let tokenKey = pageToken ?? "<initial>"
            guard visitedPageTokens.insert(tokenKey).inserted else {
                throw MailBackendError.backendSpecific(
                    message: "IMAP attachment search did not advance the page cursor."
                )
            }

            let page = try await searchMessagePageWithAuthenticatedOAuthRetry(
                operation,
                folderID: folderID,
                query: Self.serverSearchQuery(from: query),
                pageToken: pageToken,
                limit: Self.attachmentSearchPageSize
            )
            try await headers.append(contentsOf: searchHeaders(
                from: page.messages,
                folderID: folderID,
                attachmentFilter: attachmentFilter
            ))

            guard let nextPageToken = page.nextPageToken else { break }
            guard nextPageToken != pageToken else {
                throw MailBackendError.backendSpecific(
                    message: "IMAP attachment search did not advance the page cursor."
                )
            }
            pageToken = nextPageToken
        }
        return headers
    }

    private static func recipientEmails(from draft: Draft) -> [String] {
        (draft.to + draft.cc + draft.bcc)
            .map { $0.email.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func setSystemFlag(
        _ flag: IMAPSystemFlag,
        isEnabled: Bool,
        for messageIDs: [MessageHeader.ID]
    ) async throws {
        try await state.requireConnected()
        guard !messageIDs.isEmpty else { return }
        guard let setMessageFlagOperation else {
            throw MailBackendError.notSupported(capabilities)
        }

        for group in try Self.messageReferencesByFolder(from: messageIDs) {
            try await withAuthenticatedOAuthRetry { credential in
                try await setMessageFlagOperation(
                    self.configuration,
                    credential,
                    group.folderID,
                    group.uids,
                    flag,
                    isEnabled
                )
            }
            await updateCachedHeaders(
                folderID: group.folderID,
                uids: group.uids,
                flag: flag,
                isEnabled: isEnabled
            )
            await state.emit(.messagesUpdated(
                folderID: group.folderID,
                messageIDs: Self.messageIDs(from: group)
            ))
        }
    }

    // MARK: - Gmail labels (X-GM-EXT-1)

    /// Records that the server advertised `X-GM-EXT-1` so `.labels` is
    /// advertised from now on; persists it in the folder snapshot when it
    /// changes so cache-first startup can restore it.
    private func noteGmailLabelSupport() {
        gmailLabelsLock.withLock { gmailLabelsDetected = true }
    }

    private func recordGmailLabelSupport(from page: IMAPMessageListingPage) async {
        guard page.supportsGmailLabels else { return }
        let wasDetected = gmailLabelsLock.withLock { () -> Bool in
            let previous = gmailLabelsDetected
            gmailLabelsDetected = true
            return previous
        }
        guard !wasDetected,
              var snapshot = await folderCache?.snapshot(accountID: account.id),
              !snapshot.supportsGmailLabels
        else {
            return
        }
        snapshot.supportsGmailLabels = true
        await folderCache?.setSnapshot(snapshot, accountID: account.id)
    }

    public func setLabels(
        _ labels: [String],
        isEnabled: Bool,
        for messageIDs: [MessageHeader.ID],
        sourceID: MailSourceID?
    ) async throws {
        try validateMutationSource(sourceID)
        do {
            try await performSetLabels(labels, isEnabled: isEnabled, for: messageIDs)
        } catch {
            if try await enqueueOfflineMutation(
                PendingMutation(
                    kind: .setLabels(labels, isEnabled: isEnabled),
                    sourceID: sourceID,
                    messageIDs: messageIDs
                ),
                for: error
            ) {
                return
            }
            throw error
        }
    }

    private func performSetLabels(
        _ labels: [String],
        isEnabled: Bool,
        for messageIDs: [MessageHeader.ID]
    ) async throws {
        try await state.requireConnected()
        guard !messageIDs.isEmpty, !labels.isEmpty else { return }
        guard let setMessageLabelsOperation, capabilities.contains(.labels) else {
            throw MailBackendError.notSupported(.labels)
        }

        for group in try Self.messageReferencesByFolder(from: messageIDs) {
            try await withAuthenticatedOAuthRetry { credential in
                try await setMessageLabelsOperation(
                    self.configuration,
                    credential,
                    group.folderID,
                    group.uids,
                    labels,
                    isEnabled
                )
            }
            await updateCachedHeaderLabels(
                folderID: group.folderID,
                uids: group.uids,
                labels: labels,
                isEnabled: isEnabled
            )
            await state.emit(.messagesUpdated(
                folderID: group.folderID,
                messageIDs: Self.messageIDs(from: group)
            ))
        }
    }

    private func updateCachedHeaderLabels(
        folderID: Folder.ID,
        uids: [Int],
        labels: [String],
        isEnabled: Bool
    ) async {
        guard var snapshot = await cachedHeaderSnapshot(folderID: folderID) else { return }
        let targetIDs = Set(Self.messageIDs(folderID: folderID, uids: uids))
        snapshot.headers = snapshot.headers.map { header in
            guard targetIDs.contains(header.id) else { return header }
            var updated = header
            if isEnabled {
                updated.labels += labels.filter { !updated.labels.contains($0) }
            } else {
                updated.labels.removeAll { labels.contains($0) }
            }
            return updated
        }
        await headerCache?.setSnapshot(snapshot, accountID: account.id, folderID: folderID)
        await localSearchIndex?.storeHeaders(
            snapshot.headers.filter { targetIDs.contains($0.id) },
            account: account
        )
    }

    private func performSetJunk(
        _ isJunk: Bool,
        for messageIDs: [MessageHeader.ID]
    ) async throws {
        try await state.requireConnected()
        guard !messageIDs.isEmpty else { return }
        guard let setMessageKeywordOperation else {
            throw MailBackendError.notSupported(.junkAPI)
        }

        for group in try Self.messageReferencesByFolder(from: messageIDs) {
            try await withAuthenticatedOAuthRetry { credential in
                try await setMessageKeywordOperation(
                    self.configuration,
                    credential,
                    group.folderID,
                    group.uids,
                    .junk,
                    isJunk
                )
            }
            try await withAuthenticatedOAuthRetry { credential in
                try await setMessageKeywordOperation(
                    self.configuration,
                    credential,
                    group.folderID,
                    group.uids,
                    .notJunk,
                    !isJunk
                )
            }
            await state.emit(.messagesUpdated(
                folderID: group.folderID,
                messageIDs: Self.messageIDs(from: group)
            ))
        }

        guard moveMessagesOperation != nil,
              let destination = try await state.requireConnectedFolders().first(where: {
                  $0.role == (isJunk ? .spam : .inbox)
              }) else { return }
        try await performMove(messageIDs: messageIDs, toFolderID: destination.id)
    }

    private func stagedAttachments(for attachmentIDs: [String]) async throws -> [MIMEMessageAttachment] {
        try await withThrowingTaskGroup(of: MIMEMessageAttachment.self) { group in
            for attachmentID in attachmentIDs {
                group.addTask {
                    if let attachment = await self.state.attachment(for: attachmentID) {
                        return MIMEMessageAttachment(
                            id: attachment.id,
                            filename: attachment.filename,
                            mimeType: attachment.mimeType,
                            data: attachment.data,
                            isInline: attachment.isInline,
                            contentID: attachment.contentID
                        )
                    }
                    if let attachment = await self.draftStagingStore?.attachment(
                        accountID: self.account.id,
                        attachmentID: attachmentID
                    ) {
                        return MIMEMessageAttachment(
                            id: attachment.id,
                            filename: attachment.filename,
                            mimeType: attachment.mimeType,
                            data: attachment.data,
                            isInline: attachment.isInline,
                            contentID: attachment.contentID
                        )
                    }
                    throw MailBackendError.notFound(id: attachmentID)
                }
            }

            var attachments: [MIMEMessageAttachment] = []
            for try await attachment in group {
                attachments.append(attachment)
            }
            return attachments.sorted { lhs, rhs in
                guard let lhsIndex = attachmentIDs.firstIndex(of: lhs.id),
                      let rhsIndex = attachmentIDs.firstIndex(of: rhs.id)
                else {
                    return lhs.id < rhs.id
                }
                return lhsIndex < rhsIndex
            }
        }
    }

    /// Fetches the first page of the IMAP Drafts folder on connect and stages
    /// any remote drafts not already known to this session. Body is empty here;
    /// it is fetched lazily when the user opens the draft.
    /// Starts non-critical post-connect work after the UI has a usable first frame.
    /// Safe to call repeatedly; work is tracked and cancelled on disconnect.
    public func startDeferredStartupWork() {
        let shouldStart = deferredStartupLock.withLock { () -> Bool in
            guard !didStartDeferredStartupWork else { return false }
            didStartDeferredStartupWork = true
            return true
        }
        guard shouldStart else { return }
        trackBackgroundWork { await self.startDeferredStartupWorkWhenRemoteIsAvailable() }
    }

    private func startDeferredStartupWorkWhenRemoteIsAvailable() async {
        for await remoteAvailable in state.remoteAvailabilityStream() {
            guard !Task.isCancelled else { return }
            guard remoteAvailable else { continue }
            startScheduledSendPoller()
            scheduleRemoteDraftDiscovery()
            // A reconnect retries failed sends immediately (force), bypassing the
            // in-session backoff that throttles the 30s poller.
            trackBackgroundWork { await self.deliverDueScheduledDrafts(forceRetry: true) }
            return
        }
    }

    private func scheduleRemoteDraftDiscovery() {
        let id = UUID()
        let task = Task(priority: .utility) { [weak self] in
            defer { self?.finishBackgroundWork(id: id) }
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            await loadRemoteDrafts()
            finishRemoteDraftDiscovery(id: id)
        }
        let previous = remoteDraftDiscoveryLock.withLock { () -> Task<Void, Never>? in
            guard foregroundIMAPReadCount == 0 else {
                hasPendingRemoteDraftDiscoveryRetry = true
                return nil
            }
            let previous = remoteDraftDiscoveryTask?.task
            remoteDraftDiscoveryTask = (id: id, task: task)
            return previous
        }
        guard remoteDraftDiscoveryLock.withLock({ remoteDraftDiscoveryTask?.id == id }) else {
            task.cancel()
            return
        }
        previous?.cancel()
        backgroundWorkLock.withLock { backgroundWorkTasks[id] = task }
    }

    private func finishRemoteDraftDiscovery(id: UUID) {
        remoteDraftDiscoveryLock.withLock {
            guard remoteDraftDiscoveryTask?.id == id else { return }
            remoteDraftDiscoveryTask = nil
        }
    }

    private func cancelRemoteDraftDiscovery() {
        let task = remoteDraftDiscoveryLock.withLock { () -> Task<Void, Never>? in
            let task = remoteDraftDiscoveryTask?.task
            remoteDraftDiscoveryTask = nil
            hasPendingRemoteDraftDiscoveryRetry = false
            foregroundIMAPReadCount = 0
            return task
        }
        task?.cancel()
    }

    private func loadRemoteDrafts() async {
        guard listMessagesOperation != nil,
              let draftsFolder = try? await state.draftsFolder(),
              !Task.isCancelled
        else { return }

        guard let page = try? await listMessagesWithAuthenticatedOAuthRetry(
            folderID: draftsFolder.id,
            pageToken: nil,
            limit: 50
        ), !Task.isCancelled else { return }

        for listing in page.messages {
            guard !Task.isCancelled else { return }
            let remoteID = "\(draftsFolder.id):\(listing.uid)"
            let local = await state.draft(for: remoteID)
            let metadata: DraftSyncMetadata? = if let local {
                await state.draftSyncMetadata(for: local.id)
            } else {
                nil
            }
            // A clean local draft already contains the best available body.
            // Reconcile it lazily when the user opens the draft; fetching every
            // such remote body here is startup contention without user value.
            guard Self.requiresRemoteDraftBodyReconciliation(metadata) || local == nil else { continue }
            // Discovery needs listing metadata only. Eagerly fetching every
            // remote draft body competes with the reader on the sole command
            // session. Only locally edited drafts need body-aware conflict
            // reconciliation before the user opens them.
            let htmlBody: String
            do {
                htmlBody = try await remoteDraftHTMLBody(
                    remoteID: remoteID,
                    shouldFetch: Self.requiresRemoteDraftBodyReconciliation(metadata)
                )
            } catch is CancellationError {
                return
            } catch {
                htmlBody = ""
            }
            guard !Task.isCancelled else { return }
            let remoteDraft = Draft(
                id: "remote-\(listing.uid)-\(draftsFolder.id)",
                remoteID: remoteID,
                to: listing.to,
                cc: listing.cc,
                bcc: listing.bcc,
                subject: listing.subject,
                htmlBody: htmlBody
            )
            if let local {
                let metadata = metadata ?? DraftSyncMetadata()
                switch DraftReconciliation.reconcile(
                    local: local,
                    remote: remoteDraft,
                    metadata: metadata
                ) {
                case .acceptRemote:
                    let staged = await state.stageDraft(remoteDraft)
                    let fingerprint = DraftContentFingerprint.fingerprint(for: staged)
                    await state.markDraftSynced(staged, fingerprint: fingerprint)
                    await draftStagingStore?.setDraft(staged, accountID: account.id)
                case .keepLocal:
                    continue
                case .createConflict:
                    let conflict = await state.stageConflictDraft(local: local, remote: remoteDraft)
                    await draftStagingStore?.setDraft(conflict, accountID: account.id)
                }
            } else {
                let staged = await state.stageDraft(remoteDraft)
                let fingerprint = DraftContentFingerprint.fingerprint(for: staged)
                await state.markDraftSynced(staged, fingerprint: fingerprint)
                await draftStagingStore?.setDraft(staged, accountID: account.id)
            }
        }
    }

    private func remoteDraftHTMLBody(
        remoteID: Draft.ID,
        shouldFetch: Bool
    ) async throws -> String {
        guard shouldFetch else {
            return ""
        }
        let messageBody = try await messageBody(
            for: remoteID,
            prioritizesForegroundIMAPRead: false
        )
        return messageBody.html ?? Self.htmlFromPlainText(messageBody.plainText)
    }

    static func requiresRemoteDraftBodyReconciliation(_ metadata: DraftSyncMetadata?) -> Bool {
        metadata?.isDirty == true
    }

    private static func htmlFromPlainText(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "" }
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private func removePersistedDraft(_ draft: Draft) async {
        await draftStagingStore?.removeDraft(accountID: account.id, draftID: draft.id)
        if let remoteID = draft.remoteID {
            await draftStagingStore?.removeDraft(accountID: account.id, draftID: remoteID)
        }
    }

    private func deleteRemoteDraftIfPossible(_ draftID: Draft.ID?) async -> SendResultWarning? {
        do {
            try await deleteRemoteDraft(draftID)
            return nil
        } catch {
            return .remoteDraftCleanupFailed
        }
    }

    private func deleteRemoteDraft(_ draftID: Draft.ID?) async throws {
        guard let draftID = await remoteDraftID(for: draftID),
              let reference = try? Self.messageReference(from: draftID)
        else {
            return
        }
        guard let permanentlyDeleteMessagesOperation else {
            throw MailBackendError.notSupported(capabilities)
        }
        try await withAuthenticatedOAuthRetry { credential in
            try await permanentlyDeleteMessagesOperation(
                self.configuration,
                credential,
                reference.folderID,
                [reference.uid]
            )
        }
        await removeCachedMessageSources(folderID: reference.folderID, uids: [reference.uid])
        await removeCachedHeaders(folderID: reference.folderID, uids: [reference.uid])
        await state.emit(.messagesRemoved(
            folderID: reference.folderID,
            messageIDs: [draftID]
        ))
    }

    private func remoteDraftID(for draftID: Draft.ID?) async -> Draft.ID? {
        guard let draftID else { return nil }
        if (try? Self.messageReference(from: draftID)) != nil {
            return draftID
        }
        if let stagedDraft = await state.draft(for: draftID),
           let remoteID = stagedDraft.remoteID {
            return remoteID
        }
        if let persistedDraft = await draftStagingStore?.draft(
            accountID: account.id,
            draftID: draftID
        ),
            let remoteID = persistedDraft.remoteID {
            return remoteID
        }
        return nil
    }

    private func appendSentCopyIfPossible(_ messageData: Data) async -> (uid: Int?, warning: SendResultWarning?) {
        // No append operation means sent-copy placement is not this backend's
        // responsibility (e.g. a provider that files sent mail server-side), so
        // skipping is intentional and silent.
        guard let appendSentMessageOperation else { return (nil, nil) }
        // We are expected to file a Sent copy but couldn't resolve a Sent folder.
        // Surface it as a warning rather than silently dropping the copy — a
        // missing Sent mailbox is exactly the kind of failure that otherwise
        // looks like "the message vanished from Sent."
        guard let sentFolder = try? await state.sentFolder() else {
            return (nil, .sentCopyAppendFailed)
        }
        let configuration = configuration
        let folderID = sentFolder.id
        do {
            // The message is already delivered (SMTP accepted it). Filing the
            // Sent copy is a best-effort follow-up, so bound it with a timeout —
            // a slow or stalled APPEND must never hang the composer's "Send".
            let uid = try await Self.withTimeout(seconds: Self.sentCopyAppendTimeout) {
                try await self.withAuthenticatedOAuthRetry { credential in
                    try await appendSentMessageOperation(
                        configuration,
                        credential,
                        folderID,
                        messageData,
                        [.seen]
                    )
                }
            }
            return (uid, nil)
        } catch {
            // Failing here could invite duplicate delivery on retry, so surface a
            // warning rather than failing the (already-completed) send.
            return (nil, .sentCopyAppendFailed)
        }
    }

    private static let sentCopyAppendTimeout: Double = 20

    /// Runs `operation`, returning its result, but throws `SendOperationTimeout`
    /// if it does not finish within `seconds`. Used to keep best-effort post-send
    /// steps from hanging the send indefinitely.
    private static func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw SendOperationTimeout()
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private struct SendOperationTimeout: Error {}

    private static func sendResult(
        _ result: SendResult,
        appending warning: SendResultWarning?
    ) -> SendResult {
        guard let warning else { return result }
        return sendResult(result, appending: [warning])
    }

    private static func sendResult(
        _ result: SendResult,
        appending warnings: [SendResultWarning]
    ) -> SendResult {
        guard !warnings.isEmpty else { return result }
        return SendResult(
            sentMessageID: result.sentMessageID,
            scheduledFor: result.scheduledFor,
            warnings: result.warnings + warnings
        )
    }

    private static func messageReference(
        from messageID: MessageHeader.ID
    ) throws -> (folderID: Folder.ID, uid: Int) {
        guard let separator = messageID.lastIndex(of: ":") else {
            throw MailBackendError.notFound(id: messageID)
        }
        let folderID = String(messageID[..<separator])
        let rawUID = messageID[messageID.index(after: separator)...]
        guard let uid = Int(rawUID), !folderID.isEmpty else {
            throw MailBackendError.notFound(id: messageID)
        }
        return (folderID, uid)
    }

    private static func messageReferencesByFolder(
        from messageIDs: [MessageHeader.ID]
    ) throws -> [(folderID: Folder.ID, uids: [Int])] {
        var groups: [(folderID: Folder.ID, uids: [Int])] = []
        var groupIndexesByFolderID: [Folder.ID: Int] = [:]

        for messageID in messageIDs {
            let reference = try messageReference(from: messageID)
            if let index = groupIndexesByFolderID[reference.folderID] {
                groups[index].uids.append(reference.uid)
            } else {
                groupIndexesByFolderID[reference.folderID] = groups.count
                groups.append((folderID: reference.folderID, uids: [reference.uid]))
            }
        }
        return groups
    }

    private static func messageIDs(from group: (folderID: Folder.ID, uids: [Int])) -> [MessageHeader.ID] {
        messageIDs(folderID: group.folderID, uids: group.uids)
    }

    private static func messageIDs(folderID: Folder.ID, uids: [Int]) -> [MessageHeader.ID] {
        uids.map { "\(folderID):\($0)" }
    }

    private static func attachmentReference(
        from attachment: Attachment
    ) throws -> (messageID: MessageHeader.ID, folderID: Folder.ID, uid: Int, attachmentIndex: Int) {
        guard let resource = attachment.resource,
              resource.hasPrefix("imap-source:")
        else {
            throw MailBackendError.notFound(id: attachment.id)
        }
        let payload = String(resource.dropFirst("imap-source:".count))
        guard let separator = payload.lastIndex(of: ":"),
              let attachmentIndex = Int(payload[payload.index(after: separator)...])
        else {
            throw MailBackendError.notFound(id: attachment.id)
        }
        let messageID = String(payload[..<separator])
        let messageReference = try messageReference(from: messageID)
        return (
            messageID,
            messageReference.folderID,
            messageReference.uid,
            attachmentIndex
        )
    }
}

private struct IMAPManageSieveRuleSyncService: ManageSieveRuleSyncing {
    let accountID: BrevAccount.ID
    let configuration: IMAPAccountConfiguration
    let credential: MailAccountCredential
    let syncOperation: IMAPSMTPBackend.ManageSieveRuleSyncOperation

    func syncLocalRulesToServer(
        _ rules: [ServerRule],
        sourceID: MailSourceID,
        scriptName: String
    ) async throws -> SieveScriptPlan {
        guard sourceID.accountID == accountID else {
            throw MailBackendError.notFound(id: sourceID.accountID)
        }
        guard configuration.manageSieve != nil else {
            throw MailBackendError.notSupported(.manageSieve)
        }
        return try await syncOperation(
            configuration,
            credential,
            rules,
            scriptName
        )
    }
}

/// Serializes credential refreshes for one IMAP backend instance. The account
/// provisioning layer also coordinates token-store refreshes globally; this
/// local gate prevents already-connected mutations from racing before they
/// reach that shared refresher.
private actor IMAPOAuthCredentialRefreshCoordinator {
    private var inFlight: Task<MailAccountCredential, Error>?

    func run(
        _ operation: @escaping @Sendable () async throws -> MailAccountCredential
    ) async throws -> MailAccountCredential {
        if let inFlight {
            return try await inFlight.value
        }

        let task = Task { try await operation() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
