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

import BrevBackend
import BrevCalendar
import Foundation
import Observation

/// View-facing owner of the PIM source list in Settings (ADR-0072).
///
/// The coordinator owns lifecycle truth and serializes transitions; this
/// model holds the snapshot the section renders, forwards user actions, and
/// maps failures to displayable text. Views never write source state —
/// every mutation goes through the coordinator and the list reloads.
@Observable
@MainActor
public final class PIMSourceSettingsModel {
    /// All registered sources in stable order.
    public private(set) var sources: [PIMSource] = []
    /// Whether the initial list load is in flight.
    public private(set) var isLoading = false
    /// Source running a lifecycle action; drives the per-row spinner and
    /// disables duplicate actions on that row.
    public private(set) var pendingSourceID: PIMSource.ID?
    /// Whether a connect attempt is in flight; disables sheet submission.
    public private(set) var isConnecting = false
    /// Last actionable failure, surfaced inline by the section.
    public private(set) var lastError: String?
    /// Google account running a feature authorization; drives that row's
    /// spinner and disables its buttons.
    public private(set) var pendingGoogleAccountID: BrevAccount.ID?

    private let coordinator: PIMSourceCoordinator
    /// Discovered collections per source, loaded alongside the snapshot.
    public private(set) var collectionsBySource:
        [PIMSource.ID: [PIMCollection]] = [:]
    /// Collection discovery service; nil in sessions without PIM wiring.
    private let collectionService: PIMCollectionService?
    /// Session-provided Google enablement (fresh authorization + grant
    /// swap + source registration). Nil in sessions without Google wiring —
    /// the section then shows the feature as not available yet.
    private let googleFeatureHandler:
        ((BrevAccount.ID, PIMSourceKind) async throws -> Void)?

