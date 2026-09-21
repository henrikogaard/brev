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

import Foundation

/// Lifecycle status shared by Google (`status`) and iCalendar
/// (`STATUS`) event records (ADR-0072).
public enum PIMEventStatus: String, Sendable, Hashable, Codable, CaseIterable {
    case confirmed
    case tentative
    case cancelled

    /// Maps a raw provider status token onto the shared vocabulary.
    /// Unknown values degrade to `confirmed` — the event still shows.
    public init(rawValue value: String?) {
        switch value?.lowercased() {
        case "tentative": self = .tentative
        case "cancelled": self = .cancelled
        default: self = .confirmed
        }
    }
}

/// An event participant with the RSVP state the provider reported
/// (ADR-0072 attendee contract).
public struct PIMEventPerson: Sendable, Hashable, Codable {
    /// RSVP state normalized across Google `responseStatus` and
    /// iCalendar `PARTSTAT` values.
    public enum RSVP: String, Sendable, Hashable, Codable, CaseIterable {
        case needsAction
        case accepted
        case declined
        case tentative
        case delegated
        case unknown

        /// Maps a raw provider token onto the shared vocabulary.
        public init(rawValue value: String?) {
            switch value?.lowercased() {
            case "accepted": self = .accepted
            case "declined": self = .declined
            case "tentative": self = .tentative
            case "delegated": self = .delegated
            case "needs-action", "needsaction": self = .needsAction
            case nil: self = .unknown
            default: self = .unknown
            }
        }
    }

    public var name: String?
    public var email: String
    public var rsvp: RSVP

    public init(name: String? = nil, email: String, rsvp: RSVP = .unknown) {
        self.name = name
        self.email = email
        self.rsvp = rsvp
    }
}

/// A reminder attached to an event (ADR-0072 reminder contract).
public struct PIMEventReminder: Sendable, Hashable, Codable {
    /// Delivery flavor normalized across Google `method` and VALARM
    /// `ACTION` values.
    public enum Method: String, Sendable, Hashable, Codable, CaseIterable {
        case alert
        case email
        case other

        /// Maps a raw provider token onto the shared vocabulary.
        public init(rawValue value: String?) {
            switch value?.lowercased() {
            case "popup", "display", "alert": self = .alert
            case "email": self = .email
            default: self = .other
            }
        }
    }

    /// Minutes before the event starts. `nil` means the provider's
    /// default reminder applies (Google `useDefault`).
    public var minutesBefore: Int?
    public var method: Method

    public init(minutesBefore: Int?, method: Method = .alert) {
        self.minutesBefore = minutesBefore
        self.method = method
    }
}

/// A video/phone conference attached to an event (#13).
///
/// Synced records carry whatever the provider published — join URL,
/// dial-ins, display name, lifecycle status. `isCreationRequest` is
/// the local intent flag the Google writer turns into
/// `conferenceData.createRequest`; it is never set on synced records.
public struct PIMConference: Sendable, Hashable, Codable {
    /// The conference system behind the link.
    public enum Kind: String, Sendable, Hashable, Codable {
        /// Google Meet.
        case meet
        /// Any other conference provider — readable and joinable, but
        /// Brev cannot create it.
        case other
    }

    /// Lifecycle of the conference data itself.
    public enum Status: String, Sendable, Hashable, Codable {
        /// Google is still creating the conference — entry points may
        /// arrive on the next sync.
        case pending
        /// The conference is ready.
        case success
        /// The provider failed to create the conference; the event
        /// itself is saved.
        case failure
    }

    /// A phone dial-in entry point.
    public struct DialIn: Sendable, Hashable, Codable {
        /// tel: URI for the dial-in.
        public var uri: String
        /// Provider display label (number, region).
        public var label: String?
        /// PIN / access code when the provider published one.
        public var pin: String?

        public init(uri: String, label: String? = nil, pin: String? = nil) {
            self.uri = uri
            self.label = label
            self.pin = pin
        }
    }

