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
@testable import BrevGmail
import Foundation
import SQLite3
import Testing

@Suite("Gmail API draft backend")
struct GmailAPIDraftBackendTests {
    @Test("failed schedule initialization does not publish a connected backend or live delivery owner")
    func failedScheduleInitializationStaysDisconnected() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-schedule-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let account = BrevAccount(id: UUID().uuidString, displayName: "Test", emailAddress: "primary@example.com")
        let store = try SQLiteGmailAccountStore(databaseURL: url)
        var database: OpaquePointer?
        try #require(sqlite3_open(url.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        try #require(sqlite3_exec(database, "DROP TABLE gmail_scheduled_sends;", nil, nil, nil) == SQLITE_OK)
        let backend = GmailAPIBackend(account: account, transport: DraftBackendTransport(), store: store)
        await #expect(throws: GmailAccountStoreError.self) { try await backend.connect() }
        #expect(backend.capabilities.isEmpty)
        #expect(GmailScheduledSessionRegistry.shared.activeIDs(accountID: account.id).isEmpty)
        await backend.disconnect()
    }

    @Test("a second live backend does not recover another active delivery as interrupted")
    func liveDeliveryOwnerIsPreserved() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-schedule-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = DraftBackendTransport()
        await transport.pauseNextSend()
        defer { Task { await transport.releaseSend() } }
        let first = try GmailAPIBackend(
            account: Self.account,
            transport: transport,
            store: SQLiteGmailAccountStore(databaseURL: url)
        )
        try await first.connect()
        _ = try await first.send(draft: Draft(
            id: "owned",
            to: [.init(email: "to@example.org")],
            subject: "One owner",
            scheduledFor: .distantPast
        ))
        let delivery = Task { await first.deliverDueScheduledSends() }
        await transport.waitForSendStart()
        let second = try GmailAPIBackend(
            account: Self.account,
            transport: transport,
            store: SQLiteGmailAccountStore(databaseURL: url)
        )
        try await second.connect()
        #expect(second.pendingScheduledSends().first?.state == .delivering)
        await transport.releaseSend()
        await delivery.value
        await second.deliverDueScheduledSends()
        #expect(second.pendingScheduledSends().isEmpty)
        #expect(await transport.rawSendCount() == 1)
        await first.disconnect()
        await second.disconnect()
    }

    @Test("confirmed delivery with failed local cleanup is held for review without resend")
    func scheduledCleanupFailureDoesNotResend() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-schedule-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = DraftBackendTransport()
        let store = try SQLiteGmailAccountStore(databaseURL: url)
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        try await backend.connect()
        _ = try await backend.send(draft: Draft(id: "cleanup", to: [.init(email: "to@example.org")], subject: "Already sent",
                                                scheduledFor: Date().addingTimeInterval(3600)))
        var database: OpaquePointer?
        try #require(sqlite3_open(url.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        try #require(sqlite3_exec(
            database,
            "CREATE TRIGGER fail_schedule_cleanup BEFORE DELETE ON gmail_scheduled_sends BEGIN SELECT RAISE(ABORT, 'test cleanup failure'); END;",
            nil,
            nil,
            nil
        ) == SQLITE_OK)
        try await backend.rescheduleSend(id: "cleanup", for: .distantPast)
        await backend.deliverDueScheduledSends()
        await backend.deliverDueScheduledSends()
        #expect(await transport.rawSendCount() == 1)
        #expect(backend.pendingScheduledSends().first?.state == .needsReview)
        await backend.disconnect()
    }

    @Test("rate-limited schedules keep their content and backoff across restart")
    func scheduledBackoffSurvivesRestart() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-schedule-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = DraftBackendTransport()
        await transport.setSendError(.retryable(statusCode: 429, retryAfter: 600))
        let backend = try GmailAPIBackend(
            account: Self.account,
            transport: transport,
            store: SQLiteGmailAccountStore(databaseURL: url)
        )
        try await backend.connect()
        _ = try await backend.send(draft: Draft(
            id: "limited",
            to: [.init(email: "to@example.org")],
            subject: "Wait",
            scheduledFor: .distantPast
        ))
        await backend.deliverDueScheduledSends()
        let entry = try #require(backend.pendingScheduledSends().first)
        #expect(entry.state == .waiting)
        #expect(try #require(entry.nextAttemptAt) > Date().addingTimeInterval(500))
        await backend.deliverDueScheduledSends()
        #expect(await transport.rawSendCount() == 1)
        await backend.disconnect()
        let restored = try GmailAPIBackend(
            account: Self.account,
            transport: transport,
            store: SQLiteGmailAccountStore(databaseURL: url)
        )
        try await restored.connect()
        await restored.deliverDueScheduledSends()
        #expect(await transport.rawSendCount() == 1)
        #expect(restored.pendingScheduledSends().first?.nextAttemptAt == entry.nextAttemptAt)
        let retained = try #require(try await restored.cancelScheduledSend(id: "limited"))
        #expect(retained.subject == "Wait")
        #expect(retained.scheduledFor == nil)
        #expect(restored.pendingScheduledSends().isEmpty)
        await restored.disconnect()
    }

    @Test(
        "unsupported signing and encryption are never queued or sent as plaintext",
        arguments: [OutboundMessageSecurityMode.sign, .encrypt, .signAndEncrypt]
    )
    func protectedMailRequiresCrypto(_ mode: OutboundMessageSecurityMode) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-schedule-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = DraftBackendTransport()
        let backend = try GmailAPIBackend(
            account: Self.account,
            transport: transport,
            store: SQLiteGmailAccountStore(databaseURL: url)
        )
        try await backend.connect()
        let draft = Draft(id: "protected", to: [.init(email: "to@example.org")], subject: "Protected",
                          scheduledFor: Date().addingTimeInterval(3600), securityMode: mode)
        await #expect(throws: OutboundCryptoEngineUnavailableError.self) { _ = try await backend.send(draft: draft) }
        #expect(backend.pendingScheduledSends().isEmpty)
        #expect(await transport.rawSendCount() == 0)
        await backend.disconnect()
    }

    @Test("ambiguous scheduled delivery remains held across repeat passes and restart")
    func ambiguousScheduleRequiresReview() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-schedule-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = DraftBackendTransport()
        await transport.setSendError(.ambiguousSendOutcome)
        let store = try SQLiteGmailAccountStore(databaseURL: url)
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        try await backend.connect()
        _ = try await backend.send(draft: Draft(id: "uncertain", to: [.init(email: "to@example.org")], subject: "Review",
                                                scheduledFor: .distantPast))
        await backend.deliverDueScheduledSends()
        await backend.deliverDueScheduledSends()
        #expect(await transport.rawSendCount() == 1)
        #expect(backend.pendingScheduledSends().first?.state == .needsReview)
        await backend.disconnect()
        let restored = try GmailAPIBackend(
            account: Self.account,
            transport: transport,
            store: SQLiteGmailAccountStore(databaseURL: url)
        )
        try await restored.connect()
        await restored.deliverDueScheduledSends()
        #expect(await transport.rawSendCount() == 1)
        #expect(restored.pendingScheduledSends().first?.state == .needsReview)
        await #expect(throws: GmailScheduledSendError.self) {
            try await restored.rescheduleSend(id: "uncertain", for: .distantPast)
        }
        #expect(restored.pendingScheduledSends().first?.state == .needsReview)
        await transport.setSendError(nil)
        try await restored.retryReviewedScheduledSend(id: "uncertain", for: .distantPast)
        await restored.deliverDueScheduledSends()
        #expect(await transport.rawSendCount() == 2)
        #expect(restored.pendingScheduledSends().isEmpty)
        await restored.disconnect()
    }

    @Test("delivery uses submitted content and preserves later unscheduled edits")
    func scheduledContentIsFrozen() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-schedule-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = DraftBackendTransport()
        let store = try SQLiteGmailAccountStore(databaseURL: url)
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        try await backend.connect()
        let draft = try await backend.save(draft: Draft(id: "frozen-local", to: [.init(email: "to@example.org")],
                                                        subject: "Frozen", htmlBody: "<p>Submitted snapshot</p>",
                                                        scheduledFor: Date().addingTimeInterval(3600)))
        _ = try await backend.send(draft: draft)
        var edited = draft
        edited.htmlBody = "<p>Later unscheduled edits</p>"
        edited.scheduledFor = nil
        _ = try await backend.save(draft: edited)
        try await backend.rescheduleSend(id: draft.id, for: .distantPast)
        await backend.deliverDueScheduledSends()
        let sent = try #require(await transport.sentRawMIME())
        #expect(sent.contains("Submitted snapshot"))
        #expect(!sent.contains("Later unscheduled edits"))
        #expect(try await store.draft(accountID: Self.account.id, draftID: draft.id)?.htmlBody == edited.htmlBody)
        #expect(await transport.deletedDraftIDs().isEmpty)
        await backend.disconnect()
    }

    @Test("saving a draft with a chosen date does not submit scheduling intent")
    func autosaveDoesNotSchedule() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-schedule-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let backend = try GmailAPIBackend(account: Self.account, transport: DraftBackendTransport(),
                                          store: SQLiteGmailAccountStore(databaseURL: url))
        try await backend.connect()
        _ = try await backend.save(draft: Draft(
            id: "not-submitted",
            subject: "Still composing",
            scheduledFor: Date().addingTimeInterval(3600)
        ))
        let service = try #require(backend.extensionService(ScheduledSendManaging.self))
        #expect(service.pendingScheduledSends().isEmpty)
        await backend.disconnect()
    }

    @Test("due scheduled mail is sent once and removed from the durable queue")
    func deliversDueScheduleOnce() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-schedule-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = DraftBackendTransport()
        let store = try SQLiteGmailAccountStore(databaseURL: url)
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        try await backend.connect()
        let draft = Draft(id: "due-local", to: [.init(email: "to@example.org")], subject: "Due now",
                          htmlBody: "<p>Submitted content</p>", scheduledFor: .distantPast)
        _ = try await backend.send(draft: draft)
        await backend.deliverDueScheduledSends()
        await backend.deliverDueScheduledSends()
        #expect(await transport.sentRawMIME()?.contains("Submitted content") == true)
        #expect(await transport.rawSendCount() == 1)
        #expect(backend.pendingScheduledSends().isEmpty)
        #expect(try await store.scheduledDraft(accountID: Self.account.id, draftID: draft.id) == nil)
        await backend.disconnect()
    }

    @Test("explicit scheduling persists without submitting mail and survives restart")
    func schedulesWithoutSending() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-schedule-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = DraftBackendTransport()
        let due = Date().addingTimeInterval(3600)
        let draft = Draft(id: "scheduled-local", to: [.init(email: "to@example.org")], subject: "Later",
                          htmlBody: "<p>Frozen content</p>", scheduledFor: due)
        do {
            let store = try SQLiteGmailAccountStore(databaseURL: url)
            let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
            try await backend.connect()
            let result = try await backend.send(draft: draft)
            #expect(result.sentMessageID == nil)
            #expect(result.scheduledFor == due)
            let service = try #require(backend.extensionService(ScheduledSendManaging.self))
            #expect(service.pendingScheduledSends().map(\.draftID) == [draft.id])
            #expect(await transport.sentRawMIME() == nil)
            #expect(await transport.sentDraftID() == nil)
            await backend.disconnect()
        }
        let store = try SQLiteGmailAccountStore(databaseURL: url)
        let restored = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        try await restored.connect()
        let service = try #require(restored.extensionService(ScheduledSendManaging.self))
        #expect(service.pendingScheduledSends().map(\.draftID) == [draft.id])
        #expect(await transport.sentRawMIME() == nil)
        await restored.disconnect()
    }

    @Test("disconnect prevents a late connect response from reactivating compose writes")
    func lateConnectCannotReactivateDrafts() async throws {
        let transport = DraftBackendTransport()
        await transport.pauseNextProfile()
        let backend = Self.backend(transport: transport)
        let connection = Task { try await backend.connect() }
        await transport.waitForProfileStart()
        await backend.disconnect()
        await transport.releaseProfile()
        await #expect(throws: MailBackendError.self) { try await connection.value }
        await #expect(throws: MailBackendError.self) {
            _ = try await backend.uploadAttachment(draftID: "retired", data: Data([1]), filename: "note", mimeType: "text/plain")
        }
        #expect(backend.capabilities.isEmpty)
    }

    @Test("a pending save rejects overlapping save, send and discard for the same draft")
    func draftMutationsAreSingleFlight() async throws {
        let transport = DraftBackendTransport()
        let backend = Self.backend(transport: transport)
        try await backend.connect()
        await transport.pauseNextSave()
        let draft = Draft(id: "local", to: [.init(email: "to@example.org")], subject: "One operation")
        let first = Task { try await backend.save(draft: draft) }
        await transport.waitForSaveStart()
        await #expect(throws: GmailDraftOperationError.busy) { _ = try await backend.save(draft: draft) }
        await #expect(throws: GmailDraftOperationError.busy) { _ = try await backend.send(draft: draft) }
        await #expect(throws: GmailDraftOperationError.busy) { try await backend.discard(draftID: draft.id) }
        await transport.releaseSave()
        _ = try await first.value
        #expect(await transport.sentRawMIME() == nil)
        #expect(await transport.deletedDraftIDs().isEmpty)
        _ = try await backend.save(draft: draft)
        await backend.disconnect()
    }

    @Test("an old save acknowledgement cannot recreate staging after removing and re-adding the account")
    func retiredSaveCannotRecreateStaging() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-compose-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = DraftBackendTransport()
        let store = try SQLiteGmailAccountStore(databaseURL: url)
        let old = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        try await old.connect()
        await transport.pauseNextSave()
        let save = Task { try await old.save(draft: Draft(id: "old-local", subject: "Old session")) }
        await transport.waitForSaveStart()
        await old.disconnect()
        do {
            try await store.removeAccount(accountID: Self.account.id)
            let replacement = GmailAPIBackend(account: Self.account, transport: transport, store: store)
            try await replacement.connect()
            await transport.releaseSave()
            let result = try await save.value
            #expect(result.remoteID == "remote-draft-1")
            #expect(try await store.draft(accountID: Self.account.id, draftID: "old-local") == nil)
            await replacement.disconnect()
        } catch {
            await transport.releaseSave()
            _ = await save.result
            throw error
        }
    }

    @Test("failed remote discard preserves local draft recovery", arguments: [403, 500])
    func failedDiscardKeepsStaging(_ status: Int) async throws {
        let transport = DraftBackendTransport()
        let staging = InMemoryGmailDraftStagingStore()
        let draft = Draft(id: "local", remoteID: "remote", subject: "Keep until confirmed")
        await staging.setDraft(draft, accountID: Self.account.id)
        let backend = Self.backend(transport: transport, staging: staging)
        try await backend.connect()
        await transport.setDeleteError(.httpFailure(statusCode: status))
        await #expect(throws: GmailAPIError.httpFailure(statusCode: status)) { try await backend.discard(draftID: "local") }
        #expect(await staging.draft(accountID: Self.account.id, draftID: "local") == draft)
    }

    @Test("discard can finish local cleanup when the remote draft is already gone")
    func discardMissingRemoteDraft() async throws {
        let transport = DraftBackendTransport()
        let staging = InMemoryGmailDraftStagingStore()
        let draft = Draft(id: "local", remoteID: "remote", subject: "Discarded")
        await staging.setDraft(draft, accountID: Self.account.id)
        let backend = Self.backend(transport: transport, staging: staging)
        try await backend.connect()
        await transport.setDeleteError(.httpFailure(statusCode: 404))
        try await backend.discard(draftID: "local")
        #expect(await staging.draft(accountID: Self.account.id, draftID: "local") == nil)
    }

    @Test("a staging failure prevents provider submission")
    func stagingFailureStopsSubmission() async throws {
        let transport = DraftBackendTransport()
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: InMemoryGmailAccountStore(),
                                      draftStaging: FailingDraftStaging(failRemoteAcknowledgement: false))
        try await backend.connect()
        let draft = Draft(id: "local", to: [.init(email: "to@example.org")], subject: "Do not lose")
        await #expect(throws: GmailAccountStoreError.databaseFailure) { _ = try await backend.save(draft: draft) }
        await #expect(throws: GmailAccountStoreError.databaseFailure) { _ = try await backend.send(draft: draft) }
        #expect(await transport.createdRawMIME() == nil)
        #expect(await transport.sentRawMIME() == nil)
        #expect(await transport.sentDraftID() == nil)
    }

    @Test("a local cleanup failure cannot turn confirmed delivery into a failed send")
    func sentMessageSurvivesCleanupFailure() async throws {
        let transport = DraftBackendTransport()
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: InMemoryGmailAccountStore(),
                                      draftStaging: FailingDraftStaging(failRemoteAcknowledgement: true))
        try await backend.connect()
        let result = try await backend.send(draft: Draft(id: "local", to: [.init(email: "to@example.org")], subject: "Once"))
        #expect(result.sentMessageID == "sent-message-1")
        let health = await backend.syncHealth(for: MailSourceID(accountID: Self.account.id, mailboxID: Self.account.id))
        #expect(health.lastErrorDescription != nil)
    }

    @Test("a confirmed remote draft save returns its identity even if local acknowledgement fails")
    func remoteSaveSurvivesLocalAcknowledgementFailure() async throws {
        let transport = DraftBackendTransport()
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: InMemoryGmailAccountStore(),
                                      draftStaging: FailingDraftStaging(failRemoteAcknowledgement: true))
        try await backend.connect()
        let saved = try await backend.save(draft: Draft(id: "local", subject: "Keep remote identity"))
        #expect(saved.remoteID == "remote-draft-1")
        let health = await backend.syncHealth(for: MailSourceID(accountID: Self.account.id, mailboxID: Self.account.id))
        #expect(health.lastErrorDescription != nil)
    }

    @Test("the default SQLite-backed adapter retains compose attachments across restart")
    func defaultStagingSurvivesRestart() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-compose-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = DraftBackendTransport()
        var saved: Draft
        do {
            let store = try SQLiteGmailAccountStore(databaseURL: url)
            let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
            try await backend.connect()
            let part = try await backend.uploadAttachment(draftID: "local-restart", data: Data([0, 255, 128, 1]),
                                                          filename: "original.bin", mimeType: "application/octet-stream")
            saved = try await backend.save(draft: Draft(id: "local-restart", to: [.init(email: "to@example.org")],
                                                        subject: "Recovery", htmlBody: "<p>First</p>", attachmentIDs: [part]))
            await backend.disconnect()
        }
        let store = try SQLiteGmailAccountStore(databaseURL: url)
        let backend = GmailAPIBackend(account: Self.account, transport: transport, store: store)
        try await backend.connect()
        saved.htmlBody = "<p>Recovered and edited</p>"
        _ = try await backend.save(draft: saved)
        let MIME = try #require(await transport.createdRawMIME())
        #expect(MIME.contains("AP+AAQ=="))
        #expect(MIME.contains("Recovered and edited"))
        #expect(await transport.updatedDraftID() == saved.remoteID)
        await backend.disconnect()
    }

    @Test("saves drafts with Gmail MIME and staged attachments")
    func savesDraft() async throws {
        let transport = DraftBackendTransport()
        let staging = InMemoryGmailDraftStagingStore()
        let backend = Self.backend(
            transport: transport,
            staging: staging,
            grantedScopes: ["https://www.googleapis.com/auth/gmail.settings.basic"]
        )
        try await backend.connect()
        let attachmentID = try await backend.uploadAttachment(
            draftID: "local-1",
            data: Data("attachment".utf8),
            filename: "note.txt",
            mimeType: "text/plain"
        )
        let draft = Draft(
            id: "local-1",
            to: [Correspondent(email: "to@example.com")],
            subject: "Draft subject",
            htmlBody: "<p>Draft body</p>",
            attachmentIDs: [attachmentID]
        )

        let saved = try await backend.save(draft: draft)

        #expect(saved.remoteID == "remote-draft-1")
        let raw = try #require(await transport.createdRawMIME())
        #expect(raw.contains("From: Primary <primary@example.com>"))
        #expect(raw.contains("Subject: Draft subject"))
        #expect(raw.contains("note.txt"))
        #expect(raw.contains("Draft body"))

        var updated = saved
        updated.subject = "Updated subject"
        _ = try await backend.save(draft: updated)
        #expect(await transport.updatedDraftID() == "remote-draft-1")
        try await backend.discard(draftID: "remote-draft-1")
        #expect(await transport.deletedDraftIDs() == ["remote-draft-1"])
    }

    @Test("preserves the provider-neutral thread ID across draft writes and raw sends")
    func preservesThreadIDAcrossWritesAndSends() async throws {
        let transport = DraftBackendTransport()
        let backend = Self.backend(
            transport: transport,
            grantedScopes: ["https://www.googleapis.com/auth/gmail.settings.basic"]
        )
        try await backend.connect()
        let draft = Draft(
            id: "reply-1",
            threadID: "gmail-thread-42",
            inReplyToMessageID: "original@example.com",
            to: [Correspondent(email: "to@example.com")],
            subject: "Re: Thread",
            htmlBody: "<p>Reply</p>"
        )

        let saved = try await backend.save(draft: draft)
        #expect(await transport.createdThreadID() == "gmail-thread-42")

        _ = try await backend.save(draft: saved)
        #expect(await transport.updatedThreadID() == "gmail-thread-42")

        var unsaved = draft
        unsaved.remoteID = nil
        _ = try await backend.send(draft: unsaved)
        #expect(await transport.sentThreadID() == "gmail-thread-42")
        let raw = try #require(await transport.sentRawMIME())
        #expect(raw.contains("In-Reply-To: <original@example.com>"))
        #expect(raw.contains("References: <original@example.com>"))
    }

    @Test("sends through Gmail and preserves staged draft on ambiguous delivery")
    func sendsAndPreservesAmbiguous() async throws {
        let transport = DraftBackendTransport()
        let staging = InMemoryGmailDraftStagingStore()
        let backend = Self.backend(transport: transport, staging: staging)
        try await backend.connect()
        let draft = Draft(
            id: "local-send",
            remoteID: "remote-send",
            to: [Correspondent(email: "to@example.com")],
            subject: "Send subject",
            htmlBody: "<p>Send body</p>"
        )

        let result = try await backend.send(draft: draft)
        #expect(result.sentMessageID == "sent-message-1")
        #expect(await transport.sentDraftID() == "remote-send")

        await transport.setSendDraftError(.ambiguousSendOutcome)
        do {
            _ = try await backend.send(draft: draft)
            Issue.record("Expected ambiguous delivery")
        } catch let error as GmailAPIError {
            #expect(error.isAmbiguousSend)
            #expect(await staging.draft(accountID: Self.account.id, draftID: draft.id) != nil)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("maps existing Gmail aliases and per-alias signatures")
    func mapsAliasesAndSignatures() async throws {
        let transport = DraftBackendTransport(sendAs: [
            GmailSendAs(
                sendAsEmail: "primary@example.com",
                displayName: "Primary",
                signature: "<p>Primary</p>",
                isPrimary: true,
                isDefault: true
            ),
            GmailSendAs(
                sendAsEmail: "team@example.com",
                displayName: "Team",
                signature: "<p>Team</p>",
                isPrimary: false,
                isDefault: false
            )
        ])
        let backend = Self.backend(
            transport: transport,
            grantedScopes: ["https://www.googleapis.com/auth/gmail.settings.basic"]
        )
        try await backend.connect()

        let aliases = try await backend.listAliases()
        let signatures = try await backend.listServerSignatures()

        #expect(aliases.map(\.email) == ["primary@example.com", "team@example.com"])
        #expect(aliases.first?.isDefault == true)
        #expect(signatures.map(\.body) == ["<p>Primary</p>", "<p>Team</p>"])
        #expect(backend.extendedCapabilities.contains(.serverAliases))
        #expect(backend.extendedCapabilities.contains(.serverSignatures))
    }

    @Test("does not advertise send-as capabilities without a granted settings scope")
    func hidesSendAsWithoutScope() async throws {
        let backend = Self.backend(transport: DraftBackendTransport(sendAs: []))
        try await backend.connect()

        #expect(!backend.capabilities.contains(.aliases))
        #expect(!backend.capabilities.contains(.serverSignatures))
        #expect(!backend.extendedCapabilities.contains(.serverAliases))
        #expect(!backend.extendedCapabilities.contains(.sendAs))
    }

    @Test("Workspace policy failure keeps send-as capabilities disabled")
    func hidesSendAsWhenWorkspacePolicyBlocksMetadata() async throws {
        let transport = DraftBackendTransport(
            sendAs: [],
            sendAsError: .domainPolicy
        )
        let backend = Self.backend(
            transport: transport,
            grantedScopes: ["https://www.googleapis.com/auth/gmail.settings.basic"]
        )
        try await backend.connect()

        #expect(!backend.capabilities.contains(.aliases))
        #expect(!backend.capabilities.contains(.serverSignatures))
        #expect(!backend.extendedCapabilities.contains(.serverAliases))
    }

    @Test("does not offer pending verification aliases for send or signatures")
    func hidesPendingVerificationAliases() async throws {
        let transport = DraftBackendTransport(sendAs: [
            GmailSendAs(
                sendAsEmail: "primary@example.com",
                isPrimary: true,
                isDefault: true
            ),
            GmailSendAs(
                sendAsEmail: "pending@example.com",
                signature: "Pending",
                verificationStatus: "pending"
            )
        ])
        let backend = Self.backend(
            transport: transport,
            grantedScopes: ["https://www.googleapis.com/auth/gmail.settings.basic"]
        )
        try await backend.connect()

        #expect(try await backend.listAliases().map(\.email) == ["primary@example.com"])
        #expect(try await backend.listServerSignatures().isEmpty)
        #expect(!backend.extendedCapabilities.contains(.sendAs))
    }

    @Test("staging enforces an explicit aggregate byte bound")
    func stagingBound() async throws {
        let staging = InMemoryGmailDraftStagingStore(maxBytes: 4)
        let attachment = GmailStagedAttachment(
            id: "a1",
            draftID: "d1",
            filename: "a.txt",
            mimeType: "text/plain",
            data: Data(repeating: 1, count: 5)
        )
        await #expect(throws: GmailDraftStagingError.capacityExceeded(limit: 4)) {
            try await staging.setAttachment(attachment, accountID: Self.account.id)
        }
    }

    private static let account = BrevAccount(
        id: "gmail-api:subject",
        displayName: "Primary",
        emailAddress: "primary@example.com",
        backendIdentifier: "gmail-api",
        backendDisplayName: "Gmail"
    )

    private static func backend(
        transport: DraftBackendTransport,
        staging: InMemoryGmailDraftStagingStore = InMemoryGmailDraftStagingStore(),
        grantedScopes: Set<String> = []
    ) -> GmailAPIBackend {
        GmailAPIBackend(
            account: account,
            transport: transport,
            store: InMemoryGmailAccountStore(),
            grantedScopes: grantedScopes,
            draftStaging: staging
        )
    }
}

