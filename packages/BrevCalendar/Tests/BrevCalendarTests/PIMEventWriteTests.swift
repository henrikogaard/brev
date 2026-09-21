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

@Suite("PIMEventWrite")
struct PIMEventWriteTests {
    // MARK: - Doubles

    /// Records requests and answers with scripted status/body pairs.
    private final class ScriptedTransport: @unchecked Sendable {
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

    // MARK: - Fixtures

    private static func source(
        provider: PIMSourceProvider = .calDAV,
        write: Bool = true,
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
            enabledCapabilities: write ? [.read, .write] : [.read],
            status: status
        )
    }

    private static func collection(
        sourceID: PIMSource.ID = "pim-test",
        providerKey: String = "https://dav.example.com/calendars/henrik/work/",
        isReadOnly: Bool = false
    ) -> PIMCollection {
        PIMCollection(
            id: PIMCollection.makeID(
                sourceID: sourceID,
                providerKey: providerKey
            ),
            sourceID: sourceID,
            kind: .calendar,
            displayName: "Work",
            isReadOnly: isReadOnly,
            providerKey: providerKey
        )
    }

    private static func event(
        collectionID: PIMCollection.ID,
        providerItemKey: String = "event-1",
        etag: String? = nil,
        uid: String? = nil,
        summary: String? = "Design review",
        start: Date? = nil,
        end: Date? = nil,
        isAllDay: Bool = false,
        timeZoneIdentifier: String? = nil
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
            start: start,
            end: end,
            isAllDay: isAllDay,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    private static func makeService(
        sourceStore: InMemorySourceStore,
        collectionStore: InMemoryCollectionStore,
        eventStore: InMemoryEventStore,
        credentials: InMemoryCredentialStore,
        googleTransport: ScriptedTransport,
        davTransport: ScriptedTransport,
        googleAccessToken: (@Sendable (String) async throws -> String)? = nil
    ) -> PIMEventWriteService {
        let coordinator = PIMSourceCoordinator(
            store: sourceStore,
            credentials: credentials,
            localData: InMemoryLocalDataStore()
        )
        return PIMEventWriteService(
            coordinator: coordinator,
            collectionStore: collectionStore,
            eventStore: eventStore,
            credentials: credentials,
            googleWriter: GoogleCalendarEventWriter(
                transport: { try await googleTransport.send($0) }
            ),
            davWriter: PIMDAVEventWriter(
                transport: { try await davTransport.send($0) }
            ),
            googleAccessToken: googleAccessToken,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    // MARK: - ICS writer

    @Test("Timed events serialize with TZID and escaped text")
    func icsWriterTimedEvent() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = Date(timeIntervalSince1970: 1_800_003_600)
        var event = Self.event(
            collectionID: "c1",
            uid: "uid-1@brev",
            summary: "Design, review; v2",
            start: start,
            end: end,
            timeZoneIdentifier: "Europe/Oslo"
        )
        event.eventDescription = "Line one\nLine two"
        event.location = "Office"
        let ics = PIMEventICSWriter.vcalendar(
            for: event,
            dtstamp: start
        )
        #expect(ics.contains("UID:uid-1@brev"))
        #expect(ics.contains("DTSTART;TZID=Europe/Oslo:"))
        #expect(ics.contains("DTEND;TZID=Europe/Oslo:"))
        #expect(ics.contains("SUMMARY:Design\\, review\\; v2"))
        #expect(ics.contains("DESCRIPTION:Line one\\nLine two"))
        #expect(ics.contains("LOCATION:Office"))
        #expect(ics.hasSuffix("\r\n"))
        #expect(!ics.contains("\n") || ics.contains("\r\n"))
    }

    @Test("All-day events serialize as VALUE=DATE in UTC")
    func icsWriterAllDay() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = Date(timeIntervalSince1970: 1_800_086_400)
        let event = Self.event(
            collectionID: "c1",
            uid: "uid-2@brev",
            start: start,
            end: end,
            isAllDay: true
        )
        let ics = PIMEventICSWriter.vcalendar(for: event, dtstamp: start)
        #expect(ics.contains("DTSTART;VALUE=DATE:"))
        #expect(ics.contains("DTEND;VALUE=DATE:"))
        #expect(!ics.contains("TZID"))
    }

    @Test("Recurrence, attendees, and reminders serialize")
    func icsWriterRecurrenceAndPeople() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var event = Self.event(
            collectionID: "c1",
            uid: "uid-3@brev",
            start: start
        )
        event.recurrenceRule = ICSParser.RecurrenceRule(
            frequency: .weekly,
            interval: 2,
            count: 8,
            byDay: [.monday, .wednesday]
        )
        event.organizer = PIMEventPerson(
            name: "Henrik",
            email: "henrik@example.com",
            rsvp: .accepted
        )
        event.attendees = [
            PIMEventPerson(
                name: nil,
                email: "guest@example.com",
                rsvp: .needsAction
            ),
        ]
        event.reminders = [PIMEventReminder(minutesBefore: 15, method: .alert)]
        let ics = PIMEventICSWriter.vcalendar(for: event, dtstamp: start)
        #expect(ics.contains("RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=8;BYDAY=MO,WE"))
        #expect(ics.contains("ORGANIZER;CN=Henrik;PARTSTAT=ACCEPTED:mailto:henrik@example.com"))
        #expect(ics.contains("ATTENDEE;PARTSTAT=NEEDS-ACTION:mailto:guest@example.com"))
        #expect(ics.contains("BEGIN:VALARM"))
        #expect(ics.contains("TRIGGER:-PT15M"))
    }

