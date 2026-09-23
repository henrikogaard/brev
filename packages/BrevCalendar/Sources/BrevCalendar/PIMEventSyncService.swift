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

/// Service-level sync failures that are not adapter errors.
public enum PIMEventSyncServiceError: Error, Sendable, Hashable, LocalizedError {
    /// No source exists for the requested ID.
    case unknownSource
    /// The source is disconnected or still connecting; reconnect first.
    case sourceNotReady
    /// The source record has no usable credential path.
    case missingCredential
    /// This session cannot resolve a Google access token.
    case googleAuthorizationUnavailable
    /// The source does not serve calendars.
    case unsupportedKind

    public var errorDescription: String? {
        switch self {
        case .unknownSource:
            return String(
                localized: "The source no longer exists.",
                bundle: .module
            )
        case .sourceNotReady:
            return String(
                localized: "Reconnect the source before syncing.",
                bundle: .module
            )
        case .missingCredential:
            return String(
                localized: "The source has no stored credential. Reconnect it first.",
                bundle: .module
            )
        case .googleAuthorizationUnavailable:
            return String(
                localized: "Google authorization is unavailable in this session.",
                bundle: .module
            )
        case .unsupportedKind:
            return String(
                localized: "This source does not provide calendars.",
                bundle: .module
            )
        }
    }
}

