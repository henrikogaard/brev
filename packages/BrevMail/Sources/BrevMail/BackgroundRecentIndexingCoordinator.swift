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
import BrevSettings
import Foundation
import Observation

public extension Notification.Name {
    /// Posted when foreground mailbox sync or live arrival stores new message headers
    /// so opt-in background indexing can catch up without requiring background-mail mode.
    static let brevForegroundMailDidSync = Notification.Name(
        "eu.brevmail.mail.foregroundDidSync"
    )
}

/// Point-in-time snapshot of device network and power conditions sampled before
/// every background indexing unit of work.
public struct BackgroundIndexingEnvironmentSnapshot: Equatable, Sendable {
    /// Whether the device currently has network reachability.
    public var isOnline: Bool
    /// Whether the active network path is marked expensive (for example cellular or hotspot).
    public var isExpensiveNetwork: Bool
    /// Whether the active network path is constrained (Low Data Mode).
    public var isConstrainedNetwork: Bool
    /// Whether system Low Power Mode / battery saver is active.
    public var isLowPowerModeEnabled: Bool

    /// Creates an environment snapshot.
    public init(
        isOnline: Bool = true,
        isExpensiveNetwork: Bool = false,
        isConstrainedNetwork: Bool = false,
        isLowPowerModeEnabled: Bool = false
    ) {
        self.isOnline = isOnline
        self.isExpensiveNetwork = isExpensiveNetwork
        self.isConstrainedNetwork = isConstrainedNetwork
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
    }

    /// Returns the pause reason if conditions disallow indexing under `settings`, or `nil` when eligible.
    public func pauseReason(for settings: BackgroundIndexingSettings) -> BackgroundIndexingPauseReason? {
        guard isOnline else { return .offline }
        if settings.requireUnmeteredNetworkAndPower {
            if isLowPowerModeEnabled { return .lowPowerMode }
            if isExpensiveNetwork || isConstrainedNetwork { return .meteredNetwork }
        }
        return nil
    }
}

/// Throttled, network- and power-aware scheduler for opt-in background recent-mail
/// and attachment indexing.
///
/// Hard privacy & safety guarantees:
/// - Strictly performs ZERO work and ZERO network calls while `settings.isEnabled == false`.
/// - Pauses cleanly on offline, cellular/expensive/constrained networks, or Low Power Mode
///   when `settings.requireUnmeteredNetworkAndPower == true`.
/// - Excludes Trash and Spam folders — and multi-label messages carrying Trash or Spam
///   alongside another label (e.g. Gmail) — from automatic backfill.
/// - Uses `BackgroundBodyIndexing` when available so IMAP fetches run at background priority
///   (never preempting foreground refreshes or draft discovery), persist searchable body text
///   into local FTS, and skip unbounded raw-source fallback above `maxAttachmentBytes`.
/// - Never mutates read/unread flags.
/// - Tracks attachment completion per attachment ID so mid-message pauses preserve completed
///   attachments without skipping remaining ones, and retries transient download/timeout/FTS
///   failures on later passes while deterministically skipping inline, oversized, or unsupported files.
/// - Reconciles stored attachment progress against live FTS index IDs so removing the
///   attachment index cleanly re-enables indexing.
@MainActor
@Observable
public final class BackgroundRecentIndexingCoordinator {
    /// Current runtime state of the background indexer.
    public private(set) var state: BackgroundIndexingState = .idle
    /// Count of recent messages indexed during the current lifecycle.
    public private(set) var indexedMessagesCount = 0
    /// Count of attachments whose text was indexed during the current lifecycle.
    public private(set) var indexedAttachmentsCount = 0
    /// Remaining eligible messages waiting to be indexed in the active window.
    public private(set) var pendingCount = 0
    /// Most recent successful indexing timestamp.
    public private(set) var lastIndexedAt: Date?

    /// Observable bridge consumed by Settings UI without coupling `BrevSettings` to `BrevMail`.
    public let statusModel: BackgroundIndexingStatusModel

