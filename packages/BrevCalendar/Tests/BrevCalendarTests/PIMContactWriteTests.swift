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

@Suite("PIMContactWrite")
struct PIMContactWriteTests {
    // MARK: - Doubles

    /// Records requests and answers with scripted status/body pairs.
    private final class ScriptedTransport: @unchecked Sendable {
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

    // MARK: - Fixtures

    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private static func source(
        provider: PIMSourceProvider = .cardDAV,
        write: Bool = true,
        credentialAccount: String? = "dav-acct"
    ) -> PIMSource {
        PIMSource(
            id: "pim-test",
            kind: .contacts,
            provider: provider,
            linkedAccountID: provider == .google ? "acct-1" : nil,
            displayName: "Test",
            credentialAccount: provider == .cardDAV
                ? credentialAccount : nil,
            enabledCapabilities: write ? [.read, .write] : [.read],
            status: .ready,
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
    }

    private static func collection(
        id: String = "book1",
        providerKey: String = "https://dav.example.com/contacts/henrik/book/",
        isReadOnly: Bool = false
    ) -> PIMCollection {
        PIMCollection(
            id: id,
            sourceID: "pim-test",
            kind: .contacts,
            displayName: id,
            colorHex: nil,
            isReadOnly: isReadOnly,
            isPrimary: true,
            supportsSyncToken: true,
            providerKey: providerKey,
            providerVersion: nil,
            isVisible: true,
            updatedAt: fixedNow
        )
    }

    private static func contact(
        providerItemKey: String = "https://dav.example.com/contacts/henrik/book/c-1.vcf",
        etag: String? = "\"v1\"",
        uid: String? = "uid-c@brev",
        rawPayload: String? = nil
    ) -> PIMContact {
        PIMContact(
            id: PIMContact.makeID(
                sourceID: "pim-test",
                providerItemKey: providerItemKey
            ),
            sourceID: "pim-test",
            collectionID: "book1",
            providerItemKey: providerItemKey,
            providerVersion: etag,
            uid: uid,
            displayName: "Henrik Ogard",
            givenName: "Henrik",
            familyName: "Ogard",
            emails: [PIMContactField(label: "work", value: "h@example.com")],
            rawPayload: rawPayload,
            syncedAt: fixedNow
        )
    }

    private func makeService(
        source: PIMSource,
        googleTransport: ScriptedTransport? = nil,
        davTransport: ScriptedTransport? = nil,
        contactStore: InMemoryContactStore = InMemoryContactStore()
    ) async throws -> PIMContactWriteService {
        let sourceStore = InMemorySourceStore()
        try await sourceStore.save(source)
        let coordinator = PIMSourceCoordinator(
            store: sourceStore,
            credentials: InMemoryCredentialStore(),
            localData: InMemoryLocalDataStore(),
            now: { Self.fixedNow }
        )
        let credentials = InMemoryCredentialStore()
        if let account = source.credentialAccount {
            try await credentials.setCredential(
                .basic(username: "u", password: "p"),
                for: account
            )
        }
        return PIMContactWriteService(
            coordinator: coordinator,
            contactStore: contactStore,
            credentials: credentials,
            googleWriter: GooglePeopleContactWriter { request in
                guard let googleTransport else {
                    throw URLError(.cannotConnectToHost)
                }
                return try await googleTransport.send(request)
            },
            davWriter: PIMDAVContactWriter { request in
                guard let davTransport else {
                    throw URLError(.cannotConnectToHost)
                }
                return try await davTransport.send(request)
            },
            googleAccessToken: { _ in "token" },
            now: { Self.fixedNow }
        )
    }

    // MARK: - vCard writer

    @Test("vCard emits structured name, labeled fields, and REV")
    func vcardEmission() {
        var contact = Self.contact()
        contact.nickname = "HK"
        contact.phones = [PIMContactField(label: "cell", value: "+47 999")]
        contact.addresses = [PIMContactAddress(
            label: "home",
            street: "Gate 1",
            city: "Oslo",
            postalCode: "0150",
            country: "Norway"
        )]
        contact.groupKeys = ["Friends"]
        let vcard = PIMVCardWriter.vcard(
            for: contact,
            revisedAt: Self.fixedNow
        )
        #expect(vcard.contains("BEGIN:VCARD"))
        #expect(vcard.contains("VERSION:3.0"))
        #expect(vcard.contains("UID:uid-c@brev"))
        #expect(vcard.contains("FN:Henrik Ogard"))
        #expect(vcard.contains("N:Ogard;Henrik;;;"))
        #expect(vcard.contains("NICKNAME:HK"))
        #expect(vcard.contains("EMAIL;TYPE=work:h@example.com"))
        #expect(vcard.contains("TEL;TYPE=cell:+47 999"))
        #expect(vcard.contains("ADR;TYPE=home:;;Gate 1;Oslo;;0150;Norway"))
        #expect(vcard.contains("CATEGORIES:Friends"))
        #expect(vcard.contains("REV:2027-01-"))
        #expect(vcard.hasSuffix("END:VCARD\r\n"))
    }

    @Test("vCard escapes TEXT separators and folds at 75 octets")
    func vcardEscaping() {
        var contact = Self.contact()
        contact.note = "Line one\nLine two, with; separators \\ and more"
        let vcard = PIMVCardWriter.vcard(
            for: contact,
            revisedAt: Self.fixedNow
        )
        for line in vcard.components(separatedBy: "\r\n") {
            #expect(line.utf8.count <= 75)
        }
        let parsed = PIMVCardParser.parse(vcard)
        #expect(parsed?.note == contact.note)
    }

    @Test("mergedVCard preserves unknown properties and regenerates managed ones")
    func vcardMerge() {
        let raw = [
            "BEGIN:VCARD",
            "VERSION:4.0",
            "UID:uid-c@brev",
            "FN:Old Name",
            "BDAY:1990-04-12",
            "X-SOCIALPROFILE;TYPE=twitter:https://x.com/h",
            "END:VCARD",
        ].joined(separator: "\r\n")
        var contact = Self.contact(rawPayload: raw)
        contact.displayName = "New Name"
        contact.dates = [
            PIMContactDate(
                label: "birthday",
                year: 1990,
                month: 4,
                day: 12
            ),
        ]
        let merged = PIMVCardWriter.mergedVCard(
            for: contact,
            revisedAt: Self.fixedNow
        )
        #expect(merged.contains("VERSION:4.0"))
        // BDAY is managed — regenerated from the model, same value.
        #expect(merged.contains("BDAY:1990-04-12"))
        #expect(merged.contains("X-SOCIALPROFILE;TYPE=twitter:https://x.com/h"))
        #expect(merged.contains("FN:New Name"))
        #expect(!merged.contains("FN:Old Name"))
    }

    // MARK: - Google writer

    @Test("Google create POSTs the mapped person to people:createContact")
    func googleCreate() async throws {
        let transport = ScriptedTransport(steps: [
            .response(200, body: #"{"resourceName":"people/c1","etag":"\"e1\""}"#),
        ])
        let writer = GooglePeopleContactWriter(
            transport: { try await transport.send($0) }
        )
        var contact = Self.contact(providerItemKey: "", etag: nil)
        contact.groupKeys = ["contactGroups/friends", "contactGroups/myContacts"]
        let result = try await writer.create(contact, accessToken: "token")
        #expect(result.resourceName == "people/c1")
        #expect(result.etag == "\"e1\"")
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(
            request.url?.absoluteString
                == "https://people.googleapis.com/v1/people:createContact"
        )
        let body = try #require(request.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let names = try #require(json["names"] as? [[String: Any]])
        #expect(names.first?["givenName"] as? String == "Henrik")
        #expect(names.first?["familyName"] as? String == "Ogard")
        let emails = try #require(json["emailAddresses"] as? [[String: Any]])
        #expect(emails.first?["value"] as? String == "h@example.com")
        #expect(emails.first?["type"] as? String == "work")
        // myContacts is implicit — never sent back.
        let memberships = try #require(
            json["memberships"] as? [[String: Any]]
        )
        #expect(memberships.count == 1)
        #expect(json["etag"] == nil)
    }

    @Test("Google update PATCHes with updatePersonFields and the etag")
    func googleUpdate() async throws {
        let transport = ScriptedTransport(steps: [
            .response(200, body: #"{"resourceName":"people/c1","etag":"\"e2\""}"#),
        ])
        let writer = GooglePeopleContactWriter(
            transport: { try await transport.send($0) }
        )
        let contact = Self.contact(
            providerItemKey: "people/c1",
            etag: "\"e1\""
        )
        let result = try await writer.update(contact, accessToken: "token")
        #expect(result.etag == "\"e2\"")
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PATCH")
        #expect(
            request.url?.absoluteString.contains(
                "people/c1:updateContact?updatePersonFields="
            ) == true
        )
        let body = try #require(request.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["etag"] as? String == "\"e1\"")
        // Photos are never in the writable mask — sync keeps URL refs.
        #expect(
            request.url?.absoluteString.contains("photos") == false
        )
    }

