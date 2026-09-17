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

/// One `mail/*.mbox` payload inside a `.brevbackup` package (ADR-0077
/// decision 5). `folderName` is the display name recorded at export;
/// `fileName` is the manifest payload name (`mail/<folderID>.mbox`).
public struct LocalMailBackupPayload: Sendable, Hashable {
    public let fileName: String
    public let folderName: String
    public let fileURL: URL

    public init(fileName: String, folderName: String, fileURL: URL) {
        self.fileName = fileName
        self.folderName = folderName
        self.fileURL = fileURL
    }
}

/// How local-mail payloads merge into existing local folders.
public enum LocalMailRestoreMode: Sendable {
    /// Skip messages whose Message-ID already exists in the same-named folder.
    case merge
    /// Recreate the folder wholesale.
    case replace
}

/// Result of importing `mail/` payloads into the local backend.
public struct LocalMailRestoreSummary: Sendable, Hashable {
    public var foldersRestored = 0
    public var messagesImported = 0
    public var skippedDuplicates = 0
    public var errors: [String] = []

    public init() {}
}

/// Imports `mail/*.mbox` backup payloads into a `LocalMailBackend`
/// (ADR-0077 decision 5). Kept in BrevBackend so BrevSettings' restore path
/// only needs the backend instance.
public enum LocalMailBackupImporter {
    /// Restores each payload into a same-named local folder.
    ///
    /// - Merge: reuses the existing same-named folder (creating it when
    ///   absent) and skips messages whose Message-ID is already present.
    /// - Replace: deletes the existing same-named folder first, then
    ///   recreates it.
    /// Per-payload failures are collected into `errors`; the loop continues.
    public static func restore(
        payloads: [LocalMailBackupPayload],
        into backend: LocalMailBackend,
        mode: LocalMailRestoreMode
    ) async -> LocalMailRestoreSummary {
        var summary = LocalMailRestoreSummary()
        for payload in payloads {
            do {
                try await restoreOne(payload, into: backend, mode: mode, summary: &summary)
            } catch {
                summary.errors.append(error.localizedDescription)
            }
        }
        return summary
    }

    private static func restoreOne(
        _ payload: LocalMailBackupPayload,
        into backend: LocalMailBackend,
        mode: LocalMailRestoreMode,
        summary: inout LocalMailRestoreSummary
    ) async throws {
        let existing = try await backend.folders()
        var folder = existing.first {
            $0.name.localizedCaseInsensitiveCompare(payload.folderName) == .orderedSame
        }
        if folder != nil, mode == .replace {
            try await backend.deleteFolder(id: folder!.id)
            folder = nil
        }
        if folder == nil {
            folder = try await backend.createFolder(name: payload.folderName, parentID: nil)
        }
        guard let folder else { return }

        var knownMessageIDs = Set<String>()
        if mode == .merge {
            knownMessageIDs = try await backend.storedRFCMessageIDs(in: folder.id)
        }

        var created = false
        let parseSummary = try await MBOXParser().parseBatches(contentsOf: payload.fileURL) { batch in
            let filtered = batch.filter { message in
                guard let rfcID = message.messageID else { return true }
                return knownMessageIDs.insert(rfcID).inserted
            }
            summary.skippedDuplicates += batch.count - filtered.count
            guard !filtered.isEmpty else { return }
            let result = try await backend.importMessages(filtered, into: folder)
            summary.messagesImported += result.importedCount
            summary.errors += result.errors
            created = created || result.importedCount > 0
        }
        summary.errors += parseSummary.parseErrors
        summary.foldersRestored += 1
    }
}
