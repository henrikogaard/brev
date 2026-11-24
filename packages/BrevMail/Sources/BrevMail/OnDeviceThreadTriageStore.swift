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

import BrevAI
import BrevBackend
import Foundation
import Observation

/// Precomputed per-thread header groups and fingerprints for O(1) message-list row lookups.
public struct ProactiveTriageThreadIndex: Equatable, Sendable {
    /// Empty index used before headers load.
    public static let empty = ProactiveTriageThreadIndex(
        headersByCacheKey: [:],
        headerFingerprintByCacheKey: [:]
    )

    public let headersByCacheKey: [String: [MessageHeader]]
    public let headerFingerprintByCacheKey: [String: String]

    /// Builds an O(N) thread index for a single account's loaded headers, excluding Trash and Spam messages.
    public static func build(
        accountID: BrevAccount.ID,
        headers: [MessageHeader],
        folder: Folder?,
        allFolders: [Folder]
    ) -> ProactiveTriageThreadIndex {
        let eligible = OnDeviceThreadTriageStore.eligibleHeaders(
            from: headers,
            folder: folder,
            allFolders: allFolders
        )
        guard !eligible.isEmpty else { return .empty }

        var grouped: [String: [MessageHeader]] = [:]
        grouped.reserveCapacity(eligible.count)
        for header in eligible {
            let key = OnDeviceThreadTriageStore.cacheKey(accountID: accountID, header: header)
            grouped[key, default: []].append(header)
        }

        var sortedGroups: [String: [MessageHeader]] = [:]
        var fingerprints: [String: String] = [:]
        sortedGroups.reserveCapacity(grouped.count)
        fingerprints.reserveCapacity(grouped.count)

        for (key, group) in grouped {
            let ordered = OnDeviceThreadTriageStore.sortedChronologically(group)
            sortedGroups[key] = ordered
            fingerprints[key] = OnDeviceThreadTriageStore.headerFingerprint(forOrderedHeaders: ordered)
        }

        return ProactiveTriageThreadIndex(
            headersByCacheKey: sortedGroups,
            headerFingerprintByCacheKey: fingerprints
        )
    }

    /// Builds an O(N) thread index for unified multi-account items, excluding Trash and Spam messages.
    static func build(
        items: [UnifiedInboxItem],
        excludedFolderIDsByAccountID: [BrevAccount.ID: Set<Folder.ID>]
    ) -> ProactiveTriageThreadIndex {
        guard !items.isEmpty else { return .empty }

        var grouped: [String: [MessageHeader]] = [:]
        grouped.reserveCapacity(items.count)
        for item in items {
            if OnDeviceThreadTriageStore.isExcludedFolder(item.folder) {
                continue
            }
            if let excluded = excludedFolderIDsByAccountID[item.sourceID.accountID],
               excluded.contains(item.header.folderID) {
                continue
            }
            let key = OnDeviceThreadTriageStore.cacheKey(
                accountID: item.sourceID.accountID,
                header: item.header
            )
            grouped[key, default: []].append(item.header)
        }

        var sortedGroups: [String: [MessageHeader]] = [:]
        var fingerprints: [String: String] = [:]
        sortedGroups.reserveCapacity(grouped.count)
        fingerprints.reserveCapacity(grouped.count)

        for (key, group) in grouped {
            let ordered = OnDeviceThreadTriageStore.sortedChronologically(group)
            sortedGroups[key] = ordered
            fingerprints[key] = OnDeviceThreadTriageStore.headerFingerprint(forOrderedHeaders: ordered)
        }

        return ProactiveTriageThreadIndex(
            headersByCacheKey: sortedGroups,
            headerFingerprintByCacheKey: fingerprints
        )
    }

    /// Returns the precomputed chronological thread headers for `cacheKey`, falling back to `[fallback]`.
    public func headers(for cacheKey: String, fallback: MessageHeader) -> [MessageHeader] {
        headersByCacheKey[cacheKey] ?? [fallback]
    }

