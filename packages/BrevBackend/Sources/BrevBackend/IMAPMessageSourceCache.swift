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

public protocol IMAPMessageSourceCache: Sendable {
    func source(accountID: BrevAccount.ID, messageID: MessageHeader.ID) async -> IMAPMessageSource?
    func setSource(_ source: IMAPMessageSource, accountID: BrevAccount.ID, messageID: MessageHeader.ID) async
    func removeSource(accountID: BrevAccount.ID, messageID: MessageHeader.ID) async
    func removeSources(inFolder folderID: Folder.ID, accountID: BrevAccount.ID) async
    /// Like `removeSources(inFolder:accountID:)` but keeps every ID in
    /// `exceptMessageIDs`. Also evicts orphan bodies (bodies whose header no
    /// longer exists) because the purge is prefix-based, not header-driven.
    func removeSources(
        inFolder folderID: Folder.ID,
        accountID: BrevAccount.ID,
        exceptMessageIDs: Set<MessageHeader.ID>
    ) async
    func sizeBytes(accountID: BrevAccount.ID) async -> Int
    func clear(accountID: BrevAccount.ID) async
}

public extension IMAPMessageSourceCache {
    /// Remove cached bodies for a batch of message IDs. Drives age-based
    /// retention pruning: the caller computes which IDs fall outside the
    /// retention window (from header dates — bodies carry no date) and
    /// hands them here. Default loops over `removeSource`; conformers may
    /// override with a bulk path.
    func removeSources(messageIDs: [MessageHeader.ID], accountID: BrevAccount.ID) async {
        for messageID in messageIDs {
            await removeSource(accountID: accountID, messageID: messageID)
        }
    }

    static func messageID(_ messageID: MessageHeader.ID, belongsToFolder folderID: Folder.ID) -> Bool {
        let prefix = "\(folderID):"
        guard messageID.hasPrefix(prefix) else { return false }
        let uidSuffix = messageID.dropFirst(prefix.count)
        return !uidSuffix.isEmpty && uidSuffix.allSatisfy(\.isNumber)
    }
}

public actor InMemoryIMAPMessageSourceCache: IMAPMessageSourceCache {
    private var sourcesByMessageByAccount: [BrevAccount.ID: [MessageHeader.ID: IMAPMessageSource]]

    public init(sourcesByMessageByAccount: [BrevAccount.ID: [MessageHeader.ID: IMAPMessageSource]] = [:]) {
        self.sourcesByMessageByAccount = sourcesByMessageByAccount
    }

    public func source(
        accountID: BrevAccount.ID,
        messageID: MessageHeader.ID
    ) -> IMAPMessageSource? {
        sourcesByMessageByAccount[accountID]?[messageID]
    }

    public func setSource(
        _ source: IMAPMessageSource,
        accountID: BrevAccount.ID,
        messageID: MessageHeader.ID
    ) {
        var sources = sourcesByMessageByAccount[accountID] ?? [:]
        sources[messageID] = source
        sourcesByMessageByAccount[accountID] = sources
    }

    public func removeSource(
        accountID: BrevAccount.ID,
        messageID: MessageHeader.ID
    ) {
        sourcesByMessageByAccount[accountID]?.removeValue(forKey: messageID)
        if sourcesByMessageByAccount[accountID]?.isEmpty == true {
            sourcesByMessageByAccount.removeValue(forKey: accountID)
        }
    }

    public func removeSources(
        inFolder folderID: Folder.ID,
        accountID: BrevAccount.ID
    ) async {
        guard var sources = sourcesByMessageByAccount[accountID] else { return }
        sources = sources.filter { messageID, _ in
            !Self.messageID(messageID, belongsToFolder: folderID)
        }
        if sources.isEmpty {
            sourcesByMessageByAccount.removeValue(forKey: accountID)
        } else {
            sourcesByMessageByAccount[accountID] = sources
        }
    }

    public func removeSources(
        inFolder folderID: Folder.ID,
        accountID: BrevAccount.ID,
        exceptMessageIDs: Set<MessageHeader.ID>
    ) async {
        guard var sources = sourcesByMessageByAccount[accountID] else { return }
        sources = sources.filter { messageID, _ in
            !Self.messageID(messageID, belongsToFolder: folderID) || exceptMessageIDs.contains(messageID)
        }
        if sources.isEmpty {
            sourcesByMessageByAccount.removeValue(forKey: accountID)
        } else {
            sourcesByMessageByAccount[accountID] = sources
        }
    }

    public func sizeBytes(accountID: BrevAccount.ID) -> Int {
        sourcesByMessageByAccount[accountID, default: [:]]
            .values
            .reduce(0) { total, source in
                total + (source.rawMessageData?.count ?? source.rawMessage.utf8.count)
            }
    }

    public func clear(accountID: BrevAccount.ID) {
        sourcesByMessageByAccount.removeValue(forKey: accountID)
    }
}

