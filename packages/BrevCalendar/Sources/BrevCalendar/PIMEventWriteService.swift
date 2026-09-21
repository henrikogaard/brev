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

/// Provider-neutral event write path (ADR-0072 #7).
///
/// Create, update, and delete dispatch on the source's provider —
/// Google via the `events` REST resource, CalDAV via PUT/DELETE on the
/// collection URL — behind one capability check: a write runs only when
/// the source's `enabledCapabilities` carries `.write` *and* the
/// target collection is not read-only. Preconditions ride every
/// mutation (Google `If-Match` etag, CalDAV `If-Match` /
/// `If-None-Match`) so a stale edit surfaces as `conflict` instead
/// of overwriting a newer remote change.
///
/// After a successful write the local cache updates in place — the next
/// sync reconciles the provider's canonical record
/// (`rawPayload` included).
public actor PIMEventWriteService {
    /// Errors surfaced by the write path.
    public enum WriteError: Error, Sendable, Hashable, LocalizedError {
        /// The source lacks the write capability or the collection is
        /// read-only — the UI should never have offered the action.
        case notWritable
        /// The source record has no usable credential path.
        case missingCredential
        /// The remote changed since the cached copy — reload and re-ask.
        case conflict
        /// The credential was rejected or lacks the write scope.
        case authenticationRequired
        /// The provider answered with a status or body Brev cannot use.
        case invalidResponse
        /// Connectivity or an unspecified transport failure.
        case transportFailed
        /// The provider is not served by this write path.
        case unsupportedProvider

        public var errorDescription: String? {
            switch self {
            case .notWritable:
                String(
                    localized:
                    "This calendar is read-only.",
                    bundle: .module
                )
            case .missingCredential:
                String(
                    localized:
                    "The source has no stored credential. Reconnect it first.",
                    bundle: .module
                )
            case .conflict:
                String(
                    localized:
                    "This event changed on the server. Sync, then try again.",
                    bundle: .module
                )
            case .authenticationRequired:
                String(
                    localized:
                    "Editing needs a fresh grant. Reconnect the source in Settings.",
                    bundle: .module
                )
            case .invalidResponse:
                String(
                    localized:
                    "The provider returned a response Brev could not use.",
                    bundle: .module
                )
            case .transportFailed:
                String(
                    localized:
                    "The server could not be reached. Check the connection and try again.",
                    bundle: .module
                )
            case .unsupportedProvider:
                String(
                    localized:
                    "This source does not support editing.",
                    bundle: .module
                )
            }
        }
    }

    private let coordinator: PIMSourceCoordinator
    private let collectionStore: any PIMCollectionStore
    private let eventStore: any PIMEventStore
    private let credentials: any CalDAVCredentialStore
    private let googleWriter: GoogleCalendarEventWriter
    private let davWriter: PIMDAVEventWriter
    /// Resolves a Google access token for a linked mail account ID —
    /// injected by the session so this package stays provider-agnostic.
    private let googleAccessToken: (@Sendable (String) async throws -> String)?
    private let now: () -> Date

    public init(
        coordinator: PIMSourceCoordinator,
        collectionStore: any PIMCollectionStore,
        eventStore: any PIMEventStore,
        credentials: any CalDAVCredentialStore,
        googleWriter: GoogleCalendarEventWriter = GoogleCalendarEventWriter(),
        davWriter: PIMDAVEventWriter = PIMDAVEventWriter(),
        googleAccessToken: (@Sendable (String) async throws -> String)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.coordinator = coordinator
        self.collectionStore = collectionStore
        self.eventStore = eventStore
        self.credentials = credentials
        self.googleWriter = googleWriter
        self.davWriter = davWriter
        self.googleAccessToken = googleAccessToken
        self.now = now
    }

    // MARK: - Capability

    /// Whether a write may run: the source carries the `.write`
    /// capability and the collection is not read-only. Provider
    /// support is checked separately — CardDAV sources never reach
    /// the event write path. nonisolated: a pure function of the two
    /// records, so UI code can gate affordances without an await.
    public nonisolated func canWrite(
        source: PIMSource,
        collection: PIMCollection
    ) -> Bool {
        source.enabledCapabilities.contains(.write)
            && !collection.isReadOnly
            && [PIMSourceProvider.google, .calDAV].contains(source.provider)
    }

    /// The writable collections on a source — the editor's target list.
    public func writableCollections(
        for sourceID: PIMSource.ID
    ) async throws -> [PIMCollection] {
        guard let source = try await coordinator.source(id: sourceID)
        else { return [] }
        let collections = try await collectionStore.collections(
            for: sourceID
        )
        return collections.filter {
            canWrite(source: source, collection: $0)
        }
    }

    // MARK: - Create

    /// Creates an event in a writable collection and stores the
    /// provider-assigned record in the cache. The new UID is generated
    /// here — callers never invent one.
    @discardableResult
    public func create(
        _ event: PIMEvent,
        in collection: PIMCollection,
        source: PIMSource
    ) async throws -> PIMEvent {
        guard canWrite(source: source, collection: collection) else {
            throw WriteError.notWritable
        }
        let uid = event.uid ?? "\(UUID().uuidString)@brev"
        var draft = event
        draft.uid = uid
        switch source.provider {
        case .google:
            let token = try await googleToken(for: source)
            let result = try await mapGoogleError {
                try await googleWriter.insert(
                    draft,
                    into: collection,
                    accessToken: token
                )
            }
            draft.providerItemKey = result.eventID
            draft.providerVersion = result.etag
        case .calDAV:
            let credential = try await davCredential(for: source)
            let ics = PIMEventICSWriter.vcalendar(
                for: draft,
                dtstamp: now()
            )
            let result = try await mapDAVError {
                try await davWriter.create(
                    draft,
                    ics: ics,
                    in: collection,
                    credential: credential
                )
            }
            draft.providerItemKey = result.resourceURL.absoluteString
            draft.providerVersion = result.etag
        case .cardDAV:
            throw WriteError.unsupportedProvider
        }
        // id/sourceID/collectionID are immutable identity — re-anchor the
        // stored record onto the provider-assigned key via the memberwise
        // init rather than mutating the draft in place.
        let stored = PIMEvent(
            id: PIMEvent.makeID(
                collectionID: collection.id,
                providerItemKey: draft.providerItemKey,
                recurrenceID: draft.recurrenceID
            ),
            sourceID: source.id,
            collectionID: collection.id,
            providerItemKey: draft.providerItemKey,
            providerVersion: draft.providerVersion,
            uid: draft.uid,
            summary: draft.summary,
            eventDescription: draft.eventDescription,
            location: draft.location,
            start: draft.start,
            end: draft.end,
            isAllDay: draft.isAllDay,
            timeZoneIdentifier: draft.timeZoneIdentifier,
            status: draft.status,
            organizer: draft.organizer,
            attendees: draft.attendees,
            reminders: draft.reminders,
            conferenceURL: draft.conferenceURL,
            recurrenceRule: draft.recurrenceRule,
            recurrenceID: draft.recurrenceID,
            rawPayload: draft.rawPayload,
            providerUpdatedAt: draft.providerUpdatedAt,
            syncedAt: now()
        )
        try await store(stored, in: collection)
        return stored
    }

    // MARK: - Update

    /// Replaces the writable fields of a cached event under its stored
    /// version precondition. Returns the updated cache record.
    @discardableResult
    public func update(
        _ event: PIMEvent,
        in collection: PIMCollection,
        source: PIMSource
    ) async throws -> PIMEvent {
        guard canWrite(source: source, collection: collection) else {
            throw WriteError.notWritable
        }
        var updated = event
        switch source.provider {
        case .google:
            let token = try await googleToken(for: source)
            let result = try await mapGoogleError {
                try await googleWriter.patch(
                    updated,
                    in: collection,
                    accessToken: token
                )
            }
            updated.providerVersion = result.etag
        case .calDAV:
            let credential = try await davCredential(for: source)
            let ics = PIMEventICSWriter.vcalendar(
                for: updated,
                dtstamp: now()
            )
            let result = try await mapDAVError {
                try await davWriter.update(
                    updated,
                    ics: ics,
                    in: collection,
                    credential: credential
                )
            }
            updated.providerVersion = result.etag
        case .cardDAV:
            throw WriteError.unsupportedProvider
        }
        updated.syncedAt = now()
        try await store(updated, in: collection)
        return updated
    }

    // MARK: - Delete

    /// Deletes a cached event remotely, then removes it from the cache.
    /// A remote 404 still clears the local record — the desired end
    /// state already held.
    public func delete(
        _ event: PIMEvent,
        in collection: PIMCollection,
        source: PIMSource
    ) async throws {
        guard canWrite(source: source, collection: collection) else {
            throw WriteError.notWritable
        }
        switch source.provider {
        case .google:
            let token = try await googleToken(for: source)
            try await mapGoogleError {
                try await googleWriter.delete(
                    event,
                    in: collection,
                    accessToken: token
                )
            }
        case .calDAV:
            let credential = try await davCredential(for: source)
            try await mapDAVError {
                try await davWriter.delete(
                    event,
                    in: collection,
                    credential: credential
                )
            }
        case .cardDAV:
            throw WriteError.unsupportedProvider
        }
        var remaining = try await eventStore.events(
            for: source.id,
            collectionID: collection.id
        )
        remaining.removeAll { $0.id == event.id }
        try await eventStore.saveEvents(
            remaining,
            for: source.id,
            collectionID: collection.id
        )
    }

    // MARK: - Cache

    /// Inserts or replaces the record inside its collection's cached
    /// event list — the sync engine owns full-generation saves, so the
    /// write path patches the single record instead.
    private func store(
        _ event: PIMEvent,
        in collection: PIMCollection
    ) async throws {
        var events = try await eventStore.events(
            for: event.sourceID,
            collectionID: collection.id
        )
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        } else {
            events.append(event)
        }
        try await eventStore.saveEvents(
            events,
            for: event.sourceID,
            collectionID: collection.id
        )
    }

    // MARK: - Credentials

    private func googleToken(for source: PIMSource) async throws -> String {
        guard let accountID = source.linkedAccountID,
              let googleAccessToken
        else { throw WriteError.missingCredential }
        return try await googleAccessToken(accountID)
    }

    private func davCredential(
        for source: PIMSource
    ) async throws -> CalDAVCredential {
        guard let account = source.credentialAccount,
              let credential = try await credentials.credential(
                  for: account
              )
        else { throw WriteError.missingCredential }
        return credential
    }

    // MARK: - Error mapping

    private func mapGoogleError<T>(
        _ work: () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch let error as GoogleCalendarEventWriter.WriteError {
            switch error {
            case .authenticationRequired:
                throw WriteError.authenticationRequired
            case .conflict:
                throw WriteError.conflict
            case .invalidResponse:
                throw WriteError.invalidResponse
            case .transportFailed:
                throw WriteError.transportFailed
            }
        }
    }

    private func mapDAVError<T>(
        _ work: () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch let error as PIMDAVEventWriter.WriteError {
            switch error {
            case .authenticationRequired:
                throw WriteError.authenticationRequired
            case .conflict:
                throw WriteError.conflict
            case .invalidResponse:
                throw WriteError.invalidResponse
            case .transportFailed:
                throw WriteError.transportFailed
            case .invalidCollection:
                throw WriteError.invalidResponse
            }
        }
    }
}
