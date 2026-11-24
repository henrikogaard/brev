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
@testable import BrevMail
import Foundation
import Testing

private actor StubMailTriageAIBackend: AIBackend {
    nonisolated let identifier: String
    nonisolated let displayName: String
    nonisolated let transparencyLabel: String
    nonisolated let isOnDeviceZeroNetwork: Bool
    nonisolated let contextBudget: AIBackendContextBudget? = .onDevice

    var recordedPrompts: [String] = []
    var responses: [String]

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

    func generateReply(to messages: [AIMessage], instruction: String?) async throws -> AIResponse {
        _ = instruction
        recordedPrompts.append(messages.map(\.content).joined(separator: "\n"))
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

    func cachedBody(for messageID: MessageHeader.ID, sourceID: MailSourceID?) async -> MessageBody? {
        _ = sourceID
        return lock.withLock {
            requestedIDsStorage.append(messageID)
            return bodies[messageID]
        }
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
        let store = OnDeviceThreadTriageStore()
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
        let store = OnDeviceThreadTriageStore()
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
        let fp1 = OnDeviceThreadTriageStore.sourceFingerprint(for: [msg1])
        #expect(store.cachedInsight(for: key, sourceFingerprint: fp1) == first)

        // Second message arrives in same thread -> fingerprint changes -> cache miss & re-triage
        let msg2 = makeHeader(
            id: "msg-2",
            snippet: "Urgent: please confirm before 5 PM.",
            date: Date(timeIntervalSince1970: 1_700_003_600)
        )
        let fp2 = OnDeviceThreadTriageStore.sourceFingerprint(for: [msg1, msg2])
        #expect(store.cachedInsight(for: key, sourceFingerprint: fp2) == nil)

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

    @Test("Trash and Spam folders are never triaged")
    func trashAndSpamExcluded() async {
        let store = OnDeviceThreadTriageStore()
        let onDeviceBackend = StubMailTriageAIBackend(isOnDeviceZeroNetwork: true)

        for role in [FolderRole.trash, .spam] {
            let folder = Folder(id: role.rawValue, name: role.rawValue, role: role)
            let result = await store.triageIfEligible(
                accountID: "acct-1",
                headers: [makeHeader(folderID: folder.id)],
                folder: folder,
                settings: enabledSettings,
                backend: onDeviceBackend
            )
            #expect(result == nil)
        }
        #expect(await onDeviceBackend.recordedPrompts.isEmpty)
    }

    @Test("sign-in codes in cached bodies are redacted before reaching the on-device model")
    func signInCodesRedactedFromCachedBodies() async throws {
        let store = OnDeviceThreadTriageStore()
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
