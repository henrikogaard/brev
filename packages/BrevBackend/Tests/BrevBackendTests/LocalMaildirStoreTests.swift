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

@testable import BrevBackend
import Foundation
import Testing

@Suite("LocalMaildirStore")
struct LocalMaildirStoreTests {
    private static let message = """
    From: Alice <alice@example.com>
    To: Bob <bob@example.com>
    Subject: Hello Bob
    Date: Thu, 1 Jan 2026 10:00:00 +0000
    Message-ID: <m1@example.com>

    Body text.
    """

    private func makeStore() throws -> LocalMaildirStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("localmaildir-\(UUID().uuidString)", isDirectory: true)
        return LocalMaildirStore(rootURL: root)
    }

    @Test("createFolder writes the manifest and cur/new/tmp")
    func createFolder() async throws {
        let store = try makeStore()
        let record = try await store.createFolder(name: "Saved")
        #expect(!record.id.isEmpty)
        #expect(record.name == "Saved")
        #expect(try await store.folders().count == 1)
        let fm = FileManager.default
        for sub in ["cur", "new", "tmp"] {
            var isDir: ObjCBool = false
            let url = store.rootURL
                .appendingPathComponent(record.id)
                .appendingPathComponent(sub)
            #expect(fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue)
        }
    }

    @Test("append → enumerate round trip preserves bytes")
    func appendEnumerateRoundTrip() async throws {
        let store = try makeStore()
        let folder = try await store.createFolder(name: "Saved")
        let raw = Data(Self.message.utf8)
        let ref = try await store.append(rawMessage: raw, flags: [.seen], folderID: folder.id)
        let stored = try await store.enumerate(folderID: folder.id)
        #expect(stored.count == 1)
        #expect(stored[0].ref == ref)
        #expect(stored[0].flags == [.seen])
        #expect(stored[0].data == raw)
    }

    @Test("append lands in cur/ with the Maildir flag suffix")
    func appendFilenameSuffix() async throws {
        let store = try makeStore()
        let folder = try await store.createFolder(name: "Saved")
        let ref = try await store.append(
            rawMessage: Data(Self.message.utf8),
            flags: [.seen, .flagged],
            folderID: folder.id
        )
        let cur = store.rootURL
            .appendingPathComponent(folder.id)
            .appendingPathComponent("cur")
        let names = try FileManager.default.contentsOfDirectory(atPath: cur.path)
        #expect(names == ["\(ref.uniqueID):2,FS"])
    }

    @Test("setFlags renames the file and persists through a fresh store")
    func flagRenamePersists() async throws {
        let store = try makeStore()
        let folder = try await store.createFolder(name: "Saved")
        let ref = try await store.append(
            rawMessage: Data(Self.message.utf8),
            flags: [.seen],
            folderID: folder.id
        )
        try await store.setFlags([.seen, .replied], for: ref)
        // Fresh actor over the same root — filename flags are authoritative.
        let reopened = LocalMaildirStore(rootURL: store.rootURL)
        #expect(try await reopened.flags(for: ref) == [.seen, .replied])
    }

    @Test("remove deletes the file permanently")
    func removeDeletesFile() async throws {
        let store = try makeStore()
        let folder = try await store.createFolder(name: "Saved")
        let ref = try await store.append(
            rawMessage: Data(Self.message.utf8),
            flags: [],
            folderID: folder.id
        )
        try await store.remove(ref)
        #expect(try await store.enumerate(folderID: folder.id).isEmpty)
        await #expect(throws: (any Error).self) {
            try await store.flags(for: ref)
        }
    }

    @Test("size counts message bytes")
    func sizeCountsMessages() async throws {
        let store = try makeStore()
        let folder = try await store.createFolder(name: "Saved")
        _ = try await store.append(
            rawMessage: Data(Self.message.utf8),
            flags: [],
            folderID: folder.id
        )
        #expect(await store.size() > 0)
    }

    @Test("deleteFolder removes the directory and descendants")
    func deleteFolder() async throws {
        let store = try makeStore()
        let parent = try await store.createFolder(name: "Parent")
        let child = try await store.createFolder(name: "Child", parentID: parent.id)
        try await store.deleteFolder(id: parent.id)
        #expect(try await store.folders().isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: store.rootURL.appendingPathComponent(child.id).path
        ))
    }
}
