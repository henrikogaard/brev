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

@Suite("PIMTaskSync")
struct PIMTaskSyncTests {
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

    private actor InMemoryCursorStore: PIMSyncCursorStore {
        var records: [String: PIMSyncCursor] = [:]
        private func key(
            _ sourceID: PIMSource.ID,
            _ collectionID: PIMCollection.ID
        ) -> String { "\(sourceID)|\(collectionID)" }

        func cursor(
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws -> PIMSyncCursor? {
            records[key(sourceID, collectionID)]
        }

        func saveCursor(
            _ cursor: PIMSyncCursor,
            for sourceID: PIMSource.ID
        ) async throws {
            records[key(sourceID, cursor.collectionID)] = cursor
        }

        func deleteCursor(
            for sourceID: PIMSource.ID,
            collectionID: PIMCollection.ID
        ) async throws {
            records[key(sourceID, collectionID)] = nil
        }
    }

    // MARK: - Fixtures

    private static func source(
        provider: PIMSourceProvider = .calDAV,
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
            status: status
        )
    }

    private static func collection(
        sourceID: PIMSource.ID = "pim-test",
        providerKey: String = "https://dav.example.com/calendars/henrik/tasks/",
        isVisible: Bool = true,
        supportsSyncToken: Bool = true
    ) -> PIMCollection {
        PIMCollection(
            id: PIMCollection.makeID(
                sourceID: sourceID,
                providerKey: providerKey
            ),
            sourceID: sourceID,
            kind: .tasks,
            displayName: "Tasks",
            supportsSyncToken: supportsSyncToken,
            providerKey: providerKey,
            isVisible: isVisible
        )
    }

