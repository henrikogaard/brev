#!/usr/bin/env bash
# Credential-free app-facing IMAP/SMTP mailbox smoke runner.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/brev-imap-smtp-local-smoke.XXXXXX")"
CACHE_DIR="${TMPDIR:-/tmp}/brev-imap-smtp-local-smoke-cache"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/Sources/BrevIMAPSMTPLocalSmoke" "$CACHE_DIR"

cat >"$WORK_DIR/Package.swift" <<EOF
// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "BrevIMAPSMTPLocalSmoke",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "$ROOT/packages/BrevBackend")
    ],
    targets: [
        .executableTarget(
            name: "BrevIMAPSMTPLocalSmoke",
            dependencies: [
                .product(name: "BrevBackend", package: "BrevBackend")
            ]
        )
    ]
)
EOF

cat >"$WORK_DIR/Sources/BrevIMAPSMTPLocalSmoke/main.swift" <<'EOF'
import BrevBackend
import Foundation

enum LocalSmokeError: Error, LocalizedError {
    case missingFolder(String)
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .missingFolder(let folder):
            "Expected folder \(folder) to be available."
        case .unexpected(let message):
            message
        }
    }
}

@main
struct BrevIMAPSMTPLocalSmoke {
    static func main() async throws {
        let sentRecorder = SentRecorder()
        let mutationRecorder = MailboxMutationRecorder()
        let folderMutationRecorder = FolderMutationRecorder()
        let smtpValidationRecorder = SMTPValidationRecorder()
        let idleRecorder = IMAPIdleEventRecorder()
        let rawMessage = """
        From: Sender <sender@example.org>
        To: Person <person@example.org>
        Subject: Local smoke invoice
        Message-ID: <local-smoke-43@example.org>
        Date: Sun, 07 Jun 2026 08:00:00 +0000
        MIME-Version: 1.0
        Content-Type: multipart/mixed; boundary="mixed-boundary"

        --mixed-boundary
        Content-Type: text/html; charset=utf-8

        <p>Hello from local IMAP smoke.</p>
        --mixed-boundary
        Content-Type: text/plain; charset=utf-8

        Hello from local IMAP smoke.
        --mixed-boundary
        Content-Type: text/plain; name="receipt.txt"
        Content-Disposition: attachment; filename="receipt.txt"
        Content-Transfer-Encoding: base64

        SGVsbG8gYXR0YWNobWVudAo=
        --mixed-boundary--
        """
        let inboxListingState = InboxListingState()

        let persistentSmokeDefaultsName = "app.brev.imap-smtp-local-smoke.\(UUID().uuidString)"
        guard let persistentSmokeDefaults = UserDefaults(suiteName: persistentSmokeDefaultsName) else {
            throw LocalSmokeError.unexpected("Expected temporary smoke UserDefaults suite.")
        }
        persistentSmokeDefaults.removePersistentDomain(forName: persistentSmokeDefaultsName)
        defer {
            persistentSmokeDefaults.removePersistentDomain(forName: persistentSmokeDefaultsName)
        }
        let persistentSmokeRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("brev-imap-smtp-local-smoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: persistentSmokeRoot,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: persistentSmokeRoot)
        }

        let persistentSmokeCredentialService = "app.brev.imap-smtp-local-smoke.\(UUID().uuidString).credentials"

        func makeConnector(
            failFolderListing: Bool = false,
            failMessageListing: Bool = false,
            failSourceFetch: Bool = false
        ) -> IMAPAccountConnector {
            let restoredCredentialStore = KeychainMailCredentialStore(
                service: persistentSmokeCredentialService
            )
            let restoredAccountStore = UserDefaultsAccountStore(
                userDefaults: persistentSmokeDefaults,
                key: "accounts"
            )
            let restoredConfigurationStore = UserDefaultsIMAPAccountConfigurationStore(
                userDefaults: persistentSmokeDefaults,
                key: "imap-configurations"
            )
            let restoredFolderCache = FileBackedIMAPFolderSnapshotCache(
                rootDirectory: persistentSmokeRoot.appendingPathComponent("folders")
            )
            let restoredHeaderCache = FileBackedIMAPMailboxHeaderCache(
                rootDirectory: persistentSmokeRoot.appendingPathComponent("headers")
            )
            let restoredSourceCache = FileIMAPMessageSourceCache(
                rootDirectory: persistentSmokeRoot.appendingPathComponent("sources")
            )
            let restoredDraftStagingStore = FileIMAPDraftStagingStore(
                rootDirectory: persistentSmokeRoot.appendingPathComponent("drafts")
            )
            return IMAPAccountConnector(
            accountStore: restoredAccountStore,
            configurationStore: restoredConfigurationStore,
            credentialStore: restoredCredentialStore,
            listFolders: { _, _ in
                if failFolderListing {
                    throw LocalSmokeError.unexpected("Simulated folder listing outage.")
                }
                return [
                    IMAPFolderListing(
                        path: "INBOX",
                        displayName: "Inbox",
                        delimiter: "/",
                        flags: [],
                        role: .inbox
                    ),
                    IMAPFolderListing(
                        path: "Sent",
                        displayName: "Sent",
                        delimiter: "/",
                        flags: ["\\Sent"],
                        role: .sent
                    ),
                    IMAPFolderListing(
                        path: "Drafts",
                        displayName: "Drafts",
                        delimiter: "/",
                        flags: ["\\Drafts"],
                        role: .drafts
                    ),
                    IMAPFolderListing(
                        path: "Archive",
                        displayName: "Archive",
                        delimiter: "/",
                        flags: ["\\Archive"],
                        role: .archive
                    ),
                    IMAPFolderListing(
                        path: "Trash",
                        displayName: "Trash",
                        delimiter: "/",
                        flags: ["\\Trash"],
                        role: .trash
                    ),
                ]
            },
            validateOutgoingServer: { _, _ in
                await smtpValidationRecorder.recordValidation()
            },
            createFolder: { _, _, folderID in
                await folderMutationRecorder.recordCreate(folderID: folderID)
            },
            renameFolder: { _, _, folderID, newFolderID in
                await folderMutationRecorder.recordRename(folderID: folderID, newFolderID: newFolderID)
            },
            deleteFolder: { _, _, folderID in
                await folderMutationRecorder.recordDelete(folderID: folderID)
            },
            listMessages: { _, _, folderID, pageToken, limit in
                if failMessageListing {
                    throw LocalSmokeError.unexpected("Simulated message listing outage.")
                }
                if folderID == "Trash", pageToken == nil, limit == 100 {
                    return IMAPMessageListingPage(
                        messages: [
                            IMAPMessageListing(
                                uid: 9,
                                messageID: "<local-smoke-trash-9@example.org>",
                                subject: "Trash flush one",
                                from: Correspondent(name: "Sender", email: "sender@example.org"),
                                to: [Correspondent(name: "Person", email: "person@example.org")],
                                cc: [],
                                bcc: [],
                                date: Date(timeIntervalSince1970: 1_780_750_700),
                                isRead: true,
                                isFlagged: false,
                                isAnswered: false
                            ),
                            IMAPMessageListing(
                                uid: 8,
                                messageID: "<local-smoke-trash-8@example.org>",
                                subject: "Trash flush two",
                                from: Correspondent(name: "Sender", email: "sender@example.org"),
                                to: [Correspondent(name: "Person", email: "person@example.org")],
                                cc: [],
                                bcc: [],
                                date: Date(timeIntervalSince1970: 1_780_750_600),
                                isRead: true,
                                isFlagged: false,
                                isAnswered: false
                            ),
                        ],
                        nextPageToken: nil
                    )
                }
                guard folderID == "INBOX", limit == 50 else {
                    return IMAPMessageListingPage(messages: [])
                }
                return await inboxListingState.page(pageToken: pageToken, limit: limit)
            },
            searchMessages: { _, _, folderID, query, limit in
                guard folderID == "INBOX",
                      query.text.localizedCaseInsensitiveContains("invoice"),
                      limit > 0
                else {
                    return []
                }
                return await inboxListingState.searchInvoice(limit: limit)
            },
            fetchMessageSource: { _, _, folderID, uid in
                if failSourceFetch {
                    throw LocalSmokeError.unexpected("Simulated message source fetch outage.")
                }
                guard folderID == "INBOX", uid == 43 else {
                    throw LocalSmokeError.unexpected("Unexpected source fetch \(folderID):\(uid).")
                }
                return IMAPMessageSource(uid: uid, rawMessage: rawMessage)
            },
            setMessageFlag: { _, _, folderID, uids, flag, isEnabled in
                await mutationRecorder.recordFlag(
                    folderID: folderID,
                    uids: uids,
                    flag: flag,
                    isEnabled: isEnabled
                )
            },
            moveMessages: { _, _, sourceFolderID, uids, destinationFolderID in
                await mutationRecorder.recordMove(
                    sourceFolderID: sourceFolderID,
                    uids: uids,
                    destinationFolderID: destinationFolderID
                )
            },
            permanentlyDeleteMessages: { _, _, folderID, uids in
                await mutationRecorder.recordPermanentDelete(folderID: folderID, uids: uids)
            },
            sendMessage: { _, _, submission in
                await sentRecorder.record(submission)
                return SendResult(sentMessageID: "smtp:local-smoke")
            },
            appendSentMessage: { _, _, folderID, messageData, flags in
                await sentRecorder.recordSentAppend(
                    folderID: folderID,
                    messageData: messageData,
                    flags: flags
                )
                return 9001
            },
            appendDraftMessage: { _, _, folderID, messageData, flags in
                await sentRecorder.recordDraftAppend(
                    folderID: folderID,
                    messageData: messageData,
                    flags: flags
                )
            },
            idleEvents: { _, _, folderID in
                guard folderID == "INBOX" else {
                    return AsyncThrowingStream { continuation in
                        continuation.finish(throwing: LocalSmokeError.unexpected(
                            "Expected IDLE subscription for INBOX, got \(folderID)."
                        ))
                    }
                }
                return await idleRecorder.stream()
            },
            folderCache: restoredFolderCache,
            headerCache: restoredHeaderCache,
            sourceCache: restoredSourceCache,
            draftStagingStore: restoredDraftStagingStore
            )
        }

        let connector = makeConnector()

        let request = IMAPAccountSetupRequest(
            emailAddress: "person@example.org",
            displayName: "Person",
            password: "local-app-password",
            discovery: MailAccountDiscoveryResult(
                domain: "example.org",
                displayName: nil,
                source: .manualFallback,
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
                    port: 465,
                    tlsMode: .implicit,
                    authentication: .password
                ),
                requiresManualReview: true
            )
        )

