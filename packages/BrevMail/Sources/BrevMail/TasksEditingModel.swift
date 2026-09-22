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

/// The write seam the task editor calls (ADR-0072 #12).
/// PIMTaskWriteService conforms; tests substitute a recording double.
public protocol TaskWriting: Sendable {
    /// Whether the source may write into the collection.
    func canWrite(
        source: PIMSource,
        collection: PIMCollection
    ) -> Bool

    /// Creates the task and returns the stored record.
    @discardableResult
    func create(
        _ task: PIMTask,
        in collection: PIMCollection,
        source: PIMSource
    ) async throws -> PIMTask

    /// Replaces the writable fields of a cached task.
    @discardableResult
    func update(
        _ task: PIMTask,
        in collection: PIMCollection,
        source: PIMSource
    ) async throws -> PIMTask

    /// Deletes the task remotely and from the cache.
    func delete(
        _ task: PIMTask,
        in collection: PIMCollection,
        source: PIMSource
    ) async throws

    /// Moves the task to another collection on the same source.
    @discardableResult
    func move(
        _ task: PIMTask,
        to target: PIMCollection,
        in collection: PIMCollection,
        source: PIMSource
    ) async throws -> PIMTask
}

extension PIMTaskWriteService: TaskWriting {}

/// One writable target the task editor offers — a task list on a
/// writable source.
public struct TaskWriteTarget: Sendable, Hashable, Identifiable {
    public let source: PIMSource
    public let collection: PIMCollection

    public var id: String { collection.id }

    public init(source: PIMSource, collection: PIMCollection) {
        self.source = source
        self.collection = collection
    }

    /// "List · account" for the target picker.
    public var title: String {
        collection.displayName + " · " + source.displayName
    }
}

/// Observable owner of task authoring for the Tasks surface
/// (ADR-0072 #12).
///
/// The model resolves writable targets from the coordinator and the
/// cached collections, runs create/update/delete/move through the
/// write seam, and reports failures as displayable text. Views never
/// touch the provider; the browsing model reloads after every
/// mutation.
@Observable
@MainActor
public final class TasksEditingModel {
    /// Writable targets, refreshed on load.
    public private(set) var targets: [TaskWriteTarget] = []
    /// Whether a mutation is in flight; drives the editor spinner.
    public private(set) var isSaving = false
    /// Last actionable failure, surfaced inline by the editor sheet.
    public private(set) var lastError: String?

    private let writeService: (any TaskWriting)?
    private let coordinator: PIMSourceCoordinator?
    private let collectionService: PIMCollectionService?
    private let now: () -> Date
    private var sourcesByID: [PIMSource.ID: PIMSource] = [:]

    public init(
        writeService: (any TaskWriting)? = nil,
        coordinator: PIMSourceCoordinator? = nil,
        collectionService: PIMCollectionService? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.writeService = writeService
        self.coordinator = coordinator
        self.collectionService = collectionService
        self.now = now
    }

    /// Whether task authoring is wired in this session.
    public var canAuthor: Bool { writeService != nil }