    /// Supplies the currently connected backends when a pass runs.
    public var backendsProvider: @MainActor () -> [any MailBackend]

    /// Supplies live network and power conditions; mutable so the app shell can attach its reachability monitor.
    public var environmentProvider: @MainActor () -> BackgroundIndexingEnvironmentSnapshot

    private let settingsProvider: @MainActor () -> BackgroundIndexingSettings
    private let progressStore: BackgroundIndexingProgressStore
    private let now: @Sendable () -> Date
    private let maxBatchSize: Int
    private let maxAttachmentBytes: Int
    private let pacingDelay: Duration
    private let batchInterval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    private var activeTask: Task<Void, Never>?
    private var activeGeneration = 0
    private var isUserPaused = false
    private var needsFollowUpSweep = false

    private static let excludedCanonicalLabels: Set<String> = [
        "trash",
        "spam",
        "\\trash",
        "\\junk",
        "\\spam",
        "[gmail]/trash",
        "[gmail]/spam"
    ]

    /// Creates a background recent-mail indexing coordinator.
    /// - Parameters:
    ///   - backendsProvider: Returns currently connected mail backends.
    ///   - settingsProvider: Reads the current `BackgroundIndexingSettings`.
    ///   - environmentProvider: Samples live network and power conditions.
    ///   - progressStore: Persists per-account indexed message and attachment IDs.
    ///   - now: Supplies the current date for window filtering and timestamps (injectable for tests).
    ///   - maxBatchSize: Maximum number of messages processed per throttled batch before pausing briefly.
    ///   - maxAttachmentBytes: Maximum per-attachment byte size (and fallback raw-source cap) for background indexing.
    ///   - pacingDelay: Polite yield delay between message fetches inside a batch.
    ///   - batchInterval: Polite breather delay between consecutive throttled batches when a backlog remains.
    ///   - sleep: Async sleep implementation (injectable for deterministic tests).
    public init(
        backendsProvider: @escaping @MainActor () -> [any MailBackend] = { [] },
        settingsProvider: @escaping @MainActor () -> BackgroundIndexingSettings = {
            BackgroundIndexingSettings.load()
        },
        environmentProvider: @escaping @MainActor () -> BackgroundIndexingEnvironmentSnapshot = {
            BackgroundIndexingEnvironmentSnapshot(
                isOnline: true,
                isExpensiveNetwork: false,
                isConstrainedNetwork: false,
                isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
            )
        },
        progressStore: BackgroundIndexingProgressStore = .shared,
        now: @escaping @Sendable () -> Date = { Date() },
        maxBatchSize: Int = 40,
        maxAttachmentBytes: Int = BackgroundIndexingSettings.defaultMaxAttachmentBytes,
        pacingDelay: Duration = .milliseconds(150),
        batchInterval: Duration = .milliseconds(500),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.backendsProvider = backendsProvider
        self.settingsProvider = settingsProvider
        self.environmentProvider = environmentProvider
        self.progressStore = progressStore
        self.now = now
        self.maxBatchSize = max(1, maxBatchSize)
        self.maxAttachmentBytes = max(1, maxAttachmentBytes)
        self.pacingDelay = pacingDelay
        self.batchInterval = batchInterval
        self.sleep = sleep
        statusModel = BackgroundIndexingStatusModel()
        lastIndexedAt = progressStore.latestIndexedAt()
        publishStatus()

        statusModel.onIndexNow = { [weak self] in
            await self?.runPassNow()
        }
        statusModel.onPause = { [weak self] in
            self?.pause()
        }
        statusModel.onResume = { [weak self] in
            self?.resume()
        }
        statusModel.onResetIndexState = { [weak self] in
            await self?.resetIndexState()
        }
    }

