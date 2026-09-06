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
import Foundation
import SQLite3

/// SQLite-backed canonical Gmail account store.
public final class SQLiteGmailAccountStore: GmailReadCacheStore, GmailDraftStagingStore, GmailScheduledSendStore,
    @unchecked Sendable {
    private static let currentSchemaVersion = 3
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let lock = NSLock()
    private let database: OpaquePointer?
    private let maxStagedAttachmentBytes: Int

    /// Opens or creates a Gmail account database and migrates an empty schema.
    /// - Parameters:
    ///   - databaseURL: Local account database, including compose staging.
    ///   - maxStagedAttachmentBytes: Per-account attachment bound, default 25 MiB; values below one are clamped to one.
    public init(databaseURL: URL, maxStagedAttachmentBytes: Int = 25 * 1024 * 1024) throws {
        self.maxStagedAttachmentBytes = max(1, maxStagedAttachmentBytes)
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &pointer, flags, nil) == SQLITE_OK else {
            sqlite3_close(pointer)
            throw GmailAccountStoreError.openFailed
        }
        database = pointer
        sqlite3_busy_timeout(pointer, 3000)

        do {
            try configureAndMigrate()
        } catch {
            sqlite3_close(pointer)
            throw error is GmailAccountStoreError ? error : GmailAccountStoreError.migrationFailed
        }
    }

    deinit {
        sqlite3_close(database)
    }

    /// Removes all canonical records and cached content for `accountID`.
    public func removeAccount(accountID: String) async throws {
        try validate(accountID: accountID)
        try lock.withLock {
            try begin()
            do {
                try clearStaging(accountID: accountID)
                try execute("DELETE FROM gmail_attachments WHERE account_id = ?;", bindings: [.text(accountID)])
                try execute("DELETE FROM gmail_raw_sources WHERE account_id = ?;", bindings: [.text(accountID)])
                try execute("DELETE FROM gmail_bodies WHERE account_id = ?;", bindings: [.text(accountID)])
                try deleteAccount(accountID: accountID)
                try commit()
            } catch {
                try? rollback()
                throw normalized(error)
            }
        }
    }

    /// Returns current account state.
    public func accountState(accountID: String) async throws -> GmailAccountState? {
        try validate(accountID: accountID)
        return try readAccountState(accountID: accountID)
    }

    /// Atomically replaces all account data.
    public func replaceSnapshot(_ snapshot: GmailAccountSnapshot) async throws {
        try validate(snapshot: snapshot)
        try replaceSnapshotSynchronously(snapshot)
    }

    /// Atomically applies one history delta.
    public func apply(_ delta: GmailStoreDelta) async throws {
        try validate(accountID: delta.accountID)
        try applySynchronously(delta)
    }

    /// Lists account-wide messages in stable Gmail-ID order.
    public func messages(accountID: String) async throws -> [GmailMessage] {
        try validate(accountID: accountID)
        return try readMessages(accountID: accountID)
    }

    /// Reads only one label page in received-date order, with Gmail ID as a stable tie-breaker.
    public func messages(accountID: String, labelID: String, offset: Int, limit: Int) async throws -> [GmailMessage] {
        try validate(accountID: accountID)
        guard limit > 0 else { return [] }
        return try lock.withLock {
            let statement = try prepare("""
            SELECT m.message_json FROM gmail_messages AS m
            WHERE m.account_id = ? AND EXISTS (
                SELECT 1 FROM gmail_message_labels AS l
                WHERE l.account_id = m.account_id AND l.message_id = m.message_id AND l.label_id = ?
            )
            ORDER BY CAST(json_extract(CAST(m.message_json AS TEXT), '$.internalDate') AS INTEGER) DESC, m.message_id
            LIMIT ? OFFSET ?;
            """)
            defer { sqlite3_finalize(statement) }
            bind(accountID, to: statement, at: 1)
            bind(labelID, to: statement, at: 2)
            sqlite3_bind_int64(statement, 3, Int64(limit))
            sqlite3_bind_int64(statement, 4, Int64(max(0, offset)))
            var messages: [GmailMessage] = []
            var status = sqlite3_step(statement)
            while status == SQLITE_ROW {
                guard let data = blob(statement, column: 0),
                      let message = try? JSONDecoder().decode(GmailMessage.self, from: data)
                else { throw GmailAccountStoreError.malformedStoredMessage }
                messages.append(message)
                status = sqlite3_step(statement)
            }
            guard status == SQLITE_DONE else { throw GmailAccountStoreError.malformedStoredMessage }
            return messages
        }
    }

    /// Looks up one account-wide message.
    public func message(accountID: String, messageID: String) async throws -> GmailMessage? {
        try validate(accountID: accountID)
        try validate(messageID: messageID)
        return try readMessage(accountID: accountID, messageID: messageID)
    }

    /// Lists the label catalog in stable Gmail-ID order.
    public func labels(accountID: String) async throws -> [GmailLabel] {
        try validate(accountID: accountID)
        return try readLabels(accountID: accountID)
    }

    /// Returns the persisted many-to-many label joins for one message.
    public func messageLabelIDs(accountID: String, messageID: String) async throws -> [String] {
        try validate(accountID: accountID)
        try validate(messageID: messageID)
        return try readMessageLabelIDs(accountID: accountID, messageID: messageID)
    }

    public func cachedBody(accountID: String, messageID: String) async throws -> MessageBody? {
        try validate(accountID: accountID)
        try validate(messageID: messageID)
        return try lock.withLock {
            let statement = try prepare("SELECT body_json FROM gmail_bodies WHERE account_id = ? AND message_id = ?;")
            defer { sqlite3_finalize(statement) }
            bind(accountID, to: statement, at: 1)
            bind(messageID, to: statement, at: 2)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            guard let data = blob(statement, column: 0),
                  let body = try? JSONDecoder().decode(MessageBody.self, from: data)
            else { throw GmailAccountStoreError.malformedStoredMessage }
            return body
        }
    }

    public func storeBody(_ body: MessageBody, accountID: String) async throws {
        try validate(accountID: accountID)
        try validate(messageID: body.messageID)
        let data = try JSONEncoder().encode(body)
        try lock.withLock {
            try execute("""
            INSERT INTO gmail_bodies (account_id, message_id, body_json)
            VALUES (?, ?, ?)
            ON CONFLICT(account_id, message_id) DO UPDATE SET body_json = excluded.body_json;
            """, bindings: [.text(accountID), .text(body.messageID), .blob(data)])
        }
    }

    public func cachedRawSource(accountID: String, messageID: String) async throws -> String? {
        try validate(accountID: accountID)
        try validate(messageID: messageID)
        return try lock.withLock {
            let statement = try prepare("SELECT raw_source FROM gmail_raw_sources WHERE account_id = ? AND message_id = ?;")
            defer { sqlite3_finalize(statement) }
            bind(accountID, to: statement, at: 1)
            bind(messageID, to: statement, at: 2)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            if sqlite3_column_type(statement, 0) == SQLITE_BLOB, let data = blob(statement, column: 0) {
                return IMAPMessageBodyParser().rawMessageString(from: data)
            }
            return string(statement, column: 0)
        }
    }

    public func storeRawSource(_ source: String, accountID: String, messageID: String) async throws {
        try validate(accountID: accountID)
        try validate(messageID: messageID)
        try lock.withLock {
            try execute("""
            INSERT INTO gmail_raw_sources (account_id, message_id, raw_source)
            VALUES (?, ?, ?)
            ON CONFLICT(account_id, message_id) DO UPDATE SET raw_source = excluded.raw_source;
            """, bindings: [.text(accountID), .text(messageID), .text(source)])
        }
    }

    /// Only BLOB entries preserve original octets; older TEXT entries remain rendering-only.
    public func cachedRawMessageData(accountID: String, messageID: String) async throws -> Data? {
        try validate(accountID: accountID)
        try validate(messageID: messageID)
        return try lock.withLock {
            let statement = try prepare("SELECT raw_source FROM gmail_raw_sources WHERE account_id = ? AND message_id = ?;")
            defer { sqlite3_finalize(statement) }
            bind(accountID, to: statement, at: 1)
            bind(messageID, to: statement, at: 2)
            guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) == SQLITE_BLOB else { return nil }
            return blob(statement, column: 0)
        }
    }

    /// Stores original MIME as BLOB in the existing cache table, preserving its purge lifecycle.
    public func storeRawMessageData(_ data: Data, accountID: String, messageID: String) async throws {
        try validate(accountID: accountID)
        try validate(messageID: messageID)
        try lock.withLock {
            try execute("""
            INSERT INTO gmail_raw_sources (account_id, message_id, raw_source)
            VALUES (?, ?, ?)
            ON CONFLICT(account_id, message_id) DO UPDATE SET raw_source = excluded.raw_source;
            """, bindings: [.text(accountID), .text(messageID), .blob(data)])
        }
    }

    public func cachedAttachment(accountID: String, attachmentID: String) async throws -> Data? {
        try validate(accountID: accountID)
        try validate(messageID: attachmentID)
        return try lock.withLock {
            let statement = try prepare("SELECT data FROM gmail_attachments WHERE account_id = ? AND attachment_id = ?;")
            defer { sqlite3_finalize(statement) }
            bind(accountID, to: statement, at: 1)
            bind(attachmentID, to: statement, at: 2)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return blob(statement, column: 0)
        }
    }

    public func storeAttachment(_ data: Data, accountID: String, attachmentID: String) async throws {
        try validate(accountID: accountID)
        try validate(messageID: attachmentID)
        try lock.withLock {
            try execute("""
            INSERT INTO gmail_attachments (account_id, attachment_id, data)
            VALUES (?, ?, ?)
            ON CONFLICT(account_id, attachment_id) DO UPDATE SET data = excluded.data;
            """, bindings: [.text(accountID), .text(attachmentID), .blob(data)])
        }
    }

    private func configureAndMigrate() throws {
        try execute("PRAGMA foreign_keys = ON;")
        guard let database else { throw GmailAccountStoreError.migrationFailed }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK else {
            throw GmailAccountStoreError.migrationFailed
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw GmailAccountStoreError.migrationFailed
        }
        let version = Int(sqlite3_column_int64(statement, 0))
        guard version <= Self.currentSchemaVersion else {
            throw GmailAccountStoreError.migrationFailed
        }
        try executeScript(Self.schemaSQL)
        if version < Self.currentSchemaVersion {
            try execute("PRAGMA user_version = \(Self.currentSchemaVersion);")
        }
    }

    private func replaceSnapshotSynchronously(_ snapshot: GmailAccountSnapshot) throws {
        try lock.withLock {
            try begin()
            do {
                try pruneCachedContent(
                    accountID: snapshot.accountID,
                    keepingMessageIDs: Set(snapshot.messages.map(\.id)),
                    keepingAttachmentIDs: Set(snapshot.messages.flatMap(Self.attachmentIDs))
                )
                try execute("DELETE FROM gmail_message_labels WHERE account_id = ?;", bindings: [.text(snapshot.accountID)])
                try execute("DELETE FROM gmail_messages WHERE account_id = ?;", bindings: [.text(snapshot.accountID)])
                try execute("DELETE FROM gmail_labels WHERE account_id = ?;", bindings: [.text(snapshot.accountID)])
                try insertState(snapshot.state)
                for label in snapshot.labels {
                    try insertLabel(label, accountID: snapshot.accountID)
                }
                for message in snapshot.messages {
                    try insertMessage(message, accountID: snapshot.accountID)
                }
                try commit()
            } catch {
                try? rollback()
                throw normalized(error)
            }
        }
    }

    private func applySynchronously(_ delta: GmailStoreDelta) throws {
        try lock.withLock {
            try begin()
            do {
                guard try accountExists(accountID: delta.accountID) else {
                    throw GmailAccountStoreError.accountMismatch
                }
                for label in delta.upsertedLabels {
                    try validate(label: label)
                    try insertLabel(label, accountID: delta.accountID)
                }
                for labelID in delta.removedLabelIDs {
                    try validate(labelID: labelID)
                    try execute(
                        "DELETE FROM gmail_labels WHERE account_id = ? AND label_id = ?;",
                        bindings: [.text(delta.accountID), .text(labelID)]
                    )
                    try scrubLabelFromMessages(accountID: delta.accountID, labelID: labelID)
                }
                for message in delta.upsertedMessages {
                    try validate(message: message)
                    try insertMessage(message, accountID: delta.accountID)
                }
                for messageID in delta.removedMessageIDs {
                    try validate(messageID: messageID)
                    try execute(
                        "DELETE FROM gmail_messages WHERE account_id = ? AND message_id = ?;",
                        bindings: [.text(delta.accountID), .text(messageID)]
                    )
                }
                try updateState(accountID: delta.accountID, historyID: delta.historyID, lastDeltaSyncAt: delta.lastDeltaSyncAt)
                try commit()
            } catch {
                try? rollback()
                throw normalized(error)
            }
        }
    }

    private func readAccountState(accountID: String) throws -> GmailAccountState? {
        try lock.withLock {
            let statement = try prepare("""
            SELECT email_address, history_id, last_full_sync_at, last_delta_sync_at
            FROM gmail_accounts WHERE account_id = ?;
            """)
            defer { sqlite3_finalize(statement) }
            bind(accountID, to: statement, at: 1)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return GmailAccountState(
                accountID: accountID,
                emailAddress: string(statement, column: 0) ?? "",
                historyID: string(statement, column: 1),
                lastFullSyncAt: date(statement, column: 2),
                lastDeltaSyncAt: date(statement, column: 3)
            )
        }
    }

    private func readMessages(accountID: String) throws -> [GmailMessage] {
        try lock.withLock {
            let statement = try prepare("""
            SELECT message_json FROM gmail_messages
            WHERE account_id = ? ORDER BY message_id ASC;
            """)
            defer { sqlite3_finalize(statement) }
            bind(accountID, to: statement, at: 1)
            var result: [GmailMessage] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let data = blob(statement, column: 0),
                      let message = try? JSONDecoder().decode(GmailMessage.self, from: data)
                else { throw GmailAccountStoreError.malformedStoredMessage }
                result.append(message)
            }
            return result
        }
    }

    private func readMessage(accountID: String, messageID: String) throws -> GmailMessage? {
        try lock.withLock {
            let statement = try prepare("""
            SELECT message_json FROM gmail_messages
            WHERE account_id = ? AND message_id = ? LIMIT 1;
            """)
            defer { sqlite3_finalize(statement) }
            bind(accountID, to: statement, at: 1)
            bind(messageID, to: statement, at: 2)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            guard let data = blob(statement, column: 0),
                  let message = try? JSONDecoder().decode(GmailMessage.self, from: data)
            else { throw GmailAccountStoreError.malformedStoredMessage }
            return message
        }
    }

    private func readLabels(accountID: String) throws -> [GmailLabel] {
        try lock.withLock {
            let statement = try prepare("""
            SELECT label_id, name, type, label_list_visibility,
                   message_list_visibility, color_json, messages_total,
                   messages_unread, threads_total, threads_unread
            FROM gmail_labels WHERE account_id = ? ORDER BY label_id ASC;
            """)
            defer { sqlite3_finalize(statement) }
            bind(accountID, to: statement, at: 1)
            var result: [GmailLabel] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let color = blob(statement, column: 5).flatMap {
                    try? JSONDecoder().decode(GmailLabelColor.self, from: $0)
                }
                result.append(GmailLabel(
                    id: string(statement, column: 0) ?? "",
                    name: string(statement, column: 1) ?? "",
                    type: string(statement, column: 2),
                    labelListVisibility: string(statement, column: 3),
                    messageListVisibility: string(statement, column: 4),
                    color: color,
                    messagesTotal: integer(statement, column: 6),
                    messagesUnread: integer(statement, column: 7),
                    threadsTotal: integer(statement, column: 8),
                    threadsUnread: integer(statement, column: 9)
                ))
            }
            return result
        }
    }

    private func readMessageLabelIDs(accountID: String, messageID: String) throws -> [String] {
        try lock.withLock {
            let statement = try prepare("""
            SELECT label_id FROM gmail_message_labels
            WHERE account_id = ? AND message_id = ? ORDER BY label_id ASC;
            """)
            defer { sqlite3_finalize(statement) }
            bind(accountID, to: statement, at: 1)
            bind(messageID, to: statement, at: 2)
            var result: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let labelID = string(statement, column: 0) { result.append(labelID) }
            }
            return result
        }
    }

    private func accountExists(accountID: String) throws -> Bool {
        let statement = try prepare("SELECT 1 FROM gmail_accounts WHERE account_id = ? LIMIT 1;")
        defer { sqlite3_finalize(statement) }
        bind(accountID, to: statement, at: 1)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func insertState(_ state: GmailAccountState) throws {
        try execute("""
        INSERT INTO gmail_accounts
            (account_id, email_address, history_id, last_full_sync_at, last_delta_sync_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(account_id) DO UPDATE SET
            email_address = excluded.email_address,
            history_id = excluded.history_id,
            last_full_sync_at = excluded.last_full_sync_at,
            last_delta_sync_at = excluded.last_delta_sync_at;
        """, bindings: [
            .text(state.accountID), .text(state.emailAddress), .optionalText(state.historyID),
            .optionalDate(state.lastFullSyncAt), .optionalDate(state.lastDeltaSyncAt)
        ])
    }

    private func updateState(accountID: String, historyID: String?, lastDeltaSyncAt: Date?) throws {
        try execute("""
        UPDATE gmail_accounts SET
            history_id = COALESCE(?, history_id),
            last_delta_sync_at = COALESCE(?, last_delta_sync_at)
        WHERE account_id = ?;
        """, bindings: [.optionalText(historyID), .optionalDate(lastDeltaSyncAt), .text(accountID)])
    }

    private func insertLabel(_ label: GmailLabel, accountID: String) throws {
        let colorData = try label.color.map { try JSONEncoder().encode($0) }
        try execute("""
        INSERT INTO gmail_labels
            (account_id, label_id, name, type, label_list_visibility,
             message_list_visibility, color_json, messages_total,
             messages_unread, threads_total, threads_unread)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(account_id, label_id) DO UPDATE SET
            name = excluded.name, type = excluded.type,
            label_list_visibility = excluded.label_list_visibility,
            message_list_visibility = excluded.message_list_visibility,
            color_json = excluded.color_json,
            messages_total = excluded.messages_total,
            messages_unread = excluded.messages_unread,
            threads_total = excluded.threads_total,
            threads_unread = excluded.threads_unread;
        """, bindings: [
            .text(accountID), .text(label.id), .text(label.name), .optionalText(label.type),
            .optionalText(label.labelListVisibility), .optionalText(label.messageListVisibility),
            .optionalBlob(colorData), .optionalInt(label.messagesTotal), .optionalInt(label.messagesUnread),
            .optionalInt(label.threadsTotal), .optionalInt(label.threadsUnread)
        ])
    }

    private func insertMessage(
        _ message: GmailMessage,
        accountID: String,
        preserveCachedContent: Bool = true
    ) throws {
        let merged = preserveCachedContent
            ? message.preservingCachedContent(from: storedMessage(accountID: accountID, messageID: message.id))
            : message
        let messageData = try JSONEncoder().encode(merged)
        try execute("""
        INSERT INTO gmail_messages
            (account_id, message_id, thread_id, message_json)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(account_id, message_id) DO UPDATE SET
            thread_id = excluded.thread_id, message_json = excluded.message_json;
        """, bindings: [
            .text(accountID), .text(message.id), .optionalText(merged.threadID), .blob(messageData)
        ])
        try execute(
            "DELETE FROM gmail_message_labels WHERE account_id = ? AND message_id = ?;",
            bindings: [.text(accountID), .text(message.id)]
        )
        for labelID in merged.labelIDs {
            try execute("""
            INSERT INTO gmail_message_labels (account_id, message_id, label_id)
            VALUES (?, ?, ?);
            """, bindings: [.text(accountID), .text(message.id), .text(labelID)])
        }
    }

    private func storedMessage(accountID: String, messageID: String) -> GmailMessage? {
        guard let statement =
            try? prepare("SELECT message_json FROM gmail_messages WHERE account_id = ? AND message_id = ? LIMIT 1;") else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        bind(accountID, to: statement, at: 1)
        bind(messageID, to: statement, at: 2)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let data = blob(statement, column: 0)
        else { return nil }
        return try? JSONDecoder().decode(GmailMessage.self, from: data)
    }

    private func scrubLabelFromMessages(accountID: String, labelID: String) throws {
        let statement = try prepare("SELECT message_id, message_json FROM gmail_messages WHERE account_id = ?;")
        bind(accountID, to: statement, at: 1)
        var messages: [GmailMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let data = blob(statement, column: 1),
                  let message = try? JSONDecoder().decode(GmailMessage.self, from: data)
            else { continue }
            if message.labelIDs.contains(labelID) {
                messages.append(message.withoutLabel(labelID))
            }
        }
        sqlite3_finalize(statement)
        for message in messages {
            try insertMessage(message, accountID: accountID)
        }
    }

    private func scrubContentFromMessages(accountID: String, messageIDs: Set<String>?) throws {
        let statement = try prepare("SELECT message_id, message_json FROM gmail_messages WHERE account_id = ?;")
        bind(accountID, to: statement, at: 1)
        var messages: [GmailMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let data = blob(statement, column: 1),
                  let message = try? JSONDecoder().decode(GmailMessage.self, from: data)
            else { continue }
            if messageIDs == nil || messageIDs?.contains(message.id) == true {
                messages.append(message.withoutContent())
            }
        }
        sqlite3_finalize(statement)
        for message in messages {
            try insertMessage(message, accountID: accountID, preserveCachedContent: false)
        }
    }

    private func pruneCachedContent(
        accountID: String,
        keepingMessageIDs: Set<String>,
        keepingAttachmentIDs: Set<String>
    ) throws {
        try deleteCacheRows(
            table: "gmail_bodies",
            keyColumn: "message_id",
            accountID: accountID,
            keeping: keepingMessageIDs
        )
        try deleteCacheRows(
            table: "gmail_raw_sources",
            keyColumn: "message_id",
            accountID: accountID,
            keeping: keepingMessageIDs
        )
        try deleteAttachmentCacheRows(
            accountID: accountID,
            keepingAttachmentIDs: keepingAttachmentIDs,
            keepingMessageIDs: keepingMessageIDs
        )
    }

    private func deleteCacheRows(
        table: String,
        keyColumn: String,
        accountID: String,
        keeping: Set<String>
    ) throws {
        guard !keeping.isEmpty else {
            try execute("DELETE FROM \(table) WHERE account_id = ?;", bindings: [.text(accountID)])
            return
        }
        let placeholders = Array(repeating: "?", count: keeping.count).joined(separator: ", ")
        var bindings: [Binding] = [.text(accountID)]
        bindings.append(contentsOf: keeping.sorted().map { .text($0) })
        try execute(
            "DELETE FROM \(table) WHERE account_id = ? AND \(keyColumn) NOT IN (\(placeholders));",
            bindings: bindings
        )
    }

    private func deleteAttachmentCacheRows(
        accountID: String,
        keepingAttachmentIDs: Set<String>,
        keepingMessageIDs: Set<String>
    ) throws {
        var predicates: [String] = []
        var bindings: [Binding] = [.text(accountID)]
        if !keepingAttachmentIDs.isEmpty {
            let placeholders = Array(repeating: "?", count: keepingAttachmentIDs.count).joined(separator: ", ")
            predicates.append("attachment_id IN (\(placeholders))")
            bindings.append(contentsOf: keepingAttachmentIDs.sorted().map { .text($0) })
        }
        for messageID in keepingMessageIDs.sorted() {
            predicates.append("attachment_id LIKE ?")
            bindings.append(.text("gmail-attachment:\(messageID):%"))
        }
        guard !predicates.isEmpty else {
            try execute("DELETE FROM gmail_attachments WHERE account_id = ?;", bindings: [.text(accountID)])
            return
        }
        try execute(
            "DELETE FROM gmail_attachments WHERE account_id = ? AND NOT (\(predicates.joined(separator: " OR ")));",
            bindings: bindings
        )
    }

    public func removeCachedContent(accountID: String, messageIDs: Set<String>) async throws {
        try validate(accountID: accountID)
        try lock.withLock {
            guard !messageIDs.isEmpty else { return }
            let placeholders = Array(repeating: "?", count: messageIDs.count).joined(separator: ", ")
            var bindings: [Binding] = [.text(accountID)]
            bindings.append(contentsOf: messageIDs.sorted().map { .text($0) })
            try execute("DELETE FROM gmail_bodies WHERE account_id = ? AND message_id IN (\(placeholders));", bindings: bindings)
            try execute(
                "DELETE FROM gmail_raw_sources WHERE account_id = ? AND message_id IN (\(placeholders));",
                bindings: bindings
            )
            let attachmentPredicates = messageIDs.sorted()
                .map { _ in "attachment_id = ? OR attachment_id LIKE ?" }
                .joined(separator: " OR ")
            var attachmentBindings: [Binding] = [.text(accountID)]
            for messageID in messageIDs.sorted() {
                attachmentBindings.append(.text(messageID))
                attachmentBindings.append(.text("gmail-attachment:\(messageID):%"))
            }
            try execute(
                "DELETE FROM gmail_attachments WHERE account_id = ? AND (\(attachmentPredicates));",
                bindings: attachmentBindings
            )
            try scrubContentFromMessages(accountID: accountID, messageIDs: messageIDs)
        }
    }

    public func removeAllCachedContent(accountID: String) async throws {
        try validate(accountID: accountID)
        try lock.withLock {
            try execute("DELETE FROM gmail_bodies WHERE account_id = ?;", bindings: [.text(accountID)])
            try execute("DELETE FROM gmail_raw_sources WHERE account_id = ?;", bindings: [.text(accountID)])
            try execute("DELETE FROM gmail_attachments WHERE account_id = ?;", bindings: [.text(accountID)])
            try scrubContentFromMessages(accountID: accountID, messageIDs: nil)
        }
    }

    private func deleteAccount(accountID: String) throws {
        try execute("DELETE FROM gmail_accounts WHERE account_id = ?;", bindings: [.text(accountID)])
    }

    private func begin() throws { try execute("BEGIN IMMEDIATE;") }
    private func commit() throws { try execute("COMMIT;") }
    private func rollback() throws { try execute("ROLLBACK;") }

    private enum Binding {
        case text(String)
        case optionalText(String?)
        case blob(Data)
        case optionalBlob(Data?)
        case optionalInt(Int?)
        case optionalDate(Date?)
    }

    private func execute(_ sql: String, bindings: [Binding] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        for (offset, binding) in bindings.enumerated() {
            bind(binding, to: statement, at: Int32(offset + 1))
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw GmailAccountStoreError.databaseFailure
        }
    }

    private func executeScript(_ sql: String) throws {
        guard let database else { throw GmailAccountStoreError.databaseFailure }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw GmailAccountStoreError.databaseFailure
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else { throw GmailAccountStoreError.databaseFailure }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw GmailAccountStoreError.databaseFailure }
        return statement
    }

    private func bind(_ value: Binding, to statement: OpaquePointer, at index: Int32) {
        switch value {
        case .text(let value): bind(value, to: statement, at: index)
        case .optionalText(let value):
            if let value { bind(value, to: statement, at: index) } else { sqlite3_bind_null(statement, index) }
        case .blob(let value): bind(value, to: statement, at: index)
        case .optionalBlob(let value):
            if let value { bind(value, to: statement, at: index) } else { sqlite3_bind_null(statement, index) }
        case .optionalInt(let value):
            if let value { sqlite3_bind_int64(statement, index, Int64(value)) } else { sqlite3_bind_null(statement, index) }
        case .optionalDate(let value):
            if let value { sqlite3_bind_double(statement, index, value.timeIntervalSince1970) } else { sqlite3_bind_null(
                statement,
                index
            ) }
        }
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, Self.transient)
    }

    private func bind(_ value: Data, to statement: OpaquePointer, at index: Int32) {
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), Self.transient)
        }
    }

    private func string(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, column)
        else { return nil }
        return String(cString: value)
    }

    private func integer(_ statement: OpaquePointer, column: Int32) -> Int? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(statement, column))
    }

    private func date(_ statement: OpaquePointer, column: Int32) -> Date? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, column))
    }

    private func blob(_ statement: OpaquePointer, column: Int32) -> Data? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let bytes = sqlite3_column_blob(statement, column)
        else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }

    private func normalized(_ error: Error) -> Error {
        error as? GmailAccountStoreError ?? GmailAccountStoreError.databaseFailure
    }

    private static let schemaSQL = """
    CREATE TABLE IF NOT EXISTS gmail_accounts (
        account_id TEXT PRIMARY KEY NOT NULL,
        email_address TEXT NOT NULL,
        history_id TEXT,
        last_full_sync_at REAL,
        last_delta_sync_at REAL
    );
    CREATE TABLE IF NOT EXISTS gmail_labels (
        account_id TEXT NOT NULL,
        label_id TEXT NOT NULL,
        name TEXT NOT NULL,
        type TEXT,
        label_list_visibility TEXT,
        message_list_visibility TEXT,
        color_json BLOB,
        messages_total INTEGER,
        messages_unread INTEGER,
        threads_total INTEGER,
        threads_unread INTEGER,
        PRIMARY KEY (account_id, label_id),
        FOREIGN KEY (account_id) REFERENCES gmail_accounts(account_id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS gmail_messages (
        account_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        thread_id TEXT,
        message_json BLOB NOT NULL,
        PRIMARY KEY (account_id, message_id),
        FOREIGN KEY (account_id) REFERENCES gmail_accounts(account_id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS gmail_message_labels (
        account_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        label_id TEXT NOT NULL,
        PRIMARY KEY (account_id, message_id, label_id),
        FOREIGN KEY (account_id, message_id)
            REFERENCES gmail_messages(account_id, message_id) ON DELETE CASCADE,
        FOREIGN KEY (account_id, label_id)
            REFERENCES gmail_labels(account_id, label_id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS gmail_messages_thread_idx
        ON gmail_messages(account_id, thread_id);
    CREATE INDEX IF NOT EXISTS gmail_messages_received_idx
        ON gmail_messages(account_id, CAST(json_extract(CAST(message_json AS TEXT), '$.internalDate') AS INTEGER) DESC, message_id);
    CREATE TABLE IF NOT EXISTS gmail_bodies (
        account_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        body_json BLOB NOT NULL,
        PRIMARY KEY (account_id, message_id),
        FOREIGN KEY (account_id) REFERENCES gmail_accounts(account_id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS gmail_raw_sources (
        account_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        raw_source TEXT NOT NULL,
        PRIMARY KEY (account_id, message_id),
        FOREIGN KEY (account_id) REFERENCES gmail_accounts(account_id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS gmail_attachments (
        account_id TEXT NOT NULL,
        attachment_id TEXT NOT NULL,
        data BLOB NOT NULL,
        PRIMARY KEY (account_id, attachment_id),
        FOREIGN KEY (account_id) REFERENCES gmail_accounts(account_id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS gmail_staged_drafts (
        account_id TEXT NOT NULL,
        draft_id TEXT NOT NULL,
        remote_id TEXT,
        draft_json BLOB NOT NULL,
        PRIMARY KEY (account_id, draft_id),
        FOREIGN KEY (account_id) REFERENCES gmail_accounts(account_id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS gmail_staged_drafts_remote_idx ON gmail_staged_drafts(account_id, remote_id);
    CREATE TABLE IF NOT EXISTS gmail_staged_attachments (
        account_id TEXT NOT NULL,
        attachment_id TEXT NOT NULL,
        draft_id TEXT NOT NULL,
        attachment_json BLOB NOT NULL,
        byte_count INTEGER NOT NULL,
        PRIMARY KEY (account_id, attachment_id),
        FOREIGN KEY (account_id) REFERENCES gmail_accounts(account_id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS gmail_staged_attachments_draft_idx ON gmail_staged_attachments(account_id, draft_id);
    CREATE TABLE IF NOT EXISTS gmail_scheduled_sends (
        account_id TEXT NOT NULL,
        draft_id TEXT NOT NULL,
        draft_json BLOB NOT NULL,
        mime BLOB NOT NULL,
        scheduled_at REAL NOT NULL,
        state TEXT NOT NULL DEFAULT 'waiting',
        attempt_id TEXT,
        owner_id TEXT,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at REAL,
        last_error TEXT,
        PRIMARY KEY(account_id, draft_id),
        FOREIGN KEY(account_id) REFERENCES gmail_accounts(account_id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS gmail_scheduled_due_idx ON gmail_scheduled_sends(account_id, state, scheduled_at);
    PRAGMA user_version = 3;
    """
}

