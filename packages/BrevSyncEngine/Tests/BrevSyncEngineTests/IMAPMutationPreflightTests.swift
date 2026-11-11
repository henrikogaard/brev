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
@testable import BrevSyncEngine
import Foundation
import SQLite3
import Testing

@Suite("IMAP destructive mutation migration preflight")
struct IMAPMutationPreflightTests {
    enum Operation: String, CaseIterable, Sendable {
        case move, trash, permanentDelete, moveWithUndo, discardDraft, flushFolder, deleteFolder, junk
    }

    @Test("migration failure prevents every destructive entry point from touching the server", arguments: Operation.allCases)
    func failedMigration(operation: Operation) async throws {
        let fixture = try Fixture(failingFolder: "INBOX")
        defer { fixture.cleanUp() }
        let backend = fixture.backend(includeTrash: operation == .trash)
        try await backend.connect()
        await #expect(throws: MailBackendError.self) { try await perform(operation, backend: backend) }
        #expect(await fixture.calls.count == 0)
        #expect(try await fixture.queue.pending().isEmpty)
        #expect(try fixture.store.headersByID(["INBOX:1"], accountID: Self.account.id, folderID: "INBOX").count == 1)
        #expect(await fixture.legacy.snapshot(accountID: Self.account.id, folderID: "INBOX") != nil)
    }

