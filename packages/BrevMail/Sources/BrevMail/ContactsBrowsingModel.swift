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

/// Browsing model behind the Contacts surface (ADR-0072).
///
/// Reads the synced cache only — `load()` never issues provider
/// requests, so an offline launch renders the last complete snapshot.
/// Provider traffic happens solely inside `syncNow`, which the user
/// triggers explicitly. One unreadable source cache never blanks the
/// others; the failure surfaces inline while healthy sources keep
/// rendering.
@Observable
@MainActor
public final class ContactsBrowsingModel {
    /// One alphabetical bucket in the contacts list.
    public struct LetterSection: Identifiable, Hashable, Sendable {
        public let id: String
        /// The section letter, or "#" for non-letter names.
        public let letter: String
        public var contacts: [PIMContact]

        public init(id: String, letter: String, contacts: [PIMContact]) {
            self.id = id
            self.letter = letter
            self.contacts = contacts
        }
    }

    // MARK: - State

    /// Contacts sources known to the coordinator, in coordinator order.
    public private(set) var sources: [PIMSource] = []
    /// Discovered collections (address books / contact groups) per
    /// source; empty when discovery never ran.
    public private(set) var collectionsBySource:
        [PIMSource.ID: [PIMCollection]] = [:]
    /// All cached contacts across contacts sources, name-sorted.
    public private(set) var contacts: [PIMContact] = []
    public private(set) var isLoading = false
    /// Inline error text for the last failed load or sync pass.
    public private(set) var lastError: String?
    /// Sources currently running a Sync Now pass.
    public private(set) var syncingSourceIDs: Set<PIMSource.ID> = []

    /// Local-only query over the cached contact fields.
    public var searchText = ""
    /// Group/address-book filter — nil shows every visible collection.
    public var selectedCollectionID: PIMCollection.ID?
    /// Selection shared between the list and the detail pane.
    public var selectedContactID: PIMContact.ID?
    /// One-line notice when a brev://contact deep link names a record
    /// that is no longer in the cache (#10).
    public private(set) var deepLinkNotice: String?

    private let coordinator: PIMSourceCoordinator?
    private let collectionService: PIMCollectionService?
    private let contactSyncService: PIMContactSyncService?
    private let now: () -> Date
    /// Whether load() finished at least once — deep links ensure the
    /// cache is loaded before they reveal so a cold window cannot
    /// report a miss on data it never read.
    private var didLoad = false

    /// - Parameters:
    ///   - coordinator: Source registry; nil in sessions without PIM.
    ///   - collectionService: Collection cache for visibility + groups.
    ///   - contactSyncService: Contact cache and Sync Now owner.
    ///   - now: Clock, injected for tests.
    public init(
        coordinator: PIMSourceCoordinator? = nil,
        collectionService: PIMCollectionService? = nil,
        contactSyncService: PIMContactSyncService? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.coordinator = coordinator
        self.collectionService = collectionService
        self.contactSyncService = contactSyncService
        self.now = now
    }

    // MARK: - Derived state

    /// Contacts the list shows: hidden collections excluded, the group
    /// filter and search applied, name-sorted. A contact whose
    /// collection has no discovery record still shows — it was synced
    /// while visible. Google contacts are account-wide; their
    /// membership is carried by `groupKeys`.
    public var visibleContacts: [PIMContact] {
        let hiddenCollectionIDs = Set(
            collectionsBySource.values.flatMap { $0 }
                .filter { !$0.isVisible }
                .map(\.id)
        )
        return contacts.filter { contact in
            // CardDAV records bind to one collection; Google records
            // carry group memberships. A record is hidden only when
            // every group/collection it belongs to is hidden.
            if let collectionID = contact.collectionID,
               hiddenCollectionIDs.contains(collectionID) {
                return false
            }
            if !contact.groupKeys.isEmpty,
               contact.groupKeys.allSatisfy({
                   hiddenCollectionIDs.contains($0)
               }) {
                return false
            }
            if let selectedCollectionID,
               contact.collectionID != selectedCollectionID,
               !contact.groupKeys.contains(selectedCollectionID) {
                return false
            }
            return ContactPresentation.matches(
                contact,
                query: searchText
            )
        }
    }

    /// Alphabetical sections for the list, "#" last.
    public var sections: [LetterSection] {
        var byLetter: [String: [PIMContact]] = [:]
        for contact in visibleContacts {
            byLetter[
                ContactPresentation.sectionKey(for: contact),
                default: []
            ].append(contact)
        }
        return byLetter.keys.sorted { lhs, rhs in
            if lhs == "#" { return false }
            if rhs == "#" { return true }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }.map { letter in
            LetterSection(
                id: letter,
                letter: letter,
                contacts: byLetter[letter] ?? []
            )
        }
    }