    /// The conference system kind, derived from the provider's
    /// conference solution key or link host.
    public var kind: Kind
    /// The provider's conference solution key (e.g. "hangoutsMeet");
    /// kept so unknown solutions stay identifiable.
    public var providerKey: String?
    /// Provider display name for the conference.
    public var name: String?
    /// Video join URL.
    public var joinURL: String?
    /// Phone entry points.
    public var dialIns: [DialIn]
    /// Provider-reported conference status; nil when the provider did
    /// not report one.
    public var status: Status?
    /// Local intent flag: the Google writer turns this into
    /// `conferenceData.createRequest`. Never set on synced records.
    public var isCreationRequest: Bool

    public init(
        kind: Kind,
        providerKey: String? = nil,
        name: String? = nil,
        joinURL: String? = nil,
        dialIns: [DialIn] = [],
        status: Status? = nil,
        isCreationRequest: Bool = false
    ) {
        self.kind = kind
        self.providerKey = providerKey
        self.name = name
        self.joinURL = joinURL
        self.dialIns = dialIns
        self.status = status
        self.isCreationRequest = isCreationRequest
    }
}

/// A provider-neutral cached calendar event (ADR-0072).
///
/// One record per provider item component: a CalDAV resource holding a
/// master plus `RECURRENCE-ID` exceptions produces one record per
/// component, sharing `providerItemKey`; Google returns each instance
/// exception as its own item already. `rawPayload` keeps the
/// adapter-owned representation (ICS text or Google JSON) so provider
/// fields survive refreshes and later edits untouched by the shared
/// model (R4).
public struct PIMEvent: Sendable, Hashable, Codable, Identifiable {
    public typealias ID = String

    /// Stable record ID: collection ID, provider item key, and the
    /// recurrence-instance marker when the component is an exception.
    public let id: ID
    public let sourceID: PIMSource.ID
    public let collectionID: PIMCollection.ID
    /// Provider-side item key: absolute DAV href or Google event ID.
    public var providerItemKey: String
    /// Provider version for conflict-aware edits (ETag / Google etag).
    public var providerVersion: String?
    /// iCalendar UID / Google iCalUID — series identity across providers.
    public var uid: String?
    public var summary: String?
    public var eventDescription: String?
    public var location: String?
    public var start: Date?
    public var end: Date?
    public var isAllDay: Bool
    /// Named time zone the provider attached to the start value.
    public var timeZoneIdentifier: String?
    public var status: PIMEventStatus
    public var organizer: PIMEventPerson?
    public var attendees: [PIMEventPerson]
    public var reminders: [PIMEventReminder]
    /// Conference join link (Google conferenceData / iCalendar
    /// CONFERENCE;VALUE=URI), when the provider published one.
    public var conferenceURL: String?
    /// The full conference record (#13): kind, name, join URL,
    /// dial-ins, and provider status. `conferenceURL` stays populated
    /// as the cheap join link.
    public var conference: PIMConference?
    /// Series recurrence pattern on the master component.
    public var recurrenceRule: ICSParser.RecurrenceRule?
    /// Exception marker: the original start this component overrides.
    public var recurrenceID: Date?
    /// Adapter-owned provider payload for round-trip preservation.
    /// Never shown in views.
    public var rawPayload: String?
    /// Provider-reported modification time (LAST-MODIFIED / updated).
    public var providerUpdatedAt: Date?
    /// When Brev wrote this record into the cache.
    public var syncedAt: Date