    /// Returns the precomputed header-only fingerprint for `cacheKey`, falling back to `fallback`.
    public func headerFingerprint(for cacheKey: String, fallback: MessageHeader) -> String {
        headerFingerprintByCacheKey[cacheKey]
            ?? OnDeviceThreadTriageStore.headerFingerprint(for: [fallback])
    }
}

/// Selects the bounded batch of visible/filtered rows around the active scroll viewport.
public enum ProactiveTriageVisibleWindow {
    /// Default maximum visible-window threads scheduled per batch.
    public static let defaultMaxBatchSize = 15

    /// Selects up to `maxBatchSize` unique-thread items from `filteredItems` centered on
    /// `visibleIDs`, advancing as the user scrolls and skipping hidden/filtered-out rows.
    public static func selectBatch<Item>(
        from filteredItems: [Item],
        visibleIDs: Set<String>,
        itemID: (Item) -> String,
        cacheKey: (Item) -> String,
        maxBatchSize: Int = defaultMaxBatchSize
    ) -> [Item] {
        guard maxBatchSize > 0, !filteredItems.isEmpty else { return [] }

        let anchorIndices: [Int]
        if visibleIDs.isEmpty {
            anchorIndices = Array(filteredItems.indices)
        } else {
            let matching = filteredItems.indices.filter { visibleIDs.contains(itemID(filteredItems[$0])) }
            if let firstVisible = matching.first, let lastVisible = matching.last {
                // Prioritize currently visible rows first, then look ahead/behind in the filtered list.
                let after = Array((lastVisible + 1) ..< filteredItems.count)
                let before = Array((0 ..< firstVisible).reversed())
                anchorIndices = matching + after + before
            } else {
                anchorIndices = Array(filteredItems.indices)
            }
        }

        var seenKeys = Set<String>()
        var selected: [Item] = []
        selected.reserveCapacity(min(maxBatchSize, filteredItems.count))
        for index in anchorIndices {
            let item = filteredItems[index]
            let key = cacheKey(item)
            guard seenKeys.insert(key).inserted else { continue }
            selected.append(item)
            if selected.count >= maxBatchSize {
                break
            }
        }
        return selected
    }

    /// Deterministic task key combining selected cache keys and their thread fingerprints so
    /// scrolling or paging in older replies automatically re-triggers triage.
    public static func taskKey(
        prefix: String,
        selectedKeysAndFingerprints: [(cacheKey: String, headerFingerprint: String)]
    ) -> String {
        let entries = selectedKeysAndFingerprints
            .map { "\($0.cacheKey)=\($0.headerFingerprint)" }
            .joined(separator: ",")
        return "\(prefix)|\(entries)"
    }
}

/// Main-actor observable local cache and scheduler for opt-in proactive on-device triage.
///
/// Enforces two hard privacy gates before reading cached bodies or running inference:
/// 1. `AIWriterSettings.isProactiveOnDeviceTriageAvailable` must be `true`, and
/// 2. the account's resolved `AIBackend.isOnDeviceZeroNetwork` must be `true`.
///
/// Never triggers network body fetches; reads strictly from already-loaded headers and
/// optional `CachedMessageBodyProviding` caches. Observes `UserDefaults.didChangeNotification`
/// so turning off AI or proactive triage immediately cancels queued work and wipes cached
/// insights even when no mailbox view is mounted.
@MainActor
@Observable
public final class OnDeviceThreadTriageStore {
    /// Cached insights keyed by `cacheKey(accountID:header:)`, bounded by `maxCacheEntries`.
    public private(set) var insightsByKey: [String: ThreadTriageInsight] = [:]

    @ObservationIgnored
    private let engine: ProactiveOnDeviceTriageEngine

    @ObservationIgnored
    private let maxCacheEntries: Int

    @ObservationIgnored
    private let observedDefaults: UserDefaults?

    @ObservationIgnored
    private var defaultsObserver: NSObjectProtocol?

    @ObservationIgnored
    private var headerFingerprintByKey: [String: String] = [:]

