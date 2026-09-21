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
@testable import BrevMail
import Foundation
import Testing

/// Compose autocomplete over the shared PIM contact cache (#10):
/// every contacts source is searched, results carry the source's
/// display name for provenance, and the fallback provider still runs.
@Suite("PIMContactLookupAdapter")
struct PIMContactLookupAdapterTests {
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
        func collections(
            for sourceID: PIMSource.ID
        ) async throws -> [PIMCollection] { [] }

        func saveCollections(
            _ collections: [PIMCollection],
            for sourceID: PIMSource.ID
        ) async throws {}

        func deleteCollections(for sourceID: PIMSource.ID) async throws {}
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

    private final class FallbackLookup: ContactLookupProviding,
        @unchecked Sendable {
        private(set) var queries: [ContactLookupQuery] = []
        var results: [ContactLookupResult] = []

        func contacts(
            matching query: ContactLookupQuery
        ) async throws -> [ContactLookupResult] {
            queries.append(query)
            return results
        }
    }

    private static let mailSourceID = MailSourceID(
        accountID: "acct-1",
        mailboxID: "acct-1"
    )

    private func source(id: String, name: String) -> PIMSource {
        PIMSource(
            id: id,
            kind: .contacts,
            provider: .google,
            displayName: name,
            status: .ready
        )
    }

    private func contact(
        sourceID: String,
        key: String,
        name: String,
        emails: [String]
    ) -> PIMContact {
        PIMContact(
            id: PIMContact.makeID(sourceID: sourceID, providerItemKey: key),
            sourceID: sourceID,
            providerItemKey: key,
            displayName: name,
            emails: emails.map { PIMContactField(value: $0) }
        )
    }

    private func makeAdapter(
        sources: [PIMSource],
        contacts: [PIMSource.ID: [PIMContact]],
        fallback: FallbackLookup? = nil
    ) async throws -> PIMContactLookupAdapter {
        let sourceStore = SourceStore()
        for source in sources {
            try await sourceStore.save(source)
        }
        let coordinator = PIMSourceCoordinator(
            store: sourceStore,
            credentials: CredentialStore(),
            localData: LocalDataStore()
        )
        let contactStore = ContactStore()
        for (sourceID, list) in contacts {
            try await contactStore.saveContacts(list, for: sourceID)
        }
        let syncService = PIMContactSyncService(
            coordinator: coordinator,
            collectionStore: CollectionStore(),
            contactStore: contactStore,
            cursorStore: CursorStore(),
            credentials: CredentialStore()
        )
        return PIMContactLookupAdapter(
            coordinator: coordinator,
            syncService: syncService,
            fallback: fallback
        )
    }

    @Test("matches across every contacts source carry the source name")
    func matchesAcrossSources() async throws {
        let adapter = try await makeAdapter(
            sources: [
                source(id: "g1", name: "Google Contacts"),
                source(id: "d1", name: "CardDAV Book")
            ],
            contacts: [
                "g1": [
                    contact(
                        sourceID: "g1",
                        key: "people/c1",
                        name: "Ada Lovelace",
                        emails: ["ada@example.org"]
                    )
                ],
                "d1": [
                    contact(
                        sourceID: "d1",
                        key: "/book/ada.vcf",
                        name: "Ada L.",
                        emails: ["ada@work.example"]
                    )
                ]
            ]
        )
        let results = try await adapter.contacts(
            matching: ContactLookupQuery(
                text: "ada",
                sourceID: Self.mailSourceID
            )
        )
        #expect(results.count == 2)
        #expect(
            Set(results.map(\.sourceLabel))
                == ["Google Contacts", "CardDAV Book"]
        )
        #expect(
            Set(results.map(\.email))
                == ["ada@example.org", "ada@work.example"]
        )
    }

    @Test("a source with no contacts kind is skipped")
    func skipsNonContactsSources() async throws {
        let calendarSource = PIMSource(
            id: "cal1",
            kind: .calendar,
            provider: .calDAV,
            displayName: "Cal",
            status: .ready
        )
        let adapter = try await makeAdapter(
            sources: [calendarSource],
            contacts: [:]
        )
        let results = try await adapter.contacts(
            matching: ContactLookupQuery(
                text: "ada",
                sourceID: Self.mailSourceID
            )
        )
        #expect(results.isEmpty)
    }

    @Test("the fallback provider still runs and appends its results")
    func fallbackAppends() async throws {
        let fallback = FallbackLookup()
        fallback.results = [
            ContactLookupResult(
                id: "legacy-1",
                displayName: "Legacy Ada",
                email: "ada@legacy.example",
                sourceID: Self.mailSourceID
            )
        ]
        let adapter = try await makeAdapter(
            sources: [source(id: "g1", name: "Google Contacts")],
            contacts: [
                "g1": [
                    contact(
                        sourceID: "g1",
                        key: "people/c1",
                        name: "Ada Lovelace",
                        emails: ["ada@example.org"]
                    )
                ]
            ],
            fallback: fallback
        )
        let results = try await adapter.contacts(
            matching: ContactLookupQuery(
                text: "ada",
                sourceID: Self.mailSourceID
            )
        )
        #expect(fallback.queries.count == 1)
        #expect(results.count == 2)
        #expect(results.last?.email == "ada@legacy.example")
    }
}
