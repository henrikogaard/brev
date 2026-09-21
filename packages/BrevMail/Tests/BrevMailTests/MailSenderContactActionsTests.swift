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
@testable import BrevMail
import Foundation
import Testing

/// Sender-panel contact resolution (#10): exact email match against
/// the shared cache, provenance helpers, and the Add to Contacts
/// draft pre-fill.
@Suite("MailSenderContactActions")
@MainActor
struct MailSenderContactActionsTests {
    private actor SourceStore: PIMSourceStore {
        var records: [PIMSource] = []

        func allSources() async throws -> [PIMSource] { records }

        func save(_ source: PIMSource) async throws {
            records.append(source)
        }

        func deleteSource(id: PIMSource.ID) async throws {}
    }

    private actor CredentialStore: CalDAVCredentialStore {
        func credential(for account: String) async throws -> CalDAVCredential? {
            nil
        }

        func setCredential(
            _ credential: CalDAVCredential,
            for account: String
        ) async throws {}

        func deleteCredential(for account: String) async throws {}
    }

    private actor LocalDataStore: PIMSourceLocalDataStore {
        func deleteSyncAndDraftData(for sourceID: PIMSource.ID) async throws {}
        func deleteCachedContent(for sourceID: PIMSource.ID) async throws {}
        func markCacheDisconnected(for sourceID: PIMSource.ID) async throws {}
    }

    private actor CollectionStore: PIMCollectionStore {
        var records: [PIMSource.ID: [PIMCollection]] = [:]

        func collections(
            for sourceID: PIMSource.ID
        ) async throws -> [PIMCollection] {
            records[sourceID] ?? []
        }

        func saveCollections(
            _ collections: [PIMCollection],
            for sourceID: PIMSource.ID
        ) async throws {
            records[sourceID] = collections
        }

        func deleteCollections(for sourceID: PIMSource.ID) async throws {
            records[sourceID] = nil
        }
    }

    private actor ContactStore: PIMContactStore {
        var records: [PIMSource.ID: [PIMContact]] = [:]

        func contacts(
            for sourceID: PIMSource.ID
        ) async throws -> [PIMContact] {
            records[sourceID] ?? []
        }

        func saveContacts(
            _ contacts: [PIMContact],
            for sourceID: PIMSource.ID
        ) async throws {
            records[sourceID] = contacts
        }

        func deleteContacts(for sourceID: PIMSource.ID) async throws {
            records[sourceID] = nil
        }
    }

