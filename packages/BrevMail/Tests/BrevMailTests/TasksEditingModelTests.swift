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

import BrevCalendar
@testable import BrevMail
import Foundation
import Testing

/// Authoring-model coverage for the Tasks surface (ADR-0072 #12):
/// writable-target resolution, create/update/delete dispatch, the
/// cross-list move path, completion toggling, and error surfacing.
@Suite("TasksEditingModel")
@MainActor
struct TasksEditingModelTests {
    // MARK: - In-memory doubles

    private actor SourceStore: PIMSourceStore {
        var records: [PIMSource] = []

        func allSources() async throws -> [PIMSource] { records }

        func save(_ source: PIMSource) async throws {
            if let index = records.firstIndex(where: { $0.id == source.id }) {
                records[index] = source
            } else {
                records.append(source)
            }
        }

        func deleteSource(id: PIMSource.ID) async throws {
            records.removeAll { $0.id == id }
        }
    }

    private actor CredentialStore: CalDAVCredentialStore {
        func credential(for account: String) async throws -> CalDAVCredential? {
            nil
        }

        func setCredential(
            _ credential: CalDAVCredential,
            for account: String
        ) async throws {}

        func deleteCredential(for account: String) async throws {}
    }

    private actor LocalDataStore: PIMSourceLocalDataStore {
        func deleteSyncAndDraftData(for sourceID: PIMSource.ID) async throws {}
        func deleteCachedContent(for sourceID: PIMSource.ID) async throws {}
        func markCacheDisconnected(for sourceID: PIMSource.ID) async throws {}
    }

    private actor CollectionStore: PIMCollectionStore {
        var records: [PIMSource.ID: [PIMCollection]] = [:]

        func collections(
            for sourceID: PIMSource.ID
        ) async throws -> [PIMCollection] {
            records[sourceID] ?? []
        }

        func saveCollections(
            _ collections: [PIMCollection],
            for sourceID: PIMSource.ID
        ) async throws {
            records[sourceID] = collections
        }

        func deleteCollections(for sourceID: PIMSource.ID) async throws {
            records[sourceID] = nil
        }
    }

    /// Records every mutation the model dispatches; canWrite mirrors
    /// the real service's capability + provider + read-only rule.
    private final class RecordingWriter: TaskWriting,
        @unchecked Sendable {
        enum Call: Equatable {
            case create(PIMTask, PIMCollection.ID)
            case update(PIMTask)
            case delete(PIMTask)
            case move(PIMTask, PIMCollection.ID)
        }

        private(set) var calls: [Call] = []

        func canWrite(
            source: PIMSource,
            collection: PIMCollection
        ) -> Bool {
            source.enabledCapabilities.contains(.write)
                && !collection.isReadOnly
                && [PIMSourceProvider.google, .calDAV]
                .contains(source.provider)
        }

        func create(
            _ task: PIMTask,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws -> PIMTask {
            calls.append(.create(task, collection.id))
            return task
        }

        func update(
            _ task: PIMTask,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws -> PIMTask {
            calls.append(.update(task))
            return task
        }

        func delete(
            _ task: PIMTask,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws {
            calls.append(.delete(task))
        }

        func move(
            _ task: PIMTask,
            to target: PIMCollection,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws -> PIMTask {
            calls.append(.move(task, target.id))
            return task
        }
    }

    // MARK: - Fixtures

    private nonisolated static let fixedNow = Date(
        timeIntervalSince1970: 1_800_000_000
    )

    private static func source(
        id: String,
        provider: PIMSourceProvider = .calDAV,
        writable: Bool = true
    ) -> PIMSource {
        PIMSource(
            id: id,
            kind: .tasks,
            provider: provider,
            displayName: id,
            enabledCapabilities: writable ? [.read, .write] : [.read],
            status: .ready,
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
    }

    private static func collection(
        id: String,
        sourceID: String,
        isReadOnly: Bool = false,
        isPrimary: Bool = false
    ) -> PIMCollection {
        PIMCollection(
            id: id,
            sourceID: sourceID,
            kind: .tasks,
            displayName: id,
            colorHex: nil,
            isReadOnly: isReadOnly,
            isPrimary: isPrimary,
            supportsSyncToken: true,
            providerKey: id,
            providerVersion: nil,
            isVisible: true,
            updatedAt: fixedNow
        )
    }

    private static func task(
        id: String = "t1",
        sourceID: String = "s1",
        collectionID: String = "list1",
        status: PIMTaskStatus = .needsAction
    ) -> PIMTask {
        PIMTask(
            id: id,
            sourceID: sourceID,
            collectionID: collectionID,
            providerItemKey: "https://dav.example.com/t/" + id + ".ics",
            uid: "uid-" + id + "@brev",
            title: "Write tests",
            status: status,
            syncedAt: fixedNow
        )
    }

    private func makeModel(
        sources: [PIMSource],
        collections: [PIMSource.ID: [PIMCollection]] = [:],
        writer: RecordingWriter? = nil
    ) async throws -> (TasksEditingModel, RecordingWriter) {
        let sourceStore = SourceStore()
        for source in sources {
            try await sourceStore.save(source)
        }
        let coordinator = PIMSourceCoordinator(
            store: sourceStore,
            credentials: CredentialStore(),
            localData: LocalDataStore(),
            now: { Self.fixedNow }
        )
        let collectionStore = CollectionStore()
        for (sourceID, list) in collections {
            try await collectionStore.saveCollections(list, for: sourceID)
        }
        let collectionService = PIMCollectionService(
            coordinator: coordinator,
            store: collectionStore,
            credentials: CredentialStore(),
            now: { Self.fixedNow }
        )
        let recording = writer ?? RecordingWriter()
        let model = TasksEditingModel(
            writeService: recording,
            coordinator: coordinator,
            collectionService: collectionService,
            now: { Self.fixedNow }
        )
        return (model, recording)
    }

    // MARK: - Target resolution

    @Test("load keeps writable lists and drops the rest")
    func loadFiltersTargets() async throws {
        let (model, _) = try await makeModel(
            sources: [
                Self.source(id: "dav"),
                Self.source(id: "g", provider: .google),
                Self.source(id: "ro", writable: false),
                Self.source(id: "card", provider: .cardDAV),
            ],
            collections: [
                "dav": [
                    Self.collection(
                        id: "list1",
                        sourceID: "dav",
                        isPrimary: true
                    ),
                    Self.collection(
                        id: "locked",
                        sourceID: "dav",
                        isReadOnly: true
                    ),
                ],
                "g": [Self.collection(id: "glist", sourceID: "g")],
                "ro": [Self.collection(id: "list2", sourceID: "ro")],
                "card": [Self.collection(id: "list3", sourceID: "card")],
            ]
        )

        await model.load()

        // Read-only, read-capability-only, and CardDAV-provider lists
        // never reach the picker.
        #expect(
            model.targets.map(\.id).sorted()
                == ["glist", "list1"]
        )
        #expect(model.defaultTarget?.id == "list1")
    }

    @Test("canEdit gates on source writability and collection access")
    func editability() async throws {
        let (model, _) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [
                    Self.collection(id: "list1", sourceID: "s1"),
                    Self.collection(
                        id: "locked",
                        sourceID: "s1",
                        isReadOnly: true
                    ),
                ],
            ]
        )
        await model.load()

        #expect(model.canEdit(Self.task(collectionID: "list1")))
        #expect(!model.canEdit(Self.task(collectionID: "locked")))
        #expect(!model.canEdit(Self.task(collectionID: "gone")))
    }

    // MARK: - Mutations

    @Test("create writes a new task into the chosen list")
    func createDispatches() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [Self.collection(id: "list1", sourceID: "s1")],
            ]
        )
        await model.load()
        var draft = TaskDraft()
        draft.title = "Ship it"
        draft.targetID = "list1"