// Staged compose content is separate from the evictable message cache. It can
// exist before the first draft save, but always belongs to an initialized account.
public extension SQLiteGmailAccountStore {
    /// Reads local compose state by local or current provider draft identity.
    func draft(accountID: String, draftID: String) async throws -> Draft? {
        try validate(accountID: accountID)
        return try lock.withLock { try stagedDraft(accountID: accountID, draftID: draftID) }
    }

    /// Commits compose content before the caller reports that staging succeeded.
    func setDraft(_ draft: Draft, accountID: String) async throws {
        try validate(accountID: accountID)
        try validate(messageID: draft.id)
        let bytes = try JSONEncoder().encode(draft)
        try lock.withLock {
            try execute("""
            INSERT INTO gmail_staged_drafts(account_id, draft_id, remote_id, draft_json) VALUES (?, ?, ?, ?)
            ON CONFLICT(account_id, draft_id) DO UPDATE SET remote_id = excluded.remote_id, draft_json = excluded.draft_json;
            """, bindings: [.text(accountID), .text(draft.id), .optionalText(draft.remoteID), .blob(bytes)])
        }
    }

    /// Reads original staged attachment content independently of the read cache.
    func attachment(accountID: String, attachmentID: String) async throws -> GmailStagedAttachment? {
        try validate(accountID: accountID)
        return try lock.withLock {
            try stagedValue("SELECT attachment_json FROM gmail_staged_attachments WHERE account_id = ? AND attachment_id = ?;",
                            values: [accountID, attachmentID], as: GmailStagedAttachment.self)
        }
    }

