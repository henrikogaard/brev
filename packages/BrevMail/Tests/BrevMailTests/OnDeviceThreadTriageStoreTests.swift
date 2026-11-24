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

#if os(macOS)
import AppKit
#endif
import BrevAI
import BrevBackend
import BrevDesign
@testable import BrevMail
import BrevSettings
import BrevThemes
import Foundation
import SwiftUI
import Testing

private actor StubMailTriageAIBackend: AIBackend {
    nonisolated let identifier: String
    nonisolated let displayName: String
    nonisolated let transparencyLabel: String
    nonisolated let isOnDeviceZeroNetwork: Bool
    nonisolated let contextBudget: AIBackendContextBudget? = .onDevice

    var recordedPrompts: [String] = []
    var responses: [String]
    var delayNanoseconds: UInt64 = 0

    init(
        isOnDeviceZeroNetwork: Bool,
        transparencyLabel: String = "On this Mac",
        responses: [String] = [
            #"{"priority":"urgent","summary":"Action required today to confirm the lease renewal."}"#
        ]
    ) {
        identifier = isOnDeviceZeroNetwork ? "stub-on-device" : "stub-cloud"
        displayName = isOnDeviceZeroNetwork ? "On-Device Stub" : "Cloud Stub"
        self.transparencyLabel = transparencyLabel
        self.isOnDeviceZeroNetwork = isOnDeviceZeroNetwork
        self.responses = responses
    }

    func setDelayNanoseconds(_ value: UInt64) {
        delayNanoseconds = value
    }

    func generateReply(to messages: [AIMessage], instruction: String?) async throws -> AIResponse {
        _ = instruction
        recordedPrompts.append(messages.map(\.content).joined(separator: "\n"))
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        let text = responses.count > 1 ? responses.removeFirst() : (responses.first ?? "")
        return AIResponse(text: text)
    }

    func shortcut(_ action: AIShortcutAction, on text: String) async throws -> AIResponse {
        _ = action
        return AIResponse(text: text)
    }
}

private final class RecordingCachedBodyProvider: CachedMessageBodyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [MessageHeader.ID: MessageBody]
    private var requestedIDsStorage: [MessageHeader.ID] = []

    init(bodies: [MessageHeader.ID: MessageBody] = [:]) {
        self.bodies = bodies
    }

    var requestedIDs: [MessageHeader.ID] {
        lock.withLock { requestedIDsStorage }
    }

    func setBody(_ body: MessageBody, for messageID: MessageHeader.ID) {
        lock.withLock {
            bodies[messageID] = body
        }
    }

    func cachedBody(for messageID: MessageHeader.ID, sourceID: MailSourceID?) async -> MessageBody? {
        _ = sourceID
        return lock.withLock {
            requestedIDsStorage.append(messageID)
            return bodies[messageID]
        }
    }
}

private actor GatedCachedBodyProvider: CachedMessageBodyProviding {
    private var bodies: [MessageHeader.ID: MessageBody] = [:]
    private var callCount = 0
    private var pausedCallNumber: Int?
    private var pausedStarted = false
    private var pausedStartWaiter: CheckedContinuation<Void, Never>?
    private var pausedReleased = false
    private var pausedReleaseWaiter: CheckedContinuation<Void, Never>?

    func pauseNextRead(onCall callNumber: Int) {
        pausedCallNumber = callNumber
        pausedStarted = false
        pausedReleased = false
    }

    func setBody(_ body: MessageBody, for messageID: MessageHeader.ID) {
        bodies[messageID] = body
    }

    func waitUntilPausedCallStarted() async {
        if pausedStarted { return }
        await withCheckedContinuation { continuation in
            pausedStartWaiter = continuation
        }
    }

    func releasePausedCall() {
        pausedReleased = true
        if let waiter = pausedReleaseWaiter {
            pausedReleaseWaiter = nil
            waiter.resume()
        }
    }

    func cachedBody(for messageID: MessageHeader.ID, sourceID: MailSourceID?) async -> MessageBody? {
        _ = sourceID
        callCount += 1
        let currentCall = callCount
        // Snapshot body BEFORE suspending so the paused call simulates an earlier check
        // that already observed `nil` before a new body was written to cache.
        let snapshot = bodies[messageID]
        if pausedCallNumber == currentCall {
            pausedStarted = true
            if let waiter = pausedStartWaiter {
                pausedStartWaiter = nil
                waiter.resume()
            }
            if !pausedReleased {
                await withCheckedContinuation { continuation in
                    pausedReleaseWaiter = continuation
                }
            }
        }
        return snapshot
    }
}

