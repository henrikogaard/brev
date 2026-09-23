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

/// Service-level contacts-sync failures that are not adapter errors.
public enum PIMContactSyncServiceError: Error, Sendable, Hashable, LocalizedError {
    /// No source exists for the requested ID.
    case unknownSource
    /// The source is disconnected or still connecting; reconnect first.
    case sourceNotReady
    /// The source record has no usable credential path.
    case missingCredential
    /// This session cannot resolve a Google access token.
    case googleAuthorizationUnavailable
    /// The source does not serve contacts.
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
                localized: "This source does not provide contacts.",
                bundle: .module
            )
        }
    }
}

/// Owns contact sync and the cached contact set per contacts source
/// (ADR-0072 sync rules 1–3).
///
/// Sync is always user-initiated in this slice — a Sync Now action or
/// the enable gesture — so it adds no background network traffic
/// (ADR-0006). CardDAV sources sync each visible address book
/// independently; Google sources sync the account-wide connections feed
/// once, with group memberships recorded on each contact. A failed scope
/// records an error and keeps its prior snapshot, so one unhealthy
/// address book never blanks the others. A new generation's cursor
/// commits only after its complete batch is saved; an expired cursor
/// retries once as a full sync.
public actor PIMContactSyncService {
    private let coordinator: PIMSourceCoordinator
    private let collectionStore: any PIMCollectionStore
    private let contactStore: any PIMContactStore
    private let cursorStore: any PIMContactSyncCursorStore
    private let credentials: any CalDAVCredentialStore
    private let googleSync: GooglePeopleContactSync
    private let davSync: PIMDAVContactSync
    /// Resolves a Google access token for a linked mail account ID.
    /// Injected by the session so this package stays provider-agnostic.
    private let googleAccessToken: (@Sendable (String) async throws -> String)?
    private let now: () -> Date

    public init(
        coordinator: PIMSourceCoordinator,
        collectionStore: any PIMCollectionStore,
        contactStore: any PIMContactStore,
        cursorStore: any PIMContactSyncCursorStore,
        credentials: any CalDAVCredentialStore,
        googleSync: GooglePeopleContactSync = GooglePeopleContactSync(),
        davSync: PIMDAVContactSync = PIMDAVContactSync(),
        googleAccessToken: (@Sendable (String) async throws -> String)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.coordinator = coordinator
        self.collectionStore = collectionStore
        self.contactStore = contactStore
        self.cursorStore = cursorStore
        self.credentials = credentials
        self.googleSync = googleSync
        self.davSync = davSync
        self.googleAccessToken = googleAccessToken
        self.now = now
    }

    /// Statuses from which a sync may run.
    private static let syncableStatuses: Set<PIMSourceStatus> = [
        .ready, .syncing, .permissionLimited, .failed
    ]

    // MARK: - Queries

    /// Cached contacts for a source, sorted by display name. Offline
    /// browsing reads only this cache — it never issues provider
    /// requests.
    public func contacts(for sourceID: PIMSource.ID) async throws -> [PIMContact] {
        try await contactStore
            .contacts(for: sourceID)
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare(
                    $1.displayName
                ) == .orderedAscending
            }
    }

    /// Cached contacts belonging to one group/address book. CardDAV
    /// records match by collection; Google records match by group
    /// membership key.
    public func contacts(
        for sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) async throws -> [PIMContact] {
        let all = try await contacts(for: sourceID)
        return all.filter {
            $0.collectionID == collectionID
                || $0.groupKeys.contains(collectionID)
        }
    }

    /// Local search over cached fields — names, nicknames,
    /// organizations, emails and phones. Never contacts the provider
    /// (ADR-0072 sync rule 1).
    public func searchContacts(
        matching query: String,
        for sourceID: PIMSource.ID,
        limit: Int = 50
    ) async throws -> [PIMContact] {
        let needle = query.trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard !needle.isEmpty else { return [] }
        return try await contacts(for: sourceID)
            .filter { contact in
                contact.displayName.lowercased().contains(needle)
                    || contact.nickname?.lowercased().contains(needle) == true
                    || contact.givenName?.lowercased().contains(needle) == true
                    || contact.familyName?.lowercased().contains(needle) == true
                    || contact.organization?.lowercased().contains(needle) == true
                    || contact.emails.contains {
                        $0.value.lowercased().contains(needle)
                    }
                    || contact.phones.contains {
                        $0.value.lowercased().contains(needle)
                    }
            }
            .prefix(limit)
            .map { $0 }
    }

    /// The cached contact that carries this exact email address on a
    /// source, or nil. Case-insensitive, trimmed; reads the local cache
    /// only — never contacts the provider (#10).
    public func contact(
        matchingEmail email: String,
        for sourceID: PIMSource.ID
    ) async throws -> PIMContact? {
        let needle = email.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !needle.isEmpty else { return nil }
        return try await contacts(for: sourceID)
            .first { contact in
                contact.emails.contains {
                    $0.value.trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased() == needle
                }
            }
    }

    // MARK: - Sync

    /// Syncs a contacts source: the account-wide connections feed for
    /// Google, or each visible address book for CardDAV. Hidden
    /// collections keep their cached records but do not sync.
    @discardableResult
    public func syncNow(
        sourceID: PIMSource.ID
    ) async throws -> PIMContactSyncSummary {
        guard let source = try await coordinator.source(id: sourceID) else {
            throw PIMContactSyncServiceError.unknownSource
        }
        guard source.kind == .contacts else {
            throw PIMContactSyncServiceError.unsupportedKind
        }
        guard Self.syncableStatuses.contains(source.status) else {
            throw PIMContactSyncServiceError.sourceNotReady
        }
        _ = try? await coordinator.markStatus(.syncing, for: sourceID)

        var summary = PIMContactSyncSummary()
        if source.provider == .google {
            await syncGoogleSource(source, into: &summary)
        } else {
            await syncDAVCollections(source, into: &summary)
        }

        // An auth rejection already moved the source to
        // authenticationRequired — that state is more actionable than a
        // generic failure and must not be overwritten.
        if let current = try? await coordinator.source(id: sourceID),
           current.status == .authenticationRequired {
            return summary
        }

        if summary.failures.isEmpty {
            _ = try? await coordinator.markStatus(.ready, for: sourceID)
        } else if summary.syncedScopes == 0 {
            _ = try? await coordinator.markStatus(
                .failed,
                for: sourceID,
                detail: summary.failures.first?.message
            )
        } else {
            _ = try? await coordinator.markStatus(
                .ready,
                for: sourceID,
                detail: summary.failures.first?.message
            )
        }
        return summary
    }

    // MARK: - Google (account-wide)

    private func syncGoogleSource(
        _ source: PIMSource,
        into summary: inout PIMContactSyncSummary
    ) async {
        do {
            guard let accountID = source.linkedAccountID else {
                throw PIMContactSyncServiceError.missingCredential
            }
            guard let googleAccessToken else {
                throw PIMContactSyncServiceError
                    .googleAuthorizationUnavailable
            }
            let token = try await googleAccessToken(accountID)
            let cursor = try await cursorStore.cursor(
                for: source.id,
                scope: source.id
            )
            var result = try await runGoogleSync(
                source: source,
                cursorToken: cursor?.token,
                accessToken: token
            )
            if result.nextCursorToken == nil {
                result.nextCursorToken = cursor?.token
            }
            let counts = try await commit(
                result,
                for: source,
                scope: source.id,
                scopeFilter: { _ in true }
            )
            summary.syncedScopes += 1
            summary.upsertedContacts += counts.upserted
            summary.removedContacts += counts.removed
        } catch let error as PIMContactSyncError
            where error == .authenticationRequired {
            _ = try? await coordinator.markStatus(
                .authenticationRequired,
                for: source.id,
                detail: String(describing: error)
            )
            summary.failures.append(
                .init(scope: source.id, message: String(describing: error))
            )
        } catch {
            summary.failures.append(
                .init(scope: source.id, message: String(describing: error))
            )
        }
    }

    private func runGoogleSync(
        source: PIMSource,
        cursorToken: String?,
        accessToken: String
    ) async throws -> PIMContactSyncResult {
        do {
            return try await googleSync.syncContacts(
                source: source,
                cursorToken: cursorToken,
                accessToken: accessToken
            )
        } catch PIMContactSyncError.cursorExpired {
            guard cursorToken != nil else {
                throw PIMContactSyncError.cursorExpired
            }
            return try await googleSync.syncContacts(
                source: source,
                cursorToken: nil,
                accessToken: accessToken
            )
        }
    }

    // MARK: - CardDAV (per collection)

    private func syncDAVCollections(
        _ source: PIMSource,
        into summary: inout PIMContactSyncSummary
    ) async {
        let collections = await (try? collectionStore
            .collections(for: source.id)
            .filter(\.isVisible)) ?? []

        for collection in collections {
            do {
                let counts = try await syncDAVCollection(
                    collection,
                    source: source
                )
                summary.syncedScopes += 1
                summary.upsertedContacts += counts.upserted
                summary.removedContacts += counts.removed
            } catch let error as PIMContactSyncError
                where error == .authenticationRequired {
                // One credential serves every address book on the
                // source — a rejection cannot succeed for the rest.
                _ = try? await coordinator.markStatus(
                    .authenticationRequired,
                    for: source.id,
                    detail: String(describing: error)
                )
                summary.failures.append(
                    .init(
                        scope: collection.id,
                        message: String(describing: error)
                    )
                )
                return
            } catch {
                summary.failures.append(
                    .init(
                        scope: collection.id,
                        message: String(describing: error)
                    )
                )
            }
        }
    }

    private func syncDAVCollection(
        _ collection: PIMCollection,
        source: PIMSource
    ) async throws -> (upserted: Int, removed: Int) {
        guard let account = source.credentialAccount,
              let credential = try await credentials.credential(
                  for: account
              )
        else {
            throw PIMContactSyncServiceError.missingCredential
        }
        let cursor = try await cursorStore.cursor(
            for: source.id,
            scope: collection.id
        )
        let cached = try await contactStore.contacts(for: source.id)
            .filter { $0.collectionID == collection.id }
        let cachedVersions = Dictionary(
            uniqueKeysWithValues: cached.map {
                ($0.providerItemKey, $0.providerVersion ?? "")
            }
        )

        var result: PIMContactSyncResult
        do {
            result = try await davSync.syncCollection(
                collection,
                source: source,
                cursorToken: cursor?.token,
                cachedVersions: cachedVersions,
                credential: credential
            )
        } catch PIMContactSyncError.cursorExpired {
            guard cursor?.token != nil else {
                throw PIMContactSyncError.cursorExpired
            }
            result = try await davSync.syncCollection(
                collection,
                source: source,
                cursorToken: nil,
                cachedVersions: cachedVersions,
                credential: credential
            )
        }
        if result.nextCursorToken == nil {
            result.nextCursorToken = cursor?.token
        }
        return try await commit(
            result,
            for: source,
            scope: collection.id,
            scopeFilter: { $0.collectionID == collection.id }
        )
    }

    // MARK: - Commit

    /// Merges a scope result into the source's contact set and commits
    /// the generation before its cursor (ADR-0072 sync rule 1).
    private func commit(
        _ result: PIMContactSyncResult,
        for source: PIMSource,
        scope: String,
        scopeFilter: (PIMContact) -> Bool
    ) async throws -> (upserted: Int, removed: Int) {
        let all = try await contactStore.contacts(for: source.id)
        let inScope = all.filter(scopeFilter)
        let outOfScope = all.filter { !scopeFilter($0) }

        var mergedInScope: [PIMContact]
        if result.isFullSnapshot {
            let kept = Set(result.keptItemKeys)
            mergedInScope = result.contacts + inScope.filter {
                kept.contains($0.providerItemKey)
            }
        } else {
            let upsertedKeys = Set(result.contacts.map(\.providerItemKey))
            let removedKeys = Set(result.removedItemKeys)
            mergedInScope = inScope.filter {
                !removedKeys.contains($0.providerItemKey)
                    && !upsertedKeys.contains($0.providerItemKey)
            } + result.contacts
        }
        mergedInScope = droppingStaleHrefs(
            in: mergedInScope,
            incoming: result.contacts
        )

        try await contactStore.saveContacts(
            outOfScope + mergedInScope,
            for: source.id
        )
        try await cursorStore.saveCursor(
            PIMContactSyncCursor(
                scope: scope,
                token: result.nextCursorToken,
                completedAt: now()
            ),
            for: source.id
        )
        return (result.contacts.count, result.removedItemKeys.count)
    }

    /// Drops cached records an incoming item supersedes by identity:
    /// a server-side rename reports the item at a new href while the
    /// dead-href copy stays cached (see `PIMSyncItemIdentity`).
    private func droppingStaleHrefs(
        in merged: [PIMContact],
        incoming: [PIMContact]
    ) -> [PIMContact] {
        var liveKeys: [PIMSyncItemIdentity: Set<String>] = [:]
        for contact in incoming {
            guard let uid = contact.uid else { continue }
            liveKeys[
                PIMSyncItemIdentity(uid: uid),
                default: []
            ].insert(contact.providerItemKey)
        }
        guard !liveKeys.isEmpty else { return merged }
        return merged.filter { contact in
            guard let uid = contact.uid,
                  let keys = liveKeys[PIMSyncItemIdentity(uid: uid)]
            else { return true }
            return keys.contains(contact.providerItemKey)
        }
    }
}