    @Test("Google update maps a 400 FAILED_PRECONDITION to conflict")
    func googleUpdateConflict() async throws {
        let transport = ScriptedTransport(steps: [
            .response(400, body: #"{"error":{"status":"FAILED_PRECONDITION"}}"#),
            .response(400, body: #"{"error":{"status":"INVALID_ARGUMENT"}}"#),
        ])
        let writer = GooglePeopleContactWriter(
            transport: { try await transport.send($0) }
        )
        let contact = Self.contact(providerItemKey: "people/c1")
        await #expect(
            throws: GooglePeopleContactWriter.WriteError.conflict
        ) {
            try await writer.update(contact, accessToken: "token")
        }
        await #expect(
            throws: GooglePeopleContactWriter.WriteError.invalidResponse
        ) {
            try await writer.update(contact, accessToken: "token")
        }
    }

    @Test("Google delete accepts 404")
    func googleDelete() async throws {
        let transport = ScriptedTransport(steps: [.response(404)])
        let writer = GooglePeopleContactWriter(
            transport: { try await transport.send($0) }
        )
        try await writer.delete(
            Self.contact(providerItemKey: "people/c1"),
            accessToken: "token"
        )
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(
            request.url?.absoluteString
                == "https://people.googleapis.com/v1/people/c1:deleteContact"
        )
    }

