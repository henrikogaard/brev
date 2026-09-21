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

/// Authoring-model coverage for the Calendar surface (ADR-0072 #7):
/// writable-target resolution, create/update/delete dispatch, the
/// move and future-scope paths, and error surfacing.
@Suite("CalendarEditingModel")
@MainActor
struct CalendarEditingModelTests {
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
    /// the real service's capability + read-only rule.
    private final class RecordingWriter: CalendarEventWriting,
        @unchecked Sendable {
        enum Call: Equatable {
            case create(PIMEvent, PIMCollection.ID)
            case update(PIMEvent, PIMCollection.ID)
            case delete(PIMEvent, PIMCollection.ID)
        }

        private(set) var calls: [Call] = []

        func canWrite(
            source: PIMSource,
            collection: PIMCollection
        ) -> Bool {
            source.enabledCapabilities.contains(.write)
                && !collection.isReadOnly
        }

        func create(
            _ event: PIMEvent,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws -> PIMEvent {
            calls.append(.create(event, collection.id))
            return event
        }

        func update(
            _ event: PIMEvent,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws -> PIMEvent {
            calls.append(.update(event, collection.id))
            return event
        }

        func delete(
            _ event: PIMEvent,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws {
            calls.append(.delete(event, collection.id))
        }
    }

    // MARK: - Fixtures

    private nonisolated static let fixedNow = Date(
        timeIntervalSince1970: 1_800_000_000
    )

    private static func source(
        id: String,
        kind: PIMSourceKind = .calendar,
        provider: PIMSourceProvider = .calDAV,
        writable: Bool = true
    ) -> PIMSource {
        PIMSource(
            id: id,
            kind: kind,
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
            kind: .calendar,
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

    private static func event(
        id: String = "e1",
        sourceID: String = "s1",
        collectionID: String = "c1",
        recurrenceRule: ICSParser.RecurrenceRule? = nil
    ) -> PIMEvent {
        PIMEvent(
            id: id,
            sourceID: sourceID,
            collectionID: collectionID,
            providerItemKey: id,
            uid: "uid-\(id)@brev",
            summary: "Standup",
            start: fixedNow,
            end: fixedNow.addingTimeInterval(1800),
            recurrenceRule: recurrenceRule,
            syncedAt: fixedNow
        )
    }

    private static func dailyRule() -> ICSParser.RecurrenceRule {
        ICSParser.RecurrenceRule(
            frequency: .daily,
            interval: 1,
            count: nil,
            until: nil,
            byDay: nil
        )
    }

    private func makeModel(
        sources: [PIMSource],
        collections: [PIMSource.ID: [PIMCollection]] = [:],
        writer: RecordingWriter? = nil
    ) async throws -> (CalendarEditingModel, RecordingWriter) {
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
        let model = CalendarEditingModel(
            writeService: recording,
            coordinator: coordinator,
            collectionService: collectionService,
            now: { Self.fixedNow }
        )
        return (model, recording)
    }

    // MARK: - Target resolution

    @Test("load keeps only writable calendar collections")
    func loadFiltersTargets() async throws {
        let (model, _) = try await makeModel(
            sources: [
                Self.source(id: "writable"),
                Self.source(id: "readonly-source", writable: false),
                Self.source(id: "contacts", kind: .contacts),
            ],
            collections: [
                "writable": [
                    Self.collection(id: "open", sourceID: "writable"),
                    Self.collection(
                        id: "locked",
                        sourceID: "writable",
                        isReadOnly: true
                    ),
                ],
                "readonly-source": [
                    Self.collection(id: "ro", sourceID: "readonly-source"),
                ],
                "contacts": [
                    Self.collection(id: "addr", sourceID: "contacts"),
                ],
            ]
        )

        await model.load()

        #expect(model.targets.map(\.collection.id) == ["open"])
        #expect(model.defaultTarget?.collection.id == "open")
    }

    @Test("defaultTarget prefers the primary collection")
    func defaultTargetPrefersPrimary() async throws {
        let (model, _) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [
                    Self.collection(id: "other", sourceID: "s1"),
                    Self.collection(
                        id: "main",
                        sourceID: "s1",
                        isPrimary: true
                    ),
                ],
            ]
        )

        await model.load()

        #expect(model.defaultTarget?.collection.id == "main")
    }

    @Test("canEdit and needsScopeChoice reflect the loaded targets")
    func editability() async throws {
        let (model, _) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [Self.collection(id: "c1", sourceID: "s1")],
            ]
        )
        await model.load()

        #expect(model.canEdit(Self.event(collectionID: "c1")))
        #expect(!model.canEdit(Self.event(collectionID: "elsewhere")))
        #expect(!model.needsScopeChoice(for: Self.event()))
        #expect(
            model.needsScopeChoice(
                for: Self.event(recurrenceRule: Self.dailyRule())
            )
        )
    }

    // MARK: - Mutations

