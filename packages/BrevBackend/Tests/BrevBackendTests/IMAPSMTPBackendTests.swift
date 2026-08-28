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

@Suite("IMAP SMTP backend")
struct IMAPSMTPBackendTests {
    @Test("connect leaves non-critical draft work for the UI startup phase")
    func connectLeavesNonCriticalDraftWorkForUIStartupPhase() async throws {
        let listingRecorder = MessageListingRecorder(messages: [])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "Drafts",
                    displayName: "Drafts",
                    delimiter: "/",
                    flags: ["drafts"],
                    role: .drafts
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await listingRecorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            }
        )

        try await backend.connect()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(await listingRecorder.callCount == 0)

        backend.startDeferredStartupWork()
        try await listingRecorder.waitUntilCallCount(1)
    }

    @Test("remote draft bodies are fetched only for local edits")
    func remoteDraftBodyReconciliationRequiresLocalEdits() {
        #expect(IMAPSMTPBackend.requiresRemoteDraftBodyReconciliation(nil) == false)
        #expect(IMAPSMTPBackend.requiresRemoteDraftBodyReconciliation(DraftSyncMetadata()) == false)
        #expect(IMAPSMTPBackend.requiresRemoteDraftBodyReconciliation(
            DraftSyncMetadata(isDirty: true)
        ))
    }

    @Test("deferred remote draft staging does not fetch draft bodies")
    func deferredRemoteDraftStagingDoesNotFetchDraftBodies() async throws {
        let listingRecorder = MessageListingRecorder(messages: [
            IMAPMessageListing(
                uid: 1,
                messageID: "<draft@example.org>",
                subject: "Draft",
                from: Correspondent(email: "person@example.org"),
                to: [Correspondent(email: "recipient@example.org")],
                cc: [],
                bcc: [],
                date: Date(timeIntervalSince1970: 1),
                isRead: true,
                isFlagged: false,
                isAnswered: false
            ),
        ])
        let bodyRecorder = MessageBodyRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "Drafts",
                    displayName: "Drafts",
                    delimiter: "/",
                    flags: ["drafts"],
                    role: .drafts
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await listingRecorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            fetchMessageBody: { configuration, credential, folderID, uid in
                await bodyRecorder.recordFetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            }
        )

        try await backend.connect()
        backend.startDeferredStartupWork()
        try await listingRecorder.waitUntilCallCount(1)
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(await bodyRecorder.callCount == 0)
    }

    @Test("deferred remote draft reconciliation fetches a locally edited draft body")
    func deferredRemoteDraftReconciliationFetchesLocallyEditedDraftBody() async throws {
        let listingRecorder = MessageListingRecorder(messages: [
            IMAPMessageListing(
                uid: 1,
                messageID: "<draft@example.org>",
                subject: "Draft",
                from: Correspondent(email: "person@example.org"),
                to: [Correspondent(email: "recipient@example.org")],
                cc: [],
                bcc: [],
                date: Date(timeIntervalSince1970: 1),
                isRead: true,
                isFlagged: false,
                isAnswered: false
            ),
        ])
        let bodyRecorder = MessageBodyRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "Drafts",
                    displayName: "Drafts",
                    delimiter: "/",
                    flags: ["drafts"],
                    role: .drafts
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await listingRecorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            fetchMessageBody: { configuration, credential, folderID, uid in
                await bodyRecorder.recordFetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            }
        )

        try await backend.connect()
        _ = try await backend.save(draft: Draft(
            id: "local-draft",
            remoteID: "Drafts:1",
            subject: "Local edits",
            htmlBody: "<p>Edited locally</p>"
        ))
        backend.startDeferredStartupWork()
        try await listingRecorder.waitUntilCallCount(1)
        try await bodyRecorder.waitUntilCallCount(1)

        #expect(await bodyRecorder.callCount == 1)
    }

    @Test("deferred remote draft discovery retries after a foreground read")
    func deferredRemoteDraftDiscoveryRetriesAfterForegroundRead() async throws {
        let listingRecorder = MessageListingRecorder(
            messages: [],
            firstCallDelayNanoseconds: 1_000_000_000
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "Drafts",
                    displayName: "Drafts",
                    delimiter: "/",
                    flags: ["drafts"],
                    role: .drafts
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await listingRecorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            }
        )

        try await backend.connect()
        backend.startDeferredStartupWork()
        try await listingRecorder.waitUntilCallCount(1)
        _ = try? await backend.body(for: "INBOX:1")
        try await listingRecorder.waitUntilCallCount(2)
        await backend.disconnect()

        #expect(await listingRecorder.callCount == 2)
    }

    @Test("cancelled remote draft body fetch does not stage a conflict")
    func cancelledRemoteDraftBodyFetchDoesNotStageConflict() async throws {
        let listingRecorder = MessageListingRecorder(messages: [
            IMAPMessageListing(
                uid: 1,
                messageID: "<draft@example.org>",
                subject: "Draft",
                from: Correspondent(email: "person@example.org"),
                to: [Correspondent(email: "recipient@example.org")],
                cc: [],
                bcc: [],
                date: Date(timeIntervalSince1970: 1),
                isRead: true,
                isFlagged: false,
                isAnswered: false
            ),
        ])
        let bodyRecorder = CancellableDraftBodyRecorder()
        let draftStore = DraftConflictRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "Drafts",
                    displayName: "Drafts",
                    delimiter: "/",
                    flags: ["drafts"],
                    role: .drafts
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await listingRecorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            fetchMessageBody: { configuration, credential, folderID, uid in
                try await bodyRecorder.fetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            },
            draftStagingStore: draftStore
        )

        try await backend.connect()
        _ = try await backend.save(draft: Draft(
            id: "local-draft",
            remoteID: "Drafts:1",
            subject: "Local edits",
            htmlBody: "<p>Edited locally</p>"
        ))
        backend.startDeferredStartupWork()
        try await bodyRecorder.waitUntilDraftFetchStarts()
        _ = try await backend.body(for: "INBOX:1")
        try await Task.sleep(nanoseconds: 50_000_000)
        await backend.disconnect()

        #expect(await draftStore.conflictDraftIDs.isEmpty)
    }

    @Test("opening a message cancels pending stale cache refreshes")
    func openingMessageCancelsPendingStaleCacheRefreshes() async throws {
        let header = MessageHeader(
            id: "Archive:1",
            threadID: "Archive:1",
            folderID: "Archive",
            from: Correspondent(email: "person@example.org"),
            to: [Correspondent(email: "recipient@example.org")],
            subject: "Cached",
            snippet: "Cached message",
            date: Date(timeIntervalSince1970: 1)
        )
        let headerCache = InMemoryIMAPMailboxHeaderCache(snapshotsByFolderByAccount: [
            Self.account.id: [
                "Archive": IMAPMailboxHeaderCacheSnapshot(headers: [header]),
            ],
        ])
        let listingRecorder = MessageListingRecorder(messages: [])
        let bodyRecorder = MessageBodyRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await listingRecorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            fetchMessageBody: { configuration, credential, folderID, uid in
                await bodyRecorder.recordFetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            },
            headerCache: headerCache
        )
        let archive = Folder(id: "Archive", name: "Archive", role: .archive)

        try await backend.connect()
        _ = try await backend.messages(in: archive, pageToken: nil)
        _ = try await backend.body(for: "INBOX:1")
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(await bodyRecorder.callCount == 1)
        #expect(await listingRecorder.callCount == 0)
    }

    @Test("sync health does not wait for a slow cache size scan")
    func syncHealthDoesNotWaitForSlowCacheSizeScan() async throws {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sourceCache: DelayedSizeIMAPMessageSourceCache()
        )
        try await backend.connect()

        let startedAt = Date()
        _ = await backend.syncHealth(for: MailSourceID(
            accountID: Self.account.id,
            mailboxID: Self.account.id
        ))

        #expect(Date().timeIntervalSince(startedAt) < 0.2)
    }

    @Test("startup cache restore makes persisted folders readable before remote connect")
    func startupCacheRestoreMakesPersistedFoldersReadableBeforeRemoteConnect() async throws {
        let cache = InMemoryIMAPFolderSnapshotCache(snapshotsByAccount: [
            Self.account.id: IMAPFolderCacheSnapshot(folders: [
                Folder(id: "INBOX", name: "Inbox", role: .inbox),
            ]),
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in
                throw MailBackendError.network(underlying: "offline")
            },
            folderCache: cache
        )

        #expect(await backend.restoreCachedFoldersForStartup())
        #expect(try await backend.folders().map(\.id) == ["INBOX"])
    }

    @Test("startup cache restore rejects an empty folder snapshot")
    func startupCacheRestoreRejectsEmptyFolderSnapshot() async throws {
        let cache = InMemoryIMAPFolderSnapshotCache(snapshotsByAccount: [
            Self.account.id: IMAPFolderCacheSnapshot(folders: []),
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            folderCache: cache
        )

        let restored = await backend.restoreCachedFoldersForStartup()
        #expect(!restored)
        await #expect(throws: MailBackendError.self) {
            _ = try await backend.folders()
        }
    }

    @Test("connect does not install an empty cache after remote failure")
    func connectDoesNotInstallEmptyCacheAfterRemoteFailure() async throws {
        let cache = InMemoryIMAPFolderSnapshotCache(snapshotsByAccount: [
            Self.account.id: IMAPFolderCacheSnapshot(folders: []),
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in
                throw MailBackendError.network(underlying: "offline")
            },
            folderCache: cache
        )

        await #expect(throws: MailBackendError.self) {
            try await backend.connect()
        }
        await #expect(throws: MailBackendError.self) {
            _ = try await backend.folders()
        }
    }

    @Test("connect does not use cached folders after IMAP authentication failure")
    func connectDoesNotUseCachedFoldersAfterAuthenticationFailure() async throws {
        let cache = InMemoryIMAPFolderSnapshotCache(snapshotsByAccount: [
            Self.account.id: IMAPFolderCacheSnapshot(folders: [
                Folder(id: "INBOX", name: "Inbox", role: .inbox),
            ]),
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in
                throw IMAPClientError.authenticationFailed("invalid credentials")
            },
            folderCache: cache
        )

        await #expect(throws: IMAPClientError.self) {
            try await backend.connect()
        }
        await #expect(throws: MailBackendError.self) {
            _ = try await backend.folders()
        }
    }

    @Test("connect does not use cached folders after permanent OAuth refresh failure")
    func connectDoesNotUseCachedFoldersAfterPermanentOAuthRefreshFailure() async throws {
        let cache = InMemoryIMAPFolderSnapshotCache(snapshotsByAccount: [
            Self.account.id: IMAPFolderCacheSnapshot(folders: [
                Folder(id: "INBOX", name: "Inbox", role: .inbox),
            ]),
        ])
        let xoauthCredential = MailAccountCredential(
            incomingUsername: Self.credential.incomingUsername,
            outgoingUsername: Self.credential.outgoingUsername,
            secret: "expired-access-token",
            authentication: .xoauth2
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: xoauthCredential,
            listFolders: { _, _ in
                throw IMAPClientError.authenticationFailed("invalid_grant")
            },
            refreshOAuthCredential: { _, _, _ in
                throw OAuthRefreshError.missingRefreshToken
            },
            folderCache: cache
        )

        await #expect(throws: OAuthRefreshError.missingRefreshToken) {
            try await backend.connect()
        }
        await #expect(throws: MailBackendError.self) {
            _ = try await backend.folders()
        }
    }

    @Test("connect lists IMAP folders through MailBackend")
    func connectListsIMAPFoldersThroughMailBackend() async throws {
        let recorder = FolderListingRecorder(listings: [
            IMAPFolderListing(
                path: "INBOX",
                displayName: "Inbox",
                delimiter: "/",
                flags: [],
                role: .inbox
            ),
            IMAPFolderListing(
                path: "Projects/Alpha",
                displayName: "Alpha",
                delimiter: "/",
                flags: [],
                role: .custom
            ),
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { configuration, credential in
                try await recorder.listFolders(
                    configuration: configuration,
                    credential: credential
                )
            }
        )

        try await backend.connect()

        #expect(await recorder.callCount == 1)
        #expect(try await backend.folders() == [
            Folder(id: "INBOX", name: "Inbox", role: .inbox),
            Folder(id: "Projects/Alpha", name: "Alpha", role: .custom),
        ])
    }

    @Test("connect clears caches for folders removed on the server")
    func connectClearsCachesForFoldersRemovedOnTheServer() async throws {
        let removedHeader = MessageHeader(
            id: "Removed:88",
            threadID: "Removed:88",
            folderID: "Removed",
            from: Correspondent(email: "person@example.org"),
            to: [Correspondent(email: "me@example.org")],
            subject: "Removed stale local mail",
            snippet: "Stale",
            date: Date(timeIntervalSince1970: 88)
        )
        let folderCache = InMemoryIMAPFolderSnapshotCache(snapshotsByAccount: [
            Self.account.id: IMAPFolderCacheSnapshot(folders: [
                Folder(id: "INBOX", name: "Inbox", role: .inbox),
                Folder(id: "Removed", name: "Removed", role: .custom),
            ]),
        ])
        let headerCache = InMemoryIMAPMailboxHeaderCache(snapshotsByFolderByAccount: [
            Self.account.id: [
                "Removed": IMAPMailboxHeaderCacheSnapshot(headers: [removedHeader]),
            ],
        ])
        let sourceCache = InMemoryIMAPMessageSourceCache()
        await sourceCache.setSource(
            IMAPMessageSource(uid: 88, rawMessage: "Subject: Removed\r\n\r\nBody"),
            accountID: Self.account.id,
            messageID: "Removed:88"
        )
        let localIndex = LocalSearchIndexRecorder()
        await localIndex.setHeaderPage(
            folderID: "Removed",
            pageToken: nil,
            headers: [removedHeader],
            nextPageToken: nil
        )
        await localIndex.setRawMessage(
            Data("Subject: Removed\r\n\r\nBody".utf8),
            for: "Removed:88"
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            folderCache: folderCache,
            headerCache: headerCache,
            sourceCache: sourceCache,
            localSearchIndex: localIndex
        )

        try await backend.connect()

        #expect(await headerCache.snapshot(accountID: Self.account.id, folderID: "Removed") == nil)
        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "Removed:88") == nil)
        #expect(await localIndex.cachedHeaders(
            for: Folder(id: "Removed", name: "Removed", role: .custom),
            account: Self.account,
            pageToken: nil
        ) == nil)
        #expect(await localIndex.cachedRawMessage(for: "Removed:88", account: Self.account) == nil)
        #expect(await localIndex.clearedFolders == ["Removed"])
    }

    @Test("a UIDVALIDITY change evicts queued mutations for that folder as conflicts")
    func uidValidityChangeEvictsFolderMutations() async throws {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let queue = UserDefaultsMutationQueue(defaults: defaults, storageKey: "q")
        let conflicts = UserDefaultsMutationConflictStore(defaults: defaults, storageKey: "c")

        // One mutation in the folder whose UIDs got reassigned, one in another
        // folder (must survive), and a send (folder-agnostic, must survive).
        try await queue.enqueue(PendingMutation(kind: .setRead(true), messageIDs: ["INBOX:42"]))
        try await queue.enqueue(PendingMutation(kind: .delete, messageIDs: ["Archive:7"]))
        try await queue.enqueue(PendingMutation(
            kind: .send(draft: Draft(id: "d1", subject: "Hi", htmlBody: "x")),
            messageIDs: []
        ))

        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            offlineMutationQueue: queue,
            offlineMutationConflictStore: conflicts
        )

        await backend.invalidatePendingMutations(targetingFolderID: "INBOX")

        let remaining = try await queue.pending()
        #expect(Set(remaining.map(\.messageIDs)) == [["Archive:7"], []])

        let recorded = try await conflicts.conflicts()
        #expect(recorded.count == 1)
        #expect(recorded.first?.reason == .targetMissing)
        #expect(recorded.first?.mutation.messageIDs == ["INBOX:42"])
    }

    @Test("folders require a connected IMAP session")
    func foldersRequireConnectedSession() async {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] }
        )

        do {
            _ = try await backend.folders()
            Issue.record("Expected folders() to require a connected backend.")
        } catch MailBackendError.notConnected {
        } catch {
            Issue.record("Expected notConnected, got \(error).")
        }
    }

    @Test("ManageSieve capability is advertised only when sync configuration is available")
    func manageSieveCapabilityRequiresConfiguredSync() async throws {
        let backendWithoutSieve = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            manageSieveRuleSync: { _, _, _, _ in
                SieveScriptPlan(
                    scriptName: "brev-rules",
                    script: "",
                    requiredExtensions: [],
                    unsupportedRules: []
                )
            }
        )
        #expect(!backendWithoutSieve.capabilities.contains(.manageSieve))
        #expect(backendWithoutSieve.extensionService(ManageSieveRuleSyncing.self) == nil)

        let backendWithSieve = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configurationWithManageSieve,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            manageSieveRuleSync: { _, _, _, _ in
                SieveScriptPlan(
                    scriptName: "brev-rules",
                    script: "",
                    requiredExtensions: [],
                    unsupportedRules: []
                )
            }
        )

        #expect(backendWithSieve.capabilities.contains(.manageSieve))
        #expect(backendWithSieve.extensionService(ManageSieveRuleSyncing.self) != nil)
    }

    @Test("ManageSieve sync service uploads local rules through the configured server")
    func manageSieveSyncServiceUploadsLocalRules() async throws {
        let recorder = ManageSieveRuleSyncRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configurationWithManageSieve,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            manageSieveRuleSync: { configuration, credential, rules, scriptName in
                try await recorder.sync(
                    configuration: configuration,
                    credential: credential,
                    rules: rules,
                    scriptName: scriptName
                )
            }
        )
        let service = try #require(backend.extensionService(ManageSieveRuleSyncing.self))
        let rule = ServerRule(
            id: "rule-1",
            name: "Invoices",
            isEnabled: true,
            conditions: [.senderContains("billing")],
            actions: [.moveToFolder(id: "Archive/Invoices")]
        )

        let plan = try await service.syncLocalRulesToServer([rule], sourceID: Self.sourceID)

        #expect(plan.scriptName == "brev-rules")
        let call = try await #require(recorder.calls.first)
        #expect(call.configuration.manageSieve == Self.manageSieveServer)
        #expect(call.credential == Self.credential)
        #expect(call.rules.map(\.id) == ["rule-1"])
    }

    @Test("refresh reconnects and updates folder snapshot")
    func refreshReconnectsAndUpdatesFolderSnapshot() async throws {
        let recorder = FolderListingRecorder(sequence: [
            [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ],
            [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
                IMAPFolderListing(
                    path: "Archive",
                    displayName: "Archive",
                    delimiter: "/",
                    flags: [],
                    role: .archive
                ),
            ],
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { configuration, credential in
                try await recorder.listFolders(
                    configuration: configuration,
                    credential: credential
                )
            }
        )
        try await backend.connect()

        try await backend.refresh(folder: Folder(id: "INBOX", name: "Inbox", role: .inbox))

        #expect(await recorder.callCount == 2)
        #expect(try await backend.folders().map(\.id) == ["INBOX", "Archive"])
    }

    @Test("folder mutations create rename and delete IMAP folders")
    func folderMutationsCreateRenameAndDeleteIMAPFolders() async throws {
        let listingRecorder = FolderListingRecorder(sequence: [
            [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
                IMAPFolderListing(
                    path: "Projects",
                    displayName: "Projects",
                    delimiter: "/",
                    flags: [],
                    role: .custom
                ),
            ],
            [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
                IMAPFolderListing(
                    path: "Projects",
                    displayName: "Projects",
                    delimiter: "/",
                    flags: [],
                    role: .custom
                ),
                IMAPFolderListing(
                    path: "Projects/Delta",
                    displayName: "Delta",
                    delimiter: "/",
                    flags: [],
                    role: .custom
                ),
            ],
            [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
                IMAPFolderListing(
                    path: "Projects",
                    displayName: "Projects",
                    delimiter: "/",
                    flags: [],
                    role: .custom
                ),
                IMAPFolderListing(
                    path: "Projects/Renamed Delta",
                    displayName: "Renamed Delta",
                    delimiter: "/",
                    flags: [],
                    role: .custom
                ),
            ],
            [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
                IMAPFolderListing(
                    path: "Projects",
                    displayName: "Projects",
                    delimiter: "/",
                    flags: [],
                    role: .custom
                ),
            ],
        ])
        let mutationRecorder = FolderMutationRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { configuration, credential in
                try await listingRecorder.listFolders(
                    configuration: configuration,
                    credential: credential
                )
            },
            createFolder: { configuration, credential, folderID in
                try await mutationRecorder.createFolder(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID
                )
            },
            renameFolder: { configuration, credential, folderID, newFolderID in
                try await mutationRecorder.renameFolder(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    newFolderID: newFolderID
                )
            },
            deleteFolder: { configuration, credential, folderID in
                try await mutationRecorder.deleteFolder(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID
                )
            }
        )
        try await backend.connect()

        #expect(backend.capabilities.contains(.folderCreate))
        #expect(backend.capabilities.contains(.folderRename))
        #expect(backend.capabilities.contains(.folderDelete))
        let created = try await backend.createFolder(name: "Delta", parentID: "Projects")
        let renamed = try await backend.renameFolder(id: created.id, name: "Renamed Delta")
        try await backend.deleteFolder(id: renamed.id)

        #expect(created == Folder(id: "Projects/Delta", name: "Delta", role: .custom, parentID: "Projects"))
        #expect(renamed == Folder(
            id: "Projects/Renamed Delta",
            name: "Renamed Delta",
            role: .custom,
            parentID: "Projects"
        ))
        let folderIDsAfterDelete = try await backend.folders().map { $0.id }
        #expect(folderIDsAfterDelete == ["INBOX", "Projects"])
        #expect(await mutationRecorder.calls == [
            .create(folderID: "Projects/Delta"),
            .rename(folderID: "Projects/Delta", newFolderID: "Projects/Renamed Delta"),
            .delete(folderID: "Projects/Renamed Delta"),
        ])
    }

    @Test("capabilities advertise IMAP folder flush when listing and permanent delete are available")
    func capabilitiesAdvertiseIMAPFolderFlushWhenListingAndPermanentDeleteAreAvailable() {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            listMessages: { _, _, _, _, _ in IMAPMessageListingPage(messages: []) },
            permanentlyDeleteMessages: { _, _, _, _ in }
        )

        #expect(backend.capabilities.contains(.folderFlush))
    }

    @Test("capabilities advertise SMTP send when send operation is available")
    func capabilitiesAdvertiseSMTPSendWhenSendOperationIsAvailable() {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { _, _, _ in SendResult(sentMessageID: "sent") }
        )

        #expect(backend.capabilities.contains(.smtpOAuth))
    }

    @Test("flushFolder permanently deletes each listed IMAP page")
    func flushFolderPermanentlyDeletesEachListedIMAPPage() async throws {
        let listingRecorder = MessageListingRecorder(sequence: [
            IMAPMessageListingPage(
                messages: [
                    Self.messageListing(uid: 43, subject: "Trash one"),
                    Self.messageListing(uid: 42, subject: "Trash two"),
                ],
                nextPageToken: "before:42"
            ),
            IMAPMessageListingPage(
                messages: [
                    Self.messageListing(uid: 41, subject: "Trash three"),
                ],
                nextPageToken: nil
            ),
        ])
        let deleteRecorder = MessagePermanentDeleteRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "Trash",
                    displayName: "Trash",
                    delimiter: "/",
                    flags: [],
                    role: .trash
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await listingRecorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            permanentlyDeleteMessages: { configuration, credential, folderID, uids in
                try await deleteRecorder.permanentlyDeleteMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uids: uids
                )
            }
        )
        try await backend.connect()

        try await backend.flushFolder(id: "Trash")

        #expect(await listingRecorder.requestedFolderIDs == ["Trash", "Trash"])
        #expect(await listingRecorder.requestedPageTokens == [nil, "before:42"])
        #expect(await deleteRecorder.calls == [
            MessagePermanentDeleteRecorder.Call(folderID: "Trash", uids: [43, 42]),
            MessagePermanentDeleteRecorder.Call(folderID: "Trash", uids: [41]),
        ])
    }

    @Test("folder mutations preserve provider hierarchy delimiter")
    func folderMutationsPreserveProviderHierarchyDelimiter() async throws {
        let listingRecorder = FolderListingRecorder(sequence: [
            [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: ".",
                    flags: [],
                    role: .inbox
                ),
                IMAPFolderListing(
                    path: "Projects",
                    displayName: "Projects",
                    delimiter: ".",
                    flags: [],
                    role: .custom
                ),
            ],
            [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: ".",
                    flags: [],
                    role: .inbox
                ),
                IMAPFolderListing(
                    path: "Projects",
                    displayName: "Projects",
                    delimiter: ".",
                    flags: [],
                    role: .custom
                ),
                IMAPFolderListing(
                    path: "Projects.Delta",
                    displayName: "Delta",
                    delimiter: ".",
                    flags: [],
                    role: .custom
                ),
            ],
            [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: ".",
                    flags: [],
                    role: .inbox
                ),
                IMAPFolderListing(
                    path: "Projects",
                    displayName: "Projects",
                    delimiter: ".",
                    flags: [],
                    role: .custom
                ),
                IMAPFolderListing(
                    path: "Projects.Renamed Delta",
                    displayName: "Renamed Delta",
                    delimiter: ".",
                    flags: [],
                    role: .custom
                ),
            ],
        ])
        let mutationRecorder = FolderMutationRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { configuration, credential in
                try await listingRecorder.listFolders(
                    configuration: configuration,
                    credential: credential
                )
            },
            createFolder: { configuration, credential, folderID in
                try await mutationRecorder.createFolder(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID
                )
            },
            renameFolder: { configuration, credential, folderID, newFolderID in
                try await mutationRecorder.renameFolder(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    newFolderID: newFolderID
                )
            }
        )
        try await backend.connect()

        let created = try await backend.createFolder(name: "Delta", parentID: "Projects")
        let renamed = try await backend.renameFolder(id: created.id, name: "Renamed Delta")

        #expect(created == Folder(id: "Projects.Delta", name: "Delta", role: .custom, parentID: "Projects"))
        #expect(renamed == Folder(
            id: "Projects.Renamed Delta",
            name: "Renamed Delta",
            role: .custom,
            parentID: "Projects"
        ))
        #expect(await mutationRecorder.calls == [
            .create(folderID: "Projects.Delta"),
            .rename(folderID: "Projects.Delta", newFolderID: "Projects.Renamed Delta"),
        ])
    }

    @Test("messages lists headers through IMAP message listing operation")
    func messagesListsHeadersThroughIMAPMessageListingOperation() async throws {
        let recorder = MessageListingRecorder(messages: [
            IMAPMessageListing(
                uid: 43,
                messageID: "<msg-43@example.org>",
                subject: "Second",
                snippet: "The second message preview.",
                from: Correspondent(name: "Grace Hopper", email: "grace@example.org"),
                to: [Correspondent(email: "person@example.org")],
                cc: [],
                bcc: [],
                date: Date(timeIntervalSince1970: 1_780_750_800),
                isRead: false,
                isFlagged: true,
                isAnswered: true
            ),
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            }
        )
        try await backend.connect()

        let result = try await backend.messages(
            in: Folder(id: "INBOX", name: "Inbox", role: .inbox),
            pageToken: nil
        )

        #expect(await recorder.callCount == 1)
        #expect(await recorder.requestedFolderIDs == ["INBOX"])
        #expect(await recorder.requestedPageTokens == [nil])
        #expect(await recorder.requestedLimits == [50])
        #expect(result.nextPageToken == "before:42")
        #expect(result.headers == [
            MessageHeader(
                id: "INBOX:43",
                threadID: "<msg-43@example.org>",
                folderID: "INBOX",
                from: Correspondent(name: "Grace Hopper", email: "grace@example.org"),
                to: [Correspondent(email: "person@example.org")],
                cc: [],
                bcc: [],
                subject: "Second",
                snippet: "The second message preview.",
                date: Date(timeIntervalSince1970: 1_780_750_800),
                isRead: false,
                isFlagged: true,
                isAnswered: true,
                hasAttachments: false,
                messageID: "<msg-43@example.org>"
            ),
        ])
    }

    @Test("source-scoped messages use primary IMAP mailbox source")
    func sourceScopedMessagesUsePrimaryIMAPMailboxSource() async throws {
        let recorder = MessageListingRecorder(messages: [
            Self.messageListing(uid: 43, subject: "Scoped"),
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            }
        )
        try await backend.connect()

        let result = try await backend.messages(
            in: Folder(id: "INBOX", name: "Inbox", role: .inbox),
            sourceID: Self.sourceID,
            pageToken: nil
        )

        #expect(result.headers.map(\.id) == ["INBOX:43"])
        #expect(await recorder.requestedFolderIDs == ["INBOX"])
    }

    @Test("source-scoped read paths reject stale IMAP mailbox source")
    func sourceScopedReadPathsRejectStaleIMAPMailboxSource() async throws {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] }
        )
        try await backend.connect()

        let staleSourceID = MailSourceID(
            accountID: Self.account.id,
            mailboxID: "stale-mailbox"
        )
        await expectNotFound("stale-mailbox") {
            _ = try await backend.folders(in: staleSourceID)
        }
        await expectNotFound("stale-mailbox") {
            try await backend.refresh(
                folder: Folder(id: "INBOX", name: "Inbox", role: .inbox),
                in: staleSourceID
            )
        }
        await expectNotFound("stale-mailbox") {
            _ = try await backend.messages(
                in: Folder(id: "INBOX", name: "Inbox", role: .inbox),
                sourceID: staleSourceID,
                pageToken: nil
            )
        }
        await expectNotFound("stale-mailbox") {
            _ = try await backend.body(for: "INBOX:43", sourceID: staleSourceID)
        }
        await expectNotFound("stale-mailbox") {
            _ = try await backend.downloadAttachment(
                Attachment(
                    id: "INBOX:43:attachment:1",
                    name: "receipt.pdf",
                    mimeType: "application/pdf",
                    sizeBytes: 5,
                    resource: "imap-source:INBOX:43:1"
                ),
                sourceID: staleSourceID
            )
        }
        await expectNotFound("stale-mailbox") {
            _ = try await backend.search(SearchQuery(text: "hello"), sourceID: staleSourceID)
        }
    }

    @Test("source-scoped folder paths reject stale IMAP mailbox source")
    func sourceScopedFolderPathsRejectStaleIMAPMailboxSource() async throws {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] }
        )
        try await backend.connect()

        let staleSourceID = MailSourceID(
            accountID: Self.account.id,
            mailboxID: "stale-mailbox"
        )
        await expectNotFound("stale-mailbox") {
            _ = try await backend.createFolder(
                name: "Projects",
                parentID: nil,
                sourceID: staleSourceID
            )
        }
        await expectNotFound("stale-mailbox") {
            _ = try await backend.renameFolder(
                id: "Projects",
                name: "Renamed",
                sourceID: staleSourceID
            )
        }
        await expectNotFound("stale-mailbox") {
            try await backend.deleteFolder(id: "Projects", sourceID: staleSourceID)
        }
        await expectNotFound("stale-mailbox") {
            try await backend.flushFolder(id: "Projects", sourceID: staleSourceID)
        }
    }

    @Test("messages forwards page token through IMAP message listing operation")
    func messagesForwardsPageTokenThroughIMAPMessageListingOperation() async throws {
        let recorder = MessageListingRecorder(
            page: IMAPMessageListingPage(
                messages: [
                    IMAPMessageListing(
                        uid: 41,
                        messageID: "<msg-41@example.org>",
                        subject: "Older",
                        from: Correspondent(email: "ada@example.org"),
                        to: [Correspondent(email: "person@example.org")],
                        cc: [],
                        bcc: [],
                        date: Date(timeIntervalSince1970: 1_780_560_000),
                        isRead: true,
                        isFlagged: false,
                        isAnswered: false
                    ),
                ],
                nextPageToken: nil
            )
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            }
        )
        try await backend.connect()

        let result = try await backend.messages(
            in: Folder(id: "INBOX", name: "Inbox", role: .inbox),
            pageToken: "before:42"
        )

        #expect(await recorder.requestedPageTokens == ["before:42"])
        #expect(result.headers.map(\.id) == ["INBOX:41"])
        #expect(result.nextPageToken == nil)
    }

    @Test("messages merge older IMAP pages into header cache")
    func messagesMergeOlderIMAPPagesIntoHeaderCache() async throws {
        let recorder = MessageListingRecorder(page: IMAPMessageListingPage(
            messages: [Self.messageListing(uid: 43, subject: "Newest")],
            nextPageToken: "before:43"
        ))
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            headerCache: headerCache
        )
        try await backend.connect()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        _ = try await backend.messages(in: inbox, pageToken: nil)
        await recorder.setMessages([
            Self.messageListing(uid: 41, subject: "Older cached"),
        ], nextPageToken: nil)
        _ = try await backend.messages(in: inbox, pageToken: "before:43")
        let cacheOnlyBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            headerCache: headerCache
        )
        try await cacheOnlyBackend.connect()

        let results = try await cacheOnlyBackend.search(SearchQuery(
            text: "Older cached",
            execution: .cacheOnly
        ))

        #expect(results.map(\.id) == ["INBOX:41"])
    }

    @Test("cached message header service reads persisted IMAP header cache")
    func cachedMessageHeaderServiceReadsPersistedIMAPHeaderCache() async throws {
        let recorder = MessageListingRecorder(messages: [
            Self.messageListing(uid: 43, subject: "Cached notification preview"),
        ])
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            headerCache: headerCache
        )
        try await backend.connect()

        _ = try await backend.messages(
            in: Folder(id: "INBOX", name: "Inbox", role: .inbox),
            pageToken: nil
        )
        let service = try #require(backend.extensionService(CachedMessageHeaderProviding.self))
        #expect(backend.extendedCapabilities.contains(.cachedMessageHeaders))
        let cachedHeader = await service.cachedMessageHeader(
            messageID: "INBOX:43",
            folderID: "INBOX"
        )

        #expect(cachedHeader?.subject == "Cached notification preview")
        #expect(cachedHeader?.id == "INBOX:43")
        #expect(await service.cachedMessageHeader(
            messageID: "INBOX:43",
            folderID: "Archive"
        ) == nil)
    }

    @Test("first page messages return cached headers before IMAP listing completes")
    func firstPageMessagesReturnCachedHeadersBeforeIMAPListingCompletes() async throws {
        let cachedHeader = MessageHeader(
            id: "INBOX:42",
            threadID: "<cached-42@example.org>",
            folderID: "INBOX",
            from: Correspondent(email: "sender@example.org"),
            to: [Correspondent(email: "person@example.org")],
            subject: "Cached header",
            snippet: "",
            date: Date(timeIntervalSince1970: 42)
        )
        let headerCache = InMemoryIMAPMailboxHeaderCache(snapshotsByFolderByAccount: [
            Self.account.id: [
                "INBOX": IMAPMailboxHeaderCacheSnapshot(
                    headers: [cachedHeader],
                    uidValidity: 100,
                    nextPageToken: "before:42",
                    firstPageHeaderIDs: ["INBOX:42"]
                ),
            ],
        ])
        let recorder = BlockingMessageListingRecorder(page: IMAPMessageListingPage(
            messages: [Self.messageListing(uid: 43, subject: "Fresh header")],
            uidValidity: 100,
            nextPageToken: "before:43"
        ))
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            headerCache: headerCache
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        let pageTask = Task {
            try await backend.messages(in: inbox, pageToken: nil as String?)
        }
        try await recorder.waitUntilBlocked()

        let cachedPage: (headers: [MessageHeader], nextPageToken: String?)
        do {
            cachedPage = try await value(from: pageTask)
        } catch {
            await recorder.release()
            _ = try? await pageTask.value
            throw error
        }
        #expect(cachedPage.headers.map(\.subject) == ["Cached header"])
        #expect(cachedPage.nextPageToken == "before:42")

        await recorder.release()
        let event = try await nextIMAPEvent(from: stream)
        #expect(event == .messagesAdded(folderID: "INBOX", messageIDs: ["INBOX:43"]))
    }

    @Test("messages repair cached distantPast date from cached raw source in the background")
    func messagesRepairCachedDistantPastDateFromCachedRawSource() async throws {
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let staleHeader = MessageHeader(
            id: "INBOX:16149",
            threadID: "<msg-16149@example.org>",
            folderID: "INBOX",
            from: Correspondent(email: "jobalerts-noreply@linkedin.com"),
            to: [Correspondent(email: "person@example.org")],
            subject: "Senior Solutions Architect",
            snippet: "Your job alert",
            date: Date.distantPast
        )
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [staleHeader], nextPageToken: nil),
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        await sourceCache.setSource(
            IMAPMessageSource(
                uid: 16149,
                rawMessage: """
                Date: Mon, 8 Jun 2026 08:51:02 +0000 (UTC)
                Subject: Senior Solutions Architect

                Body
                """
            ),
            accountID: Self.account.id,
            messageID: "INBOX:16149"
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            headerCache: headerCache,
            sourceCache: sourceCache
        )
        try await backend.connect()

        // Subscribe before the cache-hit call so we catch the background
        // repair's `.messagesUpdated` event.
        let stream = backend.subscribeToChanges()

        let result = try await backend.messages(
            in: Folder(id: "INBOX", name: "Inbox", role: .inbox),
            pageToken: nil
        )

        let calendar = Calendar(identifier: .gregorian)
        let expected = try #require(calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 6,
            day: 8,
            hour: 8,
            minute: 51,
            second: 2
        )))
        // The cache-hit path returns the stale header immediately so the UI
        // can render the first frame without waiting for disk reads. The
        // date is still `distantPast` at this point.
        #expect(result.headers.first?.date == Date.distantPast)
        // The background repair emits a `.messagesUpdated` event once it has
        // read the cached raw source, parsed the Date header, and written the
        // repaired snapshot back to the cache.
        let event = try await nextIMAPEvent(from: stream, timeoutNanoseconds: 2_000_000_000)
        #expect(event == .messagesUpdated(folderID: "INBOX", messageIDs: ["INBOX:16149"]))
        let repairedSnapshot = await headerCache.snapshot(
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        #expect(repairedSnapshot?.headers.first?.date == expected)
    }

    @Test("background date repair merges into live cache instead of overwriting concurrent updates")
    func backgroundDateRepairMergesIntoLiveCache() async throws {
        // Gate the raw-source read so we can insert a concurrent header into
        // the live cache while repair is in flight. The repair must merge
        // date patches into the current snapshot — not replace it with the
        // schedule-time capture — or the concurrent header would be lost.
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = GatedIMAPMessageSourceCache()
        let staleHeader = MessageHeader(
            id: "INBOX:16149",
            threadID: "<msg-16149@example.org>",
            folderID: "INBOX",
            from: Correspondent(email: "jobalerts-noreply@linkedin.com"),
            to: [Correspondent(email: "person@example.org")],
            subject: "Senior Solutions Architect",
            snippet: "Your job alert",
            date: Date.distantPast
        )
        let concurrentHeader = MessageHeader(
            id: "INBOX:16150",
            threadID: "<msg-16150@example.org>",
            folderID: "INBOX",
            from: Correspondent(email: "alerts@example.org"),
            to: [Correspondent(email: "person@example.org")],
            subject: "Concurrent refresh message",
            snippet: "Arrived during repair",
            date: Date(timeIntervalSince1970: 1_780_000_000)
        )
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [staleHeader], nextPageToken: nil),
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        await sourceCache.setSource(
            IMAPMessageSource(
                uid: 16149,
                rawMessage: """
                Date: Mon, 8 Jun 2026 08:51:02 +0000 (UTC)
                Subject: Senior Solutions Architect

                Body
                """
            ),
            accountID: Self.account.id,
            messageID: "INBOX:16149"
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            headerCache: headerCache,
            sourceCache: sourceCache
        )
        try await backend.connect()

        let stream = backend.subscribeToChanges()
        let result = try await backend.messages(
            in: Folder(id: "INBOX", name: "Inbox", role: .inbox),
            pageToken: nil
        )
        #expect(result.headers.first?.date == Date.distantPast)

        await sourceCache.waitUntilSourceCalled()
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(
                headers: [staleHeader, concurrentHeader],
                nextPageToken: nil
            ),
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        await sourceCache.releaseSource()

        let event = try await nextIMAPEvent(from: stream, timeoutNanoseconds: 2_000_000_000)
        #expect(event == .messagesUpdated(folderID: "INBOX", messageIDs: ["INBOX:16149"]))

        let repairedSnapshot = await headerCache.snapshot(
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        let headers = try #require(repairedSnapshot?.headers)
        #expect(headers.count == 2)
        #expect(headers.contains(where: { $0.id == "INBOX:16150" }))
        let calendar = Calendar(identifier: .gregorian)
        let expected = try #require(calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 6,
            day: 8,
            hour: 8,
            minute: 51,
            second: 2
        )))
        #expect(headers.first(where: { $0.id == "INBOX:16149" })?.date == expected)
    }

    @Test("applyRetention evicts bodies older than the window and keeps recent ones")
    func applyRetentionEvictsBodiesOlderThanWindow() async throws {
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let now = Date()
        let recent = Self.retentionHeader(id: "INBOX:1", date: now.addingTimeInterval(-2 * 86400))
        let old = Self.retentionHeader(id: "INBOX:2", date: now.addingTimeInterval(-60 * 86400))
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [recent, old], nextPageToken: nil),
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 1, rawMessage: "recent body"),
            accountID: Self.account.id,
            messageID: "INBOX:1"
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 2, rawMessage: "old body"),
            accountID: Self.account.id,
            messageID: "INBOX:2"
        )
        let backend = Self.retentionBackend(headerCache: headerCache, sourceCache: sourceCache)

        await backend.applyRetention(folderID: "INBOX", retentionDays: 30, keepsBodies: true)

        // The 60-day-old body is dropped; the 2-day-old one stays. Headers
        // are untouched either way.
        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:1") != nil)
        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:2") == nil)
        let snapshot = await headerCache.snapshot(accountID: Self.account.id, folderID: "INBOX")
        #expect(snapshot?.headers.map(\.id) == ["INBOX:1", "INBOX:2"])
    }

    @Test("applyRetention never evicts a kept-offline (pinned) body in the age-window mode")
    func applyRetentionExemptsKeptOfflineBodies() async throws {
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let now = Date()
        let recent = Self.retentionHeader(id: "INBOX:1", date: now.addingTimeInterval(-2 * 86400))
        let old = Self.retentionHeader(id: "INBOX:2", date: now.addingTimeInterval(-60 * 86400))
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [recent, old], nextPageToken: nil),
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 1, rawMessage: "recent body"),
            accountID: Self.account.id,
            messageID: "INBOX:1"
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 2, rawMessage: "old body"),
            accountID: Self.account.id,
            messageID: "INBOX:2"
        )
        let backend = Self.retentionBackend(headerCache: headerCache, sourceCache: sourceCache)

        // The 60-day-old body would normally be dropped, but it is pinned offline.
        await backend.applyRetention(
            folderID: "INBOX",
            retentionDays: 30,
            keepsBodies: true,
            keepingMessageIDs: ["INBOX:2"]
        )

        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:1") != nil)
        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:2") != nil)
    }

    @Test("applyRetention keeps a pinned body even in headers-only mode")
    func applyRetentionExemptsPinInHeadersOnly() async throws {
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let now = Date()
        let pinned = Self.retentionHeader(id: "INBOX:1", date: now)
        let other = Self.retentionHeader(id: "INBOX:2", date: now)
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [pinned, other], nextPageToken: nil),
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 1, rawMessage: "pinned body"),
            accountID: Self.account.id,
            messageID: "INBOX:1"
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 2, rawMessage: "other body"),
            accountID: Self.account.id,
            messageID: "INBOX:2"
        )
        let backend = Self.retentionBackend(headerCache: headerCache, sourceCache: sourceCache)

        // Headers-only normally drops every body; the pinned one survives.
        await backend.applyRetention(
            folderID: "INBOX",
            retentionDays: nil,
            keepsBodies: false,
            keepingMessageIDs: ["INBOX:1"]
        )

        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:1") != nil)
        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:2") == nil)
    }

    @Test("applyRetention evicts an orphan body (no header) while keeping a pin in headers-only mode")
    func applyRetentionEvictsOrphanBodyButKeepsPinInHeadersOnly() async throws {
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let now = Date()
        let pinned = Self.retentionHeader(id: "INBOX:1", date: now)
        let other = Self.retentionHeader(id: "INBOX:2", date: now)
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [pinned, other], nextPageToken: nil),
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 1, rawMessage: "pinned body"),
            accountID: Self.account.id,
            messageID: "INBOX:1"
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 2, rawMessage: "other body"),
            accountID: Self.account.id,
            messageID: "INBOX:2"
        )
        // Orphan: a cached body whose header is no longer present in any cache.
        await sourceCache.setSource(
            IMAPMessageSource(uid: 99, rawMessage: "orphan body"),
            accountID: Self.account.id,
            messageID: "INBOX:99"
        )
        let backend = Self.retentionBackend(headerCache: headerCache, sourceCache: sourceCache)

        // Headers-only with a pin: the pinned body survives, the headed non-pinned
        // body is evicted, and the orphan body (no surviving header) is reclaimed
        // too rather than leaking until the next pin-free sweep.
        await backend.applyRetention(
            folderID: "INBOX",
            retentionDays: nil,
            keepsBodies: false,
            keepingMessageIDs: ["INBOX:1"]
        )

        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:1") != nil)
        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:2") == nil)
        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:99") == nil)
    }

    @Test("applyRetention drops every body for headers-only and keeps all for keepAll")
    func applyRetentionHeadersOnlyAndKeepAll() async throws {
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let now = Date()
        let recent = Self.retentionHeader(id: "INBOX:1", date: now)
        let old = Self.retentionHeader(id: "INBOX:2", date: now.addingTimeInterval(-400 * 86400))
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [recent, old], nextPageToken: nil),
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 1, rawMessage: "a"),
            accountID: Self.account.id,
            messageID: "INBOX:1"
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 2, rawMessage: "b"),
            accountID: Self.account.id,
            messageID: "INBOX:2"
        )
        let backend = Self.retentionBackend(headerCache: headerCache, sourceCache: sourceCache)

        // keepAll (no age cutoff, bodies kept) prunes nothing.
        await backend.applyRetention(folderID: "INBOX", retentionDays: nil, keepsBodies: true)
        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:1") != nil)
        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:2") != nil)

        // headers-only drops every body regardless of age.
        await backend.applyRetention(folderID: "INBOX", retentionDays: nil, keepsBodies: false)
        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:1") == nil)
        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:2") == nil)
    }

    @Test("messages can read cached pages from the local search index while disconnected")
    func messagesCanReadCachedPagesFromLocalSearchIndexWhileDisconnected() async throws {
        let localIndex = LocalSearchIndexRecorder()
        let cachedHeader = Self.retentionHeader(
            id: "INBOX:42",
            date: Date(timeIntervalSince1970: 42)
        )
        await localIndex.setHeaderPage(
            folderID: "INBOX",
            pageToken: nil,
            headers: [cachedHeader],
            nextPageToken: "before:42"
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            localSearchIndex: localIndex
        )

        let page = try await backend.messages(
            in: Folder(id: "INBOX", name: "Inbox", role: .inbox),
            pageToken: nil
        )

        #expect(page.headers.map(\.id) == ["INBOX:42"])
        #expect(page.nextPageToken != nil)
        #expect(await localIndex.cachedHeaderRequests == [
            LocalSearchIndexRecorder.HeaderPageRequest(folderID: "INBOX", pageToken: nil),
        ])
    }

    @Test("connected message listing pages the local cache ahead of a large legacy snapshot")
    func connectedMessageListingPagesLocalCacheAheadOfLargeLegacySnapshot() async throws {
        let localIndex = LocalSearchIndexRecorder()
        let firstPage = (9951 ... 10000).reversed().map { uid in
            Self.retentionHeader(
                id: "INBOX:\(uid)",
                date: Date(timeIntervalSince1970: TimeInterval(uid))
            )
        }
        let secondPage = (9901 ... 9950).reversed().map { uid in
            Self.retentionHeader(
                id: "INBOX:\(uid)",
                date: Date(timeIntervalSince1970: TimeInterval(uid))
            )
        }
        await localIndex.setHeaderPage(
            folderID: "INBOX",
            pageToken: nil,
            headers: firstPage,
            nextPageToken: "50"
        )
        await localIndex.setHeaderPage(
            folderID: "INBOX",
            pageToken: "50",
            headers: secondPage,
            nextPageToken: nil
        )

        let legacyHeaders = (1 ... 10000).reversed().map { uid in
            Self.retentionHeader(
                id: "INBOX:\(uid)",
                date: Date(timeIntervalSince1970: TimeInterval(uid))
            )
        }
        let headerCache = InMemoryIMAPMailboxHeaderCache(snapshotsByFolderByAccount: [
            Self.account.id: [
                "INBOX": IMAPMailboxHeaderCacheSnapshot(
                    headers: legacyHeaders,
                    nextPageToken: "before:10000"
                ),
            ],
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            headerCache: headerCache,
            localSearchIndex: localIndex
        )
        try await backend.connect()

        let page = try await backend.messages(
            in: Folder(id: "INBOX", name: "Inbox", role: .inbox),
            pageToken: nil
        )
        let nextPage = try await backend.messages(
            in: Folder(id: "INBOX", name: "Inbox", role: .inbox),
            pageToken: page.nextPageToken
        )
        let snapshotPage = try await backend.messages(
            in: Folder(id: "INBOX", name: "Inbox", role: .inbox),
            pageToken: nextPage.nextPageToken
        )

        #expect(page.headers == firstPage)
        #expect(nextPage.headers == secondPage)
        #expect(snapshotPage.headers == Array(legacyHeaders[100 ..< 150]))
        #expect(await localIndex.cachedHeaderRequests == [
            LocalSearchIndexRecorder.HeaderPageRequest(folderID: "INBOX", pageToken: nil),
            LocalSearchIndexRecorder.HeaderPageRequest(folderID: "INBOX", pageToken: "50"),
        ])
    }

    @Test("legacy header snapshots keep cache-first inbox pages bounded")
    func legacyHeaderSnapshotsKeepCacheFirstInboxPagesBounded() async throws {
        let legacyHeaders = (1 ... 10000).reversed().map { uid in
            Self.retentionHeader(
                id: "INBOX:\(uid)",
                date: Date(timeIntervalSince1970: TimeInterval(uid))
            )
        }
        let headerCache = InMemoryIMAPMailboxHeaderCache(snapshotsByFolderByAccount: [
            Self.account.id: [
                "INBOX": IMAPMailboxHeaderCacheSnapshot(
                    headers: legacyHeaders,
                    nextPageToken: "before:10000"
                ),
            ],
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            headerCache: headerCache
        )
        try await backend.connect()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        let firstPage = try await backend.messages(in: inbox, pageToken: nil)
        let secondPage = try await backend.messages(in: inbox, pageToken: firstPage.nextPageToken)

        #expect(firstPage.headers == Array(legacyHeaders.prefix(50)))
        #expect(secondPage.headers == Array(legacyHeaders[50 ..< 100]))
    }

    @Test("cache-only search reads local search index results")
    func cacheOnlySearchReadsLocalSearchIndexResults() async throws {
        let localIndex = LocalSearchIndexRecorder()
        let indexedHeader = Self.retentionHeader(
            id: "INBOX:77",
            date: Date(timeIntervalSince1970: 77)
        )
        await localIndex.setSearchResults([indexedHeader])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            localSearchIndex: localIndex
        )
        try await backend.connect()

        let results = try await backend.search(SearchQuery(
            text: "Subject INBOX:77",
            execution: .cacheOnly
        ))

        #expect(results.map(\.id) == ["INBOX:77"])
        #expect(await localIndex.searchRequests == [
            LocalSearchIndexRecorder.SearchRequest(
                query: SearchQuery(
                    text: "Subject INBOX:77",
                    folderID: "INBOX",
                    execution: .cacheOnly
                ),
                limit: 50
            ),
        ])
    }

    @Test("cache-only search merges local index and header cache results")
    func cacheOnlySearchMergesLocalIndexAndHeaderCacheResults() async throws {
        let localIndex = LocalSearchIndexRecorder()
        let indexedHeader = Self.retentionHeader(
            id: "INBOX:77",
            date: Date(timeIntervalSince1970: 77)
        )
        let cachedHeader = Self.retentionHeader(
            id: "INBOX:88",
            date: Date(timeIntervalSince1970: 88)
        )
        await localIndex.setSearchResults([indexedHeader])
        let headerCache = InMemoryIMAPMailboxHeaderCache(snapshotsByFolderByAccount: [
            Self.account.id: [
                "INBOX": IMAPMailboxHeaderCacheSnapshot(
                    headers: [cachedHeader, indexedHeader],
                    nextPageToken: nil
                ),
            ],
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            headerCache: headerCache,
            localSearchIndex: localIndex
        )
        try await backend.connect()

        let results = try await backend.search(SearchQuery(
            text: "Subject INBOX",
            execution: .cacheOnly
        ))

        #expect(results.map(\.id) == ["INBOX:88", "INBOX:77"])
        #expect(await localIndex.searchRequests == [
            LocalSearchIndexRecorder.SearchRequest(
                query: SearchQuery(
                    text: "Subject INBOX",
                    folderID: "INBOX",
                    execution: .cacheOnly
                ),
                limit: 50
            ),
        ])
    }

    @Test("all-folder cache-only search ignores indexed rows outside current folders")
    func allFolderCacheOnlySearchIgnoresIndexedRowsOutsideCurrentFolders() async throws {
        let localIndex = LocalSearchIndexRecorder()
        let currentHeader = Self.retentionHeader(
            id: "INBOX:77",
            date: Date(timeIntervalSince1970: 77)
        )
        let staleFolderHeader = MessageHeader(
            id: "Removed:88",
            threadID: "Removed:88",
            folderID: "Removed",
            from: Correspondent(email: "person@example.org"),
            to: [Correspondent(email: "me@example.org")],
            subject: "Subject Removed:88",
            snippet: "Snippet",
            date: Date(timeIntervalSince1970: 88)
        )
        await localIndex.setSearchResults([staleFolderHeader, currentHeader])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            localSearchIndex: localIndex
        )
        try await backend.connect()

        let results = try await backend.search(SearchQuery(
            text: "Subject",
            execution: .cacheOnly
        ))

        #expect(results.map(\.id) == ["INBOX:77"])
        #expect(await localIndex.searchRequests == [
            LocalSearchIndexRecorder.SearchRequest(
                query: SearchQuery(
                    text: "Subject",
                    folderID: "INBOX",
                    execution: .cacheOnly
                ),
                limit: 50
            ),
        ])
    }

    @Test("all-folder cache-only search scopes local index reads to current folders")
    func allFolderCacheOnlySearchScopesLocalIndexReadsToCurrentFolders() async throws {
        let localIndex = LocalSearchIndexRecorder()
        let staleHeaders = (0 ..< 250).map { index in
            MessageHeader(
                id: "Removed:\(index)",
                threadID: "Removed:\(index)",
                folderID: "Removed",
                from: Correspondent(email: "person@example.org"),
                to: [Correspondent(email: "me@example.org")],
                subject: "Subject removed \(index)",
                snippet: "Stale folder candidate",
                date: Date(timeIntervalSince1970: TimeInterval(1000 + index))
            )
        }
        let currentHeader = Self.retentionHeader(
            id: "INBOX:77",
            date: Date(timeIntervalSince1970: 77)
        )
        await localIndex.setSearchResults(staleHeaders + [currentHeader])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            localSearchIndex: localIndex
        )
        try await backend.connect()

        let results = try await backend.search(SearchQuery(
            text: "Subject",
            execution: .cacheOnly
        ))

        #expect(results.map(\.id) == ["INBOX:77"])
        #expect(await localIndex.searchRequests == [
            LocalSearchIndexRecorder.SearchRequest(
                query: SearchQuery(text: "Subject", folderID: "INBOX", execution: .cacheOnly),
                limit: 50
            ),
        ])
    }

    @Test("cache-only search reads local search index while disconnected")
    func cacheOnlySearchReadsLocalSearchIndexWhileDisconnected() async throws {
        let localIndex = LocalSearchIndexRecorder()
        let indexedHeader = Self.retentionHeader(
            id: "INBOX:78",
            date: Date(timeIntervalSince1970: 78)
        )
        await localIndex.setSearchResults([indexedHeader])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            localSearchIndex: localIndex
        )

        let results = try await backend.search(SearchQuery(
            text: "Subject INBOX:78",
            execution: .cacheOnly
        ))

        #expect(results.map(\.id) == ["INBOX:78"])
        #expect(await localIndex.searchRequests == [
            LocalSearchIndexRecorder.SearchRequest(
                query: SearchQuery(text: "Subject INBOX:78", execution: .cacheOnly),
                limit: 50
            ),
        ])
    }

    @Test("cache-then-server search uses local search index hit while disconnected")
    func cacheThenServerSearchUsesLocalSearchIndexHitWhileDisconnected() async throws {
        let localIndex = LocalSearchIndexRecorder()
        let indexedHeader = Self.retentionHeader(
            id: "INBOX:79",
            date: Date(timeIntervalSince1970: 79)
        )
        await localIndex.setSearchResults([indexedHeader])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            localSearchIndex: localIndex
        )

        let results = try await backend.search(SearchQuery(
            text: "Subject INBOX:79",
            execution: .cacheThenServer
        ))

        #expect(results.map(\.id) == ["INBOX:79"])
        #expect(await localIndex.searchRequests == [
            LocalSearchIndexRecorder.SearchRequest(
                query: SearchQuery(text: "Subject INBOX:79", execution: .cacheThenServer),
                limit: 50
            ),
        ])
    }

    @Test("applyRetention can prune bodies using local search index headers")
    func applyRetentionCanPruneBodiesUsingLocalSearchIndexHeaders() async throws {
        let localIndex = LocalSearchIndexRecorder()
        let now = Date()
        let recent = Self.retentionHeader(id: "INBOX:1", date: now.addingTimeInterval(-2 * 86400))
        let old = Self.retentionHeader(id: "INBOX:2", date: now.addingTimeInterval(-60 * 86400))
        await localIndex.setHeaderPage(
            folderID: "INBOX",
            pageToken: nil,
            headers: [recent],
            nextPageToken: "older"
        )
        await localIndex.setHeaderPage(
            folderID: "INBOX",
            pageToken: "older",
            headers: [old],
            nextPageToken: nil
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            localSearchIndex: localIndex
        )
        try await backend.connect()

        await backend.applyRetention(folderID: "INBOX", retentionDays: 30, keepsBodies: true)

        #expect(await localIndex.deletedRawMessageBatches == [["INBOX:2"]])
        #expect(await localIndex.cachedHeaderRequests == [
            LocalSearchIndexRecorder.HeaderPageRequest(folderID: "INBOX", pageToken: nil),
            LocalSearchIndexRecorder.HeaderPageRequest(folderID: "INBOX", pageToken: "older"),
        ])
    }

    @Test("applyRetention uses cached folders to prune local index bodies while disconnected")
    func applyRetentionUsesCachedFoldersToPruneLocalIndexBodiesWhileDisconnected() async throws {
        let folderCache = InMemoryIMAPFolderSnapshotCache(snapshotsByAccount: [
            Self.account.id: IMAPFolderCacheSnapshot(folders: [
                Folder(id: "INBOX", name: "Inbox", role: .inbox),
            ]),
        ])
        let localIndex = LocalSearchIndexRecorder()
        let now = Date()
        let old = Self.retentionHeader(id: "INBOX:2", date: now.addingTimeInterval(-60 * 86400))
        await localIndex.setHeaderPage(
            folderID: "INBOX",
            pageToken: nil,
            headers: [old],
            nextPageToken: nil
        )
        await localIndex.setRawMessage(
            Data("Subject: old\r\n\r\nold downloaded body".utf8),
            for: "INBOX:2"
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            folderCache: folderCache,
            localSearchIndex: localIndex
        )

        await backend.applyRetention(folderID: "INBOX", retentionDays: 30, keepsBodies: true)

        let cachedRawMessage = await localIndex.cachedRawMessage(for: "INBOX:2", account: Self.account)
        #expect(cachedRawMessage == nil)
        #expect(await localIndex.deletedRawMessageBatches == [["INBOX:2"]])
        #expect(await localIndex.cachedHeaderRequests == [
            LocalSearchIndexRecorder.HeaderPageRequest(folderID: "INBOX", pageToken: nil),
        ])
    }

    @Test("headers-only retention clears all downloaded local index bodies")
    func headersOnlyRetentionClearsAllDownloadedLocalIndexBodies() async throws {
        let localIndex = LocalSearchIndexRecorder()
        let now = Date()
        let recent = Self.retentionHeader(id: "INBOX:1", date: now)
        let old = Self.retentionHeader(id: "INBOX:2", date: now.addingTimeInterval(-400 * 86400))
        await localIndex.setHeaderPage(
            folderID: "INBOX",
            pageToken: nil,
            headers: [recent],
            nextPageToken: "older"
        )
        await localIndex.setHeaderPage(
            folderID: "INBOX",
            pageToken: "older",
            headers: [old],
            nextPageToken: nil
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            localSearchIndex: localIndex
        )
        try await backend.connect()

        await backend.applyRetention(folderID: "INBOX", retentionDays: nil, keepsBodies: false)

        #expect(await localIndex.deletedRawMessageFolders == ["INBOX"])
        #expect(await localIndex.deletedRawMessageBatches.isEmpty)
        #expect(await localIndex.cachedHeaderRequests == [
            LocalSearchIndexRecorder.HeaderPageRequest(folderID: "INBOX", pageToken: nil),
            LocalSearchIndexRecorder.HeaderPageRequest(folderID: "INBOX", pageToken: "older"),
        ])
    }

    @Test("headers-only retention clears local index bodies even without headers")
    func headersOnlyRetentionClearsLocalIndexBodiesEvenWithoutHeaders() async throws {
        let folderCache = InMemoryIMAPFolderSnapshotCache(snapshotsByAccount: [
            Self.account.id: IMAPFolderCacheSnapshot(folders: [
                Folder(id: "INBOX", name: "Inbox", role: .inbox),
            ]),
        ])
        let localIndex = LocalSearchIndexRecorder()
        await localIndex.setRawMessage(
            Data("Subject: body only\r\n\r\nbody before header".utf8),
            for: "INBOX:99"
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            folderCache: folderCache,
            localSearchIndex: localIndex
        )

        await backend.applyRetention(folderID: "INBOX", retentionDays: nil, keepsBodies: false)

        let cachedRawMessage = await localIndex.cachedRawMessage(for: "INBOX:99", account: Self.account)
        #expect(cachedRawMessage == nil)
        #expect(await localIndex.deletedRawMessageFolders == ["INBOX"])
        #expect(await localIndex.cachedHeaderRequests == [
            LocalSearchIndexRecorder.HeaderPageRequest(folderID: "INBOX", pageToken: nil),
        ])
    }

    @Test("headers-only retention clears source cache bodies even without headers")
    func headersOnlyRetentionClearsSourceCacheBodiesEvenWithoutHeaders() async throws {
        let sourceCache = InMemoryIMAPMessageSourceCache()
        await sourceCache.setSource(
            IMAPMessageSource(uid: 99, rawMessage: "Subject: body only\r\n\r\nbody before header"),
            accountID: Self.account.id,
            messageID: "INBOX:99"
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 42, rawMessage: "Subject: nested\r\n\r\nnested body"),
            accountID: Self.account.id,
            messageID: "INBOX:Archive:42"
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sourceCache: sourceCache
        )

        await backend.applyRetention(folderID: "INBOX", retentionDays: nil, keepsBodies: false)

        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:99") == nil)
        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:Archive:42") != nil)
    }

    @Test("applyRetention combines complete local index with partial header cache")
    func applyRetentionCombinesCompleteLocalIndexWithPartialHeaderCache() async throws {
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let localIndex = LocalSearchIndexRecorder()
        let now = Date()
        let recent = Self.retentionHeader(id: "INBOX:1", date: now.addingTimeInterval(-2 * 86400))
        let old = Self.retentionHeader(id: "INBOX:2", date: now.addingTimeInterval(-60 * 86400))
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [recent], nextPageToken: nil),
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        await localIndex.setHeaderPage(
            folderID: "INBOX",
            pageToken: nil,
            headers: [recent],
            nextPageToken: "older"
        )
        await localIndex.setHeaderPage(
            folderID: "INBOX",
            pageToken: "older",
            headers: [old],
            nextPageToken: nil
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 1, rawMessage: "recent body"),
            accountID: Self.account.id,
            messageID: "INBOX:1"
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 2, rawMessage: "old body"),
            accountID: Self.account.id,
            messageID: "INBOX:2"
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            headerCache: headerCache,
            sourceCache: sourceCache,
            localSearchIndex: localIndex
        )
        try await backend.connect()

        await backend.applyRetention(folderID: "INBOX", retentionDays: 30, keepsBodies: true)

        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:1") != nil)
        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:2") == nil)
        #expect(await localIndex.deletedRawMessageBatches == [["INBOX:2"]])
        #expect(await localIndex.cachedHeaderRequests == [
            LocalSearchIndexRecorder.HeaderPageRequest(folderID: "INBOX", pageToken: nil),
            LocalSearchIndexRecorder.HeaderPageRequest(folderID: "INBOX", pageToken: "older"),
        ])
    }

    @Test("applyRetention combines partial local index with header cache")
    func applyRetentionCombinesPartialLocalIndexWithHeaderCache() async throws {
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let localIndex = LocalSearchIndexRecorder()
        let now = Date()
        let recent = Self.retentionHeader(id: "INBOX:1", date: now.addingTimeInterval(-2 * 86400))
        let old = Self.retentionHeader(id: "INBOX:2", date: now.addingTimeInterval(-60 * 86400))
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [recent, old], nextPageToken: nil),
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        await localIndex.setHeaderPage(
            folderID: "INBOX",
            pageToken: nil,
            headers: [recent],
            nextPageToken: nil
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 1, rawMessage: "recent body"),
            accountID: Self.account.id,
            messageID: "INBOX:1"
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 2, rawMessage: "old body"),
            accountID: Self.account.id,
            messageID: "INBOX:2"
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            headerCache: headerCache,
            sourceCache: sourceCache,
            localSearchIndex: localIndex
        )
        try await backend.connect()

        await backend.applyRetention(folderID: "INBOX", retentionDays: 30, keepsBodies: true)

        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:1") != nil)
        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:2") == nil)
        #expect(await localIndex.deletedRawMessageBatches == [["INBOX:2"]])
        #expect(await localIndex.cachedHeaderRequests == [
            LocalSearchIndexRecorder.HeaderPageRequest(folderID: "INBOX", pageToken: nil),
        ])
    }

    private static func retentionHeader(id: String, date: Date) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: id,
            folderID: "INBOX",
            from: Correspondent(email: "person@example.org"),
            to: [Correspondent(email: "me@example.org")],
            subject: "Subject \(id)",
            snippet: "Snippet",
            date: date
        )
    }

    private static func retentionBackend(
        headerCache: InMemoryIMAPMailboxHeaderCache,
        sourceCache: InMemoryIMAPMessageSourceCache
    ) -> IMAPSMTPBackend {
        IMAPSMTPBackend(
            account: account,
            configuration: configuration,
            credential: credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            headerCache: headerCache,
            sourceCache: sourceCache
        )
    }

    @Test("messages update cached page cursor when older IMAP page loads")
    func messagesUpdateCachedPageCursorWhenOlderIMAPPageLoads() async throws {
        let recorder = MessageListingRecorder(page: IMAPMessageListingPage(
            messages: [Self.messageListing(uid: 43, subject: "Newest")],
            nextPageToken: "before:43"
        ))
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            headerCache: headerCache
        )
        try await backend.connect()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        _ = try await backend.messages(in: inbox, pageToken: nil)
        await recorder.setMessages([
            Self.messageListing(uid: 41, subject: "Older cached"),
        ], nextPageToken: "before:41")
        _ = try await backend.messages(in: inbox, pageToken: "before:43")
        let cacheOnlyBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            headerCache: headerCache
        )
        try await cacheOnlyBackend.connect()

        let page = try await cacheOnlyBackend.messages(in: inbox, pageToken: nil)

        #expect(page.headers.map(\.id) == ["INBOX:43", "INBOX:41"])
        #expect(page.nextPageToken == "before:41")
    }

    @Test("older IMAP page reload emits updates for changed cached headers")
    func olderIMAPPageReloadEmitsUpdatesForChangedCachedHeaders() async throws {
        let recorder = MessageListingRecorder(page: IMAPMessageListingPage(
            messages: [Self.messageListing(uid: 43, subject: "Newest")],
            nextPageToken: "before:43"
        ))
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let localSearchIndex = LocalSearchIndexRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            headerCache: headerCache,
            localSearchIndex: localSearchIndex
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        _ = try await backend.messages(in: inbox, pageToken: nil)
        await recorder.setMessages([
            Self.messageListing(uid: 41, subject: "Older cached"),
        ], nextPageToken: nil)
        _ = try await backend.messages(in: inbox, pageToken: "before:43")
        await recorder.setMessages([
            Self.messageListing(
                uid: 41,
                subject: "Older cached",
                isRead: true,
                isFlagged: true
            ),
        ], nextPageToken: nil)
        await localSearchIndex.delayNextHeaderStore(by: 200_000_000)
        let pageTask = Task {
            try await backend.messages(in: inbox, pageToken: "before:43")
        }

        let event = try await nextIMAPEvent(from: stream)
        #expect(event == .messagesUpdated(folderID: "INBOX", messageIDs: ["INBOX:41"]))
        let cachedHeaders = await headerCache.snapshot(accountID: Self.account.id, folderID: "INBOX")?.headers
        let cachedOlderHeader = cachedHeaders?.first { $0.id == "INBOX:41" }
        #expect(cachedOlderHeader?.isRead == true)
        #expect(cachedOlderHeader?.isFlagged == true)
        let indexedOlderHeader = await localSearchIndex.storedHeaderBatches
            .last?
            .first { $0.id == "INBOX:41" }
        #expect(indexedOlderHeader?.isRead == true)
        #expect(indexedOlderHeader?.isFlagged == true)
        _ = try await pageTask.value
    }

    @Test("older IMAP page reload emits removals for missing cached page headers")
    func olderIMAPPageReloadEmitsRemovalsForMissingCachedPageHeaders() async throws {
        let recorder = MessageListingRecorder(page: IMAPMessageListingPage(
            messages: [Self.messageListing(uid: 43, subject: "Newest")],
            nextPageToken: "before:43"
        ))
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            headerCache: headerCache,
            sourceCache: sourceCache
        )
        await sourceCache.setSource(
            IMAPMessageSource(uid: 41, rawMessage: "Subject: Removed\r\n\r\nGone"),
            accountID: Self.account.id,
            messageID: "INBOX:41"
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        _ = try await backend.messages(in: inbox, pageToken: nil)
        await recorder.setMessages([
            Self.messageListing(uid: 42, subject: "Older kept"),
            Self.messageListing(uid: 41, subject: "Older removed later"),
        ], nextPageToken: nil)
        _ = try await backend.messages(in: inbox, pageToken: "before:43")
        await recorder.setMessages([
            Self.messageListing(uid: 42, subject: "Older kept"),
        ], nextPageToken: nil)
        _ = try await backend.messages(in: inbox, pageToken: "before:43")

        let event = try await nextIMAPEvent(from: stream)
        #expect(event == .messagesRemoved(folderID: "INBOX", messageIDs: ["INBOX:41"]))
        let cachedHeaders = await headerCache.snapshot(accountID: Self.account.id, folderID: "INBOX")?.headers
        #expect(cachedHeaders?.map(\.id) == ["INBOX:43", "INBOX:42"])
        let cachedSource = await sourceCache.source(
            accountID: Self.account.id,
            messageID: "INBOX:41"
        )
        #expect(cachedSource == nil)
    }

    @Test("first page refresh preserves cached older pages and prunes stale first page headers")
    func firstPageRefreshPreservesCachedOlderPagesAndPrunesStaleFirstPageHeaders() async throws {
        let recorder = MessageListingRecorder(page: IMAPMessageListingPage(
            messages: [
                Self.messageListing(uid: 43, subject: "Newest"),
                Self.messageListing(uid: 42, subject: "Old first page"),
            ],
            nextPageToken: "before:42"
        ))
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            headerCache: headerCache
        )
        try await backend.connect()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        _ = try await backend.messages(in: inbox, pageToken: nil)
        await recorder.setMessages([
            Self.messageListing(uid: 41, subject: "Older retained"),
        ], nextPageToken: nil)
        _ = try await backend.messages(in: inbox, pageToken: "before:42")
        await recorder.setMessages([
            Self.messageListing(uid: 44, subject: "New arrival"),
            Self.messageListing(uid: 43, subject: "Newest"),
        ], nextPageToken: "before:43")
        try await backend.refresh(folder: inbox)

        let cacheOnlyBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            headerCache: headerCache
        )
        try await cacheOnlyBackend.connect()

        let retainedOlder = try await cacheOnlyBackend.search(SearchQuery(
            text: "Older retained",
            execution: .cacheOnly
        ))
        let staleFirstPage = try await cacheOnlyBackend.search(SearchQuery(
            text: "Old first page",
            execution: .cacheOnly
        ))

        #expect(retainedOlder.map(\.id) == ["INBOX:41"])
        #expect(staleFirstPage.isEmpty)
    }

    @Test("complete first page refresh prunes stale older cached pages")
    func completeFirstPageRefreshPrunesStaleOlderCachedPages() async throws {
        let recorder = MessageListingRecorder(page: IMAPMessageListingPage(
            messages: [
                Self.messageListing(uid: 43, subject: "Newest"),
                Self.messageListing(uid: 42, subject: "Older first page"),
            ],
            nextPageToken: "before:42"
        ))
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            headerCache: headerCache,
            sourceCache: sourceCache
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        _ = try await backend.messages(in: inbox, pageToken: nil)
        await recorder.setMessages([
            Self.messageListing(uid: 41, subject: "Removed older cached page"),
        ], nextPageToken: nil)
        _ = try await backend.messages(in: inbox, pageToken: "before:42")
        await sourceCache.setSource(
            IMAPMessageSource(uid: 41, rawMessage: "Subject: Removed older\r\n\r\nGone"),
            accountID: Self.account.id,
            messageID: "INBOX:41"
        )
        await recorder.setMessages([
            Self.messageListing(uid: 44, subject: "Only remaining newest"),
            Self.messageListing(uid: 43, subject: "Newest"),
        ], nextPageToken: nil)

        try await backend.refresh(folder: inbox)
        let removed = try await nextIMAPEvent(from: stream)
        let cachedHeaders = await headerCache.snapshot(accountID: Self.account.id, folderID: "INBOX")?.headers
        let cachedSource = await sourceCache.source(
            accountID: Self.account.id,
            messageID: "INBOX:41"
        )

        #expect(removed == .messagesRemoved(folderID: "INBOX", messageIDs: ["INBOX:42", "INBOX:41"]))
        #expect(cachedHeaders?.map(\.id) == ["INBOX:44", "INBOX:43"])
        #expect(cachedSource == nil)
    }

    @Test("messages cache first page cursor and fall back when IMAP listing transport fails")
    func messagesCacheFirstPageCursorAndFallBackWhenIMAPListingTransportFails() async throws {
        let recorder = MessageListingRecorder(messages: [
            Self.messageListing(uid: 43, subject: "Cached invoice"),
        ])
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            headerCache: headerCache
        )
        try await backend.connect()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        let online = try await backend.messages(in: inbox, pageToken: nil)
        await recorder.setError(IMAPClientError.transport("Offline"))
        let fallback = try await backend.messages(in: inbox, pageToken: nil)
        try await recorder.waitUntilCallCount(2)

        #expect(online.headers.map(\.id) == ["INBOX:43"])
        #expect(online.nextPageToken == "before:42")
        #expect(fallback.headers.map(\.id) == ["INBOX:43"])
        #expect(fallback.nextPageToken == "before:42")
        #expect(await recorder.callCount == 2)
    }

    @Test("cache only search uses cached IMAP headers")
    func cacheOnlySearchUsesCachedIMAPHeaders() async throws {
        let recorder = MessageListingRecorder(messages: [
            Self.messageListing(uid: 43, subject: "Cached invoice"),
            Self.messageListing(uid: 44, subject: "Build alert"),
        ])
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            headerCache: headerCache
        )
        try await backend.connect()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        _ = try await backend.messages(in: inbox, pageToken: nil)

        let results = try await backend.search(SearchQuery(
            text: "invoice",
            folderID: "INBOX",
            execution: .cacheOnly
        ))

        #expect(results.map(\.id) == ["INBOX:43"])
    }

    @Test("all-folder cache-only search uses cached folders while disconnected")
    func allFolderCacheOnlySearchUsesCachedFoldersWhileDisconnected() async throws {
        let folderCache = InMemoryIMAPFolderSnapshotCache(snapshotsByAccount: [
            Self.account.id: IMAPFolderCacheSnapshot(folders: [
                Folder(id: "INBOX", name: "Inbox", role: .inbox),
                Folder(id: "Archive", name: "Archive", role: .archive),
            ]),
        ])
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let archiveHeader = MessageHeader(
            id: "Archive:7",
            threadID: "Archive:7",
            folderID: "Archive",
            from: Correspondent(email: "person@example.org"),
            to: [Correspondent(email: "me@example.org")],
            subject: "Archived invoice",
            snippet: "From the durable cache",
            date: Date(timeIntervalSince1970: 7)
        )
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [
                MessageHeader(
                    id: "INBOX:43",
                    threadID: "INBOX:43",
                    folderID: "INBOX",
                    from: Correspondent(email: "person@example.org"),
                    to: [Correspondent(email: "me@example.org")],
                    subject: "Inbox notice",
                    snippet: "Different cached folder",
                    date: Date(timeIntervalSince1970: 43)
                ),
            ]),
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [archiveHeader]),
            accountID: Self.account.id,
            folderID: "Archive"
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in
                throw IMAPClientError.transport("Offline")
            },
            folderCache: folderCache,
            headerCache: headerCache
        )

        let results = try await backend.search(SearchQuery(
            text: "invoice",
            execution: .cacheOnly
        ))

        #expect(results.map(\.id) == ["Archive:7"])
    }

    @Test("cache then server search falls back to cached headers when provider rejects search form")
    func cacheThenServerSearchFallsBackToCachedHeadersWhenProviderRejectsSearchForm() async throws {
        let recorder = MessageListingRecorder(messages: [
            Self.messageListing(uid: 43, subject: "Cached invoice"),
            Self.messageListing(uid: 44, subject: "Build alert"),
        ])
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            searchMessages: { _, _, _, _, _ in
                throw IMAPClientError.commandFailed(
                    command: "UID SEARCH",
                    response: "BAD unsupported search form"
                )
            },
            headerCache: headerCache
        )
        try await backend.connect()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        _ = try await backend.messages(in: inbox, pageToken: nil)

        let results = try await backend.search(SearchQuery(
            text: "invoice",
            folderID: "INBOX",
            execution: .cacheThenServer
        ))

        #expect(results.map(\.id) == ["INBOX:43"])
    }

    @Test("all-folder server search skips non-selectable mailboxes such as Gmail [Gmail]")
    func allFolderServerSearchSkipsNonSelectableMailboxes() async throws {
        let searchRecorder = MessageSearchRecorder(messages: [
            "INBOX": [Self.messageListing(uid: 11, subject: "Invoice 11")],
            "[Gmail]/All Mail": [Self.messageListing(uid: 22, subject: "Invoice 22")],
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
                IMAPFolderListing(
                    path: "[Gmail]",
                    displayName: "[Gmail]",
                    delimiter: "/",
                    flags: ["noselect", "haschildren"],
                    role: .custom
                ),
                IMAPFolderListing(
                    path: "[Gmail]/All Mail",
                    displayName: "All Mail",
                    delimiter: "/",
                    flags: ["all"],
                    role: .allMail
                ),
            ] },
            listMessages: { _, _, _, _, _ in IMAPMessageListingPage(messages: []) },
            searchMessages: { configuration, credential, folderID, query, limit in
                #expect(folderID != "[Gmail]")
                return try await searchRecorder.searchMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    query: query,
                    limit: limit
                )
            }
        )
        try await backend.connect()

        let results = try await backend.search(SearchQuery(
            subject: "Invoice",
            execution: .serverOnly
        ))

        #expect(await Set(searchRecorder.requestedFolderIDs) == Set(["INBOX", "[Gmail]/All Mail"]))
        #expect(results.map(\.id).sorted() == ["INBOX:11", "[Gmail]/All Mail:22"].sorted())
    }

    @Test("server only search does not silently fall back to cached headers")
    func serverOnlySearchDoesNotSilentlyFallBackToCachedHeaders() async throws {
        let recorder = MessageListingRecorder(messages: [
            Self.messageListing(uid: 43, subject: "Cached invoice"),
            Self.messageListing(uid: 44, subject: "Build alert"),
        ])
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            searchMessages: { _, _, _, _, _ in
                throw IMAPClientError.commandFailed(
                    command: "UID SEARCH",
                    response: "BAD unsupported search form"
                )
            },
            headerCache: headerCache
        )
        try await backend.connect()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        _ = try await backend.messages(in: inbox, pageToken: nil)

        await #expect(throws: IMAPClientError.self) {
            _ = try await backend.search(SearchQuery(
                text: "invoice",
                folderID: "INBOX",
                execution: .serverOnly
            ))
        }
    }

    @Test("server only search requires server search operation even with cached headers")
    func serverOnlySearchRequiresServerSearchOperationEvenWithCachedHeaders() async throws {
        let recorder = MessageListingRecorder(messages: [
            Self.messageListing(uid: 43, subject: "Cached invoice"),
            Self.messageListing(uid: 44, subject: "Build alert"),
        ])
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            headerCache: headerCache
        )
        try await backend.connect()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        _ = try await backend.messages(in: inbox, pageToken: nil)

        await #expect(throws: MailBackendError.self) {
            _ = try await backend.search(SearchQuery(
                text: "invoice",
                folderID: "INBOX",
                execution: .serverOnly
            ))
        }
    }

    @Test("capabilities advertise IMAP server search when search operation is available")
    func capabilitiesAdvertiseIMAPServerSearchWhenSearchOperationIsAvailable() {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            searchMessages: { _, _, _, _, _ in [] }
        )

        #expect(backend.capabilities.contains(.providerSyncHealth))
        #expect(backend.capabilities.contains(.serverSideSearch))
    }

    @Test("capabilities omit IMAP server search without search operation")
    func capabilitiesOmitIMAPServerSearchWithoutSearchOperation() {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] }
        )

        #expect(backend.capabilities.contains(.providerSyncHealth))
        #expect(!backend.capabilities.contains(.serverSideSearch))
    }

    @Test("search queries folders through IMAP search operation")
    func searchQueriesFoldersThroughIMAPSearchOperation() async throws {
        let recorder = MessageSearchRecorder(messages: [
            "INBOX": [
                IMAPMessageListing(
                    uid: 91,
                    messageID: "<msg-91@example.org>",
                    subject: "CI receipt",
                    from: Correspondent(name: "GitHub", email: "notifications@github.com"),
                    to: [Correspondent(email: "person@example.org")],
                    cc: [],
                    bcc: [],
                    date: Date(timeIntervalSince1970: 1_780_750_800),
                    isRead: true,
                    isFlagged: false,
                    isAnswered: false
                ),
            ],
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
                IMAPFolderListing(
                    path: "Archive",
                    displayName: "Archive",
                    delimiter: "/",
                    flags: [],
                    role: .archive
                ),
            ] },
            searchMessages: { configuration, credential, folderID, query, limit in
                try await recorder.searchMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    query: query,
                    limit: limit
                )
            }
        )
        try await backend.connect()

        let results = try await backend.search(SearchQuery(
            text: "receipt",
            folderID: "INBOX",
            execution: .serverOnly
        ))

        #expect(await recorder.requestedFolderIDs == ["INBOX"])
        #expect(await recorder.requestedLimits == [200])
        #expect(results.map(\.id) == ["INBOX:91"])
        #expect(results.first?.folderID == "INBOX")
    }

    @Test("all-folder server search queries every IMAP folder")
    func allFolderServerSearchQueriesEveryIMAPFolder() async throws {
        let recorder = MessageSearchRecorder(messages: [
            "INBOX": [
                Self.messageListing(uid: 91, subject: "Inbox receipt"),
            ],
            "Archive": [
                Self.messageListing(uid: 7, subject: "Archive receipt"),
            ],
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
                IMAPFolderListing(
                    path: "Archive",
                    displayName: "Archive",
                    delimiter: "/",
                    flags: [],
                    role: .archive
                ),
            ] },
            searchMessages: { configuration, credential, folderID, query, limit in
                try await recorder.searchMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    query: query,
                    limit: limit
                )
            }
        )
        try await backend.connect()

        let results = try await backend.search(SearchQuery(
            text: "receipt",
            execution: .serverOnly
        ))

        #expect(await recorder.requestedFolderIDs == ["INBOX", "Archive"])
        #expect(await recorder.requestedLimits == [200, 200])
        #expect(await recorder.requestedQueries == [
            SearchQuery(text: "receipt", execution: .serverOnly),
            SearchQuery(text: "receipt", execution: .serverOnly),
        ])
        #expect(results.map(\.id) == ["INBOX:91", "Archive:7"])
        #expect(results.map(\.folderID) == ["INBOX", "Archive"])
    }

    @Test("server-only search skips local index reads")
    func serverOnlySearchSkipsLocalIndexReads() async throws {
        let searchRecorder = MessageSearchRecorder(messages: [
            "INBOX": [
                Self.messageListing(uid: 91, subject: "Server receipt"),
            ],
        ])
        let localIndex = LocalSearchIndexRecorder()
        await localIndex.setSearchResults([
            Self.retentionHeader(
                id: "INBOX:77",
                date: Date(timeIntervalSince1970: 77)
            ),
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            searchMessages: { configuration, credential, folderID, query, limit in
                try await searchRecorder.searchMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    query: query,
                    limit: limit
                )
            },
            localSearchIndex: localIndex
        )
        try await backend.connect()

        let results = try await backend.search(SearchQuery(
            text: "receipt",
            execution: .serverOnly
        ))

        #expect(await localIndex.searchRequests.isEmpty)
        #expect(await searchRecorder.requestedFolderIDs == ["INBOX"])
        #expect(results.map(\.id) == ["INBOX:91"])
    }

    @Test("search filters IMAP results by parsed attachment presence")
    func searchFiltersIMAPResultsByParsedAttachmentPresence() async throws {
        let plainReceipt = [
            "Subject: Plain receipt",
            "Content-Type: text/plain; charset=utf-8",
            "",
            "No files here.",
        ].joined(separator: "\n")
        let attachedReceipt = [
            "Subject: PDF receipt",
            "Content-Type: multipart/mixed; boundary=\"mixed-boundary\"",
            "",
            "--mixed-boundary",
            "Content-Type: text/plain; charset=utf-8",
            "",
            "Attached.",
            "--mixed-boundary",
            "Content-Type: application/pdf; name=\"receipt.pdf\"",
            "Content-Disposition: attachment; filename=\"receipt.pdf\"",
            "Content-Transfer-Encoding: base64",
            "",
            "SGVsbG8=",
            "--mixed-boundary--",
        ].joined(separator: "\n")
        let candidateUIDs = Array(1 ... 201)
        let listings = candidateUIDs.map { uid in
            Self.messageListing(
                uid: uid,
                subject: uid == 1 ? "Receipt with attachment" : "Receipt without attachment"
            )
        }
        let rawMessagesByUID = Dictionary(uniqueKeysWithValues: candidateUIDs.map { uid in
            (uid, uid == 1 ? attachedReceipt : plainReceipt)
        })
        let searchRecorder = MessageSearchRecorder(messages: [
            "INBOX": listings,
        ], appliesLimit: true)
        let sourceRecorder = MessageSourceByUIDRecorder(rawMessagesByUID: rawMessagesByUID)
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            searchMessages: { configuration, credential, folderID, query, limit in
                try await searchRecorder.searchMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    query: query,
                    limit: limit
                )
            },
            fetchMessageSource: { configuration, credential, folderID, uid in
                try await sourceRecorder.fetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            }
        )
        try await backend.connect()

        let results = try await backend.search(SearchQuery(
            text: "receipt",
            folderID: "INBOX",
            hasAttachments: true,
            execution: .serverOnly
        ))

        #expect(results.map(\.id) == ["INBOX:1"])
        #expect(results.first?.hasAttachments == true)
        #expect(await searchRecorder.requestedLimits == [Int.max])
        #expect(await searchRecorder.requestedQueries.first?.hasAttachments == nil)
        #expect(await sourceRecorder.requestedUIDs == candidateUIDs)
    }

    @Test("attachment search follows paginated server results beyond the first page")
    func attachmentSearchFollowsPaginatedServerResultsBeyondFirstPage() async throws {
        let plainMessage = "Subject: Plain\nContent-Type: text/plain; charset=utf-8\n\nNo file."
        let attachedMessage = """
        Subject: Older attachment
        Content-Type: application/pdf
        Content-Disposition: attachment; filename="older.pdf"

        body
        """
        let pageRecorder = MessageSearchPageRecorder(pages: [
            nil: IMAPMessageListingPage(
                messages: [Self.messageListing(uid: 300, subject: "Newest")],
                nextPageToken: "before:300"
            ),
            "before:300": IMAPMessageListingPage(messages: [Self.messageListing(uid: 100, subject: "Older attachment")]),
        ])
        let sourceRecorder = MessageSourceByUIDRecorder(rawMessagesByUID: [
            300: plainMessage,
            100: attachedMessage,
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(path: "INBOX", displayName: "Inbox", delimiter: "/", flags: [], role: .inbox),
            ] },
            searchMessagePage: { configuration, credential, folderID, query, pageToken, limit in
                try await pageRecorder.searchPage(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    query: query,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            fetchMessageSource: { configuration, credential, folderID, uid in
                try await sourceRecorder.fetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            }
        )
        try await backend.connect()

        let results = try await backend.search(SearchQuery(
            folderID: "INBOX",
            hasAttachments: true,
            execution: .serverOnly
        ))

        #expect(results.map(\.id) == ["INBOX:100"])
        #expect(await pageRecorder.requestedPageTokens == [nil, "before:300"])
        #expect(await pageRecorder.requestedLimits == [50, 50])
        #expect(await sourceRecorder.requestedUIDs == [300, 100])
    }

    @Test("cache-then-server attachment search continues to paginated server results")
    func cacheThenServerAttachmentSearchContinuesToPaginatedServerResults() async throws {
        let cachedHeader = MessageHeader(
            id: "INBOX:200",
            threadID: "INBOX:200",
            folderID: "INBOX",
            from: Correspondent(email: "sender@example.org"),
            to: [Correspondent(email: "person@example.org")],
            subject: "Cached attachment",
            snippet: "Cached",
            date: Date(timeIntervalSince1970: 200),
            hasAttachments: true
        )
        let headerCache = InMemoryIMAPMailboxHeaderCache(
            snapshotsByFolderByAccount: [
                Self.account.id: [
                    "INBOX": IMAPMailboxHeaderCacheSnapshot(headers: [cachedHeader]),
                ],
            ]
        )
        let pageRecorder = MessageSearchPageRecorder(pages: [
            nil: IMAPMessageListingPage(
                messages: [Self.messageListing(uid: 100, subject: "Server attachment")]
            ),
        ])
        let sourceRecorder = MessageSourceByUIDRecorder(rawMessagesByUID: [
            100: "Subject: Server attachment\nContent-Type: application/pdf\n"
                + "Content-Disposition: attachment; filename=server.pdf\n\nbody",
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(path: "INBOX", displayName: "Inbox", delimiter: "/", flags: [], role: .inbox),
            ] },
            searchMessagePage: { configuration, credential, folderID, query, pageToken, limit in
                try await pageRecorder.searchPage(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    query: query,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            fetchMessageSource: { configuration, credential, folderID, uid in
                try await sourceRecorder.fetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            },
            headerCache: headerCache
        )
        try await backend.connect()

        let results = try await backend.search(SearchQuery(
            folderID: "INBOX",
            hasAttachments: true,
            execution: .cacheThenServer
        ))

        #expect(results.map(\.id) == ["INBOX:100"])
        #expect(await pageRecorder.requestedPageTokens == [nil])
        #expect(await sourceRecorder.requestedUIDs == [100])
    }

    @Test("attachment search rejects a repeated server page cursor")
    func attachmentSearchRejectsRepeatedServerPageCursor() async throws {
        let pageRecorder = MessageSearchPageRecorder(pages: [
            nil: IMAPMessageListingPage(
                messages: [Self.messageListing(uid: 300, subject: "Newest")],
                nextPageToken: "before:300"
            ),
            "before:300": IMAPMessageListingPage(
                messages: [Self.messageListing(uid: 100, subject: "Older")],
                nextPageToken: "before:300"
            ),
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(path: "INBOX", displayName: "Inbox", delimiter: "/", flags: [], role: .inbox),
            ] },
            searchMessagePage: { configuration, credential, folderID, query, pageToken, limit in
                try await pageRecorder.searchPage(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    query: query,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            fetchMessageSource: { _, _, folderID, uid in
                IMAPMessageSource(uid: uid, rawMessage: "Subject: (folderID):(uid)\n\nbody")
            }
        )
        try await backend.connect()

        await #expect(throws: MailBackendError.self) {
            _ = try await backend.search(SearchQuery(
                folderID: "INBOX",
                hasAttachments: true,
                execution: .serverOnly
            ))
        }
    }

    @Test("set read and flagged translate message IDs to IMAP flag operations")
    func setReadAndFlaggedTranslateMessageIDsToIMAPFlagOperations() async throws {
        let recorder = MessageFlagRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            setMessageFlag: { configuration, credential, folderID, uids, flag, isEnabled in
                try await recorder.setMessageFlag(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uids: uids,
                    flag: flag,
                    isEnabled: isEnabled
                )
            }
        )
        try await backend.connect()

        try await backend.setRead(true, for: ["INBOX:43", "INBOX:44"])
        try await backend.setFlagged(false, for: ["Projects/Alpha:9"])

        #expect(await recorder.calls == [
            MessageFlagRecorder.Call(
                folderID: "INBOX",
                uids: [43, 44],
                flag: .seen,
                isEnabled: true
            ),
            MessageFlagRecorder.Call(
                folderID: "Projects/Alpha",
                uids: [9],
                flag: .flagged,
                isEnabled: false
            ),
        ])
    }

    @Test("set junk trains IMAP keywords and moves to spam or inbox when folders exist")
    func setJunkTrainsIMAPKeywordsAndMovesToDestinationFolders() async throws {
        let keywordRecorder = MessageKeywordRecorder()
        let moveRecorder = MessageMoveRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(path: "INBOX", displayName: "Inbox", delimiter: "/", flags: [], role: .inbox),
                IMAPFolderListing(path: "Spam", displayName: "Spam", delimiter: "/", flags: ["junk"], role: .spam),
            ] },
            setMessageKeyword: { configuration, credential, folderID, uids, keyword, isEnabled in
                try await keywordRecorder.setMessageKeyword(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uids: uids,
                    keyword: keyword,
                    isEnabled: isEnabled
                )
            },
            moveMessages: { configuration, credential, sourceFolderID, uids, destinationFolderID in
                try await moveRecorder.moveMessages(
                    configuration: configuration,
                    credential: credential,
                    sourceFolderID: sourceFolderID,
                    uids: uids,
                    destinationFolderID: destinationFolderID
                )
            }
        )
        try await backend.connect()

        #expect(backend.capabilities.contains(.junkAPI))

        try await backend.setJunk(true, for: ["INBOX:43"])
        try await backend.setJunk(false, for: ["Spam:44"])

        #expect(await keywordRecorder.calls == [
            MessageKeywordRecorder.Call(folderID: "INBOX", uids: [43], keyword: .junk, isEnabled: true),
            MessageKeywordRecorder.Call(folderID: "INBOX", uids: [43], keyword: .notJunk, isEnabled: false),
            MessageKeywordRecorder.Call(folderID: "Spam", uids: [44], keyword: .junk, isEnabled: false),
            MessageKeywordRecorder.Call(folderID: "Spam", uids: [44], keyword: .notJunk, isEnabled: true),
        ])
        #expect(await moveRecorder.calls == [
            MessageMoveRecorder.Call(sourceFolderID: "INBOX", uids: [43], destinationFolderID: "Spam"),
            MessageMoveRecorder.Call(sourceFolderID: "Spam", uids: [44], destinationFolderID: "INBOX"),
        ])
    }

    @Test("replay pending mutations applies queued IMAP junk training")
    func replayPendingMutationsAppliesQueuedIMAPJunkTraining() async throws {
        let queue = try Self.makeMutationQueue()
        try await queue.enqueue(PendingMutation(
            kind: .setJunk(true),
            messageIDs: ["INBOX:43"]
        ))
        let keywordRecorder = MessageKeywordRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(path: "INBOX", displayName: "Inbox", delimiter: "/", flags: [], role: .inbox),
                IMAPFolderListing(path: "Spam", displayName: "Spam", delimiter: "/", flags: ["junk"], role: .spam),
            ] },
            setMessageKeyword: { configuration, credential, folderID, uids, keyword, isEnabled in
                try await keywordRecorder.setMessageKeyword(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uids: uids,
                    keyword: keyword,
                    isEnabled: isEnabled
                )
            },
            offlineMutationQueue: queue
        )
        try await backend.connect()

        let result = try await backend.replayPendingMutations()

        #expect(result.succeeded.count == 1)
        #expect(result.retrying.isEmpty)
        #expect(result.conflicts.isEmpty)
        #expect(try await queue.pending().isEmpty)
        #expect(await keywordRecorder.calls == [
            MessageKeywordRecorder.Call(folderID: "INBOX", uids: [43], keyword: .junk, isEnabled: true),
            MessageKeywordRecorder.Call(folderID: "INBOX", uids: [43], keyword: .notJunk, isEnabled: false),
        ])
    }

    @Test("replay surfaces queued flag colors as a recoverable conflict")
    func replayPendingMutationsSurfacesQueuedFlagColorConflict() async throws {
        let queue = try Self.makeMutationQueue()
        try await queue.enqueue(PendingMutation(
            kind: .setFlagColor(.red),
            messageIDs: ["INBOX:43"]
        ))
        let conflictSuite = "OfflineFlagColorConflict-\(UUID().uuidString)"
        let conflictDefaults = try #require(UserDefaults(suiteName: conflictSuite))
        defer { conflictDefaults.removePersistentDomain(forName: conflictSuite) }
        let conflictStore = UserDefaultsMutationConflictStore(
            defaults: conflictDefaults,
            storageKey: "conflicts"
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            offlineMutationQueue: queue,
            offlineMutationConflictStore: conflictStore
        )
        try await backend.connect()

        let result = try await backend.replayPendingMutations()

        #expect(result.succeeded.isEmpty)
        #expect(result.retrying.isEmpty)
        #expect(result.conflicts.count == 1)
        #expect(result.conflicts.first?.reason == .rejectedByServer)
        #expect(try await queue.pending().isEmpty)
        #expect(try await conflictStore.conflicts().count == 1)
    }

    @Test("set read emits update and updates cached IMAP header")
    func setReadEmitsUpdateAndUpdatesCachedIMAPHeader() async throws {
        let recorder = MessageFlagRecorder()
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(messages: [
                    Self.messageListing(uid: 43, subject: "Unread"),
                ])
            },
            setMessageFlag: { configuration, credential, folderID, uids, flag, isEnabled in
                try await recorder.setMessageFlag(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uids: uids,
                    flag: flag,
                    isEnabled: isEnabled
                )
            },
            headerCache: headerCache
        )
        try await backend.connect()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        _ = try await backend.messages(in: inbox, pageToken: nil)
        let stream = backend.subscribeToChanges()

        try await backend.setRead(true, for: ["INBOX:43"])

        let event = try await nextIMAPEvent(from: stream)
        #expect(event == .messagesUpdated(folderID: "INBOX", messageIDs: ["INBOX:43"]))
        let cachedHeaders = await headerCache.snapshot(accountID: Self.account.id, folderID: "INBOX")?.headers
        #expect(cachedHeaders?.first?.isRead == true)
    }

    @Test("network-like IMAP flag errors enqueue pending read mutation")
    func networkLikeIMAPFlagErrorsEnqueuePendingReadMutation() async throws {
        let queue = try Self.makeMutationQueue()
        let recorder = MessageFlagRecorder()
        await recorder.setError(IMAPClientError.transport("offline"))
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            setMessageFlag: { configuration, credential, folderID, uids, flag, isEnabled in
                try await recorder.setMessageFlag(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uids: uids,
                    flag: flag,
                    isEnabled: isEnabled
                )
            },
            offlineMutationQueue: queue
        )
        try await backend.connect()

        try await backend.setRead(true, for: ["INBOX:43"])

        let pending = try await queue.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.kind == .setRead(true))
        #expect(pending.first?.sourceID == nil)
        #expect(pending.first?.messageIDs == ["INBOX:43"])
        #expect(pending.first?.attempt == 0)
        #expect(await recorder.calls == [
            MessageFlagRecorder.Call(
                folderID: "INBOX",
                uids: [43],
                flag: .seen,
                isEnabled: true
            ),
        ])
    }

    @Test("source-scoped read errors enqueue pending mutation with source")
    func sourceScopedReadErrorsEnqueuePendingMutationWithSource() async throws {
        let queue = try Self.makeMutationQueue()
        let recorder = MessageFlagRecorder()
        await recorder.setError(IMAPClientError.transport("offline"))
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            setMessageFlag: { configuration, credential, folderID, uids, flag, isEnabled in
                try await recorder.setMessageFlag(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uids: uids,
                    flag: flag,
                    isEnabled: isEnabled
                )
            },
            offlineMutationQueue: queue
        )
        try await backend.connect()

        try await backend.setRead(true, for: ["INBOX:43"], sourceID: Self.sourceID)

        let pending = try await queue.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.kind == .setRead(true))
        #expect(pending.first?.sourceID == Self.sourceID)
        #expect(pending.first?.messageIDs == ["INBOX:43"])
    }

    @Test("source-scoped mailbox actions reject stale IMAP mailbox source")
    func sourceScopedMailboxActionsRejectStaleIMAPMailboxSource() async throws {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] }
        )
        try await backend.connect()

        let staleSourceID = MailSourceID(
            accountID: Self.account.id,
            mailboxID: "stale-mailbox"
        )
        await expectNotFound("stale-mailbox") {
            try await backend.setRead(true, for: ["INBOX:43"], sourceID: staleSourceID)
        }
        await expectNotFound("stale-mailbox") {
            try await backend.setFlagged(true, for: ["INBOX:43"], sourceID: staleSourceID)
        }
        await expectNotFound("stale-mailbox") {
            try await backend.move(
                messageIDs: ["INBOX:43"],
                to: Folder(id: "Archive", name: "Archive", role: .archive),
                sourceID: staleSourceID
            )
        }
        await expectNotFound("stale-mailbox") {
            try await backend.copy(
                messageIDs: ["INBOX:43"],
                to: Folder(id: "Archive", name: "Archive", role: .archive),
                sourceID: staleSourceID
            )
        }
        await expectNotFound("stale-mailbox") {
            try await backend.delete(messageIDs: ["INBOX:43"], sourceID: staleSourceID)
        }
    }

    @Test("move groups message IDs by source folder")
    func moveGroupsMessageIDsBySourceFolder() async throws {
        let recorder = MessageMoveRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            moveMessages: { configuration, credential, sourceFolderID, uids, destinationFolderID in
                try await recorder.moveMessages(
                    configuration: configuration,
                    credential: credential,
                    sourceFolderID: sourceFolderID,
                    uids: uids,
                    destinationFolderID: destinationFolderID
                )
            }
        )
        try await backend.connect()

        try await backend.move(
            messageIDs: ["INBOX:43", "INBOX:44", "Projects/Alpha:9"],
            to: Folder(id: "Archive", name: "Archive", role: .archive)
        )

        #expect(await recorder.calls == [
            MessageMoveRecorder.Call(
                sourceFolderID: "INBOX",
                uids: [43, 44],
                destinationFolderID: "Archive"
            ),
            MessageMoveRecorder.Call(
                sourceFolderID: "Projects/Alpha",
                uids: [9],
                destinationFolderID: "Archive"
            ),
        ])
    }

    @Test("copy groups message IDs by source folder and refreshes destination")
    func copyGroupsMessageIDsBySourceFolderAndRefreshesDestination() async throws {
        let recorder = MessageMoveRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            copyMessages: { configuration, credential, sourceFolderID, uids, destinationFolderID in
                try await recorder.moveMessages(
                    configuration: configuration,
                    credential: credential,
                    sourceFolderID: sourceFolderID,
                    uids: uids,
                    destinationFolderID: destinationFolderID
                )
            }
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()
        try await Task.sleep(nanoseconds: 10_000_000)

        try await backend.copy(
            messageIDs: ["INBOX:43", "INBOX:44", "Projects/Alpha:9"],
            to: Folder(id: "Archive", name: "Archive", role: .archive)
        )

        #expect(await recorder.calls == [
            MessageMoveRecorder.Call(
                sourceFolderID: "INBOX",
                uids: [43, 44],
                destinationFolderID: "Archive"
            ),
            MessageMoveRecorder.Call(
                sourceFolderID: "Projects/Alpha",
                uids: [9],
                destinationFolderID: "Archive"
            ),
        ])
        #expect(try await nextIMAPEvent(from: stream) == .folderRefreshed(folderID: "Archive"))
    }

    @Test("move invalidates cached IMAP source for moved messages")
    func moveInvalidatesCachedIMAPSourceForMovedMessages() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevIMAPMessageSourceCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let sourceCache = FileIMAPMessageSourceCache(rootDirectory: rootDirectory)
        await sourceCache.setSource(
            IMAPMessageSource(uid: 43, rawMessage: "Content-Type: text/plain\n\nCached body."),
            accountID: Self.account.id,
            messageID: "INBOX:43"
        )
        let recorder = MessageMoveRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            moveMessages: { configuration, credential, sourceFolderID, uids, destinationFolderID in
                try await recorder.moveMessages(
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

        try await backend.move(
            messageIDs: ["INBOX:43"],
            to: Folder(id: "Archive", name: "Archive", role: .archive)
        )

        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:43") == nil)
        #expect(await recorder.calls == [
            MessageMoveRecorder.Call(
                sourceFolderID: "INBOX",
                uids: [43],
                destinationFolderID: "Archive"
            ),
        ])
    }

    @Test("move emits source removal and prunes cached IMAP header")
    func moveEmitsSourceRemovalAndPrunesCachedIMAPHeader() async throws {
        let recorder = MessageMoveRecorder()
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
                IMAPFolderListing(
                    path: "Archive",
                    displayName: "Archive",
                    delimiter: "/",
                    flags: ["archive"],
                    role: .archive
                ),
            ] },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(messages: [
                    Self.messageListing(uid: 43, subject: "Move me"),
                ])
            },
            moveMessages: { configuration, credential, sourceFolderID, uids, destinationFolderID in
                try await recorder.moveMessages(
                    configuration: configuration,
                    credential: credential,
                    sourceFolderID: sourceFolderID,
                    uids: uids,
                    destinationFolderID: destinationFolderID
                )
            },
            headerCache: headerCache
        )
        try await backend.connect()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        _ = try await backend.messages(in: inbox, pageToken: nil)
        let stream = backend.subscribeToChanges()

        try await backend.move(
            messageIDs: ["INBOX:43"],
            to: Folder(id: "Archive", name: "Archive", role: .archive)
        )

        let removed = try await nextIMAPEvent(from: stream)
        let destinationRefresh = try await nextIMAPEvent(from: stream)
        #expect(removed == .messagesRemoved(folderID: "INBOX", messageIDs: ["INBOX:43"]))
        #expect(destinationRefresh == .folderRefreshed(folderID: "Archive"))
        let cachedHeaders = await headerCache.snapshot(accountID: Self.account.id, folderID: "INBOX")?.headers
        #expect(cachedHeaders?.isEmpty == true)
    }

    @Test("replay pending mutations applies queued IMAP move")
    func replayPendingMutationsAppliesQueuedIMAPMove() async throws {
        let queue = try Self.makeMutationQueue()
        try await queue.enqueue(PendingMutation(
            kind: .move(folderID: "Archive"),
            messageIDs: ["INBOX:43"]
        ))
        let recorder = MessageMoveRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            moveMessages: { configuration, credential, sourceFolderID, uids, destinationFolderID in
                try await recorder.moveMessages(
                    configuration: configuration,
                    credential: credential,
                    sourceFolderID: sourceFolderID,
                    uids: uids,
                    destinationFolderID: destinationFolderID
                )
            },
            offlineMutationQueue: queue
        )
        try await backend.connect()

        let result = try await backend.replayPendingMutations()

        #expect(result.succeeded.count == 1)
        #expect(result.retrying.isEmpty)
        #expect(result.conflicts.isEmpty)
        #expect(try await queue.pending().isEmpty)
        #expect(await recorder.calls == [
            MessageMoveRecorder.Call(
                sourceFolderID: "INBOX",
                uids: [43],
                destinationFolderID: "Archive"
            ),
        ])
    }

    @Test("replaying an offline future-scheduled send re-registers the schedule, not immediate delivery")
    func replayPendingMutationsReschedulesFutureScheduledSend() async throws {
        // A scheduled send composed while OFFLINE is queued as a .send mutation
        // with its future scheduledFor intact (scheduleSend threw at
        // requireConnected before registering the schedule). Replaying it on
        // reconnect must re-register the schedule — NOT deliver immediately.
        let storageKey = "scheduledSends.\(Self.account.id)"
        UserDefaults.standard.removeObject(forKey: storageKey)
        defer { UserDefaults.standard.removeObject(forKey: storageKey) }

        // An isolated staging store gives a deterministic signal: scheduleSend
        // *stages* the draft, whereas performImmediateSend *clears* it. Reading
        // the shared ScheduledSendStore would be flaky under the suite's parallel
        // `person@example.org` connect()s.
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevOfflineScheduledReplay-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let draftStore = FileIMAPDraftStagingStore(rootDirectory: rootDirectory)

        let queue = try Self.makeMutationQueue()
        let scheduledFor = Date(timeIntervalSinceNow: 3600)
        let scheduledDraft = Self.outgoingDraft(id: "offline-scheduled", scheduledFor: scheduledFor)
        await draftStore.setDraft(scheduledDraft, accountID: Self.account.id)
        try await queue.enqueue(PendingMutation(
            kind: .send(draft: scheduledDraft),
            messageIDs: []
        ))

        let sendCounter = OfflineSendReplayCallCounter()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { _, _, _ in
                await sendCounter.increment()
                return SendResult(sentMessageID: nil, scheduledFor: nil)
            },
            draftStagingStore: draftStore,
            offlineMutationQueue: queue
        )
        try await backend.connect()
        defer { Task { await backend.disconnect() } }

        let result = try await backend.replayPendingMutations()

        #expect(result.succeeded.count == 1)
        #expect(try await queue.pending().isEmpty)
        // The message must NOT have been delivered to SMTP on reconnect…
        #expect(await sendCounter.count == 0)
        // …and the draft must be re-staged for later scheduled delivery
        // (scheduleSend stages it; performImmediateSend would have cleared it).
        #expect(await draftStore.draft(accountID: Self.account.id, draftID: "offline-scheduled") != nil)
    }

    @Test("sync health reports pending IMAP mutations")
    func syncHealthReportsPendingIMAPMutations() async throws {
        let queue = try Self.makeMutationQueue()
        try await queue.enqueue(PendingMutation(
            kind: .setRead(true),
            messageIDs: ["INBOX:43"]
        ))
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            offlineMutationQueue: queue
        )
        try await backend.connect()

        #expect(backend.capabilities.contains(.providerSyncHealth))
        let reporter = try #require(backend.extensionService(SyncHealthReporting.self))
        let health = await reporter.syncHealth(for: Self.sourceID)

        #expect(health.sourceID == Self.sourceID)
        #expect(health.state == .degraded)
        #expect(health.lastSuccessfulSyncAt != nil)
        #expect(health.pendingMutationCount == 1)
    }

    @Test("sync health reports local search index metrics")
    func syncHealthReportsLocalSearchIndexMetrics() async throws {
        let localIndex = LocalSearchIndexRecorder()
        let metrics = LocalSearchIndexMetrics(
            databaseBytes: 8192,
            indexedHeaderCount: 10,
            cachedBodyCount: 7,
            searchDocumentCount: 10,
            syncedFolderCount: 3
        )
        await localIndex.setMetrics(metrics)
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            localSearchIndex: localIndex
        )

        let health = await backend.syncHealth(for: Self.sourceID)

        #expect(health.localSearchIndexMetrics == metrics)
        #expect(health.cacheSizeBytes == 8192)
    }

    @Test("sync health reports replay conflicts after IMAP mutation retry")
    func syncHealthReportsReplayConflictsAfterIMAPMutationRetry() async throws {
        let queue = try Self.makeMutationQueue()
        try await queue.enqueue(PendingMutation(
            kind: .move(folderID: "Archive"),
            messageIDs: ["INBOX:404"]
        ))
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            moveMessages: { _, _, _, _, _ in
                throw MailBackendError.notFound(id: "INBOX:404")
            },
            offlineMutationQueue: queue
        )
        try await backend.connect()

        let result = try await backend.replayPendingMutations()
        let reporter = try #require(backend.extensionService(SyncHealthReporting.self))
        let health = await reporter.syncHealth(for: Self.sourceID)

        #expect(result.conflicts.count == 1)
        #expect(result.conflicts.first?.reason == .targetMissing)
        #expect(try await queue.pending().isEmpty)
        #expect(health.state == .degraded)
        #expect(health.pendingMutationCount == 0)
        #expect(health.replayConflictCount == 1)
        #expect(health.lastErrorDescription?.contains("queued mail change") == true)
        #expect(health.lastErrorDescription?.contains("INBOX:404") == true)
    }

    @Test("sync health restores persisted IMAP replay conflicts")
    func syncHealthRestoresPersistedIMAPReplayConflicts() async throws {
        let suiteName = "IMAPSMTPBackendConflictTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let queue = UserDefaultsMutationQueue(defaults: defaults, storageKey: "q")
        let conflictStore = UserDefaultsMutationConflictStore(
            defaults: defaults,
            storageKey: "conflicts"
        )
        try await queue.enqueue(PendingMutation(
            kind: .move(folderID: "Archive"),
            messageIDs: ["INBOX:404"]
        ))
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            moveMessages: { _, _, _, _, _ in
                throw MailBackendError.notFound(id: "INBOX:404")
            },
            offlineMutationQueue: queue,
            offlineMutationConflictStore: conflictStore
        )
        try await backend.connect()
        _ = try await backend.replayPendingMutations()

        let restoredBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            offlineMutationConflictStore: conflictStore
        )
        try await restoredBackend.connect()
        let reporter = try #require(restoredBackend.extensionService(SyncHealthReporting.self))
        let health = await reporter.syncHealth(for: Self.sourceID)

        #expect(health.state == .degraded)
        #expect(health.pendingMutationCount == 0)
        #expect(health.replayConflictCount == 1)
        #expect(health.lastErrorDescription?.contains("queued mail change") == true)
        #expect(health.lastErrorDescription?.contains("INBOX:404") == true)
    }

    @Test("sync conflict review lists persisted IMAP replay conflicts")
    func syncConflictReviewListsPersistedIMAPReplayConflicts() async throws {
        let suiteName = "IMAPSMTPBackendConflictReviewTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let conflictStore = UserDefaultsMutationConflictStore(
            defaults: defaults,
            storageKey: "conflicts"
        )
        try await conflictStore.append([
            MutationConflict(
                mutation: PendingMutation(
                    kind: .move(folderID: "Archive"),
                    messageIDs: ["INBOX:404"]
                ),
                reason: .targetMissing,
                message: "The item no longer exists on the server (INBOX:404)."
            ),
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            offlineMutationConflictStore: conflictStore
        )
        try await backend.connect()

        let reviewer = try #require(backend.extensionService(SyncConflictReviewing.self))
        let conflicts = try await reviewer.syncConflicts(for: Self.sourceID)

        #expect(conflicts.count == 1)
        #expect(conflicts.first?.reason == .targetMissing)
        #expect(conflicts.first?.message.contains("INBOX:404") == true)
    }

    @Test("sync repair clears reviewed IMAP replay conflicts")
    func syncRepairClearsReviewedIMAPReplayConflicts() async throws {
        let suiteName = "IMAPSMTPBackendConflictClearTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let conflictStore = UserDefaultsMutationConflictStore(
            defaults: defaults,
            storageKey: "conflicts"
        )
        try await conflictStore.append([
            MutationConflict(
                mutation: PendingMutation(
                    kind: .move(folderID: "Archive"),
                    messageIDs: ["INBOX:404"]
                ),
                reason: .targetMissing,
                message: "The item no longer exists on the server (INBOX:404)."
            ),
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            offlineMutationConflictStore: conflictStore
        )
        try await backend.connect()
        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))

        try await repair.clearSyncConflicts(for: Self.sourceID)
        let health = await backend.syncHealth(for: Self.sourceID)

        #expect(try await conflictStore.conflicts().isEmpty)
        #expect(health.state == .healthy)
        #expect(health.lastErrorDescription == nil)
    }

    @Test("reset local cache clears draft staging and offline mutation metadata")
    func resetLocalCacheClearsDraftStagingAndOfflineMetadata() async throws {
        let draftStore = InMemoryIMAPDraftStagingStore()
        await draftStore.setDraft(
            Draft(id: "local-draft", subject: "Cached draft", htmlBody: "<p>Cached</p>"),
            accountID: Self.account.id
        )
        await draftStore.setAttachment(
            IMAPDraftStagedAttachment(
                id: "attachment-1",
                draftID: "local-draft",
                filename: "cached.txt",
                mimeType: "text/plain",
                data: Data("cached".utf8)
            ),
            accountID: Self.account.id
        )
        let suiteName = "IMAPSMTPBackendResetCacheTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let queue = UserDefaultsMutationQueue(defaults: defaults, storageKey: "q")
        let conflictStore = UserDefaultsMutationConflictStore(defaults: defaults, storageKey: "c")
        let mutation = PendingMutation(kind: .delete, messageIDs: ["INBOX:404"])
        try await queue.enqueue(mutation)
        try await conflictStore.append([
            MutationConflict(
                mutation: mutation,
                reason: .targetMissing,
                message: "The item no longer exists."
            ),
        ])
        let localIndex = LocalSearchIndexRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            localSearchIndex: localIndex,
            draftStagingStore: draftStore,
            offlineMutationQueue: queue,
            offlineMutationConflictStore: conflictStore
        )
        try await backend.connect()
        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))

        try await repair.resetLocalCacheAndIndex(for: Self.sourceID)

        #expect(await draftStore.draft(accountID: Self.account.id, draftID: "local-draft") == nil)
        #expect(await draftStore.attachment(accountID: Self.account.id, attachmentID: "attachment-1") == nil)
        #expect(try await queue.pending().isEmpty)
        #expect(try await conflictStore.conflicts().isEmpty)
        #expect(await localIndex.clearedAccounts == [Self.account.id])
    }

    @Test("sync health reports IMAP source cache bytes")
    func syncHealthReportsIMAPSourceCacheBytes() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevIMAPMessageSourceCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let sourceCache = FileIMAPMessageSourceCache(rootDirectory: rootDirectory)
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
            sourceCache: sourceCache
        )
        try await backend.connect()

        let reporter = try #require(backend.extensionService(SyncHealthReporting.self))
        var health = await reporter.syncHealth(for: Self.sourceID)
        for _ in 0 ..< 50 where health.cacheSizeBytes == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
            health = await reporter.syncHealth(for: Self.sourceID)
        }

        #expect(health.cacheSizeBytes > 0)
    }

    @Test("sync health reports indexing while search index rebuild is in flight")
    func syncHealthReportsIndexingWhileSearchIndexRebuildIsInFlight() async throws {
        let gate = AsyncGate()
        let localIndex = LocalSearchIndexRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in
                await gate.enterAndWait()
                return [
                    IMAPFolderListing(
                        path: "INBOX",
                        displayName: "Inbox",
                        delimiter: "/",
                        flags: [],
                        role: .inbox
                    ),
                ]
            },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(messages: [])
            },
            localSearchIndex: localIndex
        )
        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        let rebuild = Task {
            try await repair.rebuildSearchIndex(for: Self.sourceID)
        }
        try await gate.waitUntilEntered()

        let health = await backend.syncHealth(for: Self.sourceID)

        #expect(health.state == .indexing)
        #expect(health.indexStatus == .rebuilding(progress: nil))
        await gate.release()
        try await rebuild.value
    }

    @Test("rebuild search index rejects overlapping download all mail runs")
    func rebuildSearchIndexRejectsOverlappingDownloadAllMailRuns() async throws {
        let gate = AsyncGate()
        let localIndex = LocalSearchIndexRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in
                await gate.enterAndWait()
                return [
                    IMAPFolderListing(
                        path: "INBOX",
                        displayName: "Inbox",
                        delimiter: "/",
                        flags: [],
                        role: .inbox
                    ),
                ]
            },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(messages: [])
            },
            localSearchIndex: localIndex
        )
        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        let rebuild = Task {
            try await repair.rebuildSearchIndex(for: Self.sourceID)
        }
        try await gate.waitUntilEntered()

        await #expect(throws: MailBackendError.self) {
            try await repair.rebuildSearchIndex(for: Self.sourceID)
        }
        let inFlightHealth = await backend.syncHealth(for: Self.sourceID)

        #expect(inFlightHealth.state == .indexing)
        #expect(inFlightHealth.indexStatus == .rebuilding(progress: nil))
        await gate.release()
        try await rebuild.value

        let completedHealth = await backend.syncHealth(for: Self.sourceID)
        #expect(completedHealth.indexStatus == .ready(messageCount: 0))
    }

    @Test("reset local cache is rejected while search index rebuild is in flight")
    func resetLocalCacheIsRejectedWhileSearchIndexRebuildIsInFlight() async throws {
        let gate = AsyncGate()
        let localIndex = LocalSearchIndexRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in
                await gate.enterAndWait()
                return [
                    IMAPFolderListing(
                        path: "INBOX",
                        displayName: "Inbox",
                        delimiter: "/",
                        flags: [],
                        role: .inbox
                    ),
                ]
            },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(messages: [])
            },
            localSearchIndex: localIndex
        )
        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        let rebuild = Task {
            try await repair.rebuildSearchIndex(for: Self.sourceID)
        }
        try await gate.waitUntilEntered()

        await #expect(throws: MailBackendError.self) {
            try await repair.resetLocalCacheAndIndex(for: Self.sourceID)
        }
        let inFlightHealth = await backend.syncHealth(for: Self.sourceID)

        #expect(inFlightHealth.state == .indexing)
        #expect(inFlightHealth.indexStatus == .rebuilding(progress: nil))
        #expect(await localIndex.clearedAccounts.isEmpty)
        await gate.release()
        try await rebuild.value
    }

    @Test("search index rebuild is rejected while reset local cache is in flight")
    func searchIndexRebuildIsRejectedWhileResetLocalCacheIsInFlight() async throws {
        let gate = AsyncGate()
        let localIndex = LocalSearchIndexRecorder()
        await localIndex.setClearAccountGate(gate)
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in
                [
                    IMAPFolderListing(
                        path: "INBOX",
                        displayName: "Inbox",
                        delimiter: "/",
                        flags: [],
                        role: .inbox
                    ),
                ]
            },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(messages: [])
            },
            localSearchIndex: localIndex
        )
        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        let reset = Task {
            try await repair.resetLocalCacheAndIndex(for: Self.sourceID)
        }
        try await gate.waitUntilEntered()

        await #expect(throws: MailBackendError.self) {
            try await repair.rebuildSearchIndex(for: Self.sourceID)
        }

        await gate.release()
        try await reset.value
        let health = await backend.syncHealth(for: Self.sourceID)

        #expect(await localIndex.clearedAccounts == [Self.account.id])
        #expect(health.indexStatus == .notBuilt)
    }

    @Test("rebuild search index requires local search index storage")
    func rebuildSearchIndexRequiresLocalSearchIndexStorage() async throws {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(messages: [])
            }
        )

        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        await #expect(throws: MailBackendError.self) {
            try await repair.rebuildSearchIndex(for: Self.sourceID)
        }
        let health = await backend.syncHealth(for: Self.sourceID)

        if case .failed(let description) = health.indexStatus {
            #expect(description.contains("Local search index storage is unavailable."))
        } else {
            Issue.record("Expected failed index status, got \(health.indexStatus).")
        }
        #expect(health.lastErrorDescription == "Local search index storage is unavailable.")
    }

    @Test("rebuild search index fails when storage metrics prove messages were not persisted")
    func rebuildSearchIndexFailsWhenStorageMetricsProveMessagesWereNotPersisted() async throws {
        let localIndex = LocalSearchIndexRecorder()
        await localIndex.setMetrics(LocalSearchIndexMetrics(
            databaseBytes: 1024,
            indexedHeaderCount: 0,
            cachedBodyCount: 0,
            searchDocumentCount: 0,
            syncedFolderCount: 1
        ))
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in
                [
                    IMAPFolderListing(
                        path: "INBOX",
                        displayName: "Inbox",
                        delimiter: "/",
                        flags: [],
                        role: .inbox
                    ),
                ]
            },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(messages: [
                    Self.messageListing(uid: 44, subject: "Unpersisted")
                ])
            },
            localSearchIndex: localIndex
        )

        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        await #expect(throws: MailBackendError.self) {
            try await repair.rebuildSearchIndex(for: Self.sourceID)
        }
        let health = await backend.syncHealth(for: Self.sourceID)

        if case .failed(let description) = health.indexStatus {
            #expect(description.contains("Local search index rebuild did not persist all indexed messages."))
        } else {
            Issue.record("Expected failed index status, got \(health.indexStatus).")
        }
        #expect(health.lastErrorDescription == "Local search index rebuild did not persist all indexed messages.")
    }

    @Test("rebuild search index fails when cached body metrics prove bodies were not persisted")
    func rebuildSearchIndexFailsWhenCachedBodyMetricsProveBodiesWereNotPersisted() async throws {
        let localIndex = LocalSearchIndexRecorder()
        await localIndex.setMetrics(LocalSearchIndexMetrics(
            databaseBytes: 1024,
            indexedHeaderCount: 1,
            cachedBodyCount: 0,
            searchDocumentCount: 1,
            syncedFolderCount: 1
        ))
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in
                [
                    IMAPFolderListing(
                        path: "INBOX",
                        displayName: "Inbox",
                        delimiter: "/",
                        flags: [],
                        role: .inbox
                    ),
                ]
            },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(messages: [
                    Self.messageListing(uid: 44, subject: "Body persistence check")
                ])
            },
            fetchMessageSource: { _, _, folderID, uid in
                IMAPMessageSource(
                    uid: uid,
                    rawMessage: "Subject: \(folderID) \(uid)\n\nCached body."
                )
            },
            localSearchIndex: localIndex
        )

        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        await #expect(throws: MailBackendError.self) {
            try await repair.rebuildSearchIndex(for: Self.sourceID)
        }
        let health = await backend.syncHealth(for: Self.sourceID)

        #expect(await localIndex.storedRawMessageIDs == ["INBOX:44"])
        if case .failed(let description) = health.indexStatus {
            #expect(description.contains("Local search index rebuild did not persist all cached message bodies."))
        } else {
            Issue.record("Expected failed index status, got \(health.indexStatus).")
        }
        #expect(health.lastErrorDescription == "Local search index rebuild did not persist all cached message bodies.")
    }

    @Test("rebuild search index validates the specific cached body IDs")
    func rebuildSearchIndexValidatesTheSpecificCachedBodyIDs() async throws {
        let localIndex = LocalSearchIndexRecorder()
        await localIndex.setMetrics(LocalSearchIndexMetrics(
            databaseBytes: 1024,
            indexedHeaderCount: 1,
            cachedBodyCount: 1,
            searchDocumentCount: 1,
            syncedFolderCount: 1
        ))
        await localIndex.setPersistsStoredRawMessages(false)
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in
                [
                    IMAPFolderListing(
                        path: "INBOX",
                        displayName: "Inbox",
                        delimiter: "/",
                        flags: [],
                        role: .inbox
                    ),
                ]
            },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(messages: [
                    Self.messageListing(uid: 44, subject: "Specific body persistence check")
                ])
            },
            fetchMessageSource: { _, _, folderID, uid in
                IMAPMessageSource(
                    uid: uid,
                    rawMessage: "Subject: \(folderID) \(uid)\n\nCached body."
                )
            },
            localSearchIndex: localIndex
        )

        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        await #expect(throws: MailBackendError.self) {
            try await repair.rebuildSearchIndex(for: Self.sourceID)
        }
        let health = await backend.syncHealth(for: Self.sourceID)

        #expect(await localIndex.storedRawMessageIDs == ["INBOX:44"])
        #expect(await localIndex.cachedRawMessageRequests.contains("INBOX:44"))
        if case .failed(let description) = health.indexStatus {
            #expect(description.contains("Local search index rebuild did not persist all cached message bodies."))
        } else {
            Issue.record("Expected failed index status, got \(health.indexStatus).")
        }
        #expect(health.lastErrorDescription == "Local search index rebuild did not persist all cached message bodies.")
    }

    @Test("rebuild search index fails when stored messages are not searchable")
    func rebuildSearchIndexFailsWhenStoredMessagesAreNotSearchable() async throws {
        let localIndex = LocalSearchIndexRecorder()
        await localIndex.setMetrics(LocalSearchIndexMetrics(
            databaseBytes: 1024,
            indexedHeaderCount: 1,
            cachedBodyCount: 0,
            searchDocumentCount: 1,
            syncedFolderCount: 1
        ))
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in
                [
                    IMAPFolderListing(
                        path: "INBOX",
                        displayName: "Inbox",
                        delimiter: "/",
                        flags: [],
                        role: .inbox
                    ),
                ]
            },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(messages: [
                    Self.messageListing(uid: 44, subject: "Unsearchable rebuild row")
                ])
            },
            localSearchIndex: localIndex
        )

        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        await #expect(throws: MailBackendError.self) {
            try await repair.rebuildSearchIndex(for: Self.sourceID)
        }
        let health = await backend.syncHealth(for: Self.sourceID)

        #expect(await localIndex.searchRequests.map(\.query.subject) == ["Unsearchable rebuild row"])
        if case .failed(let description) = health.indexStatus {
            #expect(description.contains("Local search index rebuild did not make indexed messages searchable."))
        } else {
            Issue.record("Expected failed index status, got \(health.indexStatus).")
        }
        #expect(health.lastErrorDescription == "Local search index rebuild did not make indexed messages searchable.")
    }

    @Test("rebuild search index validates through recipient when subject and sender are blank")
    func rebuildSearchIndexValidatesThroughRecipientWhenSubjectAndSenderAreBlank() async throws {
        let localIndex = LocalSearchIndexRecorder()
        await localIndex.setMetrics(LocalSearchIndexMetrics(
            databaseBytes: 1024,
            indexedHeaderCount: 1,
            cachedBodyCount: 0,
            searchDocumentCount: 1,
            syncedFolderCount: 1
        ))
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in
                [
                    IMAPFolderListing(
                        path: "INBOX",
                        displayName: "Inbox",
                        delimiter: "/",
                        flags: [],
                        role: .inbox
                    ),
                ]
            },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(messages: [
                    IMAPMessageListing(
                        uid: 44,
                        messageID: "<blank-searchable-fields@example.org>",
                        subject: "   ",
                        from: Correspondent(email: "   "),
                        to: [Correspondent(email: "recipient@example.org")],
                        cc: [],
                        bcc: [],
                        date: Date(timeIntervalSince1970: 44),
                        isRead: false,
                        isFlagged: false,
                        isAnswered: false
                    ),
                ])
            },
            localSearchIndex: localIndex
        )

        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        await #expect(throws: MailBackendError.self) {
            try await repair.rebuildSearchIndex(for: Self.sourceID)
        }

        #expect(await localIndex.searchRequests.map(\.query.to) == ["recipient@example.org"])
    }

    @Test("sync health reports folder and message progress during search index rebuild")
    func syncHealthReportsFolderAndMessageProgressDuringSearchIndexRebuild() async throws {
        let gate = AsyncGate()
        let localIndex = LocalSearchIndexRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in
                [
                    IMAPFolderListing(
                        path: "INBOX",
                        displayName: "Inbox",
                        delimiter: "/",
                        flags: [],
                        role: .inbox
                    ),
                    IMAPFolderListing(
                        path: "Archive",
                        displayName: "Archive",
                        delimiter: "/",
                        flags: ["archive"],
                        role: .archive
                    ),
                ]
            },
            listMessages: { _, _, folderID, _, _ in
                if folderID == "Archive" {
                    await gate.enterAndWait()
                }
                return IMAPMessageListingPage(messages: [
                    Self.messageListing(uid: folderID == "INBOX" ? 44 : 7, subject: folderID)
                ])
            },
            localSearchIndex: localIndex
        )
        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        let rebuild = Task {
            try await repair.rebuildSearchIndex(for: Self.sourceID)
        }
        try await gate.waitUntilEntered()

        let inFlightHealth = await backend.syncHealth(for: Self.sourceID)

        #expect(inFlightHealth.state == .indexing)
        #expect(inFlightHealth.indexStatus == .rebuilding(progress: 0.5))
        #expect(inFlightHealth.searchIndexProgress == SearchIndexProgressSnapshot(
            completedFolderCount: 1,
            totalFolderCount: 2,
            indexedMessageCount: 1
        ))
        await gate.release()
        try await rebuild.value

        let completedHealth = await backend.syncHealth(for: Self.sourceID)
        #expect(completedHealth.indexStatus == .ready(messageCount: 2))
        #expect(completedHealth.searchIndexProgress == nil)
    }

    @Test("sync health reports stale IMAP mailbox source")
    func syncHealthReportsStaleIMAPMailboxSource() async throws {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] }
        )
        try await backend.connect()

        let staleSourceID = MailSourceID(
            accountID: Self.account.id,
            mailboxID: "stale-mailbox"
        )
        let reporter = try #require(backend.extensionService(SyncHealthReporting.self))
        let health = await reporter.syncHealth(for: staleSourceID)

        #expect(health.sourceID == staleSourceID)
        #expect(health.state == .providerError)
        #expect(health.lastErrorDescription?.contains("stale-mailbox") == true)
    }

    @Test("sync repair rejects stale IMAP mailbox source")
    func syncRepairRejectsStaleIMAPMailboxSource() async throws {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] }
        )
        try await backend.connect()

        let staleSourceID = MailSourceID(
            accountID: Self.account.id,
            mailboxID: "stale-mailbox"
        )
        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        let refresher = try #require(backend.extensionService(MailboxBackgroundRefreshing.self))

        await expectNotFound("stale-mailbox") {
            try await repair.retrySync(for: staleSourceID)
        }
        await expectNotFound("stale-mailbox") {
            try await refresher.refreshMailbox(for: staleSourceID)
        }
        await expectNotFound("stale-mailbox") {
            try await repair.rebuildSearchIndex(for: staleSourceID)
        }
        await expectNotFound("stale-mailbox") {
            try await repair.resetLocalCacheAndIndex(for: staleSourceID)
        }
        await expectNotFound("stale-mailbox") {
            try await repair.clearSyncConflicts(for: staleSourceID)
        }
    }

    @Test("retry sync replays pending IMAP mutations")
    func retrySyncReplaysPendingIMAPMutations() async throws {
        let queue = try Self.makeMutationQueue()
        try await queue.enqueue(PendingMutation(
            kind: .move(folderID: "Archive"),
            messageIDs: ["INBOX:43"]
        ))
        let folderRecorder = FolderListingRecorder(listings: [
            IMAPFolderListing(
                path: "INBOX",
                displayName: "Inbox",
                delimiter: "/",
                flags: [],
                role: .inbox
            ),
        ])
        let moveRecorder = MessageMoveRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { configuration, credential in
                try await folderRecorder.listFolders(
                    configuration: configuration,
                    credential: credential
                )
            },
            moveMessages: { configuration, credential, sourceFolderID, uids, destinationFolderID in
                try await moveRecorder.moveMessages(
                    configuration: configuration,
                    credential: credential,
                    sourceFolderID: sourceFolderID,
                    uids: uids,
                    destinationFolderID: destinationFolderID
                )
            },
            offlineMutationQueue: queue
        )

        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        try await repair.retrySync(for: Self.sourceID)
        let health = await backend.extensionService(SyncHealthReporting.self)?
            .syncHealth(for: Self.sourceID)

        #expect(await folderRecorder.callCount == 1)
        #expect(await moveRecorder.calls == [
            MessageMoveRecorder.Call(
                sourceFolderID: "INBOX",
                uids: [43],
                destinationFolderID: "Archive"
            ),
        ])
        #expect(try await queue.pending().isEmpty)
        #expect(health?.state == .healthy)
        #expect(health?.pendingMutationCount == 0)
    }

    @Test("offline IMAP mutation replay refreshes expired XOAUTH2 once")
    func offlineMutationReplayRefreshesExpiredOAuthCredential() async throws {
        let queue = try Self.makeMutationQueue()
        try await queue.enqueue(PendingMutation(
            kind: .move(folderID: "Archive"),
            messageIDs: ["INBOX:43"]
        ))
        let expiredCredential = MailAccountCredential(
            incomingUsername: Self.account.emailAddress,
            outgoingUsername: Self.account.emailAddress,
            secret: "expired-access-token",
            authentication: .xoauth2
        )
        let refreshedCredential = MailAccountCredential(
            incomingUsername: Self.account.emailAddress,
            outgoingUsername: Self.account.emailAddress,
            secret: "fresh-access-token",
            authentication: .xoauth2
        )
        let recorder = OAuthSendCredentialRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: expiredCredential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            moveMessages: { _, credential, sourceFolderID, uids, destinationFolderID in
                await recorder.record(credential)
                #expect(sourceFolderID == "INBOX")
                #expect(uids == [43])
                #expect(destinationFolderID == "Archive")
                if credential == expiredCredential {
                    throw IMAPClientError.authenticationFailed("expired token")
                }
            },
            refreshOAuthCredential: { _, _, credential in
                await recorder.recordRefresh()
                #expect(credential == expiredCredential)
                return refreshedCredential
            },
            offlineMutationQueue: queue
        )

        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        try await repair.retrySync(for: Self.sourceID)

        #expect(try await queue.pending().isEmpty)
        #expect(await recorder.credentials == [expiredCredential, refreshedCredential])
        #expect(await recorder.refreshCount == 1)
    }

    @Test("foreground IMAP body read refreshes an expired XOAUTH2 credential once")
    func foregroundIMAPBodyReadRefreshesExpiredOAuthCredential() async throws {
        let expiredCredential = MailAccountCredential(
            incomingUsername: Self.account.emailAddress,
            outgoingUsername: Self.account.emailAddress,
            secret: "expired-access-token",
            authentication: .xoauth2
        )
        let refreshedCredential = MailAccountCredential(
            incomingUsername: Self.account.emailAddress,
            outgoingUsername: Self.account.emailAddress,
            secret: "fresh-access-token",
            authentication: .xoauth2
        )
        let recorder = OAuthSendCredentialRecorder()
        let expectedBody = MessageBody(
            messageID: "INBOX:43",
            plainText: "Fresh body"
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: expiredCredential,
            listFolders: { _, _ in [] },
            fetchMessageBody: { _, credential, folderID, uid in
                await recorder.record(credential)
                #expect(folderID == "INBOX")
                #expect(uid == 43)
                if credential == expiredCredential {
                    throw IMAPClientError.authenticationFailed("expired token")
                }
                return expectedBody
            },
            refreshOAuthCredential: { _, _, credential in
                await recorder.recordRefresh()
                #expect(credential == expiredCredential)
                return refreshedCredential
            }
        )

        try await backend.connect()
        let body = try await backend.body(for: "INBOX:43")

        #expect(body == expectedBody)
        #expect(await recorder.credentials == [expiredCredential, refreshedCredential])
        #expect(await recorder.refreshCount == 1)
    }

    @Test("raw IMAP source read refreshes an expired XOAUTH2 credential once")
    func rawIMAPSourceReadRefreshesExpiredOAuthCredential() async throws {
        let expiredCredential = MailAccountCredential(
            incomingUsername: Self.account.emailAddress,
            outgoingUsername: Self.account.emailAddress,
            secret: "expired-access-token",
            authentication: .xoauth2
        )
        let refreshedCredential = MailAccountCredential(
            incomingUsername: Self.account.emailAddress,
            outgoingUsername: Self.account.emailAddress,
            secret: "fresh-access-token",
            authentication: .xoauth2
        )
        let recorder = OAuthSendCredentialRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: expiredCredential,
            listFolders: { _, _ in [] },
            fetchMessageSource: { _, credential, folderID, uid in
                await recorder.record(credential)
                #expect(folderID == "INBOX")
                #expect(uid == 43)
                if credential == expiredCredential {
                    throw IMAPClientError.authenticationFailed("expired token")
                }
                return IMAPMessageSource(
                    uid: uid,
                    rawMessage: "Subject: OAuth source\n\nFresh source"
                )
            },
            refreshOAuthCredential: { _, _, credential in
                await recorder.recordRefresh()
                #expect(credential == expiredCredential)
                return refreshedCredential
            }
        )

        try await backend.connect()
        #expect(try await backend.rawSource(for: "INBOX:43") == "Subject: OAuth source\n\nFresh source")
        #expect(await recorder.credentials == [expiredCredential, refreshedCredential])
        #expect(await recorder.refreshCount == 1)
    }

    @Test("IMAP part attachment read refreshes an expired XOAUTH2 credential once")
    func imapPartAttachmentReadRefreshesExpiredOAuthCredential() async throws {
        let expiredCredential = MailAccountCredential(
            incomingUsername: Self.account.emailAddress,
            outgoingUsername: Self.account.emailAddress,
            secret: "expired-access-token",
            authentication: .xoauth2
        )
        let refreshedCredential = MailAccountCredential(
            incomingUsername: Self.account.emailAddress,
            outgoingUsername: Self.account.emailAddress,
            secret: "fresh-access-token",
            authentication: .xoauth2
        )
        let recorder = OAuthSendCredentialRecorder()
        let part = IMAPMessagePartReference(
            messageID: "INBOX:43",
            section: "2",
            transferEncoding: "base64"
        )
        let attachment = Attachment(
            id: "INBOX:43:attachment:1",
            name: "receipt.pdf",
            mimeType: "application/pdf",
            sizeBytes: 5,
            resource: part.resource
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: expiredCredential,
            listFolders: { _, _ in [] },
            fetchMessagePart: { _, credential, folderID, uid, section, transferEncoding in
                await recorder.record(credential)
                #expect(folderID == "INBOX")
                #expect(uid == 43)
                #expect(section == "2")
                #expect(transferEncoding == "base64")
                if credential == expiredCredential {
                    throw IMAPClientError.authenticationFailed("expired token")
                }
                return Data("Fresh part".utf8)
            },
            refreshOAuthCredential: { _, _, credential in
                await recorder.recordRefresh()
                #expect(credential == expiredCredential)
                return refreshedCredential
            }
        )

        try await backend.connect()
        #expect(try await backend.downloadAttachment(attachment) == Data("Fresh part".utf8))
        #expect(await recorder.credentials == [expiredCredential, refreshedCredential])
        #expect(await recorder.refreshCount == 1)
    }

    @Test("IMAP message listing refreshes an expired XOAUTH2 credential once")
    func imapMessageListingRefreshesExpiredOAuthCredential() async throws {
        let expiredCredential = MailAccountCredential(
            incomingUsername: Self.account.emailAddress,
            outgoingUsername: Self.account.emailAddress,
            secret: "expired-access-token",
            authentication: .xoauth2
        )
        let refreshedCredential = MailAccountCredential(
            incomingUsername: Self.account.emailAddress,
            outgoingUsername: Self.account.emailAddress,
            secret: "fresh-access-token",
            authentication: .xoauth2
        )
        let recorder = OAuthSendCredentialRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: expiredCredential,
            listFolders: { _, _ in [] },
            listMessages: { _, credential, folderID, pageToken, limit in
                await recorder.record(credential)
                #expect(folderID == "INBOX")
                #expect(pageToken == nil)
                #expect(limit == 50)
                if credential == expiredCredential {
                    throw IMAPClientError.authenticationFailed("expired token")
                }
                return IMAPMessageListingPage(
                    messages: [Self.messageListing(uid: 43, subject: "OAuth listing")],
                    nextPageToken: nil
                )
            },
            refreshOAuthCredential: { _, _, credential in
                await recorder.recordRefresh()
                #expect(credential == expiredCredential)
                return refreshedCredential
            }
        )

        try await backend.connect()
        let result = try await backend.messages(
            in: Folder(id: "INBOX", name: "Inbox", role: .inbox),
            pageToken: nil
        )

        #expect(result.headers.map(\.subject) == ["OAuth listing"])
        #expect(await recorder.credentials == [expiredCredential, refreshedCredential])
        #expect(await recorder.refreshCount == 1)
    }

    @Test("IMAP server search refreshes an expired XOAUTH2 credential once")
    func imapServerSearchRefreshesExpiredOAuthCredential() async throws {
        let expiredCredential = MailAccountCredential(
            incomingUsername: Self.account.emailAddress,
            outgoingUsername: Self.account.emailAddress,
            secret: "expired-access-token",
            authentication: .xoauth2
        )
        let refreshedCredential = MailAccountCredential(
            incomingUsername: Self.account.emailAddress,
            outgoingUsername: Self.account.emailAddress,
            secret: "fresh-access-token",
            authentication: .xoauth2
        )
        let recorder = OAuthSendCredentialRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: expiredCredential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            searchMessages: { _, credential, folderID, query, limit in
                await recorder.record(credential)
                #expect(folderID == "INBOX")
                #expect(query.text == "OAuth")
                #expect(limit == 200)
                if credential == expiredCredential {
                    throw IMAPClientError.authenticationFailed("expired token")
                }
                return [Self.messageListing(uid: 43, subject: "OAuth search")]
            },
            refreshOAuthCredential: { _, _, credential in
                await recorder.recordRefresh()
                #expect(credential == expiredCredential)
                return refreshedCredential
            }
        )

        try await backend.connect()
        let results = try await backend.search(SearchQuery(text: "OAuth", execution: .serverOnly))

        #expect(results.map(\.subject) == ["OAuth search"])
        #expect(await recorder.credentials == [expiredCredential, refreshedCredential])
        #expect(await recorder.refreshCount == 1)
    }

    @Test("retry sync refreshes connected IMAP folder first pages")
    func retrySyncRefreshesConnectedIMAPFolderFirstPages() async throws {
        let folderRecorder = FolderListingRecorder(listings: [
            IMAPFolderListing(
                path: "INBOX",
                displayName: "Inbox",
                delimiter: "/",
                flags: [],
                role: .inbox
            ),
            IMAPFolderListing(
                path: "Archive",
                displayName: "Archive",
                delimiter: "/",
                flags: ["archive"],
                role: .archive
            ),
        ])
        let messageRecorder = MessageListingRecorder(sequence: [
            IMAPMessageListingPage(
                messages: [Self.messageListing(uid: 43, subject: "Inbox refresh")],
                nextPageToken: nil
            ),
            IMAPMessageListingPage(
                messages: [Self.messageListing(uid: 7, subject: "Archive refresh")],
                nextPageToken: nil
            ),
        ])
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { configuration, credential in
                try await folderRecorder.listFolders(
                    configuration: configuration,
                    credential: credential
                )
            },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await messageRecorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            headerCache: headerCache
        )

        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        let stream = backend.subscribeToChanges()
        try await repair.retrySync(for: Self.sourceID)
        let inboxRefresh = try await nextIMAPEventSkippingProgress(from: stream)
        let archiveRefresh = try await nextIMAPEventSkippingProgress(from: stream)

        let inboxSnapshot = await headerCache.snapshot(accountID: Self.account.id, folderID: "INBOX")
        let archiveSnapshot = await headerCache.snapshot(accountID: Self.account.id, folderID: "Archive")

        #expect(await messageRecorder.requestedFolderIDs == ["INBOX", "Archive"])
        #expect(await messageRecorder.requestedPageTokens == [nil, nil])
        #expect(inboxRefresh == .folderRefreshed(folderID: "INBOX"))
        #expect(archiveRefresh == .folderRefreshed(folderID: "Archive"))
        #expect(inboxSnapshot?.headers.map(\.id) == ["INBOX:43"])
        #expect(archiveSnapshot?.headers.map(\.id) == ["Archive:7"])
    }

    @Test("rebuild search index walks every IMAP folder page and caches bodies")
    func rebuildSearchIndexWalksEveryIMAPFolderPageAndCachesBodies() async throws {
        let folderRecorder = FolderListingRecorder(listings: [
            IMAPFolderListing(
                path: "INBOX",
                displayName: "Inbox",
                delimiter: "/",
                flags: [],
                role: .inbox
            ),
            IMAPFolderListing(
                path: "Archive",
                displayName: "Archive",
                delimiter: "/",
                flags: ["archive"],
                role: .archive
            ),
        ])
        let messageRecorder = MessageListingRecorder(sequence: [
            IMAPMessageListingPage(
                messages: [Self.messageListing(uid: 44, subject: "Inbox newest")],
                nextPageToken: "before:44"
            ),
            IMAPMessageListingPage(
                messages: [Self.messageListing(uid: 43, subject: "Inbox older")],
                nextPageToken: nil
            ),
            IMAPMessageListingPage(
                messages: [Self.messageListing(uid: 7, subject: "Archive")],
                nextPageToken: nil
            ),
        ])
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let localIndex = LocalSearchIndexRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { configuration, credential in
                try await folderRecorder.listFolders(
                    configuration: configuration,
                    credential: credential
                )
            },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await messageRecorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            fetchMessageSource: { _, _, folderID, uid in
                IMAPMessageSource(
                    uid: uid,
                    rawMessage: "Subject: \(folderID) \(uid)\n\nCached body."
                )
            },
            headerCache: headerCache,
            sourceCache: sourceCache,
            localSearchIndex: localIndex
        )

        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        let eventStream = backend.subscribeToChanges()
        try await repair.rebuildSearchIndex(for: Self.sourceID)
        let health = await backend.syncHealth(for: Self.sourceID)

        let inboxSnapshot = await headerCache.snapshot(accountID: Self.account.id, folderID: "INBOX")
        let archiveSnapshot = await headerCache.snapshot(accountID: Self.account.id, folderID: "Archive")
        let inboxNewestSource = await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:44")
        let inboxOlderSource = await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:43")
        let archiveSource = await sourceCache.source(accountID: Self.account.id, messageID: "Archive:7")

        #expect(await messageRecorder.requestedFolderIDs == ["INBOX", "INBOX", "Archive"])
        #expect(await messageRecorder.requestedPageTokens == [nil, "before:44", nil])
        #expect(inboxSnapshot?.headers.map(\.id) == ["INBOX:44", "INBOX:43"])
        #expect(archiveSnapshot?.headers.map(\.id) == ["Archive:7"])
        #expect(inboxNewestSource?.rawMessage.contains("INBOX 44") == true)
        #expect(inboxOlderSource?.rawMessage.contains("INBOX 43") == true)
        #expect(archiveSource?.rawMessage.contains("Archive 7") == true)
        #expect(await localIndex.storedHeaderBatches.map { $0.map(\.id) } == [
            ["INBOX:44"],
            ["INBOX:43"],
            ["Archive:7"],
        ])
        #expect(await localIndex.storedRawMessageIDs == [
            "INBOX:44",
            "INBOX:43",
            "Archive:7",
        ])
        var progressEvents: [String] = []
        while progressEvents.count < 3 {
            let event = try await nextIMAPEvent(from: eventStream)
            if case .syncProgress(let completed, let total) = event {
                progressEvents.append("\(completed)/\(total)")
            }
        }
        #expect(progressEvents == ["0/2", "1/2", "2/2"])
        #expect(health.indexStatus == .ready(messageCount: 3))
        #expect(health.state == .healthy)
        #expect(health.lastErrorDescription == nil)
    }

    @Test("rebuild search index keeps headers when body backfill fails")
    func rebuildSearchIndexKeepsHeadersWhenBodyBackfillFails() async throws {
        let folderRecorder = FolderListingRecorder(listings: [
            IMAPFolderListing(
                path: "INBOX",
                displayName: "Inbox",
                delimiter: "/",
                flags: [],
                role: .inbox
            ),
        ])
        let messageRecorder = MessageListingRecorder(sequence: [
            IMAPMessageListingPage(
                messages: [
                    Self.messageListing(uid: 44, subject: "Cached body"),
                    Self.messageListing(uid: 43, subject: "Missing body"),
                ],
                nextPageToken: nil
            ),
        ])
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let localIndex = LocalSearchIndexRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { configuration, credential in
                try await folderRecorder.listFolders(
                    configuration: configuration,
                    credential: credential
                )
            },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await messageRecorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            fetchMessageSource: { _, _, folderID, uid in
                if uid == 43 {
                    throw MailBackendError.notFound(id: "\(folderID):\(uid)")
                }
                return IMAPMessageSource(
                    uid: uid,
                    rawMessage: "Subject: \(folderID) \(uid)\n\nCached body."
                )
            },
            headerCache: headerCache,
            sourceCache: sourceCache,
            localSearchIndex: localIndex
        )

        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        try await repair.rebuildSearchIndex(for: Self.sourceID)
        let health = await backend.syncHealth(for: Self.sourceID)

        let inboxSnapshot = await headerCache.snapshot(accountID: Self.account.id, folderID: "INBOX")
        let cachedSource = await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:44")
        let missingSource = await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:43")

        #expect(inboxSnapshot?.headers.map(\.id) == ["INBOX:44", "INBOX:43"])
        #expect(cachedSource?.rawMessage.contains("INBOX 44") == true)
        #expect(missingSource == nil)
        #expect(health.indexStatus == .ready(messageCount: 2))
        #expect(health.state == .degraded)
        #expect(health.lastErrorDescription?.contains("1 message body") == true)
    }

    @Test("rebuild search index backfills duplicate paged messages once")
    func rebuildSearchIndexBackfillsDuplicatePagedMessagesOnce() async throws {
        let folderRecorder = FolderListingRecorder(listings: [
            IMAPFolderListing(
                path: "INBOX",
                displayName: "Inbox",
                delimiter: "/",
                flags: [],
                role: .inbox
            ),
        ])
        let messageRecorder = MessageListingRecorder(sequence: [
            IMAPMessageListingPage(
                messages: [Self.messageListing(uid: 44, subject: "Overlap")],
                nextPageToken: "before:44"
            ),
            IMAPMessageListingPage(
                messages: [Self.messageListing(uid: 44, subject: "Overlap duplicate")],
                nextPageToken: nil
            ),
        ])
        let localIndex = LocalSearchIndexRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { configuration, credential in
                try await folderRecorder.listFolders(
                    configuration: configuration,
                    credential: credential
                )
            },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await messageRecorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            fetchMessageSource: { _, _, folderID, uid in
                IMAPMessageSource(
                    uid: uid,
                    rawMessage: "Subject: \(folderID) \(uid)\n\nCached body."
                )
            },
            localSearchIndex: localIndex
        )
        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))

        try await repair.rebuildSearchIndex(for: Self.sourceID)
        let health = await backend.syncHealth(for: Self.sourceID)

        #expect(await messageRecorder.requestedPageTokens == [nil, "before:44"])
        #expect(await localIndex.storedHeaderBatches.map { $0.map(\.id) } == [
            ["INBOX:44"],
            ["INBOX:44"],
        ])
        #expect(await localIndex.storedRawMessageIDs == ["INBOX:44"])
        #expect(health.indexStatus == .ready(messageCount: 1))
        #expect(health.lastErrorDescription == nil)
    }

    @Test("rebuild search index preserves existing cache when reconnect fails")
    func rebuildSearchIndexPreservesExistingCacheWhenReconnectFails() async throws {
        let header = Self.retentionHeader(
            id: "INBOX:1",
            date: Date(timeIntervalSince1970: 1)
        )
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let localIndex = LocalSearchIndexRecorder()
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [header], nextPageToken: nil),
            accountID: Self.account.id,
            folderID: "INBOX"
        )
        await sourceCache.setSource(
            IMAPMessageSource(
                uid: 1,
                rawMessage: "Subject: cached\n\ncached body"
            ),
            accountID: Self.account.id,
            messageID: "INBOX:1"
        )
        await localIndex.setRawMessage(
            Data("Subject: indexed\r\n\r\nindexed body".utf8),
            for: "INBOX:1"
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in
                throw MailBackendError.notConnected
            },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(messages: [])
            },
            headerCache: headerCache,
            sourceCache: sourceCache,
            localSearchIndex: localIndex
        )

        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        await #expect(throws: MailBackendError.self) {
            try await repair.rebuildSearchIndex(for: Self.sourceID)
        }
        let health = await backend.syncHealth(for: Self.sourceID)
        let preservedHeaders = await headerCache.snapshot(
            accountID: Self.account.id,
            folderID: "INBOX"
        )?.headers
        let preservedSource = await sourceCache.source(
            accountID: Self.account.id,
            messageID: "INBOX:1"
        )
        let preservedIndexedSource = await localIndex.cachedRawMessage(
            for: "INBOX:1",
            account: Self.account
        )

        #expect(preservedHeaders?.map(\.id) == ["INBOX:1"])
        #expect(preservedSource?.rawMessage.contains("cached body") == true)
        #expect(preservedIndexedSource != nil)
        #expect(await localIndex.clearedAccounts.isEmpty)
        if case .failed(let description) = health.indexStatus {
            #expect(description.lowercased().contains("not connected"))
        } else {
            Issue.record("Expected failed index status, got \(health.indexStatus).")
        }
        #expect(health.state == .offline)
    }

    @Test("rebuild search index preserves existing cache when listing fails mid run")
    func rebuildSearchIndexPreservesExistingCacheWhenListingFailsMidRun() async throws {
        let archiveHeader = Self.retentionHeader(
            id: "Archive:1",
            date: Date(timeIntervalSince1970: 1)
        )
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let localIndex = LocalSearchIndexRecorder()
        await headerCache.setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: [archiveHeader], nextPageToken: nil),
            accountID: Self.account.id,
            folderID: "Archive"
        )
        await sourceCache.setSource(
            IMAPMessageSource(
                uid: 1,
                rawMessage: "Subject: old archive\n\nold cached archive body"
            ),
            accountID: Self.account.id,
            messageID: "Archive:1"
        )
        await localIndex.setRawMessage(
            Data("Subject: old indexed archive\r\n\r\nold indexed archive body".utf8),
            for: "Archive:1"
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in
                [
                    IMAPFolderListing(
                        path: "INBOX",
                        displayName: "Inbox",
                        delimiter: "/",
                        flags: [],
                        role: .inbox
                    ),
                    IMAPFolderListing(
                        path: "Archive",
                        displayName: "Archive",
                        delimiter: "/",
                        flags: ["archive"],
                        role: .archive
                    ),
                ]
            },
            listMessages: { _, _, folderID, _, _ in
                if folderID == "Archive" {
                    throw IMAPClientError.transport("Archive listing failed")
                }
                return IMAPMessageListingPage(messages: [
                    Self.messageListing(uid: 44, subject: "Fresh inbox")
                ])
            },
            headerCache: headerCache,
            sourceCache: sourceCache,
            localSearchIndex: localIndex
        )

        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        await #expect(throws: IMAPClientError.self) {
            try await repair.rebuildSearchIndex(for: Self.sourceID)
        }
        let preservedHeaders = await headerCache.snapshot(
            accountID: Self.account.id,
            folderID: "Archive"
        )?.headers
        let preservedSource = await sourceCache.source(
            accountID: Self.account.id,
            messageID: "Archive:1"
        )
        let preservedIndexedSource = await localIndex.cachedRawMessage(
            for: "Archive:1",
            account: Self.account
        )

        #expect(preservedHeaders?.map(\.id) == ["Archive:1"])
        #expect(preservedSource?.rawMessage.contains("old cached archive body") == true)
        #expect(preservedIndexedSource != nil)
        #expect(await localIndex.clearedAccounts.isEmpty)
    }

    @Test("background mailbox refresh updates connected IMAP folder first pages")
    func backgroundMailboxRefreshUpdatesConnectedIMAPFolderFirstPages() async throws {
        let folderRecorder = FolderListingRecorder(listings: [
            IMAPFolderListing(
                path: "INBOX",
                displayName: "Inbox",
                delimiter: "/",
                flags: [],
                role: .inbox
            ),
            IMAPFolderListing(
                path: "Archive",
                displayName: "Archive",
                delimiter: "/",
                flags: ["archive"],
                role: .archive
            ),
        ])
        let messageRecorder = MessageListingRecorder(sequence: [
            IMAPMessageListingPage(
                messages: [Self.messageListing(uid: 43, subject: "Inbox background")],
                nextPageToken: nil
            ),
            IMAPMessageListingPage(
                messages: [Self.messageListing(uid: 7, subject: "Archive background")],
                nextPageToken: nil
            ),
        ])
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { configuration, credential in
                try await folderRecorder.listFolders(
                    configuration: configuration,
                    credential: credential
                )
            },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await messageRecorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            headerCache: headerCache
        )

        let refresh = try #require(backend.extensionService(MailboxBackgroundRefreshing.self))
        let stream = backend.subscribeToChanges()
        try await refresh.refreshMailbox(for: Self.sourceID)
        let inboxRefresh = try await nextIMAPEventSkippingProgress(from: stream)
        let archiveRefresh = try await nextIMAPEventSkippingProgress(from: stream)

        let inboxSnapshot = await headerCache.snapshot(accountID: Self.account.id, folderID: "INBOX")
        let archiveSnapshot = await headerCache.snapshot(accountID: Self.account.id, folderID: "Archive")

        #expect(await messageRecorder.requestedFolderIDs == ["INBOX", "Archive"])
        #expect(await messageRecorder.requestedPageTokens == [nil, nil])
        #expect(inboxRefresh == .folderRefreshed(folderID: "INBOX"))
        #expect(archiveRefresh == .folderRefreshed(folderID: "Archive"))
        #expect(inboxSnapshot?.headers.map(\.id) == ["INBOX:43"])
        #expect(archiveSnapshot?.headers.map(\.id) == ["Archive:7"])
    }

    @Test("background mailbox refresh is bounded for large IMAP folder trees")
    func backgroundMailboxRefreshIsBoundedForLargeIMAPFolderTrees() async throws {
        let customListings = (1 ... 14).map { index in
            IMAPFolderListing(
                path: "Custom-\(index)",
                displayName: "Custom \(index)",
                delimiter: "/",
                flags: [],
                role: .custom
            )
        }
        let folderRecorder = FolderListingRecorder(listings: customListings + [
            IMAPFolderListing(
                path: "INBOX",
                displayName: "Inbox",
                delimiter: "/",
                flags: [],
                role: .inbox
            ),
        ])
        let messageRecorder = MessageListingRecorder(messages: [])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { configuration, credential in
                try await folderRecorder.listFolders(
                    configuration: configuration,
                    credential: credential
                )
            },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await messageRecorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            }
        )

        let refresh = try #require(backend.extensionService(MailboxBackgroundRefreshing.self))
        try await refresh.refreshMailbox(for: Self.sourceID)
        let requestedFolderIDs = await messageRecorder.requestedFolderIDs

        #expect(requestedFolderIDs.count == 12)
        #expect(requestedFolderIDs.first == "INBOX")
        #expect(!requestedFolderIDs.contains("Custom-14"))
    }

    @Test("background mailbox refresh prioritizes custom folders ahead of low-signal system folders")
    func backgroundMailboxRefreshPrioritizesCustomFoldersAheadOfLowSignalSystemFolders() async throws {
        let folderRecorder = FolderListingRecorder(listings: [
            IMAPFolderListing(path: "Spam", displayName: "Spam", delimiter: "/", flags: ["junk"], role: .spam),
            IMAPFolderListing(path: "Trash", displayName: "Trash", delimiter: "/", flags: ["trash"], role: .trash),
            IMAPFolderListing(path: "INBOX", displayName: "Inbox", delimiter: "/", flags: [], role: .inbox),
            IMAPFolderListing(path: "Projects", displayName: "Projects", delimiter: "/", flags: [], role: .custom),
            IMAPFolderListing(path: "Receipts", displayName: "Receipts", delimiter: "/", flags: [], role: .custom),
        ])
        let messageRecorder = MessageListingRecorder(messages: [])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { configuration, credential in
                try await folderRecorder.listFolders(
                    configuration: configuration,
                    credential: credential
                )
            },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await messageRecorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            }
        )
        try await backend.connect()

        let refresh = try #require(backend.extensionService(MailboxBackgroundRefreshing.self))
        try await refresh.refreshMailbox(for: Self.sourceID)
        let requestedFolderIDs = await messageRecorder.requestedFolderIDs

        #expect(Array(requestedFolderIDs.prefix(3)) == ["INBOX", "Projects", "Receipts"])
    }

    @Test("sync health reports IMAP background refresh summary")
    func syncHealthReportsIMAPBackgroundRefreshSummary() async throws {
        let customListings = (1 ... 14).map { index in
            IMAPFolderListing(
                path: "Custom-\(index)",
                displayName: "Custom \(index)",
                delimiter: "/",
                flags: [],
                role: .custom
            )
        }
        let folderRecorder = FolderListingRecorder(listings: customListings + [
            IMAPFolderListing(
                path: "INBOX",
                displayName: "Inbox",
                delimiter: "/",
                flags: [],
                role: .inbox
            ),
        ])
        let messageRecorder = MessageListingRecorder(messages: [])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { configuration, credential in
                try await folderRecorder.listFolders(
                    configuration: configuration,
                    credential: credential
                )
            },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await messageRecorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            }
        )
        try await backend.connect()

        let refresh = try #require(backend.extensionService(MailboxBackgroundRefreshing.self))
        try await refresh.refreshMailbox(for: Self.sourceID)
        let reporter = try #require(backend.extensionService(SyncHealthReporting.self))
        let health = await reporter.syncHealth(for: Self.sourceID)

        #expect(health.backgroundRefreshSnapshot?.refreshedFolderCount == 12)
        #expect(health.backgroundRefreshSnapshot?.deferredFolderCount == 3)
    }

    @Test("sync health records IMAP connection failures")
    func syncHealthRecordsIMAPConnectionFailures() async throws {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in
                throw IMAPClientError.transport("offline")
            }
        )

        do {
            try await backend.connect()
            Issue.record("Expected connect() to surface the IMAP transport failure.")
        } catch IMAPClientError.transport {
        } catch {
            Issue.record("Expected IMAPClientError.transport, got \(error).")
        }

        let reporter = try #require(backend.extensionService(SyncHealthReporting.self))
        let health = await reporter.syncHealth(for: Self.sourceID)

        #expect(health.state == .offline)
        #expect(health.lastSuccessfulSyncAt == nil)
        #expect(health.lastErrorDescription?.contains("offline") == true)
    }

    @Test("delete moves messages to trash and permanently deletes trash messages")
    func deleteMovesMessagesToTrashAndPermanentlyDeletesTrashMessages() async throws {
        let moveRecorder = MessageMoveRecorder()
        let deleteRecorder = MessagePermanentDeleteRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
                IMAPFolderListing(
                    path: "Trash",
                    displayName: "Trash",
                    delimiter: "/",
                    flags: ["trash"],
                    role: .trash
                ),
            ] },
            moveMessages: { configuration, credential, sourceFolderID, uids, destinationFolderID in
                try await moveRecorder.moveMessages(
                    configuration: configuration,
                    credential: credential,
                    sourceFolderID: sourceFolderID,
                    uids: uids,
                    destinationFolderID: destinationFolderID
                )
            },
            permanentlyDeleteMessages: { configuration, credential, folderID, uids in
                try await deleteRecorder.permanentlyDeleteMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uids: uids
                )
            }
        )
        try await backend.connect()

        try await backend.delete(messageIDs: ["INBOX:43", "INBOX:44", "Trash:5"])

        #expect(await moveRecorder.calls == [
            MessageMoveRecorder.Call(
                sourceFolderID: "INBOX",
                uids: [43, 44],
                destinationFolderID: "Trash"
            ),
        ])
        #expect(await deleteRecorder.calls == [
            MessagePermanentDeleteRecorder.Call(folderID: "Trash", uids: [5]),
        ])
    }

    @Test("delete emits removal events and prunes cached IMAP headers")
    func deleteEmitsRemovalEventsAndPrunesCachedIMAPHeaders() async throws {
        let moveRecorder = MessageMoveRecorder()
        let deleteRecorder = MessagePermanentDeleteRecorder()
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
                IMAPFolderListing(
                    path: "Trash",
                    displayName: "Trash",
                    delimiter: "/",
                    flags: ["trash"],
                    role: .trash
                ),
            ] },
            listMessages: { _, _, folderID, _, _ in
                if folderID == "Trash" {
                    return IMAPMessageListingPage(messages: [
                        Self.messageListing(uid: 5, subject: "Delete me"),
                    ])
                }
                return IMAPMessageListingPage(messages: [
                    Self.messageListing(uid: 43, subject: "Delete me"),
                ])
            },
            moveMessages: { configuration, credential, sourceFolderID, uids, destinationFolderID in
                try await moveRecorder.moveMessages(
                    configuration: configuration,
                    credential: credential,
                    sourceFolderID: sourceFolderID,
                    uids: uids,
                    destinationFolderID: destinationFolderID
                )
            },
            permanentlyDeleteMessages: { configuration, credential, folderID, uids in
                try await deleteRecorder.permanentlyDeleteMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uids: uids
                )
            },
            headerCache: headerCache
        )
        try await backend.connect()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let trash = Folder(id: "Trash", name: "Trash", role: .trash)
        _ = try await backend.messages(in: inbox, pageToken: nil)
        _ = try await backend.messages(in: trash, pageToken: nil)
        let stream = backend.subscribeToChanges()

        try await backend.delete(messageIDs: ["INBOX:43", "Trash:5"])

        let inboxRemoved = try await nextIMAPEvent(from: stream)
        let trashRefreshed = try await nextIMAPEvent(from: stream)
        let trashRemoved = try await nextIMAPEvent(from: stream)
        #expect(inboxRemoved == .messagesRemoved(folderID: "INBOX", messageIDs: ["INBOX:43"]))
        #expect(trashRefreshed == .folderRefreshed(folderID: "Trash"))
        #expect(trashRemoved == .messagesRemoved(folderID: "Trash", messageIDs: ["Trash:5"]))
        let cachedInboxHeaders = await headerCache.snapshot(accountID: Self.account.id, folderID: "INBOX")?.headers
        let cachedTrashHeaders = await headerCache.snapshot(accountID: Self.account.id, folderID: "Trash")?.headers
        #expect(cachedInboxHeaders?.isEmpty == true)
        #expect(cachedTrashHeaders?.isEmpty == true)
    }

    @Test("delete invalidates cached IMAP source for deleted messages")
    func deleteInvalidatesCachedIMAPSourceForDeletedMessages() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevIMAPMessageSourceCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let sourceCache = FileIMAPMessageSourceCache(rootDirectory: rootDirectory)
        await sourceCache.setSource(
            IMAPMessageSource(uid: 43, rawMessage: "Content-Type: text/plain\n\nCached body."),
            accountID: Self.account.id,
            messageID: "INBOX:43"
        )
        let moveRecorder = MessageMoveRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
                IMAPFolderListing(
                    path: "Trash",
                    displayName: "Trash",
                    delimiter: "/",
                    flags: ["trash"],
                    role: .trash
                ),
            ] },
            moveMessages: { configuration, credential, sourceFolderID, uids, destinationFolderID in
                try await moveRecorder.moveMessages(
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

        try await backend.delete(messageIDs: ["INBOX:43"])

        #expect(await sourceCache.source(accountID: Self.account.id, messageID: "INBOX:43") == nil)
        #expect(await moveRecorder.calls == [
            MessageMoveRecorder.Call(
                sourceFolderID: "INBOX",
                uids: [43],
                destinationFolderID: "Trash"
            ),
        ])
    }

    @Test("send builds MIME message and submits through SMTP operation")
    func sendBuildsMIMEMessageAndSubmitsThroughSMTPOperation() async throws {
        let recorder = MessageSendRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { configuration, credential, submission in
                try await recorder.sendMessage(
                    configuration: configuration,
                    credential: credential,
                    submission: submission
                )
                return SendResult(sentMessageID: "smtp-queued")
            }
        )
        try await backend.connect()

        let result = try await backend.send(draft: Draft(
            id: "draft-1",
            to: [Correspondent(name: "Bob", email: "bob@example.org")],
            cc: [Correspondent(email: "carol@example.org")],
            bcc: [Correspondent(email: "dave@example.org")],
            subject: "Hello",
            htmlBody: "<p>Hei</p>"
        ))

        let call = try #require(await recorder.calls.first)
        let message = String(data: call.submission.messageData, encoding: .utf8) ?? ""
        #expect(result == SendResult(sentMessageID: "smtp-queued"))
        #expect(call.submission.senderEmail == "person@example.org")
        #expect(call.submission.recipientEmails == [
            "bob@example.org",
            "carol@example.org",
            "dave@example.org",
        ])
        #expect(message.contains("Subject: Hello"))
        #expect(message.contains("To: Bob <bob@example.org>"))
        #expect(message.contains("Cc: carol@example.org"))
        #expect(!message.contains("Bcc:"))
    }

    @Test("XOAUTH2 send refreshes once after SMTP authentication rejection")
    func xoauth2SendRefreshesOnceAfterSMTPAuthenticationRejection() async throws {
        let account = BrevAccount(
            id: "imap-smtp:person@gmail.com",
            displayName: "Person",
            emailAddress: "person@gmail.com"
        )
        let configuration = IMAPAccountConfiguration(
            accountID: account.id,
            emailAddress: account.emailAddress,
            displayName: account.displayName,
            incoming: MailServerSettings(
                kind: .imap,
                host: "imap.gmail.com",
                port: 993,
                tlsMode: .implicit,
                authentication: .xoauth2
            ),
            outgoing: MailServerSettings(
                kind: .smtp,
                host: "smtp.gmail.com",
                port: 465,
                tlsMode: .implicit,
                authentication: .xoauth2
            ),
            credentialID: account.id
        )
        let expiredCredential = MailAccountCredential(
            incomingUsername: account.emailAddress,
            outgoingUsername: account.emailAddress,
            secret: "expired-access-token",
            authentication: .xoauth2
        )
        let refreshedCredential = MailAccountCredential(
            incomingUsername: account.emailAddress,
            outgoingUsername: account.emailAddress,
            secret: "fresh-access-token",
            authentication: .xoauth2
        )
        let recorder = OAuthSendCredentialRecorder()
        let backend = IMAPSMTPBackend(
            account: account,
            configuration: configuration,
            credential: expiredCredential,
            listFolders: { _, _ in [] },
            sendMessage: { _, credential, _ in
                await recorder.record(credential)
                if credential.secret == expiredCredential.secret {
                    throw SMTPClientError.authenticationFailed("535 expired token")
                }
                return SendResult(sentMessageID: "smtp-queued")
            },
            refreshOAuthCredential: { _, _, credential in
                await recorder.recordRefresh()
                #expect(credential == expiredCredential)
                return refreshedCredential
            }
        )
        try await backend.connect()

        let result = try await backend.send(draft: Draft(
            id: "gmail-draft-1",
            to: [Correspondent(email: "bob@example.org")],
            subject: "Hello",
            htmlBody: "<p>Hi</p>"
        ))

        #expect(result.sentMessageID == "smtp-queued")
        #expect(await recorder.credentials == [expiredCredential, refreshedCredential])
        #expect(await recorder.refreshCount == 1)
    }

    @Test("a draft whose send was already confirmed is not delivered again")
    func confirmedSendIsNotDeliveredTwice() async throws {
        let ledgerDefaults = try #require(UserDefaults(suiteName: "brev.test.ledger.\(UUID().uuidString)"))

        let recorder = MessageSendRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { configuration, credential, submission in
                try await recorder.sendMessage(
                    configuration: configuration,
                    credential: credential,
                    submission: submission
                )
                return SendResult(sentMessageID: "smtp-ok")
            },
            sentMessageLedger: SentMessageLedger(defaults: ledgerDefaults)
        )
        try await backend.connect()

        let draft = Draft(
            id: "dup-draft",
            to: [Correspondent(email: "bob@example.org")],
            subject: "Once",
            htmlBody: "<p>x</p>"
        )

        _ = try await backend.send(draft: draft)
        // A second delivery of the same draft (the entry wasn't cleared) must
        // not produce a duplicate SMTP submission.
        _ = try await backend.send(draft: draft)

        #expect(await recorder.calls.count == 1)
    }

    @Test("sent-message ledger records, matches, and caps its size")
    func sentMessageLedgerRecordsAndCaps() {
        let accountID = "ledger-\(UUID().uuidString)"
        defer { SentMessageLedger.purge(accountID: accountID) }
        let ledger = SentMessageLedger(maxEntries: 3)

        #expect(!ledger.contains(draftID: "a", accountID: accountID))
        ledger.record(draftID: "a", accountID: accountID)
        #expect(ledger.contains(draftID: "a", accountID: accountID))

        ledger.record(draftID: "b", accountID: accountID)
        ledger.record(draftID: "c", accountID: accountID)
        ledger.record(draftID: "d", accountID: accountID) // evicts the oldest, "a"

        #expect(!ledger.contains(draftID: "a", accountID: accountID))
        #expect(ledger.contains(draftID: "d", accountID: accountID))
    }

    @Test("network SMTP send errors queue draft and return queued warning")
    func networkSMTPSendErrorsQueueDraftAndReturnQueuedWarning() async throws {
        let queue = try Self.makeMutationQueue()
        let draft = Self.outgoingDraft()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { _, _, _ in
                throw SMTPClientError.transport("offline")
            },
            offlineMutationQueue: queue
        )
        try await backend.connect()

        let result = try await backend.send(draft: draft)

        #expect(result == SendResult(warnings: [.queuedForRetry]))
        let pending = try await queue.pending()
        #expect(pending.count == 1)
        guard case .sendStagedDraft(let stagedDraftID) = pending.first?.kind else {
            Issue.record("Expected queued send mutation.")
            return
        }
        #expect(stagedDraftID == draft.id)
    }

    @Test("unknown SMTP delivery outcomes preserve the draft without queueing a retry")
    func unknownSMTPSendOutcomePreservesDraftWithoutQueueingRetry() async throws {
        let queue = try Self.makeMutationQueue()
        let stagingStore = InMemoryIMAPDraftStagingStore()
        let draft = Self.outgoingDraft(id: "unknown-outcome")
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { _, _, _ in
                throw SMTPClientError.deliveryOutcomeUnknown(
                    underlying: "Timed out waiting for SMTP DATA response."
                )
            },
            draftStagingStore: stagingStore,
            offlineMutationQueue: queue
        )
        try await backend.connect()

        await #expect(throws: SMTPClientError.deliveryOutcomeUnknown(
            underlying: "Timed out waiting for SMTP DATA response."
        )) {
            _ = try await backend.send(draft: draft)
        }
        #expect(try await queue.pending().isEmpty)
        #expect(await stagingStore.draft(accountID: Self.account.id, draftID: draft.id) == draft)
    }

    @Test("a draft without recipients surfaces validation and is not queued")
    func draftWithoutRecipientsSurfacesValidationAndIsNotQueued() async throws {
        let queue = try Self.makeMutationQueue()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { _, _, _ in
                Issue.record("A draft without recipients must fail before SMTP submission.")
                return SendResult(sentMessageID: "unexpected")
            },
            offlineMutationQueue: queue
        )
        try await backend.connect()

        await #expect(throws: DraftValidationError.missingRecipients) {
            _ = try await backend.send(draft: Draft(id: "missing-recipients"))
        }
        #expect(try await queue.pending().isEmpty)
    }

    @Test("permanent SMTP authentication failures are not queued")
    func permanentSMTPSAuthenticationFailuresAreNotQueued() async throws {
        let queue = try Self.makeMutationQueue()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { _, _, _ in
                throw SMTPClientError.authenticationFailed("535 invalid credentials")
            },
            offlineMutationQueue: queue
        )
        try await backend.connect()

        await #expect(throws: SMTPClientError.authenticationFailed("535 invalid credentials")) {
            _ = try await backend.send(draft: Self.outgoingDraft())
        }
        #expect(try await queue.pending().isEmpty)
    }

    // NOTE: Scheduled-send delivery tests live in the dedicated, serialized
    // `IMAPSMTPScheduledSendTests` suite below. They persist to a process-global
    // UserDefaults key derived from the account id and every `connect()` now runs
    // a delivery pass, so they must not share an account id with this suite's
    // parallel tests.

    @Test("source-scoped send rejects stale IMAP mailbox source")
    func sourceScopedSendRejectsStaleIMAPMailboxSource() async throws {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { _, _, _ in SendResult(sentMessageID: "sent") }
        )
        try await backend.connect()

        do {
            _ = try await backend.send(
                draft: Self.outgoingDraft(),
                sourceID: MailSourceID(
                    accountID: Self.account.id,
                    mailboxID: "stale-mailbox"
                )
            )
            Issue.record("Expected stale source-scoped send to fail.")
        } catch MailBackendError.notFound(let id) {
            #expect(id == "stale-mailbox")
        } catch {
            Issue.record("Expected notFound for stale source, got \(error).")
        }
    }

    @Test("source-scoped send accepts primary IMAP mailbox source")
    func sourceScopedSendAcceptsPrimaryIMAPMailboxSource() async throws {
        let recorder = MessageSendRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { configuration, credential, submission in
                try await recorder.sendMessage(
                    configuration: configuration,
                    credential: credential,
                    submission: submission
                )
                return SendResult(sentMessageID: "smtp-queued")
            }
        )
        try await backend.connect()

        let result = try await backend.send(
            draft: Self.outgoingDraft(),
            sourceID: Self.sourceID
        )

        let call = try #require(await recorder.calls.first)
        #expect(result == SendResult(sentMessageID: "smtp-queued"))
        #expect(call.submission.senderEmail == "person@example.org")
    }

    @Test("send appends accepted SMTP message to sent folder")
    func sendAppendsAcceptedSMTPMessageToSentFolder() async throws {
        let sendRecorder = MessageSendRecorder()
        let appendRecorder = MessageAppendRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
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
                    flags: ["sent"],
                    role: .sent
                ),
            ] },
            sendMessage: { configuration, credential, submission in
                try await sendRecorder.sendMessage(
                    configuration: configuration,
                    credential: credential,
                    submission: submission
                )
                return SendResult(sentMessageID: "smtp-accepted")
            },
            appendSentMessage: { configuration, credential, folderID, messageData, flags in
                try await appendRecorder.appendMessage(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    messageData: messageData,
                    flags: flags
                )
                return nil
            }
        )
        try await backend.connect()

        let result = try await backend.send(draft: Draft(
            id: "draft-2",
            to: [Correspondent(email: "bob@example.org")],
            subject: "Sent copy",
            htmlBody: "<p>Saved</p>"
        ))

        let sendCall = try #require(await sendRecorder.calls.first)
        #expect(result == SendResult(sentMessageID: "smtp-accepted"))
        #expect(await appendRecorder.calls == [
            MessageAppendRecorder.Call(
                folderID: "Sent",
                messageData: sendCall.submission.messageData,
                flags: [.seen]
            ),
        ])
    }

    @Test("send returns warning when Sent copy append fails")
    func sendReturnsWarningWhenSentCopyAppendFails() async throws {
        let sendRecorder = MessageSendRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "Sent",
                    displayName: "Sent",
                    delimiter: "/",
                    flags: ["sent"],
                    role: .sent
                ),
            ] },
            sendMessage: { configuration, credential, submission in
                try await sendRecorder.sendMessage(
                    configuration: configuration,
                    credential: credential,
                    submission: submission
                )
                return SendResult(sentMessageID: "smtp-accepted")
            },
            appendSentMessage: { _, _, _, _, _ in
                throw IMAPClientError.transport("APPEND failed")
            }
        )
        try await backend.connect()

        let result = try await backend.send(draft: Self.outgoingDraft())

        #expect(result.sentMessageID == "smtp-accepted")
        #expect(result.warnings == [.sentCopyAppendFailed])
    }

    @Test("save stages IMAP SMTP draft for compose send")
    func saveStagesIMAPSMTPDraftForComposeSend() async throws {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] }
        )
        try await backend.connect()

        let saved = try await backend.save(draft: Draft(
            id: "local-compose",
            to: [Correspondent(email: "bob@example.org")],
            subject: "Local staging",
            htmlBody: "<p>Staged</p>"
        ))

        #expect(saved.remoteID == "imap-local-draft-local-compose")
    }

    @Test("source-scoped draft actions reject stale IMAP mailbox source")
    func sourceScopedDraftActionsRejectStaleIMAPMailboxSource() async throws {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] }
        )
        try await backend.connect()

        let staleSourceID = MailSourceID(
            accountID: Self.account.id,
            mailboxID: "stale-mailbox"
        )
        await expectNotFound("stale-mailbox") {
            _ = try await backend.save(
                draft: Self.outgoingDraft(),
                sourceID: staleSourceID
            )
        }
        await expectNotFound("stale-mailbox") {
            _ = try await backend.uploadAttachment(
                draftID: "draft-1",
                data: Data("attachment".utf8),
                filename: "attachment.txt",
                mimeType: "text/plain",
                sourceID: staleSourceID
            )
        }
        await expectNotFound("stale-mailbox") {
            try await backend.discard(
                draftID: "Drafts:77",
                sourceID: staleSourceID
            )
        }
    }

    @Test("save appends IMAP draft and replaces prior remote draft")
    func saveAppendsIMAPDraftAndReplacesPriorRemoteDraft() async throws {
        let appendRecorder = DraftAppendRecorder(uids: [77, 78])
        let deleteRecorder = MessagePermanentDeleteRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "Drafts",
                    displayName: "Drafts",
                    delimiter: "/",
                    flags: [],
                    role: .drafts
                ),
            ] },
            permanentlyDeleteMessages: { configuration, credential, folderID, uids in
                try await deleteRecorder.permanentlyDeleteMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uids: uids
                )
            },
            appendDraftMessage: { configuration, credential, folderID, messageData, flags in
                try await appendRecorder.appendDraftMessage(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    messageData: messageData,
                    flags: flags
                )
            }
        )
        try await backend.connect()

        let saved = try await backend.save(draft: Draft(
            id: "remote-compose",
            to: [Correspondent(email: "bob@example.org")],
            subject: "Remote draft",
            htmlBody: "<p>Staged remotely</p>"
        ))
        var edited = saved
        edited.subject = "Remote draft updated"
        let replaced = try await backend.save(draft: edited)
        try await backend.discard(draftID: #require(replaced.remoteID))

        let appendCalls = await appendRecorder.calls
        #expect(saved.remoteID == "Drafts:77")
        #expect(replaced.remoteID == "Drafts:78")
        #expect(appendCalls.map(\.folderID) == ["Drafts", "Drafts"])
        #expect(appendCalls.map(\.flags) == [[.draft], [.draft]])
        #expect(String(data: appendCalls[0].messageData, encoding: .utf8)?.contains("Subject: Remote draft") == true)
        #expect(String(data: appendCalls[1].messageData, encoding: .utf8)?.contains("Subject: Remote draft updated") == true)
        #expect(await deleteRecorder.calls == [
            MessagePermanentDeleteRecorder.Call(folderID: "Drafts", uids: [77]),
            MessagePermanentDeleteRecorder.Call(folderID: "Drafts", uids: [78]),
        ])
    }

    @Test("send removes server-saved IMAP draft after SMTP accepts")
    func sendRemovesServerSavedIMAPDraftAfterSMTPAccepts() async throws {
        let sendRecorder = MessageSendRecorder()
        let deleteRecorder = MessagePermanentDeleteRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "Drafts",
                    displayName: "Drafts",
                    delimiter: "/",
                    flags: [],
                    role: .drafts
                ),
            ] },
            permanentlyDeleteMessages: { configuration, credential, folderID, uids in
                try await deleteRecorder.permanentlyDeleteMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uids: uids
                )
            },
            sendMessage: { configuration, credential, submission in
                try await sendRecorder.sendMessage(
                    configuration: configuration,
                    credential: credential,
                    submission: submission
                )
                return SendResult(sentMessageID: "smtp-accepted")
            }
        )
        try await backend.connect()

        let result = try await backend.send(draft: Draft(
            id: "server-draft",
            remoteID: "Drafts:91",
            to: [Correspondent(email: "bob@example.org")],
            subject: "Server saved",
            htmlBody: "<p>Ready</p>"
        ))

        #expect(result == SendResult(sentMessageID: "smtp-accepted"))
        #expect(await sendRecorder.calls.count == 1)
        #expect(await deleteRecorder.calls == [
            MessagePermanentDeleteRecorder.Call(folderID: "Drafts", uids: [91]),
        ])
    }

    @Test("send returns warning when server-saved IMAP draft cleanup fails")
    func sendReturnsWarningWhenServerSavedIMAPDraftCleanupFails() async throws {
        let sendRecorder = MessageSendRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "Drafts",
                    displayName: "Drafts",
                    delimiter: "/",
                    flags: [],
                    role: .drafts
                ),
            ] },
            permanentlyDeleteMessages: { _, _, _, _ in
                throw MailBackendError.network(underlying: "Drafts cleanup failed")
            },
            sendMessage: { configuration, credential, submission in
                try await sendRecorder.sendMessage(
                    configuration: configuration,
                    credential: credential,
                    submission: submission
                )
                return SendResult(sentMessageID: "smtp-accepted")
            }
        )
        try await backend.connect()

        let result = try await backend.send(draft: Draft(
            id: "server-draft",
            remoteID: "Drafts:91",
            to: [Correspondent(email: "bob@example.org")],
            subject: "Server saved",
            htmlBody: "<p>Ready</p>"
        ))

        #expect(result.sentMessageID == "smtp-accepted")
        #expect(result.warnings == [.remoteDraftCleanupFailed])
        #expect(await sendRecorder.calls.count == 1)
    }

    @Test("send prunes cached server-saved IMAP draft and emits removal")
    func sendPrunesCachedServerSavedIMAPDraftAndEmitsRemoval() async throws {
        let sendRecorder = MessageSendRecorder()
        let deleteRecorder = MessagePermanentDeleteRecorder()
        let headerCache = InMemoryIMAPMailboxHeaderCache(snapshotsByFolderByAccount: [
            Self.account.id: [
                "Drafts": IMAPMailboxHeaderCacheSnapshot(
                    headers: [
                        MessageHeader(
                            id: "Drafts:91",
                            threadID: "<draft-91@example.org>",
                            folderID: "Drafts",
                            from: Correspondent(email: "person@example.org"),
                            to: [Correspondent(email: "bob@example.org")],
                            subject: "Server saved",
                            snippet: "",
                            date: Date(timeIntervalSince1970: 91),
                            isRead: true,
                            isFlagged: false
                        ),
                    ],
                    firstPageHeaderIDs: ["Drafts:91"]
                ),
            ],
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "Drafts",
                    displayName: "Drafts",
                    delimiter: "/",
                    flags: [],
                    role: .drafts
                ),
            ] },
            permanentlyDeleteMessages: { configuration, credential, folderID, uids in
                try await deleteRecorder.permanentlyDeleteMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uids: uids
                )
            },
            sendMessage: { configuration, credential, submission in
                try await sendRecorder.sendMessage(
                    configuration: configuration,
                    credential: credential,
                    submission: submission
                )
                return SendResult(sentMessageID: "smtp-accepted")
            },
            headerCache: headerCache
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()

        _ = try await backend.send(draft: Draft(
            id: "server-draft",
            remoteID: "Drafts:91",
            to: [Correspondent(email: "bob@example.org")],
            subject: "Server saved",
            htmlBody: "<p>Ready</p>"
        ))

        let event = try await nextIMAPEvent(from: stream)
        let cachedDrafts = await headerCache.snapshot(
            accountID: Self.account.id,
            folderID: "Drafts"
        )
        #expect(event == .messagesRemoved(folderID: "Drafts", messageIDs: ["Drafts:91"]))
        #expect(cachedDrafts?.headers.map(\.id) == [])
        #expect(cachedDrafts?.firstPageHeaderIDs == Set<MessageHeader.ID>())
        #expect(await deleteRecorder.calls == [
            MessagePermanentDeleteRecorder.Call(folderID: "Drafts", uids: [91]),
        ])
    }

    @Test("send includes staged attachment payloads in SMTP MIME message")
    func sendIncludesStagedAttachmentPayloadsInSMTPMIMEMessage() async throws {
        let sendRecorder = MessageSendRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { configuration, credential, submission in
                try await sendRecorder.sendMessage(
                    configuration: configuration,
                    credential: credential,
                    submission: submission
                )
                return SendResult(sentMessageID: "smtp-with-attachment")
            }
        )
        try await backend.connect()
        let saved = try await backend.save(draft: Draft(
            id: "attachment-draft",
            to: [Correspondent(email: "bob@example.org")],
            subject: "Attachment",
            htmlBody: "<p>See attached.</p>"
        ))
        let draftID = try #require(saved.remoteID)
        let attachmentID = try await backend.uploadAttachment(
            draftID: draftID,
            data: Data("invoice data".utf8),
            filename: "invoice.txt",
            mimeType: "text/plain"
        )

        var draft = saved
        draft.attachmentIDs = [attachmentID]
        let result = try await backend.send(draft: draft)

        let call = try #require(await sendRecorder.calls.first)
        let message = String(data: call.submission.messageData, encoding: .utf8) ?? ""
        #expect(result == SendResult(sentMessageID: "smtp-with-attachment"))
        #expect(message.contains("Content-Type: multipart/mixed;"))
        #expect(message.contains("Content-Disposition: attachment; filename=\"invoice.txt\""))
        #expect(message.contains("Content-Transfer-Encoding: base64"))
        #expect(message.contains("aW52b2ljZSBkYXRh"))
    }

    @Test("send uses persisted staged attachment payloads across backend instances")
    func sendUsesPersistedStagedAttachmentPayloadsAcrossBackendInstances() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevIMAPDraftStagingStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let draftStore = FileIMAPDraftStagingStore(rootDirectory: rootDirectory)
        let firstBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            draftStagingStore: draftStore
        )
        try await firstBackend.connect()
        let saved = try await firstBackend.save(draft: Draft(
            id: "persisted-attachment-draft",
            to: [Correspondent(email: "bob@example.org")],
            subject: "Persisted attachment",
            htmlBody: "<p>See attached.</p>"
        ))
        let draftID = try #require(saved.remoteID)
        let attachmentID = try await firstBackend.uploadAttachment(
            draftID: draftID,
            data: Data("invoice data".utf8),
            filename: "invoice.txt",
            mimeType: "text/plain"
        )

        let sendRecorder = MessageSendRecorder()
        let secondBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { configuration, credential, submission in
                try await sendRecorder.sendMessage(
                    configuration: configuration,
                    credential: credential,
                    submission: submission
                )
                return SendResult(sentMessageID: "smtp-with-persisted-attachment")
            },
            draftStagingStore: FileIMAPDraftStagingStore(rootDirectory: rootDirectory)
        )
        try await secondBackend.connect()
        var draft = saved
        draft.attachmentIDs = [attachmentID]

        let result = try await secondBackend.send(draft: draft)

        let call = try #require(await sendRecorder.calls.first)
        let message = String(data: call.submission.messageData, encoding: .utf8) ?? ""
        #expect(result == SendResult(sentMessageID: "smtp-with-persisted-attachment"))
        #expect(message.contains("Content-Disposition: attachment; filename=\"invoice.txt\""))
        #expect(message.contains("aW52b2ljZSBkYXRh"))
    }

    @Test("discard resolves persisted local draft id to remote IMAP draft")
    func discardResolvesPersistedLocalDraftIDToRemoteIMAPDraft() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevIMAPDraftDiscardStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let draftStore = FileIMAPDraftStagingStore(rootDirectory: rootDirectory)
        let appendRecorder = DraftAppendRecorder(uids: [77])
        let firstBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "Drafts",
                    displayName: "Drafts",
                    delimiter: "/",
                    flags: [],
                    role: .drafts
                ),
            ] },
            appendDraftMessage: { configuration, credential, folderID, messageData, flags in
                try await appendRecorder.appendDraftMessage(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    messageData: messageData,
                    flags: flags
                )
            },
            draftStagingStore: draftStore
        )
        try await firstBackend.connect()
        let saved = try await firstBackend.save(draft: Draft(
            id: "local-draft-id",
            to: [Correspondent(email: "bob@example.org")],
            subject: "Persisted discard",
            htmlBody: "<p>Discard me</p>"
        ))
        let remoteID = try #require(saved.remoteID)
        #expect(remoteID == "Drafts:77")

        let deleteRecorder = MessagePermanentDeleteRecorder()
        let restoredBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "Drafts",
                    displayName: "Drafts",
                    delimiter: "/",
                    flags: [],
                    role: .drafts
                ),
            ] },
            permanentlyDeleteMessages: { configuration, credential, folderID, uids in
                try await deleteRecorder.permanentlyDeleteMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uids: uids
                )
            },
            draftStagingStore: draftStore
        )
        try await restoredBackend.connect()

        try await restoredBackend.discard(draftID: saved.id)

        #expect(await deleteRecorder.calls == [
            MessagePermanentDeleteRecorder.Call(folderID: "Drafts", uids: [77]),
        ])
        #expect(await draftStore.draft(accountID: Self.account.id, draftID: saved.id) == nil)
        #expect(await draftStore.draft(accountID: Self.account.id, draftID: remoteID) == nil)
    }

    @Test("send rejects unknown staged attachment before SMTP submission")
    func sendRejectsUnknownStagedAttachmentBeforeSMTPSubmission() async throws {
        let sendRecorder = MessageSendRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { configuration, credential, submission in
                try await sendRecorder.sendMessage(
                    configuration: configuration,
                    credential: credential,
                    submission: submission
                )
                return SendResult()
            }
        )
        try await backend.connect()

        do {
            _ = try await backend.send(draft: Draft(
                id: "bad-attachment",
                to: [Correspondent(email: "bob@example.org")],
                subject: "Missing",
                htmlBody: "Missing attachment",
                attachmentIDs: ["missing-attachment"]
            ))
            Issue.record("Expected missing attachment to fail before SMTP submission.")
        } catch MailBackendError.notFound(let id) {
            #expect(id == "missing-attachment")
        } catch {
            Issue.record("Expected notFound, got \(error).")
        }
        #expect(await sendRecorder.calls.isEmpty)
    }

    @Test("refresh emits messages added for newly listed IMAP headers")
    func refreshEmitsMessagesAddedForNewlyListedIMAPHeaders() async throws {
        let recorder = MessageListingRecorder(messages: [
            Self.messageListing(uid: 43, subject: "Existing"),
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            }
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        _ = try await backend.messages(in: inbox, pageToken: nil)
        await recorder.setMessages([
            Self.messageListing(uid: 44, subject: "New"),
            Self.messageListing(uid: 43, subject: "Existing"),
        ])
        try await backend.refresh(folder: inbox)

        let event = try await nextIMAPEvent(from: stream)
        #expect(event == .messagesAdded(folderID: "INBOX", messageIDs: ["INBOX:44"]))
    }

    @Test("refresh emits updates for remotely changed IMAP header flags")
    func refreshEmitsUpdatesForRemotelyChangedIMAPHeaderFlags() async throws {
        let recorder = MessageListingRecorder(messages: [
            Self.messageListing(uid: 43, subject: "Existing"),
        ])
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let localSearchIndex = LocalSearchIndexRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            headerCache: headerCache,
            localSearchIndex: localSearchIndex
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        _ = try await backend.messages(in: inbox, pageToken: nil)
        await recorder.setMessages([
            Self.messageListing(
                uid: 43,
                subject: "Existing",
                isRead: true,
                isFlagged: true
            ),
        ])
        await localSearchIndex.delayNextHeaderStore(by: 200_000_000)
        let refreshTask = Task {
            try await backend.refresh(folder: inbox)
        }

        let event = try await nextIMAPEvent(from: stream)
        #expect(event == .messagesUpdated(folderID: "INBOX", messageIDs: ["INBOX:43"]))
        let cachedHeaders = await headerCache.snapshot(accountID: Self.account.id, folderID: "INBOX")?.headers
        #expect(cachedHeaders?.first?.isRead == true)
        #expect(cachedHeaders?.first?.isFlagged == true)
        let indexedHeaders = await localSearchIndex.storedHeaderBatches.last
        #expect(indexedHeaders?.first?.isRead == true)
        #expect(indexedHeaders?.first?.isFlagged == true)
        try await refreshTask.value
    }

    @Test("refresh emits removals for IMAP headers missing from refreshed first page")
    func refreshEmitsRemovalsForMissingIMAPFirstPageHeaders() async throws {
        let recorder = MessageListingRecorder(messages: [
            Self.messageListing(uid: 44, subject: "Soon gone"),
            Self.messageListing(uid: 43, subject: "Existing"),
        ])
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            headerCache: headerCache
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        _ = try await backend.messages(in: inbox, pageToken: nil)
        await recorder.setMessages([
            Self.messageListing(uid: 43, subject: "Existing"),
        ], nextPageToken: nil)
        try await backend.refresh(folder: inbox)

        let event = try await nextIMAPEvent(from: stream)
        #expect(event == .messagesRemoved(folderID: "INBOX", messageIDs: ["INBOX:44"]))
        let cachedHeaders = await headerCache.snapshot(accountID: Self.account.id, folderID: "INBOX")?.headers
        #expect(cachedHeaders?.map(\.id) == ["INBOX:43"])
    }

    @Test("IDLE exists refreshes inbox into messages added event")
    func idleExistsRefreshesInboxIntoMessagesAddedEvent() async throws {
        let recorder = MessageListingRecorder(messages: [
            Self.messageListing(uid: 43, subject: "Existing"),
        ])
        let folderRecorder = FolderListingRecorder(listings: [
            IMAPFolderListing(
                path: "INBOX",
                displayName: "Inbox",
                delimiter: "/",
                flags: [],
                role: .inbox
            ),
        ])
        let idleRecorder = IMAPIdleEventRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { configuration, credential in
                try await folderRecorder.listFolders(
                    configuration: configuration,
                    credential: credential
                )
            },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            idleEvents: { configuration, credential, folderID in
                #expect(configuration.accountID == "imap-smtp:person@example.org")
                #expect(credential.incomingUsername == "person@example.org")
                #expect(folderID == "INBOX")
                return await idleRecorder.stream()
            }
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        _ = try await backend.messages(in: inbox, pageToken: nil)
        try await idleRecorder.waitUntilSubscribed()
        await recorder.setMessages([
            Self.messageListing(uid: 44, subject: "New"),
            Self.messageListing(uid: 43, subject: "Existing"),
        ])
        await idleRecorder.emit(.exists(count: 2))

        let event = try await nextIMAPEvent(from: stream)
        #expect(event == .messagesAdded(folderID: "INBOX", messageIDs: ["INBOX:44"]))
        #expect(await folderRecorder.callCount == 1)
        await idleRecorder.finish()
    }

    @Test("IDLE watches selected folder after folder load")
    func idleWatchesSelectedFolderAfterFolderLoad() async throws {
        let recorder = MessageListingRecorder(messages: [
            Self.messageListing(uid: 7, subject: "Existing archive"),
        ])
        let idleRecorder = IMAPIdleEventRecorder()
        let subscriptionRecorder = IMAPIdleFolderSubscriptionRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
                IMAPFolderListing(
                    path: "Archive",
                    displayName: "Archive",
                    delimiter: "/",
                    flags: ["archive"],
                    role: .archive
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            idleEvents: { _, _, folderID in
                await subscriptionRecorder.record(folderID)
                return await idleRecorder.stream()
            }
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()
        try await subscriptionRecorder.waitUntilFolderIDs(["INBOX"])

        let archive = Folder(id: "Archive", name: "Archive", role: .archive)
        _ = try await backend.messages(in: archive, pageToken: nil)
        try await subscriptionRecorder.waitUntilFolderIDs(["INBOX", "Archive"])

        await recorder.setMessages([
            Self.messageListing(uid: 8, subject: "New archive"),
            Self.messageListing(uid: 7, subject: "Existing archive"),
        ], nextPageToken: nil)
        await idleRecorder.emit(.exists(count: 2))

        let event = try await nextIMAPEvent(from: stream)
        #expect(event == .messagesAdded(folderID: "Archive", messageIDs: ["Archive:8"]))
        #expect(await recorder.requestedFolderIDs == ["Archive", "Archive"])
        await idleRecorder.finish()
    }

    @Test("IDLE watches one folder at a time and follows the selected mailbox")
    func idleWatchesOneFolderAtATimeAndFollowsSelectedMailbox() async throws {
        let recorder = MessageListingRecorder(messages: [
            Self.messageListing(uid: 1, subject: "Existing inbox"),
        ])
        let idle = PerFolderIdleEventRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
                IMAPFolderListing(
                    path: "Archive",
                    displayName: "Archive",
                    delimiter: "/",
                    flags: ["archive"],
                    role: .archive
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            idleEvents: { _, _, folderID in
                await idle.stream(for: folderID)
            }
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()

        // Default focus is INBOX until another folder becomes active.
        try await idle.waitUntilSubscribed("INBOX")

        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let archive = Folder(id: "Archive", name: "Archive", role: .archive)
        _ = try await backend.messages(in: inbox, pageToken: nil)
        _ = try await backend.messages(in: archive, pageToken: nil)
        try await idle.waitUntilSubscribed("Archive")

        // Single-watcher policy: while Archive is selected, INBOX events are not
        // observed until focus returns to INBOX.
        await recorder.setMessages([
            Self.messageListing(uid: 2, subject: "New inbox"),
            Self.messageListing(uid: 1, subject: "Existing inbox"),
        ])
        await idle.emit(.exists(count: 2), to: "INBOX")
        try await Task.sleep(nanoseconds: 50_000_000)

        // Returning focus to INBOX restarts the single watcher there.
        _ = try await backend.messages(in: inbox, pageToken: nil)
        try await idle.waitUntilSubscribed("INBOX")
        await idle.emit(.exists(count: 2), to: "INBOX")

        let event = try await nextIMAPEvent(from: stream)
        #expect(event == .messagesAdded(folderID: "INBOX", messageIDs: ["INBOX:2"]))
        await idle.finishAll()
    }

    @Test("paginating offline after a cached first page ends gracefully")
    func paginatingOfflineAfterCachedFirstPageEndsGracefully() async throws {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(path: "INBOX", displayName: "Inbox", delimiter: "/", flags: [], role: .inbox),
            ] },
            listMessages: { _, _, _, pageToken, _ in
                // The first page succeeds; the next page fails as if the
                // connection dropped mid-pagination.
                if pageToken != nil {
                    throw IMAPClientError.transport("offline")
                }
                return IMAPMessageListingPage(
                    messages: [Self.messageListing(uid: 1, subject: "Cached")],
                    nextPageToken: "before:1"
                )
            }
        )
        try await backend.connect()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        let firstPage = try await backend.messages(in: inbox, pageToken: nil)
        #expect(firstPage.nextPageToken == "before:1")

        // Scrolling past the first page while offline must not throw — it ends
        // pagination so the already-shown cached headers stay in place.
        let secondPage = try await backend.messages(in: inbox, pageToken: firstPage.nextPageToken)
        #expect(secondPage.headers.isEmpty)
        #expect(secondPage.nextPageToken == nil)

        // The same must hold once the session is fully disconnected.
        await backend.disconnect()
        let afterDisconnect = try await backend.messages(in: inbox, pageToken: "before:1")
        #expect(afterDisconnect.headers.isEmpty)
        #expect(afterDisconnect.nextPageToken == nil)
    }

    @Test("IDLE flags change reconciles cached inbox headers")
    func idleFlagsChangeReconcilesCachedInboxHeaders() async throws {
        let recorder = MessageListingRecorder(messages: [
            Self.messageListing(uid: 43, subject: "Existing"),
        ])
        let idleRecorder = IMAPIdleEventRecorder()
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            idleEvents: { _, _, _ in
                await idleRecorder.stream()
            },
            headerCache: headerCache
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        _ = try await backend.messages(in: inbox, pageToken: nil)
        try await idleRecorder.waitUntilSubscribed()
        await recorder.setMessages([
            Self.messageListing(
                uid: 43,
                subject: "Existing",
                isRead: true,
                isFlagged: true
            ),
        ])
        await idleRecorder.emit(.flagsChanged(sequenceNumber: 1))

        let event = try await nextIMAPEvent(from: stream)
        #expect(event == .messagesUpdated(folderID: "INBOX", messageIDs: ["INBOX:43"]))
        let cachedHeaders = await headerCache.snapshot(accountID: Self.account.id, folderID: "INBOX")?.headers
        #expect(cachedHeaders?.first?.isRead == true)
        #expect(cachedHeaders?.first?.isFlagged == true)
        await idleRecorder.finish()
    }

    @Test("IDLE expunge reconciles cached inbox removals")
    func idleExpungeReconcilesCachedInboxRemovals() async throws {
        let recorder = MessageListingRecorder(messages: [
            Self.messageListing(uid: 44, subject: "Soon gone"),
            Self.messageListing(uid: 43, subject: "Existing"),
        ])
        let idleRecorder = IMAPIdleEventRecorder()
        let headerCache = InMemoryIMAPMailboxHeaderCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            idleEvents: { _, _, _ in
                await idleRecorder.stream()
            },
            headerCache: headerCache
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        _ = try await backend.messages(in: inbox, pageToken: nil)
        try await idleRecorder.waitUntilSubscribed()
        await recorder.setMessages([
            Self.messageListing(uid: 43, subject: "Existing"),
        ], nextPageToken: nil)
        await idleRecorder.emit(.expunged(sequenceNumber: 1))

        let event = try await nextIMAPEvent(from: stream)
        #expect(event == .messagesRemoved(folderID: "INBOX", messageIDs: ["INBOX:44"]))
        let cachedHeaders = await headerCache.snapshot(accountID: Self.account.id, folderID: "INBOX")?.headers
        #expect(cachedHeaders?.map(\.id) == ["INBOX:43"])
        await idleRecorder.finish()
    }

    @Test("IDLE resubscribes after stream failure")
    func idleResubscribesAfterStreamFailure() async throws {
        let recorder = MessageListingRecorder(messages: [
            Self.messageListing(uid: 43, subject: "Existing"),
        ])
        let idleRecorder = IMAPIdleEventRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            idleEvents: { configuration, credential, folderID in
                #expect(configuration.accountID == "imap-smtp:person@example.org")
                #expect(credential.incomingUsername == "person@example.org")
                #expect(folderID == "INBOX")
                return await idleRecorder.stream()
            }
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        _ = try await backend.messages(in: inbox, pageToken: nil)
        try await idleRecorder.waitUntilSubscriptionCount(1)
        await idleRecorder.fail(IMAPClientError.transport("Idle dropped"))
        try await idleRecorder.waitUntilSubscriptionCount(2)
        await recorder.setMessages([
            Self.messageListing(uid: 44, subject: "New after reconnect"),
            Self.messageListing(uid: 43, subject: "Existing"),
        ])
        await idleRecorder.emit(.exists(count: 2))

        let event = try await nextIMAPEvent(from: stream)
        #expect(event == .messagesAdded(folderID: "INBOX", messageIDs: ["INBOX:44"]))
        await idleRecorder.finish()
    }

    @Test("IDLE refreshes an expired XOAUTH2 credential before one resubscribe")
    func idleRefreshesExpiredOAuthCredentialBeforeResubscribe() async throws {
        let expiredCredential = MailAccountCredential(
            incomingUsername: Self.account.emailAddress,
            outgoingUsername: Self.account.emailAddress,
            secret: "expired-access-token",
            authentication: .xoauth2
        )
        let refreshedCredential = MailAccountCredential(
            incomingUsername: Self.account.emailAddress,
            outgoingUsername: Self.account.emailAddress,
            secret: "fresh-access-token",
            authentication: .xoauth2
        )
        let idleRecorder = OAuthRefreshingIMAPIdleEventRecorder()
        let messageRecorder = MessageListingRecorder(messages: [
            Self.messageListing(uid: 43, subject: "Existing"),
        ])
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: expiredCredential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await messageRecorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            refreshOAuthCredential: { _, _, credential in
                #expect(credential == expiredCredential)
                return refreshedCredential
            },
            idleEvents: { _, credential, folderID in
                #expect(folderID == "INBOX")
                return await idleRecorder.stream(credential: credential)
            }
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        _ = try await backend.messages(in: inbox, pageToken: nil)

        try await idleRecorder.waitUntilSubscriptionCount(2)
        #expect(await idleRecorder.credentials == [expiredCredential, refreshedCredential])
        #expect(await idleRecorder.refreshingSubscriptionCount == 1)

        await messageRecorder.setMessages([
            Self.messageListing(uid: 44, subject: "New after OAuth refresh"),
            Self.messageListing(uid: 43, subject: "Existing"),
        ])
        await idleRecorder.emit(.exists(count: 2))

        let event = try await nextIMAPEvent(from: stream)
        #expect(event == .messagesAdded(folderID: "INBOX", messageIDs: ["INBOX:44"]))
        await idleRecorder.finish()
    }

    @Test("IDLE backs off after an OAuth refresh failure without retrying refresh")
    func idleOAuthRefreshFailureBacksOffWithoutRetryingRefresh() async throws {
        let expiredCredential = MailAccountCredential(
            incomingUsername: Self.account.emailAddress,
            outgoingUsername: Self.account.emailAddress,
            secret: "expired-access-token",
            authentication: .xoauth2
        )
        let idleRecorder = OAuthRefreshingIMAPIdleEventRecorder(
            failure: OAuthRefreshError.refreshFailed(statusCode: 503, bodyByteCount: 0)
        )
        let refreshCounter = OAuthRefreshCounter()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: expiredCredential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(messages: [Self.messageListing(uid: 43, subject: "Existing")])
            },
            refreshOAuthCredential: { _, _, _ in
                await refreshCounter.increment()
                throw OAuthRefreshError.refreshFailed(statusCode: 503, bodyByteCount: 0)
            },
            idleEvents: { _, credential, _ in
                await idleRecorder.stream(credential: credential)
            }
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()
        _ = stream

        // The first auth failure attempts one refresh. A second subscription
        // is allowed only after the bounded IDLE retry delay, and it must not
        // start another refresh while no healthy stream has been established.
        try await idleRecorder.waitUntilSubscriptionCount(2)
        #expect(await refreshCounter.count == 1)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(await idleRecorder.subscriptionCount == 2)
    }

    @Test("IDLE stream failure degrades sync health without disconnecting")
    func idleStreamFailureDegradesSyncHealthWithoutDisconnecting() async throws {
        let idleRecorder = IMAPIdleEventRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { _, _, _, _, _ in
                IMAPMessageListingPage(messages: [
                    Self.messageListing(uid: 43, subject: "Existing"),
                ])
            },
            idleEvents: { _, _, _ in
                await idleRecorder.stream()
            }
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()
        _ = stream
        try await idleRecorder.waitUntilSubscribed()
        await idleRecorder.fail(IMAPClientError.transport("Idle dropped"))

        let reporter = try #require(backend.extensionService(SyncHealthReporting.self))
        let health = try await waitForSyncHealthError(from: reporter, sourceID: Self.sourceID)

        #expect(health.state == .degraded)
        #expect(health.lastErrorDescription?.contains("Idle dropped") == true)
        #expect(try await backend.folders().map(\.id) == ["INBOX"])
    }

    @Test("IDLE repeated failures back off resubscribe attempts")
    func idleRepeatedFailuresBackOffResubscribeAttempts() async throws {
        let recorder = MessageListingRecorder(messages: [
            Self.messageListing(uid: 43, subject: "Existing"),
        ])
        let idleRecorder = AutoFailingIMAPIdleEventRecorder()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await recorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            idleEvents: { _, _, _ in
                await idleRecorder.stream()
            }
        )
        try await backend.connect()
        let stream = backend.subscribeToChanges()
        _ = stream

        try await idleRecorder.waitUntilSubscriptionCount(2)
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(await idleRecorder.subscriptionCount == 2)
        try await idleRecorder.waitUntilSubscriptionCount(3)
    }

    @Test("body fetches and parses multipart IMAP message source")
    func bodyFetchesAndParsesMultipartIMAPMessageSource() async throws {
        let recorder = MessageSourceRecorder(rawMessage: """
        Subject: Receipt
        Content-Type: multipart/mixed; boundary="mixed-boundary"

        --mixed-boundary
        Content-Type: multipart/alternative; boundary="alt-boundary"

        --alt-boundary
        Content-Type: text/plain; charset=utf-8

        Plain receipt.
        --alt-boundary
        Content-Type: text/html; charset=utf-8

        <p>HTML receipt.</p>
        --alt-boundary--
        --mixed-boundary
        Content-Type: application/pdf; name="=?UTF-8?Q?receipt_=C3=98.pdf?="
        Content-Disposition: attachment; filename="=?UTF-8?Q?receipt_=C3=98.pdf?="
        Content-Transfer-Encoding: base64

        SGVsbG8=
        --mixed-boundary--
        """)
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            fetchMessageSource: { configuration, credential, folderID, uid in
                try await recorder.fetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            }
        )
        try await backend.connect()

        let body = try await backend.body(for: "INBOX:43")

        #expect(await recorder.callCount == 1)
        #expect(await recorder.requestedFolderIDs == ["INBOX"])
        #expect(await recorder.requestedUIDs == [43])
        #expect(body.messageID == "INBOX:43")
        #expect(body.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) == "Plain receipt.")
        #expect(body.html?.trimmingCharacters(in: .whitespacesAndNewlines) == "<p>HTML receipt.</p>")
        #expect(body.attachments == [
            Attachment(
                id: "INBOX:43:attachment:1",
                name: "receipt Ø.pdf",
                mimeType: "application/pdf",
                sizeBytes: 5,
                resource: "imap-source:INBOX:43:1"
            ),
        ])
        let attachment = try #require(body.attachments.first)
        let downloaded = try await backend.downloadAttachment(attachment)
        #expect(downloaded == Data("Hello".utf8))
        #expect(await recorder.callCount == 2)
    }

    @Test("body tolerates MIME boundary transport padding")
    func bodyToleratesMIMEBoundaryTransportPadding() async throws {
        let rawMessage = [
            "Subject: Padded boundary receipt",
            "Content-Type: multipart/mixed; boundary=\"mixed-boundary\"",
            "",
            "--mixed-boundary   ",
            "Content-Type: text/plain; charset=utf-8",
            "",
            "Plain receipt.",
            "--mixed-boundary\t",
            "Content-Type: application/pdf; name=\"receipt.pdf\"",
            "Content-Disposition: attachment; filename=\"receipt.pdf\"",
            "Content-Transfer-Encoding: base64",
            "",
            "SGVsbG8=",
            "--mixed-boundary--   ",
        ].joined(separator: "\n")
        let recorder = MessageSourceRecorder(rawMessage: rawMessage)
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            fetchMessageSource: { configuration, credential, folderID, uid in
                try await recorder.fetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            }
        )
        try await backend.connect()

        let body = try await backend.body(for: "INBOX:43")

        #expect(body.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) == "Plain receipt.")
        let attachment = try #require(body.attachments.first)
        #expect(attachment.name == "receipt.pdf")
        #expect(try await backend.downloadAttachment(attachment) == Data("Hello".utf8))
    }

    @Test("body treats unnamed non text MIME leaf parts as attachments")
    func bodyTreatsUnnamedNonTextMIMELeafPartsAsAttachments() async throws {
        let recorder = MessageSourceRecorder(rawMessage: """
        Subject: Bare attachment
        Content-Type: multipart/mixed; boundary="mixed-boundary"

        --mixed-boundary
        Content-Type: text/plain; charset=utf-8

        Plain receipt.
        --mixed-boundary
        Content-Type: application/pdf
        Content-Transfer-Encoding: base64

        SGVsbG8=
        --mixed-boundary--
        """)
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            fetchMessageSource: { configuration, credential, folderID, uid in
                try await recorder.fetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            }
        )
        try await backend.connect()

        let body = try await backend.body(for: "INBOX:43")

        #expect(body.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) == "Plain receipt.")
        #expect(body.attachments == [
            Attachment(
                id: "INBOX:43:attachment:1",
                name: "Attachment 1",
                mimeType: "application/pdf",
                sizeBytes: 5,
                resource: "imap-source:INBOX:43:1"
            ),
        ])
        let attachment = try #require(body.attachments.first)
        #expect(try await backend.downloadAttachment(attachment) == Data("Hello".utf8))
    }

    @Test("body exposes inline CID image attachments")
    func bodyExposesInlineCIDImageAttachments() async throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let recorder = MessageSourceRecorder(rawMessage: """
        Subject: Inline image
        Content-Type: multipart/related; boundary="related-boundary"

        --related-boundary
        Content-Type: text/html; charset=utf-8

        <p>Hello<img src="cid:hero-image@example.org"></p>
        --related-boundary
        Content-Type: image/png; name="hero.png"
        Content-Disposition: inline; filename="hero.png"
        Content-ID: <hero-image@example.org>
        Content-Transfer-Encoding: base64

        iVBORw==
        --related-boundary--
        """)
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            fetchMessageSource: { configuration, credential, folderID, uid in
                try await recorder.fetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            }
        )
        try await backend.connect()

        let body = try await backend.body(for: "INBOX:43")

        #expect(body.html?.trimmingCharacters(in: .whitespacesAndNewlines) == """
        <p>Hello<img src="cid:hero-image@example.org"></p>
        """)
        #expect(body.attachments == [
            Attachment(
                id: "INBOX:43:attachment:1",
                name: "hero.png",
                mimeType: "image/png",
                sizeBytes: 4,
                isInline: true,
                contentID: "hero-image@example.org",
                resource: "imap-source:INBOX:43:1"
            ),
        ])
        let attachment = try #require(body.attachments.first)
        let downloaded = try await backend.downloadAttachment(attachment)
        #expect(downloaded == imageData)
    }

    @Test("body decodes RFC 2231 attachment filenames")
    func bodyDecodesRFC2231AttachmentFilenames() async throws {
        let recorder = MessageSourceRecorder(rawMessage: """
        Subject: Encoded filename
        Content-Type: multipart/mixed; boundary="mixed-boundary"

        --mixed-boundary
        Content-Type: text/plain; charset=utf-8

        See attached.
        --mixed-boundary
        Content-Type: application/pdf
        Content-Disposition: attachment;
         filename*0*=utf-8''R%C3%A9sum%C3%A9%20;
         filename*1*=Q2%202026.pdf
        Content-Transfer-Encoding: base64

        SGVsbG8=
        --mixed-boundary--
        """)
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            fetchMessageSource: { configuration, credential, folderID, uid in
                try await recorder.fetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            }
        )
        try await backend.connect()

        let body = try await backend.body(for: "INBOX:43")

        let attachment = try #require(body.attachments.first)
        #expect(attachment.name == "Résumé Q2 2026.pdf")
        #expect(attachment.mimeType == "application/pdf")
        #expect(try await backend.downloadAttachment(attachment) == Data("Hello".utf8))
    }

    @Test("body ignores incomplete RFC 2231 attachment filename continuations")
    func bodyIgnoresIncompleteRFC2231AttachmentFilenameContinuations() async throws {
        let recorder = MessageSourceRecorder(rawMessage: """
        Subject: Incomplete encoded filename
        Content-Type: multipart/mixed; boundary="mixed-boundary"

        --mixed-boundary
        Content-Type: text/plain; charset=utf-8

        See attached.
        --mixed-boundary
        Content-Type: application/pdf
        Content-Disposition: attachment;
         filename="fallback.pdf";
         filename*0*=utf-8''Report%20;
         filename*2*=Q2%202026.pdf
        Content-Transfer-Encoding: base64

        SGVsbG8=
        --mixed-boundary--
        """)
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            fetchMessageSource: { configuration, credential, folderID, uid in
                try await recorder.fetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            }
        )
        try await backend.connect()

        let body = try await backend.body(for: "INBOX:43")

        let attachment = try #require(body.attachments.first)
        #expect(attachment.name == "fallback.pdf")
        #expect(try await backend.downloadAttachment(attachment) == Data("Hello".utf8))
    }

    @Test("body keeps semicolons inside quoted attachment filenames")
    func bodyKeepsSemicolonsInsideQuotedAttachmentFilenames() async throws {
        let recorder = MessageSourceRecorder(rawMessage: """
        Subject: Quoted filename
        Content-Type: multipart/mixed; boundary="mixed-boundary"

        --mixed-boundary
        Content-Type: text/plain; charset=utf-8

        See attached.
        --mixed-boundary
        Content-Type: application/pdf; name="Invoice; June.pdf"
        Content-Disposition: attachment; filename="Invoice; June.pdf"
        Content-Transfer-Encoding: base64

        SGVsbG8=
        --mixed-boundary--
        """)
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            fetchMessageSource: { configuration, credential, folderID, uid in
                try await recorder.fetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            }
        )
        try await backend.connect()

        let body = try await backend.body(for: "INBOX:43")

        let attachment = try #require(body.attachments.first)
        #expect(attachment.name == "Invoice; June.pdf")
        #expect(try await backend.downloadAttachment(attachment) == Data("Hello".utf8))
    }

    @Test("body tolerates duplicate MIME attachment filename parameters")
    func bodyToleratesDuplicateMIMEAttachmentFilenameParameters() async throws {
        let recorder = MessageSourceRecorder(rawMessage: """
        Subject: Duplicate filename
        Content-Type: multipart/mixed; boundary="mixed-boundary"

        --mixed-boundary
        Content-Type: text/plain; charset=utf-8

        See attached.
        --mixed-boundary
        Content-Type: application/pdf; name="Invoice.pdf"; name="Invoice Copy.pdf"
        Content-Disposition: attachment; filename="Invoice.pdf"; filename="Invoice Copy.pdf"
        Content-Transfer-Encoding: base64

        SGVsbG8=
        --mixed-boundary--
        """)
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            fetchMessageSource: { configuration, credential, folderID, uid in
                try await recorder.fetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            }
        )
        try await backend.connect()

        let body = try await backend.body(for: "INBOX:43")

        let attachment = try #require(body.attachments.first)
        #expect(attachment.name == "Invoice.pdf")
        #expect(try await backend.downloadAttachment(attachment) == Data("Hello".utf8))
    }

    @Test("body falls back when MIME attachment filename is blank")
    func bodyFallsBackWhenMIMEAttachmentFilenameIsBlank() async throws {
        let recorder = MessageSourceRecorder(rawMessage: """
        Subject: Blank filename
        Content-Type: multipart/mixed; boundary="mixed-boundary"

        --mixed-boundary
        Content-Type: text/plain; charset=utf-8

        See attached.
        --mixed-boundary
        Content-Type: application/pdf; name="   "
        Content-Disposition: attachment; filename=""
        Content-Transfer-Encoding: base64

        SGVsbG8=
        --mixed-boundary--
        """)
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            fetchMessageSource: { configuration, credential, folderID, uid in
                try await recorder.fetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            }
        )
        try await backend.connect()

        let body = try await backend.body(for: "INBOX:43")

        let attachment = try #require(body.attachments.first)
        #expect(attachment.name == "Attachment 1")
        #expect(try await backend.downloadAttachment(attachment) == Data("Hello".utf8))
    }

    @Test("attachment download preserves significant whitespace for unencoded text attachments")
    func attachmentDownloadPreservesSignificantWhitespaceForUnencodedTextAttachments() async throws {
        let recorder = MessageSourceRecorder(rawMessage: """
        Subject: Text attachment spacing
        Content-Type: multipart/mixed; boundary="mixed-boundary"

        --mixed-boundary
        Content-Type: text/plain; charset=utf-8

        Hello
        --mixed-boundary
        Content-Type: text/plain; charset=utf-8; name="notes.txt"
        Content-Disposition: attachment; filename="notes.txt"

          padded attachment text  
        --mixed-boundary--
        """)
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            fetchMessageSource: { configuration, credential, folderID, uid in
                try await recorder.fetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            }
        )
        try await backend.connect()

        let body = try await backend.body(for: "INBOX:43")

        let attachment = try #require(body.attachments.first)
        let data = try await backend.downloadAttachment(attachment)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text == "  padded attachment text  ")
    }

    @Test("body caches fetched IMAP source for later cache-only reads")
    func bodyCachesFetchedIMAPSourceForLaterCacheOnlyReads() async throws {
        let recorder = MessageSourceRecorder(rawMessage: """
        Content-Type: text/plain; charset=utf-8

        Cached body.
        """)
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

        let body = try await backend.body(for: "INBOX:43")

        #expect(body.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) == "Cached body.")
        #expect(await recorder.callCount == 1)

        let cacheOnlyBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sourceCache: sourceCache
        )
        try await cacheOnlyBackend.connect()

        let cachedBody = try await cacheOnlyBackend.body(for: "INBOX:43")

        #expect(cachedBody.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) == "Cached body.")
        #expect(await recorder.callCount == 1)
    }

    @Test("UIDVALIDITY changes invalidate cached IMAP sources")
    func uidValidityChangesInvalidateCachedIMAPSources() async throws {
        let listingRecorder = MessageListingRecorder(page: IMAPMessageListingPage(
            messages: [Self.messageListing(uid: 43, subject: "First")],
            uidValidity: 100,
            nextPageToken: nil
        ))
        let sourceRecorder = MessageSourceSequenceRecorder(rawMessages: [
            """
            Content-Type: text/plain; charset=utf-8

            Old body.
            """,
            """
            Content-Type: text/plain; charset=utf-8

            New body.
            """,
        ])
        let sourceCache = InMemoryIMAPMessageSourceCache()
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await listingRecorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            fetchMessageSource: { configuration, credential, folderID, uid in
                try await sourceRecorder.fetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            },
            sourceCache: sourceCache
        )
        try await backend.connect()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        _ = try await backend.messages(in: inbox, pageToken: nil)
        let oldBody = try await backend.body(for: "INBOX:43")
        await listingRecorder.setPage(IMAPMessageListingPage(
            messages: [Self.messageListing(uid: 43, subject: "Replacement")],
            uidValidity: 200,
            nextPageToken: nil
        ))
        _ = try await backend.messages(in: inbox, pageToken: nil)
        let newBody = try await backend.body(for: "INBOX:43")

        #expect(oldBody.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) == "Old body.")
        #expect(newBody.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) == "New body.")
        #expect(await sourceRecorder.callCount == 2)
    }

    @Test("persisted UIDVALIDITY changes invalidate restored IMAP caches")
    func persistedUIDValidityChangesInvalidateRestoredIMAPCaches() async throws {
        let listingRecorder = MessageListingRecorder(page: IMAPMessageListingPage(
            messages: [Self.messageListing(uid: 43, subject: "Replacement")],
            uidValidity: 200,
            nextPageToken: nil
        ))
        let sourceRecorder = MessageSourceRecorder(rawMessage: """
        Content-Type: text/plain; charset=utf-8

        New body.
        """)
        let headerCache = InMemoryIMAPMailboxHeaderCache(snapshotsByFolderByAccount: [
            Self.account.id: [
                "INBOX": IMAPMailboxHeaderCacheSnapshot(
                    headers: [
                        MessageHeader(
                            id: "INBOX:43",
                            threadID: "<old-43@example.org>",
                            folderID: "INBOX",
                            from: Correspondent(email: "sender@example.org"),
                            to: [Correspondent(email: "person@example.org")],
                            cc: [],
                            bcc: [],
                            subject: "Old cached",
                            snippet: "",
                            date: Date(timeIntervalSince1970: 43),
                            isRead: false,
                            isFlagged: false,
                            hasAttachments: false
                        ),
                    ],
                    uidValidity: 100,
                    nextPageToken: nil,
                    firstPageHeaderIDs: ["INBOX:43"]
                ),
            ],
        ])
        let sourceCache = InMemoryIMAPMessageSourceCache()
        await sourceCache.setSource(
            IMAPMessageSource(
                uid: 43,
                rawMessage: """
                Content-Type: text/plain; charset=utf-8

                Old cached body.
                """
            ),
            accountID: Self.account.id,
            messageID: "INBOX:43"
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [
                IMAPFolderListing(
                    path: "INBOX",
                    displayName: "Inbox",
                    delimiter: "/",
                    flags: [],
                    role: .inbox
                ),
            ] },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await listingRecorder.listMessages(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            fetchMessageSource: { configuration, credential, folderID, uid in
                try await sourceRecorder.fetch(
                    configuration: configuration,
                    credential: credential,
                    folderID: folderID,
                    uid: uid
                )
            },
            headerCache: headerCache,
            sourceCache: sourceCache
        )
        try await backend.connect()
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)

        _ = try await backend.messages(in: inbox, pageToken: nil as String?)
        let refreshedSnapshot = try await waitForIMAPHeaderSnapshot(
            headerCache,
            accountID: Self.account.id,
            folderID: "INBOX"
        ) { snapshot in
            snapshot.uidValidity == 200
                && snapshot.headers.map(\.subject) == ["Replacement"]
        }
        let body = try await backend.body(for: "INBOX:43")

        #expect(body.plainText?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) == "New body.")
        #expect(await sourceRecorder.callCount == 1)
        #expect(refreshedSnapshot.uidValidity == 200)
        #expect(refreshedSnapshot.headers.map(\MessageHeader.subject) == ["Replacement"])
    }

    @Test("body cache persists fetched IMAP source across cache instances")
    func bodyCachePersistsFetchedIMAPSourceAcrossCacheInstances() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevIMAPMessageSourceCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let recorder = MessageSourceRecorder(rawMessage: """
        Content-Type: text/plain; charset=utf-8

        Persisted body.
        """)
        let firstCache = FileIMAPMessageSourceCache(rootDirectory: rootDirectory)
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
            sourceCache: firstCache
        )
        try await backend.connect()

        let body = try await backend.body(for: "INBOX:43")

        #expect(body.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) == "Persisted body.")
        #expect(await recorder.callCount == 1)

        let secondCache = FileIMAPMessageSourceCache(rootDirectory: rootDirectory)
        let cacheOnlyBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sourceCache: secondCache
        )
        try await cacheOnlyBackend.connect()

        let cachedBody = try await cacheOnlyBackend.body(for: "INBOX:43")

        #expect(cachedBody.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) == "Persisted body.")
        #expect(await recorder.callCount == 1)
    }

    @Test("body opens cached IMAP source while disconnected")
    func bodyOpensCachedIMAPSourceWhileDisconnected() async throws {
        let sourceCache = InMemoryIMAPMessageSourceCache()
        await sourceCache.setSource(
            IMAPMessageSource(uid: 43, rawMessage: """
            Content-Type: text/plain; charset=utf-8

            Offline cached body.
            """),
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

        let body = try await backend.body(for: "INBOX:43")

        #expect(body.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) == "Offline cached body.")
    }

    @Test("raw message source opens cached IMAP source while disconnected")
    func rawMessageSourceOpensCachedIMAPSourceWhileDisconnected() async throws {
        let sourceCache = InMemoryIMAPMessageSourceCache()
        await sourceCache.setSource(
            IMAPMessageSource(uid: 43, rawMessage: "Subject: Cached source\r\n\r\nOffline cached body."),
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

        let source = try await backend.rawSource(for: "INBOX:43")

        #expect(source == "Subject: Cached source\r\n\r\nOffline cached body.")
    }

    @Test("body cache miss while disconnected reports offline")
    func bodyCacheMissWhileDisconnectedReportsOffline() async throws {
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sourceCache: InMemoryIMAPMessageSourceCache()
        )

        await #expect(throws: MailBackendError.self) {
            _ = try await backend.body(for: "INBOX:43")
        }
    }

    @Test("attachment download reads cached IMAP source while disconnected")
    func attachmentDownloadReadsCachedIMAPSourceWhileDisconnected() async throws {
        let sourceCache = InMemoryIMAPMessageSourceCache()
        await sourceCache.setSource(
            IMAPMessageSource(uid: 43, rawMessage: """
            Content-Type: multipart/mixed; boundary="mixed-boundary"

            --mixed-boundary
            Content-Type: text/plain; charset=utf-8

            Offline body.
            --mixed-boundary
            Content-Type: application/pdf; name="cached.pdf"
            Content-Disposition: attachment; filename="cached.pdf"
            Content-Transfer-Encoding: base64

            SGVsbG8=
            --mixed-boundary--
            """),
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

        let body = try await backend.body(for: "INBOX:43")
        let attachment = try #require(body.attachments.first)
        let data = try await backend.downloadAttachment(attachment)

        #expect(attachment.name == "cached.pdf")
        #expect(data == Data("Hello".utf8))
    }

    @Test("file source cache clears only the requested account")
    func fileSourceCacheClearsOnlyTheRequestedAccount() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevIMAPMessageSourceCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let cache = FileIMAPMessageSourceCache(rootDirectory: rootDirectory)
        let accountID = "imap-smtp:person@example.org"
        let otherAccountID = "imap-smtp:other@example.org"
        let source = IMAPMessageSource(uid: 43, rawMessage: "Content-Type: text/plain\n\nCached body.")
        let otherSource = IMAPMessageSource(uid: 7, rawMessage: "Content-Type: text/plain\n\nOther cached body.")

        await cache.setSource(source, accountID: accountID, messageID: "INBOX:43")
        await cache.setSource(otherSource, accountID: otherAccountID, messageID: "INBOX:7")

        await cache.clear(accountID: accountID)

        #expect(await cache.source(accountID: accountID, messageID: "INBOX:43") == nil)
        #expect(await cache.source(accountID: otherAccountID, messageID: "INBOX:7") == otherSource)
    }

    @Test("file source cache prunes oldest account sources over byte budget")
    func fileSourceCachePrunesOldestAccountSourcesOverByteBudget() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevIMAPMessageSourceCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let cache = FileIMAPMessageSourceCache(
            rootDirectory: rootDirectory,
            maximumAccountSizeBytes: 12000
        )
        let accountID = "imap-smtp:person@example.org"
        let otherAccountID = "imap-smtp:other@example.org"
        let firstSource = IMAPMessageSource(uid: 1, rawMessage: String(repeating: "a", count: 5000))
        let secondSource = IMAPMessageSource(uid: 2, rawMessage: String(repeating: "b", count: 5000))
        let thirdSource = IMAPMessageSource(uid: 3, rawMessage: String(repeating: "c", count: 5000))
        let otherSource = IMAPMessageSource(uid: 4, rawMessage: String(repeating: "d", count: 5000))

        await cache.setSource(firstSource, accountID: accountID, messageID: "INBOX:1")
        await cache.setSource(secondSource, accountID: accountID, messageID: "INBOX:2")
        await cache.setSource(otherSource, accountID: otherAccountID, messageID: "INBOX:4")
        await cache.setSource(thirdSource, accountID: accountID, messageID: "INBOX:3")

        #expect(await cache.source(accountID: accountID, messageID: "INBOX:1") == nil)
        #expect(await cache.source(accountID: accountID, messageID: "INBOX:2") == secondSource)
        #expect(await cache.source(accountID: accountID, messageID: "INBOX:3") == thirdSource)
        #expect(await cache.source(accountID: otherAccountID, messageID: "INBOX:4") == otherSource)
        #expect(cache.sizeBytes(accountID: accountID) <= 12000)
    }

    @Test("attachment download uses cached IMAP source")
    func attachmentDownloadUsesCachedIMAPSource() async throws {
        let recorder = MessageSourceRecorder(rawMessage: """
        Content-Type: multipart/mixed; boundary="mixed-boundary"

        --mixed-boundary
        Content-Type: text/plain; charset=utf-8

        Receipt attached.
        --mixed-boundary
        Content-Type: application/pdf; name="receipt.pdf"
        Content-Disposition: attachment; filename="receipt.pdf"
        Content-Transfer-Encoding: base64

        SGVsbG8=
        --mixed-boundary--
        """)
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
        let body = try await backend.body(for: "INBOX:43")
        let attachment = try #require(body.attachments.first)

        let cacheOnlyBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sourceCache: sourceCache
        )
        try await cacheOnlyBackend.connect()

        let downloaded = try await cacheOnlyBackend.downloadAttachment(attachment)

        #expect(downloaded == Data("Hello".utf8))
        #expect(await recorder.callCount == 1)
    }

    @Test("body decodes quoted printable text with declared charsets")
    func bodyDecodesQuotedPrintableTextWithDeclaredCharsets() async throws {
        let recorder = MessageSourceRecorder(rawMessage: """
        Subject: Encoded receipt
        Content-Type: multipart/alternative; boundary="alt-boundary"

        --alt-boundary
        Content-Type: text/plain; charset=iso-8859-1
        Content-Transfer-Encoding: quoted-printable

        Kj=E6re=20Henrik=0AThis=20line=20continues=20=
        after=20a=20soft=20break.
        --alt-boundary
        Content-Type: text/html; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        <p>Kj=C3=A6re=20<strong>Henrik</strong></p>
        --alt-boundary--
        """)
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
            }
        )
        try await backend.connect()

        let body = try await backend.body(for: "INBOX:44")

        #expect(body.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) == """
        Kjære Henrik
        This line continues after a soft break.
        """)
        #expect(body.html?.trimmingCharacters(in: .whitespacesAndNewlines) == "<p>Kjære <strong>Henrik</strong></p>")
    }

    @Test("body preserves unencoded eight bit text bodies")
    func bodyPreservesUnencodedEightBitTextBodies() async throws {
        let recorder = MessageSourceRecorder(rawMessage: """
        Subject: Legacy receipt
        Content-Type: text/plain; charset=iso-8859-1
        Content-Transfer-Encoding: 8bit

        Kjære Henrik Øgård
        """)
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
            }
        )
        try await backend.connect()

        let body = try await backend.body(for: "INBOX:45")

        #expect(body.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) == "Kjære Henrik Øgård")
    }

    @Test("body unwraps flowed plain text")
    func bodyUnwrapsFlowedPlainText() async throws {
        let recorder = MessageSourceRecorder(rawMessage: """
        Subject: Flowed text
        Content-Type: text/plain; charset=utf-8; format=flowed
        Content-Transfer-Encoding: quoted-printable

        Hello Henrik,=20
        this message was wrapped=20
        by the sender.

        Second paragraph stays separate.
        """)
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
            }
        )
        try await backend.connect()

        let body = try await backend.body(for: "INBOX:46")

        #expect(body.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) == """
        Hello Henrik, this message was wrapped by the sender.

        Second paragraph stays separate.
        """)
    }

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

    private static let manageSieveServer = MailServerSettings(
        kind: .manageSieve,
        host: "sieve.example.org",
        port: 4190,
        tlsMode: .implicit,
        authentication: .password
    )

    private static let configurationWithManageSieve = IMAPAccountConfiguration(
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
        manageSieve: manageSieveServer,
        credentialID: "imap-smtp:person@example.org"
    )

    private static let credential = MailAccountCredential(
        incomingUsername: "person@example.org",
        outgoingUsername: "person@example.org",
        secret: "secret",
        authentication: .password
    )

    private static func outgoingDraft(
        id: String = "draft-1",
        to: [Correspondent] = [Correspondent(email: "recipient@example.org")],
        scheduledFor: Date? = nil
    ) -> Draft {
        Draft(
            id: id,
            to: to,
            subject: "Hello",
            htmlBody: "<p>Hello</p>",
            scheduledFor: scheduledFor
        )
    }

    private func expectNotFound(
        _ expectedID: String,
        performing operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected notFound(\(expectedID)).")
        } catch MailBackendError.notFound(let id) {
            #expect(id == expectedID)
        } catch {
            Issue.record("Expected notFound(\(expectedID)), got \(error).")
        }
    }

    private static func makeMutationQueue() throws -> UserDefaultsMutationQueue {
        let suiteName = "IMAPSMTPBackendTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsMutationQueue(defaults: defaults, storageKey: "q")
    }

    private static func clearScheduledSends() {
        UserDefaults.standard.removeObject(forKey: "scheduledSends.\(account.id)")
    }

    private static func messageListing(
        uid: Int,
        subject: String,
        isRead: Bool = false,
        isFlagged: Bool = false
    ) -> IMAPMessageListing {
        IMAPMessageListing(
            uid: uid,
            messageID: "<msg-\(uid)@example.org>",
            subject: subject,
            from: Correspondent(email: "sender@example.org"),
            to: [Correspondent(email: "person@example.org")],
            cc: [],
            bcc: [],
            date: Date(timeIntervalSince1970: TimeInterval(uid)),
            isRead: isRead,
            isFlagged: isFlagged,
            isAnswered: false
        )
    }
}

private actor DelayedSizeIMAPMessageSourceCache: IMAPMessageSourceCache {
    func source(accountID: BrevAccount.ID, messageID: MessageHeader.ID) -> IMAPMessageSource? {
        nil
    }

    func setSource(_ source: IMAPMessageSource, accountID: BrevAccount.ID, messageID: MessageHeader.ID) {}

    func removeSource(accountID: BrevAccount.ID, messageID: MessageHeader.ID) {}

    func removeSources(inFolder folderID: Folder.ID, accountID: BrevAccount.ID) {}

    func removeSources(
        inFolder folderID: Folder.ID,
        accountID: BrevAccount.ID,
        exceptMessageIDs: Set<MessageHeader.ID>
    ) {}

    func sizeBytes(accountID: BrevAccount.ID) async -> Int {
        try? await Task.sleep(nanoseconds: 500_000_000)
        return 1
    }

    func clear(accountID: BrevAccount.ID) {}
}

private actor FolderListingRecorder {
    private var sequence: [[IMAPFolderListing]]
    private var calls = 0

    init(listings: [IMAPFolderListing]) {
        sequence = [listings]
    }

    init(sequence: [[IMAPFolderListing]]) {
        self.sequence = sequence
    }

    var callCount: Int {
        calls
    }

    func listFolders(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential
    ) async throws -> [IMAPFolderListing] {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        calls += 1
        if sequence.count > 1 {
            return sequence.removeFirst()
        }
        return sequence.first ?? []
    }
}

private actor FolderMutationRecorder {
    enum Call: Equatable, Sendable {
        case create(folderID: String)
        case rename(folderID: String, newFolderID: String)
        case delete(folderID: String)
    }

    private var recordedCalls: [Call] = []

    var calls: [Call] {
        recordedCalls
    }

    func createFolder(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: String
    ) async throws {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        recordedCalls.append(.create(folderID: folderID))
    }

    func renameFolder(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: String,
        newFolderID: String
    ) async throws {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        recordedCalls.append(.rename(folderID: folderID, newFolderID: newFolderID))
    }

    func deleteFolder(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: String
    ) async throws {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        recordedCalls.append(.delete(folderID: folderID))
    }
}

private actor MessageListingRecorder {
    private var page: IMAPMessageListingPage
    private var sequence: [IMAPMessageListingPage]
    private var error: (any Error)?
    private var calls = 0
    private var folderIDs: [String] = []
    private var pageTokens: [String?] = []
    private var limits: [Int] = []
    private let firstCallDelayNanoseconds: UInt64?

    init(messages: [IMAPMessageListing], firstCallDelayNanoseconds: UInt64? = nil) {
        page = IMAPMessageListingPage(messages: messages, nextPageToken: "before:42")
        sequence = []
        self.firstCallDelayNanoseconds = firstCallDelayNanoseconds
    }

    init(page: IMAPMessageListingPage) {
        self.page = page
        sequence = []
        firstCallDelayNanoseconds = nil
    }

    init(sequence: [IMAPMessageListingPage]) {
        self.sequence = sequence
        page = sequence.first ?? IMAPMessageListingPage(messages: [])
        firstCallDelayNanoseconds = nil
    }

    var callCount: Int {
        calls
    }

    var requestedFolderIDs: [String] {
        folderIDs
    }

    var requestedPageTokens: [String?] {
        pageTokens
    }

    var requestedLimits: [Int] {
        limits
    }

    func setMessages(_ messages: [IMAPMessageListing], nextPageToken: String? = "before:42") {
        page = IMAPMessageListingPage(messages: messages, nextPageToken: nextPageToken)
        error = nil
    }

    func setPage(_ page: IMAPMessageListingPage) {
        self.page = page
        error = nil
    }

    func setError(_ error: any Error) {
        self.error = error
    }

    func waitUntilCallCount(
        _ expected: Int,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async throws {
        let intervalNanoseconds: UInt64 = 10_000_000
        let attempts = max(1, Int(timeoutNanoseconds / intervalNanoseconds))
        for _ in 0 ..< attempts {
            if calls >= expected { return }
            try await Task.sleep(nanoseconds: intervalNanoseconds)
        }
        throw IMAPEventTimeout.timedOut
    }

    func listMessages(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: String,
        pageToken: String?,
        limit: Int
    ) async throws -> IMAPMessageListingPage {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        calls += 1
        folderIDs.append(folderID)
        pageTokens.append(pageToken)
        limits.append(limit)
        if calls == 1, let firstCallDelayNanoseconds {
            try await Task.sleep(nanoseconds: firstCallDelayNanoseconds)
        }
        if let error {
            throw error
        }
        if !sequence.isEmpty {
            return sequence.removeFirst()
        }
        return page
    }
}

private actor LocalSearchIndexRecorder: MailLocalSearchIndex {
    struct HeaderPageRequest: Equatable, Sendable {
        let folderID: Folder.ID
        let pageToken: String?
    }

    struct SearchRequest: Equatable, Sendable {
        let query: SearchQuery
        let limit: Int
    }

    private struct HeaderPageKey: Hashable {
        let folderID: Folder.ID
        let pageToken: String?
    }

    private var headerPages: [HeaderPageKey: (headers: [MessageHeader], nextPageToken: String?)] = [:]
    private var rawMessages: [MessageHeader.ID: Data] = [:]
    private var indexSearchResults: [MessageHeader] = []
    private var recordedCachedHeaderRequests: [HeaderPageRequest] = []
    private var recordedCachedRawMessageRequests: [MessageHeader.ID] = []
    private var recordedSearchRequests: [SearchRequest] = []
    private var recordedStoredHeaderBatches: [[MessageHeader]] = []
    private var recordedStoredRawMessageIDs: [MessageHeader.ID] = []
    private var recordedDeletedMessageBatches: [[MessageHeader.ID]] = []
    private var recordedDeletedRawMessageBatches: [[MessageHeader.ID]] = []
    private var recordedDeletedRawMessageFolders: [Folder.ID] = []
    private var recordedClearedAccounts: [BrevAccount.ID] = []
    private var recordedClearedFolders: [Folder.ID] = []
    private var indexMetrics: LocalSearchIndexMetrics?
    private var clearAccountGate: AsyncGate?
    private var persistsStoredRawMessages = true
    private var nextHeaderStoreDelayNanoseconds: UInt64?

    var cachedHeaderRequests: [HeaderPageRequest] {
        recordedCachedHeaderRequests
    }

    var cachedRawMessageRequests: [MessageHeader.ID] {
        recordedCachedRawMessageRequests
    }

    var searchRequests: [SearchRequest] {
        recordedSearchRequests
    }

    var storedHeaderBatches: [[MessageHeader]] {
        recordedStoredHeaderBatches
    }

    var storedRawMessageIDs: [MessageHeader.ID] {
        recordedStoredRawMessageIDs
    }

    var deletedMessageBatches: [[MessageHeader.ID]] {
        recordedDeletedMessageBatches
    }

    var deletedRawMessageBatches: [[MessageHeader.ID]] {
        recordedDeletedRawMessageBatches
    }

    var deletedRawMessageFolders: [Folder.ID] {
        recordedDeletedRawMessageFolders
    }

    var clearedAccounts: [BrevAccount.ID] {
        recordedClearedAccounts
    }

    var clearedFolders: [Folder.ID] {
        recordedClearedFolders
    }

    func setHeaderPage(
        folderID: Folder.ID,
        pageToken: String?,
        headers: [MessageHeader],
        nextPageToken: String?
    ) {
        headerPages[HeaderPageKey(folderID: folderID, pageToken: pageToken)] = (
            headers: headers,
            nextPageToken: nextPageToken
        )
    }

    func setRawMessage(
        _ data: Data,
        for messageID: MessageHeader.ID
    ) {
        rawMessages[messageID] = data
    }

    func setSearchResults(_ results: [MessageHeader]) {
        indexSearchResults = results
    }

    func setMetrics(_ metrics: LocalSearchIndexMetrics?) {
        indexMetrics = metrics
    }

    func setPersistsStoredRawMessages(_ persistsStoredRawMessages: Bool) {
        self.persistsStoredRawMessages = persistsStoredRawMessages
    }

    func setClearAccountGate(_ gate: AsyncGate?) {
        clearAccountGate = gate
    }

    func delayNextHeaderStore(by nanoseconds: UInt64) {
        nextHeaderStoreDelayNanoseconds = nanoseconds
    }

    func cachedHeaders(
        for folder: Folder,
        account: BrevAccount,
        pageToken: String?
    ) async -> (headers: [MessageHeader], nextPageToken: String?)? {
        recordedCachedHeaderRequests.append(HeaderPageRequest(
            folderID: folder.id,
            pageToken: pageToken
        ))
        return headerPages[HeaderPageKey(folderID: folder.id, pageToken: pageToken)]
    }

    func cachedRawMessage(
        for messageID: MessageHeader.ID,
        account: BrevAccount
    ) async -> Data? {
        recordedCachedRawMessageRequests.append(messageID)
        return rawMessages[messageID]
    }

    func search(
        _ query: SearchQuery,
        account: BrevAccount,
        limit: Int
    ) async -> [MessageHeader] {
        recordedSearchRequests.append(SearchRequest(query: query, limit: limit))
        return Array(indexSearchResults.filter { query.matches($0) }.prefix(limit))
    }

    func storeHeaders(
        _ headers: [MessageHeader],
        account: BrevAccount
    ) async {
        if let delay = nextHeaderStoreDelayNanoseconds {
            nextHeaderStoreDelayNanoseconds = nil
            try? await Task.sleep(nanoseconds: delay)
        }
        recordedStoredHeaderBatches.append(headers)
    }

    func storeRawMessage(
        _ data: Data,
        for messageID: MessageHeader.ID,
        account: BrevAccount
    ) async {
        if persistsStoredRawMessages {
            rawMessages[messageID] = data
        }
        recordedStoredRawMessageIDs.append(messageID)
    }

    func deleteMessages(
        _ messageIDs: [MessageHeader.ID],
        account: BrevAccount
    ) async {
        recordedDeletedMessageBatches.append(messageIDs)
        for messageID in messageIDs {
            rawMessages.removeValue(forKey: messageID)
        }
    }

    func deleteRawMessages(
        _ messageIDs: [MessageHeader.ID],
        account: BrevAccount
    ) async {
        recordedDeletedRawMessageBatches.append(messageIDs)
        for messageID in messageIDs {
            rawMessages.removeValue(forKey: messageID)
        }
    }

    func deleteRawMessages(
        inFolder folderID: Folder.ID,
        account: BrevAccount
    ) async {
        recordedDeletedRawMessageFolders.append(folderID)
        rawMessages = rawMessages.filter { messageID, _ in
            !messageID.hasPrefix("\(folderID):")
        }
    }

    func deleteRawMessages(
        inFolder folderID: Folder.ID,
        except exceptMessageIDs: Set<MessageHeader.ID>,
        account: BrevAccount
    ) async {
        recordedDeletedRawMessageFolders.append(folderID)
        rawMessages = rawMessages.filter { messageID, _ in
            !messageID.hasPrefix("\(folderID):") || exceptMessageIDs.contains(messageID)
        }
    }

    func clearFolder(
        folderID: Folder.ID,
        account: BrevAccount
    ) async {
        recordedClearedFolders.append(folderID)
        headerPages = headerPages.filter { key, _ in key.folderID != folderID }
        rawMessages = rawMessages.filter { messageID, _ in
            !messageID.hasPrefix("\(folderID):")
        }
        indexSearchResults.removeAll { $0.folderID == folderID }
    }

    func clearAccount(_ account: BrevAccount) async {
        if let clearAccountGate {
            await clearAccountGate.enterAndWait()
        }
        recordedClearedAccounts.append(account.id)
        headerPages.removeAll()
        rawMessages.removeAll()
        indexSearchResults.removeAll()
    }

    func metrics(for account: BrevAccount) async -> LocalSearchIndexMetrics? {
        indexMetrics
    }
}

private actor BlockingMessageListingRecorder {
    private let page: IMAPMessageListingPage
    private var calls = 0
    private var isBlocked = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var blockedContinuation: CheckedContinuation<Void, any Error>?

    init(page: IMAPMessageListingPage) {
        self.page = page
    }

    var callCount: Int {
        calls
    }

    /// Suspends until `listMessages` is parked on its release continuation.
    ///
    /// This used to poll `isBlocked` on a 200ms budget, which is wall-clock time
    /// the polling task and the task driving `listMessages` have to share. Run
    /// alone that was ample; run inside the parallel suite it lost the race
    /// often enough to fail roughly two runs in three. `listMessages` now hands
    /// off directly, so the wait is decided by the handshake rather than by how
    /// busy the cooperative pool happens to be. The timeout is only a backstop
    /// against a genuine hang, and is generous because it no longer races.
    func waitUntilBlocked(timeoutNanoseconds: UInt64 = 5_000_000_000) async throws {
        if isBlocked { return }
        let timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            await self?.timeOutWaitUntilBlocked()
        }
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { continuation in
            blockedContinuation = continuation
        }
    }

    /// Actor isolation is what makes this safe: it and the hand-off in
    /// `listMessages` cannot both resume the same continuation.
    private func timeOutWaitUntilBlocked() {
        blockedContinuation?.resume(throwing: IMAPEventTimeout.timedOut)
        blockedContinuation = nil
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func listMessages(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: String,
        pageToken: String?,
        limit: Int
    ) async throws -> IMAPMessageListingPage {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        #expect(folderID == "INBOX")
        #expect(pageToken == nil)
        #expect(limit == 50)
        calls += 1
        isBlocked = true
        blockedContinuation?.resume()
        blockedContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        return page
    }
}

private enum IMAPEventTimeout: Error {
    case timedOut
}

private actor AsyncGate {
    private var entered = false
    private var released = false

    func enterAndWait() async {
        entered = true
        while !released {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func waitUntilEntered(timeoutNanoseconds: UInt64 = 1_000_000_000) async throws {
        let intervalNanoseconds: UInt64 = 10_000_000
        let attempts = max(1, Int(timeoutNanoseconds / intervalNanoseconds))
        for _ in 0 ..< attempts {
            if entered { return }
            try await Task.sleep(nanoseconds: intervalNanoseconds)
        }
        throw IMAPEventTimeout.timedOut
    }

    func release() {
        released = true
    }
}

private func value<T: Sendable>(
    from task: Task<T, any Error>,
    timeoutNanoseconds: UInt64 = 200_000_000
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await task.value
        }
        group.addTask {
            try await Task.sleep(nanoseconds: timeoutNanoseconds)
            throw IMAPEventTimeout.timedOut
        }

        let result = try await group.next()
        group.cancelAll()
        return try #require(result)
    }
}

private func waitForIMAPHeaderSnapshot(
    _ cache: any IMAPMailboxHeaderCache,
    accountID: BrevAccount.ID,
    folderID: Folder.ID,
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    matching predicate: @escaping @Sendable (IMAPMailboxHeaderCacheSnapshot) -> Bool
) async throws -> IMAPMailboxHeaderCacheSnapshot {
    let intervalNanoseconds: UInt64 = 10_000_000
    let attempts = max(1, Int(timeoutNanoseconds / intervalNanoseconds))
    for _ in 0 ..< attempts {
        if let snapshot = await cache.snapshot(accountID: accountID, folderID: folderID),
           predicate(snapshot) {
            return snapshot
        }
        try await Task.sleep(nanoseconds: intervalNanoseconds)
    }
    throw IMAPEventTimeout.timedOut
}

private func nextIMAPEvent(
    from stream: AsyncStream<MailEvent>,
    timeoutNanoseconds: UInt64 = 1_000_000_000
) async throws -> MailEvent? {
    try await withThrowingTaskGroup(of: MailEvent?.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: timeoutNanoseconds)
            throw IMAPEventTimeout.timedOut
        }

        let event = try await group.next()
        group.cancelAll()
        return event ?? nil
    }
}

/// Pull the next event that isn't a `.syncProgress` tick. The multi-folder
/// refresh loop interleaves determinate-progress events between the
/// per-folder `.folderRefreshed` events; tests that assert on the folder
/// events skip past the progress noise with this.
private func nextIMAPEventSkippingProgress(
    from stream: AsyncStream<MailEvent>,
    timeoutNanoseconds: UInt64 = 1_000_000_000
) async throws -> MailEvent? {
    while true {
        let event = try await nextIMAPEvent(from: stream, timeoutNanoseconds: timeoutNanoseconds)
        if case .syncProgress = event { continue }
        return event
    }
}

private func waitForSyncHealthError(
    from reporter: any SyncHealthReporting,
    sourceID: MailSourceID,
    timeoutNanoseconds: UInt64 = 1_000_000_000
) async throws -> AccountSyncHealth {
    let startedAt = Date()
    while Date().timeIntervalSince(startedAt) < Double(timeoutNanoseconds) / 1_000_000_000 {
        let health = await reporter.syncHealth(for: sourceID)
        if health.lastErrorDescription != nil {
            return health
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw IMAPEventTimeout.timedOut
}

private actor MessageSearchRecorder {
    private let messages: [String: [IMAPMessageListing]]
    private let appliesLimit: Bool
    private var folderIDs: [String] = []
    private var queries: [SearchQuery] = []
    private var limits: [Int] = []

    init(messages: [String: [IMAPMessageListing]], appliesLimit: Bool = false) {
        self.messages = messages
        self.appliesLimit = appliesLimit
    }

    var requestedFolderIDs: [String] {
        folderIDs
    }

    var requestedQueries: [SearchQuery] {
        queries
    }

    var requestedLimits: [Int] {
        limits
    }

    func searchMessages(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: String,
        query: SearchQuery,
        limit: Int
    ) async throws -> [IMAPMessageListing] {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        folderIDs.append(folderID)
        queries.append(query)
        limits.append(limit)
        let folderMessages = messages[folderID] ?? []
        guard appliesLimit else { return folderMessages }
        return Array(folderMessages.suffix(limit))
    }
}

private actor MessageSearchPageRecorder {
    private let pages: [String?: IMAPMessageListingPage]
    private var pageTokens: [String?] = []
    private var limits: [Int] = []

    init(pages: [String?: IMAPMessageListingPage]) {
        self.pages = pages
    }

    var requestedPageTokens: [String?] {
        pageTokens
    }

    var requestedLimits: [Int] {
        limits
    }

    func searchPage(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: String,
        query: SearchQuery,
        pageToken: String?,
        limit: Int
    ) async throws -> IMAPMessageListingPage {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        #expect(folderID == "INBOX")
        #expect(query.hasAttachments == nil)
        pageTokens.append(pageToken)
        limits.append(limit)
        guard let page = pages[pageToken] else {
            throw IMAPClientError.malformedResponse("unexpected page token")
        }
        return page
    }
}

private actor MessageSourceRecorder {
    private let rawMessage: String
    private var calls = 0
    private var folderIDs: [String] = []
    private var uids: [Int] = []

    init(rawMessage: String) {
        self.rawMessage = rawMessage
    }

    var callCount: Int {
        calls
    }

    var requestedFolderIDs: [String] {
        folderIDs
    }

    var requestedUIDs: [Int] {
        uids
    }

    func fetch(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: String,
        uid: Int
    ) async throws -> IMAPMessageSource {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        calls += 1
        folderIDs.append(folderID)
        uids.append(uid)
        return IMAPMessageSource(uid: uid, rawMessage: rawMessage)
    }
}

private actor MessageBodyRecorder {
    private var calls = 0

    var callCount: Int {
        calls
    }

    func waitUntilCallCount(
        _ expected: Int,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async throws {
        let intervalNanoseconds: UInt64 = 10_000_000
        let attempts = max(1, Int(timeoutNanoseconds / intervalNanoseconds))
        for _ in 0 ..< attempts {
            if calls >= expected { return }
            try await Task.sleep(nanoseconds: intervalNanoseconds)
        }
        throw IMAPEventTimeout.timedOut
    }

    func recordFetch(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: String,
        uid: Int
    ) -> MessageBody {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        #expect(folderID == "INBOX" || folderID == "Drafts")
        #expect(uid > 0)
        calls += 1
        return MessageBody(
            messageID: "\(folderID):\(uid)",
            plainText: "Body"
        )
    }
}

private actor CancellableDraftBodyRecorder {
    private var didStartDraftFetch = false

    func waitUntilDraftFetchStarts(
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async throws {
        let intervalNanoseconds: UInt64 = 10_000_000
        let attempts = max(1, Int(timeoutNanoseconds / intervalNanoseconds))
        for _ in 0 ..< attempts {
            if didStartDraftFetch { return }
            try await Task.sleep(nanoseconds: intervalNanoseconds)
        }
        throw IMAPEventTimeout.timedOut
    }

    func fetch(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: String,
        uid: Int
    ) async throws -> MessageBody {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        if folderID == "Drafts" {
            didStartDraftFetch = true
            try await Task.sleep(nanoseconds: 5_000_000_000)
        }
        return MessageBody(messageID: "\(folderID):\(uid)", plainText: "Body")
    }
}

private actor DraftConflictRecorder: IMAPDraftStagingStore {
    private var draftsByID: [BrevAccount.ID: [Draft.ID: Draft]] = [:]
    private var conflictIDs: [Draft.ID] = []

    var conflictDraftIDs: [Draft.ID] {
        conflictIDs
    }

    func draft(accountID: BrevAccount.ID, draftID: Draft.ID) -> Draft? {
        draftsByID[accountID]?[draftID]
    }

    func setDraft(_ draft: Draft, accountID: BrevAccount.ID) {
        draftsByID[accountID, default: [:]][draft.id] = draft
        if let remoteID = draft.remoteID {
            draftsByID[accountID, default: [:]][remoteID] = draft
        }
        if draft.id.contains("-conflict-") {
            conflictIDs.append(draft.id)
        }
    }

    func attachment(
        accountID: BrevAccount.ID,
        attachmentID: String
    ) -> IMAPDraftStagedAttachment? {
        nil
    }

    func setAttachment(
        _ attachment: IMAPDraftStagedAttachment,
        accountID: BrevAccount.ID
    ) {}

    func removeDraft(accountID: BrevAccount.ID, draftID: Draft.ID) {
        draftsByID[accountID]?.removeValue(forKey: draftID)
    }

    func clear(accountID: BrevAccount.ID) {
        draftsByID.removeValue(forKey: accountID)
    }
}

private actor MessageSourceSequenceRecorder {
    private var rawMessages: [String]
    private var calls = 0

    init(rawMessages: [String]) {
        self.rawMessages = rawMessages
    }

    var callCount: Int {
        calls
    }

    func fetch(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: String,
        uid: Int
    ) async throws -> IMAPMessageSource {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        #expect(folderID == "INBOX")
        calls += 1
        guard !rawMessages.isEmpty else {
            throw MailBackendError.notFound(id: "\(folderID):\(uid)")
        }
        return IMAPMessageSource(uid: uid, rawMessage: rawMessages.removeFirst())
    }
}

private actor MessageSourceByUIDRecorder {
    private let rawMessagesByUID: [Int: String]
    private var uids: [Int] = []

    init(rawMessagesByUID: [Int: String]) {
        self.rawMessagesByUID = rawMessagesByUID
    }

    var requestedUIDs: [Int] {
        uids
    }

    func fetch(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: String,
        uid: Int
    ) async throws -> IMAPMessageSource {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        #expect(folderID == "INBOX")
        uids.append(uid)
        guard let rawMessage = rawMessagesByUID[uid] else {
            throw MailBackendError.notFound(id: "\(folderID):\(uid)")
        }
        return IMAPMessageSource(uid: uid, rawMessage: rawMessage)
    }
}

private actor IMAPIdleEventRecorder {
    private var continuation: AsyncThrowingStream<IMAPIdleEvent, any Error>.Continuation?
    private var subscriptionWaiter: CheckedContinuation<Void, Never>?
    private var subscriptions = 0

    func stream() -> AsyncThrowingStream<IMAPIdleEvent, any Error> {
        AsyncThrowingStream { continuation in
            install(continuation)
        }
    }

    func waitUntilSubscribed() async throws {
        if continuation != nil { return }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    Task { await self.setSubscriptionWaiter(continuation) }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                throw IMAPEventTimeout.timedOut
            }
            try await group.next()
            group.cancelAll()
        }
    }

    func waitUntilSubscriptionCount(_ count: Int) async throws {
        let startedAt = Date()
        while subscriptions < count {
            guard Date().timeIntervalSince(startedAt) < 1 else {
                throw IMAPEventTimeout.timedOut
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func emit(_ event: IMAPIdleEvent) {
        continuation?.yield(event)
    }

    func fail(_ error: any Error) {
        continuation?.finish(throwing: error)
        continuation = nil
    }

    func finish() {
        continuation?.finish()
    }

    private func install(_ continuation: AsyncThrowingStream<IMAPIdleEvent, any Error>.Continuation) {
        self.continuation = continuation
        subscriptions += 1
        subscriptionWaiter?.resume()
        subscriptionWaiter = nil
    }

    private func setSubscriptionWaiter(_ waiter: CheckedContinuation<Void, Never>) {
        if continuation != nil {
            waiter.resume()
        } else {
            subscriptionWaiter = waiter
        }
    }
}

private actor IMAPIdleFolderSubscriptionRecorder {
    private var folderIDs: [String] = []

    func record(_ folderID: String) {
        folderIDs.append(folderID)
    }

    func waitUntilFolderIDs(
        _ expectedFolderIDs: [String],
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async throws {
        let startedAt = Date()
        while folderIDs != expectedFolderIDs {
            guard Date().timeIntervalSince(startedAt) < Double(timeoutNanoseconds) / 1_000_000_000 else {
                throw IMAPEventTimeout.timedOut
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

/// IDLE event recorder that keeps a separate continuation per folder, so a test
/// can drive INBOX and the active folder independently (the shared
/// `IMAPIdleEventRecorder` keeps only the most recent continuation).
private actor PerFolderIdleEventRecorder {
    private var continuations: [String: AsyncThrowingStream<IMAPIdleEvent, any Error>.Continuation] = [:]

    func stream(for folderID: String) -> AsyncThrowingStream<IMAPIdleEvent, any Error> {
        AsyncThrowingStream { continuation in
            install(folderID: folderID, continuation: continuation)
        }
    }

    func emit(_ event: IMAPIdleEvent, to folderID: String) {
        continuations[folderID]?.yield(event)
    }

    func waitUntilSubscribed(
        _ folderID: String,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async throws {
        let startedAt = Date()
        while continuations[folderID] == nil {
            guard Date().timeIntervalSince(startedAt) < Double(timeoutNanoseconds) / 1_000_000_000 else {
                throw IMAPEventTimeout.timedOut
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func finishAll() {
        for continuation in continuations.values {
            continuation.finish()
        }
    }

    private func install(
        folderID: String,
        continuation: AsyncThrowingStream<IMAPIdleEvent, any Error>.Continuation
    ) {
        continuations[folderID] = continuation
    }
}

private actor AutoFailingIMAPIdleEventRecorder {
    private var subscriptions = 0

    var subscriptionCount: Int {
        subscriptions
    }

    func stream() -> AsyncThrowingStream<IMAPIdleEvent, any Error> {
        AsyncThrowingStream { continuation in
            subscriptions += 1
            continuation.finish(throwing: IMAPClientError.transport("Idle dropped"))
        }
    }

    func waitUntilSubscriptionCount(
        _ count: Int,
        timeoutNanoseconds: UInt64 = 5_000_000_000
    ) async throws {
        let startedAt = Date()
        while subscriptions < count {
            guard Date().timeIntervalSince(startedAt) < Double(timeoutNanoseconds) / 1_000_000_000 else {
                throw IMAPEventTimeout.timedOut
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private actor OAuthRefreshingIMAPIdleEventRecorder {
    private var continuations: [AsyncThrowingStream<IMAPIdleEvent, any Error>.Continuation] = []
    private var recordedCredentials: [MailAccountCredential] = []
    private let failure: (any Error)?

    init(failure: (any Error)? = nil) {
        self.failure = failure
    }

    var credentials: [MailAccountCredential] {
        recordedCredentials
    }

    var subscriptionCount: Int {
        recordedCredentials.count
    }

    var refreshingSubscriptionCount: Int {
        max(0, recordedCredentials.count - 1)
    }

    func stream(
        credential: MailAccountCredential
    ) -> AsyncThrowingStream<IMAPIdleEvent, any Error> {
        AsyncThrowingStream { continuation in
            recordedCredentials.append(credential)
            if recordedCredentials.count == 1 {
                continuation.finish(throwing: IMAPClientError.authenticationFailed("expired token"))
            } else if failure != nil {
                continuation.finish(throwing: IMAPClientError.authenticationFailed("expired token"))
            } else {
                continuations.append(continuation)
            }
        }
    }

    func waitUntilSubscriptionCount(
        _ count: Int,
        timeoutNanoseconds: UInt64 = 5_000_000_000
    ) async throws {
        let startedAt = Date()
        while recordedCredentials.count < count {
            guard Date().timeIntervalSince(startedAt) < Double(timeoutNanoseconds) / 1_000_000_000 else {
                throw IMAPEventTimeout.timedOut
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func emit(_ event: IMAPIdleEvent) {
        continuations.last?.yield(event)
    }

    func finish() {
        continuations.forEach { $0.finish() }
    }
}

private actor OAuthRefreshCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

private actor MessageFlagRecorder {
    struct Call: Equatable, Sendable {
        let folderID: String
        let uids: [Int]
        let flag: IMAPSystemFlag
        let isEnabled: Bool
    }

    private var recordedCalls: [Call] = []
    private var error: (any Error)?

    var calls: [Call] {
        recordedCalls
    }

    func setError(_ error: any Error) {
        self.error = error
    }

    func setMessageFlag(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: String,
        uids: [Int],
        flag: IMAPSystemFlag,
        isEnabled: Bool
    ) async throws {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        recordedCalls.append(Call(
            folderID: folderID,
            uids: uids,
            flag: flag,
            isEnabled: isEnabled
        ))
        if let error {
            throw error
        }
    }
}

private actor MessageKeywordRecorder {
    struct Call: Equatable, Sendable {
        let folderID: String
        let uids: [Int]
        let keyword: IMAPMessageKeyword
        let isEnabled: Bool
    }

    private var recordedCalls: [Call] = []

    var calls: [Call] {
        recordedCalls
    }

    func setMessageKeyword(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: String,
        uids: [Int],
        keyword: IMAPMessageKeyword,
        isEnabled: Bool
    ) async throws {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        recordedCalls.append(Call(
            folderID: folderID,
            uids: uids,
            keyword: keyword,
            isEnabled: isEnabled
        ))
    }
}

/// Counts how many times the injected SMTP send operation is invoked, so a test
/// can assert that a future-scheduled offline send is NOT delivered on reconnect.
private actor OfflineSendReplayCallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private actor MessageMoveRecorder {
    struct Call: Equatable, Sendable {
        let sourceFolderID: String
        let uids: [Int]
        let destinationFolderID: String
    }

    private var recordedCalls: [Call] = []

    var calls: [Call] {
        recordedCalls
    }

    func moveMessages(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        sourceFolderID: String,
        uids: [Int],
        destinationFolderID: String
    ) async throws {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        recordedCalls.append(Call(
            sourceFolderID: sourceFolderID,
            uids: uids,
            destinationFolderID: destinationFolderID
        ))
    }
}

private actor MessagePermanentDeleteRecorder {
    struct Call: Equatable, Sendable {
        let folderID: String
        let uids: [Int]
    }

    private var recordedCalls: [Call] = []

    var calls: [Call] {
        recordedCalls
    }

    func permanentlyDeleteMessages(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: String,
        uids: [Int]
    ) async throws {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        recordedCalls.append(Call(folderID: folderID, uids: uids))
    }
}

private actor MessageSendRecorder {
    struct Call: Equatable, Sendable {
        let submission: SMTPMessageSubmission
    }

    private var recordedCalls: [Call] = []

    var calls: [Call] {
        recordedCalls
    }

    func sendMessage(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        submission: SMTPMessageSubmission
    ) async throws {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.outgoingUsername == "person@example.org")
        recordedCalls.append(Call(submission: submission))
    }

    func waitUntilCallCount(
        _ expected: Int,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async throws {
        let intervalNanoseconds: UInt64 = 10_000_000
        let attempts = max(1, Int(timeoutNanoseconds / intervalNanoseconds))
        for _ in 0 ..< attempts {
            if recordedCalls.count >= expected { return }
            try await Task.sleep(nanoseconds: intervalNanoseconds)
        }
        throw IMAPEventTimeout.timedOut
    }
}

private actor OAuthSendCredentialRecorder {
    private(set) var credentials: [MailAccountCredential] = []
    private(set) var refreshCount = 0

    func record(_ credential: MailAccountCredential) {
        credentials.append(credential)
    }

    func recordRefresh() {
        refreshCount += 1
    }
}

private actor MessageAppendRecorder {
    struct Call: Equatable, Sendable {
        let folderID: String
        let messageData: Data
        let flags: Set<IMAPSystemFlag>
    }

    private var recordedCalls: [Call] = []

    var calls: [Call] {
        recordedCalls
    }

    func appendMessage(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: String,
        messageData: Data,
        flags: Set<IMAPSystemFlag>
    ) async throws {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        recordedCalls.append(Call(
            folderID: folderID,
            messageData: messageData,
            flags: flags
        ))
    }
}

private actor DraftAppendRecorder {
    struct Call: Equatable, Sendable {
        let folderID: String
        let messageData: Data
        let flags: Set<IMAPSystemFlag>
    }

    private var recordedCalls: [Call] = []
    private var uids: [Int]

    init(uids: [Int]) {
        self.uids = uids
    }

    var calls: [Call] {
        recordedCalls
    }

    func appendDraftMessage(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: String,
        messageData: Data,
        flags: Set<IMAPSystemFlag>
    ) async throws -> Int {
        #expect(configuration.accountID == "imap-smtp:person@example.org")
        #expect(credential.incomingUsername == "person@example.org")
        recordedCalls.append(Call(
            folderID: folderID,
            messageData: messageData,
            flags: flags
        ))
        return uids.removeFirst()
    }
}

/// Scheduled-send delivery is backed by a process-global `UserDefaults` key
/// (`scheduledSends.<accountID>`) and every `connect()` triggers a delivery
/// pass. These tests are therefore serialized and use a dedicated account id so
/// other suites' parallel `connect()` calls can never claim their entries.
@Suite("IMAP SMTP scheduled send", .serialized)
struct IMAPSMTPScheduledSendTests {
    private static let account = BrevAccount(
        id: "imap-smtp:scheduled@example.org",
        displayName: "Scheduled",
        emailAddress: "scheduled@example.org"
    )

    private static let configuration = IMAPAccountConfiguration(
        accountID: account.id,
        emailAddress: "scheduled@example.org",
        displayName: "Scheduled",
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
        credentialID: account.id
    )

    private static let credential = MailAccountCredential(
        incomingUsername: "scheduled@example.org",
        outgoingUsername: "scheduled@example.org",
        secret: "secret",
        authentication: .password
    )

    private static func outgoingDraft(id: String, scheduledFor: Date?) -> Draft {
        Draft(
            id: id,
            to: [Correspondent(email: "recipient@example.org")],
            subject: "Hello",
            htmlBody: "<p>Hello</p>",
            scheduledFor: scheduledFor
        )
    }

    private static func clearScheduledSends() {
        UserDefaults.standard.removeObject(forKey: "scheduledSends.\(account.id)")
    }

    /// Polls `condition` until it holds or ~2s elapses. Scheduled-send delivery
    /// removes the schedule entry and staged draft *after* the SMTP send returns
    /// (`performImmediateSend` sends first, then clears state), so a test that
    /// gates only on the send-call count can observe the mid-delivery window.
    /// Waiting on the terminal state instead makes the assertions deterministic.
    private static func waitUntil(_ condition: @Sendable () async -> Bool) async throws {
        for _ in 0 ..< 200 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @Test("due scheduled send is delivered when backend reconnects")
    func dueScheduledSendIsDeliveredWhenBackendReconnects() async throws {
        Self.clearScheduledSends()
        defer { Self.clearScheduledSends() }
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevScheduledSendReconnect-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let draftStore = FileIMAPDraftStagingStore(rootDirectory: rootDirectory)
        let firstBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            draftStagingStore: draftStore
        )
        try await firstBackend.connect()
        _ = try await firstBackend.send(draft: Self.outgoingDraft(
            id: "scheduled-reconnect",
            scheduledFor: Date(timeIntervalSinceNow: -60)
        ))
        await firstBackend.disconnect()

        let recorder = ScheduledSendOutcomeRecorder(succeeds: true)
        let restoredBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { configuration, credential, submission in
                try await recorder.sendMessage(
                    configuration: configuration,
                    credential: credential,
                    submission: submission
                )
            },
            draftStagingStore: draftStore
        )
        try await restoredBackend.connect()
        restoredBackend.startDeferredStartupWork()
        defer { Task { await restoredBackend.disconnect() } }

        // Delivery clears the schedule entry and staged draft *after* the SMTP
        // send returns, so wait on that terminal state rather than the send-call
        // count (which fires mid-delivery, before cleanup) to avoid a race.
        try await Self.waitUntil {
            let draftCleared = await draftStore.draft(
                accountID: Self.account.id, draftID: "scheduled-reconnect"
            ) == nil
            return ScheduledSendStore().entries(accountID: Self.account.id).isEmpty && draftCleared
        }

        #expect(ScheduledSendStore().entries(accountID: Self.account.id).isEmpty)
        #expect(await draftStore.draft(accountID: Self.account.id, draftID: "scheduled-reconnect") == nil)
    }

    @Test("failed due scheduled send remains queued for next reconnect")
    func failedDueScheduledSendRemainsQueuedForNextReconnect() async throws {
        Self.clearScheduledSends()
        defer { Self.clearScheduledSends() }
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevScheduledSendRetry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let draftStore = FileIMAPDraftStagingStore(rootDirectory: rootDirectory)
        let firstBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            draftStagingStore: draftStore
        )
        try await firstBackend.connect()
        _ = try await firstBackend.send(draft: Self.outgoingDraft(
            id: "scheduled-retry",
            scheduledFor: Date(timeIntervalSinceNow: -60)
        ))
        await firstBackend.disconnect()

        let failingRecorder = ScheduledSendOutcomeRecorder(succeeds: false)
        let failingBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { configuration, credential, submission in
                try await failingRecorder.sendMessage(
                    configuration: configuration,
                    credential: credential,
                    submission: submission
                )
            },
            draftStagingStore: draftStore
        )
        try await failingBackend.connect()
        failingBackend.startDeferredStartupWork()
        try await failingRecorder.waitUntilCallCount(1)
        await failingBackend.disconnect()

        #expect(ScheduledSendStore().dueEntries(
            accountID: Self.account.id,
            before: Date()
        ).map(\.draftID) == ["scheduled-retry"])

        let successRecorder = ScheduledSendOutcomeRecorder(succeeds: true)
        let successBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { configuration, credential, submission in
                try await successRecorder.sendMessage(
                    configuration: configuration,
                    credential: credential,
                    submission: submission
                )
            },
            draftStagingStore: draftStore
        )
        try await successBackend.connect()
        successBackend.startDeferredStartupWork()
        defer { Task { await successBackend.disconnect() } }

        // Same terminal-state wait as above: the entry is removed only after the
        // forced retry's SMTP send returns, not when the send call is counted.
        try await Self.waitUntil {
            ScheduledSendStore().entries(accountID: Self.account.id).isEmpty
        }

        #expect(ScheduledSendStore().entries(accountID: Self.account.id).isEmpty)
    }

    @Test("ambiguous scheduled delivery becomes a conflict without retrying")
    func ambiguousScheduledDeliveryBecomesConflictWithoutRetrying() async throws {
        Self.clearScheduledSends()
        defer { Self.clearScheduledSends() }
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevScheduledSendUnknown-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let draftStore = FileIMAPDraftStagingStore(rootDirectory: rootDirectory)
        let firstBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            draftStagingStore: draftStore
        )
        try await firstBackend.connect()
        _ = try await firstBackend.send(draft: Self.outgoingDraft(
            id: "scheduled-unknown",
            scheduledFor: Date(timeIntervalSinceNow: -60)
        ))
        await firstBackend.disconnect()

        let defaults = try #require(UserDefaults(suiteName: "BrevScheduledSendUnknown.\(UUID().uuidString)"))
        let conflictStore = UserDefaultsMutationConflictStore(
            defaults: defaults,
            storageKey: "conflicts"
        )
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { _, _, _ in
                throw SMTPClientError.deliveryOutcomeUnknown(
                    underlying: "Timed out waiting for SMTP DATA response."
                )
            },
            draftStagingStore: draftStore,
            offlineMutationConflictStore: conflictStore
        )
        try await backend.connect()
        let service = try #require(backend.extensionService(ScheduledSendManaging.self))
        await service.deliverDueScheduledSends()

        #expect(ScheduledSendStore().entries(accountID: Self.account.id).isEmpty)
        #expect(await draftStore.draft(
            accountID: Self.account.id,
            draftID: "scheduled-unknown"
        ) != nil)
        let conflicts = try await conflictStore.conflicts()
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.mutation.kind == .sendStagedDraft(stagedDraftID: "scheduled-unknown"))
        #expect(conflicts.first?.message.contains("Check Sent") == true)
    }

    @Test("orphaned schedule entry with no staged draft is pruned on delivery")
    func orphanedScheduleEntryIsPrunedOnDelivery() async throws {
        Self.clearScheduledSends()
        defer { Self.clearScheduledSends() }

        // Register a due schedule entry with no corresponding staged draft.
        let store = ScheduledSendStore()
        store.add(
            entry: ScheduledDraftEntry(
                draftID: "orphan",
                scheduledFor: Date(timeIntervalSinceNow: -60)
            ),
            accountID: Self.account.id
        )

        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevScheduledSendOrphan-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let draftStore = FileIMAPDraftStagingStore(rootDirectory: rootDirectory)

        let recorder = ScheduledSendOutcomeRecorder(succeeds: true)
        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { configuration, credential, submission in
                try await recorder.sendMessage(
                    configuration: configuration,
                    credential: credential,
                    submission: submission
                )
            },
            draftStagingStore: draftStore
        )
        try await backend.connect()
        backend.startDeferredStartupWork()
        defer { Task { await backend.disconnect() } }

        // The orphan can never be sent, so it must be removed rather than
        // re-read on every poll tick — wait until the entry disappears.
        for _ in 0 ..< 100 {
            if ScheduledSendStore().entries(accountID: Self.account.id).isEmpty { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(ScheduledSendStore().entries(accountID: Self.account.id).isEmpty)
    }

    @Test("claim lease and failure backoff gate non-forced re-claims")
    func claimLeaseAndFailureBackoffGateReclaims() async throws {
        Self.clearScheduledSends()
        defer { Self.clearScheduledSends() }
        let store = ScheduledSendStore()
        let now = Date()
        store.add(
            entry: ScheduledDraftEntry(draftID: "draft-1", scheduledFor: now.addingTimeInterval(-60)),
            accountID: Self.account.id
        )

        // First claim takes the entry and stamps a lease.
        let firstClaim = store.claimDueEntries(
            accountID: Self.account.id, before: now, lease: 120
        )
        #expect(firstClaim.map(\.draftID) == ["draft-1"])

        // A second non-forced claim inside the lease window gets nothing...
        #expect(store.claimDueEntries(accountID: Self.account.id, before: now, lease: 120).isEmpty)
        // ...but a forced claim (an explicit reconnect) ignores the lease.
        #expect(store.claimDueEntries(
            accountID: Self.account.id, before: now, lease: 120, force: true
        ).map(\.draftID) == ["draft-1"])

        // After a recorded failure, the entry is gated until nextAttemptAt...
        store.recordSendFailure(
            draftID: "draft-1", accountID: Self.account.id, now: now, baseInterval: 60, maxInterval: 3600
        )
        #expect(store.claimDueEntries(
            accountID: Self.account.id, before: now.addingTimeInterval(30), lease: 120
        ).isEmpty)
        // ...yet a forced claim still retries immediately.
        #expect(store.claimDueEntries(
            accountID: Self.account.id, before: now.addingTimeInterval(30), lease: 120, force: true
        ).map(\.draftID) == ["draft-1"])
        // And once the backoff elapses, an ordinary claim succeeds again.
        #expect(store.claimDueEntries(
            accountID: Self.account.id, before: now.addingTimeInterval(3600), lease: 120
        ).map(\.draftID) == ["draft-1"])
    }

    @Test("ScheduledSendManaging reports pending entries so the app can warn before quitting")
    func scheduledSendManagingReportsPendingEntries() async throws {
        Self.clearScheduledSends()
        defer { Self.clearScheduledSends() }
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevScheduledSendPending-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let backend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            draftStagingStore: FileIMAPDraftStagingStore(rootDirectory: rootDirectory)
        )
        try await backend.connect()
        defer { Task { await backend.disconnect() } }

        let service = try #require(backend.extensionService(ScheduledSendManaging.self))
        #expect(service.pendingScheduledSends().isEmpty)

        let dueDate = Date(timeIntervalSinceNow: 3600)
        _ = try await backend.send(draft: Self.outgoingDraft(id: "scheduled-pending", scheduledFor: dueDate))

        let pending = service.pendingScheduledSends()
        #expect(pending.map(\.draftID) == ["scheduled-pending"])
        #expect(pending.first.map { abs($0.scheduledFor.timeIntervalSince(dueDate)) < 1 } == true)
    }

    @Test("ScheduledSendManaging delivers overdue entries on demand without the poller")
    func scheduledSendManagingDeliversOverdueEntriesOnDemand() async throws {
        Self.clearScheduledSends()
        defer { Self.clearScheduledSends() }
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevScheduledSendOnDemand-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let draftStore = FileIMAPDraftStagingStore(rootDirectory: rootDirectory)
        let firstBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            draftStagingStore: draftStore
        )
        try await firstBackend.connect()
        _ = try await firstBackend.send(draft: Self.outgoingDraft(
            id: "scheduled-on-demand",
            scheduledFor: Date(timeIntervalSinceNow: -60)
        ))
        await firstBackend.disconnect()

        let recorder = ScheduledSendOutcomeRecorder(succeeds: true)
        let restoredBackend = IMAPSMTPBackend(
            account: Self.account,
            configuration: Self.configuration,
            credential: Self.credential,
            listFolders: { _, _ in [] },
            sendMessage: { configuration, credential, submission in
                try await recorder.sendMessage(
                    configuration: configuration,
                    credential: credential,
                    submission: submission
                )
            },
            draftStagingStore: draftStore
        )
        // Connect only — deliberately no `startDeferredStartupWork()`, so the
        // 30s poller never starts. The overdue entry must still be delivered
        // when a background refresh asks for it explicitly.
        try await restoredBackend.connect()
        defer { Task { await restoredBackend.disconnect() } }

        let service = try #require(restoredBackend.extensionService(ScheduledSendManaging.self))
        #expect(service.pendingScheduledSends().map(\.draftID) == ["scheduled-on-demand"])

        await service.deliverDueScheduledSends()

        #expect(service.pendingScheduledSends().isEmpty)
        #expect(ScheduledSendStore().entries(accountID: Self.account.id).isEmpty)
        #expect(await draftStore.draft(accountID: Self.account.id, draftID: "scheduled-on-demand") == nil)
    }
}

/// Records scheduled-send SMTP submissions, optionally failing the send to
/// exercise the retry/backoff path. Unlike the shared recorders it doesn't
/// assert a hard-coded account id, so the scheduled-send suite can use an
/// isolated account.
private actor ScheduledSendOutcomeRecorder {
    private let succeeds: Bool
    private var calls = 0

    init(succeeds: Bool) {
        self.succeeds = succeeds
    }

    func sendMessage(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        submission: SMTPMessageSubmission
    ) async throws -> SendResult {
        #expect(!submission.recipientEmails.isEmpty)
        calls += 1
        if !succeeds {
            throw SMTPClientError.transport("offline")
        }
        return SendResult(sentMessageID: "sent-scheduled")
    }

    func waitUntilCallCount(
        _ expected: Int,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async throws {
        let intervalNanoseconds: UInt64 = 10_000_000
        let attempts = max(1, Int(timeoutNanoseconds / intervalNanoseconds))
        for _ in 0 ..< attempts {
            if calls >= expected { return }
            try await Task.sleep(nanoseconds: intervalNanoseconds)
        }
        throw IMAPEventTimeout.timedOut
    }
}

private actor ManageSieveRuleSyncRecorder {
    struct Call: Sendable, Hashable {
        let configuration: IMAPAccountConfiguration
        let credential: MailAccountCredential
        let rules: [ServerRule]
        let scriptName: String
    }

    private(set) var calls: [Call] = []

    func sync(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        rules: [ServerRule],
        scriptName: String
    ) async throws -> SieveScriptPlan {
        calls.append(Call(
            configuration: configuration,
            credential: credential,
            rules: rules,
            scriptName: scriptName
        ))
        return SieveScriptRenderer.renderBrevOwnedScript(
            rules: rules,
            scriptName: scriptName
        )
    }
}

@Suite("Offline mutation replay guard")
struct OfflineMutationReplayGuardTests {
    @Test("the replay guard admits one holder at a time and is re-acquirable after release")
    func replayGuardSerializesConcurrentReplays() async {
        let state = IMAPSMTPBackendState()

        // First trigger acquires the lock; a second overlapping trigger is told
        // to skip (so it can't double-apply the same pending mutations).
        #expect(await state.beginReplayIfIdle())
        #expect(await state.beginReplayIfIdle() == false)

        // After the holder finishes, the next replay can run.
        await state.endReplay()
        #expect(await state.beginReplayIfIdle())
        await state.endReplay()
    }
}

/// Source cache that pauses on the first `source` read so tests can mutate the
/// live header cache mid-repair. Forwards all other calls to an in-memory cache.
private actor GatedIMAPMessageSourceCache: IMAPMessageSourceCache {
    private let inner = InMemoryIMAPMessageSourceCache()
    private var sourceCallWaiters: [CheckedContinuation<Void, Never>] = []
    private var sourceReleaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var sourceCalled = false
    private var sourceReleased = false

    func waitUntilSourceCalled() async {
        if sourceCalled { return }
        await withCheckedContinuation { continuation in
            if sourceCalled {
                continuation.resume()
            } else {
                sourceCallWaiters.append(continuation)
            }
        }
    }

    func releaseSource() {
        sourceReleased = true
        let waiters = sourceReleaseWaiters
        sourceReleaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func source(
        accountID: BrevAccount.ID,
        messageID: MessageHeader.ID
    ) async -> IMAPMessageSource? {
        if !sourceCalled {
            sourceCalled = true
            let callWaiters = sourceCallWaiters
            sourceCallWaiters.removeAll()
            for waiter in callWaiters {
                waiter.resume()
            }
        }
        if !sourceReleased {
            await withCheckedContinuation { continuation in
                if sourceReleased {
                    continuation.resume()
                } else {
                    sourceReleaseWaiters.append(continuation)
                }
            }
        }
        return await inner.source(accountID: accountID, messageID: messageID)
    }

    func setSource(
        _ source: IMAPMessageSource,
        accountID: BrevAccount.ID,
        messageID: MessageHeader.ID
    ) async {
        await inner.setSource(source, accountID: accountID, messageID: messageID)
    }

    func removeSource(accountID: BrevAccount.ID, messageID: MessageHeader.ID) async {
        await inner.removeSource(accountID: accountID, messageID: messageID)
    }

    func removeSources(inFolder folderID: Folder.ID, accountID: BrevAccount.ID) async {
        await inner.removeSources(inFolder: folderID, accountID: accountID)
    }

    func removeSources(
        inFolder folderID: Folder.ID,
        accountID: BrevAccount.ID,
        exceptMessageIDs: Set<MessageHeader.ID>
    ) async {
        await inner.removeSources(
            inFolder: folderID,
            accountID: accountID,
            exceptMessageIDs: exceptMessageIDs
        )
    }

    func sizeBytes(accountID: BrevAccount.ID) async -> Int {
        await inner.sizeBytes(accountID: accountID)
    }

    func clear(accountID: BrevAccount.ID) async {
        await inner.clear(accountID: accountID)
    }
}
