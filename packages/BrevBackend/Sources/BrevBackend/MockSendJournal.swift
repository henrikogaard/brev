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
    var sender: Correspondent? = nil
    var parentMessageID: String? = nil
    var references: [String]? = nil
}

private struct MockSendJournalFile: Codable {
    let version: Int
    var records: [MockSendJournalRecord]
}

struct MockSendJournal: @unchecked Sendable {
    private static let transactionLock = NSRecursiveLock()
    private static let version = 2

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
            try Self.validate(records, accountID: accountID)
            if records != previous {
                try persistWithoutLock(records)
                let verified = try loadWithoutLock()
                guard verified == records else { throw MockSendJournalError.invalidFile }
                records = verified
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
            if fileManager.fileExists(atPath: markerURL.path) {
                try fileManager.removeItem(at: markerURL)
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

    private var markerURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("established")
    }

    private func loadWithoutLock() throws -> [MockSendJournalRecord] {
        guard directoryURL.isFileURL else { throw MockSendJournalError.invalidDirectory }
        try validateDirectoryIfPresent()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            guard !fileManager.fileExists(atPath: markerURL.path) else { throw MockSendJournalError.invalidFile }
            return []
        }
        try writeEstablishedMarkerIfNeeded()
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(MockSendJournalFile.self, from: data)
        guard decoded.version == Self.version else {
            throw MockSendJournalError.invalidFile
        }
        try Self.validate(decoded.records, accountID: accountID)
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
        try writeEstablishedMarkerIfNeeded()
        let data = try JSONEncoder().encode(MockSendJournalFile(version: Self.version, records: records))
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func writeEstablishedMarkerIfNeeded() throws {
        guard !fileManager.fileExists(atPath: markerURL.path) else { return }
        try Data([1]).write(to: markerURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: markerURL.path)
    }

    private static func validate(_ records: [MockSendJournalRecord], accountID: BrevAccount.ID) throws {
        struct SourceDraft: Hashable {
            let sourceID: MailSourceID
            let draftID: String
        }

        var identities: Set<SourceDraft> = []
        var recordIDs: Set<String> = []
        var scheduleIDs: Set<String> = []
        for record in records {
            guard record.accountID == accountID,
                  record.sourceID.accountID == accountID,
                  !record.draftID.isEmpty,
                  !record.recordID.isEmpty,
                  recordIDs.insert(record.recordID).inserted,
                  identities.insert(SourceDraft(sourceID: record.sourceID, draftID: record.draftID)).inserted,
                  record.scheduleID.map({ !$0.isEmpty && $0 != record.draftID && scheduleIDs.insert($0).inserted }) ?? true,
                  record.nextAttemptAt?.timeIntervalSince1970.isFinite ?? true else {
                throw MockSendJournalError.invalidFile
            }
            let attachmentIDs = record.attachments.map { $0.metadata.id }
            let references = record.references ?? []
            guard Set(attachmentIDs).count == attachmentIDs.count,
                  record.draft.map({ Set($0.attachmentIDs).count == $0.attachmentIDs.count }) ?? true,
                  record.attachments.allSatisfy({ $0.draftID == record.draftID }),
                  Set(attachmentIDs) == Set(record.draft?.attachmentIDs ?? []),
                  Set(references).count == references.count,
                  references.allSatisfy({ !$0.isEmpty }) else {
                throw MockSendJournalError.invalidFile
            }
            switch record.state {
            case .queued:
                guard let draft = record.draft, draft.id == record.draftID else {
                    throw MockSendJournalError.invalidFile
                }
                guard let date = record.scheduledFor,
                      date.timeIntervalSince1970.isFinite,
                      draft.scheduledFor == date,
                      record.scheduleID != nil,
                      record.sender != nil,
                      record.sentHeader == nil,
                      record.sentBody == nil else { throw MockSendJournalError.invalidFile }
            case .canceled:
                guard record.scheduledFor == nil,
                      record.scheduleID == nil,
                      record.sentHeader == nil,
                      record.sentBody == nil else { throw MockSendJournalError.invalidFile }
                if let draft = record.draft {
                    guard draft.id == record.draftID, draft.scheduledFor == nil else {
                        throw MockSendJournalError.invalidFile
                    }
                } else if !record.attachments.isEmpty {
                    throw MockSendJournalError.invalidFile
                }
            case .delivered:
                guard let draft = record.draft, draft.id == record.draftID else {
                    throw MockSendJournalError.invalidFile
                }
                guard record.scheduledFor == nil,
                      draft.scheduledFor == nil,
                      let header = record.sentHeader,
                      let body = record.sentBody,
                      !header.id.isEmpty,
                      !header.folderID.isEmpty,
                      header.id == body.messageID,
                      body.html == draft.htmlBody,
                      header.from == record.sender,
                      header.to == draft.to,
                      header.cc == draft.cc,
                      header.bcc == draft.bcc,
                      header.subject == draft.subject,
                      header.hasAttachments == !draft.attachmentIDs.isEmpty,
                      header.inReplyTo == record.parentMessageID,
                      header.references == (references.isEmpty ? nil : references),
                      body.attachments.map(\.id) == attachmentIDs else { throw MockSendJournalError.invalidFile }
            }
        }
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
