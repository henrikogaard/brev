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

// MARK: - Sync health snapshot

struct IMAPSyncHealthSnapshot: Sendable {
    let isConnected: Bool
    let lastSuccessfulSyncAt: Date?
    let lastErrorDescription: String?
    let indexStatus: SearchIndexStatus
    let searchIndexProgress: SearchIndexProgressSnapshot?
    let lastReplayConflictDescription: String?
    let lastReplayConflictCount: Int
    let lastBackgroundRefreshSnapshot: BackgroundRefreshSnapshot?
}

// MARK: - Backend state

actor IMAPSMTPBackendState {
    private nonisolated let eventBroadcaster = Broadcaster<MailEvent>()
    // Replays the latest active folder so the IDLE watcher, which reads the
    // current folder before subscribing, can't miss an emission in that window.
    private nonisolated let idleFolderBroadcaster = Broadcaster<Folder.ID>(replaysLatest: true)
    /// Replays whether a remote folder listing has succeeded. A cache-restored
    /// mailbox is locally usable but must not start IDLE or deferred network
    /// work until this becomes true.
    private nonisolated let remoteAvailabilityBroadcaster = Broadcaster<Bool>(replaysLatest: true)
    private var connected = false
    private var remoteAvailable = false
    private var lastSuccessfulSyncAt: Date?
    private var lastErrorDescription: String?
    private var indexStatus: SearchIndexStatus = .notBuilt
    private var searchIndexProgress: SearchIndexProgressSnapshot?
    private var lastReplayConflictDescription: String?
    private var lastReplayConflictCount = 0
    private var lastBackgroundRefreshSnapshot: BackgroundRefreshSnapshot?
    private var folders: [Folder] = []
    private var folderDelimitersByID: [Folder.ID: String] = [:]
    private var stagedDraftsByID: [String: Draft] = [:]
    private var draftSyncMetadataByID: [String: DraftSyncMetadata] = [:]
    private var stagedAttachmentsByID: [String: StagedAttachment] = [:]
    private var uidValidityByFolderID: [Folder.ID: Int] = [:]
    private var knownMessageIDsByFolderID: [Folder.ID: Set<MessageHeader.ID>] = [:]
    private var activeIdleFolderID: Folder.ID?

    func install(
        folders: [Folder],
        folderDelimitersByID: [Folder.ID: String]
    ) {
        self.folders = folders
        self.folderDelimitersByID = folderDelimitersByID
        connected = true
        remoteAvailable = true
        remoteAvailabilityBroadcaster.emit(true)
        lastSuccessfulSyncAt = Date()
        lastErrorDescription = nil
    }

    func installCached(
        folders: [Folder],
        folderDelimitersByID: [Folder.ID: String],
        errorDescription: String
    ) {
        self.folders = folders
        self.folderDelimitersByID = folderDelimitersByID
        connected = true
        remoteAvailable = false
        remoteAvailabilityBroadcaster.emit(false)
        lastErrorDescription = errorDescription
    }

    /// Installs a non-empty persisted folder snapshot before the background
    /// reconnect completes. This intentionally leaves remote work unavailable.
    func installStartupCache(
        folders: [Folder],
        folderDelimitersByID: [Folder.ID: String]
    ) {
        self.folders = folders
        self.folderDelimitersByID = folderDelimitersByID
        connected = true
        remoteAvailable = false
        remoteAvailabilityBroadcaster.emit(false)
        lastErrorDescription = nil
    }

    func disconnect() {
        connected = false
        remoteAvailable = false
        remoteAvailabilityBroadcaster.emit(false)
        folders = []
        folderDelimitersByID = [:]
        stagedDraftsByID = [:]
        draftSyncMetadataByID = [:]
        stagedAttachmentsByID = [:]
        uidValidityByFolderID = [:]
        knownMessageIDsByFolderID = [:]
        activeIdleFolderID = nil
    }

    func recordSyncFailure(_ description: String) {
        connected = false
        remoteAvailable = false
        remoteAvailabilityBroadcaster.emit(false)
        lastErrorDescription = description
    }

    func hasUsableFolders() -> Bool {
        connected && !folders.isEmpty
    }

    func recordBackgroundSyncFailure(_ description: String) {
        lastErrorDescription = description
    }

    /// Clears a prior background failure after a successful folder refresh.
    func clearBackgroundSyncFailure() {
        lastErrorDescription = nil
    }

    func recordBackgroundRefreshSummary(_ summary: BackgroundRefreshSnapshot?) {
        lastBackgroundRefreshSnapshot = summary
    }

    private var isResettingLocalCache = false

    func beginIndexingIfIdle() -> Bool {
        if isResettingLocalCache {
            return false
        }
        if case .rebuilding = indexStatus {
            return false
        }
        indexStatus = .rebuilding(progress: nil)
        searchIndexProgress = nil
        lastErrorDescription = nil
        return true
    }

    func beginLocalResetIfIdle() -> Bool {
        if case .rebuilding = indexStatus {
            return false
        }
        guard !isResettingLocalCache else { return false }
        isResettingLocalCache = true
        return true
    }

    func endLocalReset() {
        isResettingLocalCache = false
    }

    func recordIndexingProgress(
        _ progress: Double,
        snapshot: SearchIndexProgressSnapshot? = nil
    ) {
        indexStatus = .rebuilding(progress: progress)
        searchIndexProgress = snapshot
    }

    func recordIndexingCompleted(messageCount: Int) {
        indexStatus = .ready(messageCount: messageCount)
        searchIndexProgress = nil
        lastSuccessfulSyncAt = Date()
        lastErrorDescription = nil
    }

    func recordIndexingCompletedWithBodyFailures(messageCount: Int, failureCount: Int) {
        indexStatus = .ready(messageCount: messageCount)
        searchIndexProgress = nil
        lastSuccessfulSyncAt = Date()
        let noun = failureCount == 1 ? "message body" : "message bodies"
        lastErrorDescription =
            "\(failureCount) \(noun) couldn't be cached during the index rebuild."
    }

    func recordIndexingFailed(_ description: String) {
        indexStatus = .failed(description)
        searchIndexProgress = nil
        lastErrorDescription = description
    }

    func resetIndexStatus() {
        indexStatus = .notBuilt
        searchIndexProgress = nil
    }

    private var isReplayingMutations = false

    /// Acquires the single-replay lock; returns `false` when a replay is already
    /// running. Offline-mutation replay is triggered from several places
    /// (reconnect, network-online, account restore), and those can overlap.
    /// Each `replayPendingMutations` call builds its own processor over the
    /// shared queue, so without this guard two concurrent replays would read the
    /// same pending snapshot and apply each mutation twice — e.g. sending a
    /// queued message twice. Callers must pair a `true` result with `endReplay`.
    func beginReplayIfIdle() -> Bool {
        guard !isReplayingMutations else { return false }
        isReplayingMutations = true
        return true
    }

    func endReplay() {
        isReplayingMutations = false
    }

    func recordMutationProcessingResult(_ result: MutationProcessingResult) {
        guard !result.conflicts.isEmpty else {
            lastReplayConflictDescription = nil
            lastReplayConflictCount = 0
            return
        }

        let noun = result.conflicts.count == 1 ? "change" : "changes"
        let firstMessage = result.conflicts[0].message
        lastReplayConflictCount = result.conflicts.count
        lastReplayConflictDescription =
            "\(result.conflicts.count) queued mail \(noun) needs review: \(firstMessage)"
    }

    func clearReplayConflictDescription() {
        lastReplayConflictDescription = nil
        lastReplayConflictCount = 0
    }

    /// Surfaces conflicts created outside the normal replay loop — e.g. queued
    /// mutations evicted because a folder's UIDVALIDITY changed (#13) — so sync
    /// health reflects them. Accumulates with any existing replay-conflict count.
    func recordReplayConflictDescription(_ message: String, count: Int) {
        guard count > 0 else { return }
        lastReplayConflictCount += count
        let noun = lastReplayConflictCount == 1 ? "change" : "changes"
        lastReplayConflictDescription =
            "\(lastReplayConflictCount) queued mail \(noun) needs review: \(message)"
    }

    func syncHealthSnapshot() -> IMAPSyncHealthSnapshot {
        IMAPSyncHealthSnapshot(
            isConnected: connected,
            lastSuccessfulSyncAt: lastSuccessfulSyncAt,
            lastErrorDescription: lastErrorDescription,
            indexStatus: indexStatus,
            searchIndexProgress: searchIndexProgress,
            lastReplayConflictDescription: lastReplayConflictDescription,
            lastReplayConflictCount: lastReplayConflictCount,
            lastBackgroundRefreshSnapshot: lastBackgroundRefreshSnapshot
        )
    }

    func requireConnected() throws {
        guard connected else {
            throw MailBackendError.notConnected
        }
    }

    func requireConnectedFolders() throws -> [Folder] {
        try requireConnected()
        return folders
    }

    func folder(id: Folder.ID) -> Folder? {
        folders.first { $0.id == id }
    }

    func hierarchyDelimiter(for folderID: Folder.ID) -> String? {
        folderDelimitersByID[folderID]
    }

    func sentFolder() throws -> Folder? {
        try requireConnected()
        return folders.first { $0.role == .sent }
    }

    func draftsFolder() throws -> Folder? {
        try requireConnected()
        return folders.first { $0.role == .drafts }
    }

    func inboxFolder() throws -> Folder? {
        try requireConnected()
        return folders.first { $0.role == .inbox } ?? folders.first
    }

    func idleFolder() throws -> Folder? {
        try requireConnected()
        if let activeIdleFolderID,
           let activeFolder = folder(id: activeIdleFolderID) {
            return activeFolder
        }
        return folders.first { $0.role == .inbox } ?? folders.first
    }

    func recordActiveMessageFolder(_ folderID: Folder.ID) {
        guard activeIdleFolderID != folderID else { return }
        activeIdleFolderID = folderID
        idleFolderBroadcaster.emit(folderID)
    }

    nonisolated func eventStream() -> AsyncStream<MailEvent> {
        eventBroadcaster.stream()
    }

    nonisolated func idleFolderStream() -> AsyncStream<Folder.ID> {
        idleFolderBroadcaster.stream()
    }

    nonisolated func remoteAvailabilityStream() -> AsyncStream<Bool> {
        remoteAvailabilityBroadcaster.stream()
    }

    func recordUIDValidity(_ uidValidity: Int?, folderID: Folder.ID) -> Bool {
        guard let uidValidity else { return false }
        defer {
            uidValidityByFolderID[folderID] = uidValidity
        }
        guard let previousUIDValidity = uidValidityByFolderID[folderID] else {
            return false
        }
        guard previousUIDValidity != uidValidity else {
            return false
        }
        knownMessageIDsByFolderID[folderID] = nil
        return true
    }

    func recordListedMessageIDs(
        _ messageIDs: [MessageHeader.ID],
        folderID: Folder.ID,
        isCompleteFolderWindow: Bool = false
    ) {
        let currentIDs = Set(messageIDs)
        guard let knownIDs = knownMessageIDsByFolderID[folderID] else {
            knownMessageIDsByFolderID[folderID] = currentIDs
            return
        }
        let addedIDs = messageIDs.filter { !knownIDs.contains($0) }
        knownMessageIDsByFolderID[folderID] = isCompleteFolderWindow
            ? currentIDs
            : knownIDs.union(currentIDs)
        guard !addedIDs.isEmpty else { return }
        emit(.messagesAdded(folderID: folderID, messageIDs: addedIDs))
    }

    func stageDraft(_ draft: Draft) -> Draft {
        var saved = draft
        if saved.remoteID == nil {
            saved.remoteID = "imap-local-draft-\(saved.id)"
        }
        stagedDraftsByID[saved.id] = saved
        if let remoteID = saved.remoteID {
            stagedDraftsByID[remoteID] = saved
        }
        return saved
    }

    func draftSyncMetadata(for draftID: Draft.ID) -> DraftSyncMetadata {
        draftSyncMetadataByID[draftID] ?? DraftSyncMetadata()
    }

    func markDraftDirty(_ draft: Draft) {
        var metadata = draftSyncMetadata(for: draft.id)
        metadata.isDirty = true
        draftSyncMetadataByID[draft.id] = metadata
        if let remoteID = draft.remoteID {
            draftSyncMetadataByID[remoteID] = metadata
        }
    }

    func markDraftSynced(_ draft: Draft, fingerprint: DraftContentFingerprint) {
        let metadata = DraftSyncMetadata(
            lastSyncedFingerprint: fingerprint,
            isDirty: false,
            conflictDraftID: draftSyncMetadata(for: draft.id).conflictDraftID
        )
        draftSyncMetadataByID[draft.id] = metadata
        if let remoteID = draft.remoteID {
            draftSyncMetadataByID[remoteID] = metadata
        }
    }

    @discardableResult
    func stageConflictDraft(local: Draft, remote: Draft) -> Draft {
        let conflict = Draft(
            id: "\(local.id)-conflict-\(UUID().uuidString)",
            remoteID: nil,
            identityID: remote.identityID,
            inReplyToMessageID: remote.inReplyToMessageID,
            forwardedMessageID: remote.forwardedMessageID,
            to: remote.to,
            cc: remote.cc,
            bcc: remote.bcc,
            subject: remote.subject,
            htmlBody: remote.htmlBody,
            attachmentIDs: remote.attachmentIDs,
            scheduledFor: remote.scheduledFor,
            readReceiptRequest: remote.readReceiptRequest,
            readReceiptResponse: remote.readReceiptResponse,
            securityMode: remote.securityMode
        )
        let staged = stageDraft(conflict)
        var metadata = draftSyncMetadata(for: local.id)
        metadata.conflictDraftID = staged.id
        draftSyncMetadataByID[local.id] = metadata
        if let remoteID = local.remoteID {
            draftSyncMetadataByID[remoteID] = metadata
        }
        return staged
    }

    func draft(for draftID: Draft.ID) -> Draft? {
        stagedDraftsByID[draftID]
    }

    func stageAttachment(
        draftID: String,
        data: Data,
        filename: String,
        mimeType: String,
        isInline: Bool = false,
        contentID: String? = nil
    ) -> StagedAttachment {
        let attachmentID = "imap-local-attachment-\(draftID)-\(stagedAttachmentsByID.count + 1)"
        let attachment = StagedAttachment(
            id: attachmentID,
            draftID: draftID,
            filename: filename,
            mimeType: mimeType,
            data: data,
            isInline: isInline,
            contentID: contentID
        )
        stagedAttachmentsByID[attachmentID] = attachment
        return attachment
    }

    func attachment(for attachmentID: String) -> StagedAttachment? {
        stagedAttachmentsByID[attachmentID]
    }

    func discardDraft(draftID: String) {
        let staged = stagedDraftsByID[draftID]
        let idsToRemove = [draftID, staged?.id, staged?.remoteID].compactMap { $0 }
        for id in idsToRemove {
            stagedDraftsByID.removeValue(forKey: id)
        }
        stagedAttachmentsByID = stagedAttachmentsByID.filter { _, attachment in
            !idsToRemove.contains(attachment.draftID)
        }
    }

    func clearDraftAndAttachments(for draft: Draft) {
        let idsToRemove = [draft.id, draft.remoteID].compactMap { $0 }
        for id in idsToRemove {
            stagedDraftsByID.removeValue(forKey: id)
        }
        stagedAttachmentsByID = stagedAttachmentsByID.filter { _, attachment in
            !idsToRemove.contains(attachment.draftID)
        }
    }

    func emit(_ event: MailEvent) {
        eventBroadcaster.emit(event)
    }
}

