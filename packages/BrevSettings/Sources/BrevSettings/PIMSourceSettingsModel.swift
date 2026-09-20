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

    private let coordinator: PIMSourceCoordinator

    /// - Parameter coordinator: The serial lifecycle owner for all sources.
    public init(coordinator: PIMSourceCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Loading

    /// Refreshes the source snapshot from the coordinator.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sources = try await coordinator.allSources()
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
            _ = try await coordinator.connectDAVSource(
                kind: request.kind,
                endpoint: request.endpoint,
                displayName: request.displayName,
                credential: request.credential
            )
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
