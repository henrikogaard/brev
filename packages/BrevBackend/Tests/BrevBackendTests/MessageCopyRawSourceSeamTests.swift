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

@Suite("Message copy and raw-source seam")
struct MessageCopyRawSourceSeamTests {
    private static let account = BrevAccount(
        id: "imap-smtp:person@example.org",
        displayName: "Person",
        emailAddress: "person@example.org"
    )
    private static let sourceID = MailSourceID(
        accountID: "imap-smtp:person@example.org",
        mailboxID: "imap-smtp:person@example.org"
    )
    private static let configuration = IMAPAccountConfiguration(
        accountID: "imap-smtp:person@example.org",
        emailAddress: "person@example.org",
        displayName: "Person",
        incoming: MailServerSettings(
            kind: .imap,
            host: "imap.example.org",
            port: 993,
            tlsMode: .implicit,
            authentication: .password
        ),
        outgoing: MailServerSettings(
            kind: .smtp,
            host: "smtp.example.org",
            port: 587,
            tlsMode: .startTLS,
            authentication: .password
        ),
        credentialID: "imap-smtp:person@example.org"
    )
    private static let credential = MailAccountCredential(
        incomingUsername: "person@example.org",
        outgoingUsername: "person@example.org",
        secret: "secret",
        authentication: .password
    )

    // MARK: Capability flags

    @Test("extended capability flags are distinct")
    func extendedCapabilityFlagsAreDistinct() {
        #expect(BackendExtendedCapabilities.messageCopy.rawValue == 1 << 9)
        #expect(BackendExtendedCapabilities.rawMessageSource.rawValue == 1 << 10)
        #expect(BackendExtendedCapabilities.messageCopy != .rawMessageSource)
    }

    // MARK: Protocol defaults

    @Test("a backend without overrides advertises no extended capabilities")
    func defaultBackendHasNoExtendedCapabilities() async {
        let backend = MockBackend()
        #expect(backend.extendedCapabilities.isEmpty)
    }

