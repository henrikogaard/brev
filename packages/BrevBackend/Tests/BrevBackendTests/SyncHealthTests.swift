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

// MARK: - Helpers

private extension MailSourceID {
    static let preview = MailSourceID(accountID: "account", mailboxID: "primary")
}

private extension ReplayConflict {
    static func make(
        id: UUID = UUID(),
        folderName: String = "Inbox",
        operationDescription: String = "Mark read",
        failureReason: String = "Target not found",
        detectedAt: Date = Date()
    ) -> ReplayConflict {
        ReplayConflict(
            id: id,
            folderName: folderName,
            operationDescription: operationDescription,
            failureReason: failureReason,
            detectedAt: detectedAt
        )
    }
}

@Suite("Sync health")
struct SyncHealthTests {
    @Test("authentication-required health asks for user action")
    func authenticationRequiredHealthAsksForUserAction() {
        let health = AccountSyncHealth(
            sourceID: MailSourceID(accountID: "account", mailboxID: "primary"),
            state: .authenticationRequired,
            lastSuccessfulSyncAt: nil,
            lastErrorDescription: "OAuth token expired",
            indexStatus: .notBuilt,
            cacheSizeBytes: 0,
            pendingMutationCount: 0
        )

        #expect(health.requiresUserAction)
        #expect(health.canRetryWithoutUserAction == false)
    }

    @Test("diagnostic reports redact email addresses and secret-like tokens")
    func diagnosticReportsRedactEmailAddressesAndSecretLikeTokens() {
        let health = AccountSyncHealth(
            sourceID: MailSourceID(accountID: "account", mailboxID: "primary"),
            state: .providerError,
            lastSuccessfulSyncAt: Date(timeIntervalSince1970: 1_800_000_000),
            lastErrorDescription: "Failed for ada@example.org with Bearer secret-token-123",
            indexStatus: .ready(messageCount: 42),
            cacheSizeBytes: 1024,
            pendingMutationCount: 2
        )
        let report = SyncDiagnosticReport(
            accountDisplayName: "Ada <ada@example.org>",
            backendDisplayName: "Provider API",
            health: health
        )

        let redacted = report.redactedText()

        #expect(redacted.contains("[redacted-email]"))
        #expect(redacted.contains("[redacted-token]"))
        #expect(!redacted.contains("ada@example.org"))
        #expect(!redacted.contains("secret-token-123"))
    }

    @Test("redaction covers no-space key=value secrets and password keywords")
    func redactionCoversKeyValueAndPasswordKeywords() {
        // Regression: the pattern required whitespace before the value, so the
        // common `key=value` form (and password-class keywords) leaked.
        let health = AccountSyncHealth(
            sourceID: MailSourceID(accountID: "account", mailboxID: "primary"),
            state: .providerError,
            lastSuccessfulSyncAt: nil,
            lastErrorDescription: "auth failed token=abc123XYZ password=hunter2longvalue access_token=ya29.secretpart",
            indexStatus: .ready(messageCount: 0),
            cacheSizeBytes: 0,
            pendingMutationCount: 0
        )
        let report = SyncDiagnosticReport(
            accountDisplayName: "Ada",
            backendDisplayName: "IMAP",
            health: health
        )

        let redacted = report.redactedText()
        #expect(!redacted.contains("abc123XYZ"))
        #expect(!redacted.contains("hunter2longvalue"))
        #expect(!redacted.contains("ya29.secretpart"))
    }

    @Test("replay conflict count defaults to zero")
    func replayConflictCountDefaultsToZero() {
        let health = AccountSyncHealth(
            sourceID: .preview,
            state: .healthy,
            lastSuccessfulSyncAt: Date(),
            lastErrorDescription: nil,
            indexStatus: .notBuilt,
            cacheSizeBytes: 0,
            pendingMutationCount: 0
        )
        #expect(health.replayConflictCount == 0)
    }

    @Test("replay conflict count is reflected in health value")
    func replayConflictCountIsReflectedInHealthValue() {
        let health = AccountSyncHealth(
            sourceID: .preview,
            state: .degraded,
            lastSuccessfulSyncAt: nil,
            lastErrorDescription: "Error",
            indexStatus: .notBuilt,
            cacheSizeBytes: 0,
            pendingMutationCount: 0,
            replayConflictCount: 3
        )
        #expect(health.replayConflictCount == 3)
    }