    public init(
        id: ID,
        sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID,
        providerItemKey: String,
        providerVersion: String? = nil,
        uid: String? = nil,
        summary: String? = nil,
        eventDescription: String? = nil,
        location: String? = nil,
        start: Date? = nil,
        end: Date? = nil,
        isAllDay: Bool = false,
        timeZoneIdentifier: String? = nil,
        status: PIMEventStatus = .confirmed,
        organizer: PIMEventPerson? = nil,
        attendees: [PIMEventPerson] = [],
        reminders: [PIMEventReminder] = [],
        conferenceURL: String? = nil,
        conference: PIMConference? = nil,
        recurrenceRule: ICSParser.RecurrenceRule? = nil,
        recurrenceID: Date? = nil,
        rawPayload: String? = nil,
        providerUpdatedAt: Date? = nil,
        syncedAt: Date = Date()
    ) {
        self.id = id
        self.sourceID = sourceID
        self.collectionID = collectionID
        self.providerItemKey = providerItemKey
        self.providerVersion = providerVersion
        self.uid = uid
        self.summary = summary
        self.eventDescription = eventDescription
        self.location = location
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.status = status
        self.organizer = organizer
        self.attendees = attendees
        self.reminders = reminders
        self.conferenceURL = conferenceURL
        self.conference = conference
        self.recurrenceRule = recurrenceRule
        self.recurrenceID = recurrenceID
        self.rawPayload = rawPayload
        self.providerUpdatedAt = providerUpdatedAt
        self.syncedAt = syncedAt
    }

    /// Composes the stable record ID for a provider item component.
    /// Exception instances sharing a provider item key disambiguate by
    /// their recurrence timestamp.
    public static func makeID(
        collectionID: PIMCollection.ID,
        providerItemKey: String,
        recurrenceID: Date? = nil
    ) -> ID {
        var id = "\(collectionID)|\(providerItemKey)"
        if let recurrenceID {
            id += "|\(Int(recurrenceID.timeIntervalSince1970))"
        }
        return id
    }
}

public enum PIMEventStoreError: Error, Sendable {
    /// The on-disk record exists but cannot be decoded.
    case unreadableStore
}

