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

@testable import BrevWidgets
import Foundation
import Testing

@Suite("WidgetSnapshotStore")
struct WidgetSnapshotStoreTests {
    private func temporaryStore() throws -> (WidgetSnapshotStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-widget-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (WidgetSnapshotStore(directory: directory), directory)
    }

    @Test("snapshot round-trips through the shared container")
    func snapshotRoundTrip() throws {
        let (store, directory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            totalUnread: 7,
            previews: [
                WidgetMessagePreview(
                    senderName: "Ina",
                    subject: "Hei",
                    receivedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    accountName: "Privat"
                )
            ]
        )
        store.save(snapshot)
        #expect(store.load() == snapshot)
    }

    @Test("missing file and missing container both read as nil")
    func missingReadsNil() throws {
        let (store, directory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(store.load() == nil)
        #expect(WidgetSnapshotStore(directory: nil).load() == nil)
    }

    @Test("a newer major schema version falls back to the empty state")
    func futureVersionReadsNil() throws {
        let (store, directory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        var snapshot = WidgetSnapshot(totalUnread: 1, previews: [])
        snapshot.version = WidgetSnapshot.currentVersion + 1
        store.save(snapshot)
        #expect(store.load() == nil)
    }
}
