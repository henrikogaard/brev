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

/// What one task collection sync produced (ADR-0072 sync rule 1).
///
/// Same two shapes as event sync: incremental results upsert
/// `tasks` and delete `removedItemKeys`; a full snapshot replaces
/// the cached set with `tasks` plus the cached records whose keys
/// appear in `keptItemKeys`.
public struct PIMTaskSyncResult: Sendable, Hashable {
    /// Records to insert or replace, keyed by provider item key.
    public var tasks: [PIMTask]
    /// Provider item keys removed on the provider side (tombstones).
    public var removedItemKeys: [String]
    /// Provider item keys confirmed unchanged by a full listing; their
    /// cached records carry into the new snapshot.
    public var keptItemKeys: [String]
    /// Opaque next-generation cursor token, when the provider gave one.
    public var nextCursorToken: String?
    /// True when the result describes the collection's complete state.
    public var isFullSnapshot: Bool

    public init(
        tasks: [PIMTask] = [],
        removedItemKeys: [String] = [],
        keptItemKeys: [String] = [],
        nextCursorToken: String? = nil,
        isFullSnapshot: Bool = false
    ) {
        self.tasks = tasks
        self.removedItemKeys = removedItemKeys
        self.keptItemKeys = keptItemKeys
        self.nextCursorToken = nextCursorToken
        self.isFullSnapshot = isFullSnapshot
    }
}

/// Sync failures that are not source-setup errors (ADR-0072).
public enum PIMTaskSyncError: Error, Sendable, Hashable, LocalizedError {
    /// The stored cursor was rejected (DAV invalid sync-token). The
    /// service retries once as a full sync.
    case cursorExpired
    /// The credential was rejected or lacks the feature's scope.
    case authenticationRequired
    /// Connectivity or an unspecified transport failure.
    case transportFailed
    /// The provider answered with a status or body Brev cannot use.
    case invalidResponse
    /// The server does not implement the advertised sync mechanism;
    /// the caller may retry through a fallback path.
    case unsupportedServer
    /// The source kind is not served by this sync engine.
    case unsupportedKind

    public var errorDescription: String? {
        switch self {
        case .cursorExpired:
            return String(
                localized: "The sync checkpoint expired; a full refresh is needed.",
                bundle: .module
            )
        case .authenticationRequired:
            return String(
                localized: "The source rejected its credential. Reconnect it in Settings.",
                bundle: .module
            )
        case .transportFailed:
            return String(
                localized: "The server could not be reached. Check the connection and try again.",
                bundle: .module
            )
        case .invalidResponse:
            return String(
                localized: "The provider returned an unexpected response. Try syncing again.",
                bundle: .module
            )
        case .unsupportedServer:
            return String(
                localized: "The server does not support task sync.",
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

/// Aggregate outcome of a task source sync pass (ADR-0072 failure
/// isolation).
public struct PIMTaskSyncSummary: Sendable, Hashable {
    /// One collection that failed without disturbing the others.
    public struct CollectionFailure: Sendable, Hashable {
        public let collectionID: PIMCollection.ID
        /// Short diagnostic; not localized.
        public let message: String

        public init(collectionID: PIMCollection.ID, message: String) {
            self.collectionID = collectionID
            self.message = message
        }
    }

    /// Collections whose new generation committed.
    public var syncedCollections = 0
    /// Records inserted or replaced across all collections.
    public var upsertedTasks = 0
    /// Cached records removed by provider tombstones.
    public var removedTasks = 0
    /// Per-collection failures. A failure never blanks that collection's
    /// prior snapshot.
    public var failures: [CollectionFailure] = []

    public init() {}
}
