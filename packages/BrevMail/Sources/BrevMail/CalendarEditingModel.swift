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

/// The write seam the editor calls (ADR-0072 #7). PIMEventWriteService
/// conforms; tests substitute a recording double.
public protocol CalendarEventWriting: Sendable {
    /// Whether the source may write into the collection.
    func canWrite(
        source: PIMSource,
        collection: PIMCollection
    ) -> Bool

    /// Creates the event in the collection and returns the stored record.
    @discardableResult
    func create(
        _ event: PIMEvent,
        in collection: PIMCollection,
        source: PIMSource
    ) async throws -> PIMEvent

    /// Replaces the writable fields of a cached event.
    @discardableResult
    func update(
        _ event: PIMEvent,
        in collection: PIMCollection,
        source: PIMSource
    ) async throws -> PIMEvent

    /// Deletes the event remotely and from the cache.
    func delete(
        _ event: PIMEvent,
        in collection: PIMCollection,
        source: PIMSource
    ) async throws
}

extension PIMEventWriteService: CalendarEventWriting {}

/// How a change to a repeating series applies (ADR-0072 #7).
///
/// Both providers converge on the same portable mechanics: updating the
/// whole series patches the master component, while the future scope
/// truncates the master RRULE at the edited start and creates a new
/// series from the edited values. Single-occurrence exceptions need
/// multi-component VEVENT resources on CalDAV and recurringEventId on
/// Google — deferred to a later slice.
public enum CalendarRecurringEditScope: String, Sendable, CaseIterable {
    /// Apply to every occurrence, past and future.
    case series
    /// End the existing series before this occurrence and start a new
    /// one carrying the edits.
    case future

    /// The confirmation-dialog label for the scope.
    public var title: String {
        switch self {
        case .series:
            String(localized: "All Events", bundle: .module)
        case .future:
            String(localized: "This and Future Events", bundle: .module)
        }
    }
}

/// One writable target the editor offers: a collection plus the source
/// it belongs to, pre-checked for write capability.
public struct CalendarWriteTarget: Sendable, Hashable, Identifiable {
    public let collection: PIMCollection
    public let source: PIMSource

    public var id: PIMCollection.ID { collection.id }

    public init(collection: PIMCollection, source: PIMSource) {
        self.collection = collection
        self.source = source
    }

    /// "Work · henrik@example.com" for the target picker.
    public var title: String {
        collection.displayName + " · " + source.displayName
    }
}

/// Observable owner of event authoring for the Calendar surface
/// (ADR-0072 #7).
///
/// The model resolves writable targets from the browsing model sources
/// and collections, runs create/update/delete through the write seam,
/// and reports failures as displayable text. Views never touch the
/// provider — every mutation goes through the seam and the browsing
/// model reloads afterward.
@Observable
@MainActor
public final class CalendarEditingModel {
    /// Writable collection+source pairs, refreshed on load.
    public private(set) var targets: [CalendarWriteTarget] = []
    /// Whether a mutation is in flight; drives the editor spinner.
    public private(set) var isSaving = false
    /// Last actionable failure, surfaced inline by the editor sheet.
    public private(set) var lastError: String?

    private let writeService: (any CalendarEventWriting)?
    private let coordinator: PIMSourceCoordinator?
    private let collectionService: PIMCollectionService?
    private let now: () -> Date

    public init(
        writeService: (any CalendarEventWriting)? = nil,
        coordinator: PIMSourceCoordinator? = nil,
        collectionService: PIMCollectionService? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.writeService = writeService
        self.coordinator = coordinator
        self.collectionService = collectionService
        self.now = now
    }

    /// Whether event authoring is wired in this session.
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
                .filter { $0.kind == .calendar }
            var resolved: [CalendarWriteTarget] = []
            for source in sources {
                let collections = await (
                    try? collectionService?.collections(for: source.id)
                ) ?? []
                for collection in collections
                    where writeService.canWrite(
                        source: source,
                        collection: collection
                    ) {
                    resolved.append(
                        CalendarWriteTarget(
                            collection: collection,
                            source: source
                        )
                    )
                }
            }
            targets = resolved
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The target for a collection ID, if it is writable.
    public func target(
        for collectionID: PIMCollection.ID?
    ) -> CalendarWriteTarget? {
        targets.first { $0.collection.id == collectionID }
    }