    private static func task(
        collectionID: PIMCollection.ID,
        providerItemKey: String,
        title: String = "Task",
        etag: String? = nil
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
            title: title
        )
    }

    private static let sampleVTodo = """
    BEGIN:VCALENDAR
    VERSION:2.0
    BEGIN:VTODO
    UID:task-1@example.com
    SUMMARY:Buy milk
    DESCRIPTION:Oat, not dairy
    DUE:20260925T170000Z
    STATUS:NEEDS-ACTION
    PERCENT-COMPLETE:40
    X-APPLE-SORT-ORDER:1000
    RELATED-TO;RELTYPE=PARENT:task-0@example.com
    URL:https://example.com/list
    LAST-MODIFIED:20260920T090000Z
    BEGIN:VALARM
    TRIGGER:-PT30M
    END:VALARM
    END:VTODO
    END:VCALENDAR
    """

    private static func davSyncBody(
        members: [(href: String, etag: String?, data: String?)],
        removed: [String] = [],
        syncToken: String? = nil
    ) -> String {
        var xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
        """
        for member in members {
            xml += """
              <d:response>
                <d:href>\(member.href)</d:href>
                <d:propstat>
                  <d:prop>
                    \(member.etag.map { "<d:getetag>\($0)</d:getetag>" } ?? "")
                    \(member.data.map { "<c:calendar-data>\($0)</c:calendar-data>" } ?? "")
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
        taskStore: InMemoryTaskStore = InMemoryTaskStore(),
        cursorStore: InMemoryCursorStore = InMemoryCursorStore(),
        googleAccessToken: (@Sendable (String) async throws -> String)? = nil
    ) async throws -> (
        PIMTaskSyncService, PIMSourceCoordinator, InMemoryTaskStore,
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
        let service = PIMTaskSyncService(
            coordinator: coordinator,
            collectionStore: collectionStore,
            taskStore: taskStore,
            cursorStore: cursorStore,
            credentials: credentials,
            googleSync: GoogleTaskSync(
                transport: googleTransport
                    ?? ScriptedTransport(steps: [])
            ),
            davSync: PIMDAVTaskSync(transport: davTransport),
            googleAccessToken: googleAccessToken,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        return (service, coordinator, taskStore, cursorStore)
    }

    // MARK: - DAV sync-collection

    @Test("DAV incremental sync applies changes, removals and the new token")
    func davIncrementalSync() async throws {
        let collection = Self.collection()
        let transport = ScriptedTransport(steps: [
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/calendars/henrik/tasks/t1.ics",
                            "etag-2",
                            Self.sampleVTodo
                        )
                    ],
                    removed: ["/calendars/henrik/tasks/gone.ics"],
                    syncToken: "sync-2"
                )
            )
        ])
        let (service, _, taskStore, cursorStore) = try await makeService(
            source: Self.source(),
            collections: [collection],
            davTransport: transport
        )
        // Seed the cache: one task that will be removed, one untouched.
        try await taskStore.saveTasks(
            [
                Self.task(
                    collectionID: collection.id,
                    providerItemKey:
                    "https://dav.example.com/calendars/henrik/tasks/gone.ics",
                    title: "Gone"
                ),
                Self.task(
                    collectionID: collection.id,
                    providerItemKey:
                    "https://dav.example.com/calendars/henrik/tasks/keep.ics",
                    title: "Keep"
                )
            ],
            for: "pim-test",
            collectionID: collection.id
        )
        try await cursorStore.saveCursor(
            PIMSyncCursor(collectionID: collection.id, token: "sync-1"),
            for: "pim-test"
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedCollections == 1)
        #expect(summary.failures.isEmpty)
        let tasks = try await taskStore.tasks(
            for: "pim-test",
            collectionID: collection.id
        )
        let keys = Set(tasks.map(\.providerItemKey))
        #expect(keys.contains(
            "https://dav.example.com/calendars/henrik/tasks/t1.ics"
        ))
        #expect(keys.contains(
            "https://dav.example.com/calendars/henrik/tasks/keep.ics"
        ))
        #expect(!keys.contains(
            "https://dav.example.com/calendars/henrik/tasks/gone.ics"
        ))
        let cursor = try await cursorStore.cursor(
            for: "pim-test",
            collectionID: collection.id
        )
        #expect(cursor?.token == "sync-2")
    }

    @Test("DAV VTODO fields map onto the task record")
    func davFieldMapping() async throws {
        let collection = Self.collection()
        let transport = ScriptedTransport(steps: [
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/calendars/henrik/tasks/t1.ics",
                            "etag-1",
                            Self.sampleVTodo
                        )
                    ],
                    syncToken: "sync-1"
                )
            )
        ])
        let (service, _, taskStore, _) = try await makeService(
            source: Self.source(),
            collections: [collection],
            davTransport: transport
        )

        _ = try await service.syncNow(sourceID: "pim-test")

        let tasks = try await taskStore.tasks(
            for: "pim-test",
            collectionID: collection.id
        )
        let task = try #require(tasks.first)
        #expect(task.title == "Buy milk")
        #expect(task.notes == "Oat, not dairy")
        #expect(task.due != nil)
        #expect(task.status == PIMTaskStatus.needsAction)
        #expect(!task.isCompleted)
        #expect(task.position == "1000")
        #expect(task.parentKey == "task-0@example.com")
        #expect(task.links == ["https://example.com/list"])
        #expect(task.providerUpdatedAt != nil)
        #expect(task.rawPayload == Self.sampleVTodo)
    }

    @Test("DAV completed task maps status and timestamp")
    func davCompletedTask() async throws {
        let collection = Self.collection()
        let completed = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VTODO
        UID:done-1@example.com
        SUMMARY:Ship release
        STATUS:COMPLETED
        COMPLETED:20260918T120000Z
        END:VTODO
        END:VCALENDAR
        """
        let transport = ScriptedTransport(steps: [
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        ("/calendars/henrik/tasks/d1.ics", "e1", completed)
                    ],
                    syncToken: "s1"
                )
            )
        ])
        let (service, _, taskStore, _) = try await makeService(
            source: Self.source(),
            collections: [collection],
            davTransport: transport
        )

        _ = try await service.syncNow(sourceID: "pim-test")

        let task = try await taskStore.tasks(
            for: "pim-test",
            collectionID: collection.id
        ).first
        #expect(task?.status == PIMTaskStatus.completed)
        #expect(task?.isCompleted == true)
        #expect(task?.completedAt != nil)
    }

    @Test("DAV member without inline data is fetched by multiget")
    func davMultiget() async throws {
        let collection = Self.collection()
        let transport = ScriptedTransport(steps: [
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        ("/calendars/henrik/tasks/t1.ics", "etag-1", nil)
                    ],
                    syncToken: "sync-1"
                )
            ),
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/calendars/henrik/tasks/t1.ics",
                            "etag-1",
                            Self.sampleVTodo
                        )
                    ]
                )
            )
        ])
        let (service, _, taskStore, _) = try await makeService(
            source: Self.source(),
            collections: [collection],
            davTransport: transport
        )

        _ = try await service.syncNow(sourceID: "pim-test")

        #expect(transport.requests.count == 2)
        let tasks = try await taskStore.tasks(
            for: "pim-test",
            collectionID: collection.id
        )
        #expect(tasks.first?.title == "Buy milk")
    }

    @Test("Sync-collection 501 falls back to the bounded listing path")
    func davFallbackSync() async throws {
        let collection = Self.collection()
        let transport = ScriptedTransport(steps: [
            // sync-collection refused
            .response(501),
            // calendar-query listing: one changed, one unchanged
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        ("/calendars/henrik/tasks/t1.ics", "etag-1", nil),
                        ("/calendars/henrik/tasks/t2.ics", "etag-9", nil)
                    ]
                )
            ),
            // multiget for the changed member only
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/calendars/henrik/tasks/t1.ics",
                            "etag-1",
                            Self.sampleVTodo
                        )
                    ]
                )
            )
        ])
        let (service, _, taskStore, _) = try await makeService(
            source: Self.source(),
            collections: [collection],
            davTransport: transport
        )
        try await taskStore.saveTasks(
            [
                Self.task(
                    collectionID: collection.id,
                    providerItemKey:
                    "https://dav.example.com/calendars/henrik/tasks/t2.ics",
                    title: "Cached",
                    etag: "etag-9"
                ),
                Self.task(
                    collectionID: collection.id,
                    providerItemKey:
                    "https://dav.example.com/calendars/henrik/tasks/stale.ics",
                    title: "Stale"
                )
            ],
            for: "pim-test",
            collectionID: collection.id
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedCollections == 1)
        #expect(transport.requests.count == 3)
        // The listing request must filter VTODO without a time range.
        let listing = try #require(
            String(data: transport.requests[1].httpBody ?? Data(), encoding: .utf8)
        )
        #expect(listing.contains("VTODO"))
        #expect(!listing.contains("time-range"))
        let tasks = try await taskStore.tasks(
            for: "pim-test",
            collectionID: collection.id
        )
        let titles = Set(tasks.map(\.title))
        #expect(titles.contains("Buy milk")) // fetched
        #expect(titles.contains("Cached")) // kept via ETag
        #expect(!titles.contains("Stale")) // absent from listing
    }

    @Test("DAV invalid sync token retries once as a full sync")
    func davCursorExpiry() async throws {
        let collection = Self.collection()
        let transport = ScriptedTransport(steps: [
            .response(
                403,
                body: """
                <?xml version="1.0"?>
                <d:error xmlns:d="DAV:"><d:valid-sync-token/></d:error>
                """
            ),
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/calendars/henrik/tasks/t1.ics",
                            "etag-1",
                            Self.sampleVTodo
                        )
                    ],
                    syncToken: "sync-9"
                )
            )
        ])
        let (service, _, taskStore, cursorStore) = try await makeService(
            source: Self.source(),
            collections: [collection],
            davTransport: transport
        )
        try await cursorStore.saveCursor(
            PIMSyncCursor(collectionID: collection.id, token: "sync-old"),
            for: "pim-test"
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedCollections == 1)
        #expect(transport.requests.count == 2)
        let tasks = try await taskStore.tasks(
            for: "pim-test",
            collectionID: collection.id
        )
        #expect(tasks.first?.title == "Buy milk")
        let cursor = try await cursorStore.cursor(
            for: "pim-test",
            collectionID: collection.id
        )
        #expect(cursor?.token == "sync-9")
    }

    // MARK: - Google sync

    @Test("Google full sync pages, maps fields and stores the cursor")
    func googleFullSync() async throws {
        let collection = Self.collection(providerKey: "list-1")
        let page1 = """
        {"items":[
          {"id":"t-1","etag":"\\"e1\\"","title":"Write spec","notes":"draft","status":"needsAction","due":"2026-09-25T00:00:00.000Z","updated":"2026-09-20T09:00:00.000Z","position":"00000000000000000001","parent":"t-0","links":[{"type":"email","link":"brev://message?id=m1"}]},
          {"id":"t-2","title":"Done","status":"completed","completed":"2026-09-18T12:00:00.000Z","updated":"2026-09-18T12:00:00.000Z"}
        ],"nextPageToken":"p2"}
        """
        let page2 = """
        {"items":[
          {"id":"t-3","title":"Second page","status":"needsAction","updated":"2026-09-19T08:00:00.000Z"}
        ]}
        """
        let transport = ScriptedTransport(steps: [
            .response(200, body: page1),
            .response(200, body: page2)
        ])
        let (service, _, taskStore, cursorStore) = try await makeService(
            source: Self.source(provider: .google),
            collections: [collection],
            davTransport: ScriptedTransport(steps: []),
            googleTransport: transport,
            googleAccessToken: { _ in "google-token" }
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedCollections == 1)
        #expect(transport.requests.count == 2)
        // Full passes never send updatedMin; deleted/hidden stay visible.
        let query = transport.requests[0].url?.query ?? ""
        #expect(!query.contains("updatedMin"))
        #expect(query.contains("showDeleted=true"))
        #expect(query.contains("showHidden=true"))
        #expect(transport.requests[1].url?.query?.contains("pageToken=p2") == true)

        let tasks = try await taskStore.tasks(
            for: "pim-test",
            collectionID: collection.id
        )
        #expect(tasks.count == 3)
        let first = tasks.first { $0.providerItemKey == "t-1" }
        #expect(first?.title == "Write spec")
        #expect(first?.notes == "draft")
        #expect(first?.due != nil)
        #expect(first?.parentKey == "t-0")
        #expect(first?.position == "00000000000000000001")
        #expect(first?.links == ["brev://message?id=m1"])
        #expect(first?.providerVersion == "\"e1\"")
        let done = tasks.first { $0.providerItemKey == "t-2" }
        #expect(done?.status == PIMTaskStatus.completed)
        #expect(done?.isCompleted == true)
        #expect(done?.completedAt != nil)
        // The cursor is the pass start — the next pass sends it as
        // updatedMin.
        let cursor = try await cursorStore.cursor(
            for: "pim-test",
            collectionID: collection.id
        )
        #expect(cursor?.token != nil)
    }

    @Test("Google incremental sends updatedMin and applies tombstones")
    func googleIncremental() async throws {
        let collection = Self.collection(providerKey: "list-1")
        let page = """
        {"items":[
          {"id":"t-9","title":"New","status":"needsAction","updated":"2026-09-21T10:00:00.000Z"},
          {"id":"t-1","deleted":true,"updated":"2026-09-21T10:05:00.000Z"}
        ]}
        """
        let transport = ScriptedTransport(steps: [.response(200, body: page)])
        let (service, _, taskStore, cursorStore) = try await makeService(
            source: Self.source(provider: .google),
            collections: [collection],
            davTransport: ScriptedTransport(steps: []),
            googleTransport: transport,
            googleAccessToken: { _ in "google-token" }
        )
        try await taskStore.saveTasks(
            [
                Self.task(
                    collectionID: collection.id,
                    providerItemKey: "t-1",
                    title: "Old"
                ),
                Self.task(
                    collectionID: collection.id,
                    providerItemKey: "t-2",
                    title: "Kept"
                )
            ],
            for: "pim-test",
            collectionID: collection.id
        )
        try await cursorStore.saveCursor(
            PIMSyncCursor(
                collectionID: collection.id,
                token: "2026-09-20T00:00:00Z"
            ),
            for: "pim-test"
        )

        _ = try await service.syncNow(sourceID: "pim-test")

        let query = transport.requests[0].url?.query ?? ""
        #expect(query.contains("updatedMin=2026-09-20T00"))
        let tasks = try await taskStore.tasks(
            for: "pim-test",
            collectionID: collection.id
        )
        let keys = Set(tasks.map(\.providerItemKey))
        #expect(keys.contains("t-9"))
        #expect(keys.contains("t-2"))
        #expect(!keys.contains("t-1"))
    }

    @Test("Google 410 retries once as a full sync")
    func googleCursorExpiry() async throws {
        let collection = Self.collection(providerKey: "list-1")
        let transport = ScriptedTransport(steps: [
            .response(410),
            .response(
                200,
                body: """
                {"items":[{"id":"t-1","title":"Fresh","status":"needsAction"}]}
                """
            )
        ])
        let (service, _, taskStore, cursorStore) = try await makeService(
            source: Self.source(provider: .google),
            collections: [collection],
            davTransport: ScriptedTransport(steps: []),
            googleTransport: transport,
            googleAccessToken: { _ in "google-token" }
        )
        try await cursorStore.saveCursor(
            PIMSyncCursor(collectionID: collection.id, token: "stale"),
            for: "pim-test"
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedCollections == 1)
        #expect(transport.requests.count == 2)
        // The retry is a full listing: no updatedMin.
        #expect(
            transport.requests[1].url?.query?.contains("updatedMin") == false
        )
        let tasks = try await taskStore.tasks(
            for: "pim-test",
            collectionID: collection.id
        )
        #expect(tasks.first?.title == "Fresh")
    }

    // MARK: - Guards and isolation

    @Test("Disconnected sources cannot sync")
    func disconnectedRejected() async throws {
        let (service, _, _, _) = try await makeService(
            source: Self.source(status: .disconnected),
            collections: [Self.collection()],
            davTransport: ScriptedTransport(steps: [])
        )
        await #expect(throws: PIMTaskSyncServiceError.self) {
            _ = try await service.syncNow(sourceID: "pim-test")
        }
    }

    @Test("Calendar and contacts sources are rejected by the task engine")
    func wrongKindRejected() async throws {
        var calendar = Self.source()
        calendar.kind = .calendar
        let (service, _, _, _) = try await makeService(
            source: calendar,
            collections: [Self.collection()],
            davTransport: ScriptedTransport(steps: [])
        )
        await #expect(throws: PIMTaskSyncServiceError.self) {
            _ = try await service.syncNow(sourceID: "pim-test")
        }
    }

    @Test("Authentication failure marks the source and stops the pass")
    func authFailure() async throws {
        let collection = Self.collection()
        let other = Self.collection(
            providerKey: "https://dav.example.com/calendars/henrik/other/"
        )
        let transport = ScriptedTransport(steps: [
            .response(401)
        ])
        let (service, coordinator, _, _) = try await makeService(
            source: Self.source(),
            collections: [collection, other],
            davTransport: transport
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        // One credential serves both collections — the pass stops at the
        // first 401 rather than hammering the second collection.
        #expect(summary.failures.count == 1)
        #expect(transport.requests.count == 1)
        let source = try await coordinator.source(id: "pim-test")
        #expect(source?.status == .authenticationRequired)
    }

    @Test("Hidden collections keep their cache but skip the provider")
    func hiddenCollectionsSkip() async throws {
        let visible = Self.collection()
        let hidden = Self.collection(
            providerKey: "https://dav.example.com/calendars/henrik/hidden/",
            isVisible: false
        )
        let transport = ScriptedTransport(steps: [
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/calendars/henrik/tasks/t1.ics",
                            "etag-1",
                            Self.sampleVTodo
                        )
                    ],
                    syncToken: "s1"
                )
            )
        ])
        let (service, _, taskStore, _) = try await makeService(
            source: Self.source(),
            collections: [visible, hidden],
            davTransport: transport
        )
        try await taskStore.saveTasks(
            [
                Self.task(
                    collectionID: hidden.id,
                    providerItemKey: "old",
                    title: "Cached"
                )
            ],
            for: "pim-test",
            collectionID: hidden.id
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedCollections == 1)
        #expect(transport.requests.count == 1)
        let hiddenTasks = try await taskStore.tasks(
            for: "pim-test",
            collectionID: hidden.id
        )
        #expect(hiddenTasks.first?.title == "Cached")
    }

    @Test("One collection's failure keeps its snapshot and the others commit")
    func partialFailure() async throws {
        let failing = Self.collection()
        let healthy = Self.collection(
            providerKey: "https://dav.example.com/calendars/henrik/ok/"
        )
        // Fail the first collection outright (500 is not a fallback
        // trigger), then let the second collection succeed.
        let transport = ScriptedTransport(steps: [
            .response(500),
            .response(
                207,
                body: Self.davSyncBody(
                    members: [
                        (
                            "/calendars/henrik/ok/t1.ics",
                            "etag-1",
                            Self.sampleVTodo
                        )
                    ],
                    syncToken: "s1"
                )
            )
        ])
        let (service, coordinator, taskStore, _) = try await makeService(
            source: Self.source(),
            collections: [failing, healthy],
            davTransport: transport
        )
        try await taskStore.saveTasks(
            [
                Self.task(
                    collectionID: failing.id,
                    providerItemKey: "prior",
                    title: "Prior snapshot"
                )
            ],
            for: "pim-test",
            collectionID: failing.id
        )

        let summary = try await service.syncNow(sourceID: "pim-test")

        #expect(summary.syncedCollections == 1)
        #expect(summary.failures.count == 1)
        // The failed collection's snapshot is untouched.
        let prior = try await taskStore.tasks(
            for: "pim-test",
            collectionID: failing.id
        )
        #expect(prior.first?.title == "Prior snapshot")
        let synced = try await taskStore.tasks(
            for: "pim-test",
            collectionID: healthy.id
        )
        #expect(synced.first?.title == "Buy milk")
        // Partial success keeps the source ready with the failure noted.
        let source = try await coordinator.source(id: "pim-test")
        #expect(source?.status == .ready)
    }
}