// MARK: - Event broadcaster

/// Fan-out of a `Sendable` element to any number of `AsyncStream` subscribers.
///
/// When `replaysLatest` is set, a new subscriber immediately receives the most
/// recent element on registration. This closes the subscribe-after-emit race
/// where a value emitted between a consumer reading current state and
/// subscribing would otherwise be lost (no buffering).
final class Broadcaster<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private let replaysLatest: Bool
    private var latest: Element?

    init(replaysLatest: Bool = false) {
        self.replaysLatest = replaysLatest
    }

    func stream() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let token = UUID()
            let replay: Element? = lock.withLock {
                continuations[token] = continuation
                return replaysLatest ? latest : nil
            }
            if let replay {
                continuation.yield(replay)
            }
            continuation.onTermination = { [weak self] _ in
                self?.unregister(token: token)
            }
        }
    }

    func emit(_ element: Element) {
        let snapshot: [AsyncStream<Element>.Continuation] = lock.withLock {
            if replaysLatest {
                latest = element
            }
            return Array(continuations.values)
        }
        for continuation in snapshot {
            continuation.yield(element)
        }
    }

    private func unregister(token: UUID) {
        lock.withLock {
            _ = continuations.removeValue(forKey: token)
        }
    }
}

// MARK: - Staged attachment

