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

@testable import BrevCalendar
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing

@Suite("PIMContactSync")
struct PIMContactSyncTests {
    // MARK: - Doubles

    /// Returns scripted responses in order and records every request.
    private final class ScriptedTransport: PIMDAVTransport, @unchecked Sendable {
        struct Step {
            let status: Int
            let headers: [String: String]
            let body: Data

            static func response(
                _ status: Int,
                headers: [String: String] = [:],
                body: String = ""
            ) -> Step {
                Step(status: status, headers: headers, body: Data(body.utf8))
            }
        }

        private(set) var requests: [URLRequest] = []
        private var steps: [Step]

        init(steps: [Step]) { self.steps = steps }

        func send(
            _ request: URLRequest
        ) async throws -> (Data, HTTPURLResponse) {
            requests.append(request)
            guard !steps.isEmpty else {
                throw URLError(.cannotConnectToHost)
            }
            let step = steps.removeFirst()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: step.status,
                httpVersion: nil,
                headerFields: step.headers
            )!
            return (step.body, response)
        }
    }

    private actor InMemorySourceStore: PIMSourceStore {
        var records: [PIMSource] = []

        func allSources() async throws -> [PIMSource] { records }

        func save(_ source: PIMSource) async throws {
            if let index = records.firstIndex(where: { $0.id == source.id }) {
                records[index] = source
            } else {
                records.append(source)
            }
        }

        func deleteSource(id: PIMSource.ID) async throws {
            records.removeAll { $0.id == id }
        }
    }

    private actor InMemoryCredentialStore: CalDAVCredentialStore {
        var credentials: [String: CalDAVCredential] = [:]

        func credential(for account: String) async throws -> CalDAVCredential? {
            credentials[account]
        }

        func setCredential(
            _ credential: CalDAVCredential,
            for account: String
        ) async throws {
            credentials[account] = credential
        }

        func deleteCredential(for account: String) async throws {
            credentials[account] = nil
        }
    }

    private actor InMemoryLocalDataStore: PIMSourceLocalDataStore {
        func deleteSyncAndDraftData(for sourceID: PIMSource.ID) async throws {}
        func deleteCachedContent(for sourceID: PIMSource.ID) async throws {}
        func markCacheDisconnected(for sourceID: PIMSource.ID) async throws {}
    }

    private actor InMemoryCollectionStore: PIMCollectionStore {
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

    private actor InMemoryContactStore: PIMContactStore {
        var records: [PIMSource.ID: [PIMContact]] = [:]

        func contacts(for sourceID: PIMSource.ID) async throws -> [PIMContact] {
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

    private actor InMemoryCursorStore: PIMContactSyncCursorStore {
        var records: [String: PIMContactSyncCursor] = [:]

        func cursor(
            for sourceID: PIMSource.ID,
            scope: String
        ) async throws -> PIMContactSyncCursor? {
            records["\(sourceID)|\(scope)"]
        }

        func saveCursor(
            _ cursor: PIMContactSyncCursor,
            for sourceID: PIMSource.ID
        ) async throws {
            records["\(sourceID)|\(cursor.scope)"] = cursor
        }

        func deleteCursor(
            for sourceID: PIMSource.ID,
            scope: String
        ) async throws {
            records["\(sourceID)|\(scope)"] = nil
        }
    }

    // MARK: - Fixtures

    private static func source(
        provider: PIMSourceProvider = .cardDAV,
        status: PIMSourceStatus = .ready
    ) -> PIMSource {
        PIMSource(
            id: "pim-test",
            kind: provider == .calDAV ? .calendar : .contacts,
            provider: provider,
            linkedAccountID: provider == .google ? "acct-1" : nil,
            displayName: "Test",
            endpointURL: provider == .google
                ? nil
                : URL(string: "https://dav.example.com/dav/"),
            credentialAccount: provider == .google ? nil : "pim-source-pim-test",
            status: status
        )
    }

    private static func collection(
        sourceID: PIMSource.ID = "pim-test",
        providerKey: String =
            "https://dav.example.com/addressbooks/henrik/default/",
        isVisible: Bool = true,
        supportsSyncToken: Bool = true
    ) -> PIMCollection {
        PIMCollection(
            id: PIMCollection.makeID(
                sourceID: sourceID,
                providerKey: providerKey
            ),
            sourceID: sourceID,
            kind: .contacts,
            displayName: "Contacts",
            supportsSyncToken: supportsSyncToken,
            providerKey: providerKey,
            isVisible: isVisible
        )
    }

    private static func contact(
        collectionID: PIMCollection.ID?,
        providerItemKey: String,
        displayName: String = "Person",
        etag: String? = nil
    ) -> PIMContact {
        PIMContact(
            id: PIMContact.makeID(
                sourceID: "pim-test",
                providerItemKey: providerItemKey
            ),
            sourceID: "pim-test",
            collectionID: collectionID,
            providerItemKey: providerItemKey,
            providerVersion: etag,
            displayName: displayName
        )
    }

    private static let sampleVCard = """
    BEGIN:VCARD
    VERSION:3.0
    UID:contact-1
    FN:Ada Lovelace
    N:Lovelace;Ada;;;
    NICKNAME:Ada
    ORG:Analytical Engines;Research
    TITLE:Engineer
    EMAIL;TYPE=WORK:ada@example.com
    EMAIL;TYPE=HOME:ada.lovelace@personal.example.com
    TEL;TYPE=CELL:+47 555 0100
    ADR;TYPE=HOME:;;Storgata 1;Oslo;;0155;Norway
    NOTE:First programmer
    CATEGORIES:Work,Friends
    PHOTO;VALUE=URI:https://example.com/ada.jpg
    REV:2026-09-20T09:00:00Z
    END:VCARD
    """

    private static func davSyncBody(
        members: [(href: String, etag: String?, data: String?)],
        removed: [String] = [],
        syncToken: String? = nil
    ) -> String {
        var xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:carddav">
        """
        for member in members {
            xml += """
              <d:response>
                <d:href>\(member.href)</d:href>
                <d:propstat>
                  <d:prop>
                    \(member.etag.map { "<d:getetag>\($0)</d:getetag>" } ?? "")
                    \(member.data.map { "<c:address-data>\($0)</c:address-data>" } ?? "")
                  </d:prop>
                  <d:status>HTTP/1.1 200 OK</d:status>
                </d:propstat>
              </d:response>
            """
        }
        for href in removed {
            xml += """
              <d:response>
                <d:href>\(href)</d:href>
                <d:status>HTTP/1.1 404 Not Found</d:status>
              </d:response>
            """
        }
        if let syncToken {
            xml += "\n  <d:sync-token>\(syncToken)</d:sync-token>"
        }
        xml += "\n</d:multistatus>"
        return xml
    }

    private func makeService(
        source: PIMSource,
        collections: [PIMCollection],
        davTransport: ScriptedTransport,
        googleTransport: ScriptedTransport? = nil,
        contactStore: InMemoryContactStore = InMemoryContactStore(),
        cursorStore: InMemoryCursorStore = InMemoryCursorStore(),
        googleAccessToken: (@Sendable (String) async throws -> String)? = nil
    ) async throws -> (
        PIMContactSyncService, PIMSourceCoordinator, InMemoryContactStore,
        InMemoryCursorStore
    ) {
        let sourceStore = InMemorySourceStore()
        try await sourceStore.save(source)
        let credentials = InMemoryCredentialStore()
        if let account = source.credentialAccount {
            try await credentials.setCredential(
                .bearer(token: "dav-token"),
                for: account
            )
        }
        let coordinator = PIMSourceCoordinator(
            store: sourceStore,
            credentials: credentials,
            localData: InMemoryLocalDataStore()
        )
        let collectionStore = InMemoryCollectionStore()
        try await collectionStore.saveCollections(
            collections,
            for: source.id
        )
        let service = PIMContactSyncService(
            coordinator: coordinator,
            collectionStore: collectionStore,
            contactStore: contactStore,
            cursorStore: cursorStore,
            credentials: credentials,
            googleSync: GooglePeopleContactSync(
                transport: googleTransport
                    ?? ScriptedTransport(steps: [])
            ),
            davSync: PIMDAVContactSync(transport: davTransport),
            googleAccessToken: googleAccessToken,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        return (service, coordinator, contactStore, cursorStore)
    }

    // MARK: - CardDAV sync-collection

    @Test("CardDAV incremental sync applies changes, removals and the new token")
    func davIncrementalSync() async throws {
        let collection = Self.collection()
        let transport = ScriptedTransport(steps: [
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/addressbooks/henrik/default/c1.vcf",
                            "etag-2",
                            Self.sampleVCard
                        )
                    ],
                    removed: ["/addressbooks/henrik/default/gone.vcf"],
                    syncToken: "sync-2"
                )
            )
        ])
        let (service, _, contactStore, cursorStore) = try await makeService(
            source: Self.source(),
            collections: [collection],
            davTransport: transport
        )
        try await contactStore.saveContacts(
            [
                Self.contact(
                    collectionID: collection.id,
                    providerItemKey:
                    "https://dav.example.com/addressbooks/henrik/default/gone.vcf",
                    displayName: "Gone"
                ),
                Self.contact(
                    collectionID: collection.id,
                    providerItemKey:
                    "https://dav.example.com/addressbooks/henrik/default/keep.vcf",
                    displayName: "Keep"
                )
            ],
            for: "pim-test"
        )
        try await cursorStore.saveCursor(
            PIMContactSyncCursor(scope: collection.id, token: "sync-1"),
            for: "pim-test"
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedScopes == 1)
        #expect(summary.failures.isEmpty)
        let contacts = try await contactStore.contacts(for: "pim-test")
        let keys = Set(contacts.map(\.providerItemKey))
        #expect(keys.contains(
            "https://dav.example.com/addressbooks/henrik/default/c1.vcf"
        ))
        #expect(keys.contains(
            "https://dav.example.com/addressbooks/henrik/default/keep.vcf"
        ))
        #expect(!keys.contains(
            "https://dav.example.com/addressbooks/henrik/default/gone.vcf"
        ))
        #expect(
            try await cursorStore.cursor(
                for: "pim-test",
                scope: collection.id
            )?.token == "sync-2"
        )
        // Field fidelity: the vCard mapped onto the shared model.
        let ada = contacts.first {
            $0.providerItemKey.hasSuffix("c1.vcf")
        }
        #expect(ada?.displayName == "Ada Lovelace")
        #expect(ada?.givenName == "Ada")
        #expect(ada?.familyName == "Lovelace")
        #expect(ada?.emails.count == 2)
        #expect(ada?.emails.first?.label == "work")
        #expect(ada?.phones.first?.value == "+47 555 0100")
        #expect(ada?.addresses.first?.city == "Oslo")
        #expect(ada?.organization == "Analytical Engines")
        #expect(ada?.jobTitle == "Engineer")
        #expect(ada?.note == "First programmer")
        #expect(ada?.groupKeys == ["Work", "Friends"])
        #expect(ada?.photoURL == "https://example.com/ada.jpg")
        #expect(ada?.rawPayload?.contains("BEGIN:VCARD") == true)
    }

    @Test("CardDAV member without inline data is fetched by multiget")
    func davMultigetForMissingData() async throws {
        let collection = Self.collection()
        let transport = ScriptedTransport(steps: [
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        ("/addressbooks/henrik/default/c2.vcf", "e2", nil)
                    ],
                    syncToken: "s3"
                )
            ),
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/addressbooks/henrik/default/c2.vcf",
                            "e2",
                            Self.sampleVCard
                        )
                    ]
                )
            )
        ])
        let (service, _, contactStore, _) = try await makeService(
            source: Self.source(),
            collections: [collection],
            davTransport: transport
        )

        _ = try await service.syncNow(sourceID: "pim-test")

        #expect(transport.requests.count == 2)
        let second = String(
            data: transport.requests[1].httpBody ?? Data(),
            encoding: .utf8
        )
        #expect(second?.contains("addressbook-multiget") == true)
        let contacts = try await contactStore.contacts(for: "pim-test")
        #expect(contacts.first?.displayName == "Ada Lovelace")
    }

    @Test("CardDAV fallback diffs ETags and deletes hrefs missing from the listing")
    func davQueryFallback() async throws {
        let collection = Self.collection(supportsSyncToken: false)
        let transport = ScriptedTransport(steps: [
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        ("/addressbooks/henrik/default/keep.vcf", "e1", nil),
                        ("/addressbooks/henrik/default/new.vcf", "e9", nil)
                    ]
                )
            ),
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/addressbooks/henrik/default/new.vcf",
                            "e9",
                            Self.sampleVCard
                        )
                    ]
                )
            )
        ])
        let (service, _, contactStore, _) = try await makeService(
            source: Self.source(),
            collections: [collection],
            davTransport: transport
        )
        try await contactStore.saveContacts(
            [
                Self.contact(
                    collectionID: collection.id,
                    providerItemKey:
                    "https://dav.example.com/addressbooks/henrik/default/keep.vcf",
                    displayName: "Keep",
                    etag: "e1"
                ),
                Self.contact(
                    collectionID: collection.id,
                    providerItemKey:
                    "https://dav.example.com/addressbooks/henrik/default/gone.vcf",
                    displayName: "Gone",
                    etag: "e0"
                )
            ],
            for: "pim-test"
        )

        _ = try await service.syncNow(sourceID: "pim-test")

        let contacts = try await contactStore.contacts(for: "pim-test")
        let byKey = Dictionary(
            uniqueKeysWithValues: contacts.map { ($0.providerItemKey, $0) }
        )
        #expect(byKey[
            "https://dav.example.com/addressbooks/henrik/default/keep.vcf"
        ]?.displayName == "Keep")
        #expect(byKey[
            "https://dav.example.com/addressbooks/henrik/default/new.vcf"
        ]?.displayName == "Ada Lovelace")
        #expect(byKey[
            "https://dav.example.com/addressbooks/henrik/default/gone.vcf"
        ] == nil)
        let query = String(
            data: transport.requests[0].httpBody ?? Data(),
            encoding: .utf8
        )
        #expect(query?.contains("addressbook-query") == true)
    }

    // MARK: - Google People

    private static func personJSON(
        resourceName: String,
        displayName: String = "Person",
        deleted: Bool = false,
        extra: String = ""
    ) -> String {
        if deleted {
            return """
            {"resourceName":"\(resourceName)",
             "metadata":{"deleted":true}}
            """
        }
        return """
        {"resourceName":"\(resourceName)","etag":"et",
         "names":[{"displayName":"\(displayName)","givenName":"\(displayName)",
                   "metadata":{"primary":true}}]
         \(extra)}
        """
    }

    @Test("Google full sync pages, maps fields and stores the sync token")
    func googleFullSync() async throws {
        let page1 = """
        {"connections":[
          \(Self.personJSON(
              resourceName: "people/c1",
              displayName: "Ada Lovelace",
              extra: """
              ,"emailAddresses":[{"value":"ada@example.com","formattedType":"Work"}]
              ,"phoneNumbers":[{"value":"+47 555 0100","formattedType":"Mobile"}]
              ,"organizations":[{"name":"Analytical Engines","title":"Engineer","metadata":{"primary":true}}]
              ,"nicknames":[{"value":"Ada"}]
              ,"biographies":[{"value":"First programmer"}]
              ,"memberships":[{"contactGroupMembership":{"contactGroupResourceName":"contactGroups/myContacts"}}]
              ,"photos":[{"url":"https://example.com/ada.jpg"}]
              ,"metadata":{"sources":[{"updateTime":"2026-09-20T09:00:00Z"}]}
              ,"providerOnlyField":{"nested":true}
              """
          ))
        ],"nextPageToken":"p2"}
        """
        let page2 = """
        {"connections":[
          {"resourceName":"people/c2","metadata":{"deleted":true}},
          \(Self.personJSON(resourceName: "people/c3", displayName: "Grace"))
        ],"nextSyncToken":"tok-9"}
        """
        let transport = ScriptedTransport(steps: [
            .response(200, body: page1),
            .response(200, body: page2)
        ])
        let (service, _, contactStore, cursorStore) = try await makeService(
            source: Self.source(provider: .google),
            collections: [],
            davTransport: ScriptedTransport(steps: []),
            googleTransport: transport,
            googleAccessToken: { _ in "google-token" }
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedScopes == 1)
        let contacts = try await contactStore.contacts(for: "pim-test")
        #expect(contacts.count == 2)
        let ada = contacts.first { $0.providerItemKey == "people/c1" }
        #expect(ada?.displayName == "Ada Lovelace")
        #expect(ada?.emails.first?.value == "ada@example.com")
        #expect(ada?.emails.first?.label == "work")
        #expect(ada?.phones.first?.value == "+47 555 0100")
        #expect(ada?.organization == "Analytical Engines")
        #expect(ada?.jobTitle == "Engineer")
        #expect(ada?.nickname == "Ada")
        #expect(ada?.note == "First programmer")
        #expect(ada?.groupKeys == ["contactGroups/myContacts"])
        #expect(ada?.photoURL == "https://example.com/ada.jpg")
        #expect(ada?.providerUpdatedAt != nil)
        #expect(ada?.rawPayload?.contains("providerOnlyField") == true)
        #expect(
            try await cursorStore.cursor(
                for: "pim-test",
                scope: "pim-test"
            )?.token == "tok-9"
        )
        let query = transport.requests[0].url?.query ?? ""
        #expect(query.contains("requestSyncToken=true"))
        #expect(query.contains("personFields="))
    }

    @Test("Google incremental sends only the sync token and applies tombstones")
    func googleIncremental() async throws {
        let page = """
        {"connections":[
          {"resourceName":"people/c1","metadata":{"deleted":true}},
          \(Self.personJSON(resourceName: "people/c4", displayName: "New"))
        ],"nextSyncToken":"tok-10"}
        """
        let transport = ScriptedTransport(steps: [.response(200, body: page)])
        let (service, _, contactStore, cursorStore) = try await makeService(
            source: Self.source(provider: .google),
            collections: [],
            davTransport: ScriptedTransport(steps: []),
            googleTransport: transport,
            googleAccessToken: { _ in "google-token" }
        )
        try await contactStore.saveContacts(
            [
                Self.contact(
                    collectionID: nil,
                    providerItemKey: "people/c1",
                    displayName: "Old"
                ),
                Self.contact(
                    collectionID: nil,
                    providerItemKey: "people/c2",
                    displayName: "Keep"
                )
            ],
            for: "pim-test"
        )
        try await cursorStore.saveCursor(
            PIMContactSyncCursor(scope: "pim-test", token: "tok-9"),
            for: "pim-test"
        )

        _ = try await service.syncNow(sourceID: "pim-test")

        let query = transport.requests[0].url?.query ?? ""
        #expect(query.contains("syncToken=tok-9"))
        #expect(!query.contains("requestSyncToken"))
        let contacts = try await contactStore.contacts(for: "pim-test")
        let keys = Set(contacts.map(\.providerItemKey))
        #expect(keys == ["people/c2", "people/c4"])
    }

    @Test("Google 410 retries once as a full sync")
    func googleCursorExpired() async throws {
        let page = """
        {"connections":[
          \(Self.personJSON(resourceName: "people/c5", displayName: "Fresh"))
        ],"nextSyncToken":"tok-new"}
        """
        let transport = ScriptedTransport(steps: [
            .response(410),
            .response(200, body: page)
        ])
        let (service, _, contactStore, cursorStore) = try await makeService(
            source: Self.source(provider: .google),
            collections: [],
            davTransport: ScriptedTransport(steps: []),
            googleTransport: transport,
            googleAccessToken: { _ in "google-token" }
        )
        try await cursorStore.saveCursor(
            PIMContactSyncCursor(scope: "pim-test", token: "tok-stale"),
            for: "pim-test"
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedScopes == 1)
        #expect(transport.requests.count == 2)
        let retry = transport.requests[1].url?.query ?? ""
        #expect(retry.contains("requestSyncToken=true"))
        #expect(!retry.contains("syncToken"))
        #expect(
            try await cursorStore.cursor(
                for: "pim-test",
                scope: "pim-test"
            )?.token == "tok-new"
        )
    }

    // MARK: - Service behavior

    @Test("Hidden address books keep their cache but skip the provider")
    func hiddenCollectionSkipped() async throws {
        let visible = Self.collection()
        let hidden = Self.collection(
            providerKey: "https://dav.example.com/addressbooks/henrik/hidden/",
            isVisible: false
        )
        let transport = ScriptedTransport(steps: [
            .response(
                207,
                body: Self.davSyncBody(members: [], syncToken: "s1")
            )
        ])
        let (service, _, _, _) = try await makeService(
            source: Self.source(),
            collections: [visible, hidden],
            davTransport: transport
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedScopes == 1)
        #expect(transport.requests.count == 1)
    }

    @Test("One address book's failure keeps its snapshot and the others commit")
    func failureIsolation() async throws {
        let failing = Self.collection()
        let healthy = Self.collection(
            providerKey: "https://dav.example.com/addressbooks/henrik/home/"
        )
        let transport = ScriptedTransport(steps: [
            .response(500),
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/addressbooks/henrik/home/c1.vcf",
                            "e1",
                            Self.sampleVCard
                        )
                    ],
                    syncToken: "s1"
                )
            )
        ])
        let (service, coordinator, contactStore, _) = try await makeService(
            source: Self.source(),
            collections: [failing, healthy],
            davTransport: transport
        )
        try await contactStore.saveContacts(
            [
                Self.contact(
                    collectionID: failing.id,
                    providerItemKey: "old",
                    displayName: "Prior snapshot"
                )
            ],
            for: "pim-test"
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedScopes == 1)
        #expect(summary.failures.count == 1)
        #expect(summary.failures.first?.scope == failing.id)
        let kept = try await contactStore.contacts(for: "pim-test")
        #expect(kept.contains { $0.displayName == "Prior snapshot" })
        #expect(kept.contains { $0.displayName == "Ada Lovelace" })
        let source = try await coordinator.source(id: "pim-test")
        #expect(source?.status == .ready)
    }

    @Test("Authentication failure marks the source and stops the pass")
    func authFailureStopsSource() async throws {
        let collections = [
            Self.collection(),
            Self.collection(
                providerKey: "https://dav.example.com/addressbooks/henrik/two/"
            )
        ]
        let transport = ScriptedTransport(steps: [.response(401)])
        let (service, coordinator, _, _) = try await makeService(
            source: Self.source(),
            collections: collections,
            davTransport: transport
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedScopes == 0)
        #expect(transport.requests.count == 1)
        let source = try await coordinator.source(id: "pim-test")
        #expect(source?.status == .authenticationRequired)
    }

    @Test("Calendar sources are rejected by the contacts sync engine")
    func calendarSourceRejected() async throws {
        let (service, _, _, _) = try await makeService(
            source: Self.source(provider: .calDAV),
            collections: [],
            davTransport: ScriptedTransport(steps: [])
        )
        await #expect(throws: PIMContactSyncServiceError.self) {
            _ = try await service.syncNow(sourceID: "pim-test")
        }
    }

    @Test("Local search covers names, organizations, emails and phones")
    func localSearch() async throws {
        let (service, _, contactStore, _) = try await makeService(
            source: Self.source(provider: .google),
            collections: [],
            davTransport: ScriptedTransport(steps: []),
            googleTransport: ScriptedTransport(steps: [])
        )
        try await contactStore.saveContacts(
            [
                PIMContact(
                    id: "1",
                    sourceID: "pim-test",
                    providerItemKey: "p1",
                    displayName: "Ada Lovelace",
                    nickname: "Ada",
                    organization: "Analytical Engines",
                    emails: [PIMContactField(value: "ada@example.com")],
                    phones: [PIMContactField(value: "+47 555 0100")]
                ),
                PIMContact(
                    id: "2",
                    sourceID: "pim-test",
                    providerItemKey: "p2",
                    displayName: "Grace Hopper",
                    organization: "Navy"
                )
            ],
            for: "pim-test"
        )

        #expect(
            try await service.searchContacts(
                matching: "ada",
                for: "pim-test"
            ).first?.displayName == "Ada Lovelace"
        )
        #expect(
            try await service.searchContacts(
                matching: "analytical",
                for: "pim-test"
            ).count == 1
        )
        #expect(
            try await service.searchContacts(
                matching: "555 0100",
                for: "pim-test"
            ).count == 1
        )
        #expect(
            try await service.searchContacts(
                matching: "grace",
                for: "pim-test"
            ).count == 1
        )
        #expect(
            try await service.searchContacts(
                matching: "nobody",
                for: "pim-test"
            ).isEmpty
        )
        #expect(
            try await service.searchContacts(
                matching: "  ",
                for: "pim-test"
            ).isEmpty
        )
    }

    // MARK: - Dates, URLs, inline photos

    @Test("CardDAV sync parses dates, URLs and inline photo bytes")
    func davSyncDatesUrlsPhoto() async throws {
        let vcard = """
        BEGIN:VCARD
        VERSION:3.0
        UID:c-dates
        FN:Dated Person
        BDAY:1990-04-12
        X-ABDATE;TYPE=ANNIVERSARY:--06-01
        URL;TYPE=WORK:https://work.example.com
        PHOTO;TYPE=JPEG;ENCODING=b:/9j/4AAQ
        END:VCARD
        """
        let collection = Self.collection()
        let transport = ScriptedTransport(steps: [
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/addressbooks/henrik/default/d.vcf",
                            "e1",
                            vcard
                        )
                    ],
                    syncToken: "s1"
                )
            )
        ])
        let (service, _, contactStore, _) = try await makeService(
            source: Self.source(),
            collections: [collection],
            davTransport: transport
        )

        _ = try await service.syncNow(sourceID: "pim-test")

        let contact = try await contactStore
            .contacts(for: "pim-test").first
        #expect(
            contact?.dates.contains(PIMContactDate(
                label: "birthday",
                year: 1990,
                month: 4,
                day: 12
            )) == true
        )
        #expect(
            contact?.dates.contains(PIMContactDate(
                label: "anniversary",
                year: nil,
                month: 6,
                day: 1
            )) == true
        )
        #expect(
            contact?.urls
                == [PIMContactField(
                    label: "work",
                    value: "https://work.example.com"
                )]
        )
        #expect(
            contact?.photoData == Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        )
    }

    @Test("Google sync maps birthdays, events and urls; requests their fields")
    func googleSyncDatesUrls() async throws {
        let page = """
        {"connections":[
          \(Self.personJSON(
              resourceName: "people/d1",
              displayName: "Dated",
              extra: """
              ,"birthdays":[{"date":{"year":1990,"month":4,"day":12}}]
              ,"events":[{"type":"anniversary","date":{"month":6,"day":1}},
                         {"type":"custom","customType":"Nameday","date":{"year":2020,"month":2,"day":29}}]
              ,"urls":[{"value":"https://h.example.com","formattedType":"Home"}]
              """
          ))
        ],"nextSyncToken":"tok-1"}
        """
        let transport = ScriptedTransport(steps: [.response(200, body: page)])
        let (service, _, contactStore, _) = try await makeService(
            source: Self.source(provider: .google),
            collections: [],
            davTransport: ScriptedTransport(steps: []),
            googleTransport: transport,
            googleAccessToken: { _ in "google-token" }
        )

        _ = try await service.syncNow(sourceID: "pim-test")

        let contact = try await contactStore
            .contacts(for: "pim-test").first
        #expect(
            contact?.dates.contains(PIMContactDate(
                label: "birthday",
                year: 1990,
                month: 4,
                day: 12
            )) == true
        )
        #expect(
            contact?.dates.contains(PIMContactDate(
                label: "anniversary",
                year: nil,
                month: 6,
                day: 1
            )) == true
        )
        #expect(
            contact?.dates.contains(PIMContactDate(
                label: "nameday",
                year: 2020,
                month: 2,
                day: 29
            )) == true
        )
        #expect(
            contact?.urls
                == [PIMContactField(
                    label: "home",
                    value: "https://h.example.com"
                )]
        )
        // The field mask must include them or an update would erase
        // provider-side values the model never saw.
        let query = transport.requests[0].url?.query ?? ""
        #expect(query.contains("birthdays"))
        #expect(query.contains("events"))
        #expect(query.contains("urls"))
    }
}

@Suite("PIMVCardParser")
struct PIMVCardParserTests {
    @Test("Full field coverage maps onto the contact record")
    func fullCard() {
        let vcard = """
        BEGIN:VCARD
        VERSION:3.0
        UID:c1
        FN:Ada Lovelace
        N:Lovelace;Ada;Byron;Dr.;Lady
        NICKNAME:Ada,Enchantress
        ORG:Analytical Engines;Research
        TITLE:Engineer
        EMAIL;TYPE=WORK:ada@example.com
        TEL;TYPE=CELL,VOICE:+47 555 0100
        ADR;TYPE=HOME:;;Storgata 1;Oslo;;0155;Norway
        NOTE:First programmer\\nwith notes
        CATEGORIES:Work, Friends
        PHOTO;VALUE=URI:https://example.com/ada.jpg
        REV:2026-09-20T09:00:00Z
        END:VCARD
        """
        let parsed = PIMVCardParser.parse(vcard)
        #expect(parsed?.displayName == "Ada Lovelace")
        #expect(parsed?.familyName == "Lovelace")
        #expect(parsed?.givenName == "Ada")
        #expect(parsed?.nickname == "Ada")
        #expect(parsed?.organization == "Analytical Engines")
        #expect(parsed?.jobTitle == "Engineer")
        #expect(parsed?.emails.first?.label == "work")
        #expect(parsed?.phones.first?.value == "+47 555 0100")
        #expect(parsed?.addresses.first?.street == "Storgata 1")
        #expect(parsed?.addresses.first?.postalCode == "0155")
        #expect(parsed?.note == "First programmer\nwith notes")
        #expect(parsed?.groupKeys == ["Work", "Friends"])
        #expect(parsed?.photoURL == "https://example.com/ada.jpg")
        #expect(parsed?.revisedAt != nil)
        #expect(parsed?.uid == "c1")
    }

    @Test("Folded lines and group prefixes parse")
    func foldedAndGrouped() {
        let vcard = """
        BEGIN:VCARD
        FN:Long name that was folded acr
         oss two lines
        item1.EMAIL;TYPE=HOME:ada@example.com
        END:VCARD
        """
        let parsed = PIMVCardParser.parse(vcard)
        #expect(parsed?.displayName == "Long name that was folded across two lines")
        #expect(parsed?.emails.first?.value == "ada@example.com")
        #expect(parsed?.emails.first?.label == "home")
    }

    @Test("A card with no identity returns nil")
    func noIdentity() {
        #expect(PIMVCardParser.parse("BEGIN:VCARD\nORG:Solo\nEND:VCARD") == nil)
        #expect(PIMVCardParser.parse("") == nil)
    }

    @Test("N-only cards compose a display name")
    func nOnly() {
        let parsed = PIMVCardParser.parse(
            "BEGIN:VCARD\nN:Hopper;Grace;;;\nEND:VCARD"
        )
        #expect(parsed?.displayName == "Grace Hopper")
    }

    @Test("Non-HTTPS photos and invalid inline payloads are dropped")
    func photoSafety() {
        let inline = PIMVCardParser.parse(
            "BEGIN:VCARD\nFN:A\nPHOTO;ENCODING=b:BASE64DATA\nEND:VCARD"
        )
        #expect(inline?.photoURL == nil)
        #expect(inline?.photoData == nil)
        let insecure = PIMVCardParser.parse(
            "BEGIN:VCARD\nFN:A\nPHOTO;VALUE=URI:http://x.example.com/a.jpg\nEND:VCARD"
        )
        #expect(insecure?.photoURL == nil)
    }

    @Test("Base64 photo padding does not swallow the following property")
    func photoPaddingVsUnfold() {
        // A base64 payload ends in '=' — the quoted-printable soft-break
        // heuristic must not merge the next property into the photo.
        let vcard = """
        BEGIN:VCARD
        FN:A
        PHOTO;ENCODING=b:/9j/4AAQ
        URL:https://after.example.com
        END:VCARD
        """
        let parsed = PIMVCardParser.parse(vcard)
        #expect(parsed?.photoData == Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]))
        #expect(
            parsed?.urls
                == [PIMContactField(value: "https://after.example.com")]
        )
    }
}