    /// Reconciles running state against the latest `BackgroundIndexingSettings`.
    /// Immediately cancels in-flight work and performs zero network calls when disabled.
    public func reconcile() {
        let settings = settingsProvider()
        guard settings.isEnabled else {
            cancelActiveWork()
            isUserPaused = false
            needsFollowUpSweep = false
            pendingCount = 0
            state = .idle
            publishStatus()
            return
        }
        if isUserPaused {
            state = .paused(.userPaused)
            publishStatus()
            return
        }
        if let reason = environmentProvider().pauseReason(for: settings) {
            cancelActiveWork()
            state = .paused(reason)
            publishStatus()
            return
        }
        startPassIfIdle()
    }

    /// Wakes the indexer when foreground sync or live mail arrival adds new headers.
    /// Strictly a no-op when disabled or manually paused.
    public func notifyNewHeadersAvailable() {
        let settings = settingsProvider()
        guard settings.isEnabled, !isUserPaused else { return }
        if activeTask != nil {
            needsFollowUpSweep = true
            return
        }
        reconcile()
    }

    /// Reacts to network reachability, metering, or Low Power Mode changes.
    public func handleEnvironmentChanged() {
        let settings = settingsProvider()
        guard settings.isEnabled else {
            cancelActiveWork()
            state = .idle
            publishStatus()
            return
        }
        guard !isUserPaused else { return }

        if let reason = environmentProvider().pauseReason(for: settings) {
            cancelActiveWork()
            state = .paused(reason)
            publishStatus()
        } else if case .paused(let previous) = state, previous != .userPaused {
            startPassIfIdle()
        }
    }

    /// Manually pauses background indexing until the user chooses Resume or Index now.
    public func pause() {
        isUserPaused = true
        needsFollowUpSweep = false
        cancelActiveWork()
        if settingsProvider().isEnabled {
            state = .paused(.userPaused)
        } else {
            state = .idle
        }
        publishStatus()
    }

    /// Resumes background indexing after a manual pause.
    public func resume() {
        isUserPaused = false
        reconcile()
    }

    /// Cancels in-flight work and stops indexing cleanly (for sign-out or shutdown).
    public func stop() {
        cancelActiveWork()
        needsFollowUpSweep = false
        pendingCount = 0
        state = .idle
        publishStatus()
    }

    /// Cancels active work when an account signs out or is removed, optionally clearing persisted progress.
    public func cancelAccount(_ accountID: BrevAccount.ID, clearProgress: Bool = false) {
        cancelActiveWork()
        if clearProgress {
            progressStore.clear(accountID: accountID)
        }
        reconcile()
    }

    /// Clears stored attachment-indexing progress for `accountID` after the user removes
    /// the local attachment index or clears local cache in Mail Storage settings.
    public func invalidateAttachmentProgress(accountID: BrevAccount.ID) {
        cancelActiveWork()
        progressStore.clearAttachmentProgress(accountID: accountID)
        reconcile()
    }

    /// Clears persisted per-account indexing cursors and restarts a pass if enabled.
    public func resetIndexState() async {
        cancelActiveWork()
        let accountIDs = backendsProvider().map(\.account.id)
        progressStore.clearAll(accountIDs: accountIDs)
        indexedMessagesCount = 0
        indexedAttachmentsCount = 0
        pendingCount = 0
        lastIndexedAt = nil
        isUserPaused = false
        needsFollowUpSweep = false
        state = .idle
        publishStatus()
        if settingsProvider().isEnabled {
            await runPassNow()
        }
    }

    /// Triggers an immediate indexing pass and waits for it to finish (useful for Settings "Index now" and tests).
    public func runPassNow() async {
        let settings = settingsProvider()
        guard settings.isEnabled else {
            cancelActiveWork()
            pendingCount = 0
            state = .idle
            publishStatus()
            return
        }
        isUserPaused = false
        needsFollowUpSweep = false
        cancelActiveWork()
        activeGeneration &+= 1
        let generation = activeGeneration
        let task = Task<Void, Never> { @MainActor [weak self] in
            await self?.executeBacklog(generation: generation)
        }
        activeTask = task
        await task.value
    }