    @ObservationIgnored
    private var lruOrder: [String] = []

    @ObservationIgnored
    private var activeTasksByKey: [String: (fingerprint: String, task: Task<Void, Never>)] = [:]

    /// Creates a store backed by the given proactive on-device triage engine.
    ///
    /// - Parameters:
    ///   - engine: Actor enforcing concurrency, redaction, and zero-network privacy gates.
    ///   - maxCacheEntries: Maximum insights retained in `insightsByKey` (LRU evicted).
    ///   - defaults: `UserDefaults` observed for immediate opt-out invalidation even when no views are mounted.
    public init(
        engine: ProactiveOnDeviceTriageEngine = ProactiveOnDeviceTriageEngine(),
        maxCacheEntries: Int = ProactiveOnDeviceTriageEngine.defaultMaxCacheEntries,
        defaults: UserDefaults? = .standard
    ) {
        self.engine = engine
        self.maxCacheEntries = max(1, maxCacheEntries)
        observedDefaults = defaults

        if let defaults {
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: defaults,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleObservedDefaultsChange()
                }
            }
        }
    }

    deinit {
        if let observer = defaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func handleObservedDefaultsChange() {
        guard let observedDefaults else { return }
        let liveSettings = AIWriterSettings.load(from: observedDefaults)
        if !liveSettings.isProactiveOnDeviceTriageAvailable {
            clearAll()
        }
    }

    private func resolveLiveSettings(
        fallback: AIWriterSettings,
        overrideProvider: (() -> AIWriterSettings)?
    ) -> AIWriterSettings {
        if let overrideProvider {
            return overrideProvider()
        }
        if let observedDefaults {
            return AIWriterSettings.load(from: observedDefaults)
        }
        return fallback
    }

    /// Account-scoped cache key preventing collisions across accounts.
    public nonisolated static func cacheKey(
        accountID: BrevAccount.ID,
        header: MessageHeader
    ) -> String {
        let threadKey = header.threadID.isEmpty ? header.id : header.threadID
        return "\(accountID)|\(threadKey)"
    }

    /// Sorts headers deterministically oldest → newest.
    public nonisolated static func sortedChronologically(_ headers: [MessageHeader]) -> [MessageHeader] {
        headers.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id < $1.id
        }
    }

    /// Returns folder IDs for every Trash or Spam folder in `folders`.
    public nonisolated static func excludedFolderIDs(from folders: [Folder]) -> Set<Folder.ID> {
        Set(folders.filter { isExcludedFolder($0) }.map(\.id))
    }

    /// Filters out messages belonging to Trash or Spam across the entire conversation.
    public nonisolated static func eligibleHeaders(
        from headers: [MessageHeader],
        folder: Folder?,
        allFolders: [Folder] = []
    ) -> [MessageHeader] {
        if isExcludedFolder(folder) {
            return []
        }
        let excludedIDs = excludedFolderIDs(from: allFolders)
        guard !excludedIDs.isEmpty else { return headers }
        return headers.filter { !excludedIDs.contains($0.folderID) }
    }

    /// Header-only deterministic fingerprint invalidated when messages are added or updated.
    public nonisolated static func headerFingerprint(for headers: [MessageHeader]) -> String {
        headerFingerprint(forOrderedHeaders: sortedChronologically(headers))
    }

    /// Header-only deterministic fingerprint for already chronologically sorted headers.
    public nonisolated static func headerFingerprint(forOrderedHeaders ordered: [MessageHeader]) -> String {
        ordered
            .map { "\($0.id)|\($0.date.timeIntervalSinceReferenceDate)|\($0.subject.count)|\($0.snippet.count)" }
            .joined(separator: ";")
    }

    /// Cache-only body revision token for the selected newest-message window.
    public nonisolated static func bodyRevision(
        for recentOrderedHeaders: [MessageHeader],
        cachedBodies: [MessageHeader.ID: MessageBody]
    ) -> String {
        recentOrderedHeaders.map { header in
            guard let body = cachedBodies[header.id] else {
                return "\(header.id):0"
            }
            let text = cachedPlainText(for: body, fallbackSnippet: "")
            guard !text.isEmpty else { return "\(header.id):0" }
            let hash = fnv1a64(text)
            return "\(header.id):\(text.utf8.count):\(String(hash, radix: 16))"
        }.joined(separator: ",")
    }

    /// Deterministic fingerprint combining header state and cache-only body availability/revision.
    public nonisolated static func sourceFingerprint(
        for headers: [MessageHeader],
        cachedBodies: [MessageHeader.ID: MessageBody] = [:]
    ) -> String {
        let ordered = sortedChronologically(headers)
        let headerFP = headerFingerprint(forOrderedHeaders: ordered)
        let recentWindow = Array(ordered.suffix(ProactiveOnDeviceTriageEngine.maxMessagesPerThread))
        let bodyRev = bodyRevision(for: recentWindow, cachedBodies: cachedBodies)
        return "\(headerFP)|b:\(bodyRev)"
    }

    /// Trash and Spam folders are always excluded from proactive triage.
    public nonisolated static func isExcludedFolder(_ folder: Folder?) -> Bool {
        guard let role = folder?.role else { return false }
        return role == .trash || role == .spam
    }

    /// Returns a cached insight only if its full fingerprint (headers + body revision) matches.
    public func cachedInsight(
        for key: String,
        sourceFingerprint: String
    ) -> ThreadTriageInsight? {
        guard let existing = insightsByKey[key],
              existing.sourceFingerprint == sourceFingerprint
        else { return nil }
        touchLRU(key)
        return existing
    }

    /// Returns a cached insight whose header fingerprint matches, allowing list rows and
    /// headers to display upgraded full-body summaries synchronously while still invalidating
    /// immediately whenever a message is added or updated.
    public func cachedInsight(
        for key: String,
        matchingHeaderFingerprint headerFingerprint: String
    ) -> ThreadTriageInsight? {
        guard let existing = insightsByKey[key] else { return nil }
        if let storedHeaderFP = headerFingerprintByKey[key] {
            guard storedHeaderFP == headerFingerprint else { return nil }
        } else {
            guard existing.sourceFingerprint == headerFingerprint
                || existing.sourceFingerprint.hasPrefix("\(headerFingerprint)|b:")
            else { return nil }
        }
        touchLRU(key)
        return existing
    }

    /// Cancels all active triage tasks and wipes cached insights immediately.
    public func clearAll() {
        for entry in activeTasksByKey.values {
            entry.task.cancel()
        }
        activeTasksByKey.removeAll()
        if !insightsByKey.isEmpty {
            insightsByKey.removeAll()
        }
        headerFingerprintByKey.removeAll()
        lruOrder.removeAll()
        let engine = engine
        Task {
            await engine.clearCache()
        }
    }

    /// Seeds a cached insight directly for deterministic tests and snapshots.
    func seed(
        _ insight: ThreadTriageInsight,
        for key: String,
        headerFingerprint: String? = nil
    ) {
        storeInsight(
            insight,
            for: key,
            headerFingerprint: headerFingerprint ?? insight.sourceFingerprint
        )
    }

    /// Builds a cache-only, sign-in-code-redacted input for `ProactiveOnDeviceTriageEngine`.
    public nonisolated static func makeInput(
        accountID: BrevAccount.ID,
        headers: [MessageHeader],
        cachedBodies: [MessageHeader.ID: MessageBody] = [:],
        isExcludedFolder: Bool
    ) -> ProactiveTriageThreadInput? {
        let ordered = sortedChronologically(headers)
        guard let latest = ordered.last else { return nil }
        let key = cacheKey(accountID: accountID, header: latest)
        let fingerprint = sourceFingerprint(for: ordered, cachedBodies: cachedBodies)
        let messages = ordered.map { header -> ProactiveTriageMessageInput in
            let senderName = header.from.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let sender = senderName.isEmpty ? header.from.email : "\(senderName) <\(header.from.email)>"
            let rawText = cachedPlainText(for: cachedBodies[header.id], fallbackSnippet: header.snippet)
            return ProactiveTriageMessageInput(
                sender: sender,
                subject: redactSignInCredentials(header.subject),
                text: redactSignInCredentials(rawText),
                date: header.date,
                isRead: header.isRead
            )
        }
        return ProactiveTriageThreadInput(
            cacheKey: key,
            sourceFingerprint: fingerprint,
            isExcludedFolder: isExcludedFolder,
            messages: messages
        )
    }

    /// Computes or returns a cached on-device triage insight for one thread if strictly eligible.
    @discardableResult
    public func triageIfEligible(
        accountID: BrevAccount.ID,
        headers: [MessageHeader],
        folder: Folder?,
        allFolders: [Folder] = [],
        settings: AIWriterSettings,
        liveSettingsProvider: (() -> AIWriterSettings)? = nil,
        backend: (any AIBackend)?,
        cachedBodyProvider: (any CachedMessageBodyProviding)? = nil,
        preloadedPlainTextByID: [MessageHeader.ID: String] = [:],
        sourceID: MailSourceID? = nil
    ) async -> ThreadTriageInsight? {
        let currentSettings = resolveLiveSettings(
            fallback: settings,
            overrideProvider: liveSettingsProvider
        )
        guard currentSettings.isProactiveOnDeviceTriageAvailable else {
            clearAll()
            return nil
        }
        guard let backend, backend.isOnDeviceZeroNetwork else {
            return nil
        }

        let eligible = Self.eligibleHeaders(from: headers, folder: folder, allFolders: allFolders)
        let ordered = Self.sortedChronologically(eligible)
        guard let latest = ordered.last else {
            return nil
        }

        let key = Self.cacheKey(accountID: accountID, header: latest)
        let headerFP = Self.headerFingerprint(forOrderedHeaders: ordered)
        let recentWindow = Array(ordered.suffix(ProactiveOnDeviceTriageEngine.maxMessagesPerThread))

        var cachedBodies: [MessageHeader.ID: MessageBody] = [:]
        for (id, plain) in preloadedPlainTextByID where !plain.isEmpty {
            cachedBodies[id] = MessageBody(messageID: id, plainText: plain)
        }
        if let cachedBodyProvider {
            for header in recentWindow where cachedBodies[header.id] == nil {
                if Task.isCancelled { return nil }
                if let body = await cachedBodyProvider.cachedBody(for: header.id, sourceID: sourceID) {
                    cachedBodies[header.id] = body
                }
            }
        }

        let afterReadSettings = resolveLiveSettings(
            fallback: settings,
            overrideProvider: liveSettingsProvider
        )
        guard !Task.isCancelled, afterReadSettings.isProactiveOnDeviceTriageAvailable else {
            if !afterReadSettings.isProactiveOnDeviceTriageAvailable {
                clearAll()
            }
            return nil
        }

        let fullFingerprint = Self.sourceFingerprint(for: ordered, cachedBodies: cachedBodies)
        if let existing = cachedInsight(for: key, sourceFingerprint: fullFingerprint) {
            return existing
        }

        guard let input = Self.makeInput(
            accountID: accountID,
            headers: ordered,
            cachedBodies: cachedBodies,
            isExcludedFolder: false
        ) else {
            return nil
        }

        let insight = await engine.insight(for: input, settings: afterReadSettings, backend: backend)
        let finalSettings = resolveLiveSettings(
            fallback: settings,
            overrideProvider: liveSettingsProvider
        )
        guard !Task.isCancelled, finalSettings.isProactiveOnDeviceTriageAvailable else {
            if !finalSettings.isProactiveOnDeviceTriageAvailable {
                clearAll()
            }
            return nil
        }
        if let insight {
            storeInsight(insight, for: key, headerFingerprint: headerFP)
        }
        return insight
    }

    /// Enqueues a bounded window of visible threads for background on-device triage.
    public func scheduleVisibleThreads(
        accountID: BrevAccount.ID,
        threadGroups: [[MessageHeader]],
        folder: Folder?,
        allFolders: [Folder] = [],
        settings: AIWriterSettings,
        liveSettingsProvider: (() -> AIWriterSettings)? = nil,
        backend: (any AIBackend)?,
        cachedBodyProvider: (any CachedMessageBodyProviding)? = nil,
        sourceID: MailSourceID? = nil,
        maxThreads: Int = ProactiveTriageVisibleWindow.defaultMaxBatchSize
    ) {
        let currentSettings = resolveLiveSettings(
            fallback: settings,
            overrideProvider: liveSettingsProvider
        )
        guard currentSettings.isProactiveOnDeviceTriageAvailable else {
            clearAll()
            return
        }
        guard let backend, backend.isOnDeviceZeroNetwork else {
            return
        }
        guard !Self.isExcludedFolder(folder) else {
            return
        }

        for group in threadGroups.prefix(max(0, maxThreads)) {
            let eligible = Self.eligibleHeaders(from: group, folder: folder, allFolders: allFolders)
            let ordered = Self.sortedChronologically(eligible)
            guard let latest = ordered.last else { continue }
            let key = Self.cacheKey(accountID: accountID, header: latest)
            let headerFP = Self.headerFingerprint(forOrderedHeaders: ordered)
            if cachedInsight(for: key, matchingHeaderFingerprint: headerFP) != nil {
                continue
            }
            if let existing = activeTasksByKey[key] {
                if existing.fingerprint == headerFP {
                    continue
                }
                existing.task.cancel()
                activeTasksByKey.removeValue(forKey: key)
            }

            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    if self.activeTasksByKey[key]?.fingerprint == headerFP {
                        self.activeTasksByKey.removeValue(forKey: key)
                    }
                }
                guard !Task.isCancelled else { return }
                let liveSettings = resolveLiveSettings(
                    fallback: settings,
                    overrideProvider: liveSettingsProvider
                )
                guard liveSettings.isProactiveOnDeviceTriageAvailable else {
                    clearAll()
                    return
                }
                _ = await triageIfEligible(
                    accountID: accountID,
                    headers: ordered,
                    folder: folder,
                    allFolders: allFolders,
                    settings: liveSettings,
                    liveSettingsProvider: liveSettingsProvider,
                    backend: backend,
                    cachedBodyProvider: cachedBodyProvider,
                    sourceID: sourceID
                )
            }
            activeTasksByKey[key] = (fingerprint: headerFP, task: task)
        }
    }

    // MARK: - LRU cache management

    private func storeInsight(
        _ insight: ThreadTriageInsight,
        for key: String,
        headerFingerprint: String
    ) {
        insightsByKey[key] = insight
        headerFingerprintByKey[key] = headerFingerprint
        touchLRU(key)
        while lruOrder.count > maxCacheEntries {
            let evicted = lruOrder.removeFirst()
            insightsByKey.removeValue(forKey: evicted)
            headerFingerprintByKey.removeValue(forKey: evicted)
        }
    }

    private func touchLRU(_ key: String) {
        if let index = lruOrder.firstIndex(of: key) {
            lruOrder.remove(at: index)
        }
        lruOrder.append(key)
    }

    // MARK: - Helpers

    private nonisolated static func cachedPlainText(
        for body: MessageBody?,
        fallbackSnippet: String
    ) -> String {
        if let plain = body?.plainText?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return plain
        }
        if let html = body?.html?.trimmingCharacters(in: .whitespacesAndNewlines), !html.isEmpty {
            return html
                .replacingOccurrences(of: #"(?is)<(script|style)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fallbackSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func redactSignInCredentials(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        if SignInCodeDetector.detect(in: text) != nil {
            return ProactiveTriageRedactor.placeholder
        }
        return ProactiveTriageRedactor.redactSignInCodes(text)
    }

    private nonisolated static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }
}