private actor FailingDraftStaging: GmailDraftStagingStore {
    let failRemoteAcknowledgement: Bool
    init(failRemoteAcknowledgement: Bool) { self.failRemoteAcknowledgement = failRemoteAcknowledgement }
    func draft(accountID: String, draftID: String) -> Draft? { nil }
    func setDraft(_ draft: Draft, accountID: String) throws {
        if !failRemoteAcknowledgement || draft.remoteID != nil { throw GmailAccountStoreError.databaseFailure }
    }

    func attachment(accountID: String, attachmentID: String) -> GmailStagedAttachment? { nil }
    func setAttachment(_ attachment: GmailStagedAttachment, accountID: String) throws {
        throw GmailAccountStoreError.databaseFailure
    }

    func removeDraft(accountID: String, draftID: String) throws { throw GmailAccountStoreError.databaseFailure }
    func clear(accountID: String) {}
}

private actor DraftBackendTransport: GmailAPITransporting {
    private let sendAs: [GmailSendAs]
    private let sendAsError: GmailAPIError?
    private var createdMIME: String?
    private var sentMIME: String?
    private var rawSendAttempts = 0
    private var updatedID: String?
    private var deletedIDs: [String] = []
    private var sentDraft: String?
    private var createdThread: String?
    private var updatedThread: String?
    private var sentThread: String?
    var sendError: GmailAPIError?
    var sendDraftError: GmailAPIError?
    private var deleteError: GmailAPIError?
    private var pausesSave = false
    private var saveStarted = false
    private var saveRelease: CheckedContinuation<Void, Never>?
    private var saveStartedWaiter: CheckedContinuation<Void, Never>?
    private var pausesProfile = false
    private var profileStarted = false
    private var profileRelease: CheckedContinuation<Void, Never>?
    private var profileStartedWaiter: CheckedContinuation<Void, Never>?
    private var pausesSend = false
    private var sendStarted = false
    private var sendRelease: CheckedContinuation<Void, Never>?
    private var sendStartedWaiter: CheckedContinuation<Void, Never>?

    init(sendAs: [GmailSendAs] = [GmailSendAs(
        sendAsEmail: "primary@example.com",
        displayName: "Primary",
        isPrimary: true,
        isDefault: true
    )], sendAsError: GmailAPIError? = nil) {
        self.sendAs = sendAs
        self.sendAsError = sendAsError
    }

    func profile() async throws -> GmailProfile {
        if pausesProfile {
            profileStarted = true
            profileStartedWaiter?.resume()
            profileStartedWaiter = nil
            await withCheckedContinuation { profileRelease = $0 }
        }
        return GmailProfile(emailAddress: "primary@example.com", historyID: "history-1")
    }

    func listLabels() async throws -> [GmailLabel] {
        [GmailLabel(id: "INBOX", name: "Inbox", type: "system")]
    }

    func listMessages(labelID: String?, query: String?, pageToken: String?, maxResults: Int) async throws -> GmailMessagePage {
        GmailMessagePage()
    }

    func getMessage(messageID: String, format: GmailMessageFormat) async throws -> GmailMessage {
        GmailMessage(id: messageID)
    }

    func getAttachment(messageID: String, attachmentID: String) async throws -> GmailAttachment {
        GmailAttachment(id: attachmentID, messageID: messageID)
    }

    func createDraft(rawMIME: String, threadID: String?) async throws -> GmailDraft {
        createdMIME = rawMIME
        createdThread = threadID
        if pausesSave {
            saveStarted = true
            saveStartedWaiter?.resume()
            saveStartedWaiter = nil
            await withCheckedContinuation { saveRelease = $0 }
        }
        return GmailDraft(id: "remote-draft-1")
    }

    func updateDraft(id: String, rawMIME: String, threadID: String?) async throws -> GmailDraft {
        createdMIME = rawMIME
        updatedID = id
        updatedThread = threadID
        return GmailDraft(id: id)
    }

    func deleteDraft(id: String) async throws {
        if let deleteError { throw deleteError }
        deletedIDs.append(id)
    }

    func sendDraft(id: String) async throws -> GmailMessage {
        if let sendDraftError { throw sendDraftError }
        sentDraft = id
        return GmailMessage(id: "sent-message-1")
    }

    func sendMessage(rawMIME: String, threadID: String?) async throws -> GmailMessage {
        rawSendAttempts += 1
        if let sendError { throw sendError }
        if pausesSend {
            sendStarted = true
            sendStartedWaiter?.resume()
            sendStartedWaiter = nil
            await withCheckedContinuation { sendRelease = $0 }
        }
        sentMIME = rawMIME
        sentThread = threadID
        return GmailMessage(id: "sent-message-1")
    }

    func listSendAs() async throws -> [GmailSendAs] {
        if let sendAsError { throw sendAsError }
        return sendAs
    }

    func setSendError(_ error: GmailAPIError?) { sendError = error }
    func pauseNextSend() { pausesSend = true; sendStarted = false }
    func waitForSendStart() async {
        if sendStarted { return }
        await withCheckedContinuation { sendStartedWaiter = $0 }
    }

    func releaseSend() {
        pausesSend = false
        sendRelease?.resume()
        sendRelease = nil
    }

    func pauseNextProfile() { pausesProfile = true; profileStarted = false }
    func waitForProfileStart() async {
        if profileStarted { return }
        await withCheckedContinuation { profileStartedWaiter = $0 }
    }

    func releaseProfile() {
        pausesProfile = false
        profileRelease?.resume()
        profileRelease = nil
    }

    func pauseNextSave() { pausesSave = true; saveStarted = false }
    func waitForSaveStart() async {
        if saveStarted { return }
        await withCheckedContinuation { saveStartedWaiter = $0 }
    }

    func releaseSave() {
        pausesSave = false
        saveRelease?.resume()
        saveRelease = nil
    }

    func setDeleteError(_ error: GmailAPIError?) { deleteError = error }
    func setSendDraftError(_ error: GmailAPIError?) { sendDraftError = error }

    func createdRawMIME() -> String? { createdMIME }
    func sentRawMIME() -> String? { sentMIME }
    func rawSendCount() -> Int { rawSendAttempts }
    func updatedDraftID() -> String? { updatedID }
    func deletedDraftIDs() -> [String] { deletedIDs }
    func sentDraftID() -> String? { sentDraft }
    func createdThreadID() -> String? { createdThread }
    func updatedThreadID() -> String? { updatedThread }
    func sentThreadID() -> String? { sentThread }
}