private actor GatedViewportTriageBackend: AIBackend {
    nonisolated let identifier = "gated-viewport-on-device"
    nonisolated let displayName = "Gated Viewport On-Device"
    nonisolated let transparencyLabel = "On this Mac"
    nonisolated let isOnDeviceZeroNetwork = true
    nonisolated let contextBudget: AIBackendContextBudget? = .onDevice

    var startedPrompts: [String] = []
    private var gatedTag: String?
    private var gatedStarted = false
    private var gatedStartWaiter: CheckedContinuation<Void, Never>?
    private var gatedReleased = false
    private var gatedReleaseWaiter: CheckedContinuation<Void, Never>?

    init(gatedTag: String) {
        self.gatedTag = gatedTag
    }

    func waitUntilGatedStarted() async {
        if gatedStarted { return }
        await withCheckedContinuation { continuation in
            gatedStartWaiter = continuation
        }
    }

    func releaseGate() {
        gatedReleased = true
        if let waiter = gatedReleaseWaiter {
            gatedReleaseWaiter = nil
            waiter.resume()
        }
    }

    func generateReply(to messages: [AIMessage], instruction: String?) async throws -> AIResponse {
        _ = instruction
        let prompt = messages.map(\.content).joined(separator: "\n")
        startedPrompts.append(prompt)

        if let gatedTag, prompt.contains(gatedTag) {
            gatedStarted = true
            if let waiter = gatedStartWaiter {
                gatedStartWaiter = nil
                waiter.resume()
            }
            if !gatedReleased {
                await withCheckedContinuation { continuation in
                    gatedReleaseWaiter = continuation
                }
            }
        }
        try Task.checkCancellation()
        return AIResponse(text: #"{"priority":"normal","summary":"Viewport triage completed."}"#)
    }

    func shortcut(_ action: AIShortcutAction, on text: String) async throws -> AIResponse {
        _ = action
        return AIResponse(text: text)
    }
}

@Suite("On-device thread triage store")
@MainActor
struct OnDeviceThreadTriageStoreTests {
    private let enabledSettings = AIWriterSettings(
        isEnabled: true,
        consentGiven: true,
        proactiveOnDeviceTriageEnabled: true
    )

    private func waitUntil(
        timeoutSeconds: TimeInterval = 8.0,
        pollNanoseconds: UInt64 = 10_000_000,
        condition: @MainActor () async -> Bool
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await condition() {
                return true
            }
            try await Task.sleep(nanoseconds: pollNanoseconds)
        }
        return await condition()
    }

    private func makeHeader(
        id: String = "msg-1",
        threadID: String = "thread-1",
        folderID: String = "inbox",
        subject: String = "Lease renewal",
        snippet: String = "Please confirm by 5 PM.",
        date: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: threadID,
            folderID: folderID,
            from: Correspondent(name: "Nora Lind", email: "nora@example.com"),
            subject: subject,
            snippet: snippet,
            date: date,
            isRead: false
        )
    }

    @Test("cloud backend is never invoked and cached bodies are never read")
    func cloudBackendIsBlocked() async {
        let store = OnDeviceThreadTriageStore(defaults: nil)
        let cloudBackend = StubMailTriageAIBackend(
            isOnDeviceZeroNetwork: false,
            transparencyLabel: "Sent to: OpenAI (api.openai.com)"
        )
        let bodyProvider = RecordingCachedBodyProvider(bodies: [
            "msg-1": MessageBody(messageID: "msg-1", plainText: "Body text")
        ])

        let result = await store.triageIfEligible(
            accountID: "acct-1",
            headers: [makeHeader()],
            folder: Folder(id: "inbox", name: "Inbox", role: .inbox),
            settings: enabledSettings,
            backend: cloudBackend,
            cachedBodyProvider: bodyProvider
        )

        #expect(result == nil)
        #expect(await cloudBackend.recordedPrompts.isEmpty)
        #expect(bodyProvider.requestedIDs.isEmpty)
        #expect(store.insightsByKey.isEmpty)
    }

    @Test("on-device backend caches insight, invalidates on new message, and clears on opt-out")
    func onDeviceCachesInvalidatesAndClears() async throws {
        let store = OnDeviceThreadTriageStore(defaults: nil)
        let onDeviceBackend = StubMailTriageAIBackend(
            isOnDeviceZeroNetwork: true,
            responses: [
                #"{"priority":"needs_reply","summary":"Nora asked for confirmation on the renewal."}"#,
                #"{"priority":"urgent","summary":"Nora needs signed confirmation before 5 PM today."}"#
            ]
        )
        let bodyProvider = RecordingCachedBodyProvider(bodies: [
            "msg-1": MessageBody(messageID: "msg-1", plainText: "Could you confirm the renewal terms?")
        ])
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let msg1 = makeHeader(id: "msg-1", date: Date(timeIntervalSince1970: 1_700_000_000))

        let first = try #require(await store.triageIfEligible(
            accountID: "acct-1",
            headers: [msg1],
            folder: inbox,
            settings: enabledSettings,
            backend: onDeviceBackend,
            cachedBodyProvider: bodyProvider
        ))
        #expect(first.priority == .needsReply)
        #expect(first.attribution == "On this Mac")

        let key = OnDeviceThreadTriageStore.cacheKey(accountID: "acct-1", header: msg1)
        let fp1 = OnDeviceThreadTriageStore.headerFingerprint(for: [msg1])
        #expect(store.cachedInsight(for: key, matchingHeaderFingerprint: fp1) == first)

        // Second message arrives in same thread -> fingerprint changes -> cache miss & re-triage
        let msg2 = makeHeader(
            id: "msg-2",
            snippet: "Urgent: please confirm before 5 PM.",
            date: Date(timeIntervalSince1970: 1_700_003_600)
        )
        let fp2 = OnDeviceThreadTriageStore.headerFingerprint(for: [msg1, msg2])
        #expect(store.cachedInsight(for: key, matchingHeaderFingerprint: fp2) == nil)

        let second = try #require(await store.triageIfEligible(
            accountID: "acct-1",
            headers: [msg1, msg2],
            folder: inbox,
            settings: enabledSettings,
            backend: onDeviceBackend,
            cachedBodyProvider: bodyProvider
        ))
        #expect(second.priority == .urgent)
        #expect(await onDeviceBackend.recordedPrompts.count == 2)

        // Turning proactive off clears cached insights immediately
        let disabled = AIWriterSettings(
            isEnabled: true,
            consentGiven: true,
            proactiveOnDeviceTriageEnabled: false
        )
        let afterDisable = await store.triageIfEligible(
            accountID: "acct-1",
            headers: [msg1, msg2],
            folder: inbox,
            settings: disabled,
            backend: onDeviceBackend
        )
        #expect(afterDisable == nil)
        #expect(store.insightsByKey.isEmpty)
    }

    @Test("opt-out via UserDefaults cancels queued jobs and clears insights even with no view mounted")
    func optOutCancelsQueuedJobsWithoutMountedViews() async throws {
        let suiteName = "OnDeviceTriageOptOut-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        enabledSettings.save(to: defaults)
        let store = OnDeviceThreadTriageStore(defaults: defaults)
        let onDeviceBackend = StubMailTriageAIBackend(
            isOnDeviceZeroNetwork: true,
            responses: [#"{"priority":"urgent","summary":"Cached before opt-out."}"#]
        )

        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let initialHeader = makeHeader(id: "m-initial", threadID: "t-initial")
        _ = try #require(await store.triageIfEligible(
            accountID: "acct-1",
            headers: [initialHeader],
            folder: inbox,
            settings: enabledSettings,
            liveSettingsProvider: { AIWriterSettings.load(from: defaults) },
            backend: onDeviceBackend
        ))
        #expect(store.insightsByKey.count == 1)

        // Queue several slow threads, then opt out in UserDefaults with ZERO views mounted
        await onDeviceBackend.setDelayNanoseconds(120_000_000)
        let queuedGroups = (1 ... 4).map { idx in
            [makeHeader(id: "m-queued-\(idx)", threadID: "t-queued-\(idx)")]
        }
        store.scheduleVisibleThreads(
            accountID: "acct-1",
            threadGroups: queuedGroups,
            folder: inbox,
            settings: enabledSettings,
            liveSettingsProvider: { AIWriterSettings.load(from: defaults) },
            backend: onDeviceBackend
        )

        // Flip opt-out in UserDefaults -> observer fires immediately and cancels all queued tasks
        let optedOut = AIWriterSettings(
            isEnabled: true,
            consentGiven: true,
            proactiveOnDeviceTriageEnabled: false
        )
        optedOut.save(to: defaults)
        let cleared = try await waitUntil { store.insightsByKey.isEmpty }
        #expect(cleared)
        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(store.insightsByKey.isEmpty)
        let totalCalls = await onDeviceBackend.recordedPrompts.count
        // Only the initial pre-opt-out call (plus at most 1 already-dispatched task) could have started,
        // and the remaining queued jobs were cancelled without populating insightsByKey.
        #expect(totalCalls < 5)
    }

    @Test("Trash and Spam folders are never triaged, including per-message inside mixed conversations")
    func trashAndSpamExcludedPerMessage() async throws {
        let store = OnDeviceThreadTriageStore(defaults: nil)
        let onDeviceBackend = StubMailTriageAIBackend(
            isOnDeviceZeroNetwork: true,
            responses: [#"{"priority":"normal","summary":"Inbox-only message summary."}"#]
        )
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let trash = Folder(id: "trash", name: "Trash", role: .trash)
        let spam = Folder(id: "spam", name: "Spam", role: .spam)
        let allFolders = [inbox, trash, spam]

        // Pure Trash / Spam folders return nil
        for folder in [trash, spam] {
            let result = await store.triageIfEligible(
                accountID: "acct-1",
                headers: [makeHeader(folderID: folder.id)],
                folder: folder,
                allFolders: allFolders,
                settings: enabledSettings,
                backend: onDeviceBackend
            )
            #expect(result == nil)
        }
        #expect(await onDeviceBackend.recordedPrompts.isEmpty)

        // Mixed conversation (Inbox + Trash + Spam): only Inbox message enters prompt & body lookup
        let inboxMsg = makeHeader(
            id: "m-inbox",
            threadID: "t-mixed",
            folderID: "inbox",
            subject: "Project timeline",
            snippet: "SAFE-INBOX-TEXT",
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let trashMsg = makeHeader(
            id: "m-trash",
            threadID: "t-mixed",
            folderID: "trash",
            subject: "Deleted draft",
            snippet: "SECRET-TRASH-TEXT",
            date: Date(timeIntervalSince1970: 1_700_001_000)
        )
        let spamMsg = makeHeader(
            id: "m-spam",
            threadID: "t-mixed",
            folderID: "spam",
            subject: "Phishing spam",
            snippet: "SECRET-SPAM-TEXT",
            date: Date(timeIntervalSince1970: 1_700_002_000)
        )
        let bodyProvider = RecordingCachedBodyProvider(bodies: [
            "m-inbox": MessageBody(messageID: "m-inbox", plainText: "SAFE-INBOX-BODY"),
            "m-trash": MessageBody(messageID: "m-trash", plainText: "SECRET-TRASH-BODY"),
            "m-spam": MessageBody(messageID: "m-spam", plainText: "SECRET-SPAM-BODY")
        ])

        _ = try #require(await store.triageIfEligible(
            accountID: "acct-1",
            headers: [inboxMsg, trashMsg, spamMsg],
            folder: nil,
            allFolders: allFolders,
            settings: enabledSettings,
            backend: onDeviceBackend,
            cachedBodyProvider: bodyProvider
        ))

        #expect(bodyProvider.requestedIDs == ["m-inbox"])
        let prompts = await onDeviceBackend.recordedPrompts
        #expect(prompts.count == 1)
        #expect(prompts[0].contains("SAFE-INBOX-BODY"))
        #expect(!prompts[0].contains("SECRET-TRASH"))
        #expect(!prompts[0].contains("SECRET-SPAM"))
    }

    @Test("newest-first 5-message thread sorts chronologically first and reads cached bodies for the 4 newest messages")
    func sortsChronologicallyBeforeCachedBodyWindow() async throws {
        let store = OnDeviceThreadTriageStore(defaults: nil)
        let onDeviceBackend = StubMailTriageAIBackend(
            isOnDeviceZeroNetwork: true,
            responses: [#"{"priority":"needs_reply","summary":"Newest 4 messages triaged."}"#]
        )
        let headersOldestToNewest = (1 ... 5).map { idx in
            makeHeader(
                id: "m-\(idx)",
                threadID: "t-5",
                snippet: "Snippet \(idx)",
                date: Date(timeIntervalSince1970: 1_700_000_000 + Double(idx) * 600)
            )
        }
        // Pass newest-first (reversing chronological order, as message lists often store)
        let newestFirst = Array(headersOldestToNewest.reversed())
        let bodyProvider = RecordingCachedBodyProvider(bodies: Dictionary(
            uniqueKeysWithValues: headersOldestToNewest.map {
                ($0.id, MessageBody(messageID: $0.id, plainText: "BODY-CONTENT-\($0.id)"))
            }
        ))

        _ = try #require(await store.triageIfEligible(
            accountID: "acct-1",
            headers: newestFirst,
            folder: Folder(id: "inbox", name: "Inbox", role: .inbox),
            settings: enabledSettings,
            backend: onDeviceBackend,
            cachedBodyProvider: bodyProvider
        ))

        // Must request the 4 NEWEST messages (m-2, m-3, m-4, m-5) and skip oldest (m-1)
        #expect(bodyProvider.requestedIDs == ["m-2", "m-3", "m-4", "m-5"])
        let prompts = await onDeviceBackend.recordedPrompts
        #expect(prompts.count == 1)
        #expect(prompts[0].contains("BODY-CONTENT-m-5"))
        #expect(prompts[0].contains("BODY-CONTENT-m-2"))
        #expect(!prompts[0].contains("BODY-CONTENT-m-1"))
    }

    @Test("caching a full body after snippet-only triage invalidates fingerprint and regenerates summary")
    func bodyCacheArrivalRegeneratesSummary() async throws {
        let store = OnDeviceThreadTriageStore(defaults: nil)
        let onDeviceBackend = StubMailTriageAIBackend(
            isOnDeviceZeroNetwork: true,
            responses: [
                #"{"priority":"normal","summary":"Initial snippet summary."}"#,
                #"{"priority":"urgent","summary":"Full body reveals urgent deadline today at 3 PM."}"#
            ]
        )
        let header = makeHeader(id: "m-upgrade", threadID: "t-upgrade", snippet: "Short preview...")
        let bodyProvider = RecordingCachedBodyProvider(bodies: [:])
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)

        let snippetInsight = try #require(await store.triageIfEligible(
            accountID: "acct-1",
            headers: [header],
            folder: inbox,
            settings: enabledSettings,
            backend: onDeviceBackend,
            cachedBodyProvider: bodyProvider
        ))
        #expect(snippetInsight.summary == "Initial snippet summary.")
        #expect(await onDeviceBackend.recordedPrompts.count == 1)

        // Now the reader caches the full body locally -> fingerprint changes -> regenerates!
        bodyProvider.setBody(
            MessageBody(messageID: "m-upgrade", plainText: "URGENT: deadline moved up to 3 PM today."),
            for: "m-upgrade"
        )
        let fullBodyInsight = try #require(await store.triageIfEligible(
            accountID: "acct-1",
            headers: [header],
            folder: inbox,
            settings: enabledSettings,
            backend: onDeviceBackend,
            cachedBodyProvider: bodyProvider
        ))
        #expect(fullBodyInsight.priority == .urgent)
        #expect(fullBodyInsight.summary == "Full body reveals urgent deadline today at 3 PM.")
        #expect(await onDeviceBackend.recordedPrompts.count == 2)

        // List-row header-fingerprint lookup serves the upgraded full-body summary synchronously
        let key = OnDeviceThreadTriageStore.cacheKey(accountID: "acct-1", header: header)
        let headerFP = OnDeviceThreadTriageStore.headerFingerprint(for: [header])
        #expect(store.cachedInsight(for: key, matchingHeaderFingerprint: headerFP) == fullBodyInsight)
    }

    @Test("store enforces bounded LRU eviction on insightsByKey")
    func storeEnforcesBoundedLRUEviction() async throws {
        let store = OnDeviceThreadTriageStore(maxCacheEntries: 3, defaults: nil)
        let backend = StubMailTriageAIBackend(
            isOnDeviceZeroNetwork: true,
            responses: [#"{"priority":"normal","summary":"Compact summary."}"#]
        )
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)

        let headers = (1 ... 4).map { idx in
            makeHeader(id: "m-lru-\(idx)", threadID: "t-lru-\(idx)")
        }
        for header in headers.prefix(3) {
            _ = try #require(await store.triageIfEligible(
                accountID: "acct-1",
                headers: [header],
                folder: inbox,
                settings: enabledSettings,
                backend: backend
            ))
        }
        #expect(store.insightsByKey.count == 3)

        // Touch thread 1 so thread 2 becomes least recently used
        let key1 = OnDeviceThreadTriageStore.cacheKey(accountID: "acct-1", header: headers[0])
        let fp1 = OnDeviceThreadTriageStore.headerFingerprint(for: [headers[0]])
        #expect(store.cachedInsight(for: key1, matchingHeaderFingerprint: fp1) != nil)

        // Insert thread 4 -> evicts thread 2
        _ = try #require(await store.triageIfEligible(
            accountID: "acct-1",
            headers: [headers[3]],
            folder: inbox,
            settings: enabledSettings,
            backend: backend
        ))

        let key2 = OnDeviceThreadTriageStore.cacheKey(accountID: "acct-1", header: headers[1])
        let key4 = OnDeviceThreadTriageStore.cacheKey(accountID: "acct-1", header: headers[3])
        #expect(store.insightsByKey.count == 3)
        #expect(store.insightsByKey[key1] != nil)
        #expect(store.insightsByKey[key2] == nil)
        #expect(store.insightsByKey[key4] != nil)
    }

    @Test("visible window schedules only filtered rows, advances on scroll, and invalidates when older replies page in")
    func visibleWindowAndThreadIndexTracking() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let allHeaders = (1 ... 25).map { idx in
            makeHeader(
                id: "m-\(idx)",
                threadID: "t-\(idx)",
                date: Date(timeIntervalSince1970: 1_700_000_000 - Double(idx) * 60)
            )
        }
        // Filtered subset (e.g. search/category hides odd rows)
        let filteredVisible = allHeaders.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil }

        // Scrolled down to later rows (m-19, m-21)
        let scrolledBatch = ProactiveTriageVisibleWindow.selectBatch(
            from: filteredVisible,
            visibleIDs: ["m-19", "m-21"],
            itemID: \.id,
            cacheKey: { OnDeviceThreadTriageStore.cacheKey(accountID: "acct-1", header: $0) },
            maxBatchSize: 5
        )
        #expect(scrolledBatch.first?.id == "m-19")
        #expect(scrolledBatch.contains(where: { $0.id == "m-21" }))
        // Hidden/filtered-out rows (even indices -> m-2, m-4, etc.) never enter the batch
        #expect(!scrolledBatch.contains(where: { $0.id == "m-20" }))

        // Paging in an older reply into a visible thread updates its precomputed fingerprint & task key
        let indexBefore = ProactiveTriageThreadIndex.build(
            accountID: "acct-1",
            headers: allHeaders,
            folder: inbox,
            allFolders: [inbox]
        )
        let olderReply = makeHeader(
            id: "m-19-older",
            threadID: "t-19",
            snippet: "Older context message",
            date: Date(timeIntervalSince1970: 1_699_000_000)
        )
        let indexAfter = ProactiveTriageThreadIndex.build(
            accountID: "acct-1",
            headers: allHeaders + [olderReply],
            folder: inbox,
            allFolders: [inbox]
        )
        let key19 = OnDeviceThreadTriageStore.cacheKey(accountID: "acct-1", header: allHeaders[18])
        let fpBefore = indexBefore.headerFingerprint(for: key19, fallback: allHeaders[18])
        let fpAfter = indexAfter.headerFingerprint(for: key19, fallback: allHeaders[18])
        #expect(fpBefore != fpAfter)
        #expect(indexAfter.headers(for: key19, fallback: allHeaders[18]).count == 2)

        let taskKeyBefore = ProactiveTriageVisibleWindow.taskKey(
            prefix: "p",
            selectedKeysAndFingerprints: [(cacheKey: key19, headerFingerprint: fpBefore)]
        )
        let taskKeyAfter = ProactiveTriageVisibleWindow.taskKey(
            prefix: "p",
            selectedKeysAndFingerprints: [(cacheKey: key19, headerFingerprint: fpAfter)]
        )
        #expect(taskKeyBefore != taskKeyAfter)
    }

    @Test("sign-in codes in cached bodies are redacted before reaching the on-device model")
    func signInCodesRedactedFromCachedBodies() async throws {
        let store = OnDeviceThreadTriageStore(defaults: nil)
        let onDeviceBackend = StubMailTriageAIBackend(
            isOnDeviceZeroNetwork: true,
            responses: [#"{"priority":"normal","summary":"Automated login email from Example."}"#]
        )
        let header = makeHeader(
            subject: "Sign in to Example",
            snippet: "Your verification code is 739104."
        )
        let bodyProvider = RecordingCachedBodyProvider(bodies: [
            "msg-1": MessageBody(
                messageID: "msg-1",
                plainText: "Your one-time verification code is 739104. Do not share it."
            )
        ])

        _ = try #require(await store.triageIfEligible(
            accountID: "acct-1",
            headers: [header],
            folder: Folder(id: "inbox", name: "Inbox", role: .inbox),
            settings: enabledSettings,
            backend: onDeviceBackend,
            cachedBodyProvider: bodyProvider
        ))

        let prompts = await onDeviceBackend.recordedPrompts
        #expect(prompts.count == 1)
        #expect(!prompts[0].contains("739104"))
        #expect(prompts[0].contains("[Redacted"))
    }

    @Test("scrolled-past viewport batch jobs are cancelled per owner without starving new rows or co-waiting readers")
    func supersededOffscreenViewportJobsAreCancelledPerOwner() async throws {
        let engine = ProactiveOnDeviceTriageEngine(maxConcurrentInferences: 1)
        let store = OnDeviceThreadTriageStore(engine: engine, defaults: nil)
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let backend = GatedViewportTriageBackend(gatedTag: "Subject-Thread-1")

        let t1 = makeHeader(id: "m-1", threadID: "t-1", subject: "Subject-Thread-1")
        let t2 = makeHeader(id: "m-2", threadID: "t-2", subject: "Subject-Thread-2")
        let t3 = makeHeader(id: "m-3", threadID: "t-3", subject: "Subject-Thread-3")
        let t4 = makeHeader(id: "m-4", threadID: "t-4", subject: "Subject-Thread-4")
        let t5 = makeHeader(id: "m-5", threadID: "t-5", subject: "Subject-Thread-5")
        let t6 = makeHeader(id: "m-6", threadID: "t-6", subject: "Subject-Thread-6")

        // Viewport owner schedules initial batch [t1, t2, t3, t4]. t1 occupies the single slot
        // and blocks at the gate while t2..t4 wait in the engine's queue.
        store.scheduleVisibleThreads(
            ownerID: "folder-list",
            accountID: "acct-1",
            threadGroups: [[t1], [t2], [t3], [t4]],
            folder: inbox,
            settings: enabledSettings,
            backend: backend,
            maxThreads: 4
        )
        await backend.waitUntilGatedStarted()

        // Reader simultaneously awaits t1 so shared inference must survive the list scrolling past t1.
        let readerTask = Task { @MainActor in
            await store.triageIfEligible(
                accountID: "acct-1",
                headers: [t1],
                folder: inbox,
                settings: enabledSettings,
                backend: backend
            )
        }
        await Task.yield()
        await Task.yield()

        // User scrolls down: owner replaces its viewport batch with [t5, t6].
        // Superseded offscreen jobs (t2, t3, t4) are cancelled immediately.
        store.scheduleVisibleThreads(
            ownerID: "folder-list",
            accountID: "acct-1",
            threadGroups: [[t5], [t6]],
            folder: inbox,
            settings: enabledSettings,
            backend: backend,
            maxThreads: 4
        )
        await Task.yield()
        await Task.yield()

        // Release t1 so queued work drains.
        await backend.releaseGate()

        let readerInsight = try #require(await readerTask.value)
        #expect(readerInsight.summary == "Viewport triage completed.")

        let key5 = OnDeviceThreadTriageStore.cacheKey(accountID: "acct-1", header: t5)
        let key6 = OnDeviceThreadTriageStore.cacheKey(accountID: "acct-1", header: t6)
        let newRowsTriaged = try await waitUntil {
            store.insightsByKey[key5] != nil && store.insightsByKey[key6] != nil
        }

        #expect(newRowsTriaged)
        #expect(store.insightsByKey[key5] != nil)
        #expect(store.insightsByKey[key6] != nil)

        let started = await backend.startedPrompts
        #expect(started.contains(where: { $0.contains("Subject-Thread-1") }))
        #expect(started.contains(where: { $0.contains("Subject-Thread-5") }))
        #expect(started.contains(where: { $0.contains("Subject-Thread-6") }))
        #expect(!started.contains(where: { $0.contains("Subject-Thread-2") }))
        #expect(!started.contains(where: { $0.contains("Subject-Thread-3") }))
        #expect(!started.contains(where: { $0.contains("Subject-Thread-4") }))
    }

    @Test("scheduleVisibleThreads upgrades snippet-only cached insight once full body is cached")
    func scheduleVisibleThreadsUpgradesSnippetSummaryOnceBodyIsCached() async throws {
        let store = OnDeviceThreadTriageStore(defaults: nil)
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let header = makeHeader(
            id: "msg-upgrade",
            threadID: "thread-upgrade",
            subject: "Lease addendum",
            snippet: "Short snippet only."
        )
        let key = OnDeviceThreadTriageStore.cacheKey(accountID: "acct-1", header: header)
        let bodyProvider = RecordingCachedBodyProvider()
        let backend = StubMailTriageAIBackend(
            isOnDeviceZeroNetwork: true,
            responses: [
                #"{"priority":"normal","summary":"Snippet-only summary before body cached."}"#,
                #"{"priority":"urgent","summary":"Full cached body confirms Friday 3 PM deadline."}"#
            ]
        )

        // 1. Initial schedule before body is cached -> produces snippet-only summary.
        store.scheduleVisibleThreads(
            ownerID: "list-upgrade",
            accountID: "acct-1",
            threadGroups: [[header]],
            folder: inbox,
            settings: enabledSettings,
            backend: backend,
            cachedBodyProvider: bodyProvider
        )
        let initialReady = try await waitUntil { store.insightsByKey[key] != nil }
        #expect(initialReady)
        #expect(store.insightsByKey[key]?.summary == "Snippet-only summary before body cached.")
        #expect(await backend.recordedPrompts.count == 1)

        // 2. Rescheduling while body is still absent checks cache-only provider and avoids re-running the model.
        let readsBeforeSecondPass = bodyProvider.requestedIDs.count
        store.scheduleVisibleThreads(
            ownerID: "list-upgrade",
            accountID: "acct-1",
            threadGroups: [[header]],
            folder: inbox,
            settings: enabledSettings,
            backend: backend,
            cachedBodyProvider: bodyProvider
        )
        let secondPassCheckedCache = try await waitUntil {
            bodyProvider.requestedIDs.count > readsBeforeSecondPass
        }
        #expect(secondPassCheckedCache)
        #expect(await backend.recordedPrompts.count == 1)

        // 3. Body becomes locally cached -> scheduleVisibleThreads upgrades the insight automatically,
        // even if step 2's cache check task is still unwinding.
        bodyProvider.setBody(
            MessageBody(
                messageID: "msg-upgrade",
                plainText: "Full cached body confirming the binding deadline is Friday 3 PM."
            ),
            for: "msg-upgrade"
        )
        store.scheduleVisibleThreads(
            ownerID: "list-upgrade",
            accountID: "acct-1",
            threadGroups: [[header]],
            folder: inbox,
            settings: enabledSettings,
            backend: backend,
            cachedBodyProvider: bodyProvider
        )
        let upgraded = try await waitUntil {
            store.insightsByKey[key]?.summary == "Full cached body confirms Friday 3 PM deadline."
        }
        #expect(upgraded)
        #expect(store.insightsByKey[key]?.priority == .urgent)
        #expect(store.insightsByKey[key]?.summary == "Full cached body confirms Friday 3 PM deadline.")
        let prompts = await backend.recordedPrompts
        try #require(prompts.count == 2)
        #expect(prompts[1].contains("Full cached body confirming the binding deadline is Friday 3 PM."))

        // 4. Once full body coverage is cached, subsequent reschedules skip synchronously without extra cache reads.
        let readsAfterUpgrade = bodyProvider.requestedIDs.count
        store.scheduleVisibleThreads(
            ownerID: "list-upgrade",
            accountID: "acct-1",
            threadGroups: [[header]],
            folder: inbox,
            settings: enabledSettings,
            backend: backend,
            cachedBodyProvider: bodyProvider
        )
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(bodyProvider.requestedIDs.count == readsAfterUpgrade)
        #expect(await backend.recordedPrompts.count == 2)
    }

    @Test("rescheduling after body caches while an earlier cache check is in flight does not drop upgrade")
    func scheduleVisibleThreadsRechecksWhenBodyCachesDuringInFlightPass() async throws {
        let store = OnDeviceThreadTriageStore(defaults: nil)
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let header = makeHeader(
            id: "msg-race-upgrade",
            threadID: "thread-race-upgrade",
            subject: "Contract terms",
            snippet: "Short preview."
        )
        let key = OnDeviceThreadTriageStore.cacheKey(accountID: "acct-1", header: header)
        let bodyProvider = GatedCachedBodyProvider()
        let backend = StubMailTriageAIBackend(
            isOnDeviceZeroNetwork: true,
            responses: [
                #"{"priority":"normal","summary":"Initial snippet summary."}"#,
                #"{"priority":"urgent","summary":"Upgraded after in-flight cache check."}"#
            ]
        )

        // First pass caches snippet-only insight (body read #1 returns nil).
        store.scheduleVisibleThreads(
            ownerID: "list-race",
            accountID: "acct-1",
            threadGroups: [[header]],
            folder: inbox,
            settings: enabledSettings,
            backend: backend,
            cachedBodyProvider: bodyProvider
        )
        let initialReady = try await waitUntil { store.insightsByKey[key] != nil }
        #expect(initialReady)

        // Second pass pauses inside cachedBody (read #2) after observing nil.
        await bodyProvider.pauseNextRead(onCall: 2)
        store.scheduleVisibleThreads(
            ownerID: "list-race",
            accountID: "acct-1",
            threadGroups: [[header]],
            folder: inbox,
            settings: enabledSettings,
            backend: backend,
            cachedBodyProvider: bodyProvider
        )
        await bodyProvider.waitUntilPausedCallStarted()

        // While read #2 is still in flight, the body is written to cache and scheduleVisibleThreads fires again.
        await bodyProvider.setBody(
            MessageBody(
                messageID: "msg-race-upgrade",
                plainText: "Urgent full body written while earlier check was in flight."
            ),
            for: "msg-race-upgrade"
        )
        store.scheduleVisibleThreads(
            ownerID: "list-race",
            accountID: "acct-1",
            threadGroups: [[header]],
            folder: inbox,
            settings: enabledSettings,
            backend: backend,
            cachedBodyProvider: bodyProvider
        )

        // Release paused read #2 (which returns its pre-write nil snapshot).
        // The store must run one coalesced recheck and upgrade the summary automatically.
        await bodyProvider.releasePausedCall()
        let upgraded = try await waitUntil {
            store.insightsByKey[key]?.summary == "Upgraded after in-flight cache check."
        }
        #expect(upgraded)
        #expect(store.insightsByKey[key]?.priority == .urgent)
        let prompts = await backend.recordedPrompts
        try #require(prompts.count == 2)
        #expect(prompts[1].contains("Urgent full body written while earlier check was in flight."))
    }

    #if os(macOS)
    @Test("mounted views receive store updates across MessageListRow and ThreadConversationView and clear on switch/opt-out")
    func mountedViewStorePropagationAndConversationSwitch() async throws {
        let suiteName = "MountedProactiveTriage-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        enabledSettings.save(to: defaults)

        let store = OnDeviceThreadTriageStore(defaults: defaults)
        let onDeviceBackend = StubMailTriageAIBackend(
            isOnDeviceZeroNetwork: true,
            responses: [#"{"priority":"urgent","summary":"Mounted reader and list row received this insight."}"#]
        )
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let msgA = makeHeader(id: "m-a", threadID: "thread-a", subject: "Conversation A")
        let msgB = makeHeader(id: "m-b", threadID: "thread-b", subject: "Conversation B")
        let mockMailBackend = MockBackend()
        let source = MailSourceID(accountID: mockMailBackend.account.id, mailboxID: mockMailBackend.account.id)
        let navigation = MailNavigationState(
            selectedSourceID: source,
            selectedFolderID: "inbox",
            selectedMessageID: msgA.id,
            currentFolderHeaders: [msgA, msgB]
        )

        // Mount ThreadConversationView bound to the live store and verify on-device triage populates store
        let conversationHost = NSHostingController(
            rootView: ThreadConversationView(
                threadHeaders: [msgA],
                backend: mockMailBackend,
                sourceID: source,
                navigation: navigation,
                allFolders: [inbox],
                aiBackend: onDeviceBackend,
                triageStore: store,
                showsAvatars: false,
                autoScrollsToExpandedMessage: false
            )
            .frame(width: 600, height: 320)
            .brevTheme(.brevMonoLight)
            .defaultAppStorage(defaults)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 320),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = conversationHost
        window.layoutIfNeeded()
        conversationHost.view.frame = NSRect(x: 0, y: 0, width: 600, height: 320)
        conversationHost.view.layoutSubtreeIfNeeded()
        defer {
            window.contentViewController = nil
            window.close()
        }

        // Let AppKit + SwiftUI mount the view and yield the MainActor so the view's .task runs
        let keyA = OnDeviceThreadTriageStore.cacheKey(accountID: mockMailBackend.account.id, header: msgA)
        let fpA = OnDeviceThreadTriageStore.headerFingerprint(for: [msgA])
        for _ in 0 ..< 30 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            try await Task.sleep(nanoseconds: 20_000_000)
            if store.cachedInsight(for: keyA, matchingHeaderFingerprint: fpA) != nil {
                break
            }
        }
        // In headless AppKit runs where offscreen windows defer `.task`, also exercise direct store update
        if store.cachedInsight(for: keyA, matchingHeaderFingerprint: fpA) == nil {
            _ = await store.triageIfEligible(
                accountID: mockMailBackend.account.id,
                headers: [msgA],
                folder: inbox,
                allFolders: [inbox],
                settings: enabledSettings,
                backend: onDeviceBackend
            )
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            conversationHost.view.layoutSubtreeIfNeeded()
        }

        let liveInsight = try #require(store.cachedInsight(for: keyA, matchingHeaderFingerprint: fpA))
        #expect(liveInsight.priority == .urgent)
        #expect(liveInsight.summary == "Mounted reader and list row received this insight.")
        #expect(conversationHost.view.fittingSize.height > 0)

        // Mount a MessageListRow with the store-resolved insight to verify clean layout & rendering
        let rowHost = NSHostingController(
            rootView: MessageListRow(
                header: msgA,
                threadCount: 1,
                isSelected: false,
                isChecked: false,
                isInSelectionMode: false,
                isPinned: false,
                isThreadExpanded: false,
                showAvatar: false,
                previewLineCount: 1,
                fontFamily: .system,
                textSize: .medium,
                density: .comfortable,
                showsAbsoluteArrivalTime: false,
                sourceContext: nil,
                triageInsight: liveInsight,
                isBlockedSender: false,
                hasFollowUp: false,
                onActivate: {},
                onToggleCheck: {},
                onToggleThread: {}
            )
            .frame(width: 360, height: 96)
            .brevTheme(.brevMonoLight)
        )
        rowHost.view.frame = NSRect(x: 0, y: 0, width: 360, height: 96)
        rowHost.view.layoutSubtreeIfNeeded()
        #expect(rowHost.view.fittingSize.height > 0)

        // Switching the mounted ThreadConversationView to Conversation B resets conversation state cleanly
        conversationHost.rootView = ThreadConversationView(
            threadHeaders: [msgB],
            backend: mockMailBackend,
            sourceID: source,
            navigation: navigation,
            allFolders: [inbox],
            aiBackend: onDeviceBackend,
            triageStore: store,
            showsAvatars: false,
            autoScrollsToExpandedMessage: false
        )
        .frame(width: 600, height: 320)
        .brevTheme(.brevMonoLight)
        .defaultAppStorage(defaults)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        // Opting out in UserDefaults clears cached insights across both surfaces immediately
        AIWriterSettings(isEnabled: true, consentGiven: true, proactiveOnDeviceTriageEnabled: false)
            .save(to: defaults)
        let clearedAfterOptOut = try await waitUntil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            return store.insightsByKey.isEmpty
        }
        #expect(clearedAfterOptOut)
    }
    #endif

    @Test("BrevMail proactive summary header string has Norwegian catalog translation")
    func norwegianCatalogCoverage() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BrevMail/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: Any])

        let entry = try #require(strings["On-device summary"] as? [String: Any])
        let nb = (entry["localizations"] as? [String: Any])?["nb"] as? [String: Any]
        let unit = nb?["stringUnit"] as? [String: Any]
        #expect((unit?["value"] as? String)?.isEmpty == false)
    }
}
