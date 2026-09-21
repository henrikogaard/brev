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

/// Authoring-model coverage for the Contacts surface (ADR-0072 #9):
/// writable-target resolution, create/update/delete dispatch, the
/// CardDAV move path, Google group membership, and error surfacing.
@Suite("ContactsEditingModel")
@MainActor
struct ContactsEditingModelTests {
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
    private final class RecordingWriter: ContactWriting,
        @unchecked Sendable {
        enum Call: Equatable {
            case create(PIMContact, PIMCollection.ID?)
            case update(PIMContact)
            case delete(PIMContact)
        }

        private(set) var calls: [Call] = []

        func canWrite(
            source: PIMSource,
            collection: PIMCollection?
        ) -> Bool {
            source.enabledCapabilities.contains(.write)
                && collection?.isReadOnly != true
        }

        func create(
            _ contact: PIMContact,
            in collection: PIMCollection?,
            source: PIMSource
        ) async throws -> PIMContact {
            calls.append(.create(contact, collection?.id))
            return contact
        }

        func update(
            _ contact: PIMContact,
            source: PIMSource
        ) async throws -> PIMContact {
            calls.append(.update(contact))
            return contact
        }

        func delete(
            _ contact: PIMContact,
            source: PIMSource
        ) async throws {
            calls.append(.delete(contact))
        }
    }

    // MARK: - Fixtures

    private nonisolated static let fixedNow = Date(
        timeIntervalSince1970: 1_800_000_000
    )

    private static func source(
        id: String,
        provider: PIMSourceProvider = .cardDAV,
        writable: Bool = true
    ) -> PIMSource {
        PIMSource(
            id: id,
            kind: .contacts,
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
        providerKey: String? = nil,
        isReadOnly: Bool = false,
        isPrimary: Bool = false
    ) -> PIMCollection {
        PIMCollection(
            id: id,
            sourceID: sourceID,
            kind: .contacts,
            displayName: id,
            colorHex: nil,
            isReadOnly: isReadOnly,
            isPrimary: isPrimary,
            supportsSyncToken: true,
            providerKey: providerKey ?? id,
            providerVersion: nil,
            isVisible: true,
            updatedAt: fixedNow
        )
    }

    private static func contact(
        id: String = "c1",
        sourceID: String = "s1",
        collectionID: String? = "book1"
    ) -> PIMContact {
        PIMContact(
            id: id,
            sourceID: sourceID,
            collectionID: collectionID,
            providerItemKey: "https://dav.example.com/c/" + id + ".vcf",
            uid: "uid-" + id + "@brev",
            displayName: "Henrik Ogard",
            syncedAt: fixedNow
        )
    }

    private func makeModel(
        sources: [PIMSource],
        collections: [PIMSource.ID: [PIMCollection]] = [:],
        writer: RecordingWriter? = nil
    ) async throws -> (ContactsEditingModel, RecordingWriter) {
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
        let model = ContactsEditingModel(
            writeService: recording,
            coordinator: coordinator,
            collectionService: collectionService,
            now: { Self.fixedNow }
        )
        return (model, recording)
    }

    // MARK: - Target resolution

    @Test("load keeps writable books and one Google account target")
    func loadFiltersTargets() async throws {
        let (model, _) = try await makeModel(
            sources: [
                Self.source(id: "dav"),
                Self.source(id: "g", provider: .google),
                Self.source(id: "ro", writable: false),
            ],
            collections: [
                "dav": [
                    Self.collection(
                        id: "book1",
                        sourceID: "dav",
                        isPrimary: true
                    ),
                    Self.collection(
                        id: "locked",
                        sourceID: "dav",
                        isReadOnly: true
                    ),
                ],
                "ro": [Self.collection(id: "book2", sourceID: "ro")],
            ]
        )

        await model.load()

        #expect(
            model.targets.map(\.id).sorted()
                == ["book1", "google:g"]
        )
        #expect(model.defaultTarget?.id == "book1")
    }

