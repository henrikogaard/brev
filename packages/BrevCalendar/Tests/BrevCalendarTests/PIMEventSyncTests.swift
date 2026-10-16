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

@testable import BrevCalendar
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing

@Suite("PIMEventSync")
struct PIMEventSyncTests {
    // MARK: - Doubles

    /// Returns scripted responses in order and records every request.
    private final class ScriptedTransport: PIMDAVTransport, @unchecked Sendable {
        struct Step {
            let status: Int
            let headers: [String: String]
            let body: Data

            static func response(
                _ status: Int,
                headers: [String: String] = [:],
                body: String = ""
            ) -> Step {
                Step(status: status, headers: headers, body: Data(body.utf8))
            }
        }

        private(set) var requests: [URLRequest] = []
        private var steps: [Step]

        init(steps: [Step]) { self.steps = steps }

        func send(
            _ request: URLRequest
        ) async throws -> (Data, HTTPURLResponse) {
            requests.append(request)
            guard !steps.isEmpty else {
                throw URLError(.cannotConnectToHost)
            }
            let step = steps.removeFirst()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: step.status,
                httpVersion: nil,
                headerFields: step.headers
            )!
            return (step.body, response)
        }
    }

    private actor InMemorySourceStore: PIMSourceStore {
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

    private actor InMemoryCredentialStore: CalDAVCredentialStore {
        var credentials: [String: CalDAVCredential] = [:]

        func credential(for account: String) async throws -> CalDAVCredential? {
            credentials[account]
        }

        func setCredential(
            _ credential: CalDAVCredential,
            for account: String
        ) async throws {
            credentials[account] = credential
        }

        func deleteCredential(for account: String) async throws {
            credentials[account] = nil
        }
    }

    private actor InMemoryLocalDataStore: PIMSourceLocalDataStore {
        func deleteSyncAndDraftData(for sourceID: PIMSource.ID) async throws {}
        func deleteCachedContent(for sourceID: PIMSource.ID) async throws {}
        func markCacheDisconnected(for sourceID: PIMSource.ID) async throws {}
    }

    private actor InMemoryCollectionStore: PIMCollectionStore {
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

    private actor InMemoryEventStore: PIMEventStore {
        var records: [String: [PIMEvent]] = [:]
        private func key(
            _ sourceID: PIMSource.ID,
            _ collectionID: PIMCollection.ID
        ) -> String { "\(sourceID)|\(collectionID)" }

        func events(
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws -> [PIMEvent] {
            records[key(sourceID, collectionID)] ?? []
        }

        func events(for sourceID: PIMSource.ID) async throws -> [PIMEvent] {
            records
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

    private actor InMemoryCursorStore: PIMSyncCursorStore {
        var records: [String: PIMSyncCursor] = [:]
        private func key(
            _ sourceID: PIMSource.ID,
            _ collectionID: PIMCollection.ID
        ) -> String { "\(sourceID)|\(collectionID)" }

        func cursor(
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws -> PIMSyncCursor? {
            records[key(sourceID, collectionID)]
        }

        func saveCursor(
            _ cursor: PIMSyncCursor,
            for sourceID: PIMSource.ID
        ) async throws {
            records[key(sourceID, cursor.collectionID)] = cursor
        }

        func deleteCursor(
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws {
            records[key(sourceID, collectionID)] = nil
        }
    }

    // MARK: - Fixtures

    private static func source(
        provider: PIMSourceProvider = .calDAV,
        status: PIMSourceStatus = .ready
    ) -> PIMSource {
        PIMSource(
            id: "pim-test",
            kind: provider == .cardDAV ? .contacts : .calendar,
            provider: provider,
            linkedAccountID: provider == .google ? "acct-1" : nil,
            displayName: "Test",
            endpointURL: provider == .google
                ? nil
                : URL(string: "https://dav.example.com/dav/"),
            credentialAccount: provider == .google ? nil : "pim-source-pim-test",
            status: status
        )
    }

    private static func collection(
        sourceID: PIMSource.ID = "pim-test",
        providerKey: String = "https://dav.example.com/calendars/henrik/work/",
        isVisible: Bool = true,
        supportsSyncToken: Bool = true
    ) -> PIMCollection {
        PIMCollection(
            id: PIMCollection.makeID(
                sourceID: sourceID,
                providerKey: providerKey
            ),
            sourceID: sourceID,
            kind: .calendar,
            displayName: "Work",
            supportsSyncToken: supportsSyncToken,
            providerKey: providerKey,
            isVisible: isVisible
        )
    }

    private static func event(
        collectionID: PIMCollection.ID,
        providerItemKey: String,
        summary: String = "Event",
        etag: String? = nil,
        uid: String? = nil,
        start: Date? = nil
    ) -> PIMEvent {
        PIMEvent(
            id: PIMEvent.makeID(
                collectionID: collectionID,
                providerItemKey: providerItemKey
            ),
            sourceID: "pim-test",
            collectionID: collectionID,
            providerItemKey: providerItemKey,
            providerVersion: etag,
            uid: uid,
            summary: summary,
            start: start
        )
    }

    private static let sampleVEvent = """
    BEGIN:VCALENDAR
    VERSION:2.0
    BEGIN:VEVENT
    UID:event-1@example.com
    SUMMARY:Design review
    DTSTART:20260922T140000Z
    DTEND:20260922T150000Z
    STATUS:CONFIRMED
    LAST-MODIFIED:20260920T090000Z
    ORGANIZER;CN=Henrik:mailto:henrik@example.com
    ATTENDEE;CN=Ada;PARTSTAT=ACCEPTED:mailto:ada@example.com
    BEGIN:VALARM
    TRIGGER:-PT15M
    END:VALARM
    END:VEVENT
    END:VCALENDAR
    """

    private static func davSyncBody(
        members: [(href: String, etag: String?, data: String?)],
        removed: [String] = [],
        syncToken: String? = nil
    ) -> String {
        var xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
        """
        for member in members {
            xml += """
              <d:response>
                <d:href>\(member.href)</d:href>
                <d:propstat>
                  <d:prop>
                    \(member.etag.map { "<d:getetag>\($0)</d:getetag>" } ?? "")
                    \(member.data.map { "<c:calendar-data>\($0)</c:calendar-data>" } ?? "")
                  </d:prop>
                  <d:status>HTTP/1.1 200 OK</d:status>
                </d:propstat>
              </d:response>
            """
        }
        for href in removed {
            xml += """
              <d:response>
                <d:href>\(href)</d:href>
                <d:status>HTTP/1.1 404 Not Found</d:status>
              </d:response>
            """
        }
        if let syncToken {
            xml += "\n  <d:sync-token>\(syncToken)</d:sync-token>"
        }
        xml += "\n</d:multistatus>"
        return xml
    }

    private func makeService(
        source: PIMSource,
        collections: [PIMCollection],
        davTransport: ScriptedTransport,
        googleTransport: ScriptedTransport? = nil,
        eventStore: InMemoryEventStore = InMemoryEventStore(),
        cursorStore: InMemoryCursorStore = InMemoryCursorStore(),
        googleAccessToken: (@Sendable (String) async throws -> String)? = nil
    ) async throws -> (
        PIMEventSyncService, PIMSourceCoordinator, InMemoryEventStore,
        InMemoryCursorStore
    ) {
        let sourceStore = InMemorySourceStore()
        try await sourceStore.save(source)
        let credentials = InMemoryCredentialStore()
        if let account = source.credentialAccount {
            try await credentials.setCredential(
                .bearer(token: "dav-token"),
                for: account
            )
        }
        let coordinator = PIMSourceCoordinator(
            store: sourceStore,
            credentials: credentials,
            localData: InMemoryLocalDataStore()
        )
        let collectionStore = InMemoryCollectionStore()
        try await collectionStore.saveCollections(
            collections,
            for: source.id
        )
        let service = PIMEventSyncService(
            coordinator: coordinator,
            collectionStore: collectionStore,
            eventStore: eventStore,
            cursorStore: cursorStore,
            credentials: credentials,
            googleSync: GoogleCalendarEventSync(
                transport: googleTransport
                    ?? ScriptedTransport(steps: [])
            ),
            davSync: PIMDAVEventSync(transport: davTransport),
            googleAccessToken: googleAccessToken,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        return (service, coordinator, eventStore, cursorStore)
    }

    // MARK: - DAV sync-collection

    @Test("DAV incremental sync applies changes, removals and the new token")
    func davIncrementalSync() async throws {
        let collection = Self.collection()
        let transport = ScriptedTransport(steps: [
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/calendars/henrik/work/e1.ics",
                            "etag-2",
                            Self.sampleVEvent
                        )
                    ],
                    removed: ["/calendars/henrik/work/gone.ics"],
                    syncToken: "sync-2"
                )
            )
        ])
        let (service, _, eventStore, cursorStore) = try await makeService(
            source: Self.source(),
            collections: [collection],
            davTransport: transport
        )
        // Seed the cache: one event that will be removed, one untouched.
        try await eventStore.saveEvents(
            [
                Self.event(
                    collectionID: collection.id,
                    providerItemKey:
                    "https://dav.example.com/calendars/henrik/work/gone.ics",
                    summary: "Gone"
                ),
                Self.event(
                    collectionID: collection.id,
                    providerItemKey:
                    "https://dav.example.com/calendars/henrik/work/keep.ics",
                    summary: "Keep"
                )
            ],
            for: "pim-test",
            collectionID: collection.id
        )
        try await cursorStore.saveCursor(
            PIMSyncCursor(collectionID: collection.id, token: "sync-1"),
            for: "pim-test"
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedCollections == 1)
        #expect(summary.failures.isEmpty)
        let events = try await eventStore.events(
            for: "pim-test",
            collectionID: collection.id
        )
        let keys = Set(events.map(\.providerItemKey))
        #expect(keys.contains(
            "https://dav.example.com/calendars/henrik/work/e1.ics"
        ))
        #expect(keys.contains(
            "https://dav.example.com/calendars/henrik/work/keep.ics"
        ))
        #expect(!keys.contains(
            "https://dav.example.com/calendars/henrik/work/gone.ics"
        ))
        let cursor = try await cursorStore.cursor(
            for: "pim-test",
            collectionID: collection.id
        )
        #expect(cursor?.token == "sync-2")
        // The stored token must reach the REPORT body.
        let body = String(
            data: transport.requests[0].httpBody ?? Data(),
            encoding: .utf8
        )
        #expect(body?.contains("sync-1") == true)
    }

    @Test("DAV delta with a renamed href supersedes the stale record")
    func davSyncSupersedesStaleHref() async throws {
        let collection = Self.collection()
        let transport = ScriptedTransport(steps: [
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/calendars/henrik/work/renamed.ics",
                            "etag-3",
                            Self.sampleVEvent
                        )
                    ],
                    syncToken: "sync-2"
                )
            )
        ])
        let (service, _, eventStore, cursorStore) = try await makeService(
            source: Self.source(),
            collections: [collection],
            davTransport: transport
        )
        // The server renamed the resource without a tombstone for the
        // old path — the cache still holds the same UID under it.
        try await eventStore.saveEvents(
            [
                Self.event(
                    collectionID: collection.id,
                    providerItemKey:
                    "https://dav.example.com/calendars/henrik/work/old-name.ics",
                    summary: "Stale copy",
                    etag: "etag-1",
                    uid: "event-1@example.com"
                ),
                Self.event(
                    collectionID: collection.id,
                    providerItemKey:
                    "https://dav.example.com/calendars/henrik/work/keep.ics",
                    summary: "Keep",
                    uid: "other@example.com"
                )
            ],
            for: "pim-test",
            collectionID: collection.id
        )
        try await cursorStore.saveCursor(
            PIMSyncCursor(collectionID: collection.id, token: "sync-1"),
            for: "pim-test"
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.failures.isEmpty)
        let events = try await eventStore.events(
            for: "pim-test",
            collectionID: collection.id
        )
        let keys = Set(events.map(\.providerItemKey))
        #expect(keys.contains(
            "https://dav.example.com/calendars/henrik/work/renamed.ics"
        ))
        #expect(!keys.contains(
            "https://dav.example.com/calendars/henrik/work/old-name.ics"
        ))
        #expect(keys.contains(
            "https://dav.example.com/calendars/henrik/work/keep.ics"
        ))
        #expect(events.count == 2)
    }

    @Test("DAV member without inline data is fetched by multiget")
    func davMultigetForMissingData() async throws {
        let collection = Self.collection()
        let transport = ScriptedTransport(steps: [
            // sync-collection: changed member carries only an ETag.
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        ("/calendars/henrik/work/e2.ics", "etag-3", nil)
                    ],
                    syncToken: "sync-3"
                )
            ),
            // multiget answers with the payload.
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/calendars/henrik/work/e2.ics",
                            "etag-3",
                            Self.sampleVEvent
                        )
                    ]
                )
            )
        ])
        let (service, _, eventStore, _) = try await makeService(
            source: Self.source(),
            collections: [collection],
            davTransport: transport
        )

        _ = try await service.syncNow(sourceID: "pim-test")

        #expect(transport.requests.count == 2)
        let second = String(
            data: transport.requests[1].httpBody ?? Data(),
            encoding: .utf8
        )
        #expect(second?.contains("calendar-multiget") == true)
        let events = try await eventStore.events(
            for: "pim-test",
            collectionID: collection.id
        )
        #expect(events.first?.summary == "Design review")
        #expect(events.first?.attendees.first?.rsvp == .accepted)
        #expect(events.first?.reminders.first?.minutesBefore == 15)
    }

    @Test("DAV fallback diffs ETags and deletes hrefs missing from the listing")
    func davCalendarQueryFallback() async throws {
        let collection = Self.collection(supportsSyncToken: false)
        let transport = ScriptedTransport(steps: [
            // calendar-query listing: keep.ics unchanged, new.ics new,
            // gone.ics absent.
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        ("/calendars/henrik/work/keep.ics", "etag-1", nil),
                        ("/calendars/henrik/work/new.ics", "etag-9", nil)
                    ]
                )
            ),
            // multiget for the one changed/new href.
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/calendars/henrik/work/new.ics",
                            "etag-9",
                            Self.sampleVEvent
                        )
                    ]
                )
            )
        ])
        let (service, _, eventStore, _) = try await makeService(
            source: Self.source(),
            collections: [collection],
            davTransport: transport
        )
        try await eventStore.saveEvents(
            [
                Self.event(
                    collectionID: collection.id,
                    providerItemKey:
                    "https://dav.example.com/calendars/henrik/work/keep.ics",
                    summary: "Keep",
                    etag: "etag-1"
                ),
                Self.event(
                    collectionID: collection.id,
                    providerItemKey:
                    "https://dav.example.com/calendars/henrik/work/gone.ics",
                    summary: "Gone",
                    etag: "etag-0"
                )
            ],
            for: "pim-test",
            collectionID: collection.id
        )

        _ = try await service.syncNow(sourceID: "pim-test")

        let events = try await eventStore.events(
            for: "pim-test",
            collectionID: collection.id
        )
        let byKey = Dictionary(
            uniqueKeysWithValues: events.map { ($0.providerItemKey, $0) }
        )
        // Unchanged record carried over; its cached summary survives.
        #expect(byKey[
            "https://dav.example.com/calendars/henrik/work/keep.ics"
        ]?.summary == "Keep")
        #expect(byKey[
            "https://dav.example.com/calendars/henrik/work/new.ics"
        ]?.summary == "Design review")
        #expect(byKey[
            "https://dav.example.com/calendars/henrik/work/gone.ics"
        ] == nil)
        // The fallback path issues exactly one listing + one multiget.
        #expect(transport.requests.count == 2)
        let query = String(
            data: transport.requests[0].httpBody ?? Data(),
            encoding: .utf8
        )
        #expect(query?.contains("calendar-query") == true)
        #expect(query?.contains("time-range") == true)
    }

    @Test("Sync-collection 501 falls back to the bounded listing path")
    func davSyncCollectionUnsupported() async throws {
        let collection = Self.collection(supportsSyncToken: true)
        let transport = ScriptedTransport(steps: [
            .response(501),
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        ("/calendars/henrik/work/e1.ics", "e1", nil)
                    ]
                )
            ),
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/calendars/henrik/work/e1.ics",
                            "e1",
                            Self.sampleVEvent
                        )
                    ]
                )
            )
        ])
        let (service, _, eventStore, _) = try await makeService(
            source: Self.source(),
            collections: [collection],
            davTransport: transport
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedCollections == 1)
        #expect(transport.requests.count == 3)
        let events = try await eventStore.events(
            for: "pim-test",
            collectionID: collection.id
        )
        #expect(events.count == 1)
    }

    // MARK: - Google

    private static func googleEventJSON(
        id: String,
        summary: String = "Event",
        status: String = "confirmed",
        extra: String = ""
    ) -> String {
        """
        {"id":"\(id)","status":"\(status)","summary":"\(summary)",
         "iCalUID":"\(id)@google.com","etag":"et-\(id)",
         "start":{"dateTime":"2026-09-22T14:00:00+02:00","timeZone":"Europe/Oslo"},
         "end":{"dateTime":"2026-09-22T15:00:00+02:00","timeZone":"Europe/Oslo"}
         \(extra)}
        """
    }

    @Test("Google full sync pages, maps fields and stores the sync token")
    func googleFullSync() async throws {
        let collection = Self.collection(
            providerKey: "primary"
        )
        let page1 = """
        {"items":[
          \(Self.googleEventJSON(
              id: "g1",
              summary: "Standup",
              extra: """
              ,"attendees":[{"email":"ada@example.com","displayName":"Ada","responseStatus":"accepted"}]
              ,"reminders":{"overrides":[{"method":"popup","minutes":10}]}
              ,"conferenceData":{"conferenceSolution":{"key":{"type":"hangoutsMeet"},"name":"Google Meet"},"status":{"statusCode":"success"},"entryPoints":[{"entryPointType":"video","uri":"https://meet.google.com/abc","label":"meet.google.com/abc"},{"entryPointType":"phone","uri":"tel:+1-555-0100","label":"+1 555-0100","pin":"1234"}]}
              ,"recurrence":["RRULE:FREQ=WEEKLY;BYDAY=MO"]
              ,"updated":"2026-09-20T09:00:00Z"
              ,"providerOnlyField":{"nested":true}
              """
          ))
        ],"nextPageToken":"p2"}
        """
        let page2 = """
        {"items":[
          {"id":"g2","status":"cancelled"},
          \(Self.googleEventJSON(id: "g3", summary: "Focus"))
        ],"nextSyncToken":"tok-9"}
        """
        let transport = ScriptedTransport(steps: [
            .response(200, body: page1),
            .response(200, body: page2)
        ])
        let (service, _, eventStore, cursorStore) = try await makeService(
            source: Self.source(provider: .google),
            collections: [collection],
            davTransport: ScriptedTransport(steps: []),
            googleTransport: transport,
            googleAccessToken: { _ in "google-token" }
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedCollections == 1)
        let events = try await eventStore.events(
            for: "pim-test",
            collectionID: collection.id
        )
        #expect(events.count == 2)
        let standup = events.first { $0.providerItemKey == "g1" }
        #expect(standup?.summary == "Standup")
        #expect(standup?.attendees.first?.rsvp == .accepted)
        #expect(standup?.reminders.first?.minutesBefore == 10)
        #expect(standup?.conferenceURL == "https://meet.google.com/abc")
        // #13: the full conference record carries kind, name, status,
        // and dial-ins alongside the flat join link.
        #expect(standup?.conference?.kind == .meet)
        #expect(standup?.conference?.name == "Google Meet")
        #expect(standup?.conference?.status == .success)
        #expect(
            standup?.conference?.dialIns
                == [PIMConference.DialIn(
                    uri: "tel:+1-555-0100",
                    label: "+1 555-0100",
                    pin: "1234"
                )]
        )
        #expect(standup?.recurrenceRule?.frequency == .weekly)
        #expect(standup?.timeZoneIdentifier == "Europe/Oslo")
        // Unknown provider fields survive in the raw payload (R4).
        #expect(standup?.rawPayload?.contains("providerOnlyField") == true)
        // Cancelled items arrive as tombstones, not records.
        #expect(events.contains { $0.providerItemKey == "g2" } == false)
        let cursor = try await cursorStore.cursor(
            for: "pim-test",
            collectionID: collection.id
        )
        #expect(cursor?.token == "tok-9")
        // Full sync carries the bounded window parameters.
        let query = transport.requests[0].url?.query ?? ""
        #expect(query.contains("timeMin="))
        #expect(query.contains("singleEvents=false"))
    }

    @Test("Google incremental sends only the sync token and applies tombstones")
    func googleIncremental() async throws {
        let collection = Self.collection(providerKey: "primary")
        let page = """
        {"items":[
          {"id":"g1","status":"cancelled"},
          \(Self.googleEventJSON(id: "g4", summary: "New"))
        ],"nextSyncToken":"tok-10"}
        """
        let transport = ScriptedTransport(steps: [.response(200, body: page)])
        let (service, _, eventStore, cursorStore) = try await makeService(
            source: Self.source(provider: .google),
            collections: [collection],
            davTransport: ScriptedTransport(steps: []),
            googleTransport: transport,
            googleAccessToken: { _ in "google-token" }
        )
        try await eventStore.saveEvents(
            [
                Self.event(
                    collectionID: collection.id,
                    providerItemKey: "g1",
                    summary: "Old"
                ),
                Self.event(
                    collectionID: collection.id,
                    providerItemKey: "g2",
                    summary: "Keep"
                )
            ],
            for: "pim-test",
            collectionID: collection.id
        )
        try await cursorStore.saveCursor(
            PIMSyncCursor(collectionID: collection.id, token: "tok-9"),
            for: "pim-test"
        )

        _ = try await service.syncNow(sourceID: "pim-test")

        let query = transport.requests[0].url?.query ?? ""
        #expect(query.contains("syncToken=tok-9"))
        // Google forbids time bounds alongside syncToken.
        #expect(!query.contains("timeMin"))
        #expect(!query.contains("singleEvents"))
        let events = try await eventStore.events(
            for: "pim-test",
            collectionID: collection.id
        )
        let keys = Set(events.map(\.providerItemKey))
        #expect(keys == ["g2", "g4"])
    }

    @Test("Google 410 retries once as a full sync")
    func googleCursorExpired() async throws {
        let collection = Self.collection(providerKey: "primary")
        let page = """
        {"items":[\(Self.googleEventJSON(id: "g5", summary: "Fresh"))],
         "nextSyncToken":"tok-new"}
        """
        let transport = ScriptedTransport(steps: [
            .response(410),
            .response(200, body: page)
        ])
        let (service, _, eventStore, cursorStore) = try await makeService(
            source: Self.source(provider: .google),
            collections: [collection],
            davTransport: ScriptedTransport(steps: []),
            googleTransport: transport,
            googleAccessToken: { _ in "google-token" }
        )
        try await cursorStore.saveCursor(
            PIMSyncCursor(collectionID: collection.id, token: "tok-stale"),
            for: "pim-test"
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedCollections == 1)
        #expect(transport.requests.count == 2)
        // The retry is a full listing, not another token request.
        let retry = transport.requests[1].url?.query ?? ""
        #expect(retry.contains("timeMin="))
        #expect(!retry.contains("syncToken"))
        let cursor = try await cursorStore.cursor(
            for: "pim-test",
            collectionID: collection.id
        )
        #expect(cursor?.token == "tok-new")
    }

    // MARK: - Service behavior

    @Test("Hidden collections keep their cache but skip the provider")
    func hiddenCollectionSkipped() async throws {
        let visible = Self.collection()
        let hidden = Self.collection(
            providerKey: "https://dav.example.com/calendars/henrik/hidden/",
            isVisible: false
        )
        let transport = ScriptedTransport(steps: [
            .response(
                207,
                body: Self.davSyncBody(members: [], syncToken: "s1")
            )
        ])
        let (service, _, _, _) = try await makeService(
            source: Self.source(),
            collections: [visible, hidden],
            davTransport: transport
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedCollections == 1)
        #expect(transport.requests.count == 1)
    }

    @Test("One collection's failure keeps its snapshot and the others commit")
    func failureIsolation() async throws {
        let failing = Self.collection()
        let healthy = Self.collection(
            providerKey: "https://dav.example.com/calendars/henrik/home/"
        )
        let transport = ScriptedTransport(steps: [
            .response(500),
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/calendars/henrik/home/e1.ics",
                            "e1",
                            Self.sampleVEvent
                        )
                    ],
                    syncToken: "s1"
                )
            )
        ])
        let (service, coordinator, eventStore, _) = try await makeService(
            source: Self.source(),
            collections: [failing, healthy],
            davTransport: transport
        )
        try await eventStore.saveEvents(
            [
                Self.event(
                    collectionID: failing.id,
                    providerItemKey: "old",
                    summary: "Prior snapshot"
                )
            ],
            for: "pim-test",
            collectionID: failing.id
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedCollections == 1)
        #expect(summary.failures.count == 1)
        #expect(summary.failures.first?.collectionID == failing.id)
        // Failed collection keeps its prior snapshot.
        let kept = try await eventStore.events(
            for: "pim-test",
            collectionID: failing.id
        )
        #expect(kept.first?.summary == "Prior snapshot")
        // Healthy collection committed.
        let synced = try await eventStore.events(
            for: "pim-test",
            collectionID: healthy.id
        )
        #expect(synced.count == 1)
        // Partial failure leaves the source usable.
        let source = try await coordinator.source(id: "pim-test")
        #expect(source?.status == .ready)
    }

    @Test("Authentication failure marks the source and stops the pass")
    func authFailureStopsSource() async throws {
        let collections = [
            Self.collection(),
            Self.collection(
                providerKey: "https://dav.example.com/calendars/henrik/two/"
            )
        ]
        let transport = ScriptedTransport(steps: [.response(401)])
        let (service, coordinator, _, _) = try await makeService(
            source: Self.source(),
            collections: collections,
            davTransport: transport
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedCollections == 0)
        #expect(transport.requests.count == 1)
        let source = try await coordinator.source(id: "pim-test")
        #expect(source?.status == .authenticationRequired)
    }

    @Test("Contacts sources are rejected by the calendar sync engine")
    func contactsSourceRejected() async throws {
        let (service, _, _, _) = try await makeService(
            source: Self.source(provider: .cardDAV),
            collections: [],
            davTransport: ScriptedTransport(steps: [])
        )
        await #expect(throws: PIMEventSyncServiceError.self) {
            _ = try await service.syncNow(sourceID: "pim-test")
        }
    }

    @Test("Disconnected sources cannot sync")
    func disconnectedRejected() async throws {
        let (service, _, _, _) = try await makeService(
            source: Self.source(status: .disconnected),
            collections: [Self.collection()],
            davTransport: ScriptedTransport(steps: [])
        )
        await #expect(throws: PIMEventSyncServiceError.self) {
            _ = try await service.syncNow(sourceID: "pim-test")
        }
    }

    @Test("a pending Meet create and a bare hangoutLink both map")
    func googleConferenceEdgeCases() async throws {
        let collection = Self.collection(providerKey: "primary")
        let page = """
        {"items":[
          \(Self.googleEventJSON(
              id: "g-pending",
              summary: "Pending",
              extra: """
              ,"conferenceData":{"createRequest":{"requestId":"r1","conferenceSolutionKey":{"type":"hangoutsMeet"}},"status":{"statusCode":"pending"}}
              """
          )),
          \(Self.googleEventJSON(
              id: "g-legacy",
              summary: "Legacy",
              extra: """
              ,"hangoutLink":"https://meet.google.com/legacy"
              """
          )),
          \(Self.googleEventJSON(
              id: "g-addon",
              summary: "Addon",
              extra: """
              ,"conferenceData":{"conferenceSolution":{"key":{"type":"addOn"},"name":"Zoom"},"entryPoints":[{"entryPointType":"video","uri":"https://zoom.us/j/9"}]}
              """
          ))
        ],"nextSyncToken":"tok-1"}
        """
        let transport = ScriptedTransport(steps: [
            .response(200, body: page)
        ])
        let (service, _, eventStore, _) = try await makeService(
            source: Self.source(provider: .google),
            collections: [collection],
            davTransport: ScriptedTransport(steps: []),
            googleTransport: transport,
            googleAccessToken: { _ in "google-token" }
        )

        _ = try await service.syncNow(sourceID: "pim-test")

        let events = try await eventStore.events(
            for: "pim-test",
            collectionID: collection.id
        )
        let pending = events.first { $0.providerItemKey == "g-pending" }
        #expect(pending?.conference?.status == .pending)
        #expect(pending?.conference?.kind == PIMConference.Kind.meet)
        #expect(pending?.conference?.joinURL == nil)
        #expect(pending?.conferenceURL == nil)

        let legacy = events.first { $0.providerItemKey == "g-legacy" }
        #expect(legacy?.conference?.kind == PIMConference.Kind.meet)
        #expect(
            legacy?.conference?.joinURL
                == "https://meet.google.com/legacy"
        )

        let addon = events.first { $0.providerItemKey == "g-addon" }
        #expect(addon?.conference?.kind == PIMConference.Kind.other)
        #expect(addon?.conference?.name == "Zoom")
        #expect(addon?.conference?.joinURL == "https://zoom.us/j/9")
    }

    @Test("DAV conference label and Meet marker map to the record")
    func davConferenceMapping() async throws {
        let collection = Self.collection()
        let vevent = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:conf-1@example.com
        SUMMARY:Labeled call
        DTSTART:20260922T140000Z
        DTEND:20260922T150000Z
        CONFERENCE;VALUE=URI;LABEL=Zoom room:https://zoom.us/j/42
        END:VEVENT
        BEGIN:VEVENT
        UID:conf-2@example.com
        SUMMARY:Meet call
        DTSTART:20260923T140000Z
        DTEND:20260923T150000Z
        X-GOOGLE-CONFERENCE:https://meet.google.com/xyz
        END:VEVENT
        END:VCALENDAR
        """
        let transport = ScriptedTransport(steps: [
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/calendars/henrik/work/conf.ics",
                            "etag-1",
                            vevent
                        )
                    ],
                    syncToken: "sync-1"
                )
            )
        ])
        let (service, _, eventStore, _) = try await makeService(
            source: Self.source(),
            collections: [collection],
            davTransport: transport
        )

        _ = try await service.syncNow(sourceID: "pim-test")

        let events = try await eventStore.events(
            for: "pim-test",
            collectionID: collection.id
        )
        let labeled = events.first { $0.summary == "Labeled call" }
        #expect(labeled?.conference?.kind == PIMConference.Kind.other)
        #expect(labeled?.conference?.name == "Zoom room")
        #expect(
            labeled?.conference?.joinURL == "https://zoom.us/j/42"
        )
        let meet = events.first { $0.summary == "Meet call" }
        #expect(meet?.conference?.kind == PIMConference.Kind.meet)
        #expect(meet?.conference?.name == "Google Meet")
    }

    @Test("Google sync maps attachments[] to link attachments (#14)")
    func googleAttachments() async throws {
        let collection = Self.collection(providerKey: "primary")
        let page = """
        {"items":[
          \(Self.googleEventJSON(
              id: "g-att",
              summary: "Review",
              extra: """
              ,"attachments":[{"fileUrl":"https://drive.google.com/file/d/abc/view","title":"Deck","mimeType":"application/pdf","iconLink":"https://drive.google.com/icon.png"}]
              """
          ))
        ],"nextSyncToken":"tok-att"}
        """
        let transport = ScriptedTransport(steps: [.response(200, body: page)])
        let (service, _, eventStore, _) = try await makeService(
            source: Self.source(provider: .google),
            collections: [collection],
            davTransport: ScriptedTransport(steps: []),
            googleTransport: transport,
            googleAccessToken: { _ in "google-token" }
        )

        _ = try await service.syncNow(sourceID: "pim-test")

        let events = try await eventStore.events(
            for: "pim-test",
            collectionID: collection.id
        )
        let event = events.first { $0.providerItemKey == "g-att" }
        #expect(event?.attachments.count == 1)
        #expect(
            event?.attachments.first?.url
                == "https://drive.google.com/file/d/abc/view"
        )
        #expect(event?.attachments.first?.title == "Deck")
        #expect(event?.attachments.first?.mimeType == "application/pdf")
        #expect(
            event?.attachments.first?.iconURL
                == "https://drive.google.com/icon.png"
        )
    }

    @Test("DAV sync maps ATTACH;VALUE=URI to link attachments (#14)")
    func davAttachments() async throws {
        let collection = Self.collection()
        let vevent = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:att-1@example.com
        SUMMARY:With file
        DTSTART:20260922T140000Z
        DTEND:20260922T150000Z
        ATTACH;VALUE=URI;FMTTYPE=application/pdf;X-FILENAME=Deck:https://drive.google.com/file/d/abc/view
        END:VEVENT
        END:VCALENDAR
        """
        let transport = ScriptedTransport(steps: [
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/calendars/henrik/work/att.ics",
                            "etag-1",
                            vevent
                        )
                    ],
                    syncToken: "sync-1"
                )
            )
        ])
        let (service, _, eventStore, _) = try await makeService(
            source: Self.source(),
            collections: [collection],
            davTransport: transport
        )

        _ = try await service.syncNow(sourceID: "pim-test")

        let events = try await eventStore.events(
            for: "pim-test",
            collectionID: collection.id
        )
        let event = events.first { $0.summary == "With file" }
        #expect(event?.attachments.count == 1)
        #expect(
            event?.attachments.first?.url
                == "https://drive.google.com/file/d/abc/view"
        )
        #expect(event?.attachments.first?.title == "Deck")
        #expect(event?.attachments.first?.mimeType == "application/pdf")
    }
}

@Suite("ICSParser event-sync fields")
struct ICSParserSyncFieldTests {
    @Test("parseEvents returns master and exception components")
    func multiVEvent() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:series-1
        SUMMARY:Weekly sync
        DTSTART;TZID=Europe/Oslo:20260921T090000
        DTEND;TZID=Europe/Oslo:20260921T093000
        RRULE:FREQ=WEEKLY;BYDAY=MO
        END:VEVENT
        BEGIN:VEVENT
        UID:series-1
        SUMMARY:Weekly sync (moved)
        RECURRENCE-ID;TZID=Europe/Oslo:20260928T090000
        DTSTART;TZID=Europe/Oslo:20260928T110000
        DTEND;TZID=Europe/Oslo:20260928T113000
        END:VEVENT
        END:VCALENDAR
        """
        let events = ICSParser.parseEvents(from: ics)
        #expect(events.count == 2)
        #expect(events[0].recurrenceRule?.frequency == .weekly)
        #expect(events[0].recurrenceID == nil)
        #expect(events[0].timeZoneIdentifier == "Europe/Oslo")
        #expect(events[1].recurrenceID != nil)
        #expect(events[1].summary == "Weekly sync (moved)")
    }

    @Test("Status, alarms, conference and last-modified are captured")
    func extendedFields() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:e1
        SUMMARY:Cancelled call
        STATUS:CANCELLED
        DTSTART:20260922T140000Z
        DTEND:20260922T150000Z
        LAST-MODIFIED:20260921T080000Z
        CONFERENCE;VALUE=URI:https://meet.example.com/x
        BEGIN:VALARM
        ACTION:DISPLAY
        TRIGGER:-PT30M
        END:VALARM
        BEGIN:VALARM
        ACTION:EMAIL
        TRIGGER:-P1D
        END:VALARM
        END:VEVENT
        END:VCALENDAR
        """
        let event = ICSParser.parseFirstEvent(from: ics)
        #expect(event?.status == "CANCELLED")
        #expect(event?.reminderMinutes == [30, 1440])
        #expect(event?.conferenceURL == "https://meet.example.com/x")
        #expect(event?.lastModified != nil)
    }

    @Test("Attendee PARTSTAT is captured")
    func partstat() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:e2
        DTSTART:20260922T140000Z
        ATTENDEE;CN=Ada;PARTSTAT=DECLINED:mailto:ada@example.com
        END:VEVENT
        END:VCALENDAR
        """
        let event = ICSParser.parseFirstEvent(from: ics)
        #expect(event?.attendees.first?.participation == "DECLINED")
    }

    @Test("parseRecurrenceRule reads bare RRULE values")
    func bareRRule() {
        let rule = ICSParser.parseRecurrenceRule("FREQ=DAILY;INTERVAL=2;COUNT=5")
        #expect(rule?.frequency == .daily)
        #expect(rule?.interval == 2)
        #expect(rule?.count == 5)
        #expect(ICSParser.parseRecurrenceRule("X-NOT-A-RULE") == nil)
    }
}

