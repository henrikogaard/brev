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

@Suite("ImportProgressPresentation")
struct ImportProgressPresentationTests {
    private let sourceID = MailSourceID(accountID: "acct", mailboxID: "mbox")

    @Test("idle healthy mailbox hides the banner")
    func idleHealthyMailboxHidesBanner() {
        let health = AccountSyncHealth(
            sourceID: sourceID,
            state: .healthy,
            lastSuccessfulSyncAt: Date(),
            lastErrorDescription: nil,
            indexStatus: .ready(messageCount: 42),
            cacheSizeBytes: 1024,
            pendingMutationCount: 0
        )

        #expect(ImportProgressPresentation.resolve(health: health, folderSyncProgress: nil) == nil)
    }

    @Test("folder backfill shows determinate progress while mail stays readable")
    func folderBackfillShowsDeterminateProgress() {
        let health = AccountSyncHealth(
            sourceID: sourceID,
            state: .healthy,
            lastSuccessfulSyncAt: Date(),
            lastErrorDescription: nil,
            indexStatus: .ready(messageCount: 12),
            cacheSizeBytes: 4096,
            pendingMutationCount: 0
        )
        let progress = MailSyncProgress(completed: 2, total: 5)

        let presentation = ImportProgressPresentation.resolve(
            health: health,
            folderSyncProgress: progress
        )

        #expect(presentation?.phase == .backfillContinuing)
        #expect(presentation?.showsDeterminateProgress == true)
        #expect(presentation?.progressCompleted == 2)
        #expect(presentation?.progressTotal == 5)
        #expect(presentation?.message?.contains("read available messages") == true)
    }

    @Test("index rebuild shows indexing phase with folder progress")
    func indexRebuildShowsIndexingPhase() {
        let health = AccountSyncHealth(
            sourceID: sourceID,
            state: .indexing,
            lastSuccessfulSyncAt: Date(),
            lastErrorDescription: nil,
            indexStatus: .rebuilding(progress: 0.4),
            cacheSizeBytes: 8192,
            pendingMutationCount: 0,
            searchIndexProgress: SearchIndexProgressSnapshot(
                completedFolderCount: 3,
                totalFolderCount: 10,
                indexedMessageCount: 120
            )
        )

        let presentation = ImportProgressPresentation.resolve(health: health, folderSyncProgress: nil)

        #expect(presentation?.phase == .indexCatchingUp)
        #expect(presentation?.title == "Indexing mail")
        #expect(presentation?.progressCompleted == 3)
        #expect(presentation?.progressTotal == 10)
    }

    @Test("recoverable provider error offers retry without hiding cached mail")
    func recoverableProviderErrorOffersRetry() {
        let health = AccountSyncHealth(
            sourceID: sourceID,
            state: .providerError,
            lastSuccessfulSyncAt: Date(),
            lastErrorDescription: "Provider timed out.",
            indexStatus: .ready(messageCount: 8),
            cacheSizeBytes: 2048,
            pendingMutationCount: 0
        )

        let presentation = ImportProgressPresentation.resolve(health: health, folderSyncProgress: nil)

        #expect(presentation?.phase == .recoverableFailure)
        #expect(presentation?.showsRetryAction == true)
        #expect(presentation?.message == "Provider timed out.")
    }

    @Test("cancellation noise does not surface as sync needs attention")
    func cancellationNoiseDoesNotSurfaceAsSyncNeedsAttention() {
        let health = AccountSyncHealth(
            sourceID: sourceID,
            state: .degraded,
            lastSuccessfulSyncAt: Date(),
            lastErrorDescription: "The operation couldn’t be completed. (Swift.CancellationError error 1.)",
            indexStatus: .ready(messageCount: 8),
            cacheSizeBytes: 2048,
            pendingMutationCount: 0
        )

        let presentation = ImportProgressPresentation.resolve(health: health, folderSyncProgress: nil)

        #expect(presentation == nil)
    }

    @Test("background import stays quiet once cached mail is readable")
    func backgroundImportStaysQuietOnceCachedMailIsReadable() {
        let health = AccountSyncHealth(
            sourceID: sourceID,
            state: .healthy,
            lastSuccessfulSyncAt: Date(),
            lastErrorDescription: nil,
            indexStatus: .notBuilt,
            cacheSizeBytes: 512,
            pendingMutationCount: 0,
            backgroundRefreshSnapshot: BackgroundRefreshSnapshot(
                refreshedFolderCount: 1,
                deferredFolderCount: 4,
                refreshedAt: Date()
            )
        )

        let presentation = ImportProgressPresentation.resolve(health: health, folderSyncProgress: nil)

        #expect(presentation == nil)
    }

    @Test("frequent polling is enabled while import work is active")
    func frequentPollingEnabledDuringActiveImport() {
        let indexingHealth = AccountSyncHealth(
            sourceID: sourceID,
            state: .indexing,
            lastSuccessfulSyncAt: Date(),
            lastErrorDescription: nil,
            indexStatus: .rebuilding(progress: nil),
            cacheSizeBytes: 0,
            pendingMutationCount: 0
        )

        #expect(ImportProgressPresentation.shouldPollFrequently(health: indexingHealth))
        #expect(!ImportProgressPresentation.shouldPollFrequently(health: nil))
    }

    @Test("healthy ready mailbox exits health polling")
    func healthyReadyMailboxExitsHealthPolling() {
        let health = AccountSyncHealth(
            sourceID: sourceID,
            state: .healthy,
            lastSuccessfulSyncAt: Date(),
            lastErrorDescription: nil,
            indexStatus: .ready(messageCount: 42),
            cacheSizeBytes: 1024,
            pendingMutationCount: 0
        )

        #expect(ImportProgressPresentation.pollingIntervalNanoseconds(health: health) == nil)
    }

    @Test("non-urgent health polling backs off")
    func nonUrgentHealthPollingBacksOff() {
        let health = AccountSyncHealth(
            sourceID: sourceID,
            state: .syncing,
            lastSuccessfulSyncAt: Date(),
            lastErrorDescription: nil,
            indexStatus: .ready(messageCount: 42),
            cacheSizeBytes: 1024,
            pendingMutationCount: 0
        )

        #expect(ImportProgressPresentation.pollingIntervalNanoseconds(health: health) == 10_000_000_000)
    }
}