    @Test("Lines fold at 75 octets without splitting UTF-8")
    func icsWriterFolding() {
        let longSummary = String(repeating: "æ", count: 60)
        var event = Self.event(
            collectionID: "c1",
            uid: "uid-4@brev",
            summary: longSummary,
            start: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let ics = PIMEventICSWriter.vcalendar(
            for: event,
            dtstamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        for line in ics.components(separatedBy: "\r\n") {
            #expect(line.utf8.count <= 75)
        }
        // Round-trip: unfolding must recover the original summary.
        let parsed = ICSParser.parseFirstEvent(from: ics)
        #expect(parsed?.summary == longSummary)
    }

    @Test("Emitted VEVENT round-trips through ICSParser")
    func icsWriterRoundTrip() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = Date(timeIntervalSince1970: 1_800_003_600)
        var event = Self.event(
            collectionID: "c1",
            uid: "uid-5@brev",
            summary: "Round trip",
            start: start,
            end: end
        )
        event.location = "Room 4"
        let ics = PIMEventICSWriter.vcalendar(for: event, dtstamp: start)
        let parsed = ICSParser.parseFirstEvent(from: ics)
        #expect(parsed?.uid == "uid-5@brev")
        #expect(parsed?.summary == "Round trip")
        #expect(parsed?.location == "Room 4")
        #expect(parsed?.start != nil)
    }

    @Test("A synced conference emits CONFERENCE;VALUE=URI with its label")
    func icsWriterConference() {
        var event = Self.event(
            collectionID: "c1",
            uid: "uid-conf@brev",
            start: Date(timeIntervalSince1970: 1_800_000_000)
        )
        event.conference = PIMConference(
            kind: .other,
            name: "Zoom room",
            joinURL: "https://zoom.us/j/42"
        )
        event.conferenceURL = "https://zoom.us/j/42"
        let ics = PIMEventICSWriter.vcalendar(
            for: event,
            dtstamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(
            ics.contains(
                "CONFERENCE;VALUE=URI;LABEL=Zoom room:https://zoom.us/j/42"
            )
        )
        // The flat URL line is skipped when it duplicates the
        // conference join link.
        #expect(!ics.contains("URL:https://zoom.us/j/42"))
        let parsed = ICSParser.parseFirstEvent(from: ics)
        #expect(parsed?.conferenceURL == "https://zoom.us/j/42")
        #expect(parsed?.conferenceLabel == "Zoom room")
    }

    // MARK: - Google writer

    @Test("Google insert POSTs the mapped body to the collection events URL")
    func googleInsert() async throws {
        let transport = ScriptedTransport(steps: [
            .response(200, body: #"{"id":"g-1","etag":"\"v1\""}"#),
        ])
        let writer = GoogleCalendarEventWriter(
            transport: { try await transport.send($0) }
        )
        let collection = PIMCollection(
            id: "c1",
            sourceID: "pim-test",
            kind: .calendar,
            displayName: "Work",
            providerKey: "primary"
        )
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var event = Self.event(
            collectionID: "c1",
            uid: "uid-g@brev",
            start: start,
            timeZoneIdentifier: "Europe/Oslo"
        )
        event.attendees = [
            PIMEventPerson(
                name: "Guest",
                email: "guest@example.com",
                rsvp: .accepted
            ),
        ]
        event.reminders = [PIMEventReminder(minutesBefore: 10, method: .alert)]
        let result = try await writer.insert(
            event,
            into: collection,
            accessToken: "token"
        )
        #expect(result.eventID == "g-1")
        #expect(result.etag == "\"v1\"")
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(
            request.url?.absoluteString
                == "https://www.googleapis.com/calendar/v3/calendars/primary/events?sendUpdates=all"
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        let body = try #require(request.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["summary"] as? String == "Design review")
        #expect(json["iCalUID"] as? String == "uid-g@brev")
        let startDict = try #require(json["start"] as? [String: Any])
        #expect(startDict["timeZone"] as? String == "Europe/Oslo")
        let attendees = try #require(json["attendees"] as? [[String: Any]])
        #expect(attendees.first?["responseStatus"] as? String == "accepted")
        let reminders = try #require(json["reminders"] as? [String: Any])
        #expect(reminders["useDefault"] as? Bool == false)
    }

    @Test("Google patch sends the cached etag as If-Match")
    func googlePatchPrecondition() async throws {
        let transport = ScriptedTransport(steps: [
            .response(200, body: #"{"id":"g-1","etag":"\"v2\""}"#),
        ])
        let writer = GoogleCalendarEventWriter(
            transport: { try await transport.send($0) }
        )
        let collection = PIMCollection(
            id: "c1",
            sourceID: "pim-test",
            kind: .calendar,
            displayName: "Work",
            providerKey: "primary"
        )
        let event = Self.event(
            collectionID: "c1",
            providerItemKey: "g-1",
            etag: "\"v1\""
        )
        let result = try await writer.patch(
            event,
            in: collection,
            accessToken: "token"
        )
        #expect(result.etag == "\"v2\"")
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.value(forHTTPHeaderField: "If-Match") == "\"v1\"")
    }

    @Test("Google insert with a Meet request sends conferenceDataVersion and a fresh requestId")
    func googleInsertConferenceRequest() async throws {
        let transport = ScriptedTransport(steps: [
            .response(
                200,
                body: #"{"id":"g-1","etag":"\"v1\"","conferenceData":{"conferenceSolution":{"key":{"type":"hangoutsMeet"},"name":"Google Meet"},"status":{"statusCode":"pending"}}}"#
            ),
        ])
        let writer = GoogleCalendarEventWriter(
            transport: { try await transport.send($0) }
        )
        let collection = PIMCollection(
            id: "c1",
            sourceID: "pim-test",
            kind: .calendar,
            displayName: "Work",
            providerKey: "primary"
        )
        var event = Self.event(
            collectionID: "c1",
            uid: "uid-g@brev",
            start: Date(timeIntervalSince1970: 1_800_000_000)
        )
        event.conference = PIMConference(
            kind: .meet,
            status: .pending,
            isCreationRequest: true
        )

        let result = try await writer.insert(
            event,
            into: collection,
            accessToken: "token"
        )

        let request = try #require(transport.requests.first)
        #expect(
            request.url?.absoluteString
                == "https://www.googleapis.com/calendar/v3/calendars/primary/events?sendUpdates=all&conferenceDataVersion=1"
        )
        let body = try #require(request.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let conferenceData = try #require(
            json["conferenceData"] as? [String: Any]
        )
        let createRequest = try #require(
            conferenceData["createRequest"] as? [String: Any]
        )
        // A fresh requestId per call — Meet codes are never reused.
        let requestId = try #require(createRequest["requestId"] as? String)
        #expect(UUID(uuidString: requestId) != nil)
        let key = try #require(
            createRequest["conferenceSolutionKey"] as? [String: Any]
        )
        #expect(key["type"] as? String == "hangoutsMeet")
        // The provider's pending conference lands on the result.
        #expect(result.conference?.status == .pending)
        #expect(result.conference?.kind == .meet)
        #expect(result.conference?.name == "Google Meet")
    }