        let connected = try await connector.provisionAndConnect(request)
        let sourceID = MailSourceID(
            accountID: connected.account.id,
            mailboxID: connected.account.id
        )
        guard await smtpValidationRecorder.validationCount() == 1 else {
            throw LocalSmokeError.unexpected("Expected one SMTP setup credential validation.")
        }
        await connected.backend.disconnect()
        let freshConnector = makeConnector()
        guard let freshConnectorRestoredBackend = try await freshConnector.restore(connected.account) else {
            throw LocalSmokeError.unexpected("Expected provisioned IMAP account to restore from stored credentials through a fresh connector.")
        }
        let backend = freshConnectorRestoredBackend
        let folders = try await backend.folders()
        let sourceScopedFolders = try await backend.folders(in: sourceID)
        guard sourceScopedFolders.map(\.id) == folders.map(\.id) else {
            throw LocalSmokeError.unexpected("Expected source-scoped folders to match restored folder list.")
        }
        let listingOutageConnector = makeConnector(failFolderListing: true)
        guard let cachedFolderRestoreBackend = try await listingOutageConnector.restore(connected.account) else {
            throw LocalSmokeError.unexpected("Expected cached folder restore when folder listing is temporarily unavailable.")
        }
        let cachedFolderRestoreFolders = try await cachedFolderRestoreBackend.folders()
        guard cachedFolderRestoreFolders.map(\.id) == folders.map(\.id) else {
            throw LocalSmokeError.unexpected("Expected cached folder restore to reuse persisted folder snapshot.")
        }
        await cachedFolderRestoreBackend.disconnect()
        guard let inbox = folders.first(where: { $0.role == .inbox }) else {
            throw LocalSmokeError.missingFolder("INBOX")
        }
        guard let archive = folders.first(where: { $0.role == .archive }) else {
            throw LocalSmokeError.missingFolder("Archive")
        }
        guard folders.contains(where: { $0.role == .trash }) else {
            throw LocalSmokeError.missingFolder("Trash")
        }