    @Test("diagnostic report includes replay conflict count")
    func diagnosticReportIncludesReplayConflictCount() {
        let health = AccountSyncHealth(
            sourceID: .preview,
            state: .degraded,
            lastSuccessfulSyncAt: nil,
            lastErrorDescription: nil,
            indexStatus: .notBuilt,
            cacheSizeBytes: 0,
            pendingMutationCount: 0,
            replayConflictCount: 2,
            searchIndexProgress: SearchIndexProgressSnapshot(
                completedFolderCount: 3,
                totalFolderCount: 5,
                indexedMessageCount: 42,
                bodyBackfillFailureCount: 1
            )
        )
        let report = SyncDiagnosticReport(
            accountDisplayName: "Test",
            backendDisplayName: "IMAP",
            health: health
        )
        #expect(report.redactedText().contains("Replay conflicts: 2"))
        #expect(report.redactedText().contains("Index progress: 3/5 folders, 42 indexed messages, 1 body cache failure"))
    }
}

@Suite("SyncConflictManaging — MockBackend")
struct SyncConflictManagingTests {
    private let sourceID = MailSourceID.preview

    private func makeBackend() -> MockBackend {
        MockBackend(
            account: BrevAccount(
                id: "account",
                displayName: "Test",
                emailAddress: "test@example.com",
                backendDisplayName: "IMAP"
            ),
            mailboxes: [
                Mailbox(
                    id: "primary",
                    email: "test@example.com",
                    displayName: "Test",
                    isPrimary: true
                )
            ]
        )
    }

    @Test("no conflicts initially")
    func noConflictsInitially() async {
        let backend = makeBackend()
        guard let manager = backend.extensionService(SyncConflictManaging.self) else {
            Issue.record("SyncConflictManaging not available")
            return
        }
        let conflicts = await manager.replayConflicts(for: sourceID)
        #expect(conflicts.isEmpty)
    }

    @Test("seeded conflict appears in list and increments health count")
    func seededConflictAppearsInList() async throws {
        let backend = makeBackend()
        let conflict = ReplayConflict.make(folderName: "Archive", operationDescription: "Move to Archive")
        try await backend.seedConflict(conflict, mailboxID: "primary")

        guard let manager = backend.extensionService(SyncConflictManaging.self) else {
            Issue.record("SyncConflictManaging not available")
            return
        }
        let conflicts = await manager.replayConflicts(for: sourceID)
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.id == conflict.id)

        guard let reporter = backend.extensionService(SyncHealthReporting.self) else {
            Issue.record("SyncHealthReporting not available")
            return
        }
        let health = await reporter.syncHealth(for: sourceID)
        #expect(health.replayConflictCount == 1)
    }

    @Test("dismiss individual conflict removes it and decrements count")
    func dismissIndividualConflictRemovesItAndDecrementsCount() async throws {
        let backend = makeBackend()
        let conflictA = ReplayConflict.make(operationDescription: "Mark read")
        let conflictB = ReplayConflict.make(operationDescription: "Delete")
        try await backend.seedConflict(conflictA, mailboxID: "primary")
        try await backend.seedConflict(conflictB, mailboxID: "primary")

        guard let manager = backend.extensionService(SyncConflictManaging.self) else {
            Issue.record("SyncConflictManaging not available")
            return
        }
        await manager.dismissConflict(id: conflictA.id, sourceID: sourceID)

        let remaining = await manager.replayConflicts(for: sourceID)
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == conflictB.id)

        guard let reporter = backend.extensionService(SyncHealthReporting.self) else {
            Issue.record("SyncHealthReporting not available")
            return
        }
        let health = await reporter.syncHealth(for: sourceID)
        #expect(health.replayConflictCount == 1)
    }

    @Test("dismiss all removes all conflicts")
    func dismissAllRemovesAllConflicts() async throws {
        let backend = makeBackend()
        try await backend.seedConflict(.make(), mailboxID: "primary")
        try await backend.seedConflict(.make(), mailboxID: "primary")

        guard let manager = backend.extensionService(SyncConflictManaging.self) else {
            Issue.record("SyncConflictManaging not available")
            return
        }
        await manager.dismissAllConflicts(for: sourceID)

        let remaining = await manager.replayConflicts(for: sourceID)
        #expect(remaining.isEmpty)

        guard let reporter = backend.extensionService(SyncHealthReporting.self) else {
            Issue.record("SyncHealthReporting not available")
            return
        }
        let health = await reporter.syncHealth(for: sourceID)
        #expect(health.replayConflictCount == 0)
    }
}
