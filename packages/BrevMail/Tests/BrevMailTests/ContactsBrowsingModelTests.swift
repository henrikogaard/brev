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

/// Browsing-model coverage for the Contacts surface (ADR-0072 #8):
/// cache-only loading, hidden-collection filtering (CardDAV collection
/// and Google groupKeys paths), local search, letter bucketing,
/// staleness, and per-source failure isolation.
@Suite("ContactsBrowsingModel")
@MainActor
struct ContactsBrowsingModelTests {
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

    private actor ContactStore: PIMContactStore {
        var records: [PIMSource.ID: [PIMContact]] = [:]
        /// Source IDs whose reads should throw — exercises failure
        /// isolation without touching the other sources' caches.
        private var failingSourceIDs: Set<PIMSource.ID> = []

        func failReads(for sourceID: PIMSource.ID) {
            failingSourceIDs.insert(sourceID)
        }

        func contacts(for sourceID: PIMSource.ID) async throws -> [PIMContact] {
            if failingSourceIDs.contains(sourceID) {
                throw CocoaError(.coderReadCorrupt)
            }
            return records[sourceID] ?? []
        }

        func saveContacts(
            _ contacts: [PIMContact],
            for sourceID: PIMSource.ID
        ) async throws {
            records[sourceID] = contacts
        }

        func deleteContacts(for sourceID: PIMSource.ID) async throws {
            records[sourceID] = nil
        }
    }

    private actor CursorStore: PIMContactSyncCursorStore {
        func cursor(
            for sourceID: PIMSource.ID,
            scope: String
        ) async throws -> PIMContactSyncCursor? { nil }

        func saveCursor(
            _ cursor: PIMContactSyncCursor,
            for sourceID: PIMSource.ID
        ) async throws {}

        func deleteCursor(
            for sourceID: PIMSource.ID,
            scope: String
        ) async throws {}
    }

    // MARK: - Fixtures

    private nonisolated static let fixedNow = Date(
        timeIntervalSince1970: 1_800_000_000
    )