    /// Atomically stores one attachment while enforcing the account's aggregate byte bound.
    func setAttachment(_ attachment: GmailStagedAttachment, accountID: String) async throws {
        try validate(accountID: accountID)
        guard !attachment.id.isEmpty, !attachment.draftID.isEmpty else { throw GmailDraftStagingError.invalidIdentifier }
        guard attachment.data.count <= maxStagedAttachmentBytes else {
            throw GmailDraftStagingError.capacityExceeded(limit: maxStagedAttachmentBytes)
        }
        let bytes = try JSONEncoder().encode(attachment)
        try lock.withLock {
            try begin()
            do {
                let statement = try prepare("""
                SELECT COALESCE(SUM(byte_count), 0) FROM gmail_staged_attachments
                WHERE account_id = ? AND attachment_id <> ?;
                """)
                defer { sqlite3_finalize(statement) }
                bind(accountID, to: statement, at: 1)
                bind(attachment.id, to: statement, at: 2)
                guard sqlite3_step(statement) == SQLITE_ROW else { throw GmailAccountStoreError.databaseFailure }
                let used = sqlite3_column_int64(statement, 0)
                guard used <= Int64(maxStagedAttachmentBytes - attachment.data.count) else {
                    throw GmailDraftStagingError.capacityExceeded(limit: maxStagedAttachmentBytes)
                }
                try execute("""
                INSERT INTO gmail_staged_attachments(account_id, attachment_id, draft_id, attachment_json, byte_count)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(account_id, attachment_id) DO UPDATE SET draft_id = excluded.draft_id,
                    attachment_json = excluded.attachment_json, byte_count = excluded.byte_count;
                """, bindings: [.text(accountID), .text(attachment.id), .text(attachment.draftID), .blob(bytes),
                                .optionalInt(attachment.data.count)])
                try commit()
            } catch { try? rollback(); throw error }
        }
    }

