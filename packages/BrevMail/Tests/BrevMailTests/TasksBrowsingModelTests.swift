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

/// Browsing-model coverage for the Tasks surface (ADR-0072 #12):
/// cache-only loading, hidden-collection and completed filtering,
/// local search, list sections, staleness, per-source failure
/// isolation, and brev://task deep links.
@Suite("TasksBrowsingModel")
@MainActor
struct TasksBrowsingModelTests {
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

    private actor TaskStore: PIMTaskStore {
        var records: [PIMSource.ID: [PIMTask]] = [:]
        /// Source IDs whose reads should throw — exercises failure
        /// isolation without touching the other sources' caches.
        private var failingSourceIDs: Set<PIMSource.ID> = []

        func failReads(for sourceID: PIMSource.ID) {
            failingSourceIDs.insert(sourceID)
        }

        /// Test seeding: writes records under their own collection
        /// IDs without going through the per-collection protocol.
        func seed(_ tasks: [PIMTask], for sourceID: PIMSource.ID) {
            records[sourceID, default: []].append(contentsOf: tasks)
        }

        func tasks(
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws -> [PIMTask] {
            try await tasks(for: sourceID)
                .filter { $0.collectionID == collectionID }
        }

        func tasks(for sourceID: PIMSource.ID) async throws -> [PIMTask] {
            if failingSourceIDs.contains(sourceID) {
                throw CocoaError(.coderReadCorrupt)
            }
            return records[sourceID] ?? []
        }

        func saveTasks(
            _ tasks: [PIMTask],
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws {
            var kept = (records[sourceID] ?? [])
                .filter { $0.collectionID != collectionID }
            kept.append(contentsOf: tasks)
            records[sourceID] = kept
        }

        func deleteTasks(
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws {
            records[sourceID]?.removeAll {
                $0.collectionID == collectionID
            }
        }
    }

    private actor CursorStore: PIMSyncCursorStore {
        func cursor(
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws -> PIMSyncCursor? { nil }

        func saveCursor(
            _ cursor: PIMSyncCursor,
            for sourceID: PIMSource.ID
        ) async throws {}

        func deleteCursor(
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws {}
    }

    // MARK: - Fixtures

    private nonisolated static let fixedNow = Date(
        timeIntervalSince1970: 1_800_000_000
    )

    private static func source(
        id: String,
        kind: PIMSourceKind = .tasks,
        provider: PIMSourceProvider = .calDAV,
        status: PIMSourceStatus = .ready,
        syncEnabled: Bool = true
    ) -> PIMSource {
        PIMSource(
            id: id,
            kind: kind,
            provider: provider,
            displayName: id,
            syncEnabled: syncEnabled,
            status: status,
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
    }

    private static func collection(
        id: String,
        sourceID: String,
        displayName: String? = nil,
        isVisible: Bool = true
    ) -> PIMCollection {
        PIMCollection(
            id: id,
            sourceID: sourceID,
            kind: .tasks,
            displayName: displayName ?? id,
            colorHex: nil,
            isReadOnly: false,
            isPrimary: false,
            supportsSyncToken: true,
            providerKey: id,
            providerVersion: nil,
            isVisible: isVisible,
            updatedAt: fixedNow
        )
    }

    private static func task(
        id: String,
        sourceID: String,
        collectionID: String,
        title: String? = nil,
        notes: String? = nil,
        status: PIMTaskStatus = .needsAction,
        position: String? = nil,
        syncedAt: Date = fixedNow
    ) -> PIMTask {
        PIMTask(
            id: id,
            sourceID: sourceID,
            collectionID: collectionID,
            providerItemKey: id,
            title: title ?? id,
            notes: notes,
            status: status,
            position: position,
            syncedAt: syncedAt
        )
    }

    /// Seeds the store directly — records carry their own
    /// collectionID, so a single per-source write keeps them all.
    private func makeModel(
        sources: [PIMSource],
        collections: [PIMSource.ID: [PIMCollection]] = [:],
        tasks: [PIMSource.ID: [PIMTask]] = [:],
        failingSourceIDs: Set<PIMSource.ID> = []
    ) async throws -> (TasksBrowsingModel, TaskStore) {
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
        let taskStore = TaskStore()
        for sourceID in failingSourceIDs {
            await taskStore.failReads(for: sourceID)
        }
        for (sourceID, list) in tasks {
            await taskStore.seed(list, for: sourceID)
        }
        let collectionService = PIMCollectionService(
            coordinator: coordinator,
            store: collectionStore,
            credentials: CredentialStore(),
            now: { Self.fixedNow }
        )
        let taskSyncService = PIMTaskSyncService(
            coordinator: coordinator,
            collectionStore: collectionStore,
            taskStore: taskStore,
            cursorStore: CursorStore(),
            credentials: CredentialStore(),
            now: { Self.fixedNow }
        )
        let model = TasksBrowsingModel(
            coordinator: coordinator,
            collectionService: collectionService,
            taskSyncService: taskSyncService,
            now: { Self.fixedNow }
        )
        return (model, taskStore)
    }

    // MARK: - Loading

    @Test("load merges cached tasks across sources")
    func loadMergesSources() async throws {
        let (model, _) = try await makeModel(
            sources: [
                Self.source(id: "s1"), Self.source(id: "s2"),
            ],
            tasks: [
                "s1": [
                    Self.task(
                        id: "t1", sourceID: "s1", collectionID: "c1"
                    ),
                ],
                "s2": [
                    Self.task(
                        id: "t2", sourceID: "s2", collectionID: "c2"
                    ),
                ],
            ]
        )

        await model.load()

        #expect(model.visibleTasks.map(\.id).sorted() == ["t1", "t2"])
        #expect(model.lastError == nil)
        #expect(model.hasSources)
    }

    @Test("contacts and calendar sources stay out of the tasks surface")
    func ignoresOtherKinds() async throws {
        let (model, _) = try await makeModel(
            sources: [
                Self.source(id: "lists", kind: .tasks),
                Self.source(
                    id: "addr",
                    kind: .contacts,
                    provider: .cardDAV
                ),
                Self.source(
                    id: "cal",
                    kind: .calendar,
                    provider: .cardDAV
                ),
            ]
        )

        await model.load()

        #expect(model.sources.map(\.id) == ["lists"])
    }

    @Test("hidden collections' tasks stay out of the list")
    func hiddenCollectionsExcluded() async throws {
        let (model, _) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [
                    Self.collection(id: "c1", sourceID: "s1"),
                    Self.collection(
                        id: "c2",
                        sourceID: "s1",
                        isVisible: false
                    ),
                ],
            ],
            tasks: [
                "s1": [
                    Self.task(
                        id: "shown", sourceID: "s1", collectionID: "c1"
                    ),
                    Self.task(
                        id: "hidden", sourceID: "s1", collectionID: "c2"
                    ),
                ],
            ]
        )

        await model.load()

        #expect(model.visibleTasks.map(\.id) == ["shown"])
    }

    @Test("one unreadable source cache keeps the others and reports inline")
    func failureIsolation() async throws {
        let (model, _) = try await makeModel(
            sources: [
                Self.source(id: "good"), Self.source(id: "bad"),
            ],
            tasks: [
                "good": [
                    Self.task(
                        id: "t1", sourceID: "good", collectionID: "c1"
                    ),
                ],
            ],
            failingSourceIDs: ["bad"]
        )

        await model.load()

        #expect(model.visibleTasks.map(\.id) == ["t1"])
        #expect(model.lastError?.contains("bad") == true)
    }

    // MARK: - Filters

    @Test("search matches title and notes locally")
    func searchFilters() async throws {
        let (model, _) = try await makeModel(
            sources: [Self.source(id: "s1")],
            tasks: [
                "s1": [
                    Self.task(
                        id: "t1", sourceID: "s1", collectionID: "c1",
                        title: "Buy milk"
                    ),
                    Self.task(
                        id: "t2", sourceID: "s1", collectionID: "c1",
                        title: "Call bank",
                        notes: "Mortgage renewal"
                    ),
                ],
            ]
        )
        await model.load()

        model.searchText = "milk"
        #expect(model.visibleTasks.map(\.id) == ["t1"])

        model.searchText = "MORTGAGE"
        #expect(model.visibleTasks.map(\.id) == ["t2"])

        model.searchText = "   "
        #expect(model.visibleTasks.count == 2)
    }

    @Test("the list filter keeps one collection's tasks")
    func listFilter() async throws {
        let (model, _) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [
                    Self.collection(id: "home", sourceID: "s1"),
                    Self.collection(id: "work", sourceID: "s1"),
                ],
            ],
            tasks: [
                "s1": [
                    Self.task(
                        id: "t1", sourceID: "s1", collectionID: "home"
                    ),
                    Self.task(
                        id: "t2", sourceID: "s1", collectionID: "work"
                    ),
                ],
            ]
        )
        await model.load()

        model.selectedCollectionID = "work"
        #expect(model.visibleTasks.map(\.id) == ["t2"])

        model.selectedCollectionID = nil
        #expect(model.visibleTasks.count == 2)
    }

    @Test("the completed toggle hides done and cancelled tasks")
    func completedToggle() async throws {
        let (model, _) = try await makeModel(
            sources: [Self.source(id: "s1")],
            tasks: [
                "s1": [
                    Self.task(
                        id: "open", sourceID: "s1", collectionID: "c1"
                    ),
                    Self.task(
                        id: "done", sourceID: "s1", collectionID: "c1",
                        status: .completed
                    ),
                    Self.task(
                        id: "cancelled", sourceID: "s1",
                        collectionID: "c1", status: .cancelled
                    ),
                ],
            ]
        )
        await model.load()

        #expect(model.visibleTasks.count == 3)

        model.showsCompleted = false
        #expect(model.visibleTasks.map(\.id) == ["open"])
    }

    // MARK: - Sections

    @Test("sections group by collection and sort by position")
    func sectionGrouping() async throws {
        let (model, _) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [
                    Self.collection(
                        id: "b", sourceID: "s1", displayName: "Beta"
                    ),
                    Self.collection(
                        id: "a", sourceID: "s1", displayName: "Alpha"
                    ),
                ],
            ],
            tasks: [
                "s1": [
                    Self.task(
                        id: "t2", sourceID: "s1", collectionID: "a",
                        position: "0002"
                    ),
                    Self.task(
                        id: "t1", sourceID: "s1", collectionID: "a",
                        position: "0001"
                    ),
                    Self.task(
                        id: "t3", sourceID: "s1", collectionID: "b"
                    ),
                ],
            ]
        )

        await model.load()

        #expect(model.sections.map(\.title) == ["Alpha", "Beta"])
        #expect(model.sections[0].tasks.map(\.id) == ["t1", "t2"])
    }