    @Test("save creates a new event in the chosen target")
    func saveCreates() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [Self.collection(id: "c1", sourceID: "s1")],
            ]
        )
        await model.load()
        var draft = CalendarEventDraft(start: Self.fixedNow)
        draft.summary = "Planning"
        draft.targetCollectionID = "c1"

        let saved = try await model.save(draft)

        #expect(saved.summary == "Planning")
        guard case .create(let event, let collectionID) = writer.calls.first
        else {
            Issue.record("expected a single create call")
            return
        }
        #expect(collectionID == "c1")
        #expect(writer.calls.count == 1)
        #expect(event.summary == "Planning")
    }

    @Test("save updates an existing event in place")
    func saveUpdates() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [Self.collection(id: "c1", sourceID: "s1")],
            ]
        )
        await model.load()
        var draft = CalendarEventDraft(
            event: Self.event(collectionID: "c1")
        )
        draft.summary = "Renamed"

        _ = try await model.save(draft)

        guard case .update(let event, let collectionID) = writer.calls.first
        else {
            Issue.record("expected a single update call")
            return
        }
        #expect(collectionID == "c1")
        #expect(event.summary == "Renamed")
        #expect(writer.calls.count == 1)
    }

    @Test("a moved event is created in the target then deleted from the source")
    func saveMoves() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [
                    Self.collection(id: "c1", sourceID: "s1"),
                    Self.collection(id: "c2", sourceID: "s1"),
                ],
            ]
        )
        await model.load()
        var draft = CalendarEventDraft(
            event: Self.event(collectionID: "c1")
        )
        draft.targetCollectionID = "c2"

        _ = try await model.save(draft)

        #expect(writer.calls.count == 2)
        guard case .create(let created, let createCollection) =
            writer.calls[0],
            case .delete(let deleted, let deleteCollection) =
            writer.calls[1]
        else {
            Issue.record("expected create(c2) then delete(c1)")
            return
        }
        #expect(createCollection == "c2")
        #expect(deleteCollection == "c1")
        // The UID survives the move; the provider key does not.
        #expect(created.uid == "uid-e1@brev")
        #expect(deleted.providerItemKey == "e1")
    }

    @Test("future scope truncates the master and creates a new series")
    func saveFutureScope() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [Self.collection(id: "c1", sourceID: "s1")],
            ]
        )
        await model.load()
        var draft = CalendarEventDraft(
            event: Self.event(
                collectionID: "c1",
                recurrenceRule: Self.dailyRule()
            )
        )
        draft.summary = "New time"

        _ = try await model.save(draft, scope: .future)

        #expect(writer.calls.count == 2)
        guard case .update(let truncated, _) = writer.calls[0],
              case .create(let newSeries, let newCollection) = writer.calls[1]
        else {
            Issue.record("expected update(master) then create(series)")
            return
        }
        // The master ends the day before the edited occurrence.
        let expectedUntil = Calendar.current.date(
            byAdding: .day,
            value: -1,
            to: Self.fixedNow
        )
        #expect(truncated.recurrenceRule?.until == expectedUntil)
        #expect(truncated.recurrenceRule?.count == nil)
        #expect(newCollection == "c1")
        #expect(newSeries.summary == "New time")
        #expect(newSeries.uid == nil)
        #expect(newSeries.providerItemKey == "draft")
    }

    @Test("delete removes a non-recurring event outright")
    func deleteSeries() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [Self.collection(id: "c1", sourceID: "s1")],
            ]
        )
        await model.load()

        try await model.delete(Self.event(collectionID: "c1"))

        guard case .delete(_, let collectionID) = writer.calls.first
        else {
            Issue.record("expected a single delete call")
            return
        }
        #expect(collectionID == "c1")
        #expect(writer.calls.count == 1)
    }

    @Test("future delete truncates the master instead of removing it")
    func deleteFuture() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [Self.collection(id: "c1", sourceID: "s1")],
            ]
        )
        await model.load()

        try await model.delete(
            Self.event(
                collectionID: "c1",
                recurrenceRule: Self.dailyRule()
            ),
            scope: .future
        )

        guard case .update(let truncated, _) = writer.calls.first
        else {
            Issue.record("expected a truncating update call")
            return
        }
        let expectedUntil = Calendar.current.date(
            byAdding: .day,
            value: -1,
            to: Self.fixedNow
        )
        #expect(truncated.recurrenceRule?.until == expectedUntil)
        #expect(writer.calls.count == 1)
    }

    // MARK: - Errors

    @Test("save without a writable target surfaces notWritable")
    func saveRequiresTarget() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [Self.collection(id: "c1", sourceID: "s1")],
            ]
        )
        await model.load()
        var draft = CalendarEventDraft(start: Self.fixedNow)
        draft.summary = "Nowhere"
        draft.targetCollectionID = "missing"

        await #expect(
            throws: PIMEventWriteService.WriteError.notWritable
        ) {
            try await model.save(draft)
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
        let model = CalendarEditingModel(
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