/// Owns event sync and the cached event set per calendar source
/// (ADR-0072 sync rules 1–3).
///
/// Sync is always user-initiated in this slice — a Sync Now action or
/// the enable gesture — so it adds no background network traffic
/// (ADR-0006). Each visible collection syncs independently: a failure
/// records a per-collection error and keeps the prior snapshot, so one
/// unhealthy collection never blanks the others. A new generation's
/// cursor commits only after its complete batch is saved; an expired
/// cursor retries once as a full sync while the previous snapshot stays
/// readable.
public actor PIMEventSyncService {
    private let coordinator: PIMSourceCoordinator
    private let collectionStore: any PIMCollectionStore
    private let eventStore: any PIMEventStore
    private let cursorStore: any PIMSyncCursorStore
    private let credentials: any CalDAVCredentialStore
    private let googleSync: GoogleCalendarEventSync
    private let davSync: PIMDAVEventSync
    /// Resolves a Google access token for a linked mail account ID.
    /// Injected by the session so this package stays provider-agnostic.
    private let googleAccessToken: (@Sendable (String) async throws -> String)?
    /// Full-sync listing window: how far back and ahead a complete
    /// fetch reads. Incremental syncs are unbounded — the provider's
    /// token already scopes them to changes.
    private let windowPast: TimeInterval
    private let windowFuture: TimeInterval
    private let now: () -> Date

    public init(
        coordinator: PIMSourceCoordinator,
        collectionStore: any PIMCollectionStore,
        eventStore: any PIMEventStore,
        cursorStore: any PIMSyncCursorStore,
        credentials: any CalDAVCredentialStore,
        googleSync: GoogleCalendarEventSync = GoogleCalendarEventSync(),
        davSync: PIMDAVEventSync = PIMDAVEventSync(),
        googleAccessToken: (@Sendable (String) async throws -> String)? = nil,
        windowPast: TimeInterval = 365 * 24 * 60 * 60,
        windowFuture: TimeInterval = 2 * 365 * 24 * 60 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.coordinator = coordinator
        self.collectionStore = collectionStore
        self.eventStore = eventStore
        self.cursorStore = cursorStore
        self.credentials = credentials
        self.googleSync = googleSync
        self.davSync = davSync
        self.googleAccessToken = googleAccessToken
        self.windowPast = windowPast
        self.windowFuture = windowFuture
        self.now = now
    }

    /// Statuses from which a sync may run. Disconnected, connecting and
    /// authentication-required sources must complete that transition
    /// first.
    private static let syncableStatuses: Set<PIMSourceStatus> = [
        .ready, .syncing, .permissionLimited, .failed
    ]

    // MARK: - Queries

    /// Cached events for one collection, sorted by start.
    public func events(
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws -> [PIMEvent] {
        try await eventStore
            .events(for: sourceID, collectionID: collectionID)
            .sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
    }

    /// Cached events across every collection of a source, sorted by
    /// start. Offline browsing reads only this cache — it never issues
    /// provider requests.
    public func events(for sourceID: PIMSource.ID) async throws -> [PIMEvent] {
        try await eventStore
            .events(for: sourceID)
            .sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
    }

    // MARK: - Sync

    /// Syncs every visible collection of a calendar source.
    ///
    /// Hidden collections keep their cached records but do not sync —
    /// the user's visibility choice gates provider traffic. The source
    /// is marked syncing for the duration and returns to ready, or
    /// failed when every collection failed.
    @discardableResult
    public func syncNow(
        sourceID: PIMSource.ID
    ) async throws -> PIMEventSyncSummary {
        guard let source = try await coordinator.source(id: sourceID) else {
            throw PIMEventSyncServiceError.unknownSource
        }
        guard source.kind == .calendar else {
            throw PIMEventSyncServiceError.unsupportedKind
        }
        guard Self.syncableStatuses.contains(source.status) else {
            throw PIMEventSyncServiceError.sourceNotReady
        }
        _ = try? await coordinator.markStatus(.syncing, for: sourceID)

        let collections = try await collectionStore
            .collections(for: sourceID)
            .filter(\.isVisible)

        var summary = PIMEventSyncSummary()
        for collection in collections {
            do {
                let counts = try await syncCollection(
                    collection,
                    source: source
                )
                summary.syncedCollections += 1
                summary.upsertedEvents += counts.upserted
                summary.removedEvents += counts.removed
            } catch let error as PIMEventSyncError
                where error == .authenticationRequired {
                // One credential serves every collection on the source —
                // when it is rejected the rest cannot succeed either.
                _ = try? await coordinator.markStatus(
                    .authenticationRequired,
                    for: sourceID,
                    detail: String(describing: error)
                )
                summary.failures.append(
                    .init(
                        collectionID: collection.id,
                        message: String(describing: error)
                    )
                )
                return summary
            } catch {
                summary.failures.append(
                    .init(
                        collectionID: collection.id,
                        message: String(describing: error)
                    )
                )
            }
        }

        if summary.failures.isEmpty {
            _ = try? await coordinator.markStatus(.ready, for: sourceID)
        } else if summary.syncedCollections == 0 {
            _ = try? await coordinator.markStatus(
                .failed,
                for: sourceID,
                detail: summary.failures.first?.message
            )
        } else {
            // Partial success: the source stays usable and the summary
            // names the collections that kept their prior snapshot.
            _ = try? await coordinator.markStatus(
                .ready,
                for: sourceID,
                detail: summary.failures.first?.message
            )
        }
        return summary
    }

    // MARK: - Per-collection sync

    private func syncCollection(
        _ collection: PIMCollection,
        source: PIMSource
    ) async throws -> (upserted: Int, removed: Int) {
        let cursor = try await cursorStore.cursor(
            for: source.id,
            collectionID: collection.id
        )
        let cached = try await eventStore.events(
            for: source.id,
            collectionID: collection.id
        )
        let cachedVersions = Dictionary(
            uniqueKeysWithValues: cached.map {
                ($0.providerItemKey, $0.providerVersion ?? "")
            }
        )

        var result = try await runSync(
            collection: collection,
            source: source,
            cursorToken: cursor?.token,
            cachedVersions: cachedVersions
        )
        if result.nextCursorToken == nil {
            result.nextCursorToken = cursor?.token
        }

        var merged: [PIMEvent]
        if result.isFullSnapshot {
            let kept = Set(result.keptItemKeys)
            merged = result.events + cached.filter {
                kept.contains($0.providerItemKey)
            }
        } else {
            let upsertedKeys = Set(result.events.map(\.providerItemKey))
            let removedKeys = Set(result.removedItemKeys)
            merged = cached.filter {
                !removedKeys.contains($0.providerItemKey)
                    && !upsertedKeys.contains($0.providerItemKey)
            } + result.events
        }
        merged = droppingStaleHrefs(in: merged, incoming: result.events)

        // The complete generation commits before its checkpoint: a crash
        // between the two writes re-syncs conservatively rather than
        // skipping changes (ADR-0072 sync rule 1).
        try await eventStore.saveEvents(
            merged,
            for: source.id,
            collectionID: collection.id
        )
        try await cursorStore.saveCursor(
            PIMSyncCursor(
                collectionID: collection.id,
                token: result.nextCursorToken,
                completedAt: now()
            ),
            for: source.id
        )
        return (result.events.count, result.removedItemKeys.count)
    }

    /// Drops cached records an incoming item supersedes by identity:
    /// a server-side rename reports the item at a new href while the
    /// dead-href copy stays cached (see `PIMSyncItemIdentity`).
    private func droppingStaleHrefs(
        in merged: [PIMEvent],
        incoming: [PIMEvent]
    ) -> [PIMEvent] {
        var liveKeys: [PIMSyncItemIdentity: Set<String>] = [:]
        for event in incoming {
            guard let uid = event.uid else { continue }
            liveKeys[
                PIMSyncItemIdentity(
                    uid: uid,
                    recurrenceID: event.recurrenceID
                ),
                default: []
            ].insert(event.providerItemKey)
        }
        guard !liveKeys.isEmpty else { return merged }
        return merged.filter { event in
            guard let uid = event.uid,
                  let keys = liveKeys[
                      PIMSyncItemIdentity(
                          uid: uid,
                          recurrenceID: event.recurrenceID
                      )
                  ]
            else { return true }
            return keys.contains(event.providerItemKey)
        }
    }

    /// Runs the provider adapter with one full-resync retry when the
    /// stored cursor was rejected (ADR-0072 sync rule 2).
    private func runSync(
        collection: PIMCollection,
        source: PIMSource,
        cursorToken: String?,
        cachedVersions: [String: String]
    ) async throws -> PIMEventSyncResult {
        do {
            return try await adapterSync(
                collection: collection,
                source: source,
                cursorToken: cursorToken,
                cachedVersions: cachedVersions
            )
        } catch PIMEventSyncError.cursorExpired {
            guard cursorToken != nil else { throw PIMEventSyncError.cursorExpired }
            return try await adapterSync(
                collection: collection,
                source: source,
                cursorToken: nil,
                cachedVersions: cachedVersions
            )
        }
    }

    private func adapterSync(
        collection: PIMCollection,
        source: PIMSource,
        cursorToken: String?,
        cachedVersions: [String: String]
    ) async throws -> PIMEventSyncResult {
        let windowStart = now().addingTimeInterval(-windowPast)
        let windowEnd = now().addingTimeInterval(windowFuture)
        switch source.provider {
        case .google:
            guard let accountID = source.linkedAccountID else {
                throw PIMEventSyncServiceError.missingCredential
            }
            guard let googleAccessToken else {
                throw PIMEventSyncServiceError.googleAuthorizationUnavailable
            }
            let token = try await googleAccessToken(accountID)
            return try await googleSync.syncCollection(
                collection,
                source: source,
                cursorToken: cursorToken,
                windowStart: windowStart,
                windowEnd: windowEnd,
                accessToken: token
            )
        case .calDAV:
            guard let account = source.credentialAccount,
                  let credential = try await credentials.credential(
                      for: account
                  )
            else {
                throw PIMEventSyncServiceError.missingCredential
            }
            return try await davSync.syncCollection(
                collection,
                source: source,
                cursorToken: cursorToken,
                cachedVersions: cachedVersions,
                windowStart: windowStart,
                windowEnd: windowEnd,
                credential: credential
            )
        case .cardDAV:
            throw PIMEventSyncServiceError.unsupportedKind
        }
    }
}
