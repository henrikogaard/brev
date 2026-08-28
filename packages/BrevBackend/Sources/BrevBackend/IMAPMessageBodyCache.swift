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

import Foundation

public protocol IMAPMessageBodyCache: Sendable {
    func body(accountID: BrevAccount.ID, messageID: MessageHeader.ID) async -> MessageBody?
    func setBody(_ body: MessageBody, accountID: BrevAccount.ID, messageID: MessageHeader.ID) async
    func removeBody(accountID: BrevAccount.ID, messageID: MessageHeader.ID) async
    func removeBodies(inFolder folderID: Folder.ID, accountID: BrevAccount.ID) async
    func removeBodies(
        inFolder folderID: Folder.ID,
        accountID: BrevAccount.ID,
        exceptMessageIDs: Set<MessageHeader.ID>
    ) async
    func sizeBytes(accountID: BrevAccount.ID) async -> Int
    func clear(accountID: BrevAccount.ID) async
}

public extension IMAPMessageBodyCache {
    func removeBodies(messageIDs: [MessageHeader.ID], accountID: BrevAccount.ID) async {
        for messageID in messageIDs {
            await removeBody(accountID: accountID, messageID: messageID)
        }
    }

    static func messageID(_ messageID: MessageHeader.ID, belongsToFolder folderID: Folder.ID) -> Bool {
        let prefix = "\(folderID):"
        guard messageID.hasPrefix(prefix) else { return false }
        let uidSuffix = messageID.dropFirst(prefix.count)
        return !uidSuffix.isEmpty && uidSuffix.allSatisfy(\.isNumber)
    }
}

public actor InMemoryIMAPMessageBodyCache: IMAPMessageBodyCache {
    private var bodiesByMessageByAccount: [BrevAccount.ID: [MessageHeader.ID: MessageBody]] = [:]

    public init() {}

    public func body(accountID: BrevAccount.ID, messageID: MessageHeader.ID) -> MessageBody? {
        bodiesByMessageByAccount[accountID]?[messageID]
    }

    public func setBody(
        _ body: MessageBody,
        accountID: BrevAccount.ID,
        messageID: MessageHeader.ID
    ) {
        bodiesByMessageByAccount[accountID, default: [:]][messageID] = body
    }

    public func removeBody(accountID: BrevAccount.ID, messageID: MessageHeader.ID) {
        bodiesByMessageByAccount[accountID]?.removeValue(forKey: messageID)
    }

    public func removeBodies(inFolder folderID: Folder.ID, accountID: BrevAccount.ID) {
        bodiesByMessageByAccount[accountID] = bodiesByMessageByAccount[accountID]?.filter {
            !Self.messageID($0.key, belongsToFolder: folderID)
        }
    }

    public func removeBodies(
        inFolder folderID: Folder.ID,
        accountID: BrevAccount.ID,
        exceptMessageIDs: Set<MessageHeader.ID>
    ) {
        bodiesByMessageByAccount[accountID] = bodiesByMessageByAccount[accountID]?.filter {
            !Self.messageID($0.key, belongsToFolder: folderID) || exceptMessageIDs.contains($0.key)
        }
    }

    public func clear(accountID: BrevAccount.ID) {
        bodiesByMessageByAccount.removeValue(forKey: accountID)
    }

    public func sizeBytes(accountID: BrevAccount.ID) -> Int {
        let encoder = JSONEncoder()
        return bodiesByMessageByAccount[accountID, default: [:]].values.reduce(0) {
            $0 + ((try? encoder.encode($1).count) ?? 0)
        }
    }
}

