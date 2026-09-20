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

/// Owns the on-device data a PIM source leaves behind (ADR-0072).
///
/// Removal has two distinct cleanup steps so a retained cache can never
/// silently resume work:
///   1. Sync cursors, checkpoints and unsent editor drafts are always
///      deleted on removal — a kept cache is read-only and cannot write.
///   2. The readable cached content itself is deleted only when the user
///      chooses it; otherwise it is marked disconnected.
public protocol PIMSourceLocalDataStore: Sendable {
    /// Deletes cursors, checkpoints, staged attachments and unsent editor
    /// drafts for a source. Always performed on removal.
    func deleteSyncAndDraftData(for sourceID: PIMSource.ID) async throws
    /// Deletes the readable cached content for a source.
    func deleteCachedContent(for sourceID: PIMSource.ID) async throws
    /// Marks any retained cache as disconnected and read-only.
    func markCacheDisconnected(for sourceID: PIMSource.ID) async throws
}

/// File-backed PIMSourceLocalDataStore.
///
/// Each source owns a directory partitioned into cache, cursors and drafts
/// subdirectories. Browsing and authoring slices write into these
/// locations; the coordinator only manages their lifecycle.
public struct FilePIMSourceLocalDataStore: PIMSourceLocalDataStore {
    private let rootURL: URL

    /// - Parameter rootURL: Directory that holds one subdirectory per source.
    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    private var fileManager: FileManager { .default }

    /// Default location inside the app's Application Support directory.
    public static func defaultRootURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base
            .appendingPathComponent("Brev", isDirectory: true)
            .appendingPathComponent("PIMSources", isDirectory: true)
    }

    /// Directory that owns all local data for a source.
    public func directory(for sourceID: PIMSource.ID) -> URL {
        rootURL.appendingPathComponent(sourceID, isDirectory: true)
    }

    /// Read-only content the source may keep after disconnect.
    public func cacheDirectory(for sourceID: PIMSource.ID) -> URL {
        directory(for: sourceID).appendingPathComponent("cache", isDirectory: true)
    }

    /// Sync checkpoints and cursors; always wiped on removal.
    public func cursorDirectory(for sourceID: PIMSource.ID) -> URL {
        directory(for: sourceID).appendingPathComponent("cursors", isDirectory: true)
    }

    /// Unsent editor drafts and staged attachments; always wiped on removal.
    public func draftDirectory(for sourceID: PIMSource.ID) -> URL {
        directory(for: sourceID).appendingPathComponent("drafts", isDirectory: true)
    }

    public func deleteSyncAndDraftData(for sourceID: PIMSource.ID) async throws {
        try removeIfPresent(cursorDirectory(for: sourceID))
        try removeIfPresent(draftDirectory(for: sourceID))
        // A retained cache must not be able to submit writes: drop the
        // writable marker even when the content stays.
        try removeIfPresent(
            directory(for: sourceID).appendingPathComponent("writable")
        )
    }

    public func deleteCachedContent(for sourceID: PIMSource.ID) async throws {
        try removeIfPresent(cacheDirectory(for: sourceID))
        try removeIfPresent(
            directory(for: sourceID).appendingPathComponent("disconnected")
        )
        // Remove the source directory itself once nothing else uses it.
        let contents = try? fileManager.contentsOfDirectory(
            atPath: directory(for: sourceID).path
        )
        if contents?.isEmpty == true {
            try removeIfPresent(directory(for: sourceID))
        }
    }

    public func markCacheDisconnected(for sourceID: PIMSource.ID) async throws {
        guard fileManager.fileExists(atPath: cacheDirectory(for: sourceID).path) else {
            return
        }
        let marker = directory(for: sourceID).appendingPathComponent("disconnected")
        try Data().write(to: marker, options: .atomic)
    }

    private func removeIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