    private actor CursorStore: PIMContactSyncCursorStore {
        func cursor(
            for sourceID: PIMSource.ID,
            scope: String
        ) async throws -> PIMContactSyncCursor? { nil }

        func saveCursor(
            _ cursor: PIMContactSyncCursor,
            for sourceID: PIMSource.ID
        ) async throws {}

        func deleteCursor(
            for sourceID: PIMSource.ID,
            scope: String
        ) async throws {}
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func source(id: String) -> PIMSource {
        PIMSource(
            id: id,
            kind: .contacts,
            provider: .google,
            displayName: id,
            enabledCapabilities: [.read, .write],
            status: .ready,
            createdAt: Self.fixedNow,
            updatedAt: Self.fixedNow
        )
    }

    private func contact(
        sourceID: String,
        key: String,
        name: String,
        emails: [String],
        groupKeys: [String] = []
    ) -> PIMContact {
        PIMContact(
            id: PIMContact.makeID(sourceID: sourceID, providerItemKey: key),
            sourceID: sourceID,
            providerItemKey: key,
            displayName: name,
            emails: emails.map { PIMContactField(value: $0) },
            groupKeys: groupKeys,
            syncedAt: Self.fixedNow
        )
    }

    private func makeActions(
        sources: [PIMSource],
        contacts: [PIMSource.ID: [PIMContact]],
        collections: [PIMSource.ID: [PIMCollection]] = [:],
        includeEditing: Bool = false
    ) async throws -> MailSenderContactActions {
        let sourceStore = SourceStore()
        for source in sources {
            try await sourceStore.save(source)
        }
        let coordinator = PIMSourceCoordinator(
            store: sourceStore,
            credentials: CredentialStore(),
            localData: LocalDataStore(),
            now: { Self.fixedNow }
        )
        let contactStore = ContactStore()
        for (sourceID, list) in contacts {
            try await contactStore.saveContacts(list, for: sourceID)
        }
        let collectionStore = CollectionStore()
        for (sourceID, list) in collections {
            try await collectionStore.saveCollections(list, for: sourceID)
        }
        let collectionService = PIMCollectionService(
            coordinator: coordinator,
            store: collectionStore,
            credentials: CredentialStore(),
            now: { Self.fixedNow }
        )
        let syncService = PIMContactSyncService(
            coordinator: coordinator,
            collectionStore: collectionStore,
            contactStore: contactStore,
            cursorStore: CursorStore(),
            credentials: CredentialStore(),
            now: { Self.fixedNow }
        )
        return MailSenderContactActions(
            coordinator: coordinator,
            contactSyncService: syncService,
            collectionService: collectionService,
            editing: includeEditing
                ? ContactsEditingModel(
                    writeService: nil,
                    coordinator: coordinator,
                    collectionService: collectionService
                )
                : nil
        )
    }

    @Test("an exact email match resolves to the cached contact")
    func resolvesExactEmailMatch() async throws {
        let actions = try await makeActions(
            sources: [source(id: "g1")],
            contacts: [
                "g1": [
                    contact(
                        sourceID: "g1",
                        key: "people/c1",
                        name: "Ada Lovelace",
                        emails: ["ada@example.org"]
                    )
                ]
            ]
        )
        await actions.resolve(email: " ADA@example.org ")
        guard case .existing(let contact) = actions.state else {
            Issue.record("expected .existing, got \(actions.state)")
            return
        }
        #expect(contact.displayName == "Ada Lovelace")
        #expect(actions.resolvedEmail == "ADA@example.org")
    }

    @Test("an unknown address resolves to missing")
    func unknownEmailIsMissing() async throws {
        let actions = try await makeActions(
            sources: [source(id: "g1")],
            contacts: [
                "g1": [
                    contact(
                        sourceID: "g1",
                        key: "people/c1",
                        name: "Ada",
                        emails: ["ada@example.org"]
                    )
                ]
            ]
        )
        await actions.resolve(email: "nobody@example.org")
        #expect(actions.state == .missing)
    }

    @Test("no contacts sources resolves to missing, not unavailable")
    func noSourcesIsMissing() async throws {
        let actions = try await makeActions(sources: [], contacts: [:])
        await actions.resolve(email: "a@b.c")
        #expect(actions.state == .missing)
    }

    @Test("no services reports unavailable")
    func noServicesIsUnavailable() async {
        let actions = MailSenderContactActions()
        await actions.resolve(email: "a@b.c")
        #expect(actions.state == .unavailable)
        #expect(actions.isAvailable == false)
    }

    @Test("group names resolve through the collection providerKeys")
    func groupNamesResolve() async throws {
        let actions = try await makeActions(
            sources: [source(id: "g1")],
            contacts: [
                "g1": [
                    contact(
                        sourceID: "g1",
                        key: "people/c1",
                        name: "Ada",
                        emails: ["ada@example.org"],
                        groupKeys: ["contactGroups/friends"]
                    )
                ]
            ],
            collections: [
                "g1": [
                    PIMCollection(
                        id: "g1|contactGroups/friends",
                        sourceID: "g1",
                        kind: .contacts,
                        displayName: "Friends",
                        colorHex: nil,
                        isReadOnly: false,
                        isPrimary: false,
                        supportsSyncToken: false,
                        providerKey: "contactGroups/friends",
                        providerVersion: nil,
                        isVisible: true,
                        updatedAt: Self.fixedNow
                    )
                ]
            ]
        )
        await actions.resolve(email: "ada@example.org")
        guard case .existing(let contact) = actions.state else {
            Issue.record("expected .existing")
            return
        }
        let names = await actions.groupNames(for: contact)
        #expect(names == ["Friends"])
    }

    @Test("the add draft carries the participant email and split name")
    func draftPrefillsParticipant() async throws {
        let actions = try await makeActions(
            sources: [source(id: "g1")],
            contacts: [:],
            includeEditing: true
        )
        let draft = actions.draftForNewContact(
            email: "ada@example.org",
            displayName: "Ada Lovelace"
        )
        #expect(draft.emails.first?.value == "ada@example.org")
        #expect(draft.givenName == "Ada")
        #expect(draft.familyName == "Lovelace")
        #expect(draft.isEditing == false)
    }

    // MARK: - Stateless participant lookup

    @Test("lookup returns the cached contact without touching panel state")
    func lookupIsStateless() async throws {
        let actions = try await makeActions(
            sources: [source(id: "g1")],
            contacts: [
                "g1": [
                    contact(
                        sourceID: "g1",
                        key: "people/c1",
                        name: "Ada Lovelace",
                        emails: ["ada@example.org"]
                    )
                ]
            ]
        )
        // A sender resolution is in flight state; the participant
        // lookup must not overwrite it.
        await actions.resolve(email: "sender@example.org")

        let result = await actions.lookup(email: "ada@example.org")

        guard case .existing(let contact) = result else {
            Issue.record("expected .existing, got \(result)")
            return
        }
        #expect(contact.displayName == "Ada Lovelace")
        #expect(actions.resolvedEmail == "sender@example.org")
        #expect(actions.state == .missing)
    }

    @Test("lookup reports missing and unavailable distinctly")
    func lookupMissAndUnavailable() async throws {
        let actions = try await makeActions(
            sources: [source(id: "g1")],
            contacts: [:]
        )
        #expect(
            await actions.lookup(email: "nobody@example.org") == .missing
        )
        #expect(await actions.lookup(email: "  ") == .unavailable)

        let empty = MailSenderContactActions()
        #expect(
            await empty.lookup(email: "ada@example.org") == .unavailable
        )
    }
}