        let page = try await backend.messages(in: inbox, pageToken: nil)
        guard page.headers.map(\.id) == ["INBOX:44", "INBOX:43"] else {
            throw LocalSmokeError.unexpected("Expected two INBOX messages, got \(page.headers.map(\.id)).")
        }
        let sourceScopedPage = try await backend.messages(in: inbox, sourceID: sourceID, pageToken: nil)
        guard sourceScopedPage.headers.map(\.id) == page.headers.map(\.id),
              sourceScopedPage.nextPageToken == page.nextPageToken
        else {
            throw LocalSmokeError.unexpected("Expected source-scoped first page to match unscoped first page.")
        }
        let messageListingOutageConnector = makeConnector(failMessageListing: true)
        guard let cachedMessagePageBackend = try await messageListingOutageConnector.restore(connected.account) else {
            throw LocalSmokeError.unexpected("Expected cached message-page restore when message listing is temporarily unavailable.")
        }
        let cachedMessagePage = try await cachedMessagePageBackend.messages(in: inbox, pageToken: nil)
        guard cachedMessagePage.headers.map(\.id) == page.headers.map(\.id),
              cachedMessagePage.nextPageToken == page.nextPageToken
        else {
            throw LocalSmokeError.unexpected("Expected cached first page to reuse persisted header cache.")
        }
        let sourceScopedCachedMessagePage = try await cachedMessagePageBackend.messages(
            in: inbox,
            sourceID: sourceID,
            pageToken: nil
        )
        guard sourceScopedCachedMessagePage.headers.map(\.id) == page.headers.map(\.id),
              sourceScopedCachedMessagePage.nextPageToken == page.nextPageToken
        else {
            throw LocalSmokeError.unexpected("Expected source-scoped cached first page to reuse persisted header cache.")
        }
        await cachedMessagePageBackend.disconnect()

        let olderPage = try await backend.messages(in: inbox, pageToken: "before:43")
        guard olderPage.headers.map(\.id) == ["INBOX:42", "INBOX:41"] else {
            throw LocalSmokeError.unexpected("Expected older INBOX page, got \(olderPage.headers.map(\.id)).")
        }

        let olderPageEventStream = backend.subscribeToChanges()
        await inboxListingState.replaceOlderPageWithRemoteChangeState()
        let reconciledOlderPage = try await backend.messages(in: inbox, pageToken: "before:43")
        guard reconciledOlderPage.headers.map(\.id) == ["INBOX:42"],
              reconciledOlderPage.headers[0].isRead,
              reconciledOlderPage.headers[0].isFlagged
        else {
            throw LocalSmokeError.unexpected("Expected reconciled older INBOX page to keep only updated INBOX:42.")
        }
        let expectedOlderPageEvents: [MailEvent] = [
            .messagesUpdated(folderID: "INBOX", messageIDs: ["INBOX:42"]),
            .messagesRemoved(folderID: "INBOX", messageIDs: ["INBOX:41"]),
        ]
        let olderPageEvents = try await nextEvents(
            from: olderPageEventStream,
            count: expectedOlderPageEvents.count
        )
        guard olderPageEvents == expectedOlderPageEvents else {
            throw LocalSmokeError.unexpected("Expected older page events \(expectedOlderPageEvents), got \(olderPageEvents).")
        }

        let refreshEventStream = backend.subscribeToChanges()
        await inboxListingState.replaceWithRemoteRefreshState()
        try await backend.refresh(folder: inbox)
        let expectedRefreshEvents: [MailEvent] = [
            .messagesUpdated(folderID: "INBOX", messageIDs: ["INBOX:43"]),
            .messagesRemoved(folderID: "INBOX", messageIDs: ["INBOX:44", "INBOX:42"]),
        ]
        let refreshEvents = try await nextEvents(
            from: refreshEventStream,
            count: expectedRefreshEvents.count
        )
        guard refreshEvents == expectedRefreshEvents else {
            throw LocalSmokeError.unexpected("Expected refresh events \(expectedRefreshEvents), got \(refreshEvents).")
        }
        let refreshedPage = try await backend.messages(in: inbox, pageToken: nil)
        guard refreshedPage.headers.map(\.id) == ["INBOX:43"],
              refreshedPage.headers[0].isRead,
              refreshedPage.headers[0].isFlagged
        else {
            throw LocalSmokeError.unexpected("Expected refreshed INBOX cache to keep only updated INBOX:43.")
        }
        let sourceScopedRefreshEventStream = backend.subscribeToChanges()
        await inboxListingState.replaceWithSourceScopedRefreshState()
        try await backend.refresh(folder: inbox, in: sourceID)
        let sourceScopedRefreshEvents = try await nextEvents(
            from: sourceScopedRefreshEventStream,
            count: 1
        )
        guard sourceScopedRefreshEvents == [
            .messagesUpdated(folderID: "INBOX", messageIDs: ["INBOX:43"]),
        ] else {
            throw LocalSmokeError.unexpected("Expected source-scoped refresh update event, got \(sourceScopedRefreshEvents).")
        }
        let sourceScopedRefreshedPage = try await backend.messages(in: inbox, sourceID: sourceID, pageToken: nil)
        guard sourceScopedRefreshedPage.headers.map(\.id) == ["INBOX:43"],
              sourceScopedRefreshedPage.headers[0].isRead,
              !sourceScopedRefreshedPage.headers[0].isFlagged
        else {
            throw LocalSmokeError.unexpected("Expected source-scoped refreshed INBOX cache to update INBOX:43.")
        }