    /// The most recent cache write across loaded contacts — the
    /// "Updated" label's timestamp. Nil when the cache is empty.
    public var lastSyncAt: Date? {
        contacts.map(\.syncedAt).max()
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

    /// Whether any contacts source exists — drives the empty state that
    /// points at Settings rather than a bare "no contacts".
    public var hasSources: Bool {
        !sources.isEmpty
    }

    /// Whether Sync Now can run for a source in this session — the
    /// service exists and the source sits in a syncable status.
    public func canSyncNow(_ source: PIMSource) -> Bool {
        contactSyncService != nil
            && [
                PIMSourceStatus.ready, .syncing, .permissionLimited, .failed
            ].contains(source.status)
    }

    /// The cached record behind a selection, if it still exists.
    public func contact(id: PIMContact.ID?) -> PIMContact? {
        guard let id else { return nil }
        return contacts.first { $0.id == id }
    }

    /// The collection a contact belongs to, for provenance on detail.
    /// Google contacts may carry several group keys; the first known
    /// collection wins.
    public func collection(for contact: PIMContact) -> PIMCollection? {
        let collections = collectionsBySource[contact.sourceID] ?? []
        if let collectionID = contact.collectionID {
            return collections.first { $0.id == collectionID }
        }
        return contact.groupKeys
            .compactMap { key in collections.first { $0.id == key } }
            .first
    }

    /// The source a contact belongs to, for provenance on detail.
    public func source(for contact: PIMContact) -> PIMSource? {
        sources.first { $0.id == contact.sourceID }
    }

    /// Every discovered collection across contacts sources — the group
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

    /// Loads sources, collections, and the cached contacts. Cache-only —
    /// never contacts a provider.
    public func load() async {
        isLoading = true
        defer {
            isLoading = false
            didLoad = true
        }
        do {
            sources = try await coordinator?.allSources()
                .filter { $0.kind == .contacts } ?? []
        } catch {
            lastError = error.localizedDescription
            return
        }
        await loadCollections()
        await loadContacts()
        reconcileSelection()
    }

    // MARK: - Deep links

    /// Reveals the contact a brev://contact link names (#10).
    ///
    /// Ensures the cache has loaded at least once, then clears the
    /// search/group filters so the record is visible and selects it.
    /// A record that left the cache — the source was disconnected with
    /// its cache cleared, or the link is stale — fails safe: the
    /// selection clears and an inline notice explains the miss instead
    /// of silently landing on an unrelated contact.
    public func revealContact(id: PIMContact.ID) async {
        if !didLoad { await load() }
        guard let contact = contacts.first(where: { $0.id == id }) else {
            selectedContactID = nil
            deepLinkNotice = String(
                localized:
                "That contact is no longer synced. It may have been deleted or its contacts source removed.",
                bundle: .module
            )
            return
        }
        deepLinkNotice = nil
        searchText = ""
        selectedCollectionID = nil
        selectedContactID = contact.id
    }

    private func loadCollections() async {
        guard let collectionService else {
            collectionsBySource = [:]
            return
        }
        var map: [PIMSource.ID: [PIMCollection]] = [:]
        for source in sources {
            // A store read failure must not blank the source — its rows
            // render without group metadata instead.
            await map[source.id] =
                (try? collectionService.collections(for: source.id))
                    ?? []
        }
        collectionsBySource = map
    }

    private func loadContacts() async {
        guard let contactSyncService else {
            contacts = []
            return
        }
        var all: [PIMContact] = []
        var failedSources: [String] = []
        for source in sources {
            do {
                try await all.append(
                    contentsOf: contactSyncService.contacts(
                        for: source.id
                    )
                )
            } catch {
                // One unreadable cache must not blank the others.
                failedSources.append(source.displayName)
            }
        }
        contacts = all.sorted {
            $0.displayName.localizedStandardCompare($1.displayName)
                == .orderedAscending
        }
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

    /// User-initiated sync for one contacts source; reloads the cache
    /// afterward so the list reflects the fresh snapshot.
    public func syncNow(sourceID: PIMSource.ID) async {
        guard let contactSyncService,
              !syncingSourceIDs.contains(sourceID)
        else { return }
        syncingSourceIDs.insert(sourceID)
        defer { syncingSourceIDs.remove(sourceID) }
        do {
            let summary = try await contactSyncService.syncNow(
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

    // MARK: - Selection

    /// Drops a stale selection after reloads; never auto-selects — the
    /// detail pane shows a placeholder until the user picks a contact.
    private func reconcileSelection() {
        guard let selectedContactID else { return }
        if !contacts.contains(where: { $0.id == selectedContactID }) {
            self.selectedContactID = nil
        }
    }
}