@Suite("Recurrence descriptors (ADR-0089)")
struct RecurrenceDescriptorTests {
    // MARK: - ICS capture

    private static func parse(_ vevent: String) -> ICSParser.ParsedEvent? {
        ICSParser.parseFirstEvent(
            from: "BEGIN:VCALENDAR\n\(vevent)\nEND:VCALENDAR\n"
        )
    }

    @Test("RRULE values are captured verbatim, including unknown parts")
    func verbatimRRule() {
        let parsed = Self.parse("""
        BEGIN:VEVENT
        UID:e1
        DTSTART;TZID=Europe/Oslo:20261016T090000
        DTEND;TZID=Europe/Oslo:20261016T100000
        RRULE:FREQ=DAILY;COUNT=5;BYSETPOS=1
        END:VEVENT
        """)
        #expect(
            parsed?.recurrenceDescriptor?.rrules
                == ["FREQ=DAILY;COUNT=5;BYSETPOS=1"]
        )
        #expect(
            parsed?.recurrenceDescriptor?.startBasis
                == .zoned("Europe/Oslo")
        )
        #expect(parsed?.recurrenceDescriptor?.hasRDate == false)
        #expect(parsed?.recurrenceDescriptor?.hasExDate == false)
    }

    @Test("RDATE and EXDATE set their flags and keep every RRULE")
    func rdateExdate() {
        let parsed = Self.parse("""
        BEGIN:VEVENT
        UID:e1
        DTSTART:20261016T090000Z
        RRULE:FREQ=DAILY
        RRULE:FREQ=WEEKLY
        RDATE:20261020T090000Z
        EXDATE:20261017T090000Z
        END:VEVENT
        """)
        let descriptor = parsed?.recurrenceDescriptor
        #expect(descriptor?.rrules == ["FREQ=DAILY", "FREQ=WEEKLY"])
        #expect(descriptor?.hasRDate == true)
        #expect(descriptor?.hasExDate == true)
    }

    @Test("no descriptor is emitted without recurrence properties")
    func noRecurrence() {
        let parsed = Self.parse("""
        BEGIN:VEVENT
        UID:e1
        DTSTART:20261016T090000Z
        END:VEVENT
        """)
        #expect(parsed?.recurrenceDescriptor == nil)
    }

    @Test("every DTSTART basis maps to its descriptor value")
    func startBases() {
        let dateOnly = Self.parse("""
        BEGIN:VEVENT
        UID:e1
        DTSTART;VALUE=DATE:20261016
        RRULE:FREQ=DAILY
        END:VEVENT
        """)
        #expect(dateOnly?.recurrenceDescriptor?.startBasis == .dateOnly)

        let utc = Self.parse("""
        BEGIN:VEVENT
        UID:e1
        DTSTART:20261016T090000Z
        RRULE:FREQ=DAILY
        END:VEVENT
        """)
        #expect(utc?.recurrenceDescriptor?.startBasis == .utc)

        let zoned = Self.parse("""
        BEGIN:VEVENT
        UID:e1
        DTSTART;TZID=Custom/Zone:20261016T090000
        RRULE:FREQ=DAILY
        END:VEVENT
        """)
        #expect(
            zoned?.recurrenceDescriptor?.startBasis
                == .zoned("Custom/Zone")
        )

        let floating = Self.parse("""
        BEGIN:VEVENT
        UID:e1
        DTSTART:20261016T090000
        RRULE:FREQ=DAILY
        END:VEVENT
        """)
        #expect(floating?.recurrenceDescriptor?.startBasis == .floating)

        let missing = Self.parse("""
        BEGIN:VEVENT
        UID:e1
        RRULE:FREQ=DAILY
        END:VEVENT
        """)
        #expect(missing?.recurrenceDescriptor?.startBasis == .unknown)
    }

    // MARK: - Google mapping

    private static func googleSource() -> PIMSource {
        PIMSource(
            id: "pim-test",
            kind: .calendar,
            provider: .google,
            displayName: "Google",
            syncEnabled: true,
            status: .ready,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// Syncs one Google page and returns the mapped result.
    private static func syncGoogleItems(
        _ items: String
    ) async throws -> (PIMEventSyncResult) {
        struct Transport: PIMDAVTransport {
            let body: String
            func send(
                _ request: URLRequest
            ) async throws -> (Data, HTTPURLResponse) {
                (
                    Data(body.utf8),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        }
        let collection = PIMCollection(
            id: "c1",
            sourceID: "pim-test",
            kind: .calendar,
            displayName: "Cal",
            isReadOnly: false,
            isPrimary: true,
            providerKey: "primary",
            updatedAt: Date()
        )
        let sync = GoogleCalendarEventSync(
            transport: Transport(body: """
            {"items":[\(items)],"nextSyncToken":"tok"}
            """)
        )
        return try await sync.syncCollection(
            collection,
            source: googleSource(),
            cursorToken: "tok-0",
            windowStart: Date(timeIntervalSince1970: 0),
            windowEnd: Date(),
            accessToken: "token"
        )
    }

    @Test("a Google master maps recurrence[] into the descriptor")
    func googleDescriptor() async throws {
        let result = try await Self.syncGoogleItems("""
        {"id":"g1","status":"confirmed","summary":"Standup",
         "iCalUID":"g1@google.com",
         "start":{"dateTime":"2026-10-16T09:00:00+02:00","timeZone":"Europe/Oslo"},
         "end":{"dateTime":"2026-10-16T09:30:00+02:00","timeZone":"Europe/Oslo"},
         "recurrence":["RRULE:FREQ=DAILY;COUNT=5","EXDATE:20261018T070000Z","X-ODD:1"]}
        """)
        let event = try #require(result.events.first)
        let descriptor = try #require(event.recurrenceDescriptor)
        #expect(descriptor.rrules == ["FREQ=DAILY;COUNT=5"])
        #expect(descriptor.hasExDate)
        #expect(!descriptor.hasRDate)
        #expect(descriptor.hasUnrecognizedEntries)
        #expect(descriptor.startBasis == .zoned("Europe/Oslo"))
    }

    @Test("a Google all-day series maps the date-only basis")
    func googleDateOnlyBasis() async throws {
        let result = try await Self.syncGoogleItems("""
        {"id":"g1","status":"confirmed",
         "start":{"date":"2026-10-16"},
         "end":{"date":"2026-10-17"},
         "recurrence":["RRULE:FREQ=DAILY;COUNT=3"]}
        """)
        #expect(
            result.events.first?.recurrenceDescriptor?.startBasis
                == .dateOnly
        )
        // A timed master without a reported zone keeps the unknown basis.
        let unknown = try await Self.syncGoogleItems("""
        {"id":"g2","status":"confirmed",
         "start":{"dateTime":"2026-10-16T09:00:00+02:00"},
         "end":{"dateTime":"2026-10-16T09:30:00+02:00"},
         "recurrence":["RRULE:FREQ=DAILY;COUNT=3"]}
        """)
        #expect(
            unknown.events.first?.recurrenceDescriptor?.startBasis
                == .unknown
        )
    }

    @Test("a cancelled recurring instance is a marker, not a tombstone")
    func googleCancelledInstance() async throws {
        let result = try await Self.syncGoogleItems("""
        {"id":"m_20261018T070000Z","status":"cancelled",
         "iCalUID":"master@google.com",
         "recurringEventId":"m",
         "originalStartTime":{"dateTime":"2026-10-18T09:00:00+02:00"}}
        """)
        #expect(result.removedItemKeys.isEmpty)
        let marker = try #require(result.events.first)
        #expect(marker.status == .cancelled)
        #expect(marker.seriesMasterItemKey == "m")
        #expect(marker.providerItemKey == "m_20261018T070000Z")
        #expect(marker.uid == "master@google.com")
        #expect(marker.recurrenceID != nil)
        #expect(
            marker.id
                == PIMEvent.makeID(
                    collectionID: "c1",
                    providerItemKey: "m_20261018T070000Z",
                    recurrenceID: marker.recurrenceID
                )
        )
    }

    @Test("a cancelled master stays a tombstone")
    func googleCancelledMaster() async throws {
        let result = try await Self.syncGoogleItems("""
        {"id":"m","status":"cancelled","iCalUID":"master@google.com"}
        """)
        #expect(result.events.isEmpty)
        #expect(result.removedItemKeys == ["m"])
    }

    @Test("a Google exception instance links its master key")
    func googleInstanceLink() async throws {
        let result = try await Self.syncGoogleItems("""
        {"id":"m_20261018T070000Z","status":"confirmed","summary":"Moved",
         "recurringEventId":"m",
         "originalStartTime":{"dateTime":"2026-10-18T09:00:00+02:00"},
         "start":{"dateTime":"2026-10-18T11:00:00+02:00","timeZone":"Europe/Oslo"},
         "end":{"dateTime":"2026-10-18T11:30:00+02:00","timeZone":"Europe/Oslo"}}
        """)
        let event = try #require(result.events.first)
        #expect(event.seriesMasterItemKey == "m")
        #expect(event.recurrenceID != nil)
    }
}
