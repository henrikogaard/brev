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

enum MockSendJournalState: String, Codable, Sendable {
    case queued
    case canceled
    case delivered
}

struct MockSendJournalAttachment: Codable, Sendable, Equatable {
    let metadata: Attachment
    let data: Data
    let draftID: String
}

struct MockSendJournalRecord: Codable, Sendable, Equatable {
    let recordID: String
    let accountID: BrevAccount.ID
    let sourceID: MailSourceID
    let draftID: String
    var scheduleID: String?
    var draft: Draft?
    var attachments: [MockSendJournalAttachment]
    var state: MockSendJournalState
    var scheduledFor: Date?
    var sentHeader: MessageHeader?
    var sentBody: MessageBody?
    var nextAttemptAt: Date?
}

private struct MockSendJournalFile: Codable {
    let version: Int
    var records: [MockSendJournalRecord]
}

struct MockSendJournal: @unchecked Sendable {
    private static let transactionLock = NSRecursiveLock()
    private static let version = 1

    let directoryURL: URL
    let accountID: BrevAccount.ID
    private let fileManager = FileManager.default

    init(directoryURL: URL, accountID: BrevAccount.ID) {
        self.directoryURL = directoryURL
        self.accountID = accountID
    }

    func load() throws -> [MockSendJournalRecord] {
        try Self.transactionLock.withLock {
            try loadWithoutLock()
        }
    }

    func transact<T>(
        _ operation: (inout [MockSendJournalRecord]) throws -> T
    ) throws -> (value: T, records: [MockSendJournalRecord]) {
        try Self.transactionLock.withLock {
            var records = try loadWithoutLock()
            let previous = records
            let value = try operation(&records)
            if records != previous {
                try persistWithoutLock(records)
            }
            return (value, records)
        }
    }

    func purge() throws {
        try Self.transactionLock.withLock {
            try validateDirectoryIfPresent()
            let url = fileURL
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    var fileURL: URL {
        let encodedAccount = Data(accountID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return directoryURL.appendingPathComponent("account-\(encodedAccount).mock-sends.json")
    }

    private func loadWithoutLock() throws -> [MockSendJournalRecord] {
        guard directoryURL.isFileURL else { throw MockSendJournalError.invalidDirectory }
        try validateDirectoryIfPresent()
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(MockSendJournalFile.self, from: data)
        guard decoded.version == Self.version,
              decoded.records.allSatisfy({ $0.accountID == accountID && $0.sourceID.accountID == accountID }) else {
            throw MockSendJournalError.invalidFile
        }
        return decoded.records
    }

    private func validateDirectoryIfPresent() throws {
        guard directoryURL.isFileURL else { throw MockSendJournalError.invalidDirectory }
        if fileManager.fileExists(atPath: directoryURL.path) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw MockSendJournalError.invalidDirectory
            }
        }
    }

    private func persistWithoutLock(_ records: [MockSendJournalRecord]) throws {
        guard directoryURL.isFileURL else { throw MockSendJournalError.invalidDirectory }
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        let data = try JSONEncoder().encode(MockSendJournalFile(version: Self.version, records: records))
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

enum MockSendJournalError: Error {
    case invalidDirectory
    case invalidFile
}

final class MockScheduledSendSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [PendingScheduledSend] = []

    func read() -> [PendingScheduledSend] {
        lock.withLock { entries }
    }

    func replace(with entries: [PendingScheduledSend]) {
        lock.withLock { self.entries = entries }
    }
}
