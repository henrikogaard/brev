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

/// The write seam the contact editor calls (ADR-0072 #9).
/// PIMContactWriteService conforms; tests substitute a recording
/// double.
public protocol ContactWriting: Sendable {
    /// Whether the source may write into the collection (nil =
    /// account-wide, Google contacts).
    func canWrite(
        source: PIMSource,
        collection: PIMCollection?
    ) -> Bool

    /// Creates the contact and returns the stored record.
    @discardableResult
    func create(
        _ contact: PIMContact,
        in collection: PIMCollection?,
        source: PIMSource
    ) async throws -> PIMContact

    /// Replaces the writable fields of a cached contact.
    @discardableResult
    func update(
        _ contact: PIMContact,
        source: PIMSource
    ) async throws -> PIMContact

    /// Deletes the contact remotely and from the cache.
    func delete(
        _ contact: PIMContact,
        source: PIMSource
    ) async throws
}

extension PIMContactWriteService: ContactWriting {}

/// One writable target the contact editor offers. CardDAV targets wrap
/// one address-book collection; Google has a single account-wide
/// target — its contact groups are edited as memberships, not
/// containers.
public struct ContactWriteTarget: Sendable, Hashable, Identifiable {
    /// The account-wide target ID for Google contacts sources.
    public static func googleTargetID(for sourceID: PIMSource.ID) -> String {
        "google:" + sourceID
    }

    public let source: PIMSource
    /// The CardDAV address book; nil on the Google account-wide target.
    public let collection: PIMCollection?

    public var id: String {
        collection?.id ?? Self.googleTargetID(for: source.id)
    }

    public init(source: PIMSource, collection: PIMCollection?) {
        self.source = source
        self.collection = collection
    }

    /// "Family · account" for DAV; "account" for the Google target.
    public var title: String {
        if let collection {
            return collection.displayName + " · " + source.displayName
        }
        return source.displayName
    }
}

/// Observable owner of contact authoring for the Contacts surface
/// (ADR-0072 #9).
///
/// The model resolves writable targets from the coordinator and the
/// cached collections, runs create/update/delete through the write
/// seam, and reports failures as displayable text. A CardDAV move
/// between address books is create-in-target then delete-original —
/// there is no portable move primitive. Views never touch the
/// provider; the browsing model reloads after every mutation.
@Observable
@MainActor
public final class ContactsEditingModel {
    /// Writable targets, refreshed on load.
    public private(set) var targets: [ContactWriteTarget] = []
    /// Group collections per source, for the editor's membership
    /// section — Google contact groups and CardDAV collections alike,
    /// keyed by the ID the editor binds against (providerKey for
    /// groups, collection.id for CardDAV books).
    public private(set) var groupsBySource: [PIMSource.ID: [PIMCollection]] = [:]
    /// Whether a mutation is in flight; drives the editor spinner.
    public private(set) var isSaving = false
    /// Last actionable failure, surfaced inline by the editor sheet.
    public private(set) var lastError: String?

    private let writeService: (any ContactWriting)?
    private let coordinator: PIMSourceCoordinator?
    private let collectionService: PIMCollectionService?
    private let now: () -> Date

    public init(
        writeService: (any ContactWriting)? = nil,
        coordinator: PIMSourceCoordinator? = nil,
        collectionService: PIMCollectionService? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.writeService = writeService
        self.coordinator = coordinator
        self.collectionService = collectionService
        self.now = now
    }

    /// Whether contact authoring is wired in this session.
    public var canAuthor: Bool { writeService != nil }

