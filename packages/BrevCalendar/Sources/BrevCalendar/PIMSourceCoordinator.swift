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

/// Serial owner of PIM source lifecycle transitions (ADR-0072).
///
/// All state changes — connect, reconnect, sync opt-in, disable, remove —
/// pass through this actor so a source can never be half-connected or lose
/// its credential to a racing transition. Credentials are staged and
/// validated before they replace a working reference: a rejected candidate
/// never overwrites the credential that still works.
public actor PIMSourceCoordinator {
    private let store: any PIMSourceStore
    private let credentials: any CalDAVCredentialStore
    private let localData: any PIMSourceLocalDataStore
    private let davClient: PIMDAVClient
    private let now: () -> Date

    private var sources: [PIMSource.ID: PIMSource]?

    public init(
        store: any PIMSourceStore,
        credentials: any CalDAVCredentialStore,
        localData: any PIMSourceLocalDataStore,
        davClient: PIMDAVClient = PIMDAVClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.credentials = credentials
        self.localData = localData
        self.davClient = davClient
        self.now = now
    }

    // MARK: - Queries

    /// All registered sources in stable order.
    public func allSources() async throws -> [PIMSource] {
        let records = try await loadSources()
        return records.values.sorted { $0.createdAt < $1.createdAt }
    }

    /// One source by ID.
    public func source(id: PIMSource.ID) async throws -> PIMSource? {
        try await loadSources()[id]
    }

    /// Sources attached to a mail account. Account removal enumerates these
    /// so linked sources are removed or explicitly retained instead of
    /// silently orphaned (ADR-0072).
    public func linkedSources(accountID: String) async throws -> [PIMSource] {
        try await allSources().filter { $0.linkedAccountID == accountID }
    }

    /// The Google source of a kind already enabled on a mail account, if
    /// any. Enablement is idempotent per account and kind.
    public func googleSource(
        accountID: String,
        kind: PIMSourceKind
    ) async throws -> PIMSource? {
        try await allSources().first {
            $0.provider == .google
                && $0.kind == kind
                && $0.linkedAccountID == accountID
        }
    }

    // MARK: - Connect

    /// Connects a standards-based DAV source: validates the endpoint and
    /// credential, stages the credential in Keychain, then persists the
    /// record as ready. A failed attempt creates no record and stores no
    /// credential. Background sync stays off — enablement is a separate
    /// explicit opt-in.
    @discardableResult
    public func connectDAVSource(
        kind: PIMSourceKind,
        endpoint: PIMDAVEndpoint,
        displayName: String,
        credential: CalDAVCredential,
        linkedAccountID: String? = nil
    ) async throws -> PIMSource {
        let provider: PIMSourceProvider = kind == .calendar ? .calDAV : .cardDAV
        let validation = try await davClient.validate(
            endpoint: endpoint,
            kind: kind,
            credential: credential
        )

        let timestamp = now()
        var source = PIMSource(
            id: "pim-\(UUID().uuidString.lowercased())",
            kind: kind,
            provider: provider,
            linkedAccountID: linkedAccountID,
            displayName: displayName,
            endpointURL: validation.endpointURL,
            principalURL: validation.principalURL,
            credentialAccount: nil,
            enabledCapabilities: [.read],
            syncEnabled: false,
            status: .ready,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let credentialAccount = Self.credentialAccount(for: source.id)

        // Stage the credential before the record references it. If the
        // record write fails, the staged credential is rolled back so no
        // orphaned secret remains.
        try await credentials.setCredential(credential, for: credentialAccount)
        do {
            source.credentialAccount = credentialAccount
            try await store.save(source)
        } catch {
            try? await credentials.deleteCredential(for: credentialAccount)
            throw error
        }
        sources?[source.id] = source
        return source
    }

    // MARK: - Google sources

    /// Registers a Google PIM source on a mail account whose shared grant
    /// already covers the feature (ADR-0072).
    ///
    /// No credential is staged here: the source rides the account's OAuth
    /// grant in the token store, so credentialAccount stays nil and removal
    /// can never delete the credential mail still uses. Enablement is
    /// idempotent — a second call for the same account and kind returns the
    /// existing record. The caller authorizes first; this method only
    /// records the enabled feature.
    @discardableResult
    public func connectGoogleSource(
        kind: PIMSourceKind,
        accountID: String,
        displayName: String
    ) async throws -> PIMSource {
        if let existing = try await googleSource(accountID: accountID, kind: kind) {
            return existing
        }
        let timestamp = now()
        let source = PIMSource(
            id: "pim-\(UUID().uuidString.lowercased())",
            kind: kind,
            provider: .google,
            linkedAccountID: accountID,
            displayName: displayName,
            credentialAccount: nil,
            enabledCapabilities: [.read],
            syncEnabled: false,
            status: .ready,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        try await store.save(source)
        sources?[source.id] = source
        return source
    }

    // MARK: - Reconnect

    /// Revalidates a source with a replacement credential. The new
    /// credential is staged and verified first; only a successful
    /// validation replaces the stored reference and clears
    /// authentication-required. A rejected candidate leaves the existing
    /// credential untouched.
    @discardableResult
    public func reconnect(
        sourceID: PIMSource.ID,
        credential: CalDAVCredential
    ) async throws -> PIMSource {
        var source = try await requireSource(sourceID)
        guard let endpoint = source.endpointURL else {
            throw PIMDAVConnectError.invalidEndpoint
        }
        let validation = try await davClient.validate(
            endpoint: .manual(endpoint),
            kind: source.kind,
            credential: credential
        )
        guard let credentialAccount = source.credentialAccount else {
            throw PIMSourceCoordinatorError.missingCredentialReference
        }
        try await credentials.setCredential(credential, for: credentialAccount)
        source.principalURL = validation.principalURL ?? source.principalURL
        source.status = .ready
        source.statusDetail = nil
        source.updatedAt = now()
        try await store.save(source)
        sources?[source.id] = source
        return source
    }

    // MARK: - Status transitions

    /// Explicit background-sync opt-in or pause. Connecting alone never
    /// enables sync; disabling pauses without disconnecting the source.
    @discardableResult
    public func setSyncEnabled(
        _ enabled: Bool,
        for sourceID: PIMSource.ID
    ) async throws -> PIMSource {
        var source = try await requireSource(sourceID)
        source.syncEnabled = enabled
        source.updatedAt = now()
        try await store.save(source)
        sources?[source.id] = source
        return source
    }

    /// Explicit editing opt-in or lock (#7). The `.write` capability
    /// gates every mutation path; disabling is local-only and never
    /// touches the provider grant — a granted Google scope stays granted
    /// but unused, a DAV credential keeps its server-side privileges.
    /// Enabling is also local-only here: Google sources re-authorize
    /// for the write scope *before* calling this (the session owns that
    /// ordering), so the capability never claims a grant the account
    /// does not hold.
    @discardableResult
    public func setWriteEnabled(
        _ enabled: Bool,
        for sourceID: PIMSource.ID
    ) async throws -> PIMSource {
        var source = try await requireSource(sourceID)
        if enabled {
            source.enabledCapabilities.insert(.write)
        } else {
            source.enabledCapabilities.remove(.write)
        }
        source.updatedAt = now()
        try await store.save(source)
        sources?[source.id] = source
        return source
    }

    /// Disconnects a source while keeping its credential and cache. Cached
    /// content remains readable with freshness warnings until removal.
    @discardableResult
    public func disconnect(sourceID: PIMSource.ID) async throws -> PIMSource {
        try await transition(sourceID, to: .disconnected, detail: nil)
    }

    /// Records an adapter-reported state: sync in flight, partial grants,
    /// expired credentials, or a failed operation. Only adapters and the
    /// coordinator itself should call this; views never write status.
    @discardableResult
    public func markStatus(
        _ status: PIMSourceStatus,
        for sourceID: PIMSource.ID,
        detail: String? = nil
    ) async throws -> PIMSource {
        try await transition(sourceID, to: status, detail: detail)
    }

    // MARK: - Removal

    /// Removes a source. Always deletes the credential reference, sync
    /// cursors and unsent drafts; deletes the readable cache only when
    /// requested, otherwise marks it disconnected and read-only. Never
    /// contacts the provider and never deletes provider data.
    public func removeSource(
        id sourceID: PIMSource.ID,
        deleteCachedContent: Bool
    ) async throws {
        let source = try await requireSource(sourceID)
        // Mutable data goes first: a retained cache must never resume sync
        // or submit writes for a removed source.
        try await localData.deleteSyncAndDraftData(for: sourceID)
        if let credentialAccount = source.credentialAccount {
            try await credentials.deleteCredential(for: credentialAccount)
        }
        if deleteCachedContent {
            try await localData.deleteCachedContent(for: sourceID)
        } else {
            try await localData.markCacheDisconnected(for: sourceID)
        }
        try await store.deleteSource(id: sourceID)
        sources?[sourceID] = nil
    }

    // MARK: - Internals

    private func loadSources() async throws -> [PIMSource.ID: PIMSource] {
        if let sources { return sources }
        let records = try await store.allSources()
        let mapped = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        sources = mapped
        return mapped
    }

    private func requireSource(_ id: PIMSource.ID) async throws -> PIMSource {
        guard let source = try await loadSources()[id] else {
            throw PIMSourceCoordinatorError.unknownSource
        }
        return source
    }

    private func transition(
        _ id: PIMSource.ID,
        to status: PIMSourceStatus,
        detail: String?
    ) async throws -> PIMSource {
        var source = try await requireSource(id)
        source.status = status
        source.statusDetail = detail
        source.updatedAt = now()
        try await store.save(source)
        sources?[id] = source
        return source
    }

    /// Keychain account key for a source's credential. Namespaced so a
    /// source credential can never collide with a mail or CalDAV
    /// write-target entry.
    static func credentialAccount(for sourceID: PIMSource.ID) -> String {
        "pim-source-\(sourceID)"
    }
}

public enum PIMSourceCoordinatorError: Error, Sendable {
    /// No source exists for the requested ID.
    case unknownSource
    /// The source record lost its credential reference; it must be
    /// reconnected rather than reused.
    case missingCredentialReference
}
