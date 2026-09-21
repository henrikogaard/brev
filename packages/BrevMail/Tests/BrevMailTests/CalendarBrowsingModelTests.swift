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

/// Browsing-model coverage for the Calendar surface (ADR-0072 #6):
/// cache-only loading, hidden-collection filtering, local search, day
/// bucketing, staleness, and per-source failure isolation.
@Suite("CalendarBrowsingModel")
@MainActor
struct CalendarBrowsingModelTests {
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

    private actor EventStore: PIMEventStore {
        var records: [String: [PIMEvent]] = [:]
        /// Source IDs whose reads should throw — exercises failure
        /// isolation without touching the other sources' caches.
        private var failingSourceIDs: Set<PIMSource.ID> = []

        func failReads(for sourceID: PIMSource.ID) {
            failingSourceIDs.insert(sourceID)
        }

        private func key(
            _ sourceID: PIMSource.ID,
            _ collectionID: PIMCollection.ID
        ) -> String { "\(sourceID)|\(collectionID)" }

        func events(
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws -> [PIMEvent] {
            if failingSourceIDs.contains(sourceID) {
                throw CocoaError(.coderReadCorrupt)
            }
            return records[key(sourceID, collectionID)] ?? []
        }

        func events(for sourceID: PIMSource.ID) async throws -> [PIMEvent] {
            if failingSourceIDs.contains(sourceID) {
                throw CocoaError(.coderReadCorrupt)
            }
            return records
                .filter { $0.key.hasPrefix("\(sourceID)|") }
                .flatMap(\.value)
        }

        func saveEvents(
            _ events: [PIMEvent],
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws {
            records[key(sourceID, collectionID)] = events
        }

        func deleteEvents(
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws {
            records[key(sourceID, collectionID)] = nil
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
        kind: PIMSourceKind = .calendar,
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
        isVisible: Bool = true
    ) -> PIMCollection {
        PIMCollection(
            id: id,
            sourceID: sourceID,
            kind: .calendar,
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

    private static func event(
        id: String,
        sourceID: String,
        collectionID: String,
        summary: String? = nil,
        location: String? = nil,
        start: Date? = nil,
        isAllDay: Bool = false,
        syncedAt: Date = fixedNow
    ) -> PIMEvent {
        PIMEvent(
            id: id,
            sourceID: sourceID,
            collectionID: collectionID,
            providerItemKey: id,
            summary: summary,
            location: location,
            start: start,
            isAllDay: isAllDay,
            syncedAt: syncedAt
        )
    }

    private func makeModel(
        sources: [PIMSource],
        collections: [PIMSource.ID: [PIMCollection]] = [:],
        events: [String: [PIMEvent]] = [:],
        failingSourceIDs: Set<PIMSource.ID> = []
    ) async throws -> CalendarBrowsingModel {
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
        let eventStore = EventStore()
        for sourceID in failingSourceIDs {
            await eventStore.failReads(for: sourceID)
        }
        for (key, list) in events {
            let parts = key.split(separator: "|").map(String.init)
            try await eventStore.saveEvents(
                list,
                for: parts[0],
                collectionID: parts[1]
            )
        }
        let collectionService = PIMCollectionService(
            coordinator: coordinator,
            store: collectionStore,
            credentials: CredentialStore(),
            now: { Self.fixedNow }
        )
        let eventSyncService = PIMEventSyncService(
            coordinator: coordinator,
            collectionStore: collectionStore,
            eventStore: eventStore,
            cursorStore: CursorStore(),
            credentials: CredentialStore(),
            now: { Self.fixedNow }
        )
        return CalendarBrowsingModel(
            coordinator: coordinator,
            collectionService: collectionService,
            eventSyncService: eventSyncService,
            now: { Self.fixedNow },
            calendar: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "UTC")!
                return calendar
            }()
        )
    }

    // MARK: - Loading

    @Test("load merges cached events across sources, sorted by start")
    func loadMergesSources() async throws {
        let early = Self.event(
            id: "e1", sourceID: "s1", collectionID: "c1",
            summary: "Early",
            start: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let late = Self.event(
            id: "e2", sourceID: "s2", collectionID: "c2",
            summary: "Late",
            start: Date(timeIntervalSince1970: 1_800_100_000)
        )
        let model = try await makeModel(
            sources: [
                Self.source(id: "s1"), Self.source(id: "s2"),
            ],
            events: ["s1|c1": [early], "s2|c2": [late]]
        )

        await model.load()

        #expect(model.visibleEvents.map(\.id) == ["e1", "e2"])
        #expect(model.lastError == nil)
        #expect(model.hasSources)
    }

    @Test("contacts sources are not loaded into the calendar surface")
    func ignoresContactsSources() async throws {
        let model = try await makeModel(
            sources: [
                Self.source(id: "cal", kind: .calendar),
                Self.source(
                    id: "addr",
                    kind: .contacts,
                    provider: .cardDAV
                ),
            ]
        )

        await model.load()

        #expect(model.sources.map(\.id) == ["cal"])
    }

    @Test("hidden collections' events stay out of the agenda")
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
            events: [
                "s1|c1": [
                    Self.event(
                        id: "shown", sourceID: "s1", collectionID: "c1",
                        summary: "Shown",
                        start: Self.fixedNow
                    ),
                ],
                "s1|c2": [
                    Self.event(
                        id: "hidden", sourceID: "s1", collectionID: "c2",
                        summary: "Hidden",
                        start: Self.fixedNow
                    ),
                ],
            ]
        )

        await model.load()

        #expect(model.visibleEvents.map(\.id) == ["shown"])
    }

    @Test("one unreadable source cache keeps the others and reports inline")
    func failureIsolation() async throws {
        let model = try await makeModel(
            sources: [
                Self.source(id: "good"), Self.source(id: "bad"),
            ],
            events: [
                "good|c1": [
                    Self.event(
                        id: "e1", sourceID: "good", collectionID: "c1",
                        summary: "Kept",
                        start: Self.fixedNow
                    ),
                ],
            ],
            failingSourceIDs: ["bad"]
        )

        await model.load()

        #expect(model.visibleEvents.map(\.id) == ["e1"])
        #expect(model.lastError?.contains("bad") == true)
    }

    // MARK: - Search

    @Test("search matches title, location, and attendee fields locally")
    func searchFilters() async throws {
        var withAttendee = Self.event(
            id: "e2", sourceID: "s1", collectionID: "c1",
            summary: "Standup",
            start: Self.fixedNow
        )
        withAttendee.attendees = [
            PIMEventPerson(name: "Ada Lovelace", email: "ada@example.com")
        ]
        let model = try await makeModel(
            sources: [Self.source(id: "s1")],
            events: [
                "s1|c1": [
                    Self.event(
                        id: "e1", sourceID: "s1", collectionID: "c1",
                        summary: "Dentist",
                        location: "Oslo clinic",
                        start: Self.fixedNow
                    ),
                    withAttendee,
                ],
            ]
        )
        await model.load()

        model.searchText = "dentist"
        #expect(model.visibleEvents.map(\.id) == ["e1"])

        model.searchText = "OSLO"
        #expect(model.visibleEvents.map(\.id) == ["e1"])

        model.searchText = "ada@"
        #expect(model.visibleEvents.map(\.id) == ["e2"])

        model.searchText = "   "
        #expect(model.visibleEvents.count == 2)
    }

    // MARK: - Day bucketing

    @Test("events bucket by local day; undated events trail last")
    func dayBucketing() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let dayOne = calendar.date(
            from: DateComponents(year: 2026, month: 12, day: 1, hour: 9)
        )!
        let dayTwo = calendar.date(
            from: DateComponents(year: 2026, month: 12, day: 2, hour: 9)
        )!
        let model = try await makeModel(
            sources: [Self.source(id: "s1")],
            events: [
                "s1|c1": [
                    Self.event(
                        id: "later", sourceID: "s1", collectionID: "c1",
                        summary: "Day two", start: dayTwo
                    ),
                    Self.event(
                        id: "earlier", sourceID: "s1", collectionID: "c1",
                        summary: "Day one", start: dayOne
                    ),
                    Self.event(
                        id: "undated", sourceID: "s1", collectionID: "c1",
                        summary: "No date"
                    ),
                ],
            ]
        )

        await model.load()

        #expect(model.days.count == 3)
        #expect(model.days[0].events.map(\.id) == ["earlier"])
        #expect(model.days[1].events.map(\.id) == ["later"])
        #expect(model.days[2].id == "undated")
        #expect(model.days[2].day == nil)
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
            events: [
                "s1|c1": [
                    Self.event(
                        id: "old", sourceID: "s1", collectionID: "c1",
                        start: Self.fixedNow,
                        syncedAt: Date(timeIntervalSince1970: 100)
                    ),
                    Self.event(
                        id: "new", sourceID: "s1", collectionID: "c1",
                        start: Self.fixedNow,
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

    @Test("a reload drops a selection whose event left the cache")
    func reconcileSelection() async throws {
        let eventStore = EventStore()
        let source = Self.source(id: "s1")
        let sourceStore = SourceStore()
        try await sourceStore.save(source)
        let coordinator = PIMSourceCoordinator(
            store: sourceStore,
            credentials: CredentialStore(),
            localData: LocalDataStore(),
            now: { Self.fixedNow }
        )
        let eventSyncService = PIMEventSyncService(
            coordinator: coordinator,
            collectionStore: CollectionStore(),
            eventStore: eventStore,
            cursorStore: CursorStore(),
            credentials: CredentialStore(),
            now: { Self.fixedNow }
        )
        let model = CalendarBrowsingModel(
            coordinator: coordinator,
            eventSyncService: eventSyncService,
            now: { Self.fixedNow }
        )
        try await eventStore.saveEvents(
            [
                Self.event(
                    id: "e1", sourceID: "s1", collectionID: "c1",
                    start: Self.fixedNow
                ),
            ],
            for: "s1",
            collectionID: "c1"
        )
        await model.load()
        model.selectedEventID = "e1"

        // The next generation no longer contains the event — the
        // selection must clear rather than point at a dead record.
        try await eventStore.saveEvents([], for: "s1", collectionID: "c1")
        await model.load()

        #expect(model.selectedEventID == nil)
    }
}
