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
@testable import BrevSettings
import Foundation
import Testing

@Suite("MailStorageSection")
struct MailStorageSectionTests {
    @Test("storage summary includes scoped folder overrides")
    func scopedRetentionSummary() {
        var settings = AccountMailboxSyncSettings.defaults
        settings.setRetentionPolicy(.headersOnly, forFolderID: "INBOX",
                                    sourceID: MailSourceID(accountID: "account", mailboxID: "work"))
        #expect(MailStoragePresentation.retentionSummary(for: settings).detail.contains("1 folder override"))
    }

    @Test("mail storage section is shipped in default settings navigation")
    func mailStorageSectionIsShippedInDefaultSettingsNavigation() {
        #expect(SettingsSection.mailStorage.title == "Mail Storage")
        #expect(SettingsSection.mailStorage.symbolName == "internaldrive")
        #expect(SettingsSection.mailStorage.availability == .shipped)
        #expect(SettingsSectionAvailability.v1Default.visibleSections.contains(.mailStorage))
    }

    @Test("mail storage reload key changes when backend availability changes")
    func mailStorageReloadKeyChangesWhenBackendAvailabilityChanges() {
        let firstBackend = MockBackend(account: BrevAccount(
            id: "account",
            displayName: "Account",
            emailAddress: "account@example.com"
        ))
        let secondBackend = MockBackend(account: firstBackend.account)

        let withoutBackend = MailStorageReloadKey(accountID: "account", backend: nil)
        let withFirstBackend = MailStorageReloadKey(accountID: "account", backend: firstBackend)
        let withFirstBackendAgain = MailStorageReloadKey(accountID: "account", backend: firstBackend)
        let withSecondBackend = MailStorageReloadKey(accountID: "account", backend: secondBackend)

        #expect(withoutBackend != withFirstBackend)
        #expect(withFirstBackend == withFirstBackendAgain)
        #expect(withFirstBackend != withSecondBackend)
    }

    @Test("sync health load failure clears stale source and health")
    func syncHealthLoadFailureClearsStaleSourceAndHealth() {
        let failure = MailStorageSyncHealthLoadPolicy.failure(for: MailStorageExampleError())

        #expect(failure.sourceID == nil)
        #expect(failure.syncHealth == nil)
        #expect(failure.statusMessage == "Could not load storage health: mailbox unavailable")
    }

