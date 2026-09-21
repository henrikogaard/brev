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

@Suite("PIMCollectionService")
struct PIMCollectionServiceTests {
    // MARK: - Doubles

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

        func collections(for sourceID: PIMSource.ID) async throws -> [PIMCollection] {
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

    /// Scripted discovery results per provider; a nil entry throws.
    private struct StubDiscovery {
        var davResult: Swift.Result<[PIMDiscoveredCollection], Error>
        var googleResult: Swift.Result<[PIMDiscoveredCollection], Error>
    }

    // MARK: - Helpers

    private static func source(
        provider: PIMSourceProvider = .calDAV,
        status: PIMSourceStatus = .ready
    ) -> PIMSource {
        PIMSource(
            id: "pim-test",
            kind: provider == .cardDAV ? .contacts : .calendar,
            provider: provider,
            linkedAccountID: provider == .google ? "acct-1" : nil,
            displayName: "Test",
            endpointURL: provider == .google
                ? nil
                : URL(string: "https://dav.example.com/dav/"),
            principalURL: provider == .google
                ? nil
                : URL(string: "https://dav.example.com/principals/henrik/"),
            credentialAccount: provider == .google ? nil : "pim-source-pim-test",
            status: status
        )
    }

    private func makeService(
        source: PIMSource,
        davTransport: ScriptedResultTransport? = nil,
        googleTransport: ScriptedResultTransport? = nil,
        collectionStore: InMemoryCollectionStore = InMemoryCollectionStore(),
        googleAccessToken: (@Sendable (String) async throws -> String)? = nil
    ) async throws -> (PIMCollectionService, PIMSourceCoordinator) {
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
        // Scripted adapters: route the stubbed results through a transport
        // that encodes the outcome as a canned HTTP response the real
        // parsers consume.
        let service = PIMCollectionService(
            coordinator: coordinator,
            store: collectionStore,
            credentials: credentials,
            davDiscovery: PIMDAVCollectionDiscovery(
                transport: davTransport
                    ?? ScriptedResultTransport(result: .success([]))
            ),
            googleDiscovery: GooglePIMCollectionDiscovery(
                transport: googleTransport
                    ?? ScriptedResultTransport(result: .success([]))
            ),
            googleAccessToken: googleAccessToken
        )
        return (service, coordinator)
    }

    /// Encodes a stubbed discovery result as transport behavior: success
    /// answers a DAV listing built from the discovered collections (or a
    /// Google JSON page for Google calls); failure throws.
    private final class ScriptedResultTransport: PIMDAVTransport, @unchecked Sendable {
        /// Mutable so a test can change the provider's answer between
        /// refreshes on the same service.
        var result: Swift.Result<[PIMDiscoveredCollection], Error>

        init(result: Swift.Result<[PIMDiscoveredCollection], Error>) {
            self.result = result
        }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 207,
                httpVersion: nil,
                headerFields: nil
            )!
            switch result {
            case .failure(let error):
                throw error
            case .success(let collections):
                if request.url?.host() == "www.googleapis.com"
                    || request.url?.host() == "people.googleapis.com" {
                    return (Self.googleBody(for: request, collections: collections), response)
                }
                return (Self.davBody(for: request, collections: collections), response)
            }
        }

        /// The home-set PROPFIND answers a fixed home set; the Depth:1
        /// request answers a listing synthesized from the stubbed
        /// collections.
        private static func davBody(
            for request: URLRequest,
            collections: [PIMDiscoveredCollection]
        ) -> Data {
            let depth = request.value(forHTTPHeaderField: "Depth")
            if depth == "0" {
                return Data(
                    """
                    <?xml version="1.0" encoding="utf-8"?>
                    <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
                      <d:response>
                        <d:href>/principals/henrik/</d:href>
                        <d:propstat>
                          <d:prop>
                            <cal:calendar-home-set><d:href>/calendars/henrik/</d:href></cal:calendar-home-set>
                          </d:prop>
                          <d:status>HTTP/1.1 200 OK</d:status>
                        </d:propstat>
                      </d:response>
                    </d:multistatus>
                    """.utf8
                )
            }
            let items = collections.map { item in
                """
                  <d:response>
                    <d:href>\(item.providerKey)</d:href>
                    <d:propstat>
                      <d:prop>
                        <d:resourcetype><d:collection/><cal:calendar/></d:resourcetype>
                        <d:displayname>\(item.displayName)</d:displayname>
                      </d:prop>
                      <d:status>HTTP/1.1 200 OK</d:status>
                    </d:propstat>
                  </d:response>
                """
            }.joined(separator: "\n")
            return Data(
                """
                <?xml version="1.0" encoding="utf-8"?>
                <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
                \(items)
                </d:multistatus>
                """.utf8
            )
        }

