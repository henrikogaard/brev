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

/// Persistence for PIM source records (ADR-0072).
///
/// Stores records only — credential references, enabled capabilities,
/// discovery metadata and local sync choices. Secrets never pass through
/// this store; they belong exclusively to the credential store.
public protocol PIMSourceStore: Sendable {
    /// All known sources, in stable insertion order.
    func allSources() async throws -> [PIMSource]
    /// Inserts or replaces a source record.
    func save(_ source: PIMSource) async throws
    /// Removes a source record. Missing records are not an error.
    func deleteSource(id: PIMSource.ID) async throws
}

public enum PIMSourceStoreError: Error, Sendable {
    case unreadableStore
}

/// JSON-file-backed PIMSourceStore.
///
/// The whole record set is small (a handful of sources per user), so a
/// single encoded array rewritten atomically per save is sufficient and
/// keeps the format trivially inspectable for QA.
public actor JSONPIMSourceStore: PIMSourceStore {
    private let fileURL: URL
    private var cache: [PIMSource]?

    /// - Parameter fileURL: Location of the JSON record file. The parent
    ///   directory is created on first save.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Default store location inside the app's Application Support directory.
    public static func defaultFileURL(
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
            .appendingPathComponent("pim-sources.json")
    }

    public func allSources() async throws -> [PIMSource] {
        try load()
    }

    public func save(_ source: PIMSource) async throws {
        var records = try load()
        if let index = records.firstIndex(where: { $0.id == source.id }) {
            records[index] = source
        } else {
            records.append(source)
        }
        try persist(records)
        cache = records
    }

    public func deleteSource(id: PIMSource.ID) async throws {
        var records = try load()
        let count = records.count
        records.removeAll { $0.id == id }
        guard records.count != count else { return }
        try persist(records)
        cache = records
    }

    private func load() throws -> [PIMSource] {
        if let cache { return cache }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cache = []
            return []
        }
        let data = try Data(contentsOf: fileURL)
        guard let records = try? JSONDecoder.pimSourceStore.decode([PIMSource].self, from: data) else {
            throw PIMSourceStoreError.unreadableStore
        }
        cache = records
        return records
    }

    private func persist(_ records: [PIMSource]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.pimSourceStore.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static let pimSourceStore: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let pimSourceStore: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