    /// Removes a draft and its owned attachments in one transaction, including unattached staging.
    func removeDraft(accountID: String, draftID: String) async throws {
        try validate(accountID: accountID)
        try lock.withLock {
            try begin()
            do {
                let stored = try stagedDraft(accountID: accountID, draftID: draftID)
                let localID = stored?.id ?? draftID
                let remoteID = stored?.remoteID ?? draftID
                try execute("DELETE FROM gmail_staged_attachments WHERE account_id = ? AND draft_id IN (?, ?);",
                            bindings: [.text(accountID), .text(localID), .text(remoteID)])
                try execute("DELETE FROM gmail_staged_drafts WHERE account_id = ? AND draft_id = ?;",
                            bindings: [.text(accountID), .text(localID)])
                try commit()
            } catch { try? rollback(); throw error }
        }
    }

    /// Clears only the account's compose staging, leaving other accounts and cached mail intact.
    func clear(accountID: String) async throws {
        try validate(accountID: accountID)
        try lock.withLock {
            try begin()
            do { try clearStaging(accountID: accountID); try commit() }
            catch { try? rollback(); throw error }
        }
    }

    private func clearStaging(accountID: String) throws {
        try execute("DELETE FROM gmail_staged_attachments WHERE account_id = ?;", bindings: [.text(accountID)])
        try execute("DELETE FROM gmail_staged_drafts WHERE account_id = ?;", bindings: [.text(accountID)])
    }

