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
