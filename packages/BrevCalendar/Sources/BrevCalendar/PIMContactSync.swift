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

/// What one contacts sync scope produced (ADR-0072 sync rule 1).
/// Mirrors the event-sync contract: incremental results upsert and
/// tombstone; full snapshots replace the scope's set, with
/// `keptItemKeys` naming unchanged items a listing confirmed without
/// refetching.
public struct PIMContactSyncResult: Sendable, Hashable {
    /// Records to insert or replace, keyed by provider item key.
    public var contacts: [PIMContact]
    /// Provider item keys removed on the provider side (tombstones).
    public var removedItemKeys: [String]
    /// Provider item keys confirmed unchanged by a full listing.
    public var keptItemKeys: [String]
    /// Opaque next-generation cursor token, when the provider gave one.
    public var nextCursorToken: String?
    /// True when the result describes the scope's complete state.
    public var isFullSnapshot: Bool

    public init(
        contacts: [PIMContact] = [],
        removedItemKeys: [String] = [],
        keptItemKeys: [String] = [],
        nextCursorToken: String? = nil,
        isFullSnapshot: Bool = false
    ) {
        self.contacts = contacts
        self.removedItemKeys = removedItemKeys
        self.keptItemKeys = keptItemKeys
        self.nextCursorToken = nextCursorToken
        self.isFullSnapshot = isFullSnapshot
    }
}

/// Contacts-sync failures that are not source-setup errors.
public enum PIMContactSyncError: Error, Sendable, Hashable, LocalizedError {
    /// The stored cursor was rejected; the service retries once as a
    /// full sync.
    case cursorExpired
    /// The credential was rejected or lacks the feature's scope.
    case authenticationRequired
    /// Connectivity or an unspecified transport failure.
    case transportFailed
    /// The provider answered with a status or body Brev cannot use.
    case invalidResponse
    /// The server does not implement the advertised sync mechanism.
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
                localized: "The server does not support contacts sync.",
                bundle: .module
            )
        case .unsupportedKind:
            return String(
                localized: "This source does not provide contacts.",
                bundle: .module
            )
        }
    }
}

/// Aggregate outcome of a contacts sync pass (ADR-0072 failure
/// isolation).
public struct PIMContactSyncSummary: Sendable, Hashable {
    /// One scope (collection or account-wide feed) that failed without
    /// disturbing the others.
    public struct ScopeFailure: Sendable, Hashable {
        public let scope: String
        /// Short diagnostic; not localized.
        public let message: String

        public init(scope: String, message: String) {
            self.scope = scope
            self.message = message
        }
    }

    /// Scopes whose new generation committed.
    public var syncedScopes = 0
    /// Records inserted or replaced across all scopes.
    public var upsertedContacts = 0
    /// Cached records removed by provider tombstones.
    public var removedContacts = 0
    /// Per-scope failures. A failure never blanks that scope's prior
    /// snapshot.
    public var failures: [ScopeFailure] = []

    public init() {}
}