    private func stagedDraft(accountID: String, draftID: String) throws -> Draft? {
        try stagedValue("""
        SELECT draft_json FROM gmail_staged_drafts WHERE account_id = ? AND (draft_id = ? OR remote_id = ?)
        ORDER BY draft_id = ? DESC LIMIT 1;
        """, values: [accountID, draftID, draftID, draftID], as: Draft.self)
    }

    private func stagedValue<Value: Decodable>(_ sql: String, values: [String], as type: Value.Type) throws -> Value? {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            bind(value, to: statement, at: Int32(index + 1))
        }
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW, let bytes = blob(statement, column: 0) else { throw GmailAccountStoreError.databaseFailure }
        return try JSONDecoder().decode(type, from: bytes)
    }
}

public extension SQLiteGmailAccountStore {
    /// Lists scheduling metadata without loading message bodies or MIME attachments.
    func scheduledSends(accountID: String) async throws -> [PendingScheduledSend] {
        try validate(accountID: accountID)
        return try lock.withLock {
            let statement = try prepare("""
            SELECT draft_id, scheduled_at, json_extract(CAST(draft_json AS TEXT), '$.subject'),
                   state, last_error, next_attempt_at FROM gmail_scheduled_sends
            WHERE account_id = ? ORDER BY scheduled_at, draft_id;
            """)
            defer { sqlite3_finalize(statement) }
            bind(accountID, to: statement, at: 1)
            var result: [PendingScheduledSend] = []
            var status = sqlite3_step(statement)
            while status == SQLITE_ROW {
                guard let id = string(statement, column: 0), let due = date(statement, column: 1),
                      let state = string(statement, column: 3).flatMap(ScheduledSendState.init(rawValue:)) else {
                    throw GmailAccountStoreError.malformedStoredMessage
                }
                result.append(PendingScheduledSend(draftID: id, scheduledFor: due, subject: string(statement, column: 2) ?? "",
                                                   state: state, lastError: string(statement, column: 4),
                                                   nextAttemptAt: date(statement, column: 5)))
                status = sqlite3_step(statement)
            }
            guard status == SQLITE_DONE else { throw GmailAccountStoreError.databaseFailure }
            return result
        }
    }