    /// The default target for a new event — the primary collection on
    /// the first writable source, else the first writable collection.
    public var defaultTarget: CalendarWriteTarget? {
        targets.first { $0.collection.isPrimary } ?? targets.first
    }

    /// Whether a cached event can be edited: its source+collection pair
    /// is writable right now.
    public func canEdit(_ event: PIMEvent) -> Bool {
        target(for: event.collectionID) != nil
    }

    /// Whether the event is part of a repeating series — master or
    /// exception — so the UI asks for a scope before mutating.
    public func needsScopeChoice(for event: PIMEvent) -> Bool {
        event.recurrenceRule != nil || event.recurrenceID != nil
    }

    // MARK: - Mutations

    /// Saves a draft: creates a new event, updates in place, or applies
    /// the recurring scope. Returns the stored record on success.
    @discardableResult
    public func save(
        _ draft: CalendarEventDraft,
        scope: CalendarRecurringEditScope? = nil
    ) async throws -> PIMEvent {
        isSaving = true
        lastError = nil
        defer { isSaving = false }
        do {
            guard let writeService else {
                throw PIMEventWriteService.WriteError.unsupportedProvider
            }
            guard let target = target(for: draft.targetCollectionID)
            else {
                throw PIMEventWriteService.WriteError.notWritable
            }
            let saved = try await performSave(
                draft,
                target: target,
                scope: scope
            )
            return saved
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            throw error
        }
    }

    /// Deletes a cached event under the requested scope. The series
    /// scope (or a non-recurring event) deletes the record outright;
    /// the future scope truncates the master RRULE so the series ends
    /// before the occurrence the user deleted from.
    public func delete(
        _ event: PIMEvent,
        scope: CalendarRecurringEditScope? = nil
    ) async throws {
        isSaving = true
        lastError = nil
        defer { isSaving = false }
        do {
            guard let writeService else {
                throw PIMEventWriteService.WriteError.unsupportedProvider
            }
            guard let target = target(for: event.collectionID) else {
                throw PIMEventWriteService.WriteError.notWritable
            }
            if scope == .future, event.recurrenceRule != nil {
                var truncated = event
                if let rule = truncated.recurrenceRule {
                    // UNTIL is inclusive — the series ends the day
                    // before the occurrence the user deleted from.
                    let boundary = Calendar.current.date(
                        byAdding: .day,
                        value: -1,
                        to: event.start ?? now()
                    ) ?? now()
                    truncated.recurrenceRule = ICSParser.RecurrenceRule(
                        frequency: rule.frequency,
                        interval: rule.interval,
                        count: nil,
                        until: boundary,
                        byDay: rule.byDay
                    )
                }
                _ = try await writeService.update(
                    truncated,
                    in: target.collection,
                    source: target.source
                )
            } else {
                try await writeService.delete(
                    event,
                    in: target.collection,
                    source: target.source
                )
            }
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            throw error
        }
    }

    // MARK: - Internals

    private func performSave(
        _ draft: CalendarEventDraft,
        target: CalendarWriteTarget,
        scope: CalendarRecurringEditScope?
    ) async throws -> PIMEvent {
        guard let writeService else {
            throw PIMEventWriteService.WriteError.unsupportedProvider
        }
        if !draft.isEditing {
            return try await writeService.create(
                draft.makeEvent(
                    sourceID: target.source.id,
                    collectionID: target.collection.id
                ),
                in: target.collection,
                source: target.source
            )
        }
        if scope == .future {
            return try await saveFutureScope(draft, target: target)
        }
        // A moved event (target differs from the original collection)
        // is a portable create+delete: providers share no move
        // primitive, and an update addressed to the old provider key
        // inside the new collection would miss. The new record lands
        // first — carrying the same UID so the event keeps its
        // identity — and the old one is removed only after the create
        // succeeds.
        let moved = draft.originalCollectionID != nil
            && draft.originalCollectionID != target.collection.id
        if moved {
            return try await move(
                draft,
                to: target,
                writeService: writeService
            )
        }
        return try await writeService.update(
            draft.makeEvent(
                sourceID: target.source.id,
                collectionID: target.collection.id
            ),
            in: target.collection,
            source: target.source
        )
    }