    // MARK: - Private execution

    private func startPassIfIdle() {
        guard activeTask == nil else { return }
        activeGeneration &+= 1
        let generation = activeGeneration
        activeTask = Task<Void, Never> { @MainActor [weak self] in
            await self?.executeBacklog(generation: generation)
        }
    }

    private func cancelActiveWork() {
        activeGeneration &+= 1
        activeTask?.cancel()
        activeTask = nil
    }

    private struct ScopedMessageKey: Hashable {
        let accountID: String
        let messageID: MessageHeader.ID
    }

    private struct Candidate {
        let backend: any MailBackend
        let sourceID: MailSourceID
        let folderID: Folder.ID
        let header: MessageHeader
        let needsBody: Bool
        let needsAttachments: Bool
    }

    private enum BatchOutcome {
        case drained
        case moreRemaining(canContinue: Bool)
        case stopped
    }

    /// Runs consecutive throttled batches of `maxBatchSize` until the backlog drains,
    /// indexing stops/pauses, or no non-deferred eligible candidates can advance.
    private func executeBacklog(generation: Int) async {
        defer {
            if activeGeneration == generation {
                activeTask = nil
            }
        }

        // Track (account, message) pairs that failed or deferred in this sweep so
        // subsequent batches continue draining untouched candidates without retrying
        // the same failing message in a tight loop.
        var deferredMessages = Set<ScopedMessageKey>()

        while true {
            needsFollowUpSweep = false
            let outcome = await executeSingleBatch(
                generation: generation,
                deferredMessages: &deferredMessages
            )
            switch outcome {
            case .stopped:
                return
            case .drained:
                if needsFollowUpSweep, isStillEligible(generation: generation) {
                    continue
                }
                if isStillEligible(generation: generation) {
                    state = .completed
                    publishStatus()
                }
                return
            case .moreRemaining(let canContinue):
                guard canContinue, isStillEligible(generation: generation) else {
                    if needsFollowUpSweep, isStillEligible(generation: generation) {
                        continue
                    }
                    if isStillEligible(generation: generation) {
                        state = .completed
                        publishStatus()
                    }
                    return
                }
                if batchInterval > .zero {
                    do {
                        try await sleep(batchInterval)
                    } catch {
                        handleCancellationIfCurrent(generation: generation)
                        return
                    }
                } else {
                    await Task.yield()
                }
                guard isStillEligible(generation: generation) else { return }
            }
        }
    }

