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
    /// Cached event counts per calendar source, for the row's status text.
    public private(set) var eventCountsBySource: [PIMSource.ID: Int] = [:]
    /// Event sync service; nil in sessions without PIM sync wiring.
    private let eventSyncService: PIMEventSyncService?
    /// Cached contact counts per contacts source, for the row's status
    /// text.
    public private(set) var contactCountsBySource: [PIMSource.ID: Int] = [:]
    /// Contact sync service; nil in sessions without PIM sync wiring.
    private let contactSyncService: PIMContactSyncService?
    /// Syncs and caches tasks per tasks source (#12).
    private let taskSyncService: PIMTaskSyncService?
    /// Session-provided Google enablement (fresh authorization + grant
    /// swap + source registration). Nil in sessions without Google wiring —
    /// the section then shows the feature as not available yet.
    private let googleFeatureHandler:
        ((BrevAccount.ID, PIMSourceKind) async throws -> Void)?
    /// Session-provided Google write enablement: re-authorizes the
    /// account with the write scope added, then flips the source
    /// capability. Nil in sessions without Google wiring.
    private let googleWriteFeatureHandler:
        ((BrevAccount.ID, PIMSourceKind) async throws -> Void)?

    /// - Parameters:
    ///   - coordinator: The serial lifecycle owner for all sources.
    ///   - collectionService: Discovers and caches collections per source.
    ///   - eventSyncService: Syncs and caches events per calendar source.
    ///   - contactSyncService: Syncs and caches contacts per contacts
    ///     source.
    ///   - googleFeatureHandler: Enables a PIM feature on a Google mail
    ///     account through feature-triggered reauthorization.
    ///   - googleWriteFeatureHandler: Grants editing on a connected
    ///     Google source through write-scope reauthorization (#7).
    public init(
        coordinator: PIMSourceCoordinator,
        collectionService: PIMCollectionService? = nil,
        eventSyncService: PIMEventSyncService? = nil,
        contactSyncService: PIMContactSyncService? = nil,
        taskSyncService: PIMTaskSyncService? = nil,
        googleFeatureHandler: ((BrevAccount.ID, PIMSourceKind) async throws -> Void)? = nil,
        googleWriteFeatureHandler: ((BrevAccount.ID, PIMSourceKind) async throws -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.collectionService = collectionService
        self.eventSyncService = eventSyncService
        self.contactSyncService = contactSyncService
        self.taskSyncService = taskSyncService
        self.googleFeatureHandler = googleFeatureHandler
        self.googleWriteFeatureHandler = googleWriteFeatureHandler
    }

    /// Whether Google feature enablement can run in this session.
    public var canEnableGoogleFeatures: Bool {
        googleFeatureHandler != nil
    }

    /// Whether collection discovery can run in this session.
    public var canManageCollections: Bool {
        collectionService != nil
    }

    /// Whether calendar event sync can run in this session.
    public var canSyncEvents: Bool {
        eventSyncService != nil
    }

    /// Whether contacts sync can run in this session.
    public var canSyncContacts: Bool {
        contactSyncService != nil
    }

    /// Whether a sync service exists for this source's kind in this
    /// session.
    public func canSyncNow(sourceID: PIMSource.ID) -> Bool {
        guard let kind = sources.first(where: { $0.id == sourceID })?.kind
        else { return false }
        switch kind {
        case .calendar: return eventSyncService != nil
        case .contacts: return contactSyncService != nil
        case .tasks: return taskSyncService != nil
        }
    }

    // MARK: - Loading

    /// Refreshes the source snapshot from the coordinator.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sources = try await coordinator.allSources()
            await loadCollections()
            await loadEventCounts()
            await loadContactCounts()
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

    private func loadEventCounts() async {
        guard let eventSyncService else {
            eventCountsBySource = [:]
            return
        }
        var map: [PIMSource.ID: Int] = [:]
        for source in sources where source.kind == .calendar {
            // A store read failure must not blank the row — the count
            // simply stays absent.
            if let events = try? await eventSyncService.events(
                for: source.id
            ) {
                map[source.id] = events.count
            }
        }
        eventCountsBySource = map
    }

    private func loadContactCounts() async {
        guard let contactSyncService else {
            contactCountsBySource = [:]
            return
        }
        var map: [PIMSource.ID: Int] = [:]
        for source in sources where source.kind == .contacts {
            // A store read failure must not blank the row — the count
            // simply stays absent.
            if let contacts = try? await contactSyncService.contacts(
                for: source.id
            ) {
                map[source.id] = contacts.count
            }
        }
        contactCountsBySource = map
    }

    // MARK: - Item sync

    /// Syncs a source's items now — events for calendar sources, contacts
    /// for contacts sources; the account-wide connections feed for Google
    /// contacts, each visible collection otherwise. Explicitly
    /// user-initiated; failures surface inline and keep prior snapshots.
    public func syncNow(sourceID: PIMSource.ID) async {
        guard let kind = sources.first(where: { $0.id == sourceID })?.kind
        else { return }
        pendingSourceID = sourceID
        lastError = nil
        defer { pendingSourceID = nil }
        do {
            let firstFailure: String?
            switch kind {
            case .calendar:
                guard let eventSyncService else { return }
                firstFailure = try await eventSyncService.syncNow(
                    sourceID: sourceID
                ).failures.first?.message
            case .contacts:
                guard let contactSyncService else { return }
                firstFailure = try await contactSyncService.syncNow(
                    sourceID: sourceID
                ).failures.first?.message
            case .tasks:
                guard let taskSyncService else { return }
                firstFailure = try await taskSyncService.syncNow(
                    sourceID: sourceID
                ).failures.first?.message
            }
            if let firstFailure {
                lastError = firstFailure
            }
            await load()
        } catch {
            lastError = Self.errorText(for: error)
            await load()
        }
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
        if enabled {
            // Enabling sync is the user's gesture — kick one immediate
            // pass so the cache fills without waiting for scheduling.
            await syncNow(sourceID: sourceID)
        }
    }

    /// Explicit editing opt-in or lock for a source (#7).
    ///
    /// Google sources re-authorize first — the write scope must be
    /// granted before the capability flips, so a declined sheet leaves
    /// the source read-only. DAV credentials already carry full access,
    /// so their toggle is a local opt-in only. Disabling is always
    /// local: the provider grant stays but Brev stops issuing writes.
    public func setWriteEnabled(_ enabled: Bool, for sourceID: PIMSource.ID) async {
        guard let source = sources.first(where: { $0.id == sourceID })
        else { return }
        if enabled, source.provider == .google {
            guard let accountID = source.linkedAccountID,
                  let googleWriteFeatureHandler
            else {
                lastError = String(
                    localized:
                    "Editing is unavailable in this session.",
                    bundle: .module
                )
                return
            }
            pendingSourceID = sourceID
            lastError = nil
            defer { pendingSourceID = nil }
            do {
                // The handler re-authorizes and flips the capability
                // atomically — a thrown error means nothing changed.
                try await googleWriteFeatureHandler(accountID, source.kind)
                await load()
            } catch {
                lastError = Self.errorText(for: error)
            }
            return
        }
        await perform(sourceID) {
            try await $0.setWriteEnabled(enabled, for: sourceID)
        }
    }

    /// Whether the source offers an editing toggle — connected Google
    /// or DAV sources only (CalDAV calendars, CardDAV address books);
    /// disconnected or auth-failed rows stay inert.
    public func canToggleWrite(sourceID: PIMSource.ID) -> Bool {
        guard let source = sources.first(where: { $0.id == sourceID })
        else { return false }
        let connected: Set<PIMSourceStatus> = [
            .ready, .syncing, .permissionLimited,
        ]
        guard connected.contains(source.status)
        else { return false }
        switch source.kind {
        case .calendar:
            return source.provider == .google
                || source.provider == .calDAV
        case .contacts:
            return source.provider == .google
                || source.provider == .cardDAV
        case .tasks:
            return source.provider == .google
                || source.provider == .calDAV
        }
    }

    /// Whether editing is currently enabled on a source.
    public func isWriteEnabled(sourceID: PIMSource.ID) -> Bool {
        sources.first(where: { $0.id == sourceID })?
            .enabledCapabilities.contains(.write) ?? false
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
