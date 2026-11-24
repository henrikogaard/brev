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
/// - Excludes Trash and Spam folders from automatic backfill.
/// - Fetches missing bodies via `MailBackend.body(for:sourceID:)` (which uses IMAP `BODY.PEEK[]`
///   or Gmail read APIs) and never mutates read/unread flags.
/// - Only downloads non-inline, text-extractable attachments within `maxAttachmentBytes`
///   and feeds extracted text into the backend's local FTS index via `LocalAttachmentTextIndexing`.
/// - Persists per-account indexed cursors so messages are not re-fetched across runs.
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
    private let sleep: @Sendable (Duration) async throws -> Void

    private var activeTask: Task<Void, Never>?
    private var activeGeneration = 0
    private var isUserPaused = false

    /// Creates a background recent-mail indexing coordinator.
    /// - Parameters:
    ///   - backendsProvider: Returns currently connected mail backends.
    ///   - settingsProvider: Reads the current `BackgroundIndexingSettings`.
    ///   - environmentProvider: Samples live network and power conditions.
    ///   - progressStore: Persists per-account indexed message IDs so already-indexed mail is skipped.
    ///   - now: Supplies the current date for window filtering and timestamps (injectable for tests).
    ///   - maxBatchSize: Maximum number of messages processed per throttled pass.
    ///   - maxAttachmentBytes: Maximum per-attachment byte size eligible for background download & extraction.
    ///   - pacingDelay: Polite yield delay between message fetches to avoid competing with foreground mail reads.
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
        cancelActiveWork()
        activeGeneration &+= 1
        let generation = activeGeneration
        let task = Task<Void, Never> { @MainActor [weak self] in
            await self?.executePass(generation: generation)
        }
        activeTask = task
        await task.value
    }

    // MARK: - Private execution

    private func startPassIfIdle() {
        guard activeTask == nil else { return }
        activeGeneration &+= 1
        let generation = activeGeneration
        activeTask = Task { @MainActor [weak self] in
            await self?.executePass(generation: generation)
        }
    }

    private func cancelActiveWork() {
        activeGeneration &+= 1
        activeTask?.cancel()
        activeTask = nil
    }

    private struct Candidate {
        let backend: any MailBackend
        let sourceID: MailSourceID
        let folderID: Folder.ID
        let header: MessageHeader
        let needsBody: Bool
        let needsAttachments: Bool
    }

    private func executePass(generation: Int) async {
        defer {
            if activeGeneration == generation {
                activeTask = nil
            }
        }

        let initialSettings = settingsProvider()
        guard initialSettings.isEnabled, !isUserPaused, !Task.isCancelled, activeGeneration == generation else {
            if !initialSettings.isEnabled {
                pendingCount = 0
                state = .idle
                publishStatus()
            }
            return
        }

        if let reason = environmentProvider().pauseReason(for: initialSettings) {
            state = .paused(reason)
            publishStatus()
            return
        }

        let backends = backendsProvider().filter { $0.account.id != LocalMailBackend.accountID }
        let cutoffDate = now().addingTimeInterval(-TimeInterval(initialSettings.windowDays.days) * 86400)

        var candidates: [Candidate] = []
        var progressByAccount: [String: BackgroundIndexingAccountProgress] = [:]

        for backend in backends {
            guard isStillEligible(generation: generation) else { return }
            let accountID = backend.account.id
            var progress = progressStore.load(accountID: accountID)
            if let attachmentIndexer = backend.extensionService(LocalAttachmentTextIndexing.self) {
                let alreadyIndexedAttachments = await attachmentIndexer.indexedAttachmentMessageIDs()
                progress.indexedAttachmentMessageIDs.formUnion(alreadyIndexedAttachments)
            }
            progressByAccount[accountID] = progress

            guard let mailbox = try? await backend.currentMailbox() else { continue }
            let sourceID = backend.sourceID(for: mailbox)
            guard let folders = try? await backend.folders(in: sourceID) else { continue }

            var seenMessageIDs = Set<MessageHeader.ID>()
            for folder in folders where Self.isEligibleFolder(folder) {
                guard isStillEligible(generation: generation) else { return }
                guard let headers = try? await backend.cachedMessageHeaders(in: folder, sourceID: sourceID) else {
                    continue
                }
                for header in headers {
                    guard header.date >= cutoffDate else { continue }
                    guard seenMessageIDs.insert(header.id).inserted else { continue }
                    let needsBody = !progress.indexedBodyMessageIDs.contains(header.id)
                    let needsAttachments = initialSettings.indexAttachments
                        && header.hasAttachments
                        && !progress.indexedAttachmentMessageIDs.contains(header.id)
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
        }

        guard isStillEligible(generation: generation) else { return }

        candidates.sort { lhs, rhs in
            if lhs.header.date != rhs.header.date {
                return lhs.header.date > rhs.header.date
            }
            return lhs.header.id < rhs.header.id
        }

        pendingCount = candidates.count
        let batch = Array(candidates.prefix(maxBatchSize))
        guard !batch.isEmpty else {
            if lastIndexedAt == nil {
                lastIndexedAt = progressStore.latestIndexedAt(accountIDs: backends.map(\.account.id))
            }
            state = .completed
            publishStatus()
            return
        }

        var completedInBatch = 0
        state = .running(completed: 0, total: batch.count)
        publishStatus()

        for (index, candidate) in batch.enumerated() {
            guard isStillEligible(generation: generation) else { return }
            let currentSettings = settingsProvider()
            let accountID = candidate.backend.account.id
            var progress = progressByAccount[accountID] ?? progressStore.load(accountID: accountID)

            do {
                let body = try await resolveBody(for: candidate, needsBody: candidate.needsBody)
                guard isStillEligible(generation: generation) else { return }

                if candidate.needsBody {
                    progress.indexedBodyMessageIDs.insert(candidate.header.id)
                    indexedMessagesCount += 1
                }

                if currentSettings.indexAttachments,
                   !progress.indexedAttachmentMessageIDs.contains(candidate.header.id) {
                    let newlyIndexed = try await indexEligibleAttachments(
                        in: body,
                        candidate: candidate,
                        generation: generation
                    )
                    guard isStillEligible(generation: generation) else { return }
                    indexedAttachmentsCount += newlyIndexed
                    progress.indexedAttachmentMessageIDs.insert(candidate.header.id)
                }

                let timestamp = now()
                progress.lastIndexedAt = timestamp
                progressByAccount[accountID] = progress
                progressStore.save(progress, accountID: accountID)
                lastIndexedAt = timestamp

                completedInBatch += 1
                pendingCount = max(0, pendingCount - 1)
                state = .running(completed: completedInBatch, total: batch.count)
                publishStatus()
            } catch is CancellationError {
                handleCancellationIfCurrent(generation: generation)
                return
            } catch {
                guard isStillEligible(generation: generation) else { return }
                state = .failed(error.localizedDescription)
                publishStatus()
                return
            }

            if index + 1 < batch.count {
                if pacingDelay > .zero {
                    do {
                        try await sleep(pacingDelay)
                    } catch {
                        handleCancellationIfCurrent(generation: generation)
                        return
                    }
                } else {
                    await Task.yield()
                }
            }
        }

        guard isStillEligible(generation: generation) else { return }
        state = .completed
        publishStatus()
    }

    private func resolveBody(for candidate: Candidate, needsBody: Bool) async throws -> MessageBody {
        if let cachedProvider = candidate.backend.extensionService(CachedMessageBodyProviding.self),
           let cached = await cachedProvider.cachedBody(for: candidate.header.id, sourceID: candidate.sourceID) {
            return cached
        }
        _ = needsBody
        return try await candidate.backend.body(for: candidate.header.id, sourceID: candidate.sourceID)
    }

    private func indexEligibleAttachments(
        in body: MessageBody,
        candidate: Candidate,
        generation: Int
    ) async throws -> Int {
        let eligible = body.attachments.filter { isEligibleAttachment($0) }
        guard !eligible.isEmpty else { return 0 }

        let ftsIndexer = candidate.backend.extensionService(LocalAttachmentTextIndexing.self)
        var indexedCount = 0

        for attachment in eligible {
            guard isStillEligible(generation: generation) else {
                throw CancellationError()
            }
            let data: Data
            do {
                data = try await candidate.backend.downloadAttachment(attachment, sourceID: candidate.sourceID)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Skip individual unreadable/missing attachments without aborting the whole pass.
                continue
            }

            guard isStillEligible(generation: generation) else {
                throw CancellationError()
            }
            guard data.count <= maxAttachmentBytes else { continue }

            let mimeType = attachment.mimeType
            let fileName = attachment.name
            let extracted = try? await Task.detached(priority: .utility) {
                try await AttachmentTextExtractor.extract(
                    data: data,
                    mimeType: mimeType,
                    fileName: fileName,
                    timeout: AttachmentTextExtractor.defaultTimeout
                )
            }.value

            guard isStillEligible(generation: generation) else {
                throw CancellationError()
            }
            guard let extracted, !extracted.isEmpty else { continue }

            if let ftsIndexer {
                try? await ftsIndexer.indexAttachmentText(
                    messageID: candidate.header.id,
                    folderID: candidate.folderID,
                    attachmentID: attachment.id,
                    name: attachment.name,
                    text: extracted
                )
            }
            indexedCount += 1
        }
        return indexedCount
    }

    private func isEligibleAttachment(_ attachment: Attachment) -> Bool {
        guard !attachment.isInline else { return false }
        guard attachment.sizeBytes >= 0, attachment.sizeBytes <= maxAttachmentBytes else { return false }
        return AttachmentTextExtractor.isSupported(mimeType: attachment.mimeType, fileName: attachment.name)
    }

    private static func isEligibleFolder(_ folder: Folder) -> Bool {
        switch folder.role {
        case .trash, .spam:
            false
        default:
            true
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