    /// Refreshes the writable target list from the coordinator and the
    /// cached collections. Cache-only — never contacts a provider.
    public func load() async {
        guard let writeService, let coordinator else {
            targets = []
            return
        }
        do {
            let sources = try await coordinator.allSources()
                .filter { $0.kind == .tasks }
            var resolved: [TaskWriteTarget] = []
            for source in sources
                where source.provider == .google
                || source.provider == .calDAV {
                let collections = await (
                    try? collectionService?.collections(for: source.id)
                ) ?? []
                for collection in collections
                    where writeService.canWrite(
                        source: source,
                        collection: collection
                    ) {
                    resolved.append(
                        TaskWriteTarget(
                            source: source,
                            collection: collection
                        )
                    )
                }
            }
            targets = resolved
            sourcesByID = Dictionary(
                uniqueKeysWithValues: sources.map { ($0.id, $0) }
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The target for a target ID, if it is writable.
    public func target(for targetID: String?) -> TaskWriteTarget? {
        targets.first { $0.id == targetID }
    }

    /// The default target for a new task — the primary collection on
    /// the first writable source, else the first writable target.
    public var defaultTarget: TaskWriteTarget? {
        targets.first { $0.collection.isPrimary }
            ?? targets.first
    }

    /// Whether a cached task can be edited: its source is writable and
    /// its collection resolves to a writable list.
    public func canEdit(_ task: PIMTask) -> Bool {
        guard let writeService,
              let source = sourcesByID[task.sourceID]
        else { return false }
        let collections = targets
            .filter { $0.source.id == task.sourceID }
            .map(\.collection)
        guard let collection = collections.first(where: {
            $0.id == task.collectionID
        }) else { return false }
        return writeService.canWrite(source: source, collection: collection)
    }

    // MARK: - Mutations

    /// Creates a task from the draft into its chosen target.
    @discardableResult
    public func create(_ draft: TaskDraft) async throws -> PIMTask {
        isSaving = true
        lastError = nil
        defer { isSaving = false }
        do {
            guard let writeService else {
                throw PIMTaskWriteService.WriteError.unsupportedProvider
            }
            guard let target = target(for: draft.targetID) else {
                throw PIMTaskWriteService.WriteError.notWritable
            }
            let stored = try await writeService.create(
                draft.task(
                    sourceID: target.source.id,
                    collectionID: target.collection.id
                ),
                in: target.collection,
                source: target.source
            )
            lastError = nil
            return stored
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            throw error
        }
    }

    /// Saves edits to a cached task — including a list change, which
    /// routes through the cross-collection move path.
    @discardableResult
    public func update(_ draft: TaskDraft, for task: PIMTask) async throws -> PIMTask {
        isSaving = true
        lastError = nil
        defer { isSaving = false }
        do {
            guard let writeService else {
                throw PIMTaskWriteService.WriteError.unsupportedProvider
            }
            guard let source = sourcesByID[task.sourceID] else {
                throw PIMTaskWriteService.WriteError.notWritable
            }
            guard let collection = targets
                .first(where: { $0.id == task.collectionID })?.collection
            else {
                throw PIMTaskWriteService.WriteError.notWritable
            }
            var updated = task
            updated.title = draft.title
            updated.notes = draft.notes.isEmpty ? nil : draft.notes
            updated.due = draft.due
            updated.status = draft.status
            updated.completedAt = draft.status == .completed
                ? (task.completedAt ?? now())
                : nil
            let result: PIMTask
            if draft.targetID != task.collectionID,
               let target = target(for: draft.targetID) {
                result = try await writeService.move(
                    updated,
                    to: target.collection,
                    in: collection,
                    source: source
                )
            } else {
                result = try await writeService.update(
                    updated,
                    in: collection,
                    source: source
                )
            }
            lastError = nil
            return result
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            throw error
        }
    }

    /// Deletes a cached task remotely and from the cache.
    public func delete(_ task: PIMTask) async throws {
        isSaving = true
        lastError = nil
        defer { isSaving = false }
        do {
            guard let writeService,
                  let source = sourcesByID[task.sourceID],
                  let collection = targets
                  .first(where: { $0.id == task.collectionID })?.collection
            else {
                throw PIMTaskWriteService.WriteError.notWritable
            }
            try await writeService.delete(
                task,
                in: collection,
                source: source
            )
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            throw error
        }
    }

    /// Toggles a task's completion — the list row's checkbox action.
    /// Completing stamps completedAt; reopening clears it.
    @discardableResult
    public func toggleCompleted(_ task: PIMTask) async throws -> PIMTask {
        var draft = TaskDraft(task: task)
        draft.status = task.isCompleted ? .needsAction : .completed
        return try await update(draft, for: task)
    }
}
