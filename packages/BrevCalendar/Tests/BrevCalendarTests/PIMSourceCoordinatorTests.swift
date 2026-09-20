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

@Suite("PIMSourceCoordinator", .serialized)
struct PIMSourceCoordinatorTests {
    // MARK: - Doubles

    private actor InMemorySourceStore: PIMSourceStore {
        var records: [PIMSource] = []
        var shouldThrowOnSave = false

        func setShouldThrow(_ value: Bool) {
            shouldThrowOnSave = value
        }

        func allSources() async throws -> [PIMSource] { records }

        func save(_ source: PIMSource) async throws {
            if shouldThrowOnSave { throw PIMSourceStoreError.unreadableStore }
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
        headers: [String: String] = [:],
        body: String = ""
    ) -> (Data, HTTPURLResponse) {
        (
            Data(body.utf8),
            HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: headers
            )!
        )
    }

    private func makeCoordinator(
        transport: any PIMDAVTransport,
        store: InMemorySourceStore = InMemorySourceStore(),
        credentials: InMemoryCredentialStore = InMemoryCredentialStore(),
        localDataRoot: URL
    ) -> PIMSourceCoordinator {
        PIMSourceCoordinator(
            store: store,
            credentials: credentials,
            localData: FilePIMSourceLocalDataStore(rootURL: localDataRoot),
            davClient: PIMDAVClient(transport: transport)
        )
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pim-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func okTransport(
        status: Int = 207,
        body: String = multistatus
    ) -> StubTransport {
        StubTransport { request in
            response(status, url: request.url!, body: body)
        }
    }

    // MARK: - Connect

    @Test("connect persists a ready source and stages the credential")
    func connectSuccess() async throws {
        let root = try makeTempDir()
        let store = InMemorySourceStore()
        let credentials = InMemoryCredentialStore()
        let coordinator = makeCoordinator(
            transport: Self.okTransport(),
            store: store,
            credentials: credentials,
            localDataRoot: root
        )

        let source = try await coordinator.connectDAVSource(
            kind: .contacts,
            endpoint: .manual(URL(string: "https://dav.example.com/carddav/")!),
            displayName: "Work contacts",
            credential: .basic(username: "u", password: "p"),
            linkedAccountID: "account-1"
        )

        #expect(source.status == .ready)
        #expect(source.provider == .cardDAV)
        #expect(source.kind == .contacts)
        #expect(source.linkedAccountID == "account-1")
        #expect(source.syncEnabled == false)
        #expect(
            source.principalURL?.absoluteString
                == "https://dav.example.com/principals/user/henrik/"
        )

        let account = try #require(source.credentialAccount)
        let stored = try await credentials.credential(for: account)
        #expect(stored == .basic(username: "u", password: "p"))

        let all = try await coordinator.allSources()
        #expect(all.map(\.id) == [source.id])
    }

    @Test("failed connect creates no record and stores no credential")
    func connectFailureLeavesNothing() async throws {
        let root = try makeTempDir()
        let store = InMemorySourceStore()
        let credentials = InMemoryCredentialStore()
        let coordinator = makeCoordinator(
            transport: StubTransport { request in
                Self.response(401, url: request.url!)
            },
            store: store,
            credentials: credentials,
            localDataRoot: root
        )

        await #expect(throws: PIMDAVConnectError.authenticationRequired) {
            try await coordinator.connectDAVSource(
                kind: .calendar,
                endpoint: .manual(URL(string: "https://dav.example.com/")!),
                displayName: "Calendar",
                credential: .bearer(token: "expired")
            )
        }

