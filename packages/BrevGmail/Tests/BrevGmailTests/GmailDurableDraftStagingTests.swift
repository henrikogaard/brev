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

@Suite("Durable Gmail draft staging")
struct GmailDurableDraftStagingTests {
    @Test("staging adapters retire old remote aliases and clear pre-save attachments", arguments: [false, true])
    func stagingAdaptersShareIdentityCleanup(inMemory: Bool) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-draft-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let staging: any GmailDraftStagingStore
        if inMemory { staging = InMemoryGmailDraftStagingStore() }
        else { staging = try await Self.store(at: url, accounts: ["a"]) }
        try await staging.setDraft(Draft(id: "local", remoteID: "old"), accountID: "a")
        try await staging.setDraft(Draft(id: "local", remoteID: "new"), accountID: "a")
        #expect(try await staging.draft(accountID: "a", draftID: "old") == nil)
        #expect(try await staging.draft(accountID: "a", draftID: "new")?.id == "local")
        try await staging.setAttachment(GmailStagedAttachment(id: "part", draftID: "not-saved", filename: "note",
                                                              mimeType: "text/plain", data: Data([1])), accountID: "a")
        try await staging.removeDraft(accountID: "a", draftID: "not-saved")
        #expect(try await staging.attachment(accountID: "a", attachmentID: "part") == nil)
    }

    @Test("database write failures surface without replacing the recoverable draft")
    func failedWriteKeepsPreviousDraft() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-draft-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let staging: any GmailDraftStagingStore = try await Self.store(at: url, accounts: ["a"])
        let original = Draft(id: "local", subject: "Keep this version")
        try await staging.setDraft(original, accountID: "a")
        try Self.execute("""
        CREATE TRIGGER reject_draft_write BEFORE INSERT ON gmail_staged_drafts
        BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END;
        """, at: url)
        await #expect(throws: GmailAccountStoreError.databaseFailure) {
            try await staging.setDraft(Draft(id: "local", subject: "Uncommitted"), accountID: "a")
        }
        #expect(try await staging.draft(accountID: "a", draftID: "local") == original)
    }

    @Test("version one account data survives adding durable staging")
    func migratesVersionOne() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-draft-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.execute("""
        CREATE TABLE gmail_accounts(account_id TEXT PRIMARY KEY NOT NULL, email_address TEXT NOT NULL,
          history_id TEXT, last_full_sync_at REAL, last_delta_sync_at REAL);
        INSERT INTO gmail_accounts(account_id, email_address, history_id) VALUES ('a', 'a@example.org', '42');
        PRAGMA user_version = 1;
        """, at: url)
        let store = try SQLiteGmailAccountStore(databaseURL: url)
        #expect(try await store.accountState(accountID: "a")?.historyID == "42")
        let staging: any GmailDraftStagingStore = store
        try await staging.setDraft(Draft(id: "local", subject: "After migration"), accountID: "a")
        #expect(try await staging.draft(accountID: "a", draftID: "local")?.subject == "After migration")
    }

    @Test("attachment limits survive restart and failed replacement preserves original content")
    func boundedAttachmentsAndRemoval() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-draft-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let first: any GmailDraftStagingStore = try await Self.store(at: url, accounts: ["a"], limit: 4)
        let original = GmailStagedAttachment(id: "part", draftID: "local", filename: "note", mimeType: "text/plain",
                                             data: Data([1, 2, 3]))
        try await first.setAttachment(original, accountID: "a")
        let second: any GmailDraftStagingStore = try SQLiteGmailAccountStore(databaseURL: url, maxStagedAttachmentBytes: 4)
        let another = GmailStagedAttachment(id: "another", draftID: "other", filename: "note", mimeType: "text/plain",
                                            data: Data([4, 5]))
        await #expect(throws: GmailDraftStagingError.capacityExceeded(limit: 4)) {
            try await second.setAttachment(another, accountID: "a")
        }
        let oversized = GmailStagedAttachment(id: "part", draftID: "local", filename: "note", mimeType: "text/plain",
                                              data: Data([1, 2, 3, 4, 5]))
        await #expect(throws: GmailDraftStagingError.capacityExceeded(limit: 4)) {
            try await second.setAttachment(oversized, accountID: "a")
        }
        #expect(try await second.attachment(accountID: "a", attachmentID: "part") == original)
        // Attachments can exist before the first draft save.
        try await second.removeDraft(accountID: "a", draftID: "local")
        #expect(try await first.attachment(accountID: "a", attachmentID: "part") == nil)
        try await second.setAttachment(another, accountID: "a")
        try await second.setDraft(Draft(id: "other", remoteID: "remote"), accountID: "a")
        try await first.removeDraft(accountID: "a", draftID: "remote")
        #expect(try await second.attachment(accountID: "a", attachmentID: "another") == nil)
        #expect(try await second.draft(accountID: "a", draftID: "other") == nil)
    }

    @Test("sync snapshots preserve compose staging while account removal deletes only its owner")
    func stagingLifetimeFollowsAccount() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-draft-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try await Self.store(at: url, accounts: ["a", "b"])
        let staging: any GmailDraftStagingStore = store
        let draft = Draft(id: "local", remoteID: "old-remote", subject: "Keep")
        let part = GmailStagedAttachment(id: "part", draftID: "local", filename: "note", mimeType: "text/plain", data: Data([1]))
        for account in ["a", "b"] {
            try await staging.setDraft(draft, accountID: account)
            try await staging.setAttachment(part, accountID: account)
        }
        try await store.replaceSnapshot(GmailAccountSnapshot(accountID: "a", state: GmailAccountState(
            accountID: "a", emailAddress: "a@example.org"
        ), labels: [], messages: []))
        try await store.removeAllCachedContent(accountID: "a")
        #expect(try await staging.draft(accountID: "a", draftID: "local") == draft)
        #expect(try await staging.attachment(accountID: "a", attachmentID: "part") == part)
        var updated = draft
        updated.remoteID = "new-remote"
        try await staging.setDraft(updated, accountID: "a")
        #expect(try await staging.draft(accountID: "a", draftID: "old-remote") == nil)
        #expect(try await staging.draft(accountID: "a", draftID: "new-remote") == updated)
        try await store.removeAccount(accountID: "a")
        #expect(try await staging.draft(accountID: "a", draftID: "local") == nil)
        #expect(try await staging.attachment(accountID: "a", attachmentID: "part") == nil)
        await #expect(throws: GmailAccountStoreError.databaseFailure) { try await staging.setDraft(draft, accountID: "a") }
        await #expect(throws: GmailAccountStoreError.databaseFailure) { try await staging.setAttachment(part, accountID: "a") }
        #expect(try await staging.draft(accountID: "b", draftID: "local") == draft)
        #expect(try await staging.attachment(accountID: "b", attachmentID: "part") == part)
    }

    @Test("draft identities and exact attachment bytes survive reopening the database")
    func stagingSurvivesRestart() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-draft-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let draft = Draft(id: "local", remoteID: "remote", to: [.init(email: "to@example.org")],
                          subject: "Recovery", htmlBody: "<p>Keep this</p>", attachmentIDs: ["part"])
        let attachment = GmailStagedAttachment(id: "part", draftID: "local", filename: "original.bin",
                                               mimeType: "application/octet-stream", data: Data([0, 255, 128, 1]))
        do {
            let store: any GmailDraftStagingStore = try await Self.store(at: url, accounts: ["account"])
            try await store.setAttachment(attachment, accountID: "account")
            try await store.setDraft(draft, accountID: "account")
        }
        let reopened: any GmailDraftStagingStore = try SQLiteGmailAccountStore(databaseURL: url)
        #expect(try await reopened.draft(accountID: "account", draftID: "local") == draft)
        #expect(try await reopened.draft(accountID: "account", draftID: "remote") == draft)
        #expect(try await reopened.attachment(accountID: "account", attachmentID: "part") == attachment)
        #expect(try await reopened.draft(accountID: "another", draftID: "local") == nil)
    }

    private static func store(at url: URL, accounts: [String],
                              limit: Int = 25 * 1024 * 1024) async throws -> SQLiteGmailAccountStore {
        let store = try SQLiteGmailAccountStore(databaseURL: url, maxStagedAttachmentBytes: limit)
        for account in accounts {
            try await store.replaceSnapshot(GmailAccountSnapshot(accountID: account, state: GmailAccountState(
                accountID: account, emailAddress: account + "@example.org"
            ), labels: [], messages: []))
        }
        return store
    }

    private static func execute(_ sql: String, at url: URL) throws {
        var database: OpaquePointer?
        let opened = sqlite3_open(url.path, &database)
        defer { sqlite3_close(database) }
        try #require(opened == SQLITE_OK)
        try #require(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
    }
}
