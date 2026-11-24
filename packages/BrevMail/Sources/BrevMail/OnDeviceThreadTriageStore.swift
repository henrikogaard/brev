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

/// Main-actor observable local cache and scheduler for opt-in proactive on-device triage.
///
/// Enforces two hard privacy gates before reading cached bodies or running inference:
/// 1. `AIWriterSettings.isProactiveOnDeviceTriageAvailable` must be `true`, and
/// 2. the account's resolved `AIBackend.isOnDeviceZeroNetwork` must be `true`.
///
/// Never triggers network body fetches; reads strictly from already-loaded headers and
/// optional `CachedMessageBodyProviding` caches.
@MainActor
@Observable
public final class OnDeviceThreadTriageStore {
    /// Cached insights keyed by `cacheKey(accountID:header:)`.
    public private(set) var insightsByKey: [String: ThreadTriageInsight] = [:]

    @ObservationIgnored
    private let engine: ProactiveOnDeviceTriageEngine

    @ObservationIgnored
    private var activeTasksByKey: [String: (fingerprint: String, task: Task<Void, Never>)] = [:]

    /// Creates a store backed by the given proactive on-device triage engine.
    public init(engine: ProactiveOnDeviceTriageEngine = ProactiveOnDeviceTriageEngine()) {
        self.engine = engine
    }

    /// Account-scoped cache key preventing collisions across accounts.
    public static func cacheKey(
        accountID: BrevAccount.ID,
        header: MessageHeader
    ) -> String {
        let threadKey = header.threadID.isEmpty ? header.id : header.threadID
        return "\(accountID)|\(threadKey)"
    }

    /// Deterministic fingerprint invalidated when messages are added or updated in a thread.
    public static func sourceFingerprint(for headers: [MessageHeader]) -> String {
        let ordered = headers.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id < $1.id
        }
        return ordered
            .map { "\($0.id)|\($0.date.timeIntervalSinceReferenceDate)|\($0.subject.count)|\($0.snippet.count)" }
            .joined(separator: ";")
    }

    /// Trash and Spam folders are always excluded from proactive triage.
    public static func isExcludedFolder(_ folder: Folder?) -> Bool {
        guard let role = folder?.role else { return false }
        return role == .trash || role == .spam
    }

    /// Returns a cached insight only if its fingerprint matches the current thread snapshot.
    public func cachedInsight(
        for key: String,
        sourceFingerprint: String
    ) -> ThreadTriageInsight? {
        guard let existing = insightsByKey[key],
              existing.sourceFingerprint == sourceFingerprint
        else { return nil }
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
        let engine = engine
        Task {
            await engine.clearCache()
        }
    }

    /// Seeds a cached insight directly for deterministic tests and snapshots.
    func seed(_ insight: ThreadTriageInsight, for key: String) {
        insightsByKey[key] = insight
    }

    /// Builds a cache-only, sign-in-code-redacted input for `ProactiveOnDeviceTriageEngine`.
    public static func makeInput(
        accountID: BrevAccount.ID,
        headers: [MessageHeader],
        cachedBodies: [MessageHeader.ID: MessageBody] = [:],
        isExcludedFolder: Bool
    ) -> ProactiveTriageThreadInput? {
        guard let latest = headers.last else { return nil }
        let ordered = headers.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id < $1.id
        }
        let key = cacheKey(accountID: accountID, header: latest)
        let fingerprint = sourceFingerprint(for: ordered)
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
        settings: AIWriterSettings,
        backend: (any AIBackend)?,
        cachedBodyProvider: (any CachedMessageBodyProviding)? = nil,
        preloadedPlainTextByID: [MessageHeader.ID: String] = [:],
        sourceID: MailSourceID? = nil
    ) async -> ThreadTriageInsight? {
        guard settings.isProactiveOnDeviceTriageAvailable else {
            clearAll()
            return nil
        }
        guard let backend, backend.isOnDeviceZeroNetwork else {
            return nil
        }
        guard !Self.isExcludedFolder(folder), let latest = headers.last else {
            return nil
        }

        let key = Self.cacheKey(accountID: accountID, header: latest)
        let fingerprint = Self.sourceFingerprint(for: headers)
        if let existing = cachedInsight(for: key, sourceFingerprint: fingerprint) {
            return existing
        }

        var cachedBodies: [MessageHeader.ID: MessageBody] = [:]
        for (id, plain) in preloadedPlainTextByID where !plain.isEmpty {
            cachedBodies[id] = MessageBody(messageID: id, plainText: plain)
        }
        if let cachedBodyProvider {
            for header in headers.suffix(3) where cachedBodies[header.id] == nil {
                if let body = await cachedBodyProvider.cachedBody(for: header.id, sourceID: sourceID) {
                    cachedBodies[header.id] = body
                }
            }
        }

        guard let input = Self.makeInput(
            accountID: accountID,
            headers: headers,
            cachedBodies: cachedBodies,
            isExcludedFolder: Self.isExcludedFolder(folder)
        ) else {
            return nil
        }

        let insight = await engine.insight(for: input, settings: settings, backend: backend)
        guard settings.isProactiveOnDeviceTriageAvailable else {
            clearAll()
            return nil
        }
        if let insight {
            insightsByKey[key] = insight
        }
        return insight
    }

    /// Enqueues a bounded window of visible threads for background on-device triage.
    public func scheduleVisibleThreads(
        accountID: BrevAccount.ID,
        threadGroups: [[MessageHeader]],
        folder: Folder?,
        settings: AIWriterSettings,
        backend: (any AIBackend)?,
        cachedBodyProvider: (any CachedMessageBodyProviding)? = nil,
        sourceID: MailSourceID? = nil,
        maxThreads: Int = 15
    ) {
        guard settings.isProactiveOnDeviceTriageAvailable else {
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
            guard let latest = group.last else { continue }
            let key = Self.cacheKey(accountID: accountID, header: latest)
            let fingerprint = Self.sourceFingerprint(for: group)
            if cachedInsight(for: key, sourceFingerprint: fingerprint) != nil {
                continue
            }
            if let existing = activeTasksByKey[key] {
                if existing.fingerprint == fingerprint {
                    continue
                }
                existing.task.cancel()
                activeTasksByKey.removeValue(forKey: key)
            }

            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    if self.activeTasksByKey[key]?.fingerprint == fingerprint {
                        self.activeTasksByKey.removeValue(forKey: key)
                    }
                }
                _ = await triageIfEligible(
                    accountID: accountID,
                    headers: group,
                    folder: folder,
                    settings: settings,
                    backend: backend,
                    cachedBodyProvider: cachedBodyProvider,
                    sourceID: sourceID
                )
            }
            activeTasksByKey[key] = (fingerprint: fingerprint, task: task)
        }
    }

    // MARK: - Helpers

    private static func cachedPlainText(
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

    private static func redactSignInCredentials(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        if SignInCodeDetector.detect(in: text) != nil {
            return ProactiveTriageRedactor.placeholder
        }
        return ProactiveTriageRedactor.redactSignInCodes(text)
    }
}
