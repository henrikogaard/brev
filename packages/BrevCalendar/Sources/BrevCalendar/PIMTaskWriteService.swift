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

/// Provider-neutral task write path (ADR-0072 #12).
///
/// Create, update, delete, and move dispatch on the source's provider —
/// Google via the `tasks` REST resource, CalDAV via PUT/DELETE on the
/// collection URL — behind one capability check: a write runs only when
/// the source's `enabledCapabilities` carries `.write` *and* the
/// target collection is not read-only. Preconditions ride every
/// mutation (Google `If-Match` etag, CalDAV `If-Match` /
/// `If-None-Match`) so a stale edit surfaces as `conflict` instead
/// of overwriting a newer remote change.
///
/// Ordering and parenting are capability fields: Google mutates them
/// through `tasks.move`, CalDAV through the VTODO properties
/// `X-APPLE-SORT-ORDER` and `RELATED-TO;RELTYPE=PARENT` on a normal
/// update. Cross-collection moves are a delete+create on both
/// providers — Google Tasks cannot move between lists.
///
/// After a successful write the local cache updates in place — the next
/// sync reconciles the provider's canonical record
/// (`rawPayload` included).
public actor PIMTaskWriteService {
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
                    "This task list is read-only.",
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
                    "This task changed on the server. Sync, then try again.",
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
    private let taskStore: any PIMTaskStore
    private let credentials: any CalDAVCredentialStore
    private let googleWriter: GoogleTaskWriter
    private let davWriter: PIMDAVTaskWriter
    /// Resolves a Google access token for a linked mail account ID —
    /// injected by the session so this package stays provider-agnostic.
    private let googleAccessToken: (@Sendable (String) async throws -> String)?
    private let now: () -> Date

    public init(
        coordinator: PIMSourceCoordinator,
        collectionStore: any PIMCollectionStore,
        taskStore: any PIMTaskStore,
        credentials: any CalDAVCredentialStore,
        googleWriter: GoogleTaskWriter = GoogleTaskWriter(),
        davWriter: PIMDAVTaskWriter = PIMDAVTaskWriter(),
        googleAccessToken: (@Sendable (String) async throws -> String)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.coordinator = coordinator
        self.collectionStore = collectionStore
        self.taskStore = taskStore
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
    /// the task write path. nonisolated: a pure function of the two
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

    /// Creates a task in a writable collection and stores the
    /// provider-assigned record in the cache. The new UID is generated
    /// here — callers never invent one.
    @discardableResult
    public func create(
        _ task: PIMTask,
        in collection: PIMCollection,
        source: PIMSource
    ) async throws -> PIMTask {
        guard canWrite(source: source, collection: collection) else {
            throw WriteError.notWritable
        }
        var draft = task
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
            draft.providerItemKey = result.taskID
            draft.providerVersion = result.etag
            if let item = result.item {
                draft.position = item.position
                draft.parentKey = item.parent
                draft.completedAt = Self.parseRFC3339(item.completed)
                    ?? draft.completedAt
                draft.providerUpdatedAt = Self.parseRFC3339(item.updated)
            }
        case .calDAV:
            if draft.uid == nil {
                draft.uid = "\(UUID().uuidString)@brev"
            }
            let credential = try await davCredential(for: source)
            let ics = PIMTaskICSWriter.vcalendar(
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
        // id/sourceID/collectionID are immutable identity — re-anchor
        // the stored record onto the provider-assigned key via the
        // memberwise init rather than mutating the draft in place.
        let stored = PIMTask(
            id: PIMTask.makeID(
                collectionID: collection.id,
                providerItemKey: draft.providerItemKey
            ),
            sourceID: source.id,
            collectionID: collection.id,
            providerItemKey: draft.providerItemKey,
            providerVersion: draft.providerVersion,
            uid: draft.uid ?? draft.providerItemKey,
            title: draft.title,
            notes: draft.notes,
            due: draft.due,
            completedAt: draft.completedAt,
            status: draft.status,
            position: draft.position,
            parentKey: draft.parentKey,
            links: draft.links,
            rawPayload: draft.rawPayload,
            providerUpdatedAt: draft.providerUpdatedAt,
            syncedAt: now()
        )
        try await store(stored, in: collection)
        return stored
    }

    // MARK: - Update

    /// Replaces the writable fields of a cached task under its stored
    /// version precondition. Returns the updated cache record.
    @discardableResult
    public func update(
        _ task: PIMTask,
        in collection: PIMCollection,
        source: PIMSource
    ) async throws -> PIMTask {
        guard canWrite(source: source, collection: collection) else {
            throw WriteError.notWritable
        }
        var updated = task
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
            if let item = result.item {
                // Patch responses carry the full resource — refresh the
                // provider-owned fields so a server-side completion
                // timestamp resolves in place.
                updated.position = item.position
                updated.parentKey = item.parent
                updated.completedAt = Self.parseRFC3339(item.completed)
                    ?? updated.completedAt
                updated.providerUpdatedAt = Self.parseRFC3339(item.updated)
            }
        case .calDAV:
            let credential = try await davCredential(for: source)
            let ics = PIMTaskICSWriter.vcalendar(
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

    // MARK: - Reorder / reparent

    /// Reorders or reparents a task inside its collection.
    ///
    /// Google routes through `tasks.move` with provider task IDs;
    /// `parent`/`previous` nil leaves that axis unchanged. CalDAV
    /// has no move verb — the caller updates `position` or
    /// `parentKey` on the record and calls `update`, so this path
    /// applies those fields as a normal conditional replace.
    @discardableResult
    public func move(
        _ task: PIMTask,
        in collection: PIMCollection,
        source: PIMSource,
        parent: String?,
        previous: String?
    ) async throws -> PIMTask {
        guard canWrite(source: source, collection: collection) else {
            throw WriteError.notWritable
        }
        var updated = task
        switch source.provider {
        case .google:
            let token = try await googleToken(for: source)
            let result = try await mapGoogleError {
                try await googleWriter.move(
                    updated,
                    in: collection,
                    parent: parent,
                    previous: previous,
                    accessToken: token
                )
            }
            updated.providerVersion = result.etag
            if let item = result.item {
                updated.position = item.position
                updated.parentKey = item.parent
                updated.providerUpdatedAt = Self.parseRFC3339(item.updated)
            }
        case .calDAV:
            let credential = try await davCredential(for: source)
            let ics = PIMTaskICSWriter.vcalendar(
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

    // MARK: - Cross-collection move

    /// Moves a task to another collection on the same source. Neither
    /// provider has a cross-list move: the write is a create in the
    /// target followed by a delete in the origin. A create failure
    /// leaves the task untouched; a delete failure after a successful
    /// create throws `conflict` so the caller re-syncs rather than
    /// keeping a silent duplicate.
    @discardableResult
    public func move(
        _ task: PIMTask,
        to target: PIMCollection,
        in collection: PIMCollection,
        source: PIMSource
    ) async throws -> PIMTask {
        guard canWrite(source: source, collection: collection),
              canWrite(source: source, collection: target)
        else {
            throw WriteError.notWritable
        }
        // A fresh record in the target: provider identity fields reset,
        // user-facing fields carry over. Parent links are list-scoped
        // on Google and UID-scoped on DAV — a moved task re-roots.
        var draft = task
        draft.uid = nil
        draft.providerItemKey = ""
        draft.providerVersion = nil
        draft.parentKey = nil
        draft.position = nil
        let created = try await create(
            draft,
            in: target,
            source: source
        )
        do {
            try await delete(task, in: collection, source: source)
        } catch {
            throw WriteError.conflict
        }
        return created
    }

    // MARK: - Delete

    /// Deletes a cached task remotely, then removes it from the cache.
    /// A remote 404 still clears the local record — the desired end
    /// state already held.
    public func delete(
        _ task: PIMTask,
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
                    task,
                    in: collection,
                    accessToken: token
                )
            }
        case .calDAV:
            let credential = try await davCredential(for: source)
            try await mapDAVError {
                try await davWriter.delete(
                    task,
                    in: collection,
                    credential: credential
                )
            }
        case .cardDAV:
            throw WriteError.unsupportedProvider
        }
        var remaining = try await taskStore.tasks(
            for: source.id,
            collectionID: collection.id
        )
        remaining.removeAll { $0.id == task.id }
        try await taskStore.saveTasks(
            remaining,
            for: source.id,
            collectionID: collection.id
        )
    }

    // MARK: - Cache

    /// Inserts or replaces the record inside its collection's cached
    /// task list — the sync engine owns full-generation saves, so the
    /// write path patches the single record instead.
    private func store(
        _ task: PIMTask,
        in collection: PIMCollection
    ) async throws {
        var tasks = try await taskStore.tasks(
            for: task.sourceID,
            collectionID: collection.id
        )
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        try await taskStore.saveTasks(
            tasks,
            for: task.sourceID,
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
        } catch let error as GoogleTaskWriter.WriteError {
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
        } catch let error as PIMDAVTaskWriter.WriteError {
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

    // MARK: - Dates

    /// RFC 3339 with optional fractional seconds — the Tasks API's
    /// timestamp form.
    private static func parseRFC3339(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [
            .withInternetDateTime, .withFractionalSeconds,
        ]
        if let date = withFractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }
}