    @Test(
        "unopened legacy headers migrate before removal and cannot replay after restart",
        arguments: [Operation.move, .trash, .permanentDelete, .moveWithUndo, .discardDraft]
    )
    func unopenedFolder(operation: Operation) async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let backend = fixture.backend(includeTrash: operation == .trash)
        try await backend.connect()
        try await perform(operation, backend: backend)
        #expect(await fixture.calls.count == 1)
        #expect(try fixture.store.headersByID(["INBOX:1"], accountID: Self.account.id, folderID: "INBOX").isEmpty)
        #expect(try fixture.store.headersByID(["INBOX:99"], accountID: Self.account.id, folderID: "INBOX").isEmpty)
        #expect(try fixture.store.hasPendingIMAPRecovery(accountID: Self.account.id, folderID: "INBOX"))
        let reopened = try BrevSyncEngine(databaseURL: fixture.databaseURL)
        try await IndexedIMAPMailboxHeaderCache(index: reopened, account: Self.account, legacy: fixture.legacy)
            .prepare(folderID: "INBOX")
        #expect(try await reopened.imapHeaders(ids: ["INBOX:1"], folderID: "INBOX", account: Self.account).isEmpty)
        #expect(try await reopened.imapHeaders(ids: ["INBOX:99"], folderID: "INBOX", account: Self.account).isEmpty)
        #expect(try await reopened.hasPendingIMAPRecovery(folderID: "INBOX", account: Self.account))
    }

    @Test("all source folders preflight before the first move or delete", arguments: [Operation.move, .trash])
    func wholeBatchPreflight(operation: Operation) async throws {
        let fixture = try Fixture(failingFolder: "Z-Archive")
        defer { fixture.cleanUp() }
        let backend = fixture.backend(includeTrash: operation == .trash)
        try await backend.connect()
        await #expect(throws: MailBackendError.self) {
            if operation == .move {
                try await backend.move(messageIDs: ["INBOX:1", "Z-Archive:1"], to: Self.destination)
            } else {
                try await backend.delete(messageIDs: ["INBOX:1", "Z-Archive:1"])
            }
        }
        #expect(await fixture.calls.count == 0)
        #expect(try fixture.store.headersByID(["INBOX:1"], accountID: Self.account.id, folderID: "INBOX").count == 1)
    }

    @Test("undo preflights its unopened source folder before reversing the move", arguments: [false, true])
    func undoPreflight(fails: Bool) async throws {
        let fixture = try Fixture(failingFolder: fails ? "Z-Archive" : nil)
        defer { fixture.cleanUp() }
        let backend = fixture.backend()
        try await backend.connect()
        let destination = Folder(id: "Z-Archive", name: "Archive", role: .archive)
        let undo = try #require(try await backend.moveWithUndo(messageIDs: ["INBOX:1"], from: Self.inbox, to: destination,
                                                               sourceID: MailSourceID(
                                                                   accountID: Self.account.id,
                                                                   mailboxID: Self.account.id
                                                               )))
        if fails {
            await #expect(throws: MailBackendError.self) { try await undo.restore() }
            #expect(await fixture.calls.count == 1)
            #expect(try fixture.store.headersByID(["Z-Archive:1"], accountID: Self.account.id, folderID: "Z-Archive").count == 1)
        } else {
            #expect(try await undo.restore() == ["INBOX:1": "INBOX:1"])
            #expect(await fixture.calls.count == 2)
            let reopened = try BrevSyncEngine(databaseURL: fixture.databaseURL)
            try await IndexedIMAPMailboxHeaderCache(index: reopened, account: Self.account, legacy: fixture.legacy)
                .prepare(folderID: "Z-Archive")
            #expect(try await reopened.imapHeaders(ids: ["Z-Archive:1"], folderID: "Z-Archive", account: Self.account).isEmpty)
            #expect(try await reopened.imapHeaders(ids: ["Z-Archive:99"], folderID: "Z-Archive", account: Self.account)
                .isEmpty)
            #expect(try await reopened.hasPendingIMAPRecovery(folderID: "Z-Archive", account: Self.account))
        }
    }

    private func perform(_ operation: Operation, backend: IMAPSMTPBackend) async throws {
        switch operation {
        case .move: try await backend.move(messageIDs: ["INBOX:1"], to: Self.destination)
        case .trash, .permanentDelete: try await backend.delete(messageIDs: ["INBOX:1"])
        case .moveWithUndo:
            _ = try await backend.moveWithUndo(messageIDs: ["INBOX:1"], from: Self.inbox, to: Self.destination,
                                               sourceID: MailSourceID(accountID: Self.account.id, mailboxID: Self.account.id))
        case .discardDraft: try await backend.discard(draftID: "INBOX:1")
        case .flushFolder: try await backend.flushFolder(id: "INBOX")
        case .deleteFolder: try await backend.deleteFolder(id: "INBOX")
        case .junk: try await backend.setJunk(true, for: ["INBOX:1"])
        }
    }

    private static let account = BrevAccount(id: "synthetic", displayName: "Synthetic", emailAddress: "reader@example.test")
    private static let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
    private static let destination = Folder(id: "Destination", name: "Destination", role: .custom)

    private struct Fixture {
        let root: URL
        let databaseURL: URL
        let store: SQLiteSyncStore
        let legacy: RetainedLegacyCache
        let calls = ServerCalls()
        let queue = MutationQueue()

        init(failingFolder: String? = nil) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("brev-mutation-preflight-\(UUID())")
            databaseURL = root.appendingPathComponent("index.sqlite")
            store = try SQLiteSyncStore(databaseURL: databaseURL)
            try store.ensureAccount(id: account.id)
            var snapshots: [String: IMAPMailboxHeaderCacheSnapshot] = [:]
            for folder in ["INBOX", "Z-Archive"] {
                let headers = [1, 99].map { uid in
                    MessageHeader(id: "\(folder):\(uid)", threadID: "t\(uid)", folderID: folder,
                                  from: Correspondent(email: "sender@example.test"), subject: "Synthetic", snippet: "",
                                  date: Date(timeIntervalSince1970: TimeInterval(uid)))
                }
                try store.storeIMAPPage(IMAPHeaderPageWrite(folderID: folder, pageToken: nil, headers: [headers[0]],
                                                            uidValidity: 777, highestModSeq: nil, nextPageToken: nil),
                                        accountID: account.id)
                snapshots[folder] = IMAPMailboxHeaderCacheSnapshot(headers: headers,
                                                                   uidValidity: folder == failingFolder ? 999 : 777)
            }
            legacy = RetainedLegacyCache(snapshots: snapshots)
            if let failingFolder {
                var db: OpaquePointer?
                #expect(sqlite3_open(databaseURL.path, &db) == SQLITE_OK)
                defer { sqlite3_close(db) }
                let sql = """
                    CREATE TRIGGER fail_archive BEFORE INSERT ON imap_legacy_recovery
                    WHEN NEW.folder_id = '\(failingFolder)'
                    BEGIN SELECT RAISE(ABORT, 'synthetic archive failure'); END;
                """
                #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
            }
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }

        func backend(includeTrash: Bool = false) -> IMAPSMTPBackend {
            let engine = BrevSyncEngine(store: store)
            let configuration = IMAPAccountConfiguration(
                accountID: account.id, emailAddress: account.emailAddress, displayName: account.displayName,
                incoming: MailServerSettings(kind: .imap, host: "imap.example.test", port: 993, tlsMode: .implicit,
                                             authentication: .password),
                outgoing: MailServerSettings(kind: .smtp, host: "smtp.example.test", port: 587, tlsMode: .startTLS,
                                             authentication: .password), credentialID: account.id
            )
            let credential = MailAccountCredential(incomingUsername: "fixture", outgoingUsername: "fixture",
                                                   secret: "fixture", authentication: .password)
            let calls = calls
            return IMAPSMTPBackend(
                account: account, configuration: configuration, credential: credential,
                listFolders: { _, _ in
                    var folders = [IMAPFolderListing(
                        path: "INBOX",
                        displayName: "Inbox",
                        delimiter: "/",
                        flags: [],
                        role: .inbox
                    )]
                    if includeTrash {
                        folders.append(IMAPFolderListing(
                            path: "Trash",
                            displayName: "Trash",
                            delimiter: "/",
                            flags: [],
                            role: .trash
                        ))
                    }
                    return folders
                }, deleteFolder: { _, _, _ in await calls.record() },
                listMessages: { _, _, _, _, _ in IMAPMessageListingPage(messages: []) },
                setMessageKeyword: { _, _, _, _, _, _ in await calls.record() },
                moveMessages: { _, _, _, _, _ in await calls.record() },
                moveMessagesWithResult: { _, _, _, uids, _, _ in
                    await calls.record()
                    return IMAPMoveResult(uidValidity: 777, uidMappings: Dictionary(uniqueKeysWithValues: uids.map { ($0, $0) }))
                }, permanentlyDeleteMessages: { _, _, _, _ in await calls.record() },
                headerCache: legacy, localSearchIndex: engine, offlineMutationQueue: queue
            )
        }
    }

    private actor ServerCalls {
        private(set) var count = 0
        func record() { count += 1 }
    }

    private actor MutationQueue: OfflineMutationQueue {
        private var mutations: [PendingMutation] = []
        func enqueue(_ mutation: PendingMutation) async throws { mutations.append(mutation) }
        func pending() async throws -> [PendingMutation] { mutations }
        func update(_ mutation: PendingMutation) async throws {
            if let index = mutations.firstIndex(where: { $0.id == mutation.id }) { mutations[index] = mutation }
        }

        func remove(id: UUID) async throws { mutations.removeAll { $0.id == id } }
        func removeAll() async throws { mutations.removeAll() }
    }

    private struct RetainedLegacyCache: IMAPMailboxHeaderCache {
        let snapshots: [Folder.ID: IMAPMailboxHeaderCacheSnapshot]
        func snapshot(accountID _: BrevAccount.ID,
                      folderID: Folder.ID) async -> IMAPMailboxHeaderCacheSnapshot? { snapshots[folderID] }
        func setSnapshot(_: IMAPMailboxHeaderCacheSnapshot, accountID _: BrevAccount.ID, folderID _: Folder.ID) async {}
        func clear(accountID _: BrevAccount.ID, folderID _: Folder.ID) async {}
        func clear(accountID _: BrevAccount.ID) async {}
    }
}
