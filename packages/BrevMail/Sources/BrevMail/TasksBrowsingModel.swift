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

/// Browsing model behind the Tasks surface (ADR-0072, #12).
///
/// Reads the synced cache only — `load()` never issues provider
/// requests, so an offline launch renders the last complete snapshot.
/// Provider traffic happens solely inside `syncNow`, which the
/// user triggers explicitly. One unreadable source cache never blanks
/// the others; the failure surfaces inline while healthy sources keep
/// rendering.
@Observable
@MainActor
public final class TasksBrowsingModel {
    /// One task list bucket in the list view — a synced collection.
    public struct ListSection: Identifiable, Hashable, Sendable {
        public let id: String
        /// The collection's display name, or the source name when the
        /// collection record is missing.
        public let title: String
        public var tasks: [PIMTask]

        public init(id: String, title: String, tasks: [PIMTask]) {
            self.id = id
            self.title = title
            self.tasks = tasks
        }
    }

    // MARK: - State

    /// Tasks sources known to the coordinator, in coordinator order.
    public private(set) var sources: [PIMSource] = []
    /// Discovered collections (task lists) per source; empty when
    /// discovery never ran.
    public private(set) var collectionsBySource:
        [PIMSource.ID: [PIMCollection]] = [:]
    /// All cached tasks across tasks sources.
    public private(set) var tasks: [PIMTask] = []
    public private(set) var isLoading = false
    /// Inline error text for the last failed load or sync pass.
    public private(set) var lastError: String?
    /// Sources currently running a Sync Now pass.
    public private(set) var syncingSourceIDs: Set<PIMSource.ID> = []

    /// Local-only query over the cached task fields.
    public var searchText = ""
    /// Task-list filter — nil shows every visible collection.
    public var selectedCollectionID: PIMCollection.ID?
    /// Selection shared between the list and the detail pane.
    public var selectedTaskID: PIMTask.ID?
    /// Whether completed/cancelled tasks render in the list.
    public var showsCompleted = true
    /// One-line notice when a brev://task deep link names a record
    /// that is no longer in the cache.
    public private(set) var deepLinkNotice: String?

    private let coordinator: PIMSourceCoordinator?
    private let collectionService: PIMCollectionService?
    private let taskSyncService: PIMTaskSyncService?
    private let now: () -> Date
    /// Whether load() finished at least once — deep links ensure the
    /// cache is loaded before they reveal so a cold window cannot
    /// report a miss on data it never read.
    private var didLoad = false

    /// - Parameters:
    ///   - coordinator: Source registry; nil in sessions without PIM.
    ///   - collectionService: Collection cache for visibility + lists.
    ///   - taskSyncService: Task cache and Sync Now owner.
    ///   - now: Clock, injected for tests.
    public init(
        coordinator: PIMSourceCoordinator? = nil,
        collectionService: PIMCollectionService? = nil,
        taskSyncService: PIMTaskSyncService? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.coordinator = coordinator
        self.collectionService = collectionService
        self.taskSyncService = taskSyncService
        self.now = now
    }

    // MARK: - Derived state

    /// Tasks the list shows: hidden collections excluded, the list
    /// filter and search applied, completed entries dropped when the
    /// toggle is off. Provider ordering (position) is preserved by the
    /// sync service's sort; unordered tasks fall back to title.
    public var visibleTasks: [PIMTask] {
        let hiddenCollectionIDs = Set(
            collectionsBySource.values.flatMap { $0 }
                .filter { !$0.isVisible }
                .map(\.id)
        )
        return tasks.filter { task in
            if hiddenCollectionIDs.contains(task.collectionID) {
                return false
            }
            if let selectedCollectionID,
               task.collectionID != selectedCollectionID {
                return false
            }
            if !showsCompleted, task.isCompleted {
                return false
            }
            return Self.matches(task, query: searchText)
        }
    }

    /// Collection-grouped sections for the list, ordered by collection
    /// display name then provider position inside each section.
    public var sections: [ListSection] {
        var byCollection: [PIMCollection.ID: [PIMTask]] = [:]
        for task in visibleTasks {
            byCollection[task.collectionID, default: []].append(task)
        }
        return byCollection.keys.sorted { lhs, rhs in
            collectionTitle(for: lhs).localizedCaseInsensitiveCompare(
                collectionTitle(for: rhs)
            ) == .orderedAscending
        }.map { collectionID in
            ListSection(
                id: collectionID,
                title: collectionTitle(for: collectionID),
                tasks: (byCollection[collectionID] ?? []).sorted {
                    ($0.position ?? "\u{7FFF}")
                        .localizedStandardCompare(
                            $1.position ?? "\u{7FFF}"
                        ) == .orderedAscending
                }
            )
        }
    }

    /// The most recent cache write across loaded tasks — the
    /// "Updated" label's timestamp. Nil when the cache is empty.
    public var lastSyncAt: Date? {
        tasks.map(\.syncedAt).max()
    }

    /// Sources whose cached data may be stale — failed, needs
    /// reauthentication, or disconnected while the cache stays readable
    /// (ADR-0072 kept-cache contract).
    public var staleSources: [PIMSource] {
        sources.filter {
            switch $0.status {
            case .failed, .authenticationRequired, .disconnected:
                true
            case .connecting, .ready, .syncing, .permissionLimited:
                false
            }
        }
    }

    /// Whether any tasks source exists — drives the empty state that
    /// points at Settings rather than a bare "no tasks".
    public var hasSources: Bool {
        !sources.isEmpty
    }