    /// Atomically records explicit scheduling intent and its immutable message content.
    func enqueueScheduledSend(_ draft: Draft, rawMIME: Data, accountID: String) async throws {
        try validate(accountID: accountID)
        guard let due = draft.scheduledFor, due.timeIntervalSince1970.isFinite, !rawMIME.isEmpty, !draft.id.isEmpty else {
            throw GmailScheduledSendError.invalidSchedule
        }
        let bytes = try JSONEncoder().encode(draft)
        try lock.withLock {
            try execute("""
            INSERT INTO gmail_scheduled_sends(account_id, draft_id, draft_json, mime, scheduled_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(account_id, draft_id) DO UPDATE SET draft_json = excluded.draft_json,
                mime = excluded.mime, scheduled_at = excluded.scheduled_at, attempt_count = 0,
                next_attempt_at = NULL, last_error = NULL
            WHERE gmail_scheduled_sends.state = 'waiting';
            """, bindings: [.text(accountID), .text(draft.id), .blob(bytes), .blob(rawMIME), .optionalDate(due)])
            guard sqlite3_changes(database) == 1 else { throw GmailScheduledSendError.inFlight }
        }
    }

    /// Reads the submitted snapshot, independently of later draft autosaves.
    func scheduledDraft(accountID: String, draftID: String) async throws -> Draft? {
        try validate(accountID: accountID)
        return try lock.withLock { try scheduledDraftWithoutLock(accountID: accountID, draftID: draftID) }
    }

