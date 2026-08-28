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

@testable import BrevBackend
import Foundation
import Testing

@Suite("UserDefaultsMutationQueue", .serialized)
struct OfflineMutationQueueTests {
    private func makeQueue() throws -> (UserDefaultsMutationQueue, UserDefaults) {
        let suite = "OfflineQueueTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (UserDefaultsMutationQueue(defaults: defaults, storageKey: "q"), defaults)
    }

    @Test("enqueue then pending returns items in insertion order")
    func enqueuePreservesOrder() async throws {
        let (queue, _) = try makeQueue()
        try await queue.enqueue(PendingMutation(kind: .setRead(true), messageIDs: ["a"]))
        try await queue.enqueue(PendingMutation(kind: .delete, messageIDs: ["b"]))
        let items = try await queue.pending()
        #expect(items.count == 2)
        #expect(items[0].messageIDs == ["a"])
        #expect(items[1].messageIDs == ["b"])
    }

    @Test("a corrupt persisted blob does not brick the queue")
    func corruptBlobDoesNotBrickQueue() async throws {
        let (queue, defaults) = try makeQueue()
        // A non-decodable blob previously made the whole-array decode throw,
        // stopping ALL offline replay.
        defaults.set(Data("not valid mutation json".utf8), forKey: "q")

        let pending = try await queue.pending()
        #expect(pending.isEmpty)

        // The queue must remain usable afterwards.
        try await queue.enqueue(PendingMutation(kind: .delete, messageIDs: ["INBOX:1"]))
        #expect(try await queue.pending().count == 1)
    }

    @Test("duplicate suppression collapses same-target mutations, newest wins")
    func duplicateSuppression() async throws {
        let (queue, _) = try makeQueue()
        try await queue.enqueue(PendingMutation(kind: .setRead(true), messageIDs: ["m1"]))
        try await queue.enqueue(PendingMutation(kind: .setRead(false), messageIDs: ["m1"]))
        let items = try await queue.pending()
        #expect(items.count == 1)
        #expect(items[0].kind == .setRead(false))
    }

    @Test("different targets are not collapsed")
    func differentTargetsKept() async throws {
        let (queue, _) = try makeQueue()
        try await queue.enqueue(PendingMutation(kind: .setRead(true), messageIDs: ["m1"]))
        try await queue.enqueue(PendingMutation(kind: .setRead(true), messageIDs: ["m2"]))
        #expect(try await queue.pending().count == 2)
    }

    @Test("same target in different sources is not collapsed")
    func sourceScopedMutationsAreNotCollapsed() async throws {
        let (queue, _) = try makeQueue()
        let sourceA = MailSourceID(accountID: "acct-a", mailboxID: "mbx-a")
        let sourceB = MailSourceID(accountID: "acct-a", mailboxID: "mbx-b")
        try await queue.enqueue(PendingMutation(
            kind: .setRead(true),
            sourceID: sourceA,
            messageIDs: ["m1"]
        ))
        try await queue.enqueue(PendingMutation(
            kind: .setRead(true),
            sourceID: sourceB,
            messageIDs: ["m1"]
        ))
        #expect(try await queue.pending().count == 2)
    }

    @Test("send is keyed by draft so re-queueing the same draft collapses")
    func sendDedupByDraft() async throws {
        let (queue, _) = try makeQueue()
        let draft = Draft(id: "d1", subject: "First")
        try await queue.enqueue(PendingMutation(kind: .send(draft: draft), messageIDs: []))
        try await queue.enqueue(PendingMutation(kind: .send(draft: draft), messageIDs: []))
        #expect(try await queue.pending().count == 1)
    }

    @Test("queued send metadata contains only the staged draft identifier")
    func queuedSendDoesNotPersistDraftContent() async throws {
        let (queue, defaults) = try makeQueue()
        let draft = Draft(
            id: "private-draft",
            to: [Correspondent(name: "Ada", email: "ada@example.org")],
            subject: "Private subject",
            htmlBody: "Private body"
        )
        try await queue.enqueue(PendingMutation(kind: .send(draft: draft), messageIDs: []))

        let raw = try #require(defaults.data(forKey: "q"))
        let encoded = try #require(String(data: raw, encoding: .utf8))
        #expect(encoded.contains("private-draft"))
        #expect(!encoded.contains("Private subject"))
        #expect(!encoded.contains("Private body"))
        #expect(!encoded.contains("ada@example.org"))
        #expect(try await queue.pending().first?.kind == .sendStagedDraft(stagedDraftID: "private-draft"))
    }

