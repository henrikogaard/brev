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
import BrevCalendar
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

/// Editor-surface snapshots: the save-error callout must sit above
/// the fold so a conflict on a long event is visible without
/// scrolling.
@Suite("Calendar event editor snapshots")
@MainActor
struct CalendarEventEditorSnapshotTests {
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

    /// Answers `.conflict` to every write so the editor renders its
    /// save-failure callout.
    private struct ConflictWriter: CalendarEventWriting {
        func canWrite(
            source: PIMSource,
            collection: PIMCollection
        ) -> Bool { true }

        func create(
            _ event: PIMEvent,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws -> PIMEvent {
            throw PIMEventWriteService.WriteError.conflict
        }

        func update(
            _ event: PIMEvent,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws -> PIMEvent {
            throw PIMEventWriteService.WriteError.conflict
        }

        func delete(
            _ event: PIMEvent,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws {
            throw PIMEventWriteService.WriteError.conflict
        }
    }

    // MARK: - Fixtures

    private nonisolated static let fixedNow = Date(
        timeIntervalSince1970: 1_800_000_000
    )

    private nonisolated static func source() -> PIMSource {
        PIMSource(
            id: "s1",
            kind: .calendar,
            provider: .calDAV,
            displayName: "s1",
            enabledCapabilities: [.read, .write],
            status: .ready,
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
    }

    private nonisolated static func collection() -> PIMCollection {
        PIMCollection(
            id: "c1",
            sourceID: "s1",
            kind: .calendar,
            displayName: "Work",
            colorHex: nil,
            isReadOnly: false,
            isPrimary: true,
            supportsSyncToken: true,
            providerKey: "c1",
            providerVersion: nil,
            isVisible: true,
            updatedAt: fixedNow
        )
    }

    private nonisolated static func event() -> PIMEvent {
        PIMEvent(
            id: "e1",
            sourceID: "s1",
            collectionID: "c1",
            providerItemKey: "e1",
            uid: "uid-e1@brev",
            summary: "Design review",
            location: "Studio",
            start: fixedNow,
            end: fixedNow.addingTimeInterval(1800),
            syncedAt: fixedNow
        )
    }

    private func conflictedModel() async throws -> CalendarEditingModel {
        let sourceStore = SourceStore()
        try await sourceStore.save(Self.source())
        let coordinator = PIMSourceCoordinator(
            store: sourceStore,
            credentials: CredentialStore(),
            localData: LocalDataStore(),
            now: { Self.fixedNow }
        )
        let collectionStore = CollectionStore()
        try await collectionStore.saveCollections(
            [Self.collection()],
            for: "s1"
        )
        let collectionService = PIMCollectionService(
            coordinator: coordinator,
            store: collectionStore,
            credentials: CredentialStore(),
            now: { Self.fixedNow }
        )
        let model = CalendarEditingModel(
            writeService: ConflictWriter(),
            coordinator: coordinator,
            collectionService: collectionService,
            now: { Self.fixedNow }
        )
        await model.load()
        var draft = CalendarEventDraft(event: Self.event())
        draft.summary = "Design review (renamed)"
        try? await model.save(draft)
        return model
    }

    // MARK: - Snapshots

    @Test("save conflict renders the error callout above the fold")
    func conflictCalloutRendersAboveFold() async throws {
        let model = try await conflictedModel()
        let theme = BrevTheme.brevPaper
        let view = CalendarEventEditorView(
            editing: model,
            event: Self.event()
        )
        .brevTheme(theme)
        .background(theme.bgPrimary.color)
        .frame(width: 440, height: 640)
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 440, height: 640)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 440, height: 640)),
            named: "conflict-callout",
            record: ProcessInfo.processInfo
                .environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