        let idleSubscriptionCount = await idleRecorder.subscriptionCount
        let idleEventStream = backend.subscribeToChanges()
        try await idleRecorder.waitUntilSubscriptionCount(idleSubscriptionCount + 1)
        await inboxListingState.replaceWithIdleNewMessageState()
        await idleRecorder.emit(.exists(count: 2))
        let idleMessagesAddedEvent = try await nextEvents(
            from: idleEventStream,
            count: 1
        )
        guard idleMessagesAddedEvent == [
            .messagesAdded(folderID: "INBOX", messageIDs: ["INBOX:45"]),
        ] else {
            throw LocalSmokeError.unexpected("Expected IDLE new-mail refresh event, got \(idleMessagesAddedEvent).")
        }

        let searchResults = try await backend.search(SearchQuery(
            text: "invoice",
            folderID: inbox.id,
            execution: .serverOnly
        ))
        guard searchResults.map(\.id) == ["INBOX:43"] else {
            throw LocalSmokeError.unexpected("Expected server search to find INBOX:43, got \(searchResults.map(\.id)).")
        }
        let sourceScopedSearchResults = try await backend.search(
            SearchQuery(
                text: "invoice",
                folderID: inbox.id,
                execution: .serverOnly
            ),
            sourceID: sourceID
        )
        guard sourceScopedSearchResults.map(\.id) == ["INBOX:43"] else {
            throw LocalSmokeError.unexpected("Expected source-scoped server search to find INBOX:43, got \(sourceScopedSearchResults.map(\.id)).")
        }

        let body = try await backend.body(for: "INBOX:43")
        guard body.html?.contains("Hello from local IMAP smoke.") == true else {
            throw LocalSmokeError.unexpected("Expected HTML body to be parsed.")
        }
        let sourceScopedBody = try await backend.body(
            for: "INBOX:43",
            sourceID: sourceID
        )
        guard sourceScopedBody.html == body.html,
              sourceScopedBody.attachments.map(\.id) == body.attachments.map(\.id)
        else {
            throw LocalSmokeError.unexpected("Expected source-scoped body read to match unscoped body read.")
        }
        guard let attachment = body.attachments.first else {
            throw LocalSmokeError.unexpected("Expected parsed attachment.")
        }
        let attachmentData = try await backend.downloadAttachment(attachment)
        guard attachmentData == Data("Hello attachment\n".utf8) else {
            throw LocalSmokeError.unexpected("Expected attachment bytes to round trip.")
        }
        let sourceScopedAttachmentData = try await backend.downloadAttachment(
            attachment,
            sourceID: sourceID
        )
        guard sourceScopedAttachmentData == attachmentData else {
            throw LocalSmokeError.unexpected("Expected source-scoped attachment bytes to match unscoped download.")
        }
        let sourceFetchOutageConnector = makeConnector(failSourceFetch: true)
        guard let cachedSourceBackend = try await sourceFetchOutageConnector.restore(connected.account) else {
            throw LocalSmokeError.unexpected("Expected cached source restore when message source fetch is temporarily unavailable.")
        }
        let cachedSourceBody = try await cachedSourceBackend.body(for: "INBOX:43")
        guard cachedSourceBody.html == body.html,
              cachedSourceBody.attachments.map(\.id) == body.attachments.map(\.id),
              let cachedSourceAttachment = cachedSourceBody.attachments.first
        else {
            throw LocalSmokeError.unexpected("Expected cached source body to reuse persisted message source cache.")
        }
        let cachedSourceAttachmentData = try await cachedSourceBackend.downloadAttachment(cachedSourceAttachment)
        guard cachedSourceAttachmentData == attachmentData else {
            throw LocalSmokeError.unexpected("Expected cached source attachment bytes to reuse persisted message source cache.")
        }
        let sourceScopedCachedSourceBody = try await cachedSourceBackend.body(
            for: "INBOX:43",
            sourceID: sourceID
        )
        guard sourceScopedCachedSourceBody.html == body.html,
              sourceScopedCachedSourceBody.attachments.map(\.id) == body.attachments.map(\.id)
        else {
            throw LocalSmokeError.unexpected("Expected source-scoped cached source body to reuse persisted message source cache.")
        }
        let sourceScopedCachedSourceAttachmentData = try await cachedSourceBackend.downloadAttachment(
            cachedSourceAttachment,
            sourceID: sourceID
        )
        guard sourceScopedCachedSourceAttachmentData == attachmentData else {
            throw LocalSmokeError.unexpected("Expected source-scoped cached source attachment bytes to reuse persisted message source cache.")
        }
        await cachedSourceBackend.disconnect()

        let sourceScopedCreatedFolder = try await backend.createFolder(
            name: "Source Clients",
            parentID: nil,
            sourceID: sourceID
        )
        guard sourceScopedCreatedFolder.id == "Source Clients", sourceScopedCreatedFolder.role == .custom else {
            throw LocalSmokeError.unexpected("Expected source-scoped created folder fallback to describe Source Clients.")
        }
        let sourceScopedRenamedFolder = try await backend.renameFolder(
            id: sourceScopedCreatedFolder.id,
            name: "Source Clients 2026",
            sourceID: sourceID
        )
        guard sourceScopedRenamedFolder.id == "Source Clients 2026", sourceScopedRenamedFolder.role == .custom else {
            throw LocalSmokeError.unexpected("Expected source-scoped renamed folder fallback to describe Source Clients 2026.")
        }
        try await backend.deleteFolder(id: sourceScopedRenamedFolder.id, sourceID: sourceID)

        let createdFolder = try await backend.createFolder(name: "Clients", parentID: nil)
        guard createdFolder.id == "Clients", createdFolder.role == .custom else {
            throw LocalSmokeError.unexpected("Expected created folder fallback to describe Clients.")
        }
        let renamedFolder = try await backend.renameFolder(id: createdFolder.id, name: "Clients 2026")
        guard renamedFolder.id == "Clients 2026", renamedFolder.role == .custom else {
            throw LocalSmokeError.unexpected("Expected renamed folder fallback to describe Clients 2026.")
        }
        try await backend.deleteFolder(id: renamedFolder.id)

        let folderMutationCalls = await folderMutationRecorder.callSnapshots()
        let sourceScopedFolderMutationCalls: [FolderMutationRecorder.Call] = [
            .create(folderID: "Source Clients"),
            .rename(folderID: "Source Clients", newFolderID: "Source Clients 2026"),
            .delete(folderID: "Source Clients 2026"),
        ]
        guard folderMutationCalls == sourceScopedFolderMutationCalls + [
            .create(folderID: "Clients"),
            .rename(folderID: "Clients", newFolderID: "Clients 2026"),
            .delete(folderID: "Clients 2026"),
        ] else {
            throw LocalSmokeError.unexpected("Expected folder create/rename/delete operations, got \(folderMutationCalls).")
        }