/// Persistence for synced calendar events (ADR-0072).
///
/// Stores normalized display fields plus the adapter-owned raw payload.
/// Secrets never pass through this store.
public protocol PIMEventStore: Sendable {
    /// Cached events for one collection, in stored order.
    func events(
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws -> [PIMEvent]
    /// Cached events across every collection of a source.
    func events(for sourceID: PIMSource.ID) async throws -> [PIMEvent]
    /// Replaces one collection's event set atomically. Called only after
    /// a complete sync generation committed (ADR-0072 sync rule 1).
    func saveEvents(
        _ events: [PIMEvent],
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws
    /// Removes one collection's events. Missing data is not an error.
    func deleteEvents(
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws
}

/// JSON-file-backed PIMEventStore.
///
/// Each collection's events live in a file inside the source's cache
/// directory owned by FilePIMSourceLocalDataStore, so the ADR-0072
/// removal contract applies without extra wiring.
public actor JSONPIMEventStore: PIMEventStore {
    private let localDataStore: FilePIMSourceLocalDataStore
    private var cache: [String: [PIMEvent]] = [:]

    /// - Parameter localDataStore: The per-source local-data layout owner.
    public init(localDataStore: FilePIMSourceLocalDataStore) {
        self.localDataStore = localDataStore
    }

    public func events(
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws -> [PIMEvent] {
        try load(sourceID: sourceID, collectionID: collectionID)
    }

    public func events(for sourceID: PIMSource.ID) async throws -> [PIMEvent] {
        let directory = eventsDirectory(for: sourceID)
        guard let names = try? FileManager.default.contentsOfDirectory(
            atPath: directory.path
        ) else { return [] }
        var all: [PIMEvent] = []
        for name in names where name.hasSuffix(".json") {
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            guard let records = try? JSONDecoder.pimEventStore.decode(
                [PIMEvent].self,
                from: data
            ) else {
                throw PIMEventStoreError.unreadableStore
            }
            all.append(contentsOf: records)
        }
        return all
    }

    public func saveEvents(
        _ events: [PIMEvent],
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws {
        let url = fileURL(for: sourceID, collectionID: collectionID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.pimEventStore.encode(events)
        try data.write(to: url, options: .atomic)
        cache[cacheKey(sourceID: sourceID, collectionID: collectionID)] = events
    }

    public func deleteEvents(
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws {
        let url = fileURL(for: sourceID, collectionID: collectionID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        cache[cacheKey(sourceID: sourceID, collectionID: collectionID)] = nil
    }

    /// The events file location inside the source's cache directory.
    public func fileURL(
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) -> URL {
        eventsDirectory(for: sourceID)
            .appendingPathComponent("\(Self.fileName(for: collectionID)).json")
    }

    private func eventsDirectory(for sourceID: PIMSource.ID) -> URL {
        localDataStore
            .cacheDirectory(for: sourceID)
            .appendingPathComponent("events", isDirectory: true)
    }

    /// Filesystem-safe deterministic name for a collection ID. Base64-url
    /// encoding keeps arbitrary provider keys collision-free.
    static func fileName(for collectionID: PIMCollection.ID) -> String {
        Data(collectionID.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func cacheKey(
        sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) -> String {
        "\(sourceID)|\(collectionID)"
    }

    private func load(
        sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) throws -> [PIMEvent] {
        let key = cacheKey(sourceID: sourceID, collectionID: collectionID)
        if let cached = cache[key] { return cached }
        let url = fileURL(for: sourceID, collectionID: collectionID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            cache[key] = []
            return []
        }
        let data = try Data(contentsOf: url)
        guard let records = try? JSONDecoder.pimEventStore.decode(
            [PIMEvent].self,
            from: data
        ) else {
            throw PIMEventStoreError.unreadableStore
        }
        cache[key] = records
        return records
    }
}

/// An adapter-owned sync checkpoint for one collection (ADR-0072).
///
/// The token is opaque to the app: a Google `nextSyncToken` or a DAV
/// `sync-token`. Cursors live in the source's cursor directory, which
/// FilePIMSourceLocalDataStore always wipes on removal — a kept cache
/// can never silently resume syncing.
public struct PIMSyncCursor: Sendable, Hashable, Codable {
    public let collectionID: PIMCollection.ID
    /// Opaque provider token; nil means the next sync is a full listing.
    public var token: String?
    /// When the generation this cursor checkpoints completed.
    public var completedAt: Date

    public init(
        collectionID: PIMCollection.ID,
        token: String?,
        completedAt: Date = Date()
    ) {
        self.collectionID = collectionID
        self.token = token
        self.completedAt = completedAt
    }
}

/// Persistence for per-collection sync cursors (ADR-0072).
public protocol PIMSyncCursorStore: Sendable {
    /// The committed cursor for a collection, if any.
    func cursor(
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws -> PIMSyncCursor?
    /// Commits a cursor after its complete generation was saved.
    func saveCursor(
        _ cursor: PIMSyncCursor,
        for sourceID: PIMSource.ID
    ) async throws
    /// Removes a collection's cursor. Missing data is not an error.
    func deleteCursor(
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws
}

/// JSON-file-backed PIMSyncCursorStore inside the source's cursor
/// directory (ADR-0072 removal contract).
public actor JSONPIMSyncCursorStore: PIMSyncCursorStore {
    private let localDataStore: FilePIMSourceLocalDataStore

    /// - Parameter localDataStore: The per-source local-data layout owner.
    public init(localDataStore: FilePIMSourceLocalDataStore) {
        self.localDataStore = localDataStore
    }

    public func cursor(
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws -> PIMSyncCursor? {
        let url = fileURL(for: sourceID, collectionID: collectionID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try? JSONDecoder.pimCursorStore.decode(
            PIMSyncCursor.self,
            from: data
        )
    }

    public func saveCursor(
        _ cursor: PIMSyncCursor,
        for sourceID: PIMSource.ID
    ) async throws {
        let url = fileURL(for: sourceID, collectionID: cursor.collectionID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.pimCursorStore.encode(cursor)
        try data.write(to: url, options: .atomic)
    }

    public func deleteCursor(
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws {
        let url = fileURL(for: sourceID, collectionID: collectionID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// The cursor file location inside the source's cursor directory.
    public func fileURL(
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) -> URL {
        localDataStore
            .cursorDirectory(for: sourceID)
            .appendingPathComponent(
                "\(JSONPIMEventStore.fileName(for: collectionID)).json"
            )
    }
}

private extension JSONEncoder {
    static let pimEventStore: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let pimCursorStore: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let pimEventStore: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let pimCursorStore: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