    @Test("legacy plaintext send entries migrate to staged references")
    func legacySendEntryMigratesToReference() async throws {
        let (queue, defaults) = try makeQueue()
        let legacy = Data(#"[{"id":"00000000-0000-0000-0000-000000000001","kind":{"send":{"draft":{"id":"legacy-draft","subject":"legacy secret","htmlBody":"legacy body"}}},"messageIDs":[],"createdAt":0,"attempt":0}]"#
            .utf8)
        defaults.set(legacy, forKey: "q")

        let pending = try await queue.pending()
        #expect(pending.count == 1)
        guard case .send(draft: let migratedDraft) = pending.first?.kind else {
            Issue.record("Expected legacy draft to remain recoverable until staging migration.")
            return
        }
        #expect(migratedDraft.subject == "legacy secret")
        try await queue.update(PendingMutation(
            id: #require(pending.first?.id),
            kind: .sendStagedDraft(stagedDraftID: migratedDraft.id),
            messageIDs: []
        ))
        let rewritten = try #require(defaults.data(forKey: "q"))
        let encoded = try #require(String(data: rewritten, encoding: .utf8))
        #expect(!encoded.contains("legacy secret"))
        #expect(!encoded.contains("legacy body"))
    }

    @Test("update replaces a stored mutation in place")
    func updateInPlace() async throws {
        let (queue, _) = try makeQueue()
        var m = PendingMutation(kind: .delete, messageIDs: ["x"])
        try await queue.enqueue(m)
        m.attempt = 3
        try await queue.update(m)
        #expect(try await queue.pending().first?.attempt == 3)
    }

    @Test("remove deletes by id; removeAll clears")
    func removeAndClear() async throws {
        let (queue, _) = try makeQueue()
        let m = PendingMutation(kind: .delete, messageIDs: ["x"])
        try await queue.enqueue(m)
        try await queue.remove(id: m.id)
        #expect(try await queue.pending().isEmpty)

        try await queue.enqueue(PendingMutation(kind: .delete, messageIDs: ["y"]))
        try await queue.removeAll()
        #expect(try await queue.pending().isEmpty)
    }

    @Test("queue survives a fresh store over the same defaults (persistence)")
    func persistsAcrossInstances() async throws {
        let (queue, defaults) = try makeQueue()
        try await queue.enqueue(PendingMutation(kind: .setFlagged(true), messageIDs: ["z"]))
        let reopened = UserDefaultsMutationQueue(defaults: defaults, storageKey: "q")
        #expect(try await reopened.pending().count == 1)
    }

    @Test("PendingMutation round-trips through Codable including flag color")
    func codableRoundTrip() throws {
        let m = PendingMutation(
            kind: .setFlagColor(.red),
            sourceID: MailSourceID(accountID: "acct", mailboxID: "mbx"),
            messageIDs: ["a", "b"]
        )
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(PendingMutation.self, from: data)
        #expect(decoded == m)
    }

    @Test("move and copy round-trip through the canonical folderID payload")
    func moveAndCopyCanonicalRoundTrip() throws {
        for kind in [PendingMutation.Kind.move(folderID: "Archive"), .copy(folderID: "Archive")] {
            let mutation = PendingMutation(kind: kind, messageIDs: ["INBOX:1"])
            let data = try JSONEncoder().encode(mutation)
            let json = try #require(String(data: data, encoding: .utf8))

            #expect(json.contains("folderID"))
            #expect(!json.contains("_0"))
            #expect(try JSONDecoder().decode(PendingMutation.self, from: data) == mutation)
        }
    }

    @Test("move and copy decode legacy associated-value payloads")
    func moveAndCopyLegacyRoundTrip() throws {
        let cases: [(String, PendingMutation.Kind)] = [
            ("move", .move(folderID: "Archive")),
            ("copy", .copy(folderID: "Archive")),
        ]

        for (caseName, expectedKind) in cases {
            let commonPrefix = "{\"id\":\"00000000-0000-0000-0000-000000000001\",\"kind\":{\""
            let legacyNestedSuffix = "\":{\"_0\":\"Archive\"}},\"messageIDs\":[\"INBOX:1\"],\"createdAt\":0,\"attempt\":0}"
            let legacyDirectSuffix = "\":\"Archive\"},\"messageIDs\":[\"INBOX:1\"],\"createdAt\":0,\"attempt\":0}"
            let legacyNested = Data((commonPrefix + caseName + legacyNestedSuffix).utf8)
            let legacyDirect = Data((commonPrefix + caseName + legacyDirectSuffix).utf8)

            #expect(try JSONDecoder().decode(PendingMutation.self, from: legacyNested).kind == expectedKind)
            #expect(try JSONDecoder().decode(PendingMutation.self, from: legacyDirect).kind == expectedKind)
        }
    }

