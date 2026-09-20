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
import Testing

@Suite("PIM source stores and presentation")
struct PIMSourceStoreTests {
    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pim-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSource(id: String = "pim-1") -> PIMSource {
        PIMSource(
            id: id,
            kind: .contacts,
            provider: .cardDAV,
            linkedAccountID: "account-1",
            displayName: "Work contacts",
            endpointURL: URL(string: "https://dav.example.com/carddav/"),
            credentialAccount: "pim-source-\(id)",
            syncEnabled: false,
            status: .ready
        )
    }

    @Test("JSON store round-trips, updates and deletes records")
    func jsonStoreRoundTrip() async throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("sources.json")
        let store = JSONPIMSourceStore(fileURL: file)

        #expect(try await store.allSources().isEmpty)

        var source = makeSource()
        try await store.save(source)
        try await store.save(makeSource(id: "pim-2"))
        #expect(try await store.allSources().count == 2)

        // A fresh instance reads the persisted file — records survive.
        let reloaded = JSONPIMSourceStore(fileURL: file)
        #expect(try await reloaded.allSources().count == 2)

        source.status = .authenticationRequired
        try await store.save(source)
        let updated = try await store.allSources().first { $0.id == "pim-1" }
        #expect(updated?.status == .authenticationRequired)

        try await store.deleteSource(id: "pim-1")
        #expect(try await store.allSources().map(\.id) == ["pim-2"])

        // Deleting a missing record is not an error.
        try await store.deleteSource(id: "pim-1")
    }

    @Test("unreadable store files surface a store error")
    func unreadableStore() async throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("sources.json")
        try Data("not json".utf8).write(to: file)

        let store = JSONPIMSourceStore(fileURL: file)
        await #expect(throws: PIMSourceStoreError.unreadableStore) {
            _ = try await store.allSources()
        }
    }

    @Test("local data store separates cache, cursors and drafts")
    func localDataSeparation() async throws {
        let root = try makeTempDir()
        let localData = FilePIMSourceLocalDataStore(rootURL: root)
        let fm = FileManager.default
        let id = "pim-9"

        for dir in [
            localData.cacheDirectory(for: id),
            localData.cursorDirectory(for: id),
            localData.draftDirectory(for: id)
        ] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        try await localData.deleteSyncAndDraftData(for: id)
        #expect(!fm.fileExists(atPath: localData.cursorDirectory(for: id).path))
        #expect(!fm.fileExists(atPath: localData.draftDirectory(for: id).path))
        #expect(fm.fileExists(atPath: localData.cacheDirectory(for: id).path))

        try await localData.markCacheDisconnected(for: id)
        #expect(
            fm.fileExists(
                atPath: localData.directory(for: id)
                    .appendingPathComponent("disconnected").path
            )
        )

        try await localData.deleteCachedContent(for: id)
        #expect(!fm.fileExists(atPath: localData.directory(for: id).path))
    }

    @Test("markCacheDisconnected is a no-op without a cache")
    func markDisconnectedWithoutCache() async throws {
        let root = try makeTempDir()
        let localData = FilePIMSourceLocalDataStore(rootURL: root)
        try await localData.markCacheDisconnected(for: "pim-none")
        #expect(
            !FileManager.default.fileExists(
                atPath: localData.directory(for: "pim-none").path
            )
        )
    }

    @Test("every source status has a non-empty presentation")
    func statusPresentationCoverage() {
        for status in PIMSourceStatus.allCases {
            let presentation = PIMSourceStatusPresenter.presentation(for: status)
            #expect(!presentation.title.isEmpty)
            #expect(!presentation.symbolName.isEmpty)
        }
    }

    @Test("actionable states match the source lifecycle contract")
    func statusActionability() {
        let actionable: Set<PIMSourceStatus> = [
            .disconnected, .permissionLimited, .authenticationRequired, .failed
        ]
        for status in PIMSourceStatus.allCases {
            #expect(
                PIMSourceStatusPresenter.presentation(for: status).isActionable
                    == actionable.contains(status)
            )
        }
    }
}