        let mutationEventStream = backend.subscribeToChanges()
        try await backend.setRead(true, for: ["INBOX:43"], sourceID: sourceID)
        try await backend.setFlagged(true, for: ["INBOX:43"], sourceID: sourceID)
        try await backend.move(messageIDs: ["INBOX:43"], to: archive, sourceID: sourceID)
        try await backend.delete(messageIDs: ["INBOX:43"], sourceID: sourceID)
        try await backend.setRead(true, for: ["INBOX:43"])
        try await backend.setFlagged(true, for: ["INBOX:43"])
        try await backend.move(messageIDs: ["INBOX:43"], to: archive)
        try await backend.delete(messageIDs: ["INBOX:43"])
        try await backend.delete(messageIDs: ["Trash:7"])

        let expectedMutationEvents: [MailEvent] = [
            .messagesUpdated(folderID: "INBOX", messageIDs: ["INBOX:43"]),
            .messagesUpdated(folderID: "INBOX", messageIDs: ["INBOX:43"]),
            .messagesRemoved(folderID: "INBOX", messageIDs: ["INBOX:43"]),
            .folderRefreshed(folderID: "Archive"),
            .messagesRemoved(folderID: "INBOX", messageIDs: ["INBOX:43"]),
            .folderRefreshed(folderID: "Trash"),
            .messagesUpdated(folderID: "INBOX", messageIDs: ["INBOX:43"]),
            .messagesUpdated(folderID: "INBOX", messageIDs: ["INBOX:43"]),
            .messagesRemoved(folderID: "INBOX", messageIDs: ["INBOX:43"]),
            .folderRefreshed(folderID: "Archive"),
            .messagesRemoved(folderID: "INBOX", messageIDs: ["INBOX:43"]),
            .folderRefreshed(folderID: "Trash"),
            .messagesRemoved(folderID: "Trash", messageIDs: ["Trash:7"]),
        ]
        let mutationEvents = try await nextEvents(
            from: mutationEventStream,
            count: expectedMutationEvents.count
        )
        guard mutationEvents == expectedMutationEvents else {
            throw LocalSmokeError.unexpected("Expected mutation events \(expectedMutationEvents), got \(mutationEvents).")
        }

        let mutationCalls = await mutationRecorder.callSnapshots()
        let sourceScopedMutationCalls: [MailboxMutationRecorder.Call] = [
            .flag(folderID: "INBOX", uids: [43], flag: .seen, isEnabled: true),
            .flag(folderID: "INBOX", uids: [43], flag: .flagged, isEnabled: true),
            .move(sourceFolderID: "INBOX", uids: [43], destinationFolderID: "Archive"),
            .move(sourceFolderID: "INBOX", uids: [43], destinationFolderID: "Trash"),
        ]
        guard mutationCalls == sourceScopedMutationCalls + [
            .flag(folderID: "INBOX", uids: [43], flag: .seen, isEnabled: true),
            .flag(folderID: "INBOX", uids: [43], flag: .flagged, isEnabled: true),
            .move(sourceFolderID: "INBOX", uids: [43], destinationFolderID: "Archive"),
            .move(sourceFolderID: "INBOX", uids: [43], destinationFolderID: "Trash"),
            .permanentlyDelete(folderID: "Trash", uids: [7]),
        ] else {
            throw LocalSmokeError.unexpected("Expected read/flag/move/delete operations, got \(mutationCalls).")
        }

        try await backend.flushFolder(id: "Trash", sourceID: sourceID)
        let mutationCallsAfterSourceScopedFlush = await mutationRecorder.callSnapshots()
        guard mutationCallsAfterSourceScopedFlush == mutationCalls + [
            .permanentlyDelete(folderID: "Trash", uids: [9, 8]),
        ] else {
            throw LocalSmokeError.unexpected("Expected source-scoped folder flush operation, got \(mutationCallsAfterSourceScopedFlush).")
        }

        try await backend.flushFolder(id: "Trash")
        let mutationCallsAfterFlush = await mutationRecorder.callSnapshots()
        guard mutationCallsAfterFlush == mutationCallsAfterSourceScopedFlush + [
            .permanentlyDelete(folderID: "Trash", uids: [9, 8]),
        ] else {
            throw LocalSmokeError.unexpected("Expected folder flush operation, got \(mutationCallsAfterFlush).")
        }

        let sendResult = try await backend.send(draft: Draft(
            id: "local-smoke-draft",
            to: [Correspondent(name: "Friend", email: "friend@example.org")],
            subject: "Local SMTP smoke",
            htmlBody: "<p>Sent from local smoke.</p>"
        ))
        guard sendResult.sentMessageID == "9001" else {
            throw LocalSmokeError.unexpected("Expected SMTP send result.")
        }
        let submissions = await sentRecorder.submissionSnapshots()
        guard submissions.count == 1,
              submissions[0].senderEmail == "person@example.org",
              submissions[0].recipientEmails == ["friend@example.org"]
        else {
            throw LocalSmokeError.unexpected("Expected one SMTP submission.")
        }
        guard await sentRecorder.sentAppendCount() == 1 else {
            throw LocalSmokeError.unexpected("Expected one Sent folder append.")
        }

        let sourceScopedSendResult = try await backend.send(
            draft: Draft(
                id: "local-smoke-source-scoped-draft",
                to: [Correspondent(name: "Friend", email: "friend@example.org")],
                subject: "Local source scoped SMTP smoke",
                htmlBody: "<p>Sent from local smoke through source-scoped compose.</p>"
            ),
            sourceID: sourceID
        )
        guard sourceScopedSendResult.sentMessageID == "9001" else {
            throw LocalSmokeError.unexpected("Expected SMTP send result for source-scoped send.")
        }
        let sourceScopedSubmissions = await sentRecorder.submissionSnapshots()
        guard sourceScopedSubmissions.count == 2,
              sourceScopedSubmissions[1].senderEmail == "person@example.org",
              sourceScopedSubmissions[1].recipientEmails == ["friend@example.org"]
        else {
            throw LocalSmokeError.unexpected("Expected source-scoped SMTP submission.")
        }
        guard await sentRecorder.sentAppendCount() == 2 else {
            throw LocalSmokeError.unexpected("Expected Sent append for source-scoped send.")
        }

