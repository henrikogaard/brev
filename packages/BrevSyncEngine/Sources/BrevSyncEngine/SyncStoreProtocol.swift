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

// MARK: - Protocol

/// Seam between `BrevSyncEngine` and the underlying persistent store (ADR-0030 §1).
///
/// The default production implementation is `SQLiteSyncStore`. Tests use
/// `InMemorySyncStore` to avoid touching the filesystem. All methods are `async`
/// so both implementations can satisfy the requirement regardless of whether they
/// perform synchronous or actor-isolated work.
protocol SyncStoreProtocol: Sendable {
    /// The schema version currently installed in this store. Used by tests to
    /// assert that migration SQL runs correctly when upgrading from a prior version.
    var currentSchemaVersion: Int { get }

    // MARK: Accounts

    /// Ensures a row exists for `accountID` in the `accounts` table. Must be
    /// called before inserting any rows that reference the account.
    func ensureAccount(id: String) async throws

    /// Clears every local sync/index row for an account.
    func clearAccount(id: String) async throws

    // MARK: Folder sync state

    func syncState(accountID: String, folderID: String) async -> FolderSyncState?
    func setSyncState(_ state: FolderSyncState) async throws
    func deleteSyncState(accountID: String, folderID: String) async throws

    /// Deletes both the cached headers and the sync state row for `folderID` in
    /// a single transaction. Used by the UIDVALIDITY-invalidation path so a crash
    /// cannot leave a ghost folder (headers without state, or state without headers).
    func clearFolder(accountID: String, folderID: String) async throws

    // MARK: Message headers

    /// Returns at most `limit` headers for `folderID`, ordered newest-first,
    /// skipping the first `offset` rows.
    func headers(
        accountID: String,
        folderID: String,
        limit: Int,
        offset: Int
    ) async -> [MessageHeader]

    /// Inserts or replaces headers. Dirty messages (pending mutations) are not
    /// overwritten — callers must filter them out before calling this method.
    func upsertHeaders(_ headers: [MessageHeader], accountID: String) async throws

    /// Deletes headers whose `MessageHeader.ID` is in `messageIDs`.
    func deleteHeaders(messageIDs: [MessageHeader.ID], accountID: String) async throws

    /// Deletes all headers for `folderID` under `accountID`.
    func clearHeaders(accountID: String, folderID: String) async throws

    /// Returns every UID currently stored for `folderID` under `accountID`.
    /// Used by `BrevSyncEngine.syncFolder` to detect expunged messages.
    func allUIDs(accountID: String, folderID: String) async -> [Int]

    func setDirty(
        _ isDirty: Bool,
        messageIDs: [MessageHeader.ID],
        accountID: String
    ) async throws

    /// Returns all messageIDs marked dirty under `accountID`.
    func dirtyMessageIDs(accountID: String) async -> [MessageHeader.ID]

    // MARK: Message bodies

    func body(accountID: String, messageID: MessageHeader.ID) async -> Data?

    /// Reads only rows explicitly written as original MIME bytes.
    func originalBody(accountID: String, messageID: MessageHeader.ID) async -> Data?
    /// Stores original MIME data and its provenance atomically.
    func storeOriginalBody(_ data: Data, accountID: String, messageID: MessageHeader.ID) async throws

    func storeBody(
        _ data: Data,
        accountID: String,
        messageID: MessageHeader.ID
    ) async throws

    func deleteBodies(
        messageIDs: [MessageHeader.ID],
        accountID: String
    ) async throws

    func deleteBodies(
        accountID: String,
        folderID: String
    ) async throws

    func deleteBodies(
        accountID: String,
        folderID: String,
        exceptMessageIDs: Set<MessageHeader.ID>
    ) async throws

    func metrics(accountID: String) async -> LocalSearchIndexMetrics?

    // MARK: Search

    func searchHeaders(
        _ query: SearchQuery,
        accountID: String,
        limit: Int
    ) async -> [MessageHeader]
}

extension SyncStoreProtocol {
    func originalBody(accountID: String, messageID: MessageHeader.ID) async -> Data? { nil }
    func storeOriginalBody(_ data: Data, accountID: String, messageID: MessageHeader.ID) async throws {
        try await storeBody(data, accountID: accountID, messageID: messageID)
    }
}