    @Test("sync health load success clears stale failure without hiding action status")
    func syncHealthLoadSuccessClearsStaleFailureWithoutHidingActionStatus() {
        #expect(MailStorageSyncHealthLoadPolicy.statusMessageAfterSuccessfulLoad(
            current: "Could not load storage health: mailbox unavailable"
        ) == nil)
        #expect(MailStorageSyncHealthLoadPolicy.statusMessageAfterSuccessfulLoad(
            current: "Downloaded and indexed local mail."
        ) == "Downloaded and indexed local mail.")
        #expect(MailStorageSyncHealthLoadPolicy.statusMessageAfterSuccessfulLoad(current: nil) == nil)
    }

    @Test("storage rows include local search index metrics")
    func storageRowsIncludeLocalSearchIndexMetrics() {
        let breakdown = MailStorageBreakdown(
            cacheBytes: 1024,
            cacheObjectCount: 3,
            draftStagingBytes: 2048,
            draftStagingObjectCount: 1,
            offlineMetadataBytes: 512,
            offlineMetadataObjectCount: 2
        )
        let indexMetrics = LocalSearchIndexMetrics(
            databaseBytes: 4096,
            indexedHeaderCount: 12,
            cachedBodyCount: 7,
            searchDocumentCount: 12,
            syncedFolderCount: 3
        )

        let rows = MailStoragePresentation.rows(
            for: breakdown,
            indexMetrics: indexMetrics
        )

        #expect(rows.map(\.title) == [
            "Mail cache",
            "Draft staging",
            "Offline sync metadata",
            "Search index database",
        ])
        #expect(rows.last?.value == "4 KB")
        #expect(rows.last?.detail == "34 index objects - 12 headers - 7 bodies - 12 docs - 3 folders")
        #expect(MailStoragePresentation.totalValue(
            for: breakdown,
            indexMetrics: indexMetrics
        ) == "\(MailStorageInfo.formattedSize(7680)) - 40 objects")
    }

    @Test("storage reset confirmation includes total local footprint")
    func storageResetConfirmationIncludesTotalLocalFootprint() {
        let breakdown = MailStorageBreakdown(
            cacheBytes: 1024,
            cacheObjectCount: 3,
            draftStagingBytes: 2048,
            draftStagingObjectCount: 1,
            offlineMetadataBytes: 512,
            offlineMetadataObjectCount: 2
        )
        let indexMetrics = LocalSearchIndexMetrics(
            databaseBytes: 4096,
            indexedHeaderCount: 12,
            cachedBodyCount: 7,
            searchDocumentCount: 12,
            syncedFolderCount: 3
        )

        let presentation = MailStoragePresentation.resetConfirmation(
            breakdown: breakdown,
            indexMetrics: indexMetrics
        )

        #expect(presentation.title == "Reset & re-download local mail?")
        #expect(presentation.confirmTitle == "Reset & re-download")
        #expect(presentation.message.contains(MailStorageInfo.formattedSize(7680)))
        #expect(presentation.message.contains("search index"))
        #expect(presentation.message.contains("draft staging"))
        #expect(presentation.message.contains("pending offline retries"))
        #expect(presentation.message.contains("server mail stay untouched"))
    }

    @Test("storage reset confirmation handles unknown local footprint")
    func storageResetConfirmationHandlesUnknownLocalFootprint() {
        let presentation = MailStoragePresentation.resetConfirmation(
            breakdown: nil,
            indexMetrics: nil
        )

        #expect(presentation.message.contains("this account's local mail data"))
    }

    @Test("cache location display redacts account storage key")
    func cacheLocationDisplayRedactsAccountStorageKey() throws {
        let accountID = "settings-mail-storage-account"
        let url = try #require(MailStorageInfo.accountDirectory(accountID: accountID))
        let displayPath = MailStorageInfo.displayPath(for: url)

        #expect(displayPath.hasSuffix("/account-cache"))
        #expect(displayPath.contains("Brev/Cache"))
        #expect(!displayPath.contains(MailStorageInfo.hexKey(accountID)))
    }

    @Test("display path keeps ordinary paths readable")
    func displayPathKeepsOrdinaryPathsReadable() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Brev/Cache", isDirectory: true)

        #expect(MailStorageInfo.displayPath(for: url).hasSuffix("Brev/Cache"))
    }

    @Test("storage breakdown counts real file-backed cache records")
    func storageBreakdownCountsFileBackedCacheRecords() async throws {
        let accountID = "settings-storage-\(UUID().uuidString)"
        let cacheRoot = try #require(MailStorageInfo.cacheRoot())
        let cacheURL = try #require(MailStorageInfo.accountDirectory(accountID: accountID))
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let headersURL = cacheURL.appendingPathComponent("headers", isDirectory: true)
        try FileManager.default.createDirectory(at: headersURL, withIntermediateDirectories: true)

        let folders = IMAPFolderCacheSnapshot(folders: [
            Folder(id: "inbox", name: "Inbox", role: .inbox),
            Folder(id: "archive", name: "Archive", role: .archive),
        ])
        try JSONEncoder().encode(folders)
            .write(to: cacheURL.appendingPathComponent("folders.json"))

        let headers = IMAPMailboxHeaderCacheSnapshot(headers: [
            Self.makeHeader(id: "inbox:1"),
            Self.makeHeader(id: "inbox:2"),
        ])
        try JSONEncoder().encode(headers)
            .write(to: headersURL.appendingPathComponent("INBOX.json"))

        let sourceCache = FileBackedIMAPMessageSourceCache(rootDirectory: cacheRoot)
        await sourceCache.setSource(
            IMAPMessageSource(uid: 1, rawMessage: "Subject: Cached\r\n\r\nBody"),
            accountID: accountID,
            messageID: "inbox:1"
        )

        let breakdown = MailStorageInfo.storageBreakdown(accountID: accountID)

        #expect(breakdown.cacheObjectCount == 5)
        #expect(breakdown.cacheBytes > 0)
    }

    @Test("storage breakdown counts nested cache source records")
    func storageBreakdownCountsNestedCacheSourceRecords() throws {
        let accountID = "settings-nested-storage-\(UUID().uuidString)"
        let cacheURL = try #require(MailStorageInfo.accountDirectory(accountID: accountID))
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let headersURL = cacheURL.appendingPathComponent("headers", isDirectory: true)
        let nestedSourceURL = cacheURL.appendingPathComponent("sources/nested", isDirectory: true)
        try FileManager.default.createDirectory(at: headersURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nestedSourceURL, withIntermediateDirectories: true)
        try JSONEncoder().encode(IMAPMailboxHeaderCacheSnapshot(headers: [
            Self.makeHeader(id: "inbox:1")
        ])).write(to: headersURL.appendingPathComponent("INBOX.json"))
        try Data("nested source".utf8).write(to: nestedSourceURL.appendingPathComponent("source.json"))

        let breakdown = MailStorageInfo.storageBreakdown(accountID: accountID)

        #expect(breakdown.cacheObjectCount == 2)
    }

    @Test("storage breakdown stays scoped to the selected account")
    func storageBreakdownStaysScopedToSelectedAccount() throws {
        let accountA = "settings-storage-a-\(UUID().uuidString)"
        let accountB = "settings-storage-b-\(UUID().uuidString)"
        let cacheA = try #require(MailStorageInfo.accountDirectory(accountID: accountA))
        let cacheB = try #require(MailStorageInfo.accountDirectory(accountID: accountB))
        let draftsA = try #require(MailStorageInfo.draftsDirectory(accountID: accountA))
        let draftsB = try #require(MailStorageInfo.draftsDirectory(accountID: accountB))
        let defaultsName = "settings-storage-defaults-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer {
            try? FileManager.default.removeItem(at: cacheA)
            try? FileManager.default.removeItem(at: cacheB)
            try? FileManager.default.removeItem(at: draftsA)
            try? FileManager.default.removeItem(at: draftsB)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        try FileManager.default.createDirectory(at: cacheA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheB, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: draftsA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: draftsB, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 128).write(to: cacheA.appendingPathComponent("source-a.json"))
        try Data(repeating: 2, count: 128).write(to: cacheB.appendingPathComponent("source-b-1.json"))
        try Data(repeating: 3, count: 128).write(to: cacheB.appendingPathComponent("source-b-2.json"))
        try Data(repeating: 4, count: 64).write(to: draftsA.appendingPathComponent("draft-a.json"))
        try Data(repeating: 5, count: 64).write(to: draftsB.appendingPathComponent("draft-b-1.json"))
        try Data(repeating: 6, count: 64).write(to: draftsB.appendingPathComponent("draft-b-2.json"))
        defaults.set(
            Data(repeating: 7, count: 11),
            forKey: OfflineMutationQueueStorage.storageKey(accountID: accountA)
        )
        defaults.set(
            Data(repeating: 8, count: 22),
            forKey: OfflineMutationQueueStorage.storageKey(accountID: accountB)
        )
        defaults.set(
            Data(repeating: 9, count: 33),
            forKey: OfflineMutationQueueStorage.conflictStorageKey(accountID: accountB)
        )

        let selected = MailStorageInfo.storageBreakdown(accountID: accountA, defaults: defaults)
        let other = MailStorageInfo.storageBreakdown(accountID: accountB, defaults: defaults)

        #expect(selected.cacheObjectCount == 1)
        #expect(selected.draftStagingObjectCount == 1)
        #expect(selected.offlineMetadataObjectCount == 1)
        #expect(selected.offlineMetadataBytes == 11)
        #expect(other.cacheObjectCount == 2)
        #expect(other.draftStagingObjectCount == 2)
        #expect(other.offlineMetadataObjectCount == 2)
        #expect(other.offlineMetadataBytes == 55)
    }

    @Test("mail storage repair actions rebuild and apply retention")
    func mailStorageRepairActionsRebuildAndApplyRetention() {
        #expect(MailStorageRepairPlan.steps(for: .downloadAllMail) == [
            .rebuildSearchIndex,
            .applyRetentionAfterDownload,
        ])
        #expect(MailStorageRepairPlan.steps(for: .resetAndRedownload) == [
            .resetLocalCacheAndIndex,
            .rebuildSearchIndex,
            .applyRetentionAfterDownload,
        ])
        #expect(MailStorageRepairPlan.pollsSyncHealth(during: .downloadAllMail))
        #expect(MailStorageRepairPlan.pollsSyncHealth(during: .resetAndRedownload))
    }

    @Test("mail storage actions describe long-running download states")
    func mailStorageActionsDescribeLongRunningDownloadStates() {
        #expect(MailStoragePresentation.actionTitle(
            for: .downloadAllMail,
            isRunning: false
        ) == "Download all mail")
        #expect(MailStoragePresentation.actionTitle(
            for: .downloadAllMail,
            isRunning: true
        ) == "Downloading mail...")
        #expect(MailStoragePresentation.actionTitle(
            for: .resetAndRedownload,
            isRunning: true
        ) == "Resetting and downloading...")
    }

    @Test("mail storage actions are enabled only after repair service and source resolve")
    func mailStorageActionsRequireRepairServiceAndSource() {
        #expect(MailStorageActionAvailability.canRun(
            hasRepairService: true,
            hasSourceID: true,
            isActionRunning: false,
            syncHealthState: nil,
            indexStatus: nil
        ))
        #expect(!MailStorageActionAvailability.canRun(
            hasRepairService: false,
            hasSourceID: true,
            isActionRunning: false,
            syncHealthState: nil,
            indexStatus: nil
        ))
        #expect(!MailStorageActionAvailability.canRun(
            hasRepairService: true,
            hasSourceID: false,
            isActionRunning: false,
            syncHealthState: nil,
            indexStatus: nil
        ))
        #expect(!MailStorageActionAvailability.canRun(
            hasRepairService: true,
            hasSourceID: true,
            isActionRunning: true,
            syncHealthState: nil,
            indexStatus: nil
        ))
        #expect(!MailStorageActionAvailability.canRun(
            hasRepairService: true,
            hasSourceID: true,
            isActionRunning: false,
            syncHealthState: nil,
            indexStatus: .rebuilding(progress: 0.42)
        ))
        #expect(!MailStorageActionAvailability.canRun(
            hasRepairService: true,
            hasSourceID: true,
            isActionRunning: false,
            syncHealthState: .indexing,
            indexStatus: nil
        ))
    }

    @Test("retention explanation makes full body download path explicit")
    func retentionExplanationMakesFullBodyDownloadPathExplicit() {
        #expect(MailStoragePresentation.retentionDownloadExplanation.contains("Download all mail applies this policy"))
        #expect(MailStoragePresentation.retentionDownloadExplanation.contains("Choose Everything"))
        #expect(MailStoragePresentation.retentionDownloadExplanation.contains("full body search for all mail"))
    }

    @Test("retention changes apply immediately when storage has backend and source")
    func retentionChangesApplyImmediatelyWhenStorageHasBackendAndSource() {
        #expect(MailStorageRetentionChangePolicy.decision(
            hasBackend: true,
            hasSourceID: true,
            isActionRunning: false,
            syncHealthState: .healthy
        ) == MailStorageRetentionChangeDecision(
            appliesImmediately: true,
            postsChangeNotification: true,
            statusMessage: nil
        ))
        #expect(MailStorageRetentionChangePolicy.decision(
            hasBackend: false,
            hasSourceID: true,
            isActionRunning: false,
            syncHealthState: nil
        ).appliesImmediately == false)
        #expect(MailStorageRetentionChangePolicy.decision(
            hasBackend: false,
            hasSourceID: true,
            isActionRunning: false,
            syncHealthState: nil
        ).postsChangeNotification)
        #expect(MailStorageRetentionChangePolicy.decision(
            hasBackend: true,
            hasSourceID: false,
            isActionRunning: false,
            syncHealthState: nil
        ).appliesImmediately == false)
        #expect(MailStorageRetentionChangePolicy.decision(
            hasBackend: true,
            hasSourceID: false,
            isActionRunning: false,
            syncHealthState: nil
        ).postsChangeNotification)
    }

    @Test("retention changes wait while storage action runs")
    func retentionChangesWaitWhileStorageActionRuns() {
        let decision = MailStorageRetentionChangePolicy.decision(
            hasBackend: true,
            hasSourceID: true,
            isActionRunning: true,
            syncHealthState: .healthy
        )
        let indexingDecision = MailStorageRetentionChangePolicy.decision(
            hasBackend: true,
            hasSourceID: true,
            isActionRunning: false,
            syncHealthState: .indexing
        )

        #expect(decision.appliesImmediately == false)
        #expect(decision.postsChangeNotification == false)
        #expect(decision.statusMessage == "Saved cache lookback; it will apply after the current storage action finishes.")
        #expect(indexingDecision.appliesImmediately == false)
        #expect(indexingDecision.postsChangeNotification == false)
        #expect(indexingDecision.statusMessage == decision.statusMessage)
    }

    @Test("download retention plan maps saved policies per folder")
    func downloadRetentionPlanMapsSavedPoliciesPerFolder() {
        let folders = [
            Folder(id: "inbox", name: "Inbox", role: .inbox),
            Folder(id: "archive", name: "Archive", role: .archive),
            Folder(id: "inbox", name: "Inbox duplicate", role: .inbox),
        ]
        let settings = AccountMailboxSyncSettings(
            roleMappingsByAccountID: [:],
            folderSyncScope: .allFolders,
            includeSharedFolders: true,
            includeArchiveFolders: true,
            offlineRetentionPolicy: .keep30Days,
            folderOverrides: [
                "archive": FolderSyncOverride(retentionPolicy: .headersOnly),
            ]
        )

        let applications = MailStorageRetentionPlan.applications(
            for: folders,
            sourceID: MailSourceID(accountID: "account", mailboxID: "mailbox"),
            settings: settings
        )

        #expect(applications == [
            MailStorageRetentionApplication(
                sourceID: MailSourceID(accountID: "account", mailboxID: "mailbox"),
                folderID: "inbox",
                retentionDays: 30,
                keepsBodies: true
            ),
            MailStorageRetentionApplication(
                sourceID: MailSourceID(accountID: "account", mailboxID: "mailbox"),
                folderID: "archive",
                retentionDays: nil,
                keepsBodies: false
            ),
        ])
    }

    @Test("retention summary exposes cache lookback and overrides")
    func retentionSummaryExposesCacheLookbackAndOverrides() {
        let noOverrides = AccountMailboxSyncSettings(
            roleMappingsByAccountID: [:],
            folderSyncScope: .allFolders,
            includeSharedFolders: true,
            includeArchiveFolders: true,
            offlineRetentionPolicy: .keep1Year
        )
        let withOverrides = AccountMailboxSyncSettings(
            roleMappingsByAccountID: [:],
            folderSyncScope: .allFolders,
            includeSharedFolders: true,
            includeArchiveFolders: true,
            offlineRetentionPolicy: .headersOnly,
            folderOverrides: [
                "archive": FolderSyncOverride(retentionPolicy: .keep30Days),
                "sent": FolderSyncOverride(retentionPolicy: .keep7Days),
                "drafts": FolderSyncOverride(),
            ]
        )

        #expect(MailStoragePresentation.retentionSummary(for: noOverrides) == MailStorageRetentionSummary(
            title: "1 year",
            detail: "Keep full message content for the latest year. No folder overrides."
        ))
        #expect(MailStoragePresentation.retentionSummary(for: withOverrides) == MailStorageRetentionSummary(
            title: "Headers only",
            detail: "Keep headers only; load body content on demand. 2 folder overrides."
        ))
    }

    @Test("index summary describes ready and rebuilding states")
    func indexSummaryDescribesReadyAndRebuildingStates() {
        let sourceID = MailSourceID(accountID: "account", mailboxID: "mailbox")
        let ready = AccountSyncHealth(
            sourceID: sourceID,
            state: .healthy,
            lastSuccessfulSyncAt: nil,
            lastErrorDescription: nil,
            indexStatus: .ready(messageCount: 12),
            cacheSizeBytes: 0,
            localSearchIndexMetrics: LocalSearchIndexMetrics(
                databaseBytes: 4096,
                indexedHeaderCount: 12,
                cachedBodyCount: 7,
                searchDocumentCount: 12,
                syncedFolderCount: 3
            ),
            pendingMutationCount: 0
        )
        let rebuilding = AccountSyncHealth(
            sourceID: sourceID,
            state: .indexing,
            lastSuccessfulSyncAt: nil,
            lastErrorDescription: nil,
            indexStatus: .rebuilding(progress: 0.42),
            cacheSizeBytes: 0,
            localSearchIndexMetrics: LocalSearchIndexMetrics(
                databaseBytes: 4096,
                indexedHeaderCount: 8,
                cachedBodyCount: 5,
                searchDocumentCount: 8,
                syncedFolderCount: 2
            ),
            pendingMutationCount: 0,
            searchIndexProgress: SearchIndexProgressSnapshot(
                completedFolderCount: 2,
                totalFolderCount: 5,
                indexedMessageCount: 41,
                bodyBackfillFailureCount: 1
            )
        )

        #expect(MailStoragePresentation.indexSummary(for: ready)
            == "Local search index ready: 34 index objects, 12 headers, 7 bodies, 12 search docs, 3 folders.")
        #expect(MailStoragePresentation.indexSummary(for: rebuilding)
            == "Downloading and indexing mail: 42% complete. 23 index objects, 8 headers, "
            + "5 bodies, 8 search docs, 2 folders. 2/5 folders complete, 41 messages indexed, "
            + "1 body cache failure.")
    }

    @Test("advanced disclosure titles and collapsed gate")
    func advancedDisclosureTitlesAndCollapsedGate() {
        #expect(MailStoragePresentation.advancedDisclosureTitle(isExpanded: false) == "Advanced storage…")
        #expect(MailStoragePresentation.advancedDisclosureTitle(isExpanded: true) == "Hide advanced storage")
        #expect(!MailStoragePresentation.showsAdvancedContent(isExpanded: false))
        #expect(MailStoragePresentation.showsAdvancedContent(isExpanded: true))
    }

    private static func makeHeader(id: String) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: id,
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            subject: "Cached",
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600)
        )
    }
}

private struct MailStorageExampleError: LocalizedError {
    var errorDescription: String? { "mailbox unavailable" }
}