        let attachmentID = try await backend.uploadAttachment(
            draftID: "local-smoke-compose-draft",
            data: Data("invoice attachment\n".utf8),
            filename: "invoice.txt",
            mimeType: "text/plain",
            sourceID: sourceID
        )
        let savedDraft = try await backend.save(
            draft: Draft(
                id: "local-smoke-compose-draft",
                to: [Correspondent(name: "Friend", email: "friend@example.org")],
                subject: "Local SMTP smoke with attachment",
                htmlBody: "<p>Sent from local smoke with an attachment.</p>",
                attachmentIDs: [attachmentID]
            ),
            sourceID: sourceID
        )
        guard savedDraft.remoteID == "Drafts:77" else {
            throw LocalSmokeError.unexpected("Expected server-saved Drafts UID, got \(String(describing: savedDraft.remoteID)).")
        }
        let draftAppendsAfterSave = await sentRecorder.draftAppendSnapshots()
        guard draftAppendsAfterSave.count == 1,
              draftAppendsAfterSave[0].folderID == "Drafts",
              draftAppendsAfterSave[0].flags == [.draft]
        else {
            throw LocalSmokeError.unexpected("Expected one Drafts append with draft flag.")
        }
        let savedDraftMessage = String(data: draftAppendsAfterSave[0].messageData, encoding: .utf8) ?? ""
        guard savedDraftMessage.contains("Content-Disposition: attachment; filename=\"invoice.txt\""),
              savedDraftMessage.contains("aW52b2ljZSBhdHRhY2htZW50Cg==")
        else {
            throw LocalSmokeError.unexpected("Expected saved draft MIME to include staged attachment.")
        }

        let sentDraftCleanupStream = backend.subscribeToChanges()
        let attachmentSendResult = try await backend.send(draft: savedDraft)
        guard attachmentSendResult.sentMessageID == "9001" else {
            throw LocalSmokeError.unexpected("Expected SMTP send result for attachment draft.")
        }
        let sentDraftCleanupEvents = try await nextEvents(
            from: sentDraftCleanupStream,
            count: 1
        )
        guard sentDraftCleanupEvents == [
            .messagesRemoved(folderID: "Drafts", messageIDs: ["Drafts:77"]),
        ] else {
            throw LocalSmokeError.unexpected("Expected sent draft cleanup event, got \(sentDraftCleanupEvents).")
        }
        let attachmentSubmissions = await sentRecorder.submissionSnapshots()
        guard attachmentSubmissions.count == 3,
              attachmentSubmissions[2].senderEmail == "person@example.org",
              attachmentSubmissions[2].recipientEmails == ["friend@example.org"]
        else {
            throw LocalSmokeError.unexpected("Expected second SMTP submission for attachment draft.")
        }
        let sentAttachmentMessage = String(data: attachmentSubmissions[2].messageData, encoding: .utf8) ?? ""
        guard sentAttachmentMessage.contains("Content-Type: multipart/mixed;"),
              sentAttachmentMessage.contains("Content-Disposition: attachment; filename=\"invoice.txt\""),
              sentAttachmentMessage.contains("aW52b2ljZSBhdHRhY2htZW50Cg==")
        else {
            throw LocalSmokeError.unexpected("Expected SMTP MIME to include staged attachment.")
        }
        guard await sentRecorder.sentAppendCount() == 3 else {
            throw LocalSmokeError.unexpected("Expected Sent append for attachment draft.")
        }

        let discardAttachmentID = try await backend.uploadAttachment(
            draftID: "local-smoke-discard-draft",
            data: Data("discard attachment\n".utf8),
            filename: "discard.txt",
            mimeType: "text/plain",
            sourceID: sourceID
        )
        let discardedDraft = try await backend.save(
            draft: Draft(
                id: "local-smoke-discard-draft",
                to: [Correspondent(email: "discard@example.org")],
                subject: "Discard me",
                htmlBody: "<p>This draft should be removed.</p>",
                attachmentIDs: [discardAttachmentID]
            ),
            sourceID: sourceID
        )
        guard discardedDraft.remoteID == "Drafts:78" else {
            throw LocalSmokeError.unexpected("Expected discard draft UID, got \(String(describing: discardedDraft.remoteID)).")
        }
        guard let discardRemoteID = discardedDraft.remoteID else {
            throw LocalSmokeError.unexpected("Expected discard draft to have a remote ID.")
        }
        let discardedDraftCleanupStream = backend.subscribeToChanges()
        try await backend.discard(draftID: discardRemoteID, sourceID: sourceID)
        let discardedDraftCleanupEvents = try await nextEvents(
            from: discardedDraftCleanupStream,
            count: 1
        )
        guard discardedDraftCleanupEvents == [
            .messagesRemoved(folderID: "Drafts", messageIDs: ["Drafts:78"]),
        ] else {
            throw LocalSmokeError.unexpected("Expected discarded draft cleanup event, got \(discardedDraftCleanupEvents).")
        }

        let finalMutationCalls = await mutationRecorder.callSnapshots()
        guard finalMutationCalls == mutationCallsAfterFlush + [
            .permanentlyDelete(folderID: "Drafts", uids: [77]),
            .permanentlyDelete(folderID: "Drafts", uids: [78]),
        ] else {
            throw LocalSmokeError.unexpected("Expected remote draft cleanup operations, got \(finalMutationCalls).")
        }
        guard await sentRecorder.draftAppendCount() == 2 else {
            throw LocalSmokeError.unexpected("Expected two Drafts appends.")
        }

        await backend.disconnect()
        await freshConnector.removeAccount(connected.account.id)