public actor FileIMAPMessageBodyCache: IMAPMessageBodyCache {
    private let rootDirectory: URL
    private let maximumAccountSizeBytes: Int?
    private var knownSizeBytesByAccountID: [BrevAccount.ID: Int] = [:]

    public init(rootDirectory: URL, maximumAccountSizeBytes: Int? = nil) {
        self.rootDirectory = rootDirectory
        self.maximumAccountSizeBytes = maximumAccountSizeBytes
    }

    public func body(accountID: BrevAccount.ID, messageID: MessageHeader.ID) -> MessageBody? {
        guard let data = try? Data(contentsOf: bodyURL(accountID: accountID, messageID: messageID)) else {
            return nil
        }
        return try? JSONDecoder().decode(MessageBody.self, from: data)
    }

    public func setBody(
        _ body: MessageBody,
        accountID: BrevAccount.ID,
        messageID: MessageHeader.ID
    ) {
        let directory = accountDirectory(accountID: accountID)
        let url = bodyURL(accountID: accountID, messageID: messageID)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(body)
            let replacedFileSize = Self.fileSize(at: url)
            try data.write(
                to: url,
                options: .atomic
            )
            prune(
                directory,
                accountID: accountID,
                replacedFileSize: replacedFileSize,
                newFileSize: data.count
            )
        } catch {
            return
        }
    }

    public func removeBody(accountID: BrevAccount.ID, messageID: MessageHeader.ID) {
        let url = bodyURL(accountID: accountID, messageID: messageID)
        let removedFileSize = Self.fileSize(at: url)
        guard (try? FileManager.default.removeItem(at: url)) != nil else { return }
        if let knownSize = knownSizeBytesByAccountID[accountID] {
            knownSizeBytesByAccountID[accountID] = max(0, knownSize - removedFileSize)
        }
    }

    public func removeBodies(inFolder folderID: Folder.ID, accountID: BrevAccount.ID) async {
        await removeBodies(inFolder: folderID, accountID: accountID, exceptMessageIDs: [])
    }

    public func removeBodies(
        inFolder folderID: Folder.ID,
        accountID: BrevAccount.ID,
        exceptMessageIDs: Set<MessageHeader.ID>
    ) async {
        knownSizeBytesByAccountID[accountID] = nil
        let directory = accountDirectory(accountID: accountID)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for url in urls {
            guard url.pathExtension == "json",
                  let messageID = Self.value(fromFileKey: url.deletingPathExtension().lastPathComponent),
                  Self.messageID(messageID, belongsToFolder: folderID),
                  !exceptMessageIDs.contains(messageID)
            else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func clear(accountID: BrevAccount.ID) {
        knownSizeBytesByAccountID[accountID] = nil
        try? FileManager.default.removeItem(at: accountDirectory(accountID: accountID))
    }

    public nonisolated func sizeBytes(accountID: BrevAccount.ID) -> Int {
        let directory = accountDirectory(accountID: accountID)
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return enumerator.reduce(0) { total, entry in
            guard let url = entry as? URL,
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            else { return total }
            return total + size
        }
    }

    private func bodyURL(accountID: BrevAccount.ID, messageID: MessageHeader.ID) -> URL {
        accountDirectory(accountID: accountID)
            .appendingPathComponent("\(Self.fileKey(messageID)).json", isDirectory: false)
    }

    private nonisolated func accountDirectory(accountID: BrevAccount.ID) -> URL {
        rootDirectory.appendingPathComponent(Self.fileKey(accountID), isDirectory: true)
    }

    private func prune(
        _ directory: URL,
        accountID: BrevAccount.ID,
        replacedFileSize: Int,
        newFileSize: Int
    ) {
        guard let maximumAccountSizeBytes, maximumAccountSizeBytes > 0
        else { return }

        if let knownSize = knownSizeBytesByAccountID[accountID] {
            let projectedSize = max(0, knownSize - replacedFileSize) + newFileSize
            guard projectedSize > maximumAccountSizeBytes else {
                knownSizeBytesByAccountID[accountID] = projectedSize
                return
            }
        }

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }
        var entries = urls.compactMap { url -> (URL, Date, Int)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let size = values.fileSize
            else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, size)
        }.sorted { $0.1 < $1.1 }
        var total = entries.reduce(0) { $0 + $1.2 }
        while total > maximumAccountSizeBytes, entries.count > 1 {
            let entry = entries.removeFirst()
            try? FileManager.default.removeItem(at: entry.0)
            total -= entry.2
        }
        knownSizeBytesByAccountID[accountID] = total
    }

    private static func fileKey(_ value: String) -> String {
        value.isEmpty ? "_" : value.utf8.map { String(format: "%02x", $0) }.joined()
    }

    private static func fileSize(at url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private static func value(fromFileKey key: String) -> String? {
        guard key.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = key.startIndex
        while index < key.endIndex {
            let next = key.index(index, offsetBy: 2)
            guard let byte = UInt8(key[index ..< next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return String(bytes: bytes, encoding: .utf8)
    }
}

/// Persistent structured-body cache used by the standard connector.
public actor FileBackedIMAPMessageBodyCache: IMAPMessageBodyCache {
    public static let defaultMaximumAccountSizeBytes = 20 * 1024 * 1024
    private let inner: FileIMAPMessageBodyCache

    public init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Brev/BodyCache", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        inner = FileIMAPMessageBodyCache(
            rootDirectory: base,
            maximumAccountSizeBytes: Self.defaultMaximumAccountSizeBytes
        )
    }

    public func body(accountID: BrevAccount.ID, messageID: MessageHeader.ID) async -> MessageBody? {
        await inner.body(accountID: accountID, messageID: messageID)
    }

    public func setBody(_ body: MessageBody, accountID: BrevAccount.ID, messageID: MessageHeader.ID) async {
        await inner.setBody(body, accountID: accountID, messageID: messageID)
    }

    public func removeBody(accountID: BrevAccount.ID, messageID: MessageHeader.ID) async {
        await inner.removeBody(accountID: accountID, messageID: messageID)
    }

    public func removeBodies(inFolder folderID: Folder.ID, accountID: BrevAccount.ID) async {
        await inner.removeBodies(inFolder: folderID, accountID: accountID)
    }

    public func removeBodies(
        inFolder folderID: Folder.ID,
        accountID: BrevAccount.ID,
        exceptMessageIDs: Set<MessageHeader.ID>
    ) async {
        await inner.removeBodies(
            inFolder: folderID,
            accountID: accountID,
            exceptMessageIDs: exceptMessageIDs
        )
    }

    public func clear(accountID: BrevAccount.ID) async {
        await inner.clear(accountID: accountID)
    }

    public nonisolated func sizeBytes(accountID: BrevAccount.ID) async -> Int {
        inner.sizeBytes(accountID: accountID)
    }
}