    @Test("default copy implementation throws notSupported")
    func defaultCopyThrows() async {
        let backend = UnsupportedSeamBackend()
        await #expect(throws: MailBackendError.self) {
            try await backend.copy(
                messageIDs: ["INBOX:1"],
                to: Folder(id: "Archive", name: "Archive", role: .archive)
            )
        }
    }

    @Test("default raw-source implementation throws notSupported")
    func defaultRawSourceThrows() async {
        let backend = UnsupportedSeamBackend()
        await #expect(throws: MailBackendError.self) {
            _ = try await backend.rawSource(for: "INBOX:1")
        }
    }

    // MARK: IMAPSMTPBackend advertisement

    @Test("IMAP backend advertises copy and raw-source when operations are injected")
    func imapBackendAdvertisesExtendedCapabilities() {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            fetchMessageSource: { _, _, _, _ in IMAPMessageSource(uid: 1, rawMessage: "") },
            copyMessages: { _, _, _, _, _ in }
        )
        #expect(backend.extendedCapabilities.contains(.messageCopy))
        #expect(backend.extendedCapabilities.contains(.rawMessageSource))
    }

    @Test("IMAP backend advertises only cache-backed capabilities without optional operations")
    func imapBackendWithoutOperationsHasNoOptionalExtendedCapabilities() {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] }
        )
        // Threading and cached-header lookup are derived from stores every IMAP
        // backend owns, so they are always advertised; operation-backed flags
        // are not.
        #expect(backend.extendedCapabilities == [
            .clientSideThreading,
            .cachedMessageHeaders,
        ])
    }

    // MARK: Copy behaviour

    @Test("copy groups message IDs by source folder and leaves originals cached")
    func copyGroupsByFolderAndLeavesOriginals() async throws {
        let recorder = CopyRecorder()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        await sourceCache.setSource(
            IMAPMessageSource(uid: 43, rawMessage: "Content-Type: text/plain\n\nCached body."),
            accountID: Self.account.id,
            messageID: "INBOX:43"
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            copyMessages: { configuration, credential, sourceFolderID, uids, destinationFolderID in
                await recorder.record(
                    configuration: configuration,
                    credential: credential,
                    sourceFolderID: sourceFolderID,
                    uids: uids,
                    destinationFolderID: destinationFolderID
                )
            },
            sourceCache: sourceCache
        )
        try await backend.connect()

        try await backend.copy(
            messageIDs: ["INBOX:43", "INBOX:44", "Projects/Alpha:9"],
            to: Folder(id: "Archive", name: "Archive", role: .archive)
        )

        #expect(await recorder.calls == [
            CopyRecorder.Call(sourceFolderID: "INBOX", uids: [43, 44], destinationFolderID: "Archive"),
            CopyRecorder.Call(sourceFolderID: "Projects/Alpha", uids: [9], destinationFolderID: "Archive"),
        ])
        // Copy must NOT invalidate the original's cached source (unlike move).
        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:43") != nil)
    }

    @Test("copy without an operation throws notSupported")
    func copyWithoutOperationThrows() async throws {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] }
        )
        try await backend.connect()
        await #expect(throws: MailBackendError.self) {
            try await backend.copy(
                messageIDs: ["INBOX:43"],
                to: Folder(id: "Archive", name: "Archive", role: .archive)
            )
        }
    }

    @Test("queued copy mutation replays through the copy operation")
    func copyReplaysThroughPendingMutation() async throws {
        let recorder = CopyRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            copyMessages: { configuration, credential, sourceFolderID, uids, destinationFolderID in
                await recorder.record(
                    configuration: configuration,
                    credential: credential,
                    sourceFolderID: sourceFolderID,
                    uids: uids,
                    destinationFolderID: destinationFolderID
                )
            }
        )
        try await backend.connect()

        try await backend.apply(
            PendingMutation(
                kind: .copy(folderID: "Archive"),
                sourceID: nil,
                messageIDs: ["INBOX:43"]
            )
        )

        #expect(await recorder.calls == [
            CopyRecorder.Call(sourceFolderID: "INBOX", uids: [43], destinationFolderID: "Archive"),
        ])
    }

    // MARK: Raw-source behaviour

    @Test("raw source returns cached source without fetching")
    func rawSourceReturnsCachedSource() async throws {
        let sourceCache = InMemoryIMAPMessageSourceCache()
        await sourceCache.setSource(
            IMAPMessageSource(uid: 43, rawMessage: "Subject: Hi\n\nCached raw."),
            accountID: Self.account.id,
            messageID: "INBOX:43"
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sourceCache: sourceCache
        )
        try await backend.connect()

        let raw = try await backend.rawSource(for: "INBOX:43")
        #expect(raw == "Subject: Hi\n\nCached raw.")
    }

    @Test("raw source fetches on a cache miss then serves from cache")
    func rawSourceFetchesOnMissThenCaches() async throws {
        let recorder = SourceFetchRecorder(rawMessage: "Subject: Fetched\n\nFetched raw.")
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            fetchMessageSource: { configuration, credential, folderID, uid in
                try await recorder.fetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            },
            sourceCache: sourceCache
        )
        try await backend.connect()

        let raw = try await backend.rawSource(for: "INBOX:43")
        #expect(raw == "Subject: Fetched\n\nFetched raw.")
        #expect(await recorder.callCount == 1)

        let again = try await backend.rawSource(for: "INBOX:43")
        #expect(again == "Subject: Fetched\n\nFetched raw.")
        #expect(await recorder.callCount == 1)
    }
}

/// A backend implementing only the non-defaulted protocol requirements, so the
/// `copy`/`rawSource` protocol-extension defaults (which throw `.notSupported`)
/// are exercised. `MockBackend` now supports the seam and can no longer stand in
/// for an unsupported backend in the default-contract tests (ADR-0045).
private final class UnsupportedSeamBackend: MailBackend {
    let account = BrevAccount(id: "bare", displayName: "Bare", emailAddress: "bare@example.org")
    let capabilities: BackendCapabilities = []

