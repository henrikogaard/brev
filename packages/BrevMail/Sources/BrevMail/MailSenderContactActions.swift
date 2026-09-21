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

/// What the sender panel can offer for a participant address (#10).
public enum SenderContactActionState: Equatable, Sendable {
    /// Still resolving the cached contact match.
    case resolving
    /// The address matches a synced contact — Open Contact is offered,
    /// with Edit when the source is writable.
    case existing(PIMContact)
    /// No cached contact — Add to Contacts is offered when at least one
    /// writable target exists.
    case missing
    /// No contacts sources are connected at all — hide the section.
    case unavailable
}

/// Resolves a message participant against the shared contact cache and
/// exposes the actions the sender panel offers (#10, ADR-0072).
///
/// All reads are cache-only — the model never contacts a provider.
/// Edits and creates go through ContactsEditingModel so capability
/// checks, target picking, and conflict handling match the Contacts
/// surface.
@Observable
@MainActor
public final class MailSenderContactActions {
    /// The resolved state for the last queried address.
    public private(set) var state: SenderContactActionState = .unavailable
    /// The email the state belongs to; stale resolutions are dropped.
    public private(set) var resolvedEmail: String?

    private let coordinator: PIMSourceCoordinator?
    private let contactSyncService: PIMContactSyncService?
    private let collectionService: PIMCollectionService?
    /// The editing model the panel hands to ContactEditorView.
    public let editing: ContactsEditingModel?

    public init(
        coordinator: PIMSourceCoordinator? = nil,
        contactSyncService: PIMContactSyncService? = nil,
        collectionService: PIMCollectionService? = nil,
        editing: ContactsEditingModel? = nil
    ) {
        self.coordinator = coordinator
        self.contactSyncService = contactSyncService
        self.collectionService = collectionService
        self.editing = editing
    }

    /// Whether the session has any contacts infrastructure at all.
    public var isAvailable: Bool {
        coordinator != nil && contactSyncService != nil
    }

    /// Resolves the participant's cached contact across every contacts
    /// source. Sources are scanned in order; the first exact email
    /// match wins so the action never silently picks a provider when
    /// several sources carry the address — the detail view shows the
    /// match's own provenance.
    public func resolve(email: String) async {
        let needle = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            resolvedEmail = nil
            state = .unavailable
            return
        }
        resolvedEmail = needle
        state = .resolving
        guard let coordinator, let contactSyncService else {
            state = .unavailable
            return
        }
        await editing?.load()
        do {
            let sources = try await coordinator.allSources()
                .filter { $0.kind == .contacts }
            for source in sources {
                if let match = try await contactSyncService.contact(
                    matchingEmail: needle,
                    for: source.id
                ) {
                    guard resolvedEmail == needle else { return }
                    state = .existing(match)
                    return
                }
            }
            guard resolvedEmail == needle else { return }
            state = .missing
        } catch {
            guard resolvedEmail == needle else { return }
            state = .missing
        }
    }

    /// Stateless variant of resolve(email:) for surfaces that query
    /// several participants — the recipient chips in the message
    /// reader (#10). Never touches state/resolvedEmail, so a lookup
    /// cannot clobber the sender panel's resolution. Returns nil when
    /// no contacts sources exist or no source caches the address.
    public func lookup(email: String) async -> SenderContactActionState {
        let needle = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty,
              let coordinator, let contactSyncService else {
            return .unavailable
        }
        await editing?.load()
        do {
            let sources = try await coordinator.allSources()
                .filter { $0.kind == .contacts }
            for source in sources {
                if let match = try await contactSyncService.contact(
                    matchingEmail: needle,
                    for: source.id
                ) {
                    return .existing(match)
                }
            }
            return .missing
        } catch {
            return .missing
        }
    }

    /// The source record for a resolved contact, for the detail view's
    /// provenance row.
    public func source(for contact: PIMContact) async -> PIMSource? {
        guard let coordinator else { return nil }
        return try? await coordinator.allSources()
            .first { $0.id == contact.sourceID }
    }

    /// The collection record for a resolved contact, when it still
    /// exists in the cached collections.
    public func collection(for contact: PIMContact) async -> PIMCollection? {
        guard let collectionService,
              let collectionID = contact.collectionID else { return nil }
        return try? await collectionService.collections(for: contact.sourceID)
            .first { $0.id == collectionID }
    }

    /// Group display names for a resolved contact — the providerKeys
    /// (Google resourceNames / CardDAV categories) matched against the
    /// source's cached collections, same rule the Contacts surface
    /// uses.
    public func groupNames(for contact: PIMContact) async -> [String] {
        guard let collectionService, !contact.groupKeys.isEmpty else {
            return []
        }
        let collections = await (try? collectionService.collections(
            for: contact.sourceID
        )) ?? []
        return contact.groupKeys.compactMap { key in
            collections.first { $0.providerKey == key }?.displayName
        }
    }

    /// Whether the resolved contact can be edited through the shared
    /// editor right now.
    public func canEdit(_ contact: PIMContact) -> Bool {
        editing?.canEdit(contact) ?? false
    }

    /// Whether at least one writable contact target exists — gates the
    /// Add to Contacts affordance.
    public var canAdd: Bool {
        editing?.targets.isEmpty == false
    }

    /// A create draft pre-filled with the participant's name and email.
    public func draftForNewContact(
        email: String,
        displayName: String?
    ) -> ContactDraft {
        var draft = ContactDraft()
        let trimmedEmail = email.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !trimmedEmail.isEmpty {
            draft.emails = [PIMContactField(label: nil, value: trimmedEmail)]
        }
        let name = displayName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        if !name.isEmpty {
            let parts = name.split(separator: " ", maxSplits: 1)
            draft.givenName = String(parts[0])
            if parts.count > 1 {
                draft.familyName = String(parts[1])
            }
        }
        draft.originalDisplayName = name
        draft.targetID = editing?.defaultTarget?.id
        return draft
    }
}
