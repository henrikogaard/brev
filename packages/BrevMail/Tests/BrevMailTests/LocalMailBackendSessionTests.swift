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
@testable import BrevMail
import Foundation
import Testing

@Suite("AppSession local backend (ADR-0077)")
@MainActor
struct LocalMailBackendSessionTests {
    private static func makeLocalBackend() -> LocalMailBackend {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-local-\(UUID().uuidString)", isDirectory: true)
        return LocalMailBackend(store: LocalMaildirStore(rootURL: root))
    }

    @Test("local backend is registered in backends")
    func registered() {
        let local = Self.makeLocalBackend()
        let session = AppSession(
            localBackend: local,
            accountStore: InMemoryAccountStore(),
            tokenStore: LocalInMemoryTokenStore()
        )
        #expect(session.backends[LocalMailBackend.accountID] != nil)
        #expect(session.localBackend != nil)
    }

    @Test("local backend is hidden from visibleBackends until it has a folder")
    func hiddenUntilFoldersExist() async {
        let local = Self.makeLocalBackend()
        let session = AppSession(
            backend: MockBackend(),
            localBackend: local,
            accountStore: InMemoryAccountStore(),
            tokenStore: LocalInMemoryTokenStore()
        )
        // Let the refreshLocalFolders task land.
        try? await Task.sleep(nanoseconds: 50_000_000)
        session.refreshLocalFolders()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(session.visibleBackends.contains {
            $0.account.id == LocalMailBackend.accountID
        } == false)

        _ = try? await local.createFolder(name: "Saved", parentID: nil)
        session.refreshLocalFolders()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(session.visibleBackends.contains {
            $0.account.id == LocalMailBackend.accountID
        })
    }
}

@Suite("LocalMailTransfer")
struct LocalMailTransferTests {
    private static let raw = Data("From: a@example.com\r\nSubject: x\r\n\r\nbody".utf8)

    @Test("copy never touches the source delete path")
    func copyDoesNotDelete() async {
        let deleted = Recorder()
        let transfer = LocalMailTransfer(
            fetchRaw: { _ in Self.raw },
            writeLocal: { _ in "local:1" },
            deleteSource: { deleted.append($0) }
        )
        let result = await transfer.copy(["m1", "m2"])
        #expect(result.copiedIDs.count == 2)
        #expect(deleted.values.isEmpty)
    }

    @Test("move deletes the source only after the local write succeeds")
    func moveDeletesAfterWrite() async {
        let order = Recorder()
        let deleted = Recorder()
        let transfer = LocalMailTransfer(
            fetchRaw: { id in order.append("fetch:\(id)"); return Self.raw },
            writeLocal: { _ in order.append("write"); return "local:x" },
            deleteSource: { order.append("delete:\($0)"); deleted.append($0) }
        )
        let result = await transfer.move(["m1"])
        #expect(result.isClean)
        #expect(order.values == ["fetch:m1", "write", "delete:m1"])
        #expect(deleted.values == ["m1"])
        #expect(result.removedSourceIDs == ["m1"])
    }

    @Test("a failed source delete still reports the local copy")
    func failedDeleteKeepsLocalCopy() async {
        struct FailingDelete: Error {}
        let transfer = LocalMailTransfer(
            fetchRaw: { _ in Self.raw },
            writeLocal: { _ in "local:kept" },
            deleteSource: { _ in throw FailingDelete() }
        )
        let result = await transfer.move(["m1"])
        // The message exists locally — it is a copy success with a distinct
        // removal failure, and the source row must stay in the listing.
        #expect(result.copiedIDs == ["local:kept"])
        #expect(result.removedSourceIDs.isEmpty)
        #expect(result.failures.count == 1)
        #expect(result.failures[0].error.contains("could not be removed"))
    }

    @Test("a failing local write prevents the source delete")
    func failedWriteSkipsDelete() async {
        struct FailingStore: Error {}
        let deleted = Recorder()
        let transfer = LocalMailTransfer(
            fetchRaw: { _ in Self.raw },
            writeLocal: { _ in throw FailingStore() },
            deleteSource: { deleted.append($0) }
        )
        let result = await transfer.move(["m1", "m2"])
        #expect(result.copiedIDs.isEmpty)
        #expect(result.failures.count == 2)
        #expect(deleted.values.isEmpty)
    }

    @Test("a fetch failure prevents both the local write and the delete")
    func failedFetchSkipsEverything() async {
        struct FailingFetch: Error {}
        let calls = Recorder()
        let transfer = LocalMailTransfer(
            fetchRaw: { _ in throw FailingFetch() },
            writeLocal: { _ in calls.append("write"); return "x" },
            deleteSource: { _ in calls.append("delete") }
        )
        let result = await transfer.move(["m1"])
        #expect(result.failures.count == 1)
        #expect(calls.values.isEmpty)
    }
}

private actor LocalInMemoryTokenStore: TokenStore {
    private var tokens: [String: Token] = [:]

    func token(for accountID: String) -> Token? {
        tokens[accountID]
    }

    func setToken(_ token: Token, for accountID: String) {
        tokens[accountID] = token
    }

    func clearToken(for accountID: String) {
        tokens[accountID] = nil
    }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

@Suite("MailUndoableDelete permanence (ADR-0077)")
struct MailUndoableDeletePermanenceTests {
    private static let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
    private static let trash = Folder(id: "Trash", name: "Trash", role: .trash)
    private static let local = Folder(id: "saved", name: "Saved", role: .custom)

    @Test("a source with no Trash folder deletes permanently")
    func noTrashIsPermanent() {
        #expect(MailUndoableDelete.isPermanentDelete(from: Self.local, folders: [Self.local]))
    }

    @Test("deleting inside Trash is permanent")
    func insideTrashIsPermanent() {
        #expect(MailUndoableDelete.isPermanentDelete(
            from: Self.trash, folders: [Self.inbox, Self.trash]
        ))
    }

    @Test("a normal folder with a Trash fallback is undoable")
    func normalFolderIsUndoable() {
        #expect(!MailUndoableDelete.isPermanentDelete(
            from: Self.inbox, folders: [Self.inbox, Self.trash]
        ))
    }

    @Test("copy explains the no-Trash permanence and pluralizes")
    func permanentCopy() {
        let single = MailUndoableDelete.permanentDeleteMessage(count: 1, folders: [Self.local])
        #expect(single.contains("1 message"))
        #expect(single.contains("no Trash"))
        let many = MailUndoableDelete.permanentDeleteMessage(
            count: 3, folders: [Self.inbox, Self.trash]
        )
        #expect(many.contains("3 messages"))
        #expect(many.contains("already in Trash"))
    }
}