    /// Moves an event between writable collections: create in the
    /// target (same UID, fresh provider key), then delete the original
    /// record. A delete failure after a successful create surfaces as
    /// an error — the event exists in both places until the next sync
    /// reconciles, which is safer than losing it.
    private func move(
        _ draft: CalendarEventDraft,
        to target: CalendarWriteTarget,
        writeService: any CalendarEventWriting
    ) async throws -> PIMEvent {
        guard let originalID = draft.originalCollectionID,
              let originalTarget = self.target(for: originalID)
        else {
            throw PIMEventWriteService.WriteError.notWritable
        }
        var moved = draft
        // Fresh provider identity in the new collection; the UID stays
        // so the event remains the same logical event.
        moved.providerItemKey = nil
        moved.providerVersion = nil
        moved.rawPayload = nil
        // A synced conference cannot be carried into a Google create —
        // conferenceData is provider-assigned — so a moved event with
        // one asks the target for a fresh conference instead of
        // silently losing the video call (#13). CalDAV targets keep
        // the conference: it round-trips through the ICS payload.
        if moved.conference != nil,
           moved.conference?.isCreationRequest == false,
           target.source.provider == .google {
            moved.conference = PIMConference(
                kind: .meet,
                status: .pending,
                isCreationRequest: true
            )
        }
        let created = try await writeService.create(
            moved.makeEvent(
                sourceID: target.source.id,
                collectionID: target.collection.id
            ),
            in: target.collection,
            source: target.source
        )
        try await writeService.delete(
            draft.makeEvent(
                sourceID: originalTarget.source.id,
                collectionID: originalTarget.collection.id
            ),
            in: originalTarget.collection,
            source: originalTarget.source
        )
        return created
    }

    /// The future scope: truncate the original series at the edited
    /// start, then create a new series with the edited fields. The new
    /// UID keeps the two series distinct on every provider.
    private func saveFutureScope(
        _ draft: CalendarEventDraft,
        target: CalendarWriteTarget
    ) async throws -> PIMEvent {
        guard let writeService else {
            throw PIMEventWriteService.WriteError.unsupportedProvider
        }
        guard let originalID = draft.originalCollectionID,
              let originalTarget = self.target(for: originalID)
        else {
            throw PIMEventWriteService.WriteError.notWritable
        }
        var master = draft.makeEvent(
            sourceID: originalTarget.source.id,
            collectionID: originalTarget.collection.id
        )
        guard let rule = master.recurrenceRule else {
            throw PIMEventWriteService.WriteError.invalidResponse
        }
        let boundary = Calendar.current.date(
            byAdding: .day,
            value: -1,
            to: draft.start
        ) ?? draft.start
        master.recurrenceRule = ICSParser.RecurrenceRule(
            frequency: rule.frequency,
            interval: rule.interval,
            count: nil,
            until: boundary,
            byDay: rule.byDay
        )
        _ = try await writeService.update(
            master,
            in: originalTarget.collection,
            source: originalTarget.source
        )
        // New series: same fields, fresh identity — uid and
        // providerItemKey reset so the provider assigns both.
        var newSeries = draft
        newSeries.uid = nil
        newSeries.providerItemKey = nil
        newSeries.providerVersion = nil
        newSeries.recurrenceID = nil
        newSeries.rawPayload = nil
        return try await writeService.create(
            newSeries.makeEvent(
                sourceID: target.source.id,
                collectionID: target.collection.id
            ),
            in: target.collection,
            source: target.source
        )
    }
}