struct StagedAttachment: Sendable, Hashable {
    let id: String
    let draftID: String
    let filename: String
    let mimeType: String
    let data: Data
    /// Inline (body-referenced) part: emitted with Content-Disposition: inline and a Content-ID.
    let isInline: Bool
    /// RFC 2392 Content-ID (no angle brackets), required when `isInline` is true.
    let contentID: String?
}

// MARK: - Scheduled send support

struct ScheduledDraftEntry: Codable, Sendable, Hashable {
    let draftID: String
    let scheduledFor: Date
    /// When this entry was last claimed by a delivery pass. Acts as a short
    /// lease so two concurrent passes don't both send the same draft.
    var claimedAt: Date?
    /// Number of failed delivery attempts, used to compute `nextAttemptAt`.
    var attemptCount: Int
    /// Earliest time the polling loop may retry after a failure (`nil` = eligible
    /// immediately). An explicit reconnect ignores this — see `claimDueEntries`.
    var nextAttemptAt: Date?

    init(
        draftID: String,
        scheduledFor: Date,
        claimedAt: Date? = nil,
        attemptCount: Int = 0,
        nextAttemptAt: Date? = nil
    ) {
        self.draftID = draftID
        self.scheduledFor = scheduledFor
        self.claimedAt = claimedAt
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        draftID = try container.decode(String.self, forKey: .draftID)
        scheduledFor = try container.decode(Date.self, forKey: .scheduledFor)
        // Tolerate entries persisted before the lease/backoff fields existed.
        claimedAt = try container.decodeIfPresent(Date.self, forKey: .claimedAt)
        attemptCount = try container.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
        nextAttemptAt = try container.decodeIfPresent(Date.self, forKey: .nextAttemptAt)
    }
}

