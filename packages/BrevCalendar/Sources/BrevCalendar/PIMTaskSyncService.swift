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

/// Source-lifecycle failures surfaced by task sync (ADR-0072).
public enum PIMTaskSyncServiceError: Error, Sendable, Hashable, LocalizedError {
    /// The source record no longer exists.
    case unknownSource
    /// The source is disconnected, connecting, or needs credentials.
    case sourceNotReady
    /// The source has no stored credential to sync with.
    case missingCredential
    /// A Google source cannot resolve an access token in this session.
    case googleAuthorizationUnavailable
    /// The source kind is not served by the task sync engine.
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
                localized: "This source does not provide task lists.",
                bundle: .module
            )
        }
    }
}

/// Owns task sync and the cached task set per tasks source (ADR-0072
/// sync rules 1–3, #12).
///
/// Sync is always user-initiated in this slice — a Sync Now action or
/// the enable gesture — so it adds no background network traffic
/// (ADR-0006). Each visible collection syncs independently: a failure
/// records a per-collection error and keeps the prior snapshot, so one
/// unhealthy collection never blanks the others. A new generation's
/// cursor commits only after its complete batch is saved; an expired
/// cursor retries once as a full sync while the previous snapshot stays
/// readable.
public actor PIMTaskSyncService {
    private let coordinator: PIMSourceCoordinator
    private let collectionStore: any PIMCollectionStore
    private let taskStore: any PIMTaskStore
    private let cursorStore: any PIMSyncCursorStore
    private let credentials: any CalDAVCredentialStore
    private let googleSync: GoogleTaskSync
    private let davSync: PIMDAVTaskSync
    /// Resolves a Google access token for a linked mail account ID.
    /// Injected by the session so this package stays provider-agnostic.
    private let googleAccessToken: (@Sendable (String) async throws -> String)?
    private let now: () -> Date

    public init(
        coordinator: PIMSourceCoordinator,
        collectionStore: any PIMCollectionStore,
        taskStore: any PIMTaskStore,
        cursorStore: any PIMSyncCursorStore,
        credentials: any CalDAVCredentialStore,
        googleSync: GoogleTaskSync = GoogleTaskSync(),
        davSync: PIMDAVTaskSync = PIMDAVTaskSync(),
        googleAccessToken: (@Sendable (String) async throws -> String)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.coordinator = coordinator
        self.collectionStore = collectionStore
        self.taskStore = taskStore
        self.cursorStore = cursorStore
        self.credentials = credentials
        self.googleSync = googleSync
        self.davSync = davSync
        self.googleAccessToken = googleAccessToken
        self.now = now
    }

    /// Statuses from which a sync may run. Disconnected, connecting and
    /// authentication-required sources must complete that transition
    /// first.
    private static let syncableStatuses: Set<PIMSourceStatus> = [
        .ready, .syncing, .permissionLimited, .failed
    ]

    // MARK: - Queries

    /// Cached tasks for one collection, sorted by provider position so
    /// manual ordering survives; unordered tasks sort by title.
    public func tasks(
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws -> [PIMTask] {
        try await taskStore
            .tasks(for: sourceID, collectionID: collectionID)
            .sorted {
                ($0.position ?? "\u{7FFF}")
                    .localizedStandardCompare($1.position ?? "\u{7FFF}")
                    == .orderedAscending
            }
    }

    /// Cached tasks across every collection of a source.
    public func tasks(for sourceID: PIMSource.ID) async throws -> [PIMTask] {
        try await taskStore.tasks(for: sourceID)
    }

    // MARK: - Sync

    /// Syncs every visible collection of a tasks source.
    ///
    /// Hidden collections keep their cached records but do not sync —
    /// the user's visibility choice gates provider traffic. The source
    /// is marked syncing for the duration and returns to ready, or
    /// failed when every collection failed.
    @discardableResult
    public func syncNow(
        sourceID: PIMSource.ID
    ) async throws -> PIMTaskSyncSummary {
        guard let source = try await coordinator.source(id: sourceID) else {
            throw PIMTaskSyncServiceError.unknownSource
        }
        guard source.kind == .tasks else {
            throw PIMTaskSyncServiceError.unsupportedKind
        }
        guard Self.syncableStatuses.contains(source.status) else {
            throw PIMTaskSyncServiceError.sourceNotReady
        }
        _ = try? await coordinator.markStatus(.syncing, for: sourceID)

        let collections = try await collectionStore
            .collections(for: sourceID)
            .filter(\.isVisible)

        var summary = PIMTaskSyncSummary()
        for collection in collections {
            do {
                let counts = try await syncCollection(
                    collection,
                    source: source
                )
                summary.syncedCollections += 1
                summary.upsertedTasks += counts.upserted
                summary.removedTasks += counts.removed
            } catch let error as PIMTaskSyncError
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
        let cached = try await taskStore.tasks(
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

        let merged: [PIMTask]
        if result.isFullSnapshot {
            let kept = Set(result.keptItemKeys)
            merged = result.tasks + cached.filter {
                kept.contains($0.providerItemKey)
            }
        } else {
            let upsertedKeys = Set(result.tasks.map(\.providerItemKey))
            let removedKeys = Set(result.removedItemKeys)
            merged = cached.filter {
                !removedKeys.contains($0.providerItemKey)
                    && !upsertedKeys.contains($0.providerItemKey)
            } + result.tasks
        }

        // The complete generation commits before its checkpoint: a crash
        // between the two writes re-syncs conservatively rather than
        // skipping changes (ADR-0072 sync rule 1).
        try await taskStore.saveTasks(
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
        return (result.tasks.count, result.removedItemKeys.count)
    }

    /// Runs the provider adapter with one full-resync retry when the
    /// stored cursor was rejected (ADR-0072 sync rule 2).
    private func runSync(
        collection: PIMCollection,
        source: PIMSource,
        cursorToken: String?,
        cachedVersions: [String: String]
    ) async throws -> PIMTaskSyncResult {
        do {
            return try await adapterSync(
                collection: collection,
                source: source,
                cursorToken: cursorToken,
                cachedVersions: cachedVersions
            )
        } catch PIMTaskSyncError.cursorExpired {
            guard cursorToken != nil else { throw PIMTaskSyncError.cursorExpired }
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
    ) async throws -> PIMTaskSyncResult {
        switch source.provider {
        case .google:
            guard let accountID = source.linkedAccountID else {
                throw PIMTaskSyncServiceError.missingCredential
            }
            guard let googleAccessToken else {
                throw PIMTaskSyncServiceError.googleAuthorizationUnavailable
            }
            let token = try await googleAccessToken(accountID)
            return try await googleSync.syncCollection(
                collection,
                source: source,
                cursorToken: cursorToken,
                accessToken: token,
                passStartedAt: now()
            )
        case .calDAV:
            guard let account = source.credentialAccount,
                  let credential = try await credentials.credential(
                      for: account
                  )
            else {
                throw PIMTaskSyncServiceError.missingCredential
            }
            return try await davSync.syncCollection(
                collection,
                source: source,
                cursorToken: cursorToken,
                cachedVersions: cachedVersions,
                credential: credential
            )
        case .cardDAV:
            throw PIMTaskSyncServiceError.unsupportedKind
        }
    }
}