    /// Whether Sync Now can run for a source in this session — the
    /// service exists and the source sits in a syncable status.
    public func canSyncNow(_ source: PIMSource) -> Bool {
        taskSyncService != nil
            && [
                PIMSourceStatus.ready, .syncing, .permissionLimited, .failed
            ].contains(source.status)
    }

    /// The cached record behind a selection, if it still exists.
    public func task(id: PIMTask.ID?) -> PIMTask? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }

    /// The collection a task belongs to, for provenance on detail.
    public func collection(for task: PIMTask) -> PIMCollection? {
        let collections = collectionsBySource[task.sourceID] ?? []
        return collections.first { $0.id == task.collectionID }
    }

    /// The source a task belongs to, for provenance on detail.
    public func source(for task: PIMTask) -> PIMSource? {
        sources.first { $0.id == task.sourceID }
    }

    /// Every discovered collection across tasks sources — the list
    /// filter's options.
    public var allCollections: [PIMCollection] {
        collectionsBySource.values.flatMap { $0 }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare(
                    $1.displayName
                ) == .orderedAscending
            }
    }

    // MARK: - Loading

    /// Loads sources, collections, and the cached tasks. Cache-only —
    /// never contacts a provider.
    public func load() async {
        isLoading = true
        defer {
            isLoading = false
            didLoad = true
        }
        do {
            sources = try await coordinator?.allSources()
                .filter { $0.kind == .tasks } ?? []
        } catch {
            lastError = error.localizedDescription
            return
        }
        await loadCollections()
        await loadTasks()
        reconcileSelection()
    }

    // MARK: - Deep links

    /// Reveals the task a brev://task link names.
    ///
    /// Ensures the cache has loaded at least once, then clears the
    /// search/list filters so the record is visible and selects it.
    /// A record that left the cache fails safe: the selection clears
    /// and an inline notice explains the miss.
    public func revealTask(id: PIMTask.ID) async {
        if !didLoad { await load() }
        guard let task = tasks.first(where: { $0.id == id }) else {
            selectedTaskID = nil
            deepLinkNotice = String(
                localized:
                "That task is no longer synced. It may have been deleted or its tasks source removed.",
                bundle: .module
            )
            return
        }
        deepLinkNotice = nil
        searchText = ""
        selectedCollectionID = nil
        showsCompleted = true
        selectedTaskID = task.id
    }

    private func loadCollections() async {
        guard let collectionService else {
            collectionsBySource = [:]
            return
        }
        var map: [PIMSource.ID: [PIMCollection]] = [:]
        for source in sources {
            // A store read failure must not blank the source — its rows
            // render without list metadata instead.
            await map[source.id] =
                (try? collectionService.collections(for: source.id))
                    ?? []
        }
        collectionsBySource = map
    }

    private func loadTasks() async {
        guard let taskSyncService else {
            tasks = []
            return
        }
        var all: [PIMTask] = []
        var failedSources: [String] = []
        for source in sources {
            do {
                try await all.append(
                    contentsOf: taskSyncService.tasks(for: source.id)
                )
            } catch {
                // One unreadable cache must not blank the others.
                failedSources.append(source.displayName)
            }
        }
        tasks = all
        if failedSources.isEmpty {
            lastError = nil
        } else {
            lastError = String(
                localized:
                "Couldn't read the cache for \(failedSources.formatted(.list(type: .and))).",
                bundle: .module
            )
        }
    }

    // MARK: - Sync

    /// User-initiated sync for one tasks source; reloads the cache
    /// afterward so the list reflects the fresh snapshot.
    public func syncNow(sourceID: PIMSource.ID) async {
        guard let taskSyncService,
              !syncingSourceIDs.contains(sourceID)
        else { return }
        syncingSourceIDs.insert(sourceID)
        defer { syncingSourceIDs.remove(sourceID) }
        do {
            let summary = try await taskSyncService.syncNow(
                sourceID: sourceID
            )
            if let first = summary.failures.first {
                lastError = first.message
            } else {
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
        await load()
    }

    /// Whether any source can run a Sync Now pass right now.
    public var canSyncAny: Bool {
        sources.contains { canSyncNow($0) }
    }

    /// Syncs every syncable source — the toolbar's single Sync action.
    public func syncAll() async {
        for source in sources where canSyncNow(source) {
            await syncNow(sourceID: source.id)
        }
    }

    // MARK: - Helpers

    /// Display name for a collection ID — the discovered collection's
    /// name, else the owning source's name, else a generic label.
    private func collectionTitle(for collectionID: PIMCollection.ID) -> String {
        for (sourceID, collections) in collectionsBySource {
            if let collection = collections.first(where: {
                $0.id == collectionID
            }) {
                return collection.displayName
            }
            _ = sourceID
        }
        return String(localized: "Tasks", bundle: .module)
    }

    /// Local-only match over title and notes — the fields the list
    /// renders.
    static func matches(_ task: PIMTask, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return (task.title ?? "")
            .localizedCaseInsensitiveContains(needle)
            || (task.notes ?? "")
            .localizedCaseInsensitiveContains(needle)
    }

    // MARK: - Selection

    /// Drops a stale selection after reloads; never auto-selects — the
    /// detail pane shows a placeholder until the user picks a task.
    private func reconcileSelection() {
        guard let selectedTaskID else { return }
        if !tasks.contains(where: { $0.id == selectedTaskID }) {
            self.selectedTaskID = nil
        }
    }
}