    private static func source(
        id: String,
        kind: PIMSourceKind = .contacts,
        provider: PIMSourceProvider = .cardDAV,
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
        isVisible: Bool = true
    ) -> PIMCollection {
        PIMCollection(
            id: id,
            sourceID: sourceID,
            kind: .contacts,
            displayName: id,
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

    private static func contact(
        id: String,
        sourceID: String,
        collectionID: String? = nil,
        displayName: String? = nil,
        groupKeys: [String] = [],
        emails: [PIMContactField] = [],
        syncedAt: Date = fixedNow
    ) -> PIMContact {
        PIMContact(
            id: id,
            sourceID: sourceID,
            collectionID: collectionID,
            providerItemKey: id,
            displayName: displayName ?? id,
            emails: emails,
            groupKeys: groupKeys,
            syncedAt: syncedAt
        )
    }

    private func makeModel(
        sources: [PIMSource],
        collections: [PIMSource.ID: [PIMCollection]] = [:],
        contacts: [PIMSource.ID: [PIMContact]] = [:],
        failingSourceIDs: Set<PIMSource.ID> = []
    ) async throws -> ContactsBrowsingModel {
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
        let contactStore = ContactStore()
        for sourceID in failingSourceIDs {
            await contactStore.failReads(for: sourceID)
        }
        for (sourceID, list) in contacts {
            try await contactStore.saveContacts(list, for: sourceID)
        }
        let collectionService = PIMCollectionService(
            coordinator: coordinator,
            store: collectionStore,
            credentials: CredentialStore(),
            now: { Self.fixedNow }
        )
        let contactSyncService = PIMContactSyncService(
            coordinator: coordinator,
            collectionStore: collectionStore,
            contactStore: contactStore,
            cursorStore: CursorStore(),
            credentials: CredentialStore(),
            now: { Self.fixedNow }
        )
        return ContactsBrowsingModel(
            coordinator: coordinator,
            collectionService: collectionService,
            contactSyncService: contactSyncService,
            now: { Self.fixedNow }
        )
    }

    // MARK: - Loading

    @Test("load merges cached contacts across sources, name-sorted")
    func loadMergesSources() async throws {
        let model = try await makeModel(
            sources: [
                Self.source(id: "s1"), Self.source(id: "s2"),
            ],
            contacts: [
                "s1": [
                    Self.contact(
                        id: "z", sourceID: "s1", collectionID: "c1",
                        displayName: "Zara"
                    ),
                ],
                "s2": [
                    Self.contact(
                        id: "a", sourceID: "s2", collectionID: "c2",
                        displayName: "Ada"
                    ),
                ],
            ]
        )

        await model.load()

        #expect(model.visibleContacts.map(\.id) == ["a", "z"])
        #expect(model.lastError == nil)
        #expect(model.hasSources)
    }

    @Test("calendar sources are not loaded into the contacts surface")
    func ignoresCalendarSources() async throws {
        let model = try await makeModel(
            sources: [
                Self.source(id: "addr", kind: .contacts),
                Self.source(
                    id: "cal",
                    kind: .calendar,
                    provider: .calDAV
                ),
            ]
        )

        await model.load()

        #expect(model.sources.map(\.id) == ["addr"])
    }

    @Test("hidden CardDAV collections' contacts stay out of the list")
    func hiddenCollectionsExcluded() async throws {
        let model = try await makeModel(
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
            contacts: [
                "s1": [
                    Self.contact(
                        id: "shown", sourceID: "s1", collectionID: "c1",
                        displayName: "Shown"
                    ),
                    Self.contact(
                        id: "hidden", sourceID: "s1", collectionID: "c2",
                        displayName: "Hidden"
                    ),
                ],
            ]
        )

        await model.load()

        #expect(model.visibleContacts.map(\.id) == ["shown"])
    }

    @Test("a Google contact hides only when every group is hidden")
    func groupKeysHiddenOnlyWhenAllHidden() async throws {
        let model = try await makeModel(
            sources: [Self.source(id: "s1", provider: .google)],
            collections: [
                "s1": [
                    Self.collection(
                        id: "g1",
                        sourceID: "s1",
                        isVisible: false
                    ),
                    Self.collection(id: "g2", sourceID: "s1"),
                ],
            ],
            contacts: [
                "s1": [
                    // Member of one hidden and one visible group — shows.
                    Self.contact(
                        id: "mixed", sourceID: "s1",
                        displayName: "Mixed",
                        groupKeys: ["g1", "g2"]
                    ),
                    // Member of the hidden group only — hides.
                    Self.contact(
                        id: "allHidden", sourceID: "s1",
                        displayName: "All hidden",
                        groupKeys: ["g1"]
                    ),
                ],
            ]
        )

        await model.load()

        #expect(model.visibleContacts.map(\.id) == ["mixed"])
    }

    @Test("one unreadable source cache keeps the others and reports inline")
    func failureIsolation() async throws {
        let model = try await makeModel(
            sources: [
                Self.source(id: "good"), Self.source(id: "bad"),
            ],
            contacts: [
                "good": [
                    Self.contact(
                        id: "c1", sourceID: "good",
                        displayName: "Kept"
                    ),
                ],
            ],
            failingSourceIDs: ["bad"]
        )

        await model.load()

        #expect(model.visibleContacts.map(\.id) == ["c1"])
        #expect(model.lastError?.contains("bad") == true)
    }

    // MARK: - Search + group filter

    @Test("search matches name, organization, and email locally")
    func searchFilters() async throws {
        var byOrg = Self.contact(
            id: "c2", sourceID: "s1", displayName: "Bo"
        )
        byOrg.organization = "Ogard Labs"
        let model = try await makeModel(
            sources: [Self.source(id: "s1")],
            contacts: [
                "s1": [
                    Self.contact(
                        id: "c1", sourceID: "s1", displayName: "Ada",
                        emails: [
                            PIMContactField(
                                label: "work",
                                value: "ada@example.com"
                            ),
                        ]
                    ),
                    byOrg,
                ],
            ]
        )
        await model.load()

        model.searchText = "ada@"
        #expect(model.visibleContacts.map(\.id) == ["c1"])

        model.searchText = "OGARD"
        #expect(model.visibleContacts.map(\.id) == ["c2"])

        model.searchText = "   "
        #expect(model.visibleContacts.count == 2)
    }

    @Test("the group filter matches collectionID or groupKeys")
    func groupFilter() async throws {
        let model = try await makeModel(
            sources: [Self.source(id: "s1")],
            collections: [
                "s1": [
                    Self.collection(id: "book", sourceID: "s1"),
                    Self.collection(id: "team", sourceID: "s1"),
                ],
            ],
            contacts: [
                "s1": [
                    // CardDAV record bound to the book collection.
                    Self.contact(
                        id: "dav", sourceID: "s1", collectionID: "book",
                        displayName: "Dav"
                    ),
                    // Google record carrying the team group key.
                    Self.contact(
                        id: "goog", sourceID: "s1",
                        displayName: "Goog",
                        groupKeys: ["team"]
                    ),
                ],
            ]
        )
        await model.load()

        model.selectedCollectionID = "team"
        #expect(model.visibleContacts.map(\.id) == ["goog"])

        model.selectedCollectionID = "book"
        #expect(model.visibleContacts.map(\.id) == ["dav"])

        model.selectedCollectionID = nil
        #expect(model.visibleContacts.count == 2)
    }

    // MARK: - Letter bucketing

    @Test("contacts bucket by initial letter; non-letters trail under #")
    func letterBucketing() async throws {
        let model = try await makeModel(
            sources: [Self.source(id: "s1")],
            contacts: [
                "s1": [
                    Self.contact(
                        id: "b", sourceID: "s1", displayName: "Bo"
                    ),
                    Self.contact(
                        id: "a", sourceID: "s1", displayName: "Ada"
                    ),
                    Self.contact(
                        id: "num", sourceID: "s1", displayName: "3M"
                    ),
                ],
            ]
        )

        await model.load()

        #expect(model.sections.map(\.letter) == ["A", "B", "#"])
        #expect(model.sections[0].contacts.map(\.id) == ["a"])
        #expect(model.sections[2].contacts.map(\.id) == ["num"])
    }

    // MARK: - Staleness

    @Test("failed, disconnected and auth-required sources read as stale")
    func staleSources() async throws {
        let model = try await makeModel(
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
        let model = try await makeModel(
            sources: [Self.source(id: "s1")],
            contacts: [
                "s1": [
                    Self.contact(
                        id: "old", sourceID: "s1",
                        syncedAt: Date(timeIntervalSince1970: 100)
                    ),
                    Self.contact(
                        id: "new", sourceID: "s1",
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
        let model = try await makeModel(sources: [])
        let ready = Self.source(id: "r", status: .ready)
        let failed = Self.source(id: "f", status: .failed)
        let connecting = Self.source(id: "c", status: .connecting)
        let auth = Self.source(id: "a", status: .authenticationRequired)

        #expect(model.canSyncNow(ready))
        #expect(model.canSyncNow(failed))
        #expect(!model.canSyncNow(connecting))
        #expect(!model.canSyncNow(auth))
    }

    @Test("a reload drops a selection whose contact left the cache")
    func reconcileSelection() async throws {
        let contactStore = ContactStore()
        let source = Self.source(id: "s1")
        let sourceStore = SourceStore()
        try await sourceStore.save(source)
        let coordinator = PIMSourceCoordinator(
            store: sourceStore,
            credentials: CredentialStore(),
            localData: LocalDataStore(),
            now: { Self.fixedNow }
        )
        let contactSyncService = PIMContactSyncService(
            coordinator: coordinator,
            collectionStore: CollectionStore(),
            contactStore: contactStore,
            cursorStore: CursorStore(),
            credentials: CredentialStore(),
            now: { Self.fixedNow }
        )
        let model = ContactsBrowsingModel(
            coordinator: coordinator,
            contactSyncService: contactSyncService,
            now: { Self.fixedNow }
        )
        try await contactStore.saveContacts(
            [Self.contact(id: "c1", sourceID: "s1", displayName: "Ada")],
            for: "s1"
        )
        await model.load()
        model.selectedContactID = "c1"

        // The next generation no longer contains the contact — the
        // selection must clear rather than point at a dead record.
        try await contactStore.saveContacts([], for: "s1")
        await model.load()

        #expect(model.selectedContactID == nil)
    }
}