    @Test("Google patch with a Meet request adds the conference to an existing event")
    func googlePatchConferenceRequest() async throws {
        let transport = ScriptedTransport(steps: [
            .response(
                200,
                body: #"{"id":"g-1","etag":"\"v2\"","conferenceData":{"conferenceSolution":{"key":{"type":"hangoutsMeet"},"name":"Google Meet"},"status":{"statusCode":"success"},"entryPoints":[{"entryPointType":"video","uri":"https://meet.google.com/new"}]}}"#
            ),
        ])
        let writer = GoogleCalendarEventWriter(
            transport: { try await transport.send($0) }
        )
        let collection = PIMCollection(
            id: "c1",
            sourceID: "pim-test",
            kind: .calendar,
            displayName: "Work",
            providerKey: "primary"
        )
        var event = Self.event(
            collectionID: "c1",
            providerItemKey: "g-1",
            etag: "\"v1\""
        )
        event.conference = PIMConference(
            kind: .meet,
            status: .pending,
            isCreationRequest: true
        )

        let result = try await writer.patch(
            event,
            in: collection,
            accessToken: "token"
        )

        let request = try #require(transport.requests.first)
        #expect(
            request.url?.absoluteString
                == "https://www.googleapis.com/calendar/v3/calendars/primary/events/g-1?sendUpdates=all&conferenceDataVersion=1"
        )
        let body = try #require(request.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["conferenceData"] != nil)
        // The ready conference replaces the pending intent.
        #expect(result.conference?.status == .success)
        #expect(
            result.conference?.joinURL == "https://meet.google.com/new"
        )
    }

    @Test("Google writes without a conference intent omit conferenceData")
    func googleWriteWithoutConference() async throws {
        let transport = ScriptedTransport(steps: [
            .response(200, body: #"{"id":"g-1","etag":"\"v1\""}"#),
        ])
        let writer = GoogleCalendarEventWriter(
            transport: { try await transport.send($0) }
        )
        let collection = PIMCollection(
            id: "c1",
            sourceID: "pim-test",
            kind: .calendar,
            displayName: "Work",
            providerKey: "primary"
        )
        let event = Self.event(
            collectionID: "c1",
            uid: "uid-g@brev"
        )
        _ = try await writer.insert(
            event,
            into: collection,
            accessToken: "token"
        )
        let request = try #require(transport.requests.first)
        #expect(
            request.url?.absoluteString
                == "https://www.googleapis.com/calendar/v3/calendars/primary/events?sendUpdates=all"
        )
        let body = try #require(request.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["conferenceData"] == nil)
    }

    @Test("Google delete accepts 404 and maps 412 to conflict")
    func googleDeleteAndConflict() async throws {
        let transport = ScriptedTransport(steps: [
            .response(404),
            .response(412),
        ])
        let writer = GoogleCalendarEventWriter(
            transport: { try await transport.send($0) }
        )
        let collection = PIMCollection(
            id: "c1",
            sourceID: "pim-test",
            kind: .calendar,
            displayName: "Work",
            providerKey: "primary"
        )
        let event = Self.event(
            collectionID: "c1",
            providerItemKey: "g-1",
            etag: "\"v1\""
        )
        try await writer.delete(
            event,
            in: collection,
            accessToken: "token"
        )
        let request = try #require(transport.requests.first)
        #expect(
            request.url?.absoluteString
                == "https://www.googleapis.com/calendar/v3/calendars/primary/events/g-1?sendUpdates=all"
        )
        await #expect(throws: GoogleCalendarEventWriter.WriteError.conflict) {
            try await writer.delete(
                event,
                in: collection,
                accessToken: "token"
            )
        }
    }

    // MARK: - DAV writer

    @Test("DAV create PUTs ICS to the UID resource with If-None-Match")
    func davCreate() async throws {
        let transport = ScriptedTransport(steps: [
            .response(201, headers: ["ETag": "\"dav-1\""]),
        ])
        let writer = PIMDAVEventWriter(
            transport: { try await transport.send($0) }
        )
        let collection = Self.collection()
        let event = Self.event(
            collectionID: collection.id,
            uid: "uid-dav@brev"
        )
        let result = try await writer.create(
            event,
            ics: "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n",
            in: collection,
            credential: .basic(username: "u", password: "p")
        )
        #expect(result.etag == "\"dav-1\"")
        // CalDAVWriteTarget.sanitize maps @ to - in the resource name.
        #expect(
            result.resourceURL.absoluteString
                == "https://dav.example.com/calendars/henrik/work/uid-dav-brev.ics"
        )
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "*")
        #expect(
            request.value(forHTTPHeaderField: "Content-Type")
                == "text/calendar; charset=utf-8"
        )
    }

    @Test("DAV update sends If-Match and maps 412 to conflict")
    func davUpdateConflict() async throws {
        let transport = ScriptedTransport(steps: [
            .response(412),
        ])
        let writer = PIMDAVEventWriter(
            transport: { try await transport.send($0) }
        )
        let collection = Self.collection()
        let event = Self.event(
            collectionID: collection.id,
            etag: "\"old\"",
            uid: "uid-dav@brev"
        )
        await #expect(throws: PIMDAVEventWriter.WriteError.conflict) {
            try await writer.update(
                event,
                ics: "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n",
                in: collection,
                credential: .basic(username: "u", password: "p")
            )
        }
        let request = try #require(transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "If-Match") == "\"old\"")
    }

    @Test("DAV delete tolerates a missing resource")
    func davDelete() async throws {
        let transport = ScriptedTransport(steps: [
            .response(404),
        ])
        let writer = PIMDAVEventWriter(
            transport: { try await transport.send($0) }
        )
        let collection = Self.collection()
        let event = Self.event(
            collectionID: collection.id,
            uid: "uid-dav@brev"
        )
        try await writer.delete(
            event,
            in: collection,
            credential: .basic(username: "u", password: "p")
        )
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "DELETE")
    }

    // MARK: - Service capability gating

    @Test("canWrite requires the write capability and a writable collection")
    func canWriteGating() async throws {
        let sourceStore = InMemorySourceStore()
        let collectionStore = InMemoryCollectionStore()
        let eventStore = InMemoryEventStore()
        let credentials = InMemoryCredentialStore()
        let service = Self.makeService(
            sourceStore: sourceStore,
            collectionStore: collectionStore,
            eventStore: eventStore,
            credentials: credentials,
            googleTransport: ScriptedTransport(steps: []),
            davTransport: ScriptedTransport(steps: [])
        )
        let writable = Self.source(write: true)
        let readOnlySource = Self.source(write: false)
        let collection = Self.collection()
        let lockedCollection = Self.collection(
            providerKey: "https://dav.example.com/calendars/henrik/shared/",
            isReadOnly: true
        )
        #expect(
            await service.canWrite(source: writable, collection: collection)
        )
        #expect(
            await service.canWrite(
                source: readOnlySource,
                collection: collection
            ) == false
        )
        #expect(
            await service.canWrite(
                source: writable,
                collection: lockedCollection
            ) == false
        )
        #expect(
            await service.canWrite(
                source: Self.source(provider: .cardDAV),
                collection: collection
            ) == false
        )
    }

    @Test("create on CalDAV PUTs ICS and caches the provider identity")
    func createOnDAV() async throws {
        let sourceStore = InMemorySourceStore()
        let collectionStore = InMemoryCollectionStore()
        let eventStore = InMemoryEventStore()
        let credentials = InMemoryCredentialStore()
        let davTransport = ScriptedTransport(steps: [
            .response(201, headers: ["ETag": "\"new-etag\""]),
        ])
        let service = Self.makeService(
            sourceStore: sourceStore,
            collectionStore: collectionStore,
            eventStore: eventStore,
            credentials: credentials,
            googleTransport: ScriptedTransport(steps: []),
            davTransport: davTransport
        )
        let source = Self.source(write: true)
        try await sourceStore.save(source)
        let collection = Self.collection()
        try await collectionStore.saveCollections([collection], for: source.id)
        try await credentials.setCredential(
            .basic(username: "u", password: "p"),
            for: "pim-source-pim-test"
        )
        let draft = Self.event(
            collectionID: collection.id,
            providerItemKey: "draft",
            start: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let created = try await service.create(
            draft,
            in: collection,
            source: source
        )
        #expect(created.uid != nil)
        #expect(created.providerVersion == "\"new-etag\"")
        #expect(created.providerItemKey.hasSuffix(".ics"))
        #expect(
            created.id
                == PIMEvent.makeID(
                    collectionID: collection.id,
                    providerItemKey: created.providerItemKey
                )
        )
        let cached = try await eventStore.events(
            for: source.id,
            collectionID: collection.id
        )
        #expect(cached.count == 1)
        #expect(cached.first?.id == created.id)
        let request = try #require(davTransport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "*")
    }

    @Test("create on Google resolves the linked account token")
    func createOnGoogle() async throws {
        let sourceStore = InMemorySourceStore()
        let collectionStore = InMemoryCollectionStore()
        let eventStore = InMemoryEventStore()
        let credentials = InMemoryCredentialStore()
        let googleTransport = ScriptedTransport(steps: [
            .response(200, body: #"{"id":"g-new","etag":"\"e1\""}"#),
        ])
        var tokenAccount: String?
        let service = Self.makeService(
            sourceStore: sourceStore,
            collectionStore: collectionStore,
            eventStore: eventStore,
            credentials: credentials,
            googleTransport: googleTransport,
            davTransport: ScriptedTransport(steps: []),
            googleAccessToken: { accountID in
                tokenAccount = accountID
                return "google-token"
            }
        )
        let source = Self.source(provider: .google, write: true)
        try await sourceStore.save(source)
        let collection = Self.collection(providerKey: "primary")
        try await collectionStore.saveCollections([collection], for: source.id)
        let draft = Self.event(
            collectionID: collection.id,
            providerItemKey: "draft",
            start: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let created = try await service.create(
            draft,
            in: collection,
            source: source
        )
        #expect(tokenAccount == "acct-1")
        #expect(created.providerItemKey == "g-new")
        #expect(created.providerVersion == "\"e1\"")
    }

    @Test("create on Google stores the provider's pending conference")
    func createOnGoogleWithConference() async throws {
        let sourceStore = InMemorySourceStore()
        let collectionStore = InMemoryCollectionStore()
        let eventStore = InMemoryEventStore()
        let credentials = InMemoryCredentialStore()
        let googleTransport = ScriptedTransport(steps: [
            .response(
                200,
                body: #"{"id":"g-new","etag":"\"e1\"","conferenceData":{"conferenceSolution":{"key":{"type":"hangoutsMeet"},"name":"Google Meet"},"status":{"statusCode":"pending"}}}"#
            ),
        ])
        let service = Self.makeService(
            sourceStore: sourceStore,
            collectionStore: collectionStore,
            eventStore: eventStore,
            credentials: credentials,
            googleTransport: googleTransport,
            davTransport: ScriptedTransport(steps: []),
            googleAccessToken: { _ in "google-token" }
        )
        let source = Self.source(provider: .google, write: true)
        try await sourceStore.save(source)
        let collection = Self.collection(providerKey: "primary")
        try await collectionStore.saveCollections([collection], for: source.id)
        var draft = Self.event(
            collectionID: collection.id,
            providerItemKey: "draft",
            start: Date(timeIntervalSince1970: 1_800_000_000)
        )
        draft.conference = PIMConference(
            kind: .meet,
            status: .pending,
            isCreationRequest: true
        )

        let created = try await service.create(
            draft,
            in: collection,
            source: source
        )

        // The pending conference is stored — the next sync resolves it
        // to success with entry points.
        #expect(created.conference?.status == .pending)
        #expect(created.conference?.isCreationRequest == false)
        #expect(created.conference?.name == "Google Meet")
        let request = try #require(googleTransport.requests.first)
        #expect(
            request.url?.query?.contains("conferenceDataVersion=1")
                == true
        )
    }

    @Test("create on CalDAV drops a Meet create intent and keeps a synced link")
    func createOnDAVDropsConferenceIntent() async throws {
        let sourceStore = InMemorySourceStore()
        let collectionStore = InMemoryCollectionStore()
        let eventStore = InMemoryEventStore()
        let credentials = InMemoryCredentialStore()
        let davTransport = ScriptedTransport(steps: [
            .response(201, headers: ["ETag": "\"new-etag\""]),
        ])
        let service = Self.makeService(
            sourceStore: sourceStore,
            collectionStore: collectionStore,
            eventStore: eventStore,
            credentials: credentials,
            googleTransport: ScriptedTransport(steps: []),
            davTransport: davTransport
        )
        let source = Self.source(write: true)
        try await sourceStore.save(source)
        let collection = Self.collection()
        try await collectionStore.saveCollections([collection], for: source.id)
        try await credentials.setCredential(
            .basic(username: "u", password: "p"),
            for: "pim-source-pim-test"
        )
        var draft = Self.event(
            collectionID: collection.id,
            providerItemKey: "draft",
            start: Date(timeIntervalSince1970: 1_800_000_000)
        )
        draft.conference = PIMConference(
            kind: .meet,
            status: .pending,
            isCreationRequest: true
        )

        let created = try await service.create(
            draft,
            in: collection,
            source: source
        )

        // CalDAV cannot create conferences — the intent is dropped
        // rather than stored as a phantom pending record.
        #expect(created.conference == nil)
        let request = try #require(davTransport.requests.first)
        let ics = try String(
            data: #require(request.httpBody),
            encoding: .utf8
        ) ?? ""
        #expect(!ics.contains("CONFERENCE"))
    }

    @Test("update on CalDAV sends the stored etag and records the new one")
    func updateOnDAV() async throws {
        let sourceStore = InMemorySourceStore()
        let collectionStore = InMemoryCollectionStore()
        let eventStore = InMemoryEventStore()
        let credentials = InMemoryCredentialStore()
        let davTransport = ScriptedTransport(steps: [
            .response(200, headers: ["ETag": "\"v2\""]),
        ])
        let service = Self.makeService(
            sourceStore: sourceStore,
            collectionStore: collectionStore,
            eventStore: eventStore,
            credentials: credentials,
            googleTransport: ScriptedTransport(steps: []),
            davTransport: davTransport
        )
        let source = Self.source(write: true)
        try await sourceStore.save(source)
        let collection = Self.collection()
        try await collectionStore.saveCollections([collection], for: source.id)
        try await credentials.setCredential(
            .basic(username: "u", password: "p"),
            for: "pim-source-pim-test"
        )
        let existing = Self.event(
            collectionID: collection.id,
            providerItemKey: "https://dav.example.com/calendars/henrik/work/e1.ics",
            etag: "\"v1\"",
            uid: "e1@brev"
        )
        try await eventStore.saveEvents(
            [existing],
            for: source.id,
            collectionID: collection.id
        )
        let updated = try await service.update(
            existing,
            in: collection,
            source: source
        )
        #expect(updated.providerVersion == "\"v2\"")
        let request = try #require(davTransport.requests.first)
        #expect(request.value(forHTTPHeaderField: "If-Match") == "\"v1\"")
    }

    @Test("delete removes the cached record after the remote delete")
    func deleteRemovesCache() async throws {
        let sourceStore = InMemorySourceStore()
        let collectionStore = InMemoryCollectionStore()
        let eventStore = InMemoryEventStore()
        let credentials = InMemoryCredentialStore()
        let davTransport = ScriptedTransport(steps: [
            .response(204),
        ])
        let service = Self.makeService(
            sourceStore: sourceStore,
            collectionStore: collectionStore,
            eventStore: eventStore,
            credentials: credentials,
            googleTransport: ScriptedTransport(steps: []),
            davTransport: davTransport
        )
        let source = Self.source(write: true)
        try await sourceStore.save(source)
        let collection = Self.collection()
        try await collectionStore.saveCollections([collection], for: source.id)
        try await credentials.setCredential(
            .basic(username: "u", password: "p"),
            for: "pim-source-pim-test"
        )
        let existing = Self.event(
            collectionID: collection.id,
            uid: "e1@brev"
        )
        try await eventStore.saveEvents(
            [existing],
            for: source.id,
            collectionID: collection.id
        )
        try await service.delete(
            existing,
            in: collection,
            source: source
        )
        let cached = try await eventStore.events(
            for: source.id,
            collectionID: collection.id
        )
        #expect(cached.isEmpty)
    }

    @Test("writes on a read-enabled source throw notWritable")
    func writeWithoutCapability() async throws {
        let sourceStore = InMemorySourceStore()
        let collectionStore = InMemoryCollectionStore()
        let eventStore = InMemoryEventStore()
        let credentials = InMemoryCredentialStore()
        let service = Self.makeService(
            sourceStore: sourceStore,
            collectionStore: collectionStore,
            eventStore: eventStore,
            credentials: credentials,
            googleTransport: ScriptedTransport(steps: []),
            davTransport: ScriptedTransport(steps: [])
        )
        let source = Self.source(write: false)
        try await sourceStore.save(source)
        let collection = Self.collection()
        try await collectionStore.saveCollections([collection], for: source.id)
        let draft = Self.event(collectionID: collection.id)
        await #expect(
            throws: PIMEventWriteService.WriteError.notWritable
        ) {
            try await service.create(draft, in: collection, source: source)
        }
        await #expect(
            throws: PIMEventWriteService.WriteError.notWritable
        ) {
            try await service.update(draft, in: collection, source: source)
        }
        await #expect(
            throws: PIMEventWriteService.WriteError.notWritable
        ) {
            try await service.delete(draft, in: collection, source: source)
        }
    }

    @Test("a remote conflict surfaces as WriteError.conflict")
    func conflictMapping() async throws {
        let sourceStore = InMemorySourceStore()
        let collectionStore = InMemoryCollectionStore()
        let eventStore = InMemoryEventStore()
        let credentials = InMemoryCredentialStore()
        let davTransport = ScriptedTransport(steps: [
            .response(412),
        ])
        let service = Self.makeService(
            sourceStore: sourceStore,
            collectionStore: collectionStore,
            eventStore: eventStore,
            credentials: credentials,
            googleTransport: ScriptedTransport(steps: []),
            davTransport: davTransport
        )
        let source = Self.source(write: true)
        try await sourceStore.save(source)
        let collection = Self.collection()
        try await collectionStore.saveCollections([collection], for: source.id)
        try await credentials.setCredential(
            .basic(username: "u", password: "p"),
            for: "pim-source-pim-test"
        )
        let existing = Self.event(
            collectionID: collection.id,
            etag: "\"v1\"",
            uid: "e1@brev"
        )
        await #expect(
            throws: PIMEventWriteService.WriteError.conflict
        ) {
            try await service.update(
                existing,
                in: collection,
                source: source
            )
        }
    }

    // MARK: - Coordinator capability

    @Test("setWriteEnabled toggles the write capability")
    func setWriteEnabled() async throws {
        let sourceStore = InMemorySourceStore()
        let credentials = InMemoryCredentialStore()
        let coordinator = PIMSourceCoordinator(
            store: sourceStore,
            credentials: credentials,
            localData: InMemoryLocalDataStore()
        )
        var source = Self.source(write: false)
        try await sourceStore.save(source)
        source = try await coordinator.setWriteEnabled(
            true,
            for: source.id
        )
        #expect(source.enabledCapabilities.contains(.write))
        source = try await coordinator.setWriteEnabled(
            false,
            for: source.id
        )
        #expect(!source.enabledCapabilities.contains(.write))
        #expect(source.enabledCapabilities.contains(.read))
    }
}