    /// Refreshes the writable target list from the coordinator and the
    /// cached collections. Cache-only — never contacts a provider.
    public func load() async {
        guard let writeService, let coordinator else {
            targets = []
            groupsBySource = [:]
            return
        }
        do {
            let sources = try await coordinator.allSources()
                .filter { $0.kind == .contacts }
            var resolved: [ContactWriteTarget] = []
            var groups: [PIMSource.ID: [PIMCollection]] = [:]
            for source in sources {
                let collections = await (
                    try? collectionService?.collections(for: source.id)
                ) ?? []
                groups[source.id] = collections
                switch source.provider {
                case .google:
                    if writeService.canWrite(
                        source: source,
                        collection: nil
                    ) {
                        resolved.append(
                            ContactWriteTarget(
                                source: source,
                                collection: nil
                            )
                        )
                    }
                case .cardDAV:
                    for collection in collections
                        where writeService.canWrite(
                            source: source,
                            collection: collection
                        ) {
                        resolved.append(
                            ContactWriteTarget(
                                source: source,
                                collection: collection
                            )
                        )
                    }
                case .calDAV:
                    break
                }
            }
            targets = resolved
            groupsBySource = groups
            sourcesByID = Dictionary(
                uniqueKeysWithValues: sources.map { ($0.id, $0) }
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The target for a target ID, if it is writable.
    public func target(for targetID: String?) -> ContactWriteTarget? {
        targets.first { $0.id == targetID }
    }

    /// The default target for a new contact — the primary collection on
    /// the first writable DAV source, else the first writable target.
    public var defaultTarget: ContactWriteTarget? {
        targets.first { $0.collection?.isPrimary == true }
            ?? targets.first
    }

    /// Whether a cached contact can be edited: its source is writable
    /// and — for CardDAV — its collection resolves to a writable
    /// address book, since the editor needs a target to save into.
    /// Deletes stay href-based and work even when the collection
    /// record is gone.
    public func canEdit(_ contact: PIMContact) -> Bool {
        guard let source = sourcesByID[contact.sourceID] else {
            return false
        }
        switch source.provider {
        case .google:
            return targets.contains { $0.source.id == contact.sourceID }
        case .cardDAV:
            return targets.contains {
                $0.source.id == contact.sourceID
                    && $0.collection?.id == contact.collectionID
            }
        case .calDAV:
            return false
        }
    }

    // Sources seen during the last load — backs canEdit and delete.
    private var sourcesByID: [PIMSource.ID: PIMSource] = [:]

    /// The editable group collections for a source — Google contact
    /// groups minus the system groups, CardDAV address books.
    public func editableGroups(
        for sourceID: PIMSource.ID
    ) -> [PIMCollection] {
        (groupsBySource[sourceID] ?? []).filter { !$0.isReadOnly }
    }

    // MARK: - Mutations

    /// Saves a draft: creates a new contact, updates in place, or
    /// moves the record between CardDAV address books. Returns the
    /// stored record on success.
    @discardableResult
    public func save(_ draft: ContactDraft) async throws -> PIMContact {
        isSaving = true
        lastError = nil
        defer { isSaving = false }
        do {
            guard let writeService else {
                throw PIMContactWriteService.WriteError.unsupportedProvider
            }
            guard let target = target(for: draft.targetID) else {
                throw PIMContactWriteService.WriteError.notWritable
            }
            return try await performSave(
                draft,
                target: target,
                writeService: writeService
            )
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            throw error
        }
    }

    /// Deletes a cached contact remotely and from the cache.
    public func delete(_ contact: PIMContact) async throws {
        isSaving = true
        lastError = nil
        defer { isSaving = false }
        do {
            guard let writeService,
                  let source = sourcesByID[contact.sourceID]
            else {
                throw PIMContactWriteService.WriteError.notWritable
            }
            try await writeService.delete(contact, source: source)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            throw error
        }
    }

    // MARK: - Internals

    private func performSave(
        _ draft: ContactDraft,
        target: ContactWriteTarget,
        writeService: any ContactWriting
    ) async throws -> PIMContact {
        if !draft.isEditing {
            return try await writeService.create(
                draft.makeContact(
                    sourceID: target.source.id,
                    collectionID: target.collection?.id
                ),
                in: target.collection,
                source: target.source
            )
        }
        // A CardDAV move (target differs from the original collection)
        // is create-in-target then delete-original — there is no
        // portable move primitive, and the new record lands first so
        // a failure never loses the contact. Google contacts have no
        // collection: a target change there is just a group edit,
        // already carried by groupKeys.
        let moved = target.source.provider == .cardDAV
            && draft.originalCollectionID != nil
            && draft.originalCollectionID != target.collection?.id
        if moved {
            return try await move(
                draft,
                to: target,
                writeService: writeService
            )
        }
        return try await writeService.update(
            draft.makeContact(
                sourceID: target.source.id,
                collectionID: target.collection?.id
            ),
            source: target.source
        )
    }

    /// Moves a CardDAV contact between address books: create in the
    /// target (same UID, fresh href), then delete the original record.
    /// A delete failure after a successful create surfaces as an
    /// error — the contact exists in both books until the next sync
    /// reconciles, which is safer than losing it.
    private func move(
        _ draft: ContactDraft,
        to target: ContactWriteTarget,
        writeService: any ContactWriting
    ) async throws -> PIMContact {
        guard let originalID = draft.originalCollectionID,
              let originalTarget = targets.first(where: {
                  $0.collection?.id == originalID
              }),
              let originalCollection = originalTarget.collection
        else {
            throw PIMContactWriteService.WriteError.notWritable
        }
        var moved = draft
        // Fresh provider identity in the new book; the UID stays so
        // the contact remains the same logical record.
        moved.providerItemKey = nil
        moved.providerVersion = nil
        moved.rawPayload = nil
        let created = try await writeService.create(
            moved.makeContact(
                sourceID: target.source.id,
                collectionID: target.collection?.id
            ),
            in: target.collection,
            source: target.source
        )
        try await writeService.delete(
            draft.makeContact(
                sourceID: originalTarget.source.id,
                collectionID: originalCollection.id
            ),
            source: originalTarget.source
        )
        return created
    }
}