    @Test("persisted move/copy mutations survive queue and conflict-store reload")
    func moveAndCopyPersistedReload() async throws {
        let suite = "OfflineMoveCopyPersistenceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        let mutations = [
            PendingMutation(kind: .move(folderID: "Archive"), messageIDs: ["INBOX:1"]),
            PendingMutation(kind: .copy(folderID: "Sent"), messageIDs: ["INBOX:2"]),
        ]
        let queue = UserDefaultsMutationQueue(defaults: defaults, storageKey: "queue")
        try await queue.enqueue(mutations[0])
        try await queue.enqueue(mutations[1])

        let reopenedQueue = UserDefaultsMutationQueue(defaults: defaults, storageKey: "queue")
        #expect(try await reopenedQueue.pending().map(\.kind) == mutations.map(\.kind))

        let conflictStore = UserDefaultsMutationConflictStore(defaults: defaults, storageKey: "conflicts")
        try await conflictStore.append(mutations.map {
            MutationConflict(mutation: $0, reason: .retriesExhausted, message: "retry")
        })
        let reopenedConflictStore = UserDefaultsMutationConflictStore(defaults: defaults, storageKey: "conflicts")
        let conflicts = try await reopenedConflictStore.conflicts()
        #expect(
            conflicts.map { $0.mutation.kind.operationDescription }.sorted()
                == mutations.map { $0.kind.operationDescription }.sorted()
        )
    }

    @Test("mutation conflict store persists and deduplicates by mutation")
    func conflictStorePersistsAndDeduplicatesByMutation() async throws {
        let suite = "OfflineConflictTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = UserDefaultsMutationConflictStore(defaults: defaults, storageKey: "conflicts")
        let mutation = PendingMutation(kind: .delete, messageIDs: ["INBOX:404"])
        try await store.append([
            MutationConflict(
                mutation: mutation,
                reason: .targetMissing,
                message: "The item no longer exists."
            ),
        ])
        try await store.append([
            MutationConflict(
                mutation: mutation,
                reason: .rejectedByServer,
                message: "The server rejected the change."
            ),
        ])

        let reopened = UserDefaultsMutationConflictStore(defaults: defaults, storageKey: "conflicts")
        let conflicts = try await reopened.conflicts()

        #expect(conflicts.count == 1)
        #expect(conflicts.first?.reason == .rejectedByServer)
    }

    @Test("legacy conflict reads rewrite plaintext send drafts")
    func legacyConflictSendIsSanitizedOnRead() async throws {
        let suite = "OfflineConflictLegacyTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let mutation = PendingMutation(
            kind: .send(draft: Draft(id: "legacy-conflict", subject: "secret subject", htmlBody: "secret body")),
            messageIDs: []
        )
        let conflict = MutationConflict(mutation: mutation, reason: .retriesExhausted, message: "retry")
        let store = UserDefaultsMutationConflictStore(defaults: defaults, storageKey: "conflicts")
        try await store.append([conflict])
        _ = try await store.conflicts()
        let raw = try #require(defaults.data(forKey: "conflicts"))
        let encoded = try #require(String(data: raw, encoding: .utf8))
        #expect(!encoded.contains("secret subject"))
        #expect(!encoded.contains("secret body"))
    }

    @Test("clearing pending mutations also clears stored conflicts")
    func clearingPendingMutationsAlsoClearsStoredConflicts() async throws {
        let suite = "OfflineQueueStorageTests-\(UUID().uuidString)"
        let accountID = "imap-smtp:person@example.org"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let queue = OfflineMutationQueueStorage.queue(
            accountID: accountID,
            defaults: defaults
        )
        let conflictStore = OfflineMutationQueueStorage.conflictStore(
            accountID: accountID,
            defaults: defaults
        )
        let mutation = PendingMutation(kind: .delete, messageIDs: ["INBOX:404"])
        try await queue.enqueue(mutation)
        try await conflictStore.append([
            MutationConflict(
                mutation: mutation,
                reason: .targetMissing,
                message: "The item no longer exists."
            ),
        ])

        await OfflineMutationQueueStorage.clearPendingMutations(
            for: accountID,
            defaults: defaults
        )

        #expect(try await queue.pending().isEmpty)
        #expect(try await conflictStore.conflicts().isEmpty)
    }
}
