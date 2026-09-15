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
import Foundation

/// Reader-side state for cross-folder conversation lookup (ADR-0074).
///
/// Owns one lookup at a time: a new anchor, source switch, or view teardown
/// cancels the previous task and rejects its stale updates via a generation
/// counter. Cached snapshots never touch the network. Remote discovery runs
/// only after the account's related-mail consent — either the session grant
/// recorded by the explicit **Load related mail** action or the persistent
/// per-account preference — and only when the backend advertises the
/// `.relatedConversationLoading` capability.
@MainActor
@Observable
final class RelatedConversationController {
    /// Awaits the current lookup task; used by tests to observe settled state.
    func awaitSettled() async {
        await task?.value
    }

    /// The most recent snapshot around the current anchor, cached or remote.
    private(set) var snapshot: ConversationSnapshot?
    /// Whether a remote related-header request is in flight.
    private(set) var isLoadingRemote = false
    /// Whether the last remote attempt failed; drives the Retry affordance.
    private(set) var remoteLoadDidFail = false
    /// Whether the selected backend offers remote related-header loading.
    private(set) var canLoadRelated = false
    /// Whether Spam and Trash folders are included in the current lookup.
    private(set) var includesSpamAndTrash = false
    /// Whether a remote attempt has already run for the current anchor.
    private(set) var remoteLoadAttempted = false

    private var anchor: ConversationMember?
    private var backend: (any MailBackend)?
    private var task: Task<Void, Never>?
    private var generation = 0
    private let consentStore: RelatedConversationConsentStore

    init(consentStore: RelatedConversationConsentStore = .shared) {
        self.consentStore = consentStore
    }

    /// Re-evaluates the conversation around a newly selected header.
    ///
    /// Cancels in-flight remote work, resolves the cached snapshot, then
    /// triggers remote discovery automatically only when the account's
    /// persistent auto-load consent is enabled.
    func updateAnchor(
        header: MessageHeader?,
        sourceID: MailSourceID?,
        backend: any MailBackend
    ) {
        task?.cancel()
        generation += 1
        let current = generation
        snapshot = nil
        isLoadingRemote = false
        remoteLoadDidFail = false
        remoteLoadAttempted = false
        includesSpamAndTrash = false
        self.backend = backend
        canLoadRelated = backend.extendedCapabilities.contains(.relatedConversationLoading)
            && backend.extensionService(RelatedConversationLoading.self) != nil
        guard let header, let sourceID else {
            anchor = nil
            return
        }
        let member = ConversationMember(sourceID: sourceID, header: header)
        anchor = member
        let hasCachedProvider = backend.extendedCapabilities.contains(.cachedConversations)
            && backend.extensionService(CachedConversationProviding.self) != nil

        task = Task { [weak self] in
            guard let self else { return }
            if hasCachedProvider {
                await resolveCached(generation: current)
            }
            guard !Task.isCancelled, generation == current else { return }
            let accountID = member.sourceID.accountID
            if consentStore.isAutoLoadEnabled(accountID: accountID) {
                await loadRemote(generation: current)
            }
        }
    }

    /// The explicit reader action: records a session-scoped consent grant and
    /// runs remote discovery once. Never persists a preference by itself.
    func loadRelatedMail() {
        guard let anchor else { return }
        consentStore.grantForSession(accountID: anchor.sourceID.accountID)
        startRemoteLoad()
    }

    /// Retries a failed or partial remote lookup. If no consent surface
    /// remains, the backend rejects with `.consentRequired` and the bar keeps
    /// showing the explicit action.
    func retry() {
        startRemoteLoad()
    }

    /// Re-runs the lookup including Spam and Trash folders.
    func includeSpamAndTrash() {
        includesSpamAndTrash = true
        guard let anchor else { return }
        // A new generation rejects updates still in flight from the
        // narrower scope.
        generation += 1
        let current = generation
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            await resolveCached(generation: current)
            guard !Task.isCancelled, generation == current else { return }
            let consented = await consentStore.isRelatedConversationConsented(
                accountID: anchor.sourceID.accountID
            )
            if consented {
                await loadRemote(generation: current)
            }
        }
    }

    /// Snapshot-aware thread headers for the reader: the snapshot supplies
    /// cross-folder members; already-loaded list headers win on ID conflicts
    /// because they carry richer display metadata (snippets, flags).
    func mergedThreadHeaders(loaded: [MessageHeader]) -> [MessageHeader] {
        guard let snapshot else { return loaded }
        var byID = Dictionary(uniqueKeysWithValues: snapshot.members.map { ($0.header.id, $0.header) })
        for header in loaded {
            byID[header.id] = header
        }
        return byID.values.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.folderID != $1.folderID { return $0.folderID < $1.folderID }
            return $0.id < $1.id
        }
    }

    /// Whether the anchor's folder is excluded from the current scope, so the
    /// reader can label instead of silently dropping that context.
    var anchorIsInExcludedFolder: Bool {
        guard let anchor, let snapshot else { return false }
        return snapshot.excludedFolderIDs.contains(anchor.header.folderID)
    }

    private func startRemoteLoad() {
        guard anchor != nil, backend != nil else { return }
        generation += 1
        let current = generation
        task?.cancel()
        remoteLoadAttempted = true
        task = Task { [weak self] in
            await self?.loadRemote(generation: current)
        }
    }

    private func resolveCached(generation current: Int) async {
        guard let anchor, let backend,
              let provider = backend.extensionService(CachedConversationProviding.self)
        else { return }
        do {
            let resolved = try await provider.cachedConversation(
                around: anchor,
                includeSpamAndTrash: includesSpamAndTrash
            )
            guard generation == current, !Task.isCancelled else { return }
            snapshot = resolved
        } catch {
            // Cached lookup is best-effort; the reader falls back to the
            // loaded-folder thread when the index cannot answer.
        }
    }

    private func loadRemote(generation current: Int) async {
        guard let anchor, let backend,
              let loader = backend.extensionService(RelatedConversationLoading.self)
        else { return }
        isLoadingRemote = true
        remoteLoadDidFail = false
        defer {
            if generation == current {
                isLoadingRemote = false
            }
        }
        do {
            let resolved = try await loader.loadRelatedConversation(
                around: anchor,
                includeSpamAndTrash: includesSpamAndTrash,
                continuation: nil
            ) { [weak self] update in
                await self?.applyRemoteUpdate(update, generation: current)
            }
            guard generation == current, !Task.isCancelled else { return }
            snapshot = resolved
        } catch is CancellationError {
            // Replaced by a newer anchor; state already moved on.
        } catch {
            guard generation == current else { return }
            remoteLoadDidFail = true
        }
    }

    /// Applies a streaming snapshot only while its request generation is
    /// still current — a stale lookup can never overwrite a newer anchor.
    private func applyRemoteUpdate(_ update: ConversationSnapshot, generation current: Int) {
        guard generation == current else { return }
        snapshot = update
    }
}
