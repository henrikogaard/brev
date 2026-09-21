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

/// Routing for Create Event from Message (#10): the shared editor is
/// used only when the session can author events and at least one
/// writable calendar target resolved; every other case keeps the
/// EventKit sheet.
@Suite("MessageCreateEventRouting")
@MainActor
struct MessageCreateEventRoutingTests {
    private actor SourceStore: PIMSourceStore {
        var records: [PIMSource] = []

        func allSources() async throws -> [PIMSource] { records }

        func save(_ source: PIMSource) async throws {
            records.append(source)
        }

        func deleteSource(id: PIMSource.ID) async throws {}
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

    private final class Writer: CalendarEventWriting, @unchecked Sendable {
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
        ) async throws -> PIMEvent { event }

        func update(
            _ event: PIMEvent,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws -> PIMEvent { event }

        func delete(
            _ event: PIMEvent,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws {}
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeModel(
        writable: Bool
    ) async throws -> CalendarEditingModel {
        let sourceStore = SourceStore()
        try await sourceStore.save(
            PIMSource(
                id: "s1",
                kind: .calendar,
                provider: .calDAV,
                displayName: "Work",
                enabledCapabilities: writable ? [.read, .write] : [.read],
                status: .ready,
                createdAt: Self.fixedNow,
                updatedAt: Self.fixedNow
            )
        )
        let coordinator = PIMSourceCoordinator(
            store: sourceStore,
            credentials: CredentialStore(),
            localData: LocalDataStore(),
            now: { Self.fixedNow }
        )
        let collectionStore = CollectionStore()
        try await collectionStore.saveCollections(
            [
                PIMCollection(
                    id: "c1",
                    sourceID: "s1",
                    kind: .calendar,
                    displayName: "Calendar",
                    colorHex: nil,
                    isReadOnly: false,
                    isPrimary: true,
                    supportsSyncToken: true,
                    providerKey: "c1",
                    providerVersion: nil,
                    isVisible: true,
                    updatedAt: Self.fixedNow
                )
            ],
            for: "s1"
        )
        let collectionService = PIMCollectionService(
            coordinator: coordinator,
            store: collectionStore,
            credentials: CredentialStore(),
            now: { Self.fixedNow }
        )
        return CalendarEditingModel(
            writeService: Writer(),
            coordinator: coordinator,
            collectionService: collectionService
        )
    }

    @Test("no editing model keeps the EventKit fallback")
    func nilEditingFallsBack() {
        #expect(MessageCreateEventRouting.usesSharedEditor(editing: nil) == false)
    }

    @Test("no write service keeps the EventKit fallback")
    func noWriteServiceFallsBack() {
        let model = CalendarEditingModel()
        #expect(MessageCreateEventRouting.usesSharedEditor(editing: model) == false)
    }

    @Test("a resolved writable calendar uses the shared editor")
    func writableTargetUsesSharedEditor() async throws {
        let model = try await makeModel(writable: true)
        await model.load()
        #expect(MessageCreateEventRouting.usesSharedEditor(editing: model) == true)
    }

    @Test("a read-only source keeps the EventKit fallback")
    func readOnlySourceFallsBack() async throws {
        let model = try await makeModel(writable: false)
        await model.load()
        #expect(MessageCreateEventRouting.usesSharedEditor(editing: model) == false)
    }
}