final class ScheduledSendStore: @unchecked Sendable {
    private let lock = NSLock()
    /// The store is shared by a backend instance, so its in-memory cache must
    /// remain account-scoped just like the persisted UserDefaults keys.
    private var cachedEntriesByAccountID: [BrevAccount.ID: [ScheduledDraftEntry]] = [:]

    private static func userDefaultsKey(for accountID: BrevAccount.ID) -> String {
        "scheduledSends.\(accountID)"
    }

    func entries(accountID: BrevAccount.ID) -> [ScheduledDraftEntry] {
        lock.withLock {
            entriesWithoutLock(accountID: accountID)
        }
    }

    func add(entry: ScheduledDraftEntry, accountID: BrevAccount.ID) {
        lock.withLock {
            var entries = entriesWithoutLock(accountID: accountID)
            entries.removeAll { $0.draftID == entry.draftID }
            entries.append(entry)
            persist(entries, accountID: accountID)
        }
    }

    func remove(draftID: String, accountID: BrevAccount.ID) {
        lock.withLock {
            var entries = entriesWithoutLock(accountID: accountID)
            entries.removeAll { $0.draftID == draftID }
            persist(entries, accountID: accountID)
        }
    }

    func dueEntries(accountID: BrevAccount.ID, before: Date) -> [ScheduledDraftEntry] {
        lock.withLock {
            entriesWithoutLock(accountID: accountID).filter { $0.scheduledFor <= before }
        }
    }