        print("IMAP local: added account, restored it with a fresh persistent-store and Keychain-backed connector, restored \(cachedFolderRestoreFolders.count) cached folders, \(cachedMessagePage.headers.count) cached messages, and cached body/attachment data during listing/source outages, listed \(folders.count) folders plus \(sourceScopedFolders.count) source-scoped folders, loaded \(page.headers.count) messages plus \(sourceScopedPage.headers.count) source-scoped messages, searched \(searchResults.count) message plus \(sourceScopedSearchResults.count) source-scoped message, and downloaded \(attachmentData.count) attachment bytes")
        print("IMAP local: recorded \(sourceScopedFolderMutationCalls.count) source-scoped folder operations and \(folderMutationCalls.count) total folder create/rename/delete operations")
        print("IMAP local: reconciled older page with \(olderPageEvents.count) update/removal events, remote refresh with \(refreshEvents.count) update/removal events, source-scoped refresh with \(sourceScopedRefreshEvents.count) update event, and IDLE with \(idleMessagesAddedEvent.count) new-mail event")
        print("IMAP local: recorded \(sourceScopedMutationCalls.count) source-scoped operations and \(mutationCalls.count) total read/flag/move/delete operations with \(mutationEvents.count) mutation events, 2 folder flushes, and 2 remote draft cleanup operations")
        print("IMAP local: saved/discarded 2 Drafts appends with \(sentDraftCleanupEvents.count + discardedDraftCleanupEvents.count) cleanup events")
        print("SMTP local: validated setup credentials, submitted \(attachmentSubmissions.count) messages, including staged attachment MIME, and appended Sent copies")
        print("imap-smtp-local-smoke: OK")
    }

    private static func nextEvents(
        from stream: AsyncStream<MailEvent>,
        count: Int,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async throws -> [MailEvent] {
        try await withThrowingTaskGroup(of: [MailEvent].self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                var events = [MailEvent]()
                while events.count < count {
                    guard let event = await iterator.next() else { break }
                    events.append(event)
                }
                return events
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw LocalSmokeError.unexpected("Timed out waiting for \(count) mutation event(s).")
            }

            let events = try await group.next() ?? []
            group.cancelAll()
            guard events.count == count else {
                throw LocalSmokeError.unexpected("Expected \(count) mutation event(s), got \(events.count).")
            }
            return events
        }
    }
}

private actor InboxListingState {
    private var firstPageMessages: [IMAPMessageListing]
    private var olderPageMessages: [IMAPMessageListing]

    init() {
        firstPageMessages = [
            InboxListingState.message(
                uid: 44,
                messageID: "<local-smoke-44@example.org>",
                subject: "Remote removal candidate",
                date: Date(timeIntervalSince1970: 1_780_750_900),
                isRead: false,
                isFlagged: false
            ),
            InboxListingState.message(
                uid: 43,
                messageID: "<local-smoke-43@example.org>",
                subject: "Local smoke invoice",
                date: Date(timeIntervalSince1970: 1_780_750_800),
                isRead: false,
                isFlagged: false
            ),
        ]
        olderPageMessages = [
            InboxListingState.message(
                uid: 42,
                messageID: "<local-smoke-42@example.org>",
                subject: "Older update candidate",
                date: Date(timeIntervalSince1970: 1_780_750_700),
                isRead: false,
                isFlagged: false
            ),
            InboxListingState.message(
                uid: 41,
                messageID: "<local-smoke-41@example.org>",
                subject: "Older removal candidate",
                date: Date(timeIntervalSince1970: 1_780_750_600),
                isRead: false,
                isFlagged: false
            ),
        ]
    }

    func page(pageToken: String?, limit: Int) -> IMAPMessageListingPage {
        if pageToken == "before:43" {
            return IMAPMessageListingPage(
                messages: Array(olderPageMessages.prefix(limit)),
                nextPageToken: nil
            )
        }
        guard pageToken == nil else {
            return IMAPMessageListingPage(messages: [])
        }
        return IMAPMessageListingPage(
            messages: Array(firstPageMessages.prefix(limit)),
            nextPageToken: olderPageMessages.isEmpty ? nil : "before:43"
        )
    }

    func searchInvoice(limit: Int) -> [IMAPMessageListing] {
        Array(firstPageMessages.filter { message in
            message.subject.localizedCaseInsensitiveContains("invoice")
        }.prefix(limit))
    }

    func replaceOlderPageWithRemoteChangeState() {
        olderPageMessages = [
            Self.message(
                uid: 42,
                messageID: "<local-smoke-42@example.org>",
                subject: "Older update candidate",
                date: Date(timeIntervalSince1970: 1_780_750_700),
                isRead: true,
                isFlagged: true
            ),
        ]
    }

    func replaceWithRemoteRefreshState() {
        firstPageMessages = [
            Self.message(
                uid: 43,
                messageID: "<local-smoke-43@example.org>",
                subject: "Local smoke invoice",
                date: Date(timeIntervalSince1970: 1_780_750_800),
                isRead: true,
                isFlagged: true
            ),
        ]
        olderPageMessages = []
    }

    func replaceWithSourceScopedRefreshState() {
        firstPageMessages = [
            Self.message(
                uid: 43,
                messageID: "<local-smoke-43@example.org>",
                subject: "Local smoke invoice",
                date: Date(timeIntervalSince1970: 1_780_750_800),
                isRead: true,
                isFlagged: false
            ),
        ]
        olderPageMessages = []
    }

    func replaceWithIdleNewMessageState() {
        firstPageMessages = [
            Self.message(
                uid: 45,
                messageID: "<local-smoke-45@example.org>",
                subject: "Local smoke IDLE new mail",
                date: Date(timeIntervalSince1970: 1_780_751_000),
                isRead: false,
                isFlagged: false
            ),
            Self.message(
                uid: 43,
                messageID: "<local-smoke-43@example.org>",
                subject: "Local smoke invoice",
                date: Date(timeIntervalSince1970: 1_780_750_800),
                isRead: true,
                isFlagged: false
            ),
        ]
        olderPageMessages = []
    }

    private nonisolated static func message(
        uid: Int,
        messageID: String,
        subject: String,
        date: Date,
        isRead: Bool,
        isFlagged: Bool
    ) -> IMAPMessageListing {
        IMAPMessageListing(
            uid: uid,
            messageID: messageID,
            subject: subject,
            from: Correspondent(name: "Sender", email: "sender@example.org"),
            to: [Correspondent(name: "Person", email: "person@example.org")],
            cc: [],
            bcc: [],
            date: date,
            isRead: isRead,
            isFlagged: isFlagged,
            isAnswered: false
        )
    }
}