    /// - Parameters:
    ///   - coordinator: The serial lifecycle owner for all sources.
    ///   - collectionService: Discovers and caches collections per source.
    ///   - googleFeatureHandler: Enables a PIM feature on a Google mail
    ///     account through feature-triggered reauthorization.
    public init(
        coordinator: PIMSourceCoordinator,
        collectionService: PIMCollectionService? = nil,
        googleFeatureHandler: ((BrevAccount.ID, PIMSourceKind) async throws -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.collectionService = collectionService
        self.googleFeatureHandler = googleFeatureHandler
    }

    /// Whether Google feature enablement can run in this session.
    public var canEnableGoogleFeatures: Bool {
        googleFeatureHandler != nil
    }

    /// Whether collection discovery can run in this session.
    public var canManageCollections: Bool {
        collectionService != nil
    }

    // MARK: - Loading

    /// Refreshes the source snapshot from the coordinator.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sources = try await coordinator.allSources()
            await loadCollections()
        } catch {
            lastError = Self.errorText(for: error)
        }
    }

    private func loadCollections() async {
        guard let collectionService else {
            collectionsBySource = [:]
            return
        }
        var map: [PIMSource.ID: [PIMCollection]] = [:]
        for source in sources {
            // A store read failure must not blank the source list — the
            // source row still renders, its collections just stay empty.
            await map[source.id] =
                (try? collectionService.collections(for: source.id)) ?? []
        }
        collectionsBySource = map
    }

    // MARK: - Collections

    /// Re-discovers a source's collections from the provider. Explicitly
    /// user-initiated; failures surface inline and keep the cached list.
    public func refreshCollections(sourceID: PIMSource.ID) async {
        guard let collectionService else { return }
        pendingSourceID = sourceID
        lastError = nil
        defer { pendingSourceID = nil }
        do {
            _ = try await collectionService.refreshCollections(for: sourceID)
            await load()
        } catch {
            lastError = Self.errorText(for: error)
            await load()
        }
    }

    /// Toggles whether a collection participates in sync and browsing.
    /// Local-only; never contacts the provider.
    public func setCollectionVisible(
        _ isVisible: Bool,
        collectionID: PIMCollection.ID,
        sourceID: PIMSource.ID
    ) async {
        guard let collectionService else { return }
        do {
            try await collectionService.setVisible(
                isVisible,
                collectionID: collectionID,
                sourceID: sourceID
            )
            collectionsBySource[sourceID] =
                try await collectionService.collections(for: sourceID)
        } catch {
            lastError = Self.errorText(for: error)
        }
    }

    /// Best-effort discovery right after a connect or feature enablement —
    /// the user's action already opted in, so this adds no new consent
    /// boundary. Failures surface inline without failing the connect.
    private func discoverAfterConnect(sourceID: PIMSource.ID) async {
        guard let collectionService else { return }
        do {
            _ = try await collectionService.refreshCollections(for: sourceID)
        } catch {
            lastError = Self.errorText(for: error)
        }
    }

    // MARK: - Connect and reconnect

    /// Validates and connects a DAV source. Returns true when the source
    /// was stored so the sheet can dismiss; on failure the form stays open
    /// and the actionable error is shown inline.
    @discardableResult
    public func connectDAV(_ form: PIMDAVConnectForm) async -> Bool {
        guard let request = form.makeRequest() else { return false }
        isConnecting = true
        lastError = nil
        defer { isConnecting = false }
        do {
            let source = try await coordinator.connectDAVSource(
                kind: request.kind,
                endpoint: request.endpoint,
                displayName: request.displayName,
                credential: request.credential
            )
            await discoverAfterConnect(sourceID: source.id)
            await load()
            return true
        } catch {
            lastError = Self.errorText(for: error)
            return false
        }
    }

    /// Revalidates a source with a replacement credential. A rejected
    /// candidate leaves both the stored credential and the error state
    /// untouched.
    @discardableResult
    public func reconnect(
        sourceID: PIMSource.ID,
        form: PIMDAVConnectForm
    ) async -> Bool {
        guard let credential = form.resolvedCredential() else { return false }
        pendingSourceID = sourceID
        lastError = nil
        defer { pendingSourceID = nil }
        do {
            _ = try await coordinator.reconnect(
                sourceID: sourceID,
                credential: credential
            )
            await load()
            return true
        } catch {
            lastError = Self.errorText(for: error)
            return false
        }
    }

    /// Enables a PIM feature on a Google mail account. Returns true when
    /// the feature was enabled and the list reloaded; a declined or
    /// partial authorization surfaces an inline error and changes nothing.
    @discardableResult
    public func enableGoogleFeature(
        accountID: BrevAccount.ID,
        kind: PIMSourceKind
    ) async -> Bool {
        guard let googleFeatureHandler else { return false }
        pendingGoogleAccountID = accountID
        lastError = nil
        defer { pendingGoogleAccountID = nil }
        do {
            try await googleFeatureHandler(accountID, kind)
            if let source = try await coordinator.googleSource(
                accountID: accountID,
                kind: kind
            ) {
                await discoverAfterConnect(sourceID: source.id)
            }
            await load()
            return true
        } catch {
            lastError = Self.errorText(for: error)
            return false
        }
    }

    // MARK: - Lifecycle actions

    /// Explicit background-sync opt-in or pause for a source.
    public func setSyncEnabled(_ enabled: Bool, for sourceID: PIMSource.ID) async {
        await perform(sourceID) {
            try await $0.setSyncEnabled(enabled, for: sourceID)
        }
    }

    /// Disconnects a source; cached content stays readable with warnings.
    public func disconnect(sourceID: PIMSource.ID) async {
        await perform(sourceID) {
            try await $0.disconnect(sourceID: sourceID)
        }
    }

    /// Removes a source. Sync cursors and unsent drafts are always
    /// deleted; the readable cache follows the user's choice. Never
    /// contacts the provider.
    public func remove(
        sourceID: PIMSource.ID,
        deleteCachedContent: Bool
    ) async {
        pendingSourceID = sourceID
        lastError = nil
        defer { pendingSourceID = nil }
        do {
            try await coordinator.removeSource(
                id: sourceID,
                deleteCachedContent: deleteCachedContent
            )
            await load()
        } catch {
            lastError = Self.errorText(for: error)
        }
    }

    // MARK: - Internals

    private func perform(
        _ sourceID: PIMSource.ID,
        _ action: (PIMSourceCoordinator) async throws -> PIMSource
    ) async {
        pendingSourceID = sourceID
        lastError = nil
        defer { pendingSourceID = nil }
        do {
            _ = try await action(coordinator)
            await load()
        } catch {
            lastError = Self.errorText(for: error)
        }
    }

    static func errorText(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
