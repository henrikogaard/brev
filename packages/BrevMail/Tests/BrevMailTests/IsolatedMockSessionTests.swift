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
import BrevMail
import Foundation
import Testing

#if DEBUG
@Suite("Isolated mock session")
@MainActor
struct IsolatedMockSessionTests {
    @Test("Bootstrap and sign-in stay synthetic without production services")
    func mockOnlyWiring() async throws {
        let suite = "IsolatedMockSessionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = AppSessionFactory.makeIsolatedMock(themeDefaults: defaults)
        let backend = try #require(session.backend)
        #expect(backend is MockBackend)
        #expect(session.accountStore is InMemoryAccountStore)
        #expect(!(session.tokenStore is KeychainTokenStore))
        #expect(await session.accountStore.current?.id == backend.account.id)
        #expect(session.localBackend == nil)
        #expect(session.pimSourceCoordinator == nil)
        #expect(session.googleDriveFeature == nil)
        #expect(!session.canUseIMAPAccountSetup)
        #expect(!session.canValidateIMAPAccountSetup)
        #expect(!session.canUseIMAPOAuthSetup)
        #expect(!session.canStartIMAPOAuthBrowserSetup)
        #expect(!session.canStartGoogleSignIn)
        #expect(!session.canStartNativeGoogleSignIn)
        #expect(!session.canDiscoverIMAPSettings)
        await session.restoreAllAccounts()
        #expect(session.backend?.account.id == backend.account.id)
        await session.signOut(account: backend.account)
        await session.signIn()
        #expect(session.backend?.account.id == backend.account.id)
        #expect(session.visibleBackends.count == 1)
    }

    @Test("account removal purges its isolated Mock scheduled-send journal")
    func removalPurgesMockJournal() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsolatedMockJournal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = AppSessionFactory.makeIsolatedMock(mockPersistenceDirectory: directory)
        let backend = try #require(session.backend)
        let mailbox = try await backend.currentMailbox()
        let sourceID = backend.sourceID(for: mailbox)
        let attachmentID = try await backend.uploadAttachment(
            draftID: "unsaved-before-remove",
            data: Data([7, 8, 9]),
            filename: "kept-only-in-memory.bin",
            mimeType: "application/octet-stream",
            sourceID: sourceID
        )
        let unsavedDraft = Draft(id: "unsaved-before-remove", attachmentIDs: [attachmentID])
        _ = try await backend.save(draft: unsavedDraft, sourceID: sourceID)
        _ = try await backend.send(
            draft: Draft(id: "remove-me", scheduledFor: Date(timeIntervalSince1970: 2_000_000_000)),
            sourceID: sourceID
        )
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)

        await session.removeAccount(backend.account)

        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        #expect(await session.accountStore.current == nil)
        await #expect(throws: (any Error).self) {
            try await backend.send(draft: Draft(id: "late-isolated-send"), sourceID: sourceID)
        }
        await #expect(throws: (any Error).self) {
            try await backend.send(
                draft: Draft(id: "late-isolated-queue", scheduledFor: Date(timeIntervalSince1970: 2_000_000_000)),
                sourceID: sourceID
            )
        }
        await #expect(throws: (any Error).self) {
            _ = try await backend.save(draft: Draft(id: "late-isolated-save"), sourceID: sourceID)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        await session.signInWithDemo()
        #expect(session.backend?.account.id == backend.account.id)
        let reconnected = try #require(session.backend as? MockBackend)
        #expect(ObjectIdentifier(reconnected) != ObjectIdentifier(backend))
        _ = try await reconnected.send(
            draft: Draft(id: "isolated-fresh-send", scheduledFor: .distantPast),
            sourceID: sourceID
        )
        await reconnected.deliverDueScheduledSends()
        #expect(reconnected.pendingScheduledSends().isEmpty)
        #expect(try await reconnected.draft(for: "remove-me", sourceID: sourceID) == nil)
        #expect(try await reconnected.draft(for: unsavedDraft.id, sourceID: sourceID) == nil)
        await #expect(throws: (any Error).self) {
            try await reconnected.localDraftAttachments(for: unsavedDraft, sourceID: sourceID)
        }
        await session.removeAccount(reconnected.account)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("failed Mock cleanup retains the account for retry")
    func failedRemovalRetainsAccount() async throws {
        let invalidDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsolatedMockJournalFile-\(UUID().uuidString)")
        try Data([1]).write(to: invalidDirectory)
        defer { try? FileManager.default.removeItem(at: invalidDirectory) }
        let session = AppSessionFactory.makeIsolatedMock(mockPersistenceDirectory: invalidDirectory)
        let backend = try #require(session.backend)

        await session.removeAccount(backend.account)

        #expect(await session.accountStore.current?.id == backend.account.id)
        #expect(await session.accountStore.accounts.count == 1)
    }
}
#endif