        private static func googleBody(
            for request: URLRequest,
            collections: [PIMDiscoveredCollection]
        ) -> Data {
            let items = collections.map { item in
                """
                {"id": "\(item.providerKey)", "summary": "\(item.displayName)", "accessRole": "owner"}
                """
            }.joined(separator: ",")
            return Data("{\"items\": [\(items)]}".utf8)
        }
    }

    private static func discovered(
        _ key: String,
        name: String,
        hidden: Bool = false
    ) -> PIMDiscoveredCollection {
        PIMDiscoveredCollection(
            providerKey: key,
            displayName: name,
            initiallyHidden: hidden
        )
    }

    // MARK: - Tests

    @Test("Refresh persists discovered collections")
    func refreshPersists() async throws {
        let source = Self.source()
        let transport = ScriptedResultTransport(
            result: .success([
                Self.discovered("/calendars/henrik/a/", name: "A"),
                Self.discovered("/calendars/henrik/b/", name: "B")
            ])
        )
        let (service, _) = try await makeService(
            source: source,
            davTransport: transport
        )
        let collections = try await service.refreshCollections(for: source.id)
        #expect(collections.count == 2)
        #expect(collections[0].sourceID == source.id)
        #expect(collections[0].isVisible == true)

        let cached = try await service.collections(for: source.id)
        #expect(cached.count == 2)
    }

    @Test("Refresh preserves user visibility across provider changes")
    func refreshPreservesVisibility() async throws {
        let source = Self.source()
        let transport = ScriptedResultTransport(
            result: .success([
                Self.discovered("/cal/a/", name: "A"),
                Self.discovered("/cal/b/", name: "B", hidden: true)
            ])
        )
        let (service, _) = try await makeService(
            source: source,
            davTransport: transport
        )
        _ = try await service.refreshCollections(for: source.id)

        // User hides A; provider-hidden B stays hidden without a toggle.
        let collections = try await service.collections(for: source.id)
        let a = try #require(collections.first { $0.displayName == "A" })
        try await service.setVisible(
            false,
            collectionID: a.id,
            sourceID: source.id
        )

        // A second refresh adds C and must keep the choices above.
        transport.result = .success([
            Self.discovered("/cal/a/", name: "A renamed"),
            Self.discovered("/cal/c/", name: "C")
        ])
        let refreshed = try await service.refreshCollections(for: source.id)
        let merged = refreshed.sorted { $0.displayName < $1.displayName }
        #expect(merged.count == 2)
        #expect(merged[0].displayName == "A renamed")
        #expect(merged[0].isVisible == false)
        #expect(merged[1].displayName == "C")
        #expect(merged[1].isVisible == true)
    }

    @Test("A failed refresh marks the source failed and keeps the cache")
    func refreshFailureKeepsCache() async throws {
        let source = Self.source()
        let transport = ScriptedResultTransport(
            result: .success([Self.discovered("/cal/a/", name: "A")])
        )
        let (service, coordinator) = try await makeService(
            source: source,
            davTransport: transport
        )
        _ = try await service.refreshCollections(for: source.id)

        // Now the provider fails; the cached list must survive.
        transport.result = .failure(URLError(.cannotConnectToHost))
        await #expect(throws: PIMDAVConnectError.self) {
            try await service.refreshCollections(for: source.id)
        }
        let updated = try await coordinator.source(id: source.id)
        #expect(updated?.status == .failed)
        let cached = try await service.collections(for: source.id)
        #expect(cached.count == 1)
    }

    @Test("Refresh requires a connected source")
    func refreshRequiresConnection() async throws {
        let source = Self.source(status: .disconnected)
        let (service, _) = try await makeService(source: source)
        await #expect(
            throws: PIMCollectionServiceError.sourceNotReady
        ) {
            try await service.refreshCollections(for: source.id)
        }
    }

    @Test("Google refresh resolves the token through the linked account")
    func googleRefresh() async throws {
        let source = Self.source(provider: .google)
        let captured = TokenCapture()
        let (service, _) = try await makeService(
            source: source,
            googleTransport: ScriptedResultTransport(
                result: .success([
                    Self.discovered("cal-1", name: "Primary")
                ])
            ),
            googleAccessToken: { accountID in
                await captured.record(accountID)
                return "google-token"
            }
        )
        let collections = try await service.refreshCollections(for: source.id)
        #expect(collections.count == 1)
        #expect(await captured.accountID == "acct-1")
    }

    @Test("Google refresh without a token provider is unavailable")
    func googleUnavailable() async throws {
        let source = Self.source(provider: .google)
        let (service, _) = try await makeService(source: source)
        await #expect(
            throws: PIMCollectionServiceError.googleAuthorizationUnavailable
        ) {
            try await service.refreshCollections(for: source.id)
        }
    }

    private actor TokenCapture {
        private(set) var accountID: String?
        func record(_ id: String) { accountID = id }
    }
}