    private func scheduledDraftWithoutLock(accountID: String, draftID: String) throws -> Draft? {
        try stagedValue("SELECT draft_json FROM gmail_scheduled_sends WHERE account_id = ? AND draft_id = ?;",
                        values: [accountID, draftID], as: Draft.self)
    }

    /// Claims a due row before any delivery request; simultaneous workers cannot both claim it.
    func claimScheduledSend(accountID: String, draftID: String, now: Date,
                            ownerID: String = "unowned") async throws -> GmailScheduledSendAttempt? {
        try validate(accountID: accountID)
        return try lock.withLock {
            try begin()
            do {
                let attemptID = UUID().uuidString
                try execute("""
                UPDATE gmail_scheduled_sends SET state = 'delivering', attempt_id = ?, owner_id = ?, attempt_count = attempt_count + 1
                WHERE account_id = ? AND draft_id = ? AND state = 'waiting' AND scheduled_at <= ?
                    AND (next_attempt_at IS NULL OR next_attempt_at <= ?);
                """, bindings: [
                    .text(attemptID),
                    .text(ownerID),
                    .text(accountID),
                    .text(draftID),
                    .optionalDate(now),
                    .optionalDate(now)
                ])
                guard sqlite3_changes(database) == 1 else { try commit(); return nil }
                let statement = try prepare("""
                SELECT draft_json, mime, attempt_count FROM gmail_scheduled_sends WHERE account_id = ? AND draft_id = ?;
                """)
                defer { sqlite3_finalize(statement) }
                bind(accountID, to: statement, at: 1)
                bind(draftID, to: statement, at: 2)
                guard sqlite3_step(statement) == SQLITE_ROW, let bytes = blob(statement, column: 0),
                      let mime = blob(statement, column: 1),
                      !mime.isEmpty else { throw GmailAccountStoreError.malformedStoredMessage }
                let draft = try JSONDecoder().decode(Draft.self, from: bytes)
                let attempt = GmailScheduledSendAttempt(draft: draft, rawMIME: mime, attemptID: attemptID,
                                                        attemptCount: Int(sqlite3_column_int64(statement, 2)))
                try commit()
                return attempt
            } catch { try? rollback(); throw error }
        }
    }

