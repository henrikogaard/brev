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

import Foundation

/// Provider-neutral contact write path (ADR-0072 #9).
///
/// Create, update, and delete dispatch on the source's provider —
/// Google via the People `people:*Contact` endpoints, CardDAV via
/// PUT/DELETE on the address object href — behind one capability
/// check: a write runs only when the source's enabledCapabilities
/// carries `.write` and, for collection-scoped creates, the target
/// address book or group is not read-only. Preconditions ride every
/// mutation (Google etag in the update body, CardDAV If-Match /
/// If-None-Match) so a stale edit surfaces as conflict instead of
/// overwriting a newer remote change.
///
/// After a successful write the local cache updates in place — the
/// next sync reconciles the provider's canonical record
/// (rawPayload included).
public actor PIMContactWriteService {
    /// Errors surfaced by the write path.
    public enum WriteError: Error, Sendable, Hashable, LocalizedError {
        /// The source lacks the write capability or the collection is
        /// read-only — the UI should never have offered the action.
        case notWritable
        /// The source record has no usable credential path.
        case missingCredential
        /// The remote changed since the cached copy — reload and re-ask.
        case conflict
        /// The credential was rejected or lacks the write scope.
        case authenticationRequired
        /// The provider answered with a status or body Brev cannot use.
        case invalidResponse
        /// Connectivity or an unspecified transport failure.
        case transportFailed
        /// The provider is not served by this write path.
        case unsupportedProvider

        public var errorDescription: String? {
            switch self {
            case .notWritable:
                String(
                    localized:
                    "This address book is read-only.",
                    bundle: .module
                )
            case .missingCredential:
                String(
                    localized:
                    "The source has no stored credential. Reconnect it first.",
                    bundle: .module
                )
            case .conflict:
                String(
                    localized:
                    "This contact changed on the server. Sync, then try again.",
                    bundle: .module
                )
            case .authenticationRequired:
                String(
                    localized:
                    "Editing needs a fresh grant. Reconnect the source in Settings.",
                    bundle: .module
                )
            case .invalidResponse:
                String(
                    localized:
                    "The provider returned a response Brev could not use.",
                    bundle: .module
                )
            case .transportFailed:
                String(
                    localized:
                    "The server could not be reached. Check the connection and try again.",
                    bundle: .module
                )
            case .unsupportedProvider:
                String(
                    localized:
                    "This source does not support editing.",
                    bundle: .module
                )
            }
        }
    }

    private let coordinator: PIMSourceCoordinator
    private let contactStore: any PIMContactStore
    private let credentials: any CalDAVCredentialStore
    private let googleWriter: GooglePeopleContactWriter
    private let davWriter: PIMDAVContactWriter
    /// Resolves a Google access token for a linked mail account ID —
    /// injected by the session so this package stays provider-agnostic.
    private let googleAccessToken: (@Sendable (String) async throws -> String)?
    private let now: () -> Date

    public init(
        coordinator: PIMSourceCoordinator,
        contactStore: any PIMContactStore,
        credentials: any CalDAVCredentialStore,
        googleWriter: GooglePeopleContactWriter = GooglePeopleContactWriter(),
        davWriter: PIMDAVContactWriter = PIMDAVContactWriter(),
        googleAccessToken: (@Sendable (String) async throws -> String)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.coordinator = coordinator
        self.contactStore = contactStore
        self.credentials = credentials
        self.googleWriter = googleWriter
        self.davWriter = davWriter
        self.googleAccessToken = googleAccessToken
        self.now = now
    }

    // MARK: - Capability

    /// Whether a write may run: the source carries the `.write`
    /// capability and — when a collection is given — the collection is
    /// not read-only. Google updates and deletes pass no collection:
    /// contacts live source-wide and their groups are editable data.
    /// nonisolated: a pure function of the records, so UI code can gate
    /// affordances without an await.
    public nonisolated func canWrite(
        source: PIMSource,
        collection: PIMCollection?
    ) -> Bool {
        guard source.enabledCapabilities.contains(.write),
              source.kind == .contacts,
              [PIMSourceProvider.google, .cardDAV].contains(
                  source.provider
              )
        else { return false }
        if let collection, collection.isReadOnly { return false }
        return true
    }

    // MARK: - Create

    /// Creates a contact and stores the provider-assigned record in the
    /// cache. CardDAV targets an address book collection; Google
    /// contacts are account-wide, so the target collection — when one
    /// is chosen — lands as a group membership. The new UID is
    /// generated here — callers never invent one.
    @discardableResult
    public func create(
        _ contact: PIMContact,
        in collection: PIMCollection?,
        source: PIMSource
    ) async throws -> PIMContact {
        guard canWrite(source: source, collection: collection) else {
            throw WriteError.notWritable
        }
        let uid = contact.uid ?? UUID().uuidString + "@brev"
        var draft = contact
        draft.uid = uid
        switch source.provider {
        case .google:
            let token = try await googleToken(for: source)
            // A chosen contact-group collection becomes a membership;
            // the system myContacts group is implicit on Google.
            if let collection,
               !collection.providerKey.hasSuffix("/myContacts"),
               !draft.groupKeys.contains(collection.providerKey) {
                draft.groupKeys.append(collection.providerKey)
            }
            let result = try await mapGoogleError {
                try await googleWriter.create(
                    draft,
                    accessToken: token
                )
            }
            draft.providerItemKey = result.resourceName
            draft.providerVersion = result.etag
        case .cardDAV:
            guard let collection else {
                throw WriteError.notWritable
            }
            let credential = try await davCredential(for: source)
            let vcard = PIMVCardWriter.vcard(
                for: draft,
                revisedAt: now()
            )
            let result = try await mapDAVError {
                try await davWriter.create(
                    draft,
                    vcard: vcard,
                    in: collection,
                    credential: credential
                )
            }
            draft.providerItemKey = result.resourceURL.absoluteString
            draft.providerVersion = result.etag
            draft.collectionID = collection.id
        case .calDAV:
            throw WriteError.unsupportedProvider
        }
        // id is immutable identity — re-anchor the stored record onto
        // the provider-assigned item key via the memberwise init rather
        // than mutating the draft in place.
        let stored = PIMContact(
            id: PIMContact.makeID(
                sourceID: source.id,
                providerItemKey: draft.providerItemKey
            ),
            sourceID: source.id,
            collectionID: draft.collectionID,
            providerItemKey: draft.providerItemKey,
            providerVersion: draft.providerVersion,
            uid: draft.uid,
            displayName: draft.displayName,
            givenName: draft.givenName,
            familyName: draft.familyName,
            nickname: draft.nickname,
            organization: draft.organization,
            jobTitle: draft.jobTitle,
            note: draft.note,
            emails: draft.emails,
            phones: draft.phones,
            addresses: draft.addresses,
            photoURL: draft.photoURL,
            groupKeys: draft.groupKeys,
            rawPayload: draft.rawPayload,
            providerUpdatedAt: draft.providerUpdatedAt,
            syncedAt: now()
        )
        try await store(stored)
        return stored
    }

    // MARK: - Update

    /// Replaces the writable fields of a cached contact under its
    /// stored version precondition. CardDAV merges the model's managed
    /// properties into the stored raw payload so unknown vCard fields
    /// survive; Google scopes the write to an updatePersonFields mask
    /// for the same guarantee. Returns the updated cache record.
    @discardableResult
    public func update(
        _ contact: PIMContact,
        source: PIMSource
    ) async throws -> PIMContact {
        guard canWrite(source: source, collection: nil) else {
            throw WriteError.notWritable
        }
        var updated = contact
        switch source.provider {
        case .google:
            let token = try await googleToken(for: source)
            let result = try await mapGoogleError {
                try await googleWriter.update(
                    updated,
                    accessToken: token
                )
            }
            updated.providerVersion = result.etag
        case .cardDAV:
            let credential = try await davCredential(for: source)
            let vcard = PIMVCardWriter.mergedVCard(
                for: updated,
                revisedAt: now()
            )
            let result = try await mapDAVError {
                try await davWriter.update(
                    updated,
                    vcard: vcard,
                    credential: credential
                )
            }
            updated.providerVersion = result.etag
            updated.rawPayload = vcard
        case .calDAV:
            throw WriteError.unsupportedProvider
        }
        updated.syncedAt = now()
        try await store(updated)
        return updated
    }

    // MARK: - Delete

    /// Deletes a cached contact remotely, then removes it from the
    /// cache. A remote 404 still clears the local record — the desired
    /// end state already held.
    public func delete(
        _ contact: PIMContact,
        source: PIMSource
    ) async throws {
        guard canWrite(source: source, collection: nil) else {
            throw WriteError.notWritable
        }
        switch source.provider {
        case .google:
            let token = try await googleToken(for: source)
            try await mapGoogleError {
                try await googleWriter.delete(
                    contact,
                    accessToken: token
                )
            }
        case .cardDAV:
            let credential = try await davCredential(for: source)
            try await mapDAVError {
                try await davWriter.delete(contact, credential: credential)
            }
        case .calDAV:
            throw WriteError.unsupportedProvider
        }
        var remaining = try await contactStore.contacts(
            for: source.id
        )
        remaining.removeAll { $0.id == contact.id }
        try await contactStore.saveContacts(remaining, for: source.id)
    }

    // MARK: - Cache

    /// Inserts or replaces the record inside the source's cached
    /// contact list — the sync engine owns full-generation saves, so
    /// the write path patches the single record instead.
    private func store(_ contact: PIMContact) async throws {
        var contacts = try await contactStore.contacts(
            for: contact.sourceID
        )
        if let index = contacts.firstIndex(where: {
            $0.id == contact.id
        }) {
            contacts[index] = contact
        } else {
            contacts.append(contact)
        }
        try await contactStore.saveContacts(
            contacts,
            for: contact.sourceID
        )
    }

    // MARK: - Credentials

    private func googleToken(for source: PIMSource) async throws -> String {
        guard let accountID = source.linkedAccountID,
              let googleAccessToken
        else { throw WriteError.missingCredential }
        return try await googleAccessToken(accountID)
    }

    private func davCredential(
        for source: PIMSource
    ) async throws -> CalDAVCredential {
        guard let account = source.credentialAccount,
              let credential = try await credentials.credential(
                  for: account
              )
        else { throw WriteError.missingCredential }
        return credential
    }

    // MARK: - Error mapping

    private func mapGoogleError<T>(
        _ work: () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch let error as GooglePeopleContactWriter.WriteError {
            switch error {
            case .authenticationRequired:
                throw WriteError.authenticationRequired
            case .conflict:
                throw WriteError.conflict
            case .invalidResponse:
                throw WriteError.invalidResponse
            case .transportFailed:
                throw WriteError.transportFailed
            }
        }
    }

    private func mapDAVError<T>(
        _ work: () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch let error as PIMDAVContactWriter.WriteError {
            switch error {
            case .authenticationRequired:
                throw WriteError.authenticationRequired
            case .conflict:
                throw WriteError.conflict
            case .invalidResponse:
                throw WriteError.invalidResponse
            case .transportFailed:
                throw WriteError.transportFailed
            case .invalidCollection:
                throw WriteError.invalidResponse
            }
        }
    }
}