    @Test("canEdit gates on source writability and collection access")
    func editability() async throws {
        let (model, _) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [
                    Self.collection(id: "book1", sourceID: "s1"),
                    Self.collection(
                        id: "locked",
                        sourceID: "s1",
                        isReadOnly: true
                    ),
                ],
            ]
        )
        await model.load()

        #expect(model.canEdit(Self.contact(collectionID: "book1")))
        #expect(!model.canEdit(Self.contact(collectionID: "locked")))
        #expect(!model.canEdit(Self.contact(collectionID: "gone")))
    }

    // MARK: - Mutations

    @Test("save creates a new contact in the chosen book")
    func saveCreates() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [Self.collection(id: "book1", sourceID: "s1")],
            ]
        )
        await model.load()
        var draft = ContactDraft()
        draft.givenName = "Ana"
        draft.targetID = "book1"

        let saved = try await model.save(draft)

        #expect(saved.displayName == "Ana")
        guard case .create(let contact, let collectionID) =
            writer.calls.first
        else {
            Issue.record("expected a single create call")
            return
        }
        #expect(collectionID == "book1")
        #expect(contact.displayName == "Ana")
        #expect(writer.calls.count == 1)
    }

    @Test("save updates an existing contact in place")
    func saveUpdates() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [Self.collection(id: "book1", sourceID: "s1")],
            ]
        )
        await model.load()
        var draft = ContactDraft(contact: Self.contact())
        draft.note = "Met at WWDC"

        _ = try await model.save(draft)

        guard case .update(let contact) = writer.calls.first else {
            Issue.record("expected a single update call")
            return
        }
        #expect(contact.note == "Met at WWDC")
        #expect(writer.calls.count == 1)
    }

    @Test("a CardDAV move creates in the target book then deletes")
    func saveMoves() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [
                    Self.collection(id: "book1", sourceID: "s1"),
                    Self.collection(id: "book2", sourceID: "s1"),
                ],
            ]
        )
        await model.load()
        var draft = ContactDraft(contact: Self.contact())
        draft.targetID = "book2"

        _ = try await model.save(draft)

        #expect(writer.calls.count == 2)
        guard case .create(let created, let createBook) = writer.calls[0],
              case .delete(let deleted) = writer.calls[1]
        else {
            Issue.record("expected create(book2) then delete(original)")
            return
        }
        #expect(createBook == "book2")
        // The UID survives the move; the href does not.
        #expect(created.uid == "uid-c1@brev")
        #expect(
            deleted.providerItemKey
                == "https://dav.example.com/c/c1.vcf"
        )
    }

    @Test("a Google save updates memberships, never moves")
    func googleSave() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "g", provider: .google)],
            collections: [
                "g": [
                    Self.collection(
                        id: "g|contactGroups/friends",
                        sourceID: "g",
                        providerKey: "contactGroups/friends"
                    ),
                ],
            ]
        )
        await model.load()
        var draft = ContactDraft(
            contact: Self.contact(sourceID: "g", collectionID: nil)
        )
        draft.targetID = "google:g"
        draft.groupKeys = ["contactGroups/friends"]

        _ = try await model.save(draft)

        guard case .update(let contact) = writer.calls.first else {
            Issue.record("expected a single update call")
            return
        }
        #expect(contact.groupKeys == ["contactGroups/friends"])
        #expect(writer.calls.count == 1)
    }

    @Test("delete removes the contact through the write seam")
    func deleteContact() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [Self.collection(id: "book1", sourceID: "s1")],
            ]
        )
        await model.load()

        try await model.delete(Self.contact())

        guard case .delete = writer.calls.first else {
            Issue.record("expected a single delete call")
            return
        }
        #expect(writer.calls.count == 1)
    }

    // MARK: - Errors

    @Test("save without a writable target surfaces notWritable")
    func saveRequiresTarget() async throws {
        let (model, writer) = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [Self.collection(id: "book1", sourceID: "s1")],
            ]
        )
        await model.load()
        var draft = ContactDraft()
        draft.givenName = "Nowhere"
        draft.targetID = "missing"

        await #expect(
            throws: PIMContactWriteService.WriteError.notWritable
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
        let model = ContactsEditingModel(
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