    // MARK: - Staleness

    @Test("failed, disconnected and auth-required sources read as stale")
    func staleSources() async throws {
        let (model, _) = try await makeModel(
            sources: [
                Self.source(id: "ok", status: .ready),
                Self.source(id: "broken", status: .failed),
                Self.source(id: "auth", status: .authenticationRequired),
                Self.source(id: "off", status: .disconnected),
                Self.source(id: "partial", status: .permissionLimited),
            ]
        )

        await model.load()

        #expect(
            model.staleSources.map(\.id).sorted()
                == ["auth", "broken", "off"]
        )
    }

    @Test("lastSyncAt is the newest cache write")
    func lastSyncAt() async throws {
        let (model, _) = try await makeModel(
            sources: [Self.source(id: "s1")],
            tasks: [
                "s1": [
                    Self.task(
                        id: "old", sourceID: "s1", collectionID: "c1",
                        syncedAt: Date(timeIntervalSince1970: 100)
                    ),
                    Self.task(
                        id: "new", sourceID: "s1", collectionID: "c1",
                        syncedAt: Date(timeIntervalSince1970: 200)
                    ),
                ],
            ]
        )

        await model.load()

        #expect(
            model.lastSyncAt == Date(timeIntervalSince1970: 200)
        )
    }

    // MARK: - Sync gating + selection

    @Test("sync gating follows the service's syncable statuses")
    func canSyncNow() async throws {
        let (model, _) = try await makeModel(sources: [])
        let ready = Self.source(id: "r", status: .ready)
        let failed = Self.source(id: "f", status: .failed)
        let connecting = Self.source(id: "c", status: .connecting)
        let auth = Self.source(id: "a", status: .authenticationRequired)

        #expect(model.canSyncNow(ready))
        #expect(model.canSyncNow(failed))
        #expect(!model.canSyncNow(connecting))
        #expect(!model.canSyncNow(auth))
    }

    @Test("a reload drops a selection whose task left the cache")
    func reconcileSelection() async throws {
        let (model, taskStore) = try await makeModel(
            sources: [Self.source(id: "s1")],
            tasks: [
                "s1": [
                    Self.task(
                        id: "t1", sourceID: "s1", collectionID: "c1"
                    ),
                ],
            ]
        )
        await model.load()
        model.selectedTaskID = "t1"

        try await taskStore.deleteTasks(
            for: "s1", collectionID: "c1"
        )
        await model.load()

        #expect(model.selectedTaskID == nil)
    }

    // MARK: - Deep links

    @Test("revealTask selects the record and clears the filters")
    func revealTaskSelects() async throws {
        let (model, _) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [
                    Self.collection(id: "c1", sourceID: "s1"),
                    Self.collection(id: "c2", sourceID: "s1"),
                ],
            ],
            tasks: [
                "s1": [
                    Self.task(
                        id: "t1", sourceID: "s1", collectionID: "c2",
                        status: .completed
                    ),
                ],
            ]
        )
        await model.load()
        model.searchText = "unrelated"
        model.selectedCollectionID = "c1"
        model.showsCompleted = false

        await model.revealTask(id: "t1")

        #expect(model.selectedTaskID == "t1")
        #expect(model.searchText == "")
        #expect(model.selectedCollectionID == nil)
        #expect(model.showsCompleted)
        #expect(model.deepLinkNotice == nil)
    }

    @Test("revealTask on a missing record clears the selection and reports")
    func revealTaskMiss() async throws {
        let (model, _) = try await makeModel(
            sources: [Self.source(id: "s1")],
            tasks: [
                "s1": [
                    Self.task(
                        id: "t1", sourceID: "s1", collectionID: "c1"
                    ),
                ],
            ]
        )
        await model.load()
        model.selectedTaskID = "t1"

        await model.revealTask(id: "gone")

        #expect(model.selectedTaskID == nil)
        #expect(model.deepLinkNotice != nil)
    }

    @Test("revealTask loads the cache when the window is cold")
    func revealTaskColdLoad() async throws {
        let (model, _) = try await makeModel(
            sources: [Self.source(id: "s1")],
            tasks: [
                "s1": [
                    Self.task(
                        id: "t1", sourceID: "s1", collectionID: "c1"
                    ),
                ],
            ]
        )
        // No explicit load() — the reveal must load before it judges
        // a hit or a miss.
        await model.revealTask(id: "t1")

        #expect(model.selectedTaskID == "t1")
        #expect(model.deepLinkNotice == nil)
    }
}