    /// Atomically claims due entries for delivery, stamping each with a lease so
    /// a concurrent pass won't re-claim the same draft. Entries throttled by a
    /// post-failure backoff (`nextAttemptAt` in the future) or still inside an
    /// unexpired claim lease are skipped unless `force` is set — an explicit
    /// reconnect retries immediately and clears stale claims/backoff gating.
    func claimDueEntries(
        accountID: BrevAccount.ID,
        before now: Date,
        lease: TimeInterval,
        force: Bool = false
    ) -> [ScheduledDraftEntry] {
        lock.withLock {
            var all = entriesWithoutLock(accountID: accountID)
            var claimed: [ScheduledDraftEntry] = []
            for index in all.indices {
                let entry = all[index]
                guard entry.scheduledFor <= now else { continue }
                if !force {
                    if let nextAttemptAt = entry.nextAttemptAt, nextAttemptAt > now { continue }
                    if let claimedAt = entry.claimedAt, now.timeIntervalSince(claimedAt) < lease { continue }
                }
                all[index].claimedAt = now
                claimed.append(all[index])
            }
            if !claimed.isEmpty {
                persist(all, accountID: accountID)
            }
            return claimed
        }
    }

    /// Records a failed delivery attempt: releases the claim lease and pushes the
    /// next eligible retry out with capped exponential backoff, so a
    /// permanently-failing send no longer fires a full SMTP attempt on every tick.
    func recordSendFailure(
        draftID: String,
        accountID: BrevAccount.ID,
        now: Date,
        baseInterval: TimeInterval,
        maxInterval: TimeInterval
    ) {
        lock.withLock {
            var all = entriesWithoutLock(accountID: accountID)
            guard let index = all.firstIndex(where: { $0.draftID == draftID }) else { return }
            var entry = all[index]
            entry.attemptCount += 1
            let delay = min(maxInterval, baseInterval * pow(2, Double(entry.attemptCount - 1)))
            entry.nextAttemptAt = now.addingTimeInterval(delay)
            entry.claimedAt = nil
            all[index] = entry
            persist(all, accountID: accountID)
        }
    }