@Suite("JSONPIMCollectionStore")
struct JSONPIMCollectionStoreTests {
    private func makeStore() throws -> (
        JSONPIMCollectionStore,
        FilePIMSourceLocalDataStore,
        URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localData = FilePIMSourceLocalDataStore(rootURL: root)
        return (JSONPIMCollectionStore(localDataStore: localData), localData, root)
    }

    private static func collection(
        _ id: String,
        sourceID: String = "src-1"
    ) -> PIMCollection {
        PIMCollection(
            id: "\(sourceID)|\(id)",
            sourceID: sourceID,
            kind: .calendar,
            displayName: id,
            providerKey: id
        )
    }

    @Test("Collections round-trip through the JSON file")
    func roundTrip() async throws {
        let (store, _, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try await store.saveCollections(
            [Self.collection("a"), Self.collection("b")],
            for: "src-1"
        )
        // A fresh instance reads from disk, not memory.
        let (_, localData, _) = ((), FilePIMSourceLocalDataStore(rootURL: root), ())
        let reloaded = JSONPIMCollectionStore(localDataStore: localData)
        let collections = try await reloaded.collections(for: "src-1")
        #expect(collections.map(\.id) == ["src-1|a", "src-1|b"])
    }

    @Test("Collection lists are isolated per source")
    func perSourceIsolation() async throws {
        let (store, _, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try await store.saveCollections([Self.collection("a")], for: "src-1")
        try await store.saveCollections(
            [Self.collection("x", sourceID: "src-2")],
            for: "src-2"
        )
        #expect(try await store.collections(for: "src-1").count == 1)
        #expect(
            try await store.collections(for: "src-2")[0].providerKey == "x"
        )
        #expect(try await store.collections(for: "src-3").isEmpty)
    }

    @Test("Deleting cached content removes the collections file")
    func cacheDeletionRemovesCollections() async throws {
        let (store, localData, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try await store.saveCollections([Self.collection("a")], for: "src-1")
        try await localData.deleteCachedContent(for: "src-1")

        // Fresh instance: nothing survives the cache wipe.
        let reloaded = JSONPIMCollectionStore(localDataStore: localData)
        #expect(try await reloaded.collections(for: "src-1").isEmpty)
    }

    @Test("Marking a kept cache disconnected keeps collections readable")
    func keptCacheStaysReadable() async throws {
        let (store, localData, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try await store.saveCollections([Self.collection("a")], for: "src-1")
        try await localData.markCacheDisconnected(for: "src-1")

        let reloaded = JSONPIMCollectionStore(localDataStore: localData)
        #expect(try await reloaded.collections(for: "src-1").count == 1)
    }
}