    func connect() async throws {}
    func disconnect() async {}
    func subscribeToChanges() -> AsyncStream<MailEvent> { AsyncStream { $0.finish() } }

    // Remaining no-source requirements are unused by the default-contract tests;
    // `copy`/`rawSource` are deliberately omitted so the throwing protocol
    // extension defaults are exercised.
    func replayOfflineMutations() async {}
    func mailboxes() async throws -> [Mailbox] { fatalError("unused") }
    func currentMailbox() async throws -> Mailbox { fatalError("unused") }
    func switchMailbox(id: String) async throws { fatalError("unused") }
    func folders() async throws -> [Folder] { fatalError("unused") }
    func refresh(folder: Folder) async throws { fatalError("unused") }
    func createFolder(name: String, parentID: Folder.ID?) async throws -> Folder { fatalError("unused") }
    func renameFolder(id: Folder.ID, name: String) async throws -> Folder { fatalError("unused") }
    func deleteFolder(id: Folder.ID) async throws { fatalError("unused") }
    func flushFolder(id: Folder.ID) async throws { fatalError("unused") }
    func applyRetention(folderID: Folder.ID, retentionDays: Int?, keepsBodies: Bool) async {}
    func messages(in folder: Folder, pageToken: String?) async throws
        -> (headers: [MessageHeader], nextPageToken: String?) { fatalError("unused") }
    func body(for messageID: String) async throws -> MessageBody { fatalError("unused") }
    func downloadAttachment(_ attachment: BrevBackend.Attachment) async throws -> Data { fatalError("unused") }
    func setRead(_ isRead: Bool, for messageIDs: [String]) async throws { fatalError("unused") }
    func setFlagged(_ isFlagged: Bool, for messageIDs: [String]) async throws { fatalError("unused") }
    func setFlagColor(_ color: FlagColor?, for messageIDs: [String]) async throws { fatalError("unused") }
    func move(messageIDs: [String], to folder: Folder) async throws { fatalError("unused") }
    func delete(messageIDs: [String]) async throws { fatalError("unused") }
    func save(draft: Draft) async throws -> Draft { fatalError("unused") }
    func uploadAttachment(draftID: String, data: Data, filename: String,
                          mimeType: String) async throws -> String { fatalError("unused") }
    func discard(draftID: String) async throws { fatalError("unused") }
    func send(draft: Draft) async throws -> SendResult { fatalError("unused") }
    func listAliases() async throws -> [ServerAlias] { fatalError("unused") }
    func listServerSignatures() async throws -> [ServerSignature] { fatalError("unused") }
    func setJunk(_ isJunk: Bool, for messageIDs: [String]) async throws { fatalError("unused") }
    func blockSender(email: String) async throws { fatalError("unused") }
    func search(_ query: SearchQuery) async throws -> [MessageHeader] { fatalError("unused") }
    func calendarEvent(from attachmentID: String) async throws -> CalendarEvent { fatalError("unused") }
    func replyToCalendarInvite(messageID: String, response: AttendeeState) async throws { fatalError("unused") }
}

private actor CopyRecorder {
    struct Call: Equatable, Sendable {
        let sourceFolderID: String
        let uids: [Int]
        let destinationFolderID: String
    }

    private(set) var calls: [Call] = []

    func record(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        sourceFolderID: String,
        uids: [Int],
        destinationFolderID: String
    ) {
        calls.append(Call(
            sourceFolderID: sourceFolderID,
            uids: uids,
            destinationFolderID: destinationFolderID
        ))
    }
}

private actor SourceFetchRecorder {
    private let rawMessage: String
    private(set) var callCount = 0

    init(rawMessage: String) {
        self.rawMessage = rawMessage
    }

    func fetch(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: String,
        uid: Int
    ) async throws -> IMAPMessageSource {
        callCount += 1
        return IMAPMessageSource(uid: uid, rawMessage: rawMessage)
    }
}