    func clear(accountID: BrevAccount.ID) {
        lock.withLock {
            cachedEntriesByAccountID[accountID] = []
            UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey(for: accountID))
        }
    }

    /// Removes an account's persisted scheduled-send entries without needing a
    /// live store instance — used during account teardown (#167) so a removed
    /// account leaves no orphaned `scheduledSends.<accountID>` behind.
    static func purge(accountID: BrevAccount.ID) {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey(for: accountID))
    }

    private func entriesWithoutLock(accountID: BrevAccount.ID) -> [ScheduledDraftEntry] {
        if let cached = cachedEntriesByAccountID[accountID] { return cached }
        let key = Self.userDefaultsKey(for: accountID)
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        let entries = (try? JSONDecoder().decode([ScheduledDraftEntry].self, from: data)) ?? []
        cachedEntriesByAccountID[accountID] = entries
        return entries
    }

    private func persist(_ entries: [ScheduledDraftEntry], accountID: BrevAccount.ID) {
        cachedEntriesByAccountID[accountID] = entries
        let key = Self.userDefaultsKey(for: accountID)
        if entries.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            let data = try? JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// A small, persisted ledger of draft IDs whose SMTP send was confirmed
/// (the server accepted DATA). It lets a replayed or relaunched send skip a
/// draft that already went out — guarding the "delivered, but the queue or
/// schedule entry wasn't cleared because of a crash/race between the send and
/// the cleanup" duplicate. It only ever *skips* a confirmed-sent draft, so it
/// can never drop a legitimate send. Capped to a recent window so it cannot
/// grow without bound (#14).
public final class SentMessageLedger: @unchecked Sendable {
    private let lock = NSLock()
    private let defaults: UserDefaults
    private let maxEntries: Int

    public init(defaults: UserDefaults = .standard, maxEntries: Int = 500) {
        self.defaults = defaults
        self.maxEntries = maxEntries
    }

    private static func userDefaultsKey(for accountID: BrevAccount.ID) -> String {
        "sentMessageLedger.\(accountID)"
    }

    func contains(draftID: String, accountID: BrevAccount.ID) -> Bool {
        lock.withLock { load(accountID: accountID).contains(draftID) }
    }

    func record(draftID: String, accountID: BrevAccount.ID) {
        lock.withLock {
            var ids = load(accountID: accountID)
            ids.removeAll { $0 == draftID }
            ids.append(draftID)
            if ids.count > maxEntries {
                ids.removeFirst(ids.count - maxEntries)
            }
            persist(ids, accountID: accountID)
        }
    }

    /// Removes an account's ledger from the standard store without a live
    /// instance — used during account teardown so a removed account leaves no
    /// orphaned key behind.
    static func purge(accountID: BrevAccount.ID) {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey(for: accountID))
    }

    private func load(accountID: BrevAccount.ID) -> [String] {
        guard let data = defaults.data(forKey: Self.userDefaultsKey(for: accountID)) else {
            return []
        }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private func persist(_ ids: [String], accountID: BrevAccount.ID) {
        let key = Self.userDefaultsKey(for: accountID)
        if ids.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(ids) {
            defaults.set(data, forKey: key)
        }
    }
}