private actor SMTPValidationRecorder {
    private var validations = 0

    func recordValidation() {
        validations += 1
    }

    func validationCount() -> Int {
        validations
    }
}

private actor FolderMutationRecorder {
    enum Call: Equatable, Sendable, CustomStringConvertible {
        case create(folderID: String)
        case rename(folderID: String, newFolderID: String)
        case delete(folderID: String)

        var description: String {
            switch self {
            case .create(let folderID):
                "create(\(folderID))"
            case .rename(let folderID, let newFolderID):
                "rename(\(folderID), \(newFolderID))"
            case .delete(let folderID):
                "delete(\(folderID))"
            }
        }
    }

    private var calls: [Call] = []

    func recordCreate(folderID: String) {
        calls.append(.create(folderID: folderID))
    }

    func recordRename(folderID: String, newFolderID: String) {
        calls.append(.rename(folderID: folderID, newFolderID: newFolderID))
    }

    func recordDelete(folderID: String) {
        calls.append(.delete(folderID: folderID))
    }

    func callSnapshots() -> [Call] {
        calls
    }
}

private actor MailboxMutationRecorder {
    enum Call: Equatable, Sendable, CustomStringConvertible {
        case flag(folderID: String, uids: [Int], flag: IMAPSystemFlag, isEnabled: Bool)
        case move(sourceFolderID: String, uids: [Int], destinationFolderID: String)
        case permanentlyDelete(folderID: String, uids: [Int])

        var description: String {
            switch self {
            case .flag(let folderID, let uids, let flag, let isEnabled):
                "flag(\(folderID), \(uids), \(flag), \(isEnabled))"
            case .move(let sourceFolderID, let uids, let destinationFolderID):
                "move(\(sourceFolderID), \(uids), \(destinationFolderID))"
            case .permanentlyDelete(let folderID, let uids):
                "permanentlyDelete(\(folderID), \(uids))"
            }
        }
    }

    private var calls: [Call] = []

    func recordFlag(folderID: String, uids: [Int], flag: IMAPSystemFlag, isEnabled: Bool) {
        calls.append(.flag(folderID: folderID, uids: uids, flag: flag, isEnabled: isEnabled))
    }

    func recordMove(sourceFolderID: String, uids: [Int], destinationFolderID: String) {
        calls.append(.move(
            sourceFolderID: sourceFolderID,
            uids: uids,
            destinationFolderID: destinationFolderID
        ))
    }

    func recordPermanentDelete(folderID: String, uids: [Int]) {
        calls.append(.permanentlyDelete(folderID: folderID, uids: uids))
    }

    func callSnapshots() -> [Call] {
        calls
    }
}

private actor IMAPIdleEventRecorder {
    private var continuations: [AsyncThrowingStream<IMAPIdleEvent, any Error>.Continuation] = []
    private var subscriptionWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var subscriptionCount = 0

    func stream() -> AsyncThrowingStream<IMAPIdleEvent, any Error> {
        AsyncThrowingStream { continuation in
            install(continuation)
        }
    }

    func waitUntilSubscriptionCount(_ count: Int) async throws {
        if subscriptionCount >= count { return }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    Task {
                        await self.setSubscriptionWaiter(
                            count: count,
                            continuation: continuation
                        )
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                throw LocalSmokeError.unexpected("Timed out waiting for IDLE subscription \(count).")
            }
            try await group.next()
            group.cancelAll()
        }
    }

    func emit(_ event: IMAPIdleEvent) {
        for continuation in continuations {
            continuation.yield(event)
        }
    }

    private func install(_ continuation: AsyncThrowingStream<IMAPIdleEvent, any Error>.Continuation) {
        continuations.append(continuation)
        subscriptionCount += 1
        resumeSatisfiedWaiters()
    }

    private func setSubscriptionWaiter(
        count: Int,
        continuation: CheckedContinuation<Void, Never>
    ) {
        if subscriptionCount >= count {
            continuation.resume()
        } else {
            subscriptionWaiters.append((count, continuation))
        }
    }

    private func resumeSatisfiedWaiters() {
        let satisfied = subscriptionWaiters.filter { subscriptionCount >= $0.count }
        subscriptionWaiters.removeAll { subscriptionCount >= $0.count }
        for waiter in satisfied {
            waiter.continuation.resume()
        }
    }
}

private actor SentRecorder {
    private(set) var submissions: [SMTPMessageSubmission] = []
    private var appendedSentMessages: [AppendSnapshot] = []
    private var appendedDraftMessages: [AppendSnapshot] = []
    private var nextDraftUID = 77

    struct AppendSnapshot: Sendable {
        let folderID: String
        let messageData: Data
        let flags: Set<IMAPSystemFlag>
    }

    func record(_ submission: SMTPMessageSubmission) {
        submissions.append(submission)
    }

    func recordSentAppend(
        folderID: String,
        messageData: Data,
        flags: Set<IMAPSystemFlag>
    ) {
        appendedSentMessages.append(AppendSnapshot(
            folderID: folderID,
            messageData: messageData,
            flags: flags
        ))
    }

    func recordDraftAppend(
        folderID: String,
        messageData: Data,
        flags: Set<IMAPSystemFlag>
    ) -> Int {
        appendedDraftMessages.append(AppendSnapshot(
            folderID: folderID,
            messageData: messageData,
            flags: flags
        ))
        defer { nextDraftUID += 1 }
        return nextDraftUID
    }

    func submissionSnapshots() -> [SMTPMessageSubmission] {
        submissions
    }

    func sentAppendCount() -> Int {
        appendedSentMessages.count
    }

    func draftAppendSnapshots() -> [AppendSnapshot] {
        appendedDraftMessages
    }

    func draftAppendCount() -> Int {
        appendedDraftMessages.count
    }
}
EOF

swift run \
  --package-path "$WORK_DIR" \
  --scratch-path "$CACHE_DIR" \
  -c debug \
  BrevIMAPSMTPLocalSmoke
