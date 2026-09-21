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

/// Service-level collection failures that are not adapter errors.
public enum PIMCollectionServiceError: Error, Sendable, Hashable, LocalizedError {
    /// No source exists for the requested ID.
    case unknownSource
    /// The source is disconnected or still connecting; reconnect first.
    case sourceNotReady
    /// The source record has no usable credential path.
    case missingCredential
    /// This session cannot resolve a Google access token.
    case googleAuthorizationUnavailable
    /// No collection exists for the requested ID on the source.
    case unknownCollection

    public var errorDescription: String? {
        switch self {
        case .unknownSource:
            return String(
                localized: "The source no longer exists.",
                bundle: .module
            )
        case .sourceNotReady:
            return String(
                localized: "Reconnect the source before refreshing its collections.",
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
        case .unknownCollection:
            return String(
                localized: "The collection no longer exists on this source.",
                bundle: .module
            )
        }
    }
}

/// Owns collection discovery and the cached collection list per source
/// (ADR-0072).
///
/// Refresh is always user-initiated — a successful connect, or the
/// explicit refresh action in Settings — so discovery adds no background
/// network traffic (ADR-0006). A failed refresh marks the source failed
/// but leaves the cached list untouched, so one unhealthy source never
/// blanks what it already showed.
public actor PIMCollectionService {
    private let coordinator: PIMSourceCoordinator
    private let store: any PIMCollectionStore
    private let credentials: any CalDAVCredentialStore
    private let davDiscovery: PIMDAVCollectionDiscovery
    private let googleDiscovery: GooglePIMCollectionDiscovery
    /// Resolves a Google access token for a linked mail account ID.
    /// Injected by the session so this package stays provider-agnostic.
    private let googleAccessToken: (@Sendable (String) async throws -> String)?
    private let now: () -> Date

    public init(
        coordinator: PIMSourceCoordinator,
        store: any PIMCollectionStore,
        credentials: any CalDAVCredentialStore,
        davDiscovery: PIMDAVCollectionDiscovery = PIMDAVCollectionDiscovery(),
        googleDiscovery: GooglePIMCollectionDiscovery = GooglePIMCollectionDiscovery(),
        googleAccessToken: (@Sendable (String) async throws -> String)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.coordinator = coordinator
        self.store = store
        self.credentials = credentials
        self.davDiscovery = davDiscovery
        self.googleDiscovery = googleDiscovery
        self.googleAccessToken = googleAccessToken
        self.now = now
    }

    /// Statuses from which a collection refresh may run. Disconnected,
    /// connecting and authentication-required sources must complete that
    /// transition first.
    private static let refreshableStatuses: Set<PIMSourceStatus> = [
        .ready, .syncing, .permissionLimited, .failed
    ]

    // MARK: - Queries

    /// Cached collections for a source: primary first, then by name.
    public func collections(for sourceID: PIMSource.ID) async throws -> [PIMCollection] {
        try await store.collections(for: sourceID).sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
            return lhs.displayName.localizedCaseInsensitiveCompare(
                rhs.displayName
            ) == .orderedAscending
        }
    }

    // MARK: - Refresh

    /// Re-discovers a source's collections and persists the merged set.
    ///
    /// Visibility choices survive a refresh by provider key; collections
    /// seen for the first time start hidden only when the provider says
    /// so. On failure the source is marked failed and the cached list is
    /// left untouched (ADR-0072: a failed source never empties what it
    /// already showed).
    @discardableResult
    public func refreshCollections(
        for sourceID: PIMSource.ID
    ) async throws -> [PIMCollection] {
        guard let source = try await coordinator.source(id: sourceID) else {
            throw PIMCollectionServiceError.unknownSource
        }
        guard Self.refreshableStatuses.contains(source.status) else {
            throw PIMCollectionServiceError.sourceNotReady
        }
        do {
            let discovered = try await discover(source)
            let existing = try await store.collections(for: sourceID)
            let timestamp = now()
            var merged = discovered.map { item in
                let prior = existing.first {
                    $0.providerKey == item.providerKey
                }
                return PIMCollection(
                    id: PIMCollection.makeID(
                        sourceID: sourceID,
                        providerKey: item.providerKey
                    ),
                    sourceID: sourceID,
                    kind: source.kind,
                    displayName: item.displayName,
                    colorHex: item.colorHex,
                    isReadOnly: item.isReadOnly,
                    isPrimary: item.isPrimary,
                    supportsSyncToken: item.supportsSyncToken,
                    providerKey: item.providerKey,
                    providerVersion: item.providerVersion,
                    isVisible: prior?.isVisible ?? !item.initiallyHidden,
                    updatedAt: timestamp
                )
            }
            merged.sort { $0.id < $1.id }
            try await store.saveCollections(merged, for: sourceID)
            // A successful refresh clears a prior discovery failure.
            if source.status == .failed {
                _ = try? await coordinator.markStatus(.ready, for: sourceID)
            }
            return merged
        } catch {
            _ = try? await coordinator.markStatus(
                .failed,
                for: sourceID,
                detail: String(describing: error)
            )
            throw error
        }
    }

    // MARK: - Visibility

    /// Toggles whether a collection participates in sync and browsing.
    /// Local-only; never contacts the provider.
    public func setVisible(
        _ isVisible: Bool,
        collectionID: PIMCollection.ID,
        sourceID: PIMSource.ID
    ) async throws {
        var collections = try await store.collections(for: sourceID)
        guard let index = collections.firstIndex(where: {
            $0.id == collectionID
        }) else {
            throw PIMCollectionServiceError.unknownCollection
        }
        collections[index].isVisible = isVisible
        collections[index].updatedAt = now()
        try await store.saveCollections(collections, for: sourceID)
    }

    // MARK: - Provider dispatch

    private func discover(
        _ source: PIMSource
    ) async throws -> [PIMDiscoveredCollection] {
        switch source.provider {
        case .calDAV, .cardDAV:
            guard let account = source.credentialAccount,
                  let credential = try await credentials.credential(
                      for: account
                  )
            else {
                throw PIMCollectionServiceError.missingCredential
            }
            return try await davDiscovery.discoverCollections(
                for: source,
                credential: credential
            )
        case .google:
            guard let accountID = source.linkedAccountID else {
                throw PIMCollectionServiceError.missingCredential
            }
            guard let googleAccessToken else {
                throw PIMCollectionServiceError.googleAuthorizationUnavailable
            }
            let token = try await googleAccessToken(accountID)
            return try await googleDiscovery.discoverCollections(
                kind: source.kind,
                accessToken: token
            )
        }
    }
}