    // MARK: - CardDAV writer

    @Test("CardDAV create PUTs vCard with If-None-Match to the UID resource")
    func davCreate() async throws {
        let transport = ScriptedTransport(steps: [
            .response(201, headers: ["ETag": "\"dav-1\""]),
        ])
        let writer = PIMDAVContactWriter(
            transport: { try await transport.send($0) }
        )
        let result = try await writer.create(
            Self.contact(),
            vcard: "BEGIN:VCARD\r\nEND:VCARD\r\n",
            in: Self.collection(),
            credential: .basic(username: "u", password: "p")
        )
        #expect(result.etag == "\"dav-1\"")
        #expect(
            result.resourceURL.absoluteString
                == "https://dav.example.com/contacts/henrik/book/uid-c-brev.vcf"
        )
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "*")
        #expect(
            request.value(forHTTPHeaderField: "Content-Type")
                == "text/vcard; charset=utf-8"
        )
    }

    @Test("CardDAV update PUTs to the stored href with If-Match")
    func davUpdate() async throws {
        let transport = ScriptedTransport(steps: [
            .response(200, headers: ["ETag": "\"dav-2\""]),
        ])
        let writer = PIMDAVContactWriter(
            transport: { try await transport.send($0) }
        )
        let result = try await writer.update(
            Self.contact(etag: "\"dav-1\""),
            vcard: "BEGIN:VCARD\r\nEND:VCARD\r\n",
            credential: .basic(username: "u", password: "p")
        )
        #expect(result.etag == "\"dav-2\"")
        let request = try #require(transport.requests.first)
        #expect(
            request.url?.absoluteString
                == "https://dav.example.com/contacts/henrik/book/c-1.vcf"
        )
        #expect(request.value(forHTTPHeaderField: "If-Match") == "\"dav-1\"")
    }

    @Test("CardDAV delete accepts 404 and maps 412 to conflict")
    func davDelete() async throws {
        let transport = ScriptedTransport(steps: [
            .response(404),
            .response(412),
        ])
        let writer = PIMDAVContactWriter(
            transport: { try await transport.send($0) }
        )
        try await writer.delete(
            Self.contact(),
            credential: .basic(username: "u", password: "p")
        )
        await #expect(
            throws: PIMDAVContactWriter.WriteError.conflict
        ) {
            try await writer.delete(
                Self.contact(),
                credential: .basic(username: "u", password: "p")
            )
        }
    }

    // MARK: - Service

    @Test("canWrite gates on kind, capability, provider, and read-only")
    func canWriteGating() async throws {
        let service = try await makeService(source: Self.source())
        #expect(
            service.canWrite(
                source: Self.source(),
                collection: Self.collection()
            )
        )
        #expect(
            !service.canWrite(
                source: Self.source(write: false),
                collection: Self.collection()
            )
        )
        #expect(
            !service.canWrite(
                source: Self.source(),
                collection: Self.collection(isReadOnly: true)
            )
        )
        #expect(
            !service.canWrite(
                source: Self.source(provider: .calDAV),
                collection: Self.collection()
            )
        )
        #expect(
            service.canWrite(
                source: Self.source(provider: .google),
                collection: nil
            )
        )
    }

    @Test("Google create lands the chosen group as a membership and caches")
    func serviceGoogleCreate() async throws {
        let transport = ScriptedTransport(steps: [
            .response(200, body: #"{"resourceName":"people/c9","etag":"\"e9\""}"#),
        ])
        let store = InMemoryContactStore()
        let service = try await makeService(
            source: Self.source(provider: .google),
            googleTransport: transport,
            contactStore: store
        )
        let group = Self.collection(
            id: "friends",
            providerKey: "contactGroups/friends"
        )
        var draft = Self.contact(
            providerItemKey: "draft",
            etag: nil,
            uid: nil
        )
        draft.collectionID = nil
        let saved = try await service.create(
            draft,
            in: group,
            source: Self.source(provider: .google)
        )
        #expect(saved.providerItemKey == "people/c9")
        #expect(saved.groupKeys.contains("contactGroups/friends"))
        #expect(saved.uid?.hasSuffix("@brev") == true)
        let cached = try await store.contacts(for: "pim-test")
        #expect(cached.count == 1)
        #expect(cached.first?.providerItemKey == "people/c9")
    }

    @Test("CardDAV create PUTs and caches the provider identity")
    func serviceDavCreate() async throws {
        let transport = ScriptedTransport(steps: [
            .response(201, headers: ["ETag": "\"dav-9\""]),
        ])
        let store = InMemoryContactStore()
        let service = try await makeService(
            source: Self.source(),
            davTransport: transport,
            contactStore: store
        )
        var draft = Self.contact(
            providerItemKey: "draft",
            etag: nil,
            uid: nil
        )
        let saved = try await service.create(
            draft,
            in: Self.collection(),
            source: Self.source()
        )
        #expect(
            saved.providerItemKey.hasSuffix(".vcf")
        )
        #expect(saved.providerVersion == "\"dav-9\"")
        #expect(saved.collectionID == "book1")
        let request = try #require(transport.requests.first)
        let body = try String(
            decoding: #require(request.httpBody),
            as: UTF8.self
        )
        #expect(body.contains("FN:Henrik Ogard"))
        #expect(body.contains("UID:"))
    }

    @Test("CardDAV update merges into the raw payload and stores the new etag")
    func serviceDavUpdate() async throws {
        let raw = [
            "BEGIN:VCARD",
            "VERSION:4.0",
            "UID:uid-c@brev",
            "FN:Old",
            "BDAY:1990-04-12",
            "END:VCARD",
        ].joined(separator: "\r\n")
        let transport = ScriptedTransport(steps: [
            .response(200, headers: ["ETag": "\"dav-2\""]),
        ])
        let store = InMemoryContactStore()
        try await store.saveContacts(
            [Self.contact(rawPayload: raw)],
            for: "pim-test"
        )
        let service = try await makeService(
            source: Self.source(),
            davTransport: transport,
            contactStore: store
        )
        var edit = Self.contact(rawPayload: raw)
        edit.displayName = "New"
        edit.dates = [
            PIMContactDate(
                label: "birthday",
                year: 1990,
                month: 4,
                day: 12
            ),
        ]
        let saved = try await service.update(edit, source: Self.source())
        #expect(saved.providerVersion == "\"dav-2\"")
        let request = try #require(transport.requests.first)
        let body = try String(
            decoding: #require(request.httpBody),
            as: UTF8.self
        )
        #expect(body.contains("FN:New"))
        #expect(body.contains("BDAY:1990-04-12"))
        #expect(body.contains("VERSION:4.0"))
        // The merged payload becomes the new rawPayload so the next
        // sync still round-trips the unknown fields.
        #expect(saved.rawPayload?.contains("BDAY") == true)
    }

    @Test("delete removes the contact remotely and from the cache")
    func serviceDelete() async throws {
        let transport = ScriptedTransport(steps: [.response(204)])
        let store = InMemoryContactStore()
        try await store.saveContacts([Self.contact()], for: "pim-test")
        let service = try await makeService(
            source: Self.source(),
            davTransport: transport,
            contactStore: store
        )
        try await service.delete(Self.contact(), source: Self.source())
        let cached = try await store.contacts(for: "pim-test")
        #expect(cached.isEmpty)
    }

    @Test("writes on a read-enabled source throw notWritable")
    func serviceReadOnly() async throws {
        let service = try await makeService(
            source: Self.source(write: false)
        )
        await #expect(
            throws: PIMContactWriteService.WriteError.notWritable
        ) {
            try await service.create(
                Self.contact(),
                in: Self.collection(),
                source: Self.source(write: false)
            )
        }
    }

    // MARK: - Photos, dates, URLs

    /// A minimal JPEG header — enough for the writer's media sniffing.
    private static let jpegData = Data([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,
    ])

    @Test("vCard emits inline photo, dates, and URLs")
    func vcardPhotoDatesUrls() {
        var contact = Self.contact()
        contact.photoData = Self.jpegData
        contact.dates = [
            PIMContactDate(
                label: "birthday", year: nil, month: 4, day: 12
            ),
            PIMContactDate(
                label: "anniversary", year: 2015, month: 6, day: 1
            ),
            PIMContactDate(
                label: "nameday", year: 2020, month: 2, day: 29
            ),
        ]
        contact.urls = [
            PIMContactField(label: "home", value: "https://h.example.com"),
        ]
        let vcard = PIMVCardWriter.vcard(
            for: contact,
            revisedAt: Self.fixedNow
        )
        // vCard 3 spelling: TYPE + ENCODING=b, base64 payload folded.
        #expect(vcard.contains("PHOTO;TYPE=JPEG;ENCODING=b:"))
        #expect(vcard.contains("BDAY:--04-12"))
        // v3 has no ANNIVERSARY — it lands as the X-ABDATE extension.
        #expect(vcard.contains("X-ABDATE;TYPE=ANNIVERSARY:2015-06-01"))
        #expect(vcard.contains("X-ABDATE;TYPE=NAMEDAY:2020-02-29"))
        #expect(vcard.contains("URL;TYPE=home:https://h.example.com"))
        // The emitted card parses back with every new field intact.
        let parsed = try? #require(PIMVCardParser.parse(vcard))
        #expect(parsed?.photoData == Self.jpegData)
        #expect(parsed?.dates.count == 3)
        #expect(parsed?.urls.first?.value == "https://h.example.com")
    }

    @Test("vCard emits URI photo when no bytes, nothing when empty")
    func vcardPhotoUriAndAbsent() {
        var byURL = Self.contact()
        byURL.photoURL = "https://example.com/photo.jpg"
        let uriCard = PIMVCardWriter.vcard(
            for: byURL,
            revisedAt: Self.fixedNow
        )
        #expect(uriCard.contains("PHOTO;VALUE=URI:https://example.com/photo.jpg"))
        let plain = PIMVCardWriter.vcard(
            for: Self.contact(),
            revisedAt: Self.fixedNow
        )
        #expect(!plain.contains("PHOTO"))
    }

    @Test("mergedVCard keeps unknown fields while swapping PHOTO bytes")
    func vcardMergePreservesUnknownWithPhoto() {
        let raw = [
            "BEGIN:VCARD",
            "VERSION:4.0",
            "UID:uid-c@brev",
            "FN:Henrik Ogard",
            "PHOTO:https://old.example.com/p.jpg",
            "X-FOO-PARAM;THING=1:kept",
            "END:VCARD",
        ].joined(separator: "\r\n")
        var contact = Self.contact(rawPayload: raw)
        contact.photoData = Self.jpegData
        let merged = PIMVCardWriter.mergedVCard(
            for: contact,
            revisedAt: Self.fixedNow
        )
        #expect(merged.contains("X-FOO-PARAM;THING=1:kept"))
        // v4 spelling: a data-URI photo replaces the old URI reference.
        #expect(
            merged.contains("PHOTO:data:image/jpeg;base64,")
        )
        #expect(!merged.contains("PHOTO:https://old.example.com"))
    }

    @Test("vCard parser reads BDAY, ANNIVERSARY, X-ABDATE, URL, PHOTO")
    func vcardParserNewFields() {
        let raw = [
            "BEGIN:VCARD",
            "VERSION:3.0",
            "FN:Henrik Ogard",
            "BDAY:--04-12",
            "ANNIVERSARY:2015-06-01",
            "X-ABDATE;TYPE=nameday:2020-02-29",
            "URL;TYPE=home:https://h.example.com",
            "PHOTO;TYPE=JPEG;ENCODING=b:"
                + Self.jpegData.base64EncodedString(),
            "END:VCARD",
        ].joined(separator: "\r\n")
        let parsed = try? #require(PIMVCardParser.parse(raw))
        #expect(parsed?.photoData == Self.jpegData)
        #expect(parsed?.dates.count == 3)
        #expect(
            parsed?.dates.contains(PIMContactDate(
                label: "birthday", year: nil, month: 4, day: 12
            )) == true
        )
        #expect(
            parsed?.dates.contains(PIMContactDate(
                label: "anniversary", year: 2015, month: 6, day: 1
            )) == true
        )
        #expect(
            parsed?.dates.contains(PIMContactDate(
                label: "nameday", year: 2020, month: 2, day: 29
            )) == true
        )
        #expect(
            parsed?.urls
                == [PIMContactField(
                    label: "home",
                    value: "https://h.example.com"
                )]
        )
    }

    @Test("Google photo calls hit the dedicated endpoints with bytes")
    func googlePhotoEndpoints() async throws {
        let transport = ScriptedTransport(steps: [
            .response(
                200,
                body: #"{"person":{"resourceName":"people/c1","etag":"\"e2\"","photos":[{"url":"https://lh3.example.com/p.jpg"}]}}"#
            ),
            .response(
                200,
                body: #"{"person":{"resourceName":"people/c1","etag":"\"e3\"","photos":[{"url":"https://www.gstatic.com/default.jpg","default":true}]}}"#
            ),
        ])
        let writer = GooglePeopleContactWriter(
            transport: { try await transport.send($0) }
        )
        let contact = Self.contact(providerItemKey: "people/c1")
        let uploaded = try await writer.updatePhoto(
            contact,
            photoData: Self.jpegData,
            accessToken: "token"
        )
        #expect(uploaded.etag == "\"e2\"")
        #expect(uploaded.photoURL == "https://lh3.example.com/p.jpg")
        let upload = try #require(transport.requests.first)
        #expect(upload.httpMethod == "PATCH")
        #expect(
            upload.url?.absoluteString
                == "https://people.googleapis.com/v1/people/c1:updateContactPhoto"
        )
        let body = try #require(upload.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(
            json["photoBytes"] as? String
                == Self.jpegData.base64EncodedString()
        )
        let removed = try await writer.deletePhoto(
            contact,
            accessToken: "token"
        )
        #expect(removed.etag == "\"e3\"")
        // A default-only photo list resolves to no photo.
        #expect(removed.photoURL == nil)
        let deletion = try #require(transport.requests.last)
        #expect(deletion.httpMethod == "DELETE")
        #expect(
            deletion.url?.absoluteString
                == "https://people.googleapis.com/v1/people/c1:deleteContactPhoto"
        )
    }

    @Test("Google updatePersonFields includes birthdays, events, urls")
    func googleUpdateMaskAndBody() async throws {
        let transport = ScriptedTransport(steps: [
            .response(200, body: #"{"resourceName":"people/c1","etag":"\"e2\""}"#),
        ])
        let writer = GooglePeopleContactWriter(
            transport: { try await transport.send($0) }
        )
        var contact = Self.contact(providerItemKey: "people/c1")
        contact.dates = [
            PIMContactDate(
                label: nil, year: 1990, month: 4, day: 12
            ),
            PIMContactDate(
                label: "anniversary", year: 2015, month: 6, day: 1
            ),
            PIMContactDate(
                label: "Nameday", year: nil, month: 2, day: 29
            ),
        ]
        contact.urls = [
            PIMContactField(label: "home", value: "https://h.example.com"),
        ]
        _ = try await writer.update(contact, accessToken: "token")
        let request = try #require(transport.requests.first)
        let mask = try #require(
            request.url?.absoluteString
        )
        #expect(mask.contains("birthdays"))
        #expect(mask.contains("events"))
        #expect(mask.contains("urls"))
        // Photos never ride the fields mask.
        #expect(!mask.contains("photos"))
        let body = try #require(request.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let birthdays = try #require(
            json["birthdays"] as? [[String: Any]]
        )
        let date = try #require(
            birthdays.first?["date"] as? [String: Any]
        )
        #expect(date["year"] as? Int == 1990)
        #expect(date["month"] as? Int == 4)
        let events = try #require(json["events"] as? [[String: Any]])
        #expect(events.count == 2)
        let anniversary = events.first { $0["type"] as? String == "anniversary" }
        #expect(anniversary != nil)
        let custom = events.first { $0["type"] as? String == "custom" }
        #expect(custom?["customType"] as? String == "Nameday")
        let urls = try #require(json["urls"] as? [[String: Any]])
        #expect(urls.first?["value"] as? String == "https://h.example.com")
        #expect(urls.first?["type"] as? String == "home")
    }

    @Test("service create uploads the picked photo through updateContactPhoto")
    func serviceGoogleCreateWithPhoto() async throws {
        let transport = ScriptedTransport(steps: [
            .response(200, body: #"{"resourceName":"people/c9","etag":"\"e9\""}"#),
            .response(
                200,
                body: #"{"person":{"resourceName":"people/c9","etag":"\"e10\"","photos":[{"url":"https://lh3.example.com/p.jpg"}]}}"#
            ),
        ])
        let store = InMemoryContactStore()
        let service = try await makeService(
            source: Self.source(provider: .google),
            googleTransport: transport,
            contactStore: store
        )
        var draft = Self.contact(
            providerItemKey: "draft",
            etag: nil,
            uid: nil
        )
        draft.collectionID = nil
        draft.photoData = Self.jpegData
        let saved = try await service.create(
            draft,
            in: nil,
            source: Self.source(provider: .google)
        )
        #expect(saved.providerVersion == "\"e10\"")
        #expect(saved.photoURL == "https://lh3.example.com/p.jpg")
        #expect(saved.photoData == Self.jpegData)
        #expect(transport.requests.count == 2)
        #expect(
            transport.requests.last?.url?.absoluteString
                == "https://people.googleapis.com/v1/people/c9:updateContactPhoto"
        )
    }

    @Test("service update replaces and removes photos on Google")
    func serviceGooglePhotoUpdateAndRemoval() async throws {
        let transport = ScriptedTransport(steps: [
            .response(200, body: #"{"resourceName":"people/c1","etag":"\"e2\""}"#),
            .response(
                200,
                body: #"{"person":{"resourceName":"people/c1","etag":"\"e3\"","photos":[{"url":"https://lh3.example.com/new.jpg"}]}}"#
            ),
            .response(200, body: #"{"resourceName":"people/c1","etag":"\"e4\""}"#),
            .response(
                200,
                body: #"{"person":{"resourceName":"people/c1","etag":"\"e5\""}}"#
            ),
        ])
        let store = InMemoryContactStore()
        var stored = Self.contact(providerItemKey: "people/c1")
        stored.photoURL = "https://lh3.example.com/old.jpg"
        try await store.saveContacts([stored], for: "pim-test")
        let service = try await makeService(
            source: Self.source(provider: .google),
            googleTransport: transport,
            contactStore: store
        )
        // Replace: photoData set → updateContact then updateContactPhoto.
        var replacing = stored
        replacing.photoData = Self.jpegData
        let saved = try await service.update(
            replacing,
            source: Self.source(provider: .google)
        )
        #expect(saved.photoURL == "https://lh3.example.com/new.jpg")
        #expect(saved.providerVersion == "\"e3\"")
        #expect(
            transport.requests.last?.url?.absoluteString.contains(
                ":updateContactPhoto"
            ) == true
        )
        // Remove: photo fields cleared on a record that had a photo →
        // updateContact then deleteContactPhoto.
        var removing = saved
        removing.photoData = nil
        removing.photoURL = nil
        let cleared = try await service.update(
            removing,
            source: Self.source(provider: .google)
        )
        #expect(cleared.photoURL == nil)
        #expect(cleared.photoData == nil)
        #expect(cleared.providerVersion == "\"e5\"")
        #expect(
            transport.requests.last?.url?.absoluteString.contains(
                ":deleteContactPhoto"
            ) == true
        )
    }

    @Test("service sends no photo call when a photo-free contact edits")
    func serviceGoogleNoPhotoNoCall() async throws {
        let transport = ScriptedTransport(steps: [
            .response(200, body: #"{"resourceName":"people/c1","etag":"\"e2\""}"#),
        ])
        let store = InMemoryContactStore()
        let stored = Self.contact(providerItemKey: "people/c1")
        try await store.saveContacts([stored], for: "pim-test")
        let service = try await makeService(
            source: Self.source(provider: .google),
            googleTransport: transport,
            contactStore: store
        )
        var edit = stored
        edit.nickname = "HK"
        _ = try await service.update(
            edit,
            source: Self.source(provider: .google)
        )
        // Only the field update — no photo endpoint touched.
        #expect(transport.requests.count == 1)
    }

    @Test("CardDAV service round-trips photo bytes inside the vCard")
    func serviceDavPhotoRoundTrip() async throws {
        let transport = ScriptedTransport(steps: [
            .response(201, headers: ["ETag": "\"dav-1\""]),
            .response(200, headers: ["ETag": "\"dav-2\""]),
        ])
        let store = InMemoryContactStore()
        let service = try await makeService(
            source: Self.source(),
            davTransport: transport,
            contactStore: store
        )
        var draft = Self.contact(
            providerItemKey: "draft",
            etag: nil,
            uid: nil
        )
        draft.photoData = Self.jpegData
        let saved = try await service.create(
            draft,
            in: Self.collection(),
            source: Self.source()
        )
        let createBody = try String(
            decoding: #require(transport.requests.first?.httpBody),
            as: UTF8.self
        )
        #expect(createBody.contains("PHOTO;TYPE=JPEG;ENCODING=b:"))
        #expect(saved.photoData == Self.jpegData)
        // Removing the photo regenerates PHOTO out of the merged card.
        var removing = saved
        removing.rawPayload = saved.rawPayload ?? createBody
        removing.photoData = nil
        removing.photoURL = nil
        _ = try await service.update(
            removing,
            source: Self.source()
        )
        let updateBody = try String(
            decoding: #require(transport.requests.last?.httpBody),
            as: UTF8.self
        )
        #expect(!updateBody.contains("PHOTO"))
        #expect(updateBody.contains("FN:Henrik Ogard"))
    }
}