        let saved = try await model.create(draft)

        #expect(saved.title == "Ship it")
        guard case .create(let task, let collectionID) =
            writer.calls.first
        else {
            Issue.record("expected a single create call")
            return
        }
        #expect(collectionID == "list1")
        #expect(task.title == "Ship it")
        #expect(writer.calls.count == 1)
    }

    @Test("update replaces the writable fields in place")
    func updateDispatches() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [Self.collection(id: "list1", sourceID: "s1")],
            ]
        )
        await model.load()
        var draft = TaskDraft(task: Self.task())
        draft.notes = "Remember the milk"

        _ = try await model.update(draft, for: Self.task())

        guard case .update(let task) = writer.calls.first else {
            Issue.record("expected a single update call")
            return
        }
        #expect(task.notes == "Remember the milk")
        #expect(writer.calls.count == 1)
    }

    @Test("a list change routes through the cross-collection move")
    func updateMoves() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [
                    Self.collection(id: "list1", sourceID: "s1"),
                    Self.collection(id: "list2", sourceID: "s1"),
                ],
            ]
        )
        await model.load()
        var draft = TaskDraft(task: Self.task())
        draft.targetID = "list2"

        _ = try await model.update(draft, for: Self.task())

        guard case .move(let task, let targetID) = writer.calls.first
        else {
            Issue.record("expected a single move call")
            return
        }
        #expect(targetID == "list2")
        #expect(task.uid == "uid-t1@brev")
        #expect(writer.calls.count == 1)
    }

    @Test("delete removes the task through the write seam")
    func deleteDispatches() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [Self.collection(id: "list1", sourceID: "s1")],
            ]
        )
        await model.load()

        try await model.delete(Self.task())

        guard case .delete = writer.calls.first else {
            Issue.record("expected a single delete call")
            return
        }
        #expect(writer.calls.count == 1)
    }

    @Test("toggling completion stamps and clears completedAt")
    func toggleCompleted() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [Self.collection(id: "list1", sourceID: "s1")],
            ]
        )
        await model.load()

        _ = try await model.toggleCompleted(Self.task())

        guard case .update(let done) = writer.calls.first else {
            Issue.record("expected an update call")
            return
        }
        #expect(done.status == .completed)
        #expect(done.completedAt == Self.fixedNow)

        _ = try await model.toggleCompleted(
            Self.task(status: .completed)
        )

        guard case .update(let reopened) = writer.calls.last else {
            Issue.record("expected a second update call")
            return
        }
        #expect(reopened.status == .needsAction)
        #expect(reopened.completedAt == nil)
    }

    // MARK: - Errors

    @Test("create without a writable target surfaces notWritable")
    func createRequiresTarget() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [Self.collection(id: "list1", sourceID: "s1")],
            ]
        )
        await model.load()
        var draft = TaskDraft()
        draft.title = "Nowhere"
        draft.targetID = "missing"

        await #expect(
            throws: PIMTaskWriteService.WriteError.notWritable
        ) {
            try await model.create(draft)
        }
        #expect(writer.calls.isEmpty)
        #expect(model.lastError != nil)
    }

    @Test("a model without a write service cannot author")
    func noWriteService() async throws {
        let sourceStore = SourceStore()
        let coordinator = PIMSourceCoordinator(
            store: sourceStore,
            credentials: CredentialStore(),
            localData: LocalDataStore(),
            now: { Self.fixedNow }
        )
        let model = TasksEditingModel(
            writeService: nil,
            coordinator: coordinator,
            collectionService: nil,
            now: { Self.fixedNow }
        )

        #expect(!model.canAuthor)
        await model.load()
        #expect(model.targets.isEmpty)
    }
}