        #expect(try await coordinator.allSources().isEmpty)
        #expect(await credentials.credentials.isEmpty)
    }

    @Test("a failed record write rolls back the staged credential")
    func connectRollsBackCredentialOnSaveFailure() async throws {
        let root = try makeTempDir()
        let store = InMemorySourceStore()
        await store.setShouldThrow(true)
        let credentials = InMemoryCredentialStore()
        let coordinator = makeCoordinator(
            transport: Self.okTransport(),
            store: store,
            credentials: credentials,
            localDataRoot: root
        )

        await #expect(throws: PIMSourceStoreError.unreadableStore) {
            try await coordinator.connectDAVSource(
                kind: .calendar,
                endpoint: .manual(URL(string: "https://dav.example.com/")!),
                displayName: "Calendar",
                credential: .bearer(token: "t")
            )
        }

        #expect(await credentials.credentials.isEmpty)
    }

    // MARK: - Reconnect

    @Test("reconnect validates before replacing the stored credential")
    func reconnectStagesThenSwaps() async throws {
        let root = try makeTempDir()
        let credentials = InMemoryCredentialStore()
        let coordinator = makeCoordinator(
            transport: Self.okTransport(),
            credentials: credentials,
            localDataRoot: root
        )
        let source = try await coordinator.connectDAVSource(
            kind: .calendar,
            endpoint: .manual(URL(string: "https://dav.example.com/")!),
            displayName: "Calendar",
            credential: .bearer(token: "old-token")
        )

        let updated = try await coordinator.reconnect(
            sourceID: source.id,
            credential: .bearer(token: "new-token")
        )

        #expect(updated.status == .ready)
        let account = try #require(source.credentialAccount)
        #expect(try await credentials.credential(for: account) == .bearer(token: "new-token"))
    }

    @Test("a rejected reconnect candidate never overwrites the working credential")
    func reconnectRejectionPreservesCredential() async throws {
        let root = try makeTempDir()
        let credentials = InMemoryCredentialStore()
        // First connect succeeds; reconnect validation fails.
        final class CallCount: @unchecked Sendable { var value = 0 }
        let count = CallCount()
        let transport = StubTransport { request in
            count.value += 1
            return Self.response(
                count.value == 1 ? 207 : 401,
                url: request.url!,
                body: Self.multistatus
            )
        }
        let coordinator = makeCoordinator(
            transport: transport,
            credentials: credentials,
            localDataRoot: root
        )
        let source = try await coordinator.connectDAVSource(
            kind: .calendar,
            endpoint: .manual(URL(string: "https://dav.example.com/")!),
            displayName: "Calendar",
            credential: .bearer(token: "working-token")
        )

        await #expect(throws: PIMDAVConnectError.authenticationRequired) {
            try await coordinator.reconnect(
                sourceID: source.id,
                credential: .bearer(token: "bad-token")
            )
        }

        let account = try #require(source.credentialAccount)
        #expect(try await credentials.credential(for: account) == .bearer(token: "working-token"))
        #expect(try await coordinator.source(id: source.id)?.status == .ready)
    }

    // MARK: - Sync opt-in and status

    @Test("sync stays off until explicitly enabled")
    func syncOptIn() async throws {
        let root = try makeTempDir()
        let coordinator = makeCoordinator(
            transport: Self.okTransport(),
            localDataRoot: root
        )
        let source = try await coordinator.connectDAVSource(
            kind: .contacts,
            endpoint: .manual(URL(string: "https://dav.example.com/")!),
            displayName: "Contacts",
            credential: .bearer(token: "t")
        )
        #expect(source.syncEnabled == false)

        let enabled = try await coordinator.setSyncEnabled(true, for: source.id)
        #expect(enabled.syncEnabled == true)
        #expect(try await coordinator.source(id: source.id)?.syncEnabled == true)

        let paused = try await coordinator.setSyncEnabled(false, for: source.id)
        #expect(paused.syncEnabled == false)
    }

    @Test("status transitions persist through the coordinator")
    func statusTransitions() async throws {
        let root = try makeTempDir()
        let coordinator = makeCoordinator(
            transport: Self.okTransport(),
            localDataRoot: root
        )
        let source = try await coordinator.connectDAVSource(
            kind: .calendar,
            endpoint: .manual(URL(string: "https://dav.example.com/")!),
            displayName: "Calendar",
            credential: .bearer(token: "t")
        )

        let syncing = try await coordinator.markStatus(.syncing, for: source.id)
        #expect(syncing.status == .syncing)

        let limited = try await coordinator.markStatus(
            .permissionLimited,
            for: source.id,
            detail: "calendar.readonly granted"
        )
        #expect(limited.status == .permissionLimited)
        #expect(limited.statusDetail == "calendar.readonly granted")

        let required = try await coordinator.markStatus(
            .authenticationRequired,
            for: source.id
        )
        #expect(required.status == .authenticationRequired)

        let disconnected = try await coordinator.disconnect(sourceID: source.id)
        #expect(disconnected.status == .disconnected)
    }

    // MARK: - Removal

    @Test("removal deletes credential, record, cursors and drafts but keeps a retained cache read-only")
    func removalKeepsCacheDisconnected() async throws {
        let root = try makeTempDir()
        let credentials = InMemoryCredentialStore()
        let coordinator = makeCoordinator(
            transport: Self.okTransport(),
            credentials: credentials,
            localDataRoot: root
        )
        let source = try await coordinator.connectDAVSource(
            kind: .contacts,
            endpoint: .manual(URL(string: "https://dav.example.com/")!),
            displayName: "Contacts",
            credential: .bearer(token: "t")
        )
        let localData = FilePIMSourceLocalDataStore(rootURL: root)
        let fm = FileManager.default
        for dir in [
            localData.cacheDirectory(for: source.id),
            localData.cursorDirectory(for: source.id),
            localData.draftDirectory(for: source.id)
        ] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try Data("cached".utf8).write(
            to: localData.cacheDirectory(for: source.id).appendingPathComponent("items.json")
        )

        try await coordinator.removeSource(id: source.id, deleteCachedContent: false)

        #expect(try await coordinator.source(id: source.id) == nil)
        let account = try #require(source.credentialAccount)
        #expect(try await credentials.credential(for: account) == nil)
        #expect(!fm.fileExists(atPath: localData.cursorDirectory(for: source.id).path))
        #expect(!fm.fileExists(atPath: localData.draftDirectory(for: source.id).path))
        #expect(fm.fileExists(atPath: localData.cacheDirectory(for: source.id).path))
        #expect(
            fm.fileExists(
                atPath: localData.directory(for: source.id)
                    .appendingPathComponent("disconnected").path
            )
        )
    }

    @Test("removal with cache deletion wipes the readable content too")
    func removalDeletesCache() async throws {
        let root = try makeTempDir()
        let coordinator = makeCoordinator(
            transport: Self.okTransport(),
            localDataRoot: root
        )
        let source = try await coordinator.connectDAVSource(
            kind: .calendar,
            endpoint: .manual(URL(string: "https://dav.example.com/")!),
            displayName: "Calendar",
            credential: .bearer(token: "t")
        )
        let localData = FilePIMSourceLocalDataStore(rootURL: root)
        let fm = FileManager.default
        try fm.createDirectory(
            at: localData.cacheDirectory(for: source.id),
            withIntermediateDirectories: true
        )

        try await coordinator.removeSource(id: source.id, deleteCachedContent: true)

        #expect(!fm.fileExists(atPath: localData.cacheDirectory(for: source.id).path))
        #expect(!fm.fileExists(atPath: localData.directory(for: source.id).path))
    }

    // MARK: - Linked sources

    @Test("linkedSources enumerates only sources attached to the account")
    func linkedSources() async throws {
        let root = try makeTempDir()
        let coordinator = makeCoordinator(
            transport: Self.okTransport(),
            localDataRoot: root
        )
        let linked = try await coordinator.connectDAVSource(
            kind: .calendar,
            endpoint: .manual(URL(string: "https://dav.example.com/")!),
            displayName: "Linked",
            credential: .bearer(token: "t"),
            linkedAccountID: "account-1"
        )
        _ = try await coordinator.connectDAVSource(
            kind: .contacts,
            endpoint: .manual(URL(string: "https://dav.example.com/")!),
            displayName: "Standalone",
            credential: .bearer(token: "t")
        )

        let linkedSources = try await coordinator.linkedSources(accountID: "account-1")
        #expect(linkedSources.map(\.id) == [linked.id])
        #expect(try await coordinator.linkedSources(accountID: "other").isEmpty)
    }

    // MARK: - Google sources

    @Test("connectGoogleSource registers a linked source without a credential")
    func connectGoogleSourceRegistersLinkedSource() async throws {
        let root = try makeTempDir()
        let credentials = InMemoryCredentialStore()
        let coordinator = makeCoordinator(
            transport: Self.okTransport(),
            credentials: credentials,
            localDataRoot: root
        )

        let source = try await coordinator.connectGoogleSource(
            kind: .calendar,
            accountID: "gmail-api:subject-1",
            displayName: "henrik@gmail.com"
        )

        #expect(source.provider == .google)
        #expect(source.kind == .calendar)
        #expect(source.linkedAccountID == "gmail-api:subject-1")
        #expect(source.status == .ready)
        #expect(source.syncEnabled == false)
        // The shared Google grant lives in the account token store; the
        // source must not hold its own credential reference.
        #expect(source.credentialAccount == nil)
        #expect(await credentials.credentials.isEmpty)
    }

    @Test("connectGoogleSource is idempotent per account and kind")
    func connectGoogleSourceIsIdempotent() async throws {
        let root = try makeTempDir()
        let coordinator = makeCoordinator(
            transport: Self.okTransport(),
            localDataRoot: root
        )

        let first = try await coordinator.connectGoogleSource(
            kind: .contacts,
            accountID: "gmail-api:subject-1",
            displayName: "henrik@gmail.com"
        )
        let second = try await coordinator.connectGoogleSource(
            kind: .contacts,
            accountID: "gmail-api:subject-1",
            displayName: "henrik@gmail.com"
        )
        let other = try await coordinator.connectGoogleSource(
            kind: .contacts,
            accountID: "gmail-api:subject-2",
            displayName: "other@gmail.com"
        )

        #expect(first.id == second.id)
        #expect(other.id != first.id)
        #expect(try await coordinator.allSources().count == 2)
    }

    @Test("removing a Google source never deletes a credential")
    func removingGoogleSourceKeepsSharedGrant() async throws {
        let root = try makeTempDir()
        let credentials = InMemoryCredentialStore()
        let coordinator = makeCoordinator(
            transport: Self.okTransport(),
            credentials: credentials,
            localDataRoot: root
        )
        let source = try await coordinator.connectGoogleSource(
            kind: .calendar,
            accountID: "gmail-api:subject-1",
            displayName: "henrik@gmail.com"
        )

        try await coordinator.removeSource(id: source.id, deleteCachedContent: true)

        #expect(try await coordinator.allSources().isEmpty)
        #expect(await credentials.credentials.isEmpty)
    }
}
