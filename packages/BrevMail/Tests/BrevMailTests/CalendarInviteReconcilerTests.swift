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

import BrevBackend
import BrevCalendar
@testable import BrevMail
import Foundation
import Testing

/// RSVP reconciliation (#10): the mail response patches the synced
/// event's matching attendee through the shared write service, with
/// explicit outcomes for unsynced, read-only, and unmatched cases.
@Suite("CalendarInviteReconciler")
@MainActor
struct CalendarInviteReconcilerTests {
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

    private actor EventStore: PIMEventStore {
        var records: [PIMSource.ID: [PIMEvent]] = [:]

        func events(
            for sourceID: PIMSource.ID
        ) async throws -> [PIMEvent] {
            records[sourceID] ?? []
        }

        func events(
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws -> [PIMEvent] {
            (records[sourceID] ?? []).filter {
                $0.collectionID == collectionID
            }
        }

        func saveEvents(
            _ events: [PIMEvent],
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws {
            var all = records[sourceID] ?? []
            all.removeAll { $0.collectionID == collectionID }
            all.append(contentsOf: events)
            records[sourceID] = all
        }

        func deleteEvents(
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws {
            records[sourceID]?.removeAll { $0.collectionID == collectionID }
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

    private final class RecordingWriter: CalendarEventWriting,
        @unchecked Sendable {
        enum Call: Equatable {
            case update(PIMEvent, PIMCollection.ID)
        }

        private(set) var calls: [Call] = []
        var allowsWrite = true
        var updateError: (any Error)?

        func canWrite(
            source: PIMSource,
            collection: PIMCollection
        ) -> Bool { allowsWrite }

        func create(
            _ event: PIMEvent,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws -> PIMEvent { event }

        func update(
            _ event: PIMEvent,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws -> PIMEvent {
            calls.append(.update(event, collection.id))
            if let updateError { throw updateError }
            return event
        }

        func delete(
            _ event: PIMEvent,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws {}
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func source(
        id: String = "cal-1",
        writable: Bool = true
    ) -> PIMSource {
        PIMSource(
            id: id,
            kind: .calendar,
            provider: .calDAV,
            displayName: id,
            enabledCapabilities: writable ? [.read, .write] : [.read],
            status: .ready,
            createdAt: Self.fixedNow,
            updatedAt: Self.fixedNow
        )
    }

    private func collection(
        id: String = "c1",
        sourceID: String = "cal-1"
    ) -> PIMCollection {
        PIMCollection(
            id: id,
            sourceID: sourceID,
            kind: .calendar,
            displayName: id,
            colorHex: nil,
            isReadOnly: false,
            isPrimary: true,
            supportsSyncToken: true,
            providerKey: id,
            providerVersion: nil,
            isVisible: true,
            updatedAt: Self.fixedNow
        )
    }

    private func event(
        uid: String = "invite-1@example.org",
        sourceID: String = "cal-1",
        collectionID: String = "c1",
        attendees: [PIMEventPerson]
    ) -> PIMEvent {
        PIMEvent(
            id: PIMEvent.makeID(
                collectionID: collectionID,
                providerItemKey: "e1",
                recurrenceID: nil
            ),
            sourceID: sourceID,
            collectionID: collectionID,
            providerItemKey: "e1",
            uid: uid,
            summary: "Sync",
            attendees: attendees,
            syncedAt: Self.fixedNow
        )
    }

    private func invite(uid: String? = "invite-1@example.org")
        -> ICSParser.ParsedEvent {
        ICSParser.ParsedEvent(
            uid: uid,
            summary: "Sync",
            description: nil,
            location: nil,
            start: Self.fixedNow,
            end: Self.fixedNow.addingTimeInterval(3600),
            isAllDay: false,
            organizer: nil,
            attendees: []
        )
    }

    private func makeReconciler(
        sources: [PIMSource],
        events: [PIMSource.ID: [PIMEvent]],
        collections: [PIMSource.ID: [PIMCollection]],
        writer: RecordingWriter
    ) async throws -> CalendarInviteReconciler {
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
        let eventStore = EventStore()
        for (sourceID, list) in events {
            for event in list {
                try await eventStore.saveEvents(
                    [event],
                    for: sourceID,
                    collectionID: event.collectionID
                )
            }
        }
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
        let syncService = PIMEventSyncService(
            coordinator: coordinator,
            collectionStore: collectionStore,
            eventStore: eventStore,
            cursorStore: CursorStore(),
            credentials: CredentialStore(),
            now: { Self.fixedNow }
        )
        return CalendarInviteReconciler(
            coordinator: coordinator,
            eventSyncService: syncService,
            collectionService: collectionService,
            writeService: writer
        )
    }

    @Test("the matching attendee's RSVP is written through the service")
    func updatesMatchingAttendee() async throws {
        let writer = RecordingWriter()
        let reconciler = try await makeReconciler(
            sources: [source()],
            events: [
                "cal-1": [
                    event(
                        attendees: [
                            PIMEventPerson(
                                email: "me@example.com",
                                rsvp: .needsAction
                            ),
                            PIMEventPerson(
                                email: "other@example.com",
                                rsvp: .needsAction
                            )
                        ]
                    )
                ]
            ],
            collections: ["cal-1": [collection()]],
            writer: writer
        )
        let outcome = await reconciler.reconcile(
            invite: invite(),
            response: .accepted,
            accountEmail: "me@example.com",
            recipientEmails: []
        )
        #expect(outcome == .updated(sourceName: "cal-1"))
        guard case .update(let written, _) = writer.calls.first else {
            Issue.record("expected an update call")
            return
        }
        #expect(written.attendees[0].rsvp == .accepted)
        #expect(written.attendees[1].rsvp == .needsAction)
    }

    @Test("an uncached invite reports notSynced")
    func uncachedInviteNotSynced() async throws {
        let writer = RecordingWriter()
        let reconciler = try await makeReconciler(
            sources: [source()],
            events: [:],
            collections: ["cal-1": [collection()]],
            writer: writer
        )
        let outcome = await reconciler.reconcile(
            invite: invite(),
            response: .accepted,
            accountEmail: "me@example.com",
            recipientEmails: []
        )
        #expect(outcome == .notSynced)
        #expect(writer.calls.isEmpty)
    }

    @Test("a read-only source reports notWritable")
    func readOnlySourceNotWritable() async throws {
        let writer = RecordingWriter()
        writer.allowsWrite = false
        let reconciler = try await makeReconciler(
            sources: [source()],
            events: [
                "cal-1": [
                    event(
                        attendees: [
                            PIMEventPerson(email: "me@example.com")
                        ]
                    )
                ]
            ],
            collections: ["cal-1": [collection()]],
            writer: writer
        )
        let outcome = await reconciler.reconcile(
            invite: invite(),
            response: .declined,
            accountEmail: "me@example.com",
            recipientEmails: []
        )
        #expect(outcome == .notWritable(sourceName: "cal-1"))
        #expect(writer.calls.isEmpty)
    }

    @Test("no matching attendee reports noMatchingAttendee")
    func noMatchingAttendee() async throws {
        let writer = RecordingWriter()
        let reconciler = try await makeReconciler(
            sources: [source()],
            events: [
                "cal-1": [
                    event(
                        attendees: [
                            PIMEventPerson(email: "someone@example.com")
                        ]
                    )
                ]
            ],
            collections: ["cal-1": [collection()]],
            writer: writer
        )
        let outcome = await reconciler.reconcile(
            invite: invite(),
            response: .accepted,
            accountEmail: "me@example.com",
            recipientEmails: ["also-me@example.com"]
        )
        #expect(outcome == .noMatchingAttendee)
        #expect(writer.calls.isEmpty)
    }

    @Test("the recipient list identifies the attendee when the account address is absent")
    func recipientFallbackIdentifies() async throws {
        let writer = RecordingWriter()
        let reconciler = try await makeReconciler(
            sources: [source()],
            events: [
                "cal-1": [
                    event(
                        attendees: [
                            PIMEventPerson(
                                email: "alias@example.com",
                                rsvp: .needsAction
                            )
                        ]
                    )
                ]
            ],
            collections: ["cal-1": [collection()]],
            writer: writer
        )
        let outcome = await reconciler.reconcile(
            invite: invite(),
            response: .tentative,
            accountEmail: "primary@example.com",
            recipientEmails: ["alias@example.com"]
        )
        #expect(outcome == .updated(sourceName: "cal-1"))
        guard case .update(let written, _) = writer.calls.first else {
            Issue.record("expected an update call")
            return
        }
        #expect(written.attendees[0].rsvp == .tentative)
    }

    @Test("a write failure reports failed with the provider message")
    func writeFailureReports() async throws {
        struct Boom: LocalizedError {
            var errorDescription: String? { "etag mismatch" }
        }
        let writer = RecordingWriter()
        writer.updateError = Boom()
        let reconciler = try await makeReconciler(
            sources: [source()],
            events: [
                "cal-1": [
                    event(
                        attendees: [
                            PIMEventPerson(email: "me@example.com")
                        ]
                    )
                ]
            ],
            collections: ["cal-1": [collection()]],
            writer: writer
        )
        let outcome = await reconciler.reconcile(
            invite: invite(),
            response: .accepted,
            accountEmail: "me@example.com",
            recipientEmails: []
        )
        #expect(
            outcome == .failed(sourceName: "cal-1", message: "etag mismatch")
        )
    }

    // MARK: - Deep-link lookup

    @Test("cachedEvent finds the event behind an invite UID")
    func cachedEventFindsMatch() async throws {
        let reconciler = try await makeReconciler(
            sources: [source()],
            events: [
                "cal-1": [
                    event(
                        attendees: [
                            PIMEventPerson(email: "me@example.com")
                        ]
                    )
                ]
            ],
            collections: ["cal-1": [collection()]],
            writer: RecordingWriter()
        )

        let match = await reconciler.cachedEvent(
            forUID: "invite-1@example.org"
        )

        #expect(match?.uid == "invite-1@example.org")
        #expect(
            match?.id == PIMEvent.makeID(
                collectionID: "c1",
                providerItemKey: "e1",
                recurrenceID: nil
            )
        )
    }

    @Test("cachedEvent misses report nil instead of guessing")
    func cachedEventMisses() async throws {
        let reconciler = try await makeReconciler(
            sources: [source()],
            events: [
                "cal-1": [
                    event(
                        attendees: [
                            PIMEventPerson(email: "me@example.com")
                        ]
                    )
                ]
            ],
            collections: ["cal-1": [collection()]],
            writer: RecordingWriter()
        )

        #expect(
            await reconciler.cachedEvent(forUID: "other-uid") == nil
        )
        #expect(await reconciler.cachedEvent(forUID: "   ") == nil)
    }

    @Test("cachedEvent without services reports nil")
    func cachedEventWithoutServices() async {
        let reconciler = CalendarInviteReconciler()

        #expect(
            await reconciler.cachedEvent(forUID: "invite-1@example.org")
                == nil
        )
    }
}