    private func executeSingleBatch(
        generation: Int,
        deferredMessages: inout Set<ScopedMessageKey>
    ) async -> BatchOutcome {
        let initialSettings = settingsProvider()
        guard initialSettings.isEnabled, !isUserPaused, !Task.isCancelled, activeGeneration == generation else {
            if !initialSettings.isEnabled {
                pendingCount = 0
                state = .idle
                publishStatus()
            }
            return .stopped
        }

        if let reason = environmentProvider().pauseReason(for: initialSettings) {
            state = .paused(reason)
            publishStatus()
            return .stopped
        }

        let backends = backendsProvider().filter { $0.account.id != LocalMailBackend.accountID }
        let cutoffDate = now().addingTimeInterval(-TimeInterval(initialSettings.windowDays.days) * 86400)

        var candidates: [Candidate] = []
        var progressByAccount: [String: BackgroundIndexingAccountProgress] = [:]
        var liveIndexedAttachmentsByAccount: [String: [MessageHeader.ID: Set<String>]] = [:]

        for backend in backends {
            guard isStillEligible(generation: generation) else { return .stopped }
            let accountID = backend.account.id
            var progress = progressStore.load(accountID: accountID)
            var progressMutated = false

            // Reconcile stored FTS attachment progress against live local index rows so
            // removing the attachment index cleanly re-enables attachment indexing.
            if let ftsIndexer = backend.extensionService(LocalAttachmentTextIndexing.self) {
                let liveIDs = await ftsIndexer.indexedAttachmentIDs()
                guard isStillEligible(generation: generation) else { return .stopped }
                liveIndexedAttachmentsByAccount[accountID] = liveIDs
                if reconcileAttachmentProgress(&progress, against: liveIDs) {
                    progressMutated = true
                }
            }

            guard let mailbox = try? await backend.currentMailbox() else {
                if progressMutated {
                    saveProgressIfActive(progress, accountID: accountID, generation: generation)
                }
                progressByAccount[accountID] = progress
                continue
            }
            let sourceID = backend.sourceID(for: mailbox)
            guard let folders = try? await backend.folders(in: sourceID) else {
                if progressMutated {
                    saveProgressIfActive(progress, accountID: accountID, generation: generation)
                }
                progressByAccount[accountID] = progress
                continue
            }

            // Collect message IDs residing in Trash or Spam so multi-label accounts
            // (e.g. Gmail messages carrying both a custom label and TRASH/SPAM) are excluded.
            var excludedMessageIDs = Set<MessageHeader.ID>()
            for folder in folders where !Self.isEligibleFolder(folder) {
                guard isStillEligible(generation: generation) else { return .stopped }
                if let excludedHeaders = try? await backend.cachedMessageHeaders(in: folder, sourceID: sourceID) {
                    for header in excludedHeaders {
                        excludedMessageIDs.insert(header.id)
                    }
                }
            }

            let cachedBodyProvider = backend.extensionService(CachedMessageBodyProviding.self)
            var seenMessageIDs = Set<MessageHeader.ID>()

            for folder in folders where Self.isEligibleFolder(folder) {
                guard isStillEligible(generation: generation) else { return .stopped }
                guard let headers = try? await backend.cachedMessageHeaders(in: folder, sourceID: sourceID) else {
                    continue
                }
                for header in headers {
                    guard header.date >= cutoffDate else { continue }
                    guard !excludedMessageIDs.contains(header.id),
                          !Self.hasExcludedTrashOrSpamLabel(header)
                    else { continue }
                    guard !deferredMessages.contains(ScopedMessageKey(accountID: accountID, messageID: header.id)) else {
                        continue
                    }
                    guard seenMessageIDs.insert(header.id).inserted else { continue }

                    let needsBody = !progress.indexedBodyMessageIDs.contains(header.id)
                    var needsAttachments = false
                    if initialSettings.indexAttachments,
                       !progress.indexedAttachmentMessageIDs.contains(header.id) {
                        if header.hasAttachments {
                            needsAttachments = true
                        } else if let cachedBody = await cachedBodyProvider?.cachedBody(
                            for: header.id,
                            sourceID: sourceID
                        ) {
                            // IMAP listings default `hasAttachments = false` and structured fetches
                            // populate `body.attachments` without mutating headers; inspect cached body
                            // metadata before excluding a message from attachment indexing.
                            if cachedBody.attachments.contains(where: { !$0.isInline }) {
                                needsAttachments = true
                            } else {
                                progress.indexedAttachmentMessageIDs.insert(header.id)
                                progressMutated = true
                            }
                        } else if needsBody {
                            // Once the body is fetched in this pass we will inspect its attachments.
                            needsAttachments = true
                        }
                    }

                    guard needsBody || needsAttachments else { continue }
                    candidates.append(Candidate(
                        backend: backend,
                        sourceID: sourceID,
                        folderID: folder.id,
                        header: header,
                        needsBody: needsBody,
                        needsAttachments: needsAttachments
                    ))
                }
            }

            if progressMutated {
                saveProgressIfActive(progress, accountID: accountID, generation: generation)
            }
            progressByAccount[accountID] = progress
        }

        guard isStillEligible(generation: generation) else { return .stopped }

        candidates.sort { lhs, rhs in
            if lhs.header.date != rhs.header.date {
                return lhs.header.date > rhs.header.date
            }
            return lhs.header.id < rhs.header.id
        }

        pendingCount = candidates.count
        let batch = Array(candidates.prefix(maxBatchSize))
        let hasRemainingCandidates = candidates.count > batch.count
        guard !batch.isEmpty else {
            if lastIndexedAt == nil {
                lastIndexedAt = progressStore.latestIndexedAt(accountIDs: backends.map(\.account.id))
            }
            return .drained
        }

        var completedInBatch = 0
        var advancedOrDeferredInBatch = false
        state = .running(completed: 0, total: batch.count)
        publishStatus()

        for (index, candidate) in batch.enumerated() {
            guard isStillEligible(generation: generation) else { return .stopped }
            let currentSettings = settingsProvider()
            let accountID = candidate.backend.account.id
            let scopedKey = ScopedMessageKey(accountID: accountID, messageID: candidate.header.id)
            var progress = progressByAccount[accountID] ?? progressStore.load(accountID: accountID)

            do {
                let resolvedBody = try await resolveBody(for: candidate)
                guard isStillEligible(generation: generation) else { return .stopped }

                if resolvedBody == nil {
                    // Structured fetch failed and raw fallback was intentionally skipped;
                    // defer for this sweep without falsely claiming the body is indexed.
                    if deferredMessages.insert(scopedKey).inserted {
                        advancedOrDeferredInBatch = true
                    }
                } else if candidate.needsBody {
                    progress.indexedBodyMessageIDs.insert(candidate.header.id)
                    indexedMessagesCount += 1
                    advancedOrDeferredInBatch = true
                }

                if let body = resolvedBody,
                   currentSettings.indexAttachments,
                   !progress.indexedAttachmentMessageIDs.contains(candidate.header.id) {
                    let liveAttachmentIDs = liveIndexedAttachmentsByAccount[accountID]?[candidate.header.id] ?? []
                    let outcome = try await indexEligibleAttachments(
                        in: body,
                        candidate: candidate,
                        liveIndexedAttachmentIDs: liveAttachmentIDs,
                        progress: &progress,
                        generation: generation
                    )
                    guard isStillEligible(generation: generation) else { return .stopped }
                    if outcome.newlyIndexedCount > 0 {
                        indexedAttachmentsCount += outcome.newlyIndexedCount
                        advancedOrDeferredInBatch = true
                    }
                    if !outcome.hadTransientFailure {
                        progress.indexedAttachmentMessageIDs.insert(candidate.header.id)
                        advancedOrDeferredInBatch = true
                    } else if deferredMessages.insert(scopedKey).inserted {
                        advancedOrDeferredInBatch = true
                    }
                }

                let timestamp = now()
                progress.lastIndexedAt = timestamp
                progressByAccount[accountID] = progress
                saveProgressIfActive(progress, accountID: accountID, generation: generation)
                lastIndexedAt = timestamp

                completedInBatch += 1
                pendingCount = max(0, pendingCount - 1)
                state = .running(completed: completedInBatch, total: batch.count)
                publishStatus()
            } catch is CancellationError {
                handleCancellationIfCurrent(generation: generation)
                return .stopped
            } catch {
                guard isStillEligible(generation: generation) else { return .stopped }
                state = .failed(error.localizedDescription)
                publishStatus()
                return .stopped
            }

            if index + 1 < batch.count {
                if pacingDelay > .zero {
                    do {
                        try await sleep(pacingDelay)
                    } catch {
                        handleCancellationIfCurrent(generation: generation)
                        return .stopped
                    }
                } else {
                    await Task.yield()
                }
            }
        }

        guard isStillEligible(generation: generation) else { return .stopped }
        return hasRemainingCandidates ? .moreRemaining(canContinue: advancedOrDeferredInBatch) : .drained
    }