    /// Removes confirmed intent, retaining newer edits; returns whether its provider draft can be removed.
    func completeScheduledSend(accountID: String, draftID: String, attemptID: String) async throws -> Bool {
        try lock.withLock {
            try begin()
            do {
                let draft = try scheduledDraftWithoutLock(accountID: accountID, draftID: draftID)
                try execute("""
                DELETE FROM gmail_scheduled_sends WHERE account_id = ? AND draft_id = ?
                    AND attempt_id = ? AND state = 'delivering';
                """, bindings: [.text(accountID), .text(draftID), .text(attemptID)])
                guard sqlite3_changes(database) == 1, var draft else { try commit(); return false }
                var staged = try stagedDraft(accountID: accountID, draftID: draftID)
                draft.scheduledFor = nil
                staged?.scheduledFor = nil
                let canCleanUp = staged == nil || staged == draft
                if canCleanUp {
                    try execute("DELETE FROM gmail_staged_attachments WHERE account_id = ? AND draft_id IN (?, ?);",
                                bindings: [.text(accountID), .text(draft.id), .text(draft.remoteID ?? draft.id)])
                    try execute("DELETE FROM gmail_staged_drafts WHERE account_id = ? AND draft_id = ?;",
                                bindings: [.text(accountID), .text(draft.id)])
                }
                try commit()
                return canCleanUp
            } catch { try? rollback(); throw error }
        }
    }

    /// Retries only known-safe failures; an absent retry date requires explicit review.
    func failScheduledSend(accountID: String, draftID: String, attemptID: String, message: String,
                           retryAt: Date?) async throws {
        try lock.withLock {
            try execute("""
            UPDATE gmail_scheduled_sends SET state = ?, last_error = ?, next_attempt_at = ?, attempt_id = NULL
            WHERE account_id = ? AND draft_id = ? AND attempt_id = ? AND state = 'delivering';
            """, bindings: [.text(retryAt == nil ? "needsReview" : "waiting"), .text(message), .optionalDate(retryAt),
                            .text(accountID), .text(draftID), .text(attemptID)])
        }
    }

    /// Interrupted attempts stay held for review after restart; they are never lease-expired into another send.
    func recoverInterruptedScheduledSends(accountID: String, activeOwnerIDs: @Sendable () -> Set<String> = { [] }) async throws {
        let message = String(
            localized: "A previous delivery attempt was interrupted. Check Sent before trying again.",
            bundle: .module
        )
        try lock.withLock {
            try begin()
            do {
                // Read live ownership after acquiring the SQLite write lock;
                // another connection cannot insert a claim between this snapshot and recovery.
                let owners = activeOwnerIDs().sorted()
                let ownerClause = owners.isEmpty ? "" : " AND (owner_id IS NULL OR owner_id NOT IN (" + owners.map { _ in "?" }
                    .joined(separator: ",") + "))"
                try execute("""
                UPDATE gmail_scheduled_sends SET state = 'needsReview', last_error = ?, next_attempt_at = NULL
                WHERE account_id = ? AND state = 'delivering'\(ownerClause);
                """, bindings: [.text(message), .text(accountID)] + owners.map { .text($0) })
                try commit()
            } catch { try? rollback(); throw error }
        }
    }

    /// Cancels waiting/reviewed intent while retaining a normal editable draft.
    func cancelScheduledSend(accountID: String, draftID: String) async throws -> Draft {
        try lock.withLock {
            try begin()
            do {
                guard let submitted = try scheduledDraftWithoutLock(accountID: accountID, draftID: draftID) else {
                    throw GmailScheduledSendError.notFound
                }
                var draft = try stagedDraft(accountID: accountID, draftID: draftID) ?? submitted
                try execute("DELETE FROM gmail_scheduled_sends WHERE account_id = ? AND draft_id = ? AND state <> 'delivering';",
                            bindings: [.text(accountID), .text(draftID)])
                guard sqlite3_changes(database) == 1 else { throw GmailScheduledSendError.inFlight }
                draft.scheduledFor = nil
                try execute("""
                INSERT INTO gmail_staged_drafts(account_id, draft_id, remote_id, draft_json) VALUES (?, ?, ?, ?)
                ON CONFLICT(account_id, draft_id) DO UPDATE SET remote_id = excluded.remote_id, draft_json = excluded.draft_json;
                """, bindings: [
                    .text(accountID),
                    .text(draftID),
                    .optionalText(draft.remoteID),
                    .blob(JSONEncoder().encode(draft))
                ])
                try commit()
                return draft
            } catch { try? rollback(); throw error }
        }
    }

    /// Reschedules frozen content after an explicit user request; active deliveries cannot be changed.
    func rescheduleSend(accountID: String, draftID: String, date: Date, allowReview: Bool = false) async throws {
        guard date.timeIntervalSince1970.isFinite else { throw GmailScheduledSendError.invalidSchedule }
        try lock.withLock {
            try begin()
            do {
                guard var draft = try scheduledDraftWithoutLock(accountID: accountID, draftID: draftID) else {
                    throw GmailScheduledSendError.notFound
                }
                draft.scheduledFor = date
                try execute("""
                UPDATE gmail_scheduled_sends SET draft_json = ?, scheduled_at = ?, state = 'waiting',
                    attempt_id = NULL, attempt_count = 0, next_attempt_at = NULL, last_error = NULL
                WHERE account_id = ? AND draft_id = ? AND (state = 'waiting' OR (? = 1 AND state = 'needsReview'));
                """, bindings: [.blob(JSONEncoder().encode(draft)), .optionalDate(date), .text(accountID), .text(draftID),
                                .optionalInt(allowReview ? 1 : 0)])
                guard sqlite3_changes(database) == 1 else { throw GmailScheduledSendError.inFlight }
                try commit()
            } catch { try? rollback(); throw error }
        }
    }
}

private extension GmailMessage {
    func withoutLabel(_ labelID: String) -> GmailMessage {
        GmailMessage(
            id: id,
            threadID: threadID,
            labelIDs: labelIDs.filter { $0 != labelID },
            snippet: snippet,
            historyID: historyID,
            internalDate: internalDate,
            sizeEstimate: sizeEstimate,
            payload: payload,
            raw: raw
        )
    }
}

private extension SQLiteGmailAccountStore {
    static func attachmentIDs(_ message: GmailMessage) -> [String] {
        var result: [String] = []
        collectAttachmentIDs(message.payload, messageID: message.id, into: &result)
        return result
    }

    static func collectAttachmentIDs(
        _ part: GmailMessagePart?,
        messageID: String,
        into result: inout [String]
    ) {
        guard let part else { return }
        if let filename = part.filename, !filename.isEmpty {
            result.append("gmail-attachment:\(messageID):\(part.partID ?? filename)")
        }
        for child in part.parts {
            collectAttachmentIDs(child, messageID: messageID, into: &result)
        }
    }
}