// MARK: - In-memory implementation (for tests)

/// Thread-safe in-memory implementation of `SyncStoreProtocol`.
///
/// Used in unit tests so that `BrevSyncEngine` can be exercised without a
/// real SQLite database file.
actor InMemorySyncStore: SyncStoreProtocol {
    let currentSchemaVersion = 4

    private var syncStates: [String: FolderSyncState] = [:]
    // ["\(accountID)|\(folderID)": [messageID: MessageHeader]]
    private var headersByFolder: [String: [String: MessageHeader]] = [:]
    private struct StoredBody {
        let data: Data
        let isOriginal: Bool
    }

    private var bodies: [String: StoredBody] = [:]
    // element format: "\(accountID)|\(messageID)"
    private var dirty: Set<String> = []

    func ensureAccount(id: String) throws {}

    func clearAccount(id: String) throws {
        let prefix = "\(id)|"
        syncStates = syncStates.filter { !$0.key.hasPrefix(prefix) }
        headersByFolder = headersByFolder.filter { !$0.key.hasPrefix(prefix) }
        bodies = bodies.filter { !$0.key.hasPrefix(prefix) }
        dirty = dirty.filter { !$0.hasPrefix(prefix) }
    }

    func syncState(accountID: String, folderID: String) -> FolderSyncState? {
        syncStates[folderKey(accountID, folderID)]
    }

    func setSyncState(_ state: FolderSyncState) throws {
        syncStates[folderKey(state.accountID, state.folderID)] = state
    }

    func deleteSyncState(accountID: String, folderID: String) throws {
        syncStates.removeValue(forKey: folderKey(accountID, folderID))
    }

    func clearFolder(accountID: String, folderID: String) throws {
        let headers = headersByFolder[folderKey(accountID, folderID)] ?? [:]
        clearLocalMessageState(
            messageIDs: Array(headers.keys),
            accountID: accountID
        )
        try deleteBodies(accountID: accountID, folderID: folderID)
        headersByFolder.removeValue(forKey: folderKey(accountID, folderID))
        syncStates.removeValue(forKey: folderKey(accountID, folderID))
    }

    func headers(
        accountID: String,
        folderID: String,
        limit: Int,
        offset: Int
    ) -> [MessageHeader] {
        let all = (headersByFolder[folderKey(accountID, folderID)] ?? [:])
            .values
            .sorted { lhs, rhs in
                lhs.date == rhs.date ? lhs.id > rhs.id : lhs.date > rhs.date
            }
        return Array(all.dropFirst(offset).prefix(limit))
    }

    func upsertHeaders(_ headers: [MessageHeader], accountID: String) throws {
        for header in headers {
            let key = folderKey(accountID, header.folderID)
            if headersByFolder[key] == nil {
                headersByFolder[key] = [:]
            }
            let previousMessageID = messageID(
                accountID: accountID,
                folderID: header.folderID,
                uid: Self.uid(from: header.id)
            )
            if let previousMessageID, dirty.contains("\(accountID)|\(previousMessageID)") {
                continue
            }
            if let previousMessageID, previousMessageID != header.id {
                headersByFolder[key]?.removeValue(forKey: previousMessageID)
                clearLocalMessageState(messageIDs: [previousMessageID], accountID: accountID)
            }
            headersByFolder[key]![header.id] = header
        }
    }

    func deleteHeaders(messageIDs: [MessageHeader.ID], accountID: String) throws {
        let targets = Set(messageIDs)
        for key in headersByFolder.keys where key.hasPrefix("\(accountID)|") {
            headersByFolder[key] = headersByFolder[key]?.filter { !targets.contains($0.key) }
        }
        clearLocalMessageState(
            messageIDs: messageIDs,
            accountID: accountID
        )
    }

    func clearHeaders(accountID: String, folderID: String) throws {
        let headers = headersByFolder[folderKey(accountID, folderID)] ?? [:]
        clearLocalMessageState(
            messageIDs: Array(headers.keys),
            accountID: accountID
        )
        try deleteBodies(accountID: accountID, folderID: folderID)
        headersByFolder.removeValue(forKey: folderKey(accountID, folderID))
    }

    func allUIDs(accountID: String, folderID: String) -> [Int] {
        (headersByFolder[folderKey(accountID, folderID)] ?? [:]).values.compactMap { header in
            guard let sep = header.id.lastIndex(of: ":") else { return nil }
            return Int(String(header.id[header.id.index(after: sep)...]))
        }
    }

    func setDirty(_ isDirty: Bool, messageIDs: [MessageHeader.ID], accountID: String) throws {
        for id in messageIDs {
            let key = "\(accountID)|\(id)"
            if isDirty { dirty.insert(key) } else { dirty.remove(key) }
        }
    }

    func dirtyMessageIDs(accountID: String) -> [MessageHeader.ID] {
        let prefix = "\(accountID)|"
        return dirty.compactMap { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : nil }
    }

    func body(accountID: String, messageID: MessageHeader.ID) -> Data? {
        bodies["\(accountID)|\(messageID)"]?.data
    }

    func originalBody(accountID: String, messageID: MessageHeader.ID) -> Data? {
        guard let body = bodies["\(accountID)|\(messageID)"], body.isOriginal else { return nil }
        return body.data
    }

    func storeOriginalBody(_ data: Data, accountID: String, messageID: MessageHeader.ID) throws {
        bodies["\(accountID)|\(messageID)"] = StoredBody(data: data, isOriginal: true)
    }

    func storeBody(_ data: Data, accountID: String, messageID: MessageHeader.ID) throws {
        bodies["\(accountID)|\(messageID)"] = StoredBody(data: data, isOriginal: false)
    }

    func deleteBodies(messageIDs: [MessageHeader.ID], accountID: String) throws {
        for messageID in messageIDs {
            bodies.removeValue(forKey: "\(accountID)|\(messageID)")
        }
    }

    func deleteBodies(accountID: String, folderID: String) throws {
        let prefix = "\(accountID)|\(folderID):"
        bodies = bodies.filter { key, _ in
            guard key.hasPrefix(prefix) else { return true }
            let suffix = key.dropFirst(prefix.count)
            return suffix.isEmpty || suffix.contains { !$0.isNumber }
        }
    }

    func deleteBodies(accountID: String, folderID: String, exceptMessageIDs: Set<MessageHeader.ID>) throws {
        let prefix = "\(accountID)|\(folderID):"
        bodies = bodies.filter { key, _ in
            guard key.hasPrefix(prefix) else { return true }
            let messageID = String(key.dropFirst("\(accountID)|".count))
            let suffix = key.dropFirst(prefix.count)
            // Keep entries that are not a direct-UID member of this folder,
            // or whose message ID is in the except set.
            let isDirectMember = !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
            return !isDirectMember || exceptMessageIDs.contains(messageID)
        }
    }

    func metrics(accountID: String) -> LocalSearchIndexMetrics? {
        let prefix = "\(accountID)|"
        let indexedHeaderCount = headersByFolder
            .filter { $0.key.hasPrefix(prefix) }
            .values
            .reduce(0) { $0 + $1.count }
        let cachedBodyCount = bodies.keys.filter { $0.hasPrefix(prefix) }.count
        let syncedFolderCount = syncStates.keys.filter { $0.hasPrefix(prefix) }.count
        return LocalSearchIndexMetrics(
            databaseBytes: 0,
            indexedHeaderCount: indexedHeaderCount,
            cachedBodyCount: cachedBodyCount,
            searchDocumentCount: indexedHeaderCount,
            syncedFolderCount: syncedFolderCount
        )
    }

    func searchHeaders(
        _ query: SearchQuery,
        accountID: String,
        limit: Int
    ) -> [MessageHeader] {
        guard query.hasSearchCriteria, limit > 0 else { return [] }
        let prefix = "\(accountID)|"
        var bodyTextByID: [MessageHeader.ID: String] = [:]
        for (key, data) in bodies {
            guard key.hasPrefix(prefix) else { continue }
            let messageID = String(key.dropFirst(prefix.count))
            bodyTextByID[messageID] = Self.searchableBodyText(from: data.data, messageID: messageID)
        }
        var seen = Set<MessageHeader.ID>()
        let candidates = headersByFolder
            .filter { $0.key.hasPrefix(prefix) }
            .values
            .flatMap(\.values)
            .sorted { lhs, rhs in
                lhs.date == rhs.date ? lhs.id > rhs.id : lhs.date > rhs.date
            }
        var results: [MessageHeader] = []
        for header in candidates {
            guard seen.insert(header.id).inserted else { continue }
            let bodyText = bodyTextByID[header.id]
            guard Self.searchQuery(query, matches: header, bodyText: bodyText) else { continue }
            results.append(header)
            if results.count == limit { break }
        }
        return results
    }

    // MARK: Private

    private func folderKey(_ accountID: String, _ folderID: String) -> String {
        "\(accountID)|\(folderID)"
    }

    private func messageID(accountID: String, folderID: String, uid: Int) -> MessageHeader.ID? {
        (headersByFolder[folderKey(accountID, folderID)] ?? [:])
            .values
            .first { Self.uid(from: $0.id) == uid }?
            .id
    }

    private func clearLocalMessageState(
        messageIDs: [MessageHeader.ID],
        accountID: String
    ) {
        for messageID in messageIDs {
            let key = "\(accountID)|\(messageID)"
            bodies.removeValue(forKey: key)
            dirty.remove(key)
        }
    }

    private static func searchQuery(
        _ query: SearchQuery,
        matches header: MessageHeader,
        bodyText: String?
    ) -> Bool {
        var metadataQuery = query
        metadataQuery.text = ""
        guard metadataQuery.matches(header) else { return false }

        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        if query.matches(header) { return true }
        let searchableText = normalizedSearchText(searchableText(for: header, bodyText: bodyText))
        let normalizedText = normalizedSearchText(text)
        if searchableText.contains(normalizedText) {
            return true
        }
        let tokens = searchTokens(for: text)
        return !tokens.isEmpty && tokens.allSatisfy {
            searchableText.contains(normalizedSearchText($0))
        }
    }

    private static func searchTokens(for text: String) -> [String] {
        text
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func searchableText(
        for header: MessageHeader,
        bodyText: String?
    ) -> String {
        [
            header.subject,
            header.snippet,
            participantSearchText(for: header),
            bodyText ?? "",
        ].joined(separator: " ")
    }

    private static func participantSearchText(for header: MessageHeader) -> String {
        ([header.from] + header.to + header.cc + header.bcc)
            .flatMap { [$0.name ?? "", $0.email] }
            .joined(separator: " ")
    }

    private static func searchableBodyText(
        from rawData: Data,
        messageID: MessageHeader.ID
    ) -> String {
        let parser = IMAPMessageBodyParser()
        let rawMessage = parser.rawMessageString(from: rawData)
        let parsed = parser.parse(messageID: messageID, rawMessage: rawMessage)
        let searchableParts: [String?] = [
            parsed.plainText,
            parsed.html.map(htmlSearchText),
        ]
            + parsed.attachments.map { Optional($0.name) }
        let parsedText = searchableParts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return parsedText.isEmpty ? rawMessage : parsedText
    }

    private static func uid(from messageID: MessageHeader.ID) -> Int {
        guard let sep = messageID.lastIndex(of: ":"),
              let uid = Int(String(messageID[messageID.index(after: sep)...]))
        else { return 0 }
        return uid
    }

    private static func htmlSearchText(_ html: String) -> String {
        decodeNumericHTMLEntities(in: html)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    private static func decodeNumericHTMLEntities(in html: String) -> String {
        let pattern = #"&#([xX][0-9A-Fa-f]+|[0-9]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        var result = html
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
            guard let range = Range(match.range(at: 1), in: html),
                  let fullRange = Range(match.range, in: html)
            else { continue }
            let rawValue = String(html[range])
            let scalarValue: UInt32?
            if rawValue.lowercased().hasPrefix("x") {
                scalarValue = UInt32(rawValue.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(rawValue, radix: 10)
            }
            guard let scalarValue,
                  let scalar = UnicodeScalar(scalarValue)
            else { continue }
            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return result
    }

    private static func normalizedSearchText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "Æ", with: "ae")
            .replacingOccurrences(of: "ø", with: "o")
            .replacingOccurrences(of: "Ø", with: "o")
            .replacingOccurrences(of: "å", with: "a")
            .replacingOccurrences(of: "Å", with: "a")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
    }
}