    private func saveProgressIfActive(
        _ progress: BackgroundIndexingAccountProgress,
        accountID: String,
        generation: Int
    ) {
        guard generation == activeGeneration, !Task.isCancelled else { return }
        progressStore.save(progress, accountID: accountID)
    }

    private func resolveBody(for candidate: Candidate) async throws -> MessageBody? {
        // Prefer the dedicated low-priority, size-bounded background indexing seam when
        // offered (e.g. IMAP) so foreground refreshes/draft discovery are never preempted
        // and searchable body text is persisted to local FTS before returning.
        if let backgroundBodyIndexer = candidate.backend.extensionService(BackgroundBodyIndexing.self) {
            return try await backgroundBodyIndexer.indexBackgroundBody(
                for: candidate.header.id,
                sourceID: candidate.sourceID,
                maxFallbackSourceBytes: maxAttachmentBytes
            )
        }
        if let cachedProvider = candidate.backend.extensionService(CachedMessageBodyProviding.self),
           let cached = await cachedProvider.cachedBody(for: candidate.header.id, sourceID: candidate.sourceID) {
            return cached
        }
        return try await candidate.backend.body(for: candidate.header.id, sourceID: candidate.sourceID)
    }

    private struct AttachmentIndexingOutcome {
        let newlyIndexedCount: Int
        let hadTransientFailure: Bool
    }