public actor FileIMAPMessageSourceCache: IMAPMessageSourceCache {
    private let rootDirectory: URL
    private let maximumAccountSizeBytes: Int?
    private var knownSizeBytesByAccountID: [BrevAccount.ID: Int] = [:]

    public init(
        rootDirectory: URL,
        maximumAccountSizeBytes: Int? = nil
    ) {
        self.rootDirectory = rootDirectory
        self.maximumAccountSizeBytes = maximumAccountSizeBytes
    }

    public func source(
        accountID: BrevAccount.ID,
        messageID: MessageHeader.ID
    ) -> IMAPMessageSource? {
        let url = sourceURL(accountID: accountID, messageID: messageID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(IMAPMessageSource.self, from: data)
    }

    public func setSource(
        _ source: IMAPMessageSource,
        accountID: BrevAccount.ID,
        messageID: MessageHeader.ID
    ) {
        let directory = accountDirectory(accountID: accountID)
        let url = sourceURL(accountID: accountID, messageID: messageID)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(source)
            let replacedFileSize = Self.fileSize(at: url)
            try data.write(to: url, options: .atomic)
            pruneAccountDirectoryIfNeeded(
                directory,
                accountID: accountID,
                replacedFileSize: replacedFileSize,
                newFileSize: data.count
            )
        } catch {
            return
        }
    }

    public func removeSource(
        accountID: BrevAccount.ID,
        messageID: MessageHeader.ID
    ) {
        let url = sourceURL(accountID: accountID, messageID: messageID)
        let removedFileSize = Self.fileSize(at: url)
        guard (try? FileManager.default.removeItem(at: url)) != nil else { return }
        if let knownSize = knownSizeBytesByAccountID[accountID] {
            knownSizeBytesByAccountID[accountID] = max(0, knownSize - removedFileSize)
        }
    }

    public func removeSources(
        inFolder folderID: Folder.ID,
        accountID: BrevAccount.ID
    ) async {
        knownSizeBytesByAccountID[accountID] = nil
        let directory = accountDirectory(accountID: accountID)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else {
            return
        }
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  url.pathExtension == "json",
                  let messageID = Self.messageID(fromFileKey: url.deletingPathExtension().lastPathComponent),
                  Self.messageID(messageID, belongsToFolder: folderID)
            else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func removeSources(
        inFolder folderID: Folder.ID,
        accountID: BrevAccount.ID,
        exceptMessageIDs: Set<MessageHeader.ID>
    ) async {
        knownSizeBytesByAccountID[accountID] = nil
        let directory = accountDirectory(accountID: accountID)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else {
            return
        }
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  url.pathExtension == "json",
                  let messageID = Self.messageID(fromFileKey: url.deletingPathExtension().lastPathComponent),
                  Self.messageID(messageID, belongsToFolder: folderID),
                  !exceptMessageIDs.contains(messageID)
            else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    public nonisolated func sizeBytes(accountID: BrevAccount.ID) -> Int {
        let directory = accountDirectory(accountID: accountID)
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else {
            return 0
        }

        return enumerator.reduce(0) { partialResult, entry in
            guard let url = entry as? URL,
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true
            else {
                return partialResult
            }
            return partialResult + (values.fileSize ?? 0)
        }
    }

    public func clear(accountID: BrevAccount.ID) {
        knownSizeBytesByAccountID[accountID] = nil
        let directory = accountDirectory(accountID: accountID)
        try? FileManager.default.removeItem(at: directory)
    }

    private func sourceURL(
        accountID: BrevAccount.ID,
        messageID: MessageHeader.ID
    ) -> URL {
        accountDirectory(accountID: accountID)
            .appendingPathComponent("\(Self.fileKey(messageID)).json", isDirectory: false)
    }

    private nonisolated func accountDirectory(accountID: BrevAccount.ID) -> URL {
        rootDirectory.appendingPathComponent(Self.fileKey(accountID), isDirectory: true)
    }

    private func pruneAccountDirectoryIfNeeded(
        _ directory: URL,
        accountID: BrevAccount.ID,
        replacedFileSize: Int,
        newFileSize: Int
    ) {
        guard let maximumAccountSizeBytes,
              maximumAccountSizeBytes > 0
        else {
            return
        }

        if let knownSize = knownSizeBytesByAccountID[accountID] {
            let projectedSize = max(0, knownSize - replacedFileSize) + newFileSize
            guard projectedSize > maximumAccountSizeBytes else {
                knownSizeBytesByAccountID[accountID] = projectedSize
                return
            }
        }

        var entries = sourceFileEntries(in: directory)
        var totalBytes = entries.reduce(0) { $0 + $1.sizeBytes }
        while totalBytes > maximumAccountSizeBytes, entries.count > 1 {
            let removed = entries.removeFirst()
            try? FileManager.default.removeItem(at: removed.url)
            totalBytes -= removed.sizeBytes
        }
        knownSizeBytesByAccountID[accountID] = totalBytes
    }

    private func sourceFileEntries(in directory: URL) -> [SourceFileEntry] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey
            ]
        ) else {
            return []
        }
        return urls.compactMap { url -> SourceFileEntry? in
            guard let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey
            ]),
                values.isRegularFile == true,
                let sizeBytes = values.fileSize
            else {
                return nil
            }
            return SourceFileEntry(
                url: url,
                modifiedAt: values.contentModificationDate ?? .distantPast,
                sizeBytes: sizeBytes
            )
        }
        .sorted { lhs, rhs in
            if lhs.modifiedAt == rhs.modifiedAt {
                return lhs.url.lastPathComponent < rhs.url.lastPathComponent
            }
            return lhs.modifiedAt < rhs.modifiedAt
        }
    }

    private static func fileKey(_ value: String) -> String {
        guard !value.isEmpty else { return "_" }
        return value.utf8.map { String(format: "%02x", $0) }.joined()
    }

    private static func fileSize(at url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private static func messageID(fromFileKey fileKey: String) -> MessageHeader.ID? {
        guard fileKey.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(fileKey.count / 2)
        var index = fileKey.startIndex
        while index < fileKey.endIndex {
            let next = fileKey.index(index, offsetBy: 2)
            guard let byte = UInt8(fileKey[index ..< next], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = next
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    private struct SourceFileEntry {
        let url: URL
        let modifiedAt: Date
        let sizeBytes: Int
    }
}
