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
@testable import BrevSettings
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing

@Suite("PIMSourceSettingsModel", .serialized)
struct PIMSourceSettingsModelTests {
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

        func setCredential(_ credential: CalDAVCredential, for account: String) async throws {
            credentials[account] = credential
        }

        func deleteCredential(for account: String) async throws {
            credentials[account] = nil
        }
    }

    private actor InMemoryLocalDataStore: PIMSourceLocalDataStore {
        enum Call: Equatable {
            case deleteSyncAndDrafts(PIMSource.ID)
            case deleteCache(PIMSource.ID)
            case markDisconnected(PIMSource.ID)
        }

        private(set) var calls: [Call] = []

        func deleteSyncAndDraftData(for sourceID: PIMSource.ID) async throws {
            calls.append(.deleteSyncAndDrafts(sourceID))
        }

        func deleteCachedContent(for sourceID: PIMSource.ID) async throws {
            calls.append(.deleteCache(sourceID))
        }

        func markCacheDisconnected(for sourceID: PIMSource.ID) async throws {
            calls.append(.markDisconnected(sourceID))
        }
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

    private struct StubTransport: PIMDAVTransport {
        let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            try handler(request)
        }
    }

    private static let multistatus = """
    <?xml version="1.0" encoding="utf-8"?>
    <d:multistatus xmlns:d="DAV:">
      <d:response>
        <d:href>/dav/</d:href>
        <d:propstat>
          <d:prop>
            <d:current-user-principal>
              <d:href>/principals/user/henrik/</d:href>
            </d:current-user-principal>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
    </d:multistatus>
    """

    private static func response(
        _ status: Int,
        url: URL,
        body: String = ""
    ) -> (Data, HTTPURLResponse) {
        (
            Data(body.utf8),
            HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    // MARK: - Helpers

    @MainActor
    private func makeModel(
        store: InMemorySourceStore = InMemorySourceStore(),
        credentials: InMemoryCredentialStore = InMemoryCredentialStore(),
        localData: InMemoryLocalDataStore = InMemoryLocalDataStore(),
        transport: StubTransport? = nil,
        collectionStore: InMemoryCollectionStore? = nil,
        collectionTransport: StubTransport? = nil,
        googleFeatureHandler: ((BrevAccount.ID, PIMSourceKind) async throws -> Void)? = nil
    ) -> PIMSourceSettingsModel {
        let client = PIMDAVClient(
            transport: transport ?? StubTransport { request in
                Self.response(207, url: request.url!, body: Self.multistatus)
            }
        )
        let coordinator = PIMSourceCoordinator(
            store: store,
            credentials: credentials,
            localData: localData,
            davClient: client
        )
        // A collection service is wired when the test provides either a
        // store to inspect or a transport to script; otherwise the model
        // exercises the no-collections path.
        let collectionService: PIMCollectionService? =
            (collectionStore != nil || collectionTransport != nil)
                ? PIMCollectionService(
                    coordinator: coordinator,
                    store: collectionStore ?? InMemoryCollectionStore(),
                    credentials: credentials,
                    davDiscovery: PIMDAVCollectionDiscovery(
                        transport: collectionTransport ?? StubTransport { request in
                            Self.response(207, url: request.url!, body: "")
                        }
                    )
                )
                : nil
        return PIMSourceSettingsModel(
            coordinator: coordinator,
            collectionService: collectionService,
            googleFeatureHandler: googleFeatureHandler
        )
    }

    private static func source(
        id: String,
        status: PIMSourceStatus = .ready,
        syncEnabled: Bool = false
    ) -> PIMSource {
        PIMSource(
            id: id,
            kind: .calendar,
            provider: .calDAV,
            displayName: "Source (id)",
            endpointURL: URL(string: "https://dav.example.com/")!,
            credentialAccount: "pim-source-(id)",
            syncEnabled: syncEnabled,
            status: status
        )
    }

    // MARK: - Tests

    @Test("load populates sources from the coordinator")
    @MainActor
    func loadPopulatesSources() async throws {
        let store = InMemorySourceStore()
        try await store.save(Self.source(id: "a"))
        try await store.save(Self.source(id: "b"))
        let model = makeModel(store: store)

        await model.load()

        #expect(model.sources.map(\.id) == ["a", "b"])
        #expect(model.lastError == nil)
    }

    @Test("setSyncEnabled persists the opt-in and refreshes the list")
    @MainActor
    func setSyncEnabledPersistsOptIn() async throws {
        let store = InMemorySourceStore()
        try await store.save(Self.source(id: "a"))
        let model = makeModel(store: store)
        await model.load()

        await model.setSyncEnabled(true, for: "a")

        #expect(model.sources.first?.syncEnabled == true)
    }

    @Test("disconnect keeps the source but marks it disconnected")
    @MainActor
    func disconnectMarksSource() async throws {
        let store = InMemorySourceStore()
        try await store.save(Self.source(id: "a"))
        let model = makeModel(store: store)
        await model.load()

        await model.disconnect(sourceID: "a")

        #expect(model.sources.first?.status == .disconnected)
        #expect(model.sources.count == 1)
    }

    @Test("removing with a kept cache marks it disconnected; deleting clears it")
    @MainActor
    func removalCacheChoices() async throws {
        let store = InMemorySourceStore()
        let localData = InMemoryLocalDataStore()
        try await store.save(Self.source(id: "a"))
        try await store.save(Self.source(id: "b"))
        let model = makeModel(store: store, localData: localData)
        await model.load()

        await model.remove(sourceID: "a", deleteCachedContent: false)
        await model.remove(sourceID: "b", deleteCachedContent: true)

        #expect(model.sources.isEmpty)
        let calls = await localData.calls
        #expect(calls.contains(.deleteSyncAndDrafts("a")))
        #expect(calls.contains(.markDisconnected("a")))
        #expect(!calls.contains(.deleteCache("a")))
        #expect(calls.contains(.deleteCache("b")))
    }

    @Test("connectDAV stores a ready source on success")
    @MainActor
    func connectDAVStoresReadySource() async {
        let model = makeModel()
        var form = PIMDAVConnectForm()
        form.endpointMode = .manual
        form.address = "https://dav.example.com/"
        form.credentialMode = .bearerToken
        form.bearerToken = "token"

        let connected = await model.connectDAV(form)

        #expect(connected)
        #expect(model.sources.count == 1)
        #expect(model.sources.first?.status == .ready)
        #expect(model.sources.first?.syncEnabled == false)
    }

    @Test("connectDAV surfaces an actionable error and stores nothing on failure")
    @MainActor
    func connectDAVSurfacesErrorOnFailure() async {
        let transport = StubTransport { request in
            Self.response(401, url: request.url!)
        }
        let model = makeModel(transport: transport)
        var form = PIMDAVConnectForm()
        form.endpointMode = .manual
        form.address = "https://dav.example.com/"
        form.credentialMode = .bearerToken
        form.bearerToken = "bad-token"

        let connected = await model.connectDAV(form)

        #expect(!connected)
        #expect(model.sources.isEmpty)
        #expect(model.lastError != nil)
    }

    @Test("connectDAV does nothing when the form is invalid")
    @MainActor
    func connectDAVRejectsInvalidForm() async {
        let model = makeModel()
        let form = PIMDAVConnectForm()

        let connected = await model.connectDAV(form)

        #expect(!connected)
        #expect(model.sources.isEmpty)
    }

    @Test("reconnect validates the new credential before clearing the error state")
    @MainActor
    func reconnectClearsAuthenticationRequired() async throws {
        let store = InMemorySourceStore()
        try await store.save(Self.source(id: "a", status: .authenticationRequired))
        let model = makeModel(store: store)
        await model.load()

        var form = PIMDAVConnectForm()
        form.endpointMode = .manual
        form.address = "https://dav.example.com/"
        form.credentialMode = .bearerToken
        form.bearerToken = "fresh-token"

        let reconnected = await model.reconnect(sourceID: "a", form: form)

        #expect(reconnected)
        #expect(model.sources.first?.status == .ready)
    }

    @Test("a rejected reconnect keeps the authentication-required state")
    @MainActor
    func rejectedReconnectKeepsState() async throws {
        let store = InMemorySourceStore()
        try await store.save(Self.source(id: "a", status: .authenticationRequired))
        let transport = StubTransport { request in
            Self.response(401, url: request.url!)
        }
        let model = makeModel(store: store, transport: transport)
        await model.load()

        var form = PIMDAVConnectForm()
        form.endpointMode = .manual
        form.address = "https://dav.example.com/"
        form.credentialMode = .bearerToken
        form.bearerToken = "still-bad"

        let reconnected = await model.reconnect(sourceID: "a", form: form)

        #expect(!reconnected)
        #expect(model.sources.first?.status == .authenticationRequired)
        #expect(model.lastError != nil)
    }

    @Test("Google feature enablement is unavailable without a session handler")
    @MainActor
    func googleFeatureUnavailableWithoutHandler() async {
        let model = makeModel()

        #expect(!model.canEnableGoogleFeatures)
        let enabled = await model.enableGoogleFeature(accountID: "acct-1", kind: .calendar)

        #expect(!enabled)
        #expect(model.pendingGoogleAccountID == nil)
    }

    @Test("a successful Google enablement forwards account and kind then reloads")
    @MainActor
    func googleEnablementForwardsAndReloads() async throws {
        let store = InMemorySourceStore()
        var calls: [(accountID: String, kind: PIMSourceKind)] = []
        let model = makeModel(store: store) { accountID, kind in
            calls.append((accountID, kind))
            try await store.save(Self.source(id: "google-cal", status: .ready))
        }

        let enabled = await model.enableGoogleFeature(accountID: "acct-1", kind: .calendar)

        #expect(enabled)
        #expect(calls.count == 1)
        #expect(calls.first?.accountID == "acct-1")
        #expect(calls.first?.kind == .calendar)
        #expect(model.sources.map(\.id) == ["google-cal"])
        #expect(model.pendingGoogleAccountID == nil)
    }

    @Test("a declined Google authorization surfaces an inline error")
    @MainActor
    func googleEnablementFailureSurfacesError() async {
        struct Declined: LocalizedError {
            var errorDescription: String? { "Authorization was declined." }
        }
        let model = makeModel { _, _ in
            throw Declined()
        }

        let enabled = await model.enableGoogleFeature(accountID: "acct-1", kind: .contacts)

        #expect(!enabled)
        #expect(model.lastError == "Authorization was declined.")
        #expect(model.pendingGoogleAccountID == nil)
    }

    // MARK: - Collections

    private static let homeSetResponse = """
    <?xml version="1.0" encoding="utf-8"?>
    <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
      <d:response>
        <d:href>/principals/user/henrik/</d:href>
        <d:propstat>
          <d:prop>
            <cal:calendar-home-set><d:href>/calendars/henrik/</d:href></cal:calendar-home-set>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
    </d:multistatus>
    """

    private static let collectionListingResponse = """
    <?xml version="1.0" encoding="utf-8"?>
    <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
      <d:response>
        <d:href>/calendars/henrik/personal/</d:href>
        <d:propstat>
          <d:prop>
            <d:resourcetype><d:collection/><cal:calendar/></d:resourcetype>
            <d:displayname>Personal</d:displayname>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
    </d:multistatus>
    """

    /// Two-step scripted transport: home-set answer, then the Depth:1
    /// listing.
    private static func collectionDiscoveryTransport() -> StubTransport {
        var responses = [Self.homeSetResponse, Self.collectionListingResponse]
        return StubTransport { request in
            let body = responses.isEmpty ? "" : responses.removeFirst()
            return Self.response(207, url: request.url!, body: body)
        }
    }

    @Test("load lists cached collections under their source")
    @MainActor
    func loadListsCollections() async throws {
        let store = InMemorySourceStore()
        try await store.save(Self.source(id: "a"))
        let collectionStore = InMemoryCollectionStore()
        try await collectionStore.saveCollections(
            [
                PIMCollection(
                    id: "a|/cal/a/",
                    sourceID: "a",
                    kind: .calendar,
                    displayName: "Personal",
                    providerKey: "/cal/a/"
                )
            ],
            for: "a"
        )
        let model = makeModel(
            store: store,
            collectionStore: collectionStore
        )

        await model.load()

        #expect(model.canManageCollections)
        #expect(model.collectionsBySource["a"]?.count == 1)
        #expect(
            model.collectionsBySource["a"]?.first?.displayName == "Personal"
        )
    }

    @Test("connectDAV discovers collections right after connecting")
    @MainActor
    func connectDiscoversCollections() async {
        let collectionStore = InMemoryCollectionStore()
        let model = makeModel(
            collectionStore: collectionStore,
            collectionTransport: Self.collectionDiscoveryTransport()
        )
        var form = PIMDAVConnectForm()
        form.endpointMode = .manual
        form.address = "https://dav.example.com/"
        form.credentialMode = .bearerToken
        form.bearerToken = "token"

        let connected = await model.connectDAV(form)

        #expect(connected)
        let sourceID = model.sources.first?.id
        #expect(sourceID != nil)
        #expect(model.collectionsBySource[sourceID ?? ""]?.count == 1)
        #expect(
            model.collectionsBySource[sourceID ?? ""]?.first?.displayName
                == "Personal"
        )
    }

    @Test("a failed collection refresh keeps the cached list and surfaces an error")
    @MainActor
    func refreshFailureKeepsCollections() async throws {
        let store = InMemorySourceStore()
        try await store.save(Self.source(id: "a"))
        let collectionStore = InMemoryCollectionStore()
        try await collectionStore.saveCollections(
            [
                PIMCollection(
                    id: "a|/cal/a/",
                    sourceID: "a",
                    kind: .calendar,
                    displayName: "Personal",
                    providerKey: "/cal/a/"
                )
            ],
            for: "a"
        )
        let model = makeModel(
            store: store,
            collectionStore: collectionStore,
            collectionTransport: StubTransport { request in
                Self.response(401, url: request.url!)
            }
        )
        await model.load()

        await model.refreshCollections(sourceID: "a")

        #expect(model.lastError != nil)
        #expect(model.collectionsBySource["a"]?.count == 1)
    }

    @Test("toggling collection visibility persists through the service")
    @MainActor
    func toggleCollectionVisibility() async throws {
        let store = InMemorySourceStore()
        try await store.save(Self.source(id: "a"))
        let collectionStore = InMemoryCollectionStore()
        try await collectionStore.saveCollections(
            [
                PIMCollection(
                    id: "a|/cal/a/",
                    sourceID: "a",
                    kind: .calendar,
                    displayName: "Personal",
                    providerKey: "/cal/a/"
                )
            ],
            for: "a"
        )
        let model = makeModel(
            store: store,
            collectionStore: collectionStore
        )
        await model.load()

        await model.setCollectionVisible(
            false,
            collectionID: "a|/cal/a/",
            sourceID: "a"
        )

        #expect(
            model.collectionsBySource["a"]?.first?.isVisible == false
        )
        let stored = await collectionStore.records["a"]
        #expect(stored?.first?.isVisible == false)
    }
}