    private func indexEligibleAttachments(
        in body: MessageBody,
        candidate: Candidate,
        liveIndexedAttachmentIDs: Set<String>,
        progress: inout BackgroundIndexingAccountProgress,
        generation: Int
    ) async throws -> AttachmentIndexingOutcome {
        let messageID = candidate.header.id
        let accountID = candidate.backend.account.id
        let ftsIndexer = candidate.backend.extensionService(LocalAttachmentTextIndexing.self)

        var ftsCompleted = progress.ftsIndexedAttachmentIDsByMessage[messageID] ?? []
        ftsCompleted.formUnion(liveIndexedAttachmentIDs)
        var skipped = progress.skippedAttachmentIDsByMessage[messageID] ?? []

        var newlyIndexedCount = 0
        var hadTransientFailure = false

        for attachment in body.attachments {
            // Deterministically skip inline, oversized, or unsupported attachments without network I/O.
            guard !attachment.isInline else { continue }
            if ftsCompleted.contains(attachment.id) || skipped.contains(attachment.id) {
                continue
            }
            guard attachment.sizeBytes >= 0,
                  attachment.sizeBytes <= maxAttachmentBytes,
                  AttachmentTextExtractor.isSupported(mimeType: attachment.mimeType, fileName: attachment.name)
            else {
                skipped.insert(attachment.id)
                progress.skippedAttachmentIDsByMessage[messageID] = skipped
                saveProgressIfActive(progress, accountID: accountID, generation: generation)
                continue
            }

            guard isStillEligible(generation: generation) else {
                throw CancellationError()
            }

            let data: Data
            do {
                data = try await candidate.backend.downloadAttachment(attachment, sourceID: candidate.sourceID)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Transient download failure: leave attachment uncompleted so a later pass retries it.
                hadTransientFailure = true
                continue
            }

            guard isStillEligible(generation: generation) else {
                throw CancellationError()
            }

            guard data.count <= maxAttachmentBytes else {
                skipped.insert(attachment.id)
                progress.skippedAttachmentIDsByMessage[messageID] = skipped
                saveProgressIfActive(progress, accountID: accountID, generation: generation)
                continue
            }

            let mimeType = attachment.mimeType
            let fileName = attachment.name
            let extracted: String?
            do {
                extracted = try await Task.detached(priority: .utility) {
                    try await AttachmentTextExtractor.extract(
                        data: data,
                        mimeType: mimeType,
                        fileName: fileName,
                        timeout: AttachmentTextExtractor.defaultTimeout
                    )
                }.value
            } catch is CancellationError {
                throw CancellationError()
            } catch AttachmentTextExtractionError.timedOut {
                hadTransientFailure = true
                continue
            } catch {
                hadTransientFailure = true
                continue
            }

            guard isStillEligible(generation: generation) else {
                throw CancellationError()
            }

            guard let extracted, !extracted.isEmpty else {
                // Encrypted/malformed/no-text document: deterministically skip on future passes.
                skipped.insert(attachment.id)
                progress.skippedAttachmentIDsByMessage[messageID] = skipped
                saveProgressIfActive(progress, accountID: accountID, generation: generation)
                continue
            }

            if let ftsIndexer {
                do {
                    try await ftsIndexer.indexAttachmentText(
                        messageID: messageID,
                        folderID: candidate.folderID,
                        attachmentID: attachment.id,
                        name: attachment.name,
                        text: extracted
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Transient FTS write failure: leave uncompleted for retry.
                    hadTransientFailure = true
                    continue
                }
            }

            guard isStillEligible(generation: generation) else {
                throw CancellationError()
            }

            ftsCompleted.insert(attachment.id)
            progress.ftsIndexedAttachmentIDsByMessage[messageID] = ftsCompleted
            progress.skippedAttachmentIDsByMessage[messageID] = skipped
            saveProgressIfActive(progress, accountID: accountID, generation: generation)
            newlyIndexedCount += 1
        }

        return AttachmentIndexingOutcome(
            newlyIndexedCount: newlyIndexedCount,
            hadTransientFailure: hadTransientFailure
        )
    }

    /// Reconciles stored FTS attachment progress against the live local index.
    /// Any attachment previously written to FTS that is no longer present (for example
    /// because the user removed the attachment index) is pruned and its owning message
    /// is marked eligible for re-indexing.
    private func reconcileAttachmentProgress(
        _ progress: inout BackgroundIndexingAccountProgress,
        against liveIndexedIDs: [MessageHeader.ID: Set<String>]
    ) -> Bool {
        var mutated = false
        for (messageID, recordedIDs) in progress.ftsIndexedAttachmentIDsByMessage {
            let liveForMessage = liveIndexedIDs[messageID] ?? []
            let surviving = recordedIDs.intersection(liveForMessage)
            if surviving != recordedIDs {
                mutated = true
                if surviving.isEmpty {
                    progress.ftsIndexedAttachmentIDsByMessage.removeValue(forKey: messageID)
                } else {
                    progress.ftsIndexedAttachmentIDsByMessage[messageID] = surviving
                }
                progress.indexedAttachmentMessageIDs.remove(messageID)
            }
        }
        return mutated
    }

    private static func isEligibleFolder(_ folder: Folder) -> Bool {
        switch folder.role {
        case .trash, .spam:
            false
        default:
            true
        }
    }

    private static func hasExcludedTrashOrSpamLabel(_ header: MessageHeader) -> Bool {
        header.labels.contains { label in
            excludedCanonicalLabels.contains(label.lowercased())
        }
    }

    private func isStillEligible(generation: Int) -> Bool {
        guard activeGeneration == generation, !Task.isCancelled else { return false }
        let settings = settingsProvider()
        guard settings.isEnabled else {
            pendingCount = 0
            state = .idle
            publishStatus()
            return false
        }
        if isUserPaused {
            state = .paused(.userPaused)
            publishStatus()
            return false
        }
        if let reason = environmentProvider().pauseReason(for: settings) {
            state = .paused(reason)
            publishStatus()
            return false
        }
        return true
    }

    private func handleCancellationIfCurrent(generation: Int) {
        guard activeGeneration == generation else { return }
        let settings = settingsProvider()
        if !settings.isEnabled {
            pendingCount = 0
            state = .idle
        } else if isUserPaused {
            state = .paused(.userPaused)
        } else if let reason = environmentProvider().pauseReason(for: settings) {
            state = .paused(reason)
        }
        publishStatus()
    }

    private func publishStatus() {
        statusModel.status = BackgroundIndexingStatus(
            state: state,
            indexedMessagesCount: indexedMessagesCount,
            indexedAttachmentsCount: indexedAttachmentsCount,
            pendingCount: pendingCount,
            lastIndexedAt: lastIndexedAt
        )
    }
}
