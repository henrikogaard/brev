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

@Suite("PIMTaskWrite")
struct PIMTaskWriteTests {
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

    private actor InMemoryTaskStore: PIMTaskStore {
        var records: [String: [PIMTask]] = [:]
        private func key(
            _ sourceID: PIMSource.ID,
            _ collectionID: PIMCollection.ID
        ) -> String { "\(sourceID)|\(collectionID)" }

        func tasks(
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws -> [PIMTask] {
            records[key(sourceID, collectionID)] ?? []
        }

        func tasks(for sourceID: PIMSource.ID) async throws -> [PIMTask] {
            records
                .filter { $0.key.hasPrefix("\(sourceID)|") }
                .flatMap(\.value)
        }

        func saveTasks(
            _ tasks: [PIMTask],
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws {
            records[key(sourceID, collectionID)] = tasks
        }

        func deleteTasks(
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws {
            records[key(sourceID, collectionID)] = nil
        }
    }

    // MARK: - Fixtures

    private static func source(
        provider: PIMSourceProvider = .calDAV,
        write: Bool = true,
        status: PIMSourceStatus = .ready
    ) -> PIMSource {
        PIMSource(
            id: "pim-test",
            kind: provider == .cardDAV ? .contacts : .tasks,
            provider: provider,
            linkedAccountID: provider == .google ? "acct-1" : nil,
            displayName: "Test",
            endpointURL: provider == .google
                ? nil
                : URL(string: "https://dav.example.com/dav/"),
            credentialAccount: provider == .google ? nil : "pim-source-pim-test",
            enabledCapabilities: write ? [.read, .write] : [.read],
            status: status
        )
    }

    private static func collection(
        sourceID: PIMSource.ID = "pim-test",
        providerKey: String = "https://dav.example.com/calendars/henrik/tasks/",
        isReadOnly: Bool = false
    ) -> PIMCollection {
        PIMCollection(
            id: PIMCollection.makeID(
                sourceID: sourceID,
                providerKey: providerKey
            ),
            sourceID: sourceID,
            kind: .tasks,
            displayName: "Tasks",
            isReadOnly: isReadOnly,
            providerKey: providerKey
        )
    }

    private static func task(
        collectionID: PIMCollection.ID,
        providerItemKey: String = "task-1",
        etag: String? = nil,
        uid: String? = nil,
        title: String? = "Buy milk",
        status: PIMTaskStatus = .needsAction
    ) -> PIMTask {
        PIMTask(
            id: PIMTask.makeID(
                collectionID: collectionID,
                providerItemKey: providerItemKey
            ),
            sourceID: "pim-test",
            collectionID: collectionID,
            providerItemKey: providerItemKey,
            providerVersion: etag,
            uid: uid,
            title: title,
            status: status
        )
    }

    private static func makeService(
        sourceStore: InMemorySourceStore,
        collectionStore: InMemoryCollectionStore,
        taskStore: InMemoryTaskStore,
        credentials: InMemoryCredentialStore,
        googleTransport: ScriptedTransport,
        davTransport: ScriptedTransport,
        googleAccessToken: (@Sendable (String) async throws -> String)? = nil
    ) -> PIMTaskWriteService {
        let coordinator = PIMSourceCoordinator(
            store: sourceStore,
            credentials: credentials,
            localData: InMemoryLocalDataStore()
        )
        return PIMTaskWriteService(
            coordinator: coordinator,
            collectionStore: collectionStore,
            taskStore: taskStore,
            credentials: credentials,
            googleWriter: GoogleTaskWriter(
                transport: { try await googleTransport.send($0) }
            ),
            davWriter: PIMDAVTaskWriter(
                transport: { try await davTransport.send($0) }
            ),
            googleAccessToken: googleAccessToken,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    // MARK: - ICS writer

    @Test("VTODO serializes owned fields and escapes text")
    func icsWriterFields() {
        var task = Self.task(
            collectionID: "c1",
            uid: "uid-1@brev",
            title: "Buy, milk; 2%"
        )
        task.notes = "Line one\nLine two"
        task.due = Date(timeIntervalSince1970: 1_800_000_000)
        task.position = "42"
        task.parentKey = "parent-uid-1"
        task.links = ["https://example.com/spec"]
        task.providerUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let ics = PIMTaskICSWriter.vcalendar(
            for: task,
            dtstamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(ics.contains("BEGIN:VTODO"))
        #expect(ics.contains("UID:uid-1@brev"))
        #expect(ics.contains("SUMMARY:Buy\\, milk\\; 2%"))
        #expect(ics.contains("DESCRIPTION:Line one\\nLine two"))
        #expect(ics.contains("DUE:20270115T080000Z"))
        #expect(ics.contains("STATUS:NEEDS-ACTION"))
        #expect(ics.contains("X-APPLE-SORT-ORDER:42"))
        #expect(ics.contains("RELATED-TO;RELTYPE=PARENT:parent-uid-1"))
        #expect(ics.contains("URL:https://example.com/spec"))
        #expect(ics.contains("LAST-MODIFIED:20231114T221320Z"))
        #expect(ics.hasSuffix("\r\n"))
    }

    @Test("Completed tasks emit COMPLETED + PERCENT-COMPLETE:100")
    func icsWriterCompleted() {
        var task = Self.task(
            collectionID: "c1",
            uid: "uid-2@brev",
            status: .completed
        )
        task.completedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let ics = PIMTaskICSWriter.vcalendar(
            for: task,
            dtstamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(ics.contains("STATUS:COMPLETED"))
        #expect(ics.contains("PERCENT-COMPLETE:100"))
        #expect(ics.contains("COMPLETED:20270115T080000Z"))
    }

    @Test("Emitted VTODO round-trips through ICSParser.parseTasks")
    func icsWriterRoundTrip() {
        var task = Self.task(
            collectionID: "c1",
            uid: "uid-3@brev",
            title: "Round trip",
            status: .inProcess
        )
        task.notes = "Notes"
        task.due = Date(timeIntervalSince1970: 1_800_000_000)
        task.position = "7"
        task.parentKey = "parent-uid-3"
        task.links = ["https://example.com/a", "https://example.com/b"]
        let ics = PIMTaskICSWriter.vcalendar(
            for: task,
            dtstamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let parsed = ICSParser.parseTasks(from: ics)
        #expect(parsed.count == 1)
        #expect(parsed.first?.uid == "uid-3@brev")
        #expect(parsed.first?.summary == "Round trip")
        #expect(parsed.first?.description == "Notes")
        #expect(parsed.first?.due == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(parsed.first?.status == "IN-PROCESS")
        #expect(parsed.first?.sortOrder == "7")
        #expect(parsed.first?.parentUID == "parent-uid-3")
        #expect(
            parsed.first?.links
                == ["https://example.com/a", "https://example.com/b"]
        )
    }

    // MARK: - Google writer

    @Test("Google insert POSTs the mapped body to the list tasks URL")
    func googleInsert() async throws {
        let transport = ScriptedTransport(steps: [
            .response(200, body: #"{"id":"g-1","etag":"\"v1\"","position":"00000000000000000001"}"#),
        ])
        let writer = GoogleTaskWriter(
            transport: { try await transport.send($0) }
        )
        var collection = Self.collection(providerKey: "list-1")
        collection.kind = .tasks
        var task = Self.task(collectionID: collection.id, title: "Write spec")
        task.due = Date(timeIntervalSince1970: 1_800_000_000)
        task.notes = "Details"

        let result = try await writer.insert(
            task,
            into: collection,
            accessToken: "token"
        )

        #expect(result.taskID == "g-1")
        #expect(result.etag == "\"v1\"")
        #expect(result.item?.position == "00000000000000000001")
        let request = transport.requests.first
        #expect(request?.httpMethod == "POST")
        #expect(
            request?.url?.absoluteString
                == "https://tasks.googleapis.com/tasks/v1/lists/list-1/tasks"
        )
        let body = request?.httpBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        #expect(body?["title"] as? String == "Write spec")
        #expect(body?["notes"] as? String == "Details")
        #expect(body?["status"] as? String == "needsAction")
        #expect(body?["due"] as? String == "2027-01-15T08:00:00.000Z")
    }

    @Test("Google patch sends If-Match and clears nil fields as null")
    func googlePatch() async throws {
        let transport = ScriptedTransport(steps: [
            .response(200, body: #"{"id":"g-1","etag":"\"v2\""}"#),
        ])
        let writer = GoogleTaskWriter(
            transport: { try await transport.send($0) }
        )
        var collection = Self.collection(providerKey: "list-1")
        collection.kind = .tasks
        let task = Self.task(
            collectionID: collection.id,
            providerItemKey: "g-1",
            etag: "\"v1\""
        )

        _ = try await writer.patch(
            task,
            in: collection,
            accessToken: "token"
        )

        let request = transport.requests.first
        #expect(request?.httpMethod == "PATCH")
        #expect(request?.value(forHTTPHeaderField: "If-Match") == "\"v1\"")
        #expect(
            request?.url?.absoluteString
                == "https://tasks.googleapis.com/tasks/v1/lists/list-1/tasks/g-1"
        )
        let body = request?.httpBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        // Cleared fields ride as JSON null so PATCH removes them.
        #expect(body?["notes"] is NSNull)
        #expect(body?["due"] is NSNull)
    }

    @Test("Google delete treats 404 as already deleted")
    func googleDelete404() async throws {
        let transport = ScriptedTransport(steps: [
            .response(404),
        ])
        let writer = GoogleTaskWriter(
            transport: { try await transport.send($0) }
        )
        var collection = Self.collection(providerKey: "list-1")
        collection.kind = .tasks
        let task = Self.task(
            collectionID: collection.id,
            providerItemKey: "g-1",
            etag: "\"v1\""
        )

        try await writer.delete(task, in: collection, accessToken: "token")

        let request = transport.requests.first
        #expect(request?.httpMethod == "DELETE")
        #expect(request?.value(forHTTPHeaderField: "If-Match") == "\"v1\"")
    }

    @Test("Google move POSTs to the move endpoint with parent/previous")
    func googleMove() async throws {
        let transport = ScriptedTransport(steps: [
            .response(200, body: #"{"id":"g-1","etag":"\"v2\"","position":"00000000000000000002","parent":"g-parent"}"#),
        ])
        let writer = GoogleTaskWriter(
            transport: { try await transport.send($0) }
        )
        var collection = Self.collection(providerKey: "list-1")
        collection.kind = .tasks
        let task = Self.task(
            collectionID: collection.id,
            providerItemKey: "g-1"
        )

        let result = try await writer.move(
            task,
            in: collection,
            parent: "g-parent",
            previous: "g-prev",
            accessToken: "token"
        )

        #expect(result.item?.parent == "g-parent")
        #expect(result.item?.position == "00000000000000000002")
        let request = transport.requests.first
        #expect(request?.httpMethod == "POST")
        let url = request?.url?.absoluteString ?? ""
        #expect(url.contains("/tasks/g-1/move"))
        #expect(url.contains("parent=g-parent"))
        #expect(url.contains("previous=g-prev"))
    }

    @Test("Google 401 maps to authenticationRequired, 412 to conflict")
    func googleErrorMapping() async throws {
        for (status, expected) in [
            (401, GoogleTaskWriter.WriteError.authenticationRequired),
            (403, GoogleTaskWriter.WriteError.authenticationRequired),
            (412, GoogleTaskWriter.WriteError.conflict),
            (500, GoogleTaskWriter.WriteError.invalidResponse),
        ] {
            let transport = ScriptedTransport(steps: [.response(status)])
            let writer = GoogleTaskWriter(
                transport: { try await transport.send($0) }
            )
            var collection = Self.collection(providerKey: "list-1")
            collection.kind = .tasks
            let task = Self.task(collectionID: collection.id)
            do {
                _ = try await writer.patch(
                    task,
                    in: collection,
                    accessToken: "token"
                )
                Issue.record("expected \(expected) for status \(status)")
            } catch let error as GoogleTaskWriter.WriteError {
                #expect(error == expected)
            }
        }
    }

    // MARK: - DAV writer

    @Test("DAV create PUTs VTODO with If-None-Match at the uid URL")
    func davCreate() async throws {
        let transport = ScriptedTransport(steps: [
            .response(201, headers: ["ETag": "\"e1\""]),
        ])
        let writer = PIMDAVTaskWriter(
            transport: { try await transport.send($0) }
        )
        let collection = Self.collection()
        let task = Self.task(
            collectionID: collection.id,
            uid: "uid-dav-1@brev"
        )
        let ics = PIMTaskICSWriter.vcalendar(for: task)

        let result = try await writer.create(
            task,
            ics: ics,
            in: collection,
            credential: .bearer(token: "pw")
        )

        #expect(result.etag == "\"e1\"")
        #expect(
            result.resourceURL.absoluteString
                == "https://dav.example.com/calendars/henrik/tasks/uid-dav-1-brev.ics"
        )
        let request = transport.requests.first
        #expect(request?.httpMethod == "PUT")
        #expect(request?.value(forHTTPHeaderField: "If-None-Match") == "*")
        #expect(
            request?.value(forHTTPHeaderField: "Content-Type")
                == "text/calendar; charset=utf-8"
        )
    }

    @Test("DAV update PUTs to the stored href with If-Match")
    func davUpdate() async throws {
        let transport = ScriptedTransport(steps: [
            .response(200, headers: ["ETag": "\"e2\""]),
        ])
        let writer = PIMDAVTaskWriter(
            transport: { try await transport.send($0) }
        )
        let collection = Self.collection()
        let task = Self.task(
            collectionID: collection.id,
            providerItemKey:
            "https://dav.example.com/calendars/henrik/tasks/t1.ics",
            etag: "\"e1\"",
            uid: "uid-dav-2@brev"
        )

        let result = try await writer.update(
            task,
            ics: PIMTaskICSWriter.vcalendar(for: task),
            in: collection,
            credential: .bearer(token: "pw")
        )

        #expect(result.etag == "\"e2\"")
        let request = transport.requests.first
        #expect(request?.httpMethod == "PUT")
        #expect(request?.value(forHTTPHeaderField: "If-Match") == "\"e1\"")
        #expect(
            request?.url?.absoluteString
                == "https://dav.example.com/calendars/henrik/tasks/t1.ics"
        )
    }

    @Test("DAV delete targets the stored href and accepts 404")
    func davDelete() async throws {
        let transport = ScriptedTransport(steps: [.response(404)])
        let writer = PIMDAVTaskWriter(
            transport: { try await transport.send($0) }
        )
        let collection = Self.collection()
        let task = Self.task(
            collectionID: collection.id,
            providerItemKey:
            "https://dav.example.com/calendars/henrik/tasks/t1.ics",
            etag: "\"e1\""
        )

        try await writer.delete(
            task,
            in: collection,
            credential: .bearer(token: "pw")
        )

        let request = transport.requests.first
        #expect(request?.httpMethod == "DELETE")
        #expect(request?.value(forHTTPHeaderField: "If-Match") == "\"e1\"")
    }

    // MARK: - Service: capability gating

    @Test("Writes refuse sources without the write capability")
    func serviceNotWritableWithoutCapability() async throws {
        let sourceStore = InMemorySourceStore()
        let collectionStore = InMemoryCollectionStore()
        let taskStore = InMemoryTaskStore()
        let credentials = InMemoryCredentialStore()
        let source = Self.source(write: false)
        try await sourceStore.save(source)
        let collection = Self.collection()
        try await collectionStore.saveCollections(
            [collection],
            for: source.id
        )
        try await credentials.setCredential(
            CalDAVCredential.bearer(token: "pw"),
            for: "pim-source-pim-test"
        )
        let service = Self.makeService(
            sourceStore: sourceStore,
            collectionStore: collectionStore,
            taskStore: taskStore,
            credentials: credentials,
            googleTransport: ScriptedTransport(steps: []),
            davTransport: ScriptedTransport(steps: [])
        )

        do {
            _ = try await service.create(
                Self.task(collectionID: collection.id),
                in: collection,
                source: source
            )
            Issue.record("expected notWritable")
        } catch let error as PIMTaskWriteService.WriteError {
            #expect(error == .notWritable)
        }
        let writable = try await service.writableCollections(
            for: source.id
        )
        #expect(writable.isEmpty)
    }

    @Test("Writes refuse read-only collections and CardDAV sources")
    func serviceNotWritableCollectionAndProvider() async throws {
        let sourceStore = InMemorySourceStore()
        let collectionStore = InMemoryCollectionStore()
        let taskStore = InMemoryTaskStore()
        let credentials = InMemoryCredentialStore()
        let source = Self.source()
        try await sourceStore.save(source)
        let readOnly = Self.collection(isReadOnly: true)
        try await collectionStore.saveCollections(
            [readOnly],
            for: source.id
        )
        let cardSource = Self.source(provider: .cardDAV)
        let service = Self.makeService(
            sourceStore: sourceStore,
            collectionStore: collectionStore,
            taskStore: taskStore,
            credentials: credentials,
            googleTransport: ScriptedTransport(steps: []),
            davTransport: ScriptedTransport(steps: [])
        )

        #expect(
            !service.canWrite(source: source, collection: readOnly)
        )
        #expect(
            !service.canWrite(source: cardSource, collection: readOnly)
        )
    }

    // MARK: - Service: Google writes

    @Test("Google create stores the provider-assigned record")
    func serviceGoogleCreate() async throws {
        let sourceStore = InMemorySourceStore()
        let collectionStore = InMemoryCollectionStore()
        let taskStore = InMemoryTaskStore()
        let credentials = InMemoryCredentialStore()
        let source = Self.source(provider: .google)
        try await sourceStore.save(source)
        var collection = Self.collection(providerKey: "list-1")
        collection.kind = .tasks
        try await collectionStore.saveCollections(
            [collection],
            for: source.id
        )
        let transport = ScriptedTransport(steps: [
            .response(
                200,
                body: #"{"id":"g-9","etag":"\"v1\"","position":"00000000000000000001"}"#
            ),
        ])
        let service = Self.makeService(
            sourceStore: sourceStore,
            collectionStore: collectionStore,
            taskStore: taskStore,
            credentials: credentials,
            googleTransport: transport,
            davTransport: ScriptedTransport(steps: []),
            googleAccessToken: { _ in "token" }
        )

        let stored = try await service.create(
            Self.task(collectionID: collection.id, title: "New"),
            in: collection,
            source: source
        )

        #expect(stored.providerItemKey == "g-9")
        #expect(stored.providerVersion == "\"v1\"")
        #expect(stored.position == "00000000000000000001")
        let cached = try await taskStore.tasks(
            for: source.id,
            collectionID: collection.id
        )
        #expect(cached.count == 1)
        #expect(cached.first?.providerItemKey == "g-9")
    }

    @Test("Google create without a token provider fails as missingCredential")
    func serviceGoogleMissingCredential() async throws {
        let sourceStore = InMemorySourceStore()
        let collectionStore = InMemoryCollectionStore()
        let taskStore = InMemoryTaskStore()
        let credentials = InMemoryCredentialStore()
        let source = Self.source(provider: .google)
        var collection = Self.collection(providerKey: "list-1")
        collection.kind = .tasks
        let service = Self.makeService(
            sourceStore: sourceStore,
            collectionStore: collectionStore,
            taskStore: taskStore,
            credentials: credentials,
            googleTransport: ScriptedTransport(steps: []),
            davTransport: ScriptedTransport(steps: [])
        )

        do {
            _ = try await service.create(
                Self.task(collectionID: collection.id),
                in: collection,
                source: source
            )
            Issue.record("expected missingCredential")
        } catch let error as PIMTaskWriteService.WriteError {
            #expect(error == .missingCredential)
        }
    }

    // MARK: - Service: DAV writes

    @Test("DAV create generates a UID and stores the resource href")
    func serviceDAVCreate() async throws {
        let sourceStore = InMemorySourceStore()
        let collectionStore = InMemoryCollectionStore()
        let taskStore = InMemoryTaskStore()
        let credentials = InMemoryCredentialStore()
        let source = Self.source()
        try await sourceStore.save(source)
        let collection = Self.collection()
        try await collectionStore.saveCollections(
            [collection],
            for: source.id
        )
        try await credentials.setCredential(
            CalDAVCredential.bearer(token: "pw"),
            for: "pim-source-pim-test"
        )
        let transport = ScriptedTransport(steps: [
            .response(201, headers: ["ETag": "\"e1\""]),
        ])
        let service = Self.makeService(
            sourceStore: sourceStore,
            collectionStore: collectionStore,
            taskStore: taskStore,
            credentials: credentials,
            googleTransport: ScriptedTransport(steps: []),
            davTransport: transport
        )

        let stored = try await service.create(
            Self.task(collectionID: collection.id, title: "New"),
            in: collection,
            source: source
        )

        #expect(stored.uid != nil)
        #expect(stored.uid?.hasSuffix("@brev") == true)
        #expect(stored.providerItemKey.hasPrefix(collection.providerKey))
        #expect(stored.providerItemKey.hasSuffix(".ics"))
        #expect(stored.providerVersion == "\"e1\"")
        let body = transport.requests.first?.httpBody.flatMap {
            String(data: $0, encoding: .utf8)
        }
        #expect(body?.contains("BEGIN:VTODO") == true)
        #expect(body?.contains("SUMMARY:New") == true)
    }

    @Test("DAV delete removes the cached record")
    func serviceDAVDelete() async throws {
        let sourceStore = InMemorySourceStore()
        let collectionStore = InMemoryCollectionStore()
        let taskStore = InMemoryTaskStore()
        let credentials = InMemoryCredentialStore()
        let source = Self.source()
        try await sourceStore.save(source)
        let collection = Self.collection()
        let task = Self.task(
            collectionID: collection.id,
            providerItemKey:
            "https://dav.example.com/calendars/henrik/tasks/t1.ics",
            etag: "\"e1\""
        )
        try await taskStore.saveTasks(
            [task],
            for: source.id,
            collectionID: collection.id
        )
        try await credentials.setCredential(
            CalDAVCredential.bearer(token: "pw"),
            for: "pim-source-pim-test"
        )
        let transport = ScriptedTransport(steps: [.response(204)])
        let service = Self.makeService(
            sourceStore: sourceStore,
            collectionStore: collectionStore,
            taskStore: taskStore,
            credentials: credentials,
            googleTransport: ScriptedTransport(steps: []),
            davTransport: transport
        )

        try await service.delete(task, in: collection, source: source)

        let cached = try await taskStore.tasks(
            for: source.id,
            collectionID: collection.id
        )
        #expect(cached.isEmpty)
    }

    // MARK: - Service: cross-collection move

    @Test("Cross-collection move creates in the target then deletes the origin")
    func serviceCrossCollectionMove() async throws {
        let sourceStore = InMemorySourceStore()
        let collectionStore = InMemoryCollectionStore()
        let taskStore = InMemoryTaskStore()
        let credentials = InMemoryCredentialStore()
        let source = Self.source(provider: .google)
        try await sourceStore.save(source)
        var origin = Self.collection(providerKey: "list-a")
        origin.kind = .tasks
        var target = Self.collection(providerKey: "list-b")
        target.kind = .tasks
        let task = Self.task(
            collectionID: origin.id,
            providerItemKey: "g-1",
            etag: "\"v1\"",
            title: "Move me"
        )
        try await taskStore.saveTasks(
            [task],
            for: source.id,
            collectionID: origin.id
        )
        let transport = ScriptedTransport(steps: [
            .response(200, body: #"{"id":"g-2","etag":"\"v1\""}"#),
            .response(204),
        ])
        let service = Self.makeService(
            sourceStore: sourceStore,
            collectionStore: collectionStore,
            taskStore: taskStore,
            credentials: credentials,
            googleTransport: transport,
            davTransport: ScriptedTransport(steps: []),
            googleAccessToken: { _ in "token" }
        )

        let moved = try await service.move(
            task,
            to: target,
            in: origin,
            source: source
        )

        #expect(moved.providerItemKey == "g-2")
        #expect(moved.collectionID == target.id)
        // Create landed in the target list; the origin list is empty.
        let targetCached = try await taskStore.tasks(
            for: source.id,
            collectionID: target.id
        )
        let originCached = try await taskStore.tasks(
            for: source.id,
            collectionID: origin.id
        )
        #expect(targetCached.count == 1)
        #expect(originCached.isEmpty)
        // Insert then delete, in that order.
        #expect(transport.requests.count == 2)
        #expect(transport.requests[0].httpMethod == "POST")
        #expect(
            transport.requests[0].url?.absoluteString
                == "https://tasks.googleapis.com/tasks/v1/lists/list-b/tasks"
        )
        #expect(transport.requests[1].httpMethod == "DELETE")
    }

    @Test("Cross-collection move into a read-only list refuses")
    func serviceCrossCollectionMoveReadOnly() async throws {
        let sourceStore = InMemorySourceStore()
        let collectionStore = InMemoryCollectionStore()
        let taskStore = InMemoryTaskStore()
        let credentials = InMemoryCredentialStore()
        let source = Self.source(provider: .google)
        var origin = Self.collection(providerKey: "list-a")
        origin.kind = .tasks
        var target = Self.collection(
            providerKey: "list-b",
            isReadOnly: true
        )
        target.kind = .tasks
        let task = Self.task(
            collectionID: origin.id,
            providerItemKey: "g-1"
        )
        let service = Self.makeService(
            sourceStore: sourceStore,
            collectionStore: collectionStore,
            taskStore: taskStore,
            credentials: credentials,
            googleTransport: ScriptedTransport(steps: []),
            davTransport: ScriptedTransport(steps: []),
            googleAccessToken: { _ in "token" }
        )

        do {
            _ = try await service.move(
                task,
                to: target,
                in: origin,
                source: source
            )
            Issue.record("expected notWritable")
        } catch let error as PIMTaskWriteService.WriteError {
            #expect(error == .notWritable)
        }
    }

    @Test("In-list move routes Google through tasks.move")
    func serviceInListMoveGoogle() async throws {
        let sourceStore = InMemorySourceStore()
        let collectionStore = InMemoryCollectionStore()
        let taskStore = InMemoryTaskStore()
        let credentials = InMemoryCredentialStore()
        let source = Self.source(provider: .google)
        var collection = Self.collection(providerKey: "list-1")
        collection.kind = .tasks
        let task = Self.task(
            collectionID: collection.id,
            providerItemKey: "g-1",
            etag: "\"v1\""
        )
        try await taskStore.saveTasks(
            [task],
            for: source.id,
            collectionID: collection.id
        )
        let transport = ScriptedTransport(steps: [
            .response(
                200,
                body: #"{"id":"g-1","etag":"\"v2\"","position":"00000000000000000003","parent":"g-p"}"#
            ),
        ])
        let service = Self.makeService(
            sourceStore: sourceStore,
            collectionStore: collectionStore,
            taskStore: taskStore,
            credentials: credentials,
            googleTransport: transport,
            davTransport: ScriptedTransport(steps: []),
            googleAccessToken: { _ in "token" }
        )

        let moved = try await service.move(
            task,
            in: collection,
            source: source,
            parent: "g-p",
            previous: nil
        )

        #expect(moved.providerVersion == "\"v2\"")
        #expect(moved.parentKey == "g-p")
        #expect(moved.position == "00000000000000000003")
        #expect(
            transport.requests.first?.url?.absoluteString
                .contains("/tasks/g-1/move") == true
        )
        let cached = try await taskStore.tasks(
            for: source.id,
            collectionID: collection.id
        )
        #expect(cached.first?.parentKey == "g-p")
    }
}
