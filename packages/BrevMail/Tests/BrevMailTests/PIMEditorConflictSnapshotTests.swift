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

/// Contact and task editor snapshots: the save-error callout must sit
/// above the fold so a conflict on a long record is visible without
/// scrolling.
@Suite("PIM editor conflict snapshots")
@MainActor
struct PIMEditorConflictSnapshotTests {
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

    private struct ConflictTaskWriter: TaskWriting {
        func canWrite(
            source: PIMSource,
            collection: PIMCollection
        ) -> Bool { true }

        func create(
            _ task: PIMTask,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws -> PIMTask {
            throw PIMTaskWriteService.WriteError.conflict
        }

        func update(
            _ task: PIMTask,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws -> PIMTask {
            throw PIMTaskWriteService.WriteError.conflict
        }

        func delete(
            _ task: PIMTask,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws {
            throw PIMTaskWriteService.WriteError.conflict
        }

        func move(
            _ task: PIMTask,
            to target: PIMCollection,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws -> PIMTask {
            throw PIMTaskWriteService.WriteError.conflict
        }
    }

    private struct ConflictContactWriter: ContactWriting {
        func canWrite(
            source: PIMSource,
            collection: PIMCollection?
        ) -> Bool { true }

        func create(
            _ contact: PIMContact,
            in collection: PIMCollection?,
            source: PIMSource
        ) async throws -> PIMContact {
            throw PIMContactWriteService.WriteError.conflict
        }

        func update(
            _ contact: PIMContact,
            source: PIMSource
        ) async throws -> PIMContact {
            throw PIMContactWriteService.WriteError.conflict
        }

        func delete(
            _ contact: PIMContact,
            source: PIMSource
        ) async throws {
            throw PIMContactWriteService.WriteError.conflict
        }
    }

    // MARK: - Fixtures

    private nonisolated static let fixedNow = Date(
        timeIntervalSince1970: 1_800_000_000
    )

    private nonisolated static func source(
        kind: PIMSourceKind
    ) -> PIMSource {
        PIMSource(
            id: "s1",
            kind: kind,
            provider: kind == .tasks ? .calDAV : .cardDAV,
            displayName: "s1",
            enabledCapabilities: [.read, .write],
            status: .ready,
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
    }

    private nonisolated static func collection(
        kind: PIMSourceKind
    ) -> PIMCollection {
        PIMCollection(
            id: "c1",
            sourceID: "s1",
            kind: kind,
            displayName: kind == .tasks ? "Tasks" : "Work",
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

    private nonisolated static func contact() -> PIMContact {
        PIMContact(
            id: PIMContact.makeID(
                sourceID: "s1",
                providerItemKey: "alice.vcf"
            ),
            sourceID: "s1",
            collectionID: "c1",
            providerItemKey: "alice.vcf",
            providerVersion: "\"v1\"",
            uid: "uid-alice@brev",
            displayName: "Alice Fjord",
            emails: [
                PIMContactField(label: "work", value: "a@example.com"),
            ],
            syncedAt: fixedNow
        )
    }

    private nonisolated static func task() -> PIMTask {
        PIMTask(
            id: PIMTask.makeID(
                collectionID: "c1",
                providerItemKey: "t1.ics"
            ),
            sourceID: "s1",
            collectionID: "c1",
            providerItemKey: "t1.ics",
            providerVersion: "\"e1\"",
            uid: "uid-t1@brev",
            title: "Send the harbour proposal",
            notes: "Include the revised berth figures.",
            status: .needsAction,
            syncedAt: fixedNow
        )
    }

    /// Stores plus the coordinator/collectionService built over them,
    /// seeded with one source and one collection of the given kind.
    private nonisolated static func seeded(
        kind: PIMSourceKind
    ) async throws -> (
        PIMSourceCoordinator,
        PIMCollectionService
    ) {
        let sourceStore = SourceStore()
        try await sourceStore.save(Self.source(kind: kind))
        let credentials = CredentialStore()
        let coordinator = PIMSourceCoordinator(
            store: sourceStore,
            credentials: credentials,
            localData: LocalDataStore(),
            now: { Self.fixedNow }
        )
        let collectionStore = CollectionStore()
        try await collectionStore.saveCollections(
            [Self.collection(kind: kind)],
            for: "s1"
        )
        let collectionService = PIMCollectionService(
            coordinator: coordinator,
            store: collectionStore,
            credentials: credentials,
            now: { Self.fixedNow }
        )
        return (coordinator, collectionService)
    }

    // MARK: - Snapshots

    @Test("contact save conflict renders the callout above the fold")
    func contactConflictCalloutAboveFold() async throws {
        let (coordinator, collectionService) = try await Self.seeded(
            kind: .contacts
        )
        let model = ContactsEditingModel(
            writeService: ConflictContactWriter(),
            coordinator: coordinator,
            collectionService: collectionService,
            now: { Self.fixedNow }
        )
        await model.load()

        var draft = ContactDraft(contact: Self.contact())
        draft.givenName = "Alice-2"
        _ = try? await model.save(draft)

        let theme = BrevTheme.brevPaper
        let view = ContactEditorView(
            editing: model,
            contact: Self.contact(),
            source: Self.source(kind: .contacts)
        )
        .brevTheme(theme)
        .background(theme.bgPrimary.color)
        .frame(width: 440, height: 640)
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 440, height: 640)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 440, height: 640)),
            named: "contact-conflict-callout",
            record: ProcessInfo.processInfo
                .environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("task save conflict renders the callout above the fold")
    func taskConflictCalloutAboveFold() async throws {
        let (coordinator, collectionService) = try await Self.seeded(
            kind: .tasks
        )
        let model = TasksEditingModel(
            writeService: ConflictTaskWriter(),
            coordinator: coordinator,
            collectionService: collectionService,
            now: { Self.fixedNow }
        )
        await model.load()

        let task = Self.task()
        var draft = TaskDraft(task: task)
        draft.title = "Send the harbour proposal (revised)"
        _ = try? await model.update(draft, for: task)

        let theme = BrevTheme.brevPaper
        let view = TaskEditorView(model: model, task: task)
            .brevTheme(theme)
            .background(theme.bgPrimary.color)
            .frame(width: 440, height: 560)
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 440, height: 560)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 440, height: 560)),
            named: "task-conflict-callout",
            record: ProcessInfo.processInfo
                .environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
